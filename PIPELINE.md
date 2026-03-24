# Cal Reflections — Food Logging Pipeline

## Overview

Cal Reflections uses Meta Ray-Ban glasses to capture what you see and say, then sends that data to Google's Gemini AI to identify food items, read nutrition labels, estimate portions, and return structured calorie data.

## End-to-End Flow

```
1. User says "log food" (or taps button)
         │
         ▼
2. TTS: "Tracking started" → plays through glasses speakers
         │
         ▼
3. 10-second recording window begins
   ├── High-quality photos captured every 3s via capturePhoto()
   ├── Stream frames captured at 1fps (fallback)
   ├── Audio transcribed in real-time by Moonshine v2
   └── Transcript fed into recording buffer
         │
         ▼
4. TTS: "Tracking complete. Analyzing."
         │
         ▼
5. Image selection:
   ├── If photos captured → use those (~4 high-quality JPEGs)
   └── If no photos → fallback to deduplicated stream frames
         │
         ▼
6. Gemini API call (single HTTPS POST)
   Input: images (base64 JPEG @ 92%) + transcript text
   Output: structured JSON with food items
         │
         ▼
7. Results displayed with photos, portions, calories
   TTS reads back: "Found 2 items: Doritos, water"
```

## Two Image Pipelines

### Pipeline A: Photo Capture (Primary — Higher Quality)

The MWDAT SDK has two separate image paths from the glasses:

1. **Video stream** (`videoFramePublisher`): 24fps at 720x1280, compressed to ~500kbps over Bluetooth. Optimized for low-latency live preview. Every frame is degraded.

2. **Photo capture** (`photoDataPublisher`): A dedicated still photo request to the glasses hardware. The glasses use their camera sensor to take a full JPEG photo and send it back. This is NOT pulled from the video stream — it's a distinct capture event with better quality.

During the 10-second recording window:
- `capturePhoto(format: .jpeg)` fires at **0s, 3s, 6s, 9s** → ~4 photos
- Each photo arrives via `photoDataPublisher` as raw JPEG `Data`
- Converted to `UIImage` and stored in `capturedPhotos` array

### Pipeline B: Stream Frame Capture (Fallback — Lower Quality)

If photo capture fails (e.g., glasses don't support it, timing issues):
- The `videoFramePublisher` delivers frames at 24fps
- `FoodRecordingBuffer` samples 1 frame per second → ~10 frames
- `FrameDeduplicator` reduces to 5-8 unique frames using perceptual hashing
- These lower-quality frames are sent to Gemini instead

### Selection Logic

```swift
if !capturedPhotos.isEmpty {
    // Use high-quality photos
    imagesToAnalyze = capturedPhotos
} else {
    // Fallback to deduplicated stream frames
    imagesToAnalyze = FrameDeduplicator.deduplicate(recording.frames)
}
```

## Component Details

### 1. Voice Trigger (`PipelineCoordinator.swift`)

The Moonshine transcriber runs continuously during streaming. Every transcript update is checked for the phrase "log food" (also matches "lock food" for misrecognition).

When triggered:
- Sets `foodLoggingTriggered = true` (observed by the view)
- Starts a 15-second cooldown to prevent re-triggering during recording

### 2. Audio Transcription

**Capture path:** Glasses mic (8kHz HFP Bluetooth) → `GlassesAudioCapture` resamples to 16kHz mono → `PipelineCoordinator.processAudio()` → `SileroVAD` (voice activity detection) + `MoonshineTranscriber` (speech-to-text)

**During recording:** Every time `PipelineCoordinator.transcriptText` updates (from Moonshine), the `CalStreamView` observes the change via `.onChange` and calls `streamVM.feedTranscript(text)` which stores it in `FoodRecordingBuffer`.

**Transcript handling:** Moonshine updates the current line in-place (each update replaces the previous partial). The buffer tracks the latest version and appends finalized lines. When recording stops, the full accumulated transcript is included in the Gemini request.

### 3. Frame Deduplication (`FrameDeduplicator.swift`) — Fallback Only

Used only when photo capture fails. Takes ~10 stream frames and reduces to 5-8 unique ones.

**Algorithm:**
1. **Perceptual hash (pHash):** Each frame → 8x8 grayscale → compare each pixel to mean → 64-bit fingerprint
2. **Grouping:** Frames with hamming distance < 12 bits are "same scene"
3. **Sharpness selection:** From each group, keep the sharpest (Laplacian variance)
4. **Cap at 8** sharpest unique frames

### 4. Gemini API Call (`GeminiService.swift`)

**Model:** `gemini-2.5-flash`

**Endpoint:**
```
POST https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=API_KEY
```

**Request body:**
```json
{
  "contents": [{
    "parts": [
      {"text": "<system prompt with transcript>"},
      {"inline_data": {"mime_type": "image/jpeg", "data": "<base64 photo 0>"}},
      {"inline_data": {"mime_type": "image/jpeg", "data": "<base64 photo 1>"}},
      {"inline_data": {"mime_type": "image/jpeg", "data": "<base64 photo 2>"}},
      {"inline_data": {"mime_type": "image/jpeg", "data": "<base64 photo 3>"}}
    ]
  }],
  "generationConfig": {
    "temperature": 0.1,
    "responseMimeType": "application/json"
  }
}
```

Images are JPEG at **92% quality**. The `responseMimeType: "application/json"` forces Gemini to return valid JSON — no markdown, no explanation.

### 5. Gemini Prompt

The prompt tells Gemini:

- **Context:** "You receive N images from a recording of someone's meal, captured through smart glasses. Images are numbered 0 to N-1."
- **Instructions:**
  - Identify all food/drink visible with specific brand names
  - Cross-reference with transcript (e.g., "I had 30 chips" + Doritos bag → 2 servings)
  - Detect nutrition labels and read them — summarize key facts
  - Estimate calories for total amount consumed
  - Pick the best image for each item (prefer nutrition label side)
  - Don't duplicate items across frames
  - Default portions to 1.0, override from transcript
- **Transcript:** The actual words spoken during the 10 seconds. If empty: "(no speech detected)"

### 6. Output Schema

Each food item in the response:

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Specific brand/food name (e.g., "Doritos Nacho Cheese") |
| `type` | string | "packaged" / "dish" / "drink" |
| `quantity` | string | Human-readable (e.g., "2 servings", "1 plate") |
| `portions` | number | Numeric portions consumed (default 1.0, from transcript) |
| `calories` | number? | Estimated total calories for amount consumed |
| `quantity_ml` | number? | For drinks only, in milliliters |
| `has_nutrition_label` | bool | Whether a label was visible in the images |
| `needs_manual_entry` | bool | Whether the user should verify |
| `confidence` | number | 0.0 to 1.0 |
| `best_image_index` | number? | Which image best shows this item (0-indexed) |
| `nutrition_summary` | string? | Brief facts if label visible (e.g., "140cal, 8g fat per serving") |

### 7. Example Response

```json
{
  "items": [
    {
      "name": "Doritos Nacho Cheese",
      "type": "packaged",
      "quantity": "about 30 chips (2 servings)",
      "portions": 2.0,
      "calories": 280,
      "quantity_ml": null,
      "has_nutrition_label": true,
      "needs_manual_entry": false,
      "confidence": 0.9,
      "best_image_index": 2,
      "nutrition_summary": "140cal, 8g fat, 17g carbs, 2g protein per serving"
    },
    {
      "name": "Water",
      "type": "drink",
      "quantity": "1 glass",
      "portions": 1.0,
      "calories": 0,
      "quantity_ml": 250,
      "has_nutrition_label": false,
      "needs_manual_entry": false,
      "confidence": 0.7,
      "best_image_index": null,
      "nutrition_summary": null
    }
  ]
}
```

### 8. UI Display (`CalGlassesView.swift`)

**Results list:** Each food item shows as a tappable card with thumbnail (from `best_image_index`), name, quantity, portions, calories, and confidence.

**Detail view (tap to expand):** Full sheet with:
- Full-size photo from the glasses
- Name, type icon, quantity, portions, calories, volume
- Confidence score
- Nutrition label detection status
- Full nutrition summary if label was read

### 9. TTS Feedback

Throughout the flow, `GlassesSpeaker` (using `AVSpeechSynthesizer` routed through HFP Bluetooth) provides audio feedback through the glasses speakers:
- "Ready. Say log food to start tracking."
- "Tracking started"
- "Tracking complete. Analyzing."
- "Found N items: [item names]" or "No food detected."

## Architecture Summary

```
Meta Glasses Hardware
├── Camera sensor
│   ├── Video stream (24fps, 720x1280, Bluetooth) → live display on phone
│   └── Photo capture (on-demand JPEG, higher quality) → food analysis
└── Microphone (HFP 8kHz)
    └── Resampled to 16kHz → SileroVAD + MoonshineTranscriber

iPhone Processing
├── Live display: stream frames → SwiftUI Image view
├── Transcription: audio → Moonshine v2 → text (continuous)
├── Voice trigger: transcript → keyword match "log food"
└── Food logging (10-second window):
    ├── Photos: capturePhoto() at 0s, 3s, 6s, 9s → ~4 JPEGs
    ├── Transcript: accumulated during window
    └── → Gemini 2.5 Flash API → structured JSON → UI results
```
