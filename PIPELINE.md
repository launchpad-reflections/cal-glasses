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
   ├── Frames captured at 1fps (from 24fps glasses stream)
   ├── Audio transcribed in real-time by Moonshine v2
   └── Transcript fed into recording buffer
         │
         ▼
4. TTS: "Tracking complete. Analyzing."
         │
         ▼
5. Frame deduplication (perceptual hashing)
   Input: ~10 raw frames
   Output: 5-8 unique frames
         │
         ▼
6. Gemini API call
   Input: unique frames (base64 JPEG) + transcript text
   Output: structured JSON with food items
         │
         ▼
7. Results displayed with photos, portions, calories
   TTS reads back: "Found 2 items: Doritos, water"
```

## Component Details

### 1. Voice Trigger (`PipelineCoordinator.swift`)

The Moonshine transcriber runs continuously during streaming. Every transcript update is checked for the phrase "log food" (also matches "lock food" for misrecognition).

When triggered:
- Sets `foodLoggingTriggered = true` (observed by the view)
- Starts a 15-second cooldown to prevent re-triggering during recording

### 2. Recording Buffer (`FoodRecordingBuffer.swift`)

During the 10-second window:

**Frames:** The glasses stream at 24fps, but we only keep 1 frame per second (throttled by timestamp comparison). This gives ~10 frames for a 10-second window.

**Transcript:** Every time `PipelineCoordinator.transcriptText` updates, the new text is fed into the buffer. Moonshine updates the current line in-place (each update replaces the previous partial), so we track the latest version and append when a new line starts.

### 3. Frame Deduplication (`FrameDeduplicator.swift`)

Takes ~10 frames and reduces to 5-8 unique ones.

**Algorithm:**
1. **Perceptual hash (pHash):** Each frame is resized to 8x8 grayscale. Each pixel is compared to the mean — above = 1, below = 0 — producing a 64-bit fingerprint.
2. **Grouping:** Frames with hamming distance < 12 bits are considered "same scene" and grouped together.
3. **Sharpness selection:** From each group, the sharpest frame is kept. Sharpness is measured by Laplacian variance (high-frequency content = sharper).
4. **Cap at 8:** Top 8 sharpest unique frames are sent to Gemini.

**Why this matters:** If you stare at a Doritos bag for 5 seconds, you get 1 frame of Doritos instead of 5 near-identical frames. This saves Gemini tokens and improves response quality.

### 4. Gemini API Call (`GeminiService.swift`)

**Model:** `gemini-2.5-flash` (Google's latest flash model, free tier compatible)

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
      {"inline_data": {"mime_type": "image/jpeg", "data": "<base64 frame 0>"}},
      {"inline_data": {"mime_type": "image/jpeg", "data": "<base64 frame 1>"}},
      ...
    ]
  }],
  "generationConfig": {
    "temperature": 0.1,
    "responseMimeType": "application/json"
  }
}
```

Images are JPEG at 80% quality, typically 80-100KB each. Total payload for 8 images ≈ 800KB of base64.

**The `responseMimeType: "application/json"` forces Gemini to return valid JSON** — no markdown fences, no explanation, just the data.

### 5. Gemini Prompt

The prompt tells Gemini:

1. **Context:** "You receive N images from a recording of someone's meal, captured through smart glasses. Images are numbered 0 to N-1."

2. **Instructions:**
   - Identify all food/drink visible
   - Cross-reference with transcript (e.g., "I had 30 chips" + Doritos bag → calculate servings)
   - Detect nutrition labels and read them
   - Estimate calories
   - Pick the best image for each item (prefer nutrition label side)
   - Don't duplicate items across frames

3. **Transcript:** The actual words spoken during the 10-second window. If empty: "(no speech detected)"

4. **Output schema:** Strict JSON with these fields per item:
   - `name` — specific brand/food name
   - `type` — "packaged" / "dish" / "drink"
   - `quantity` — human-readable (e.g., "2 servings", "1 plate")
   - `portions` — numeric (default 1.0, derived from transcript)
   - `calories` — estimated total for amount consumed
   - `quantity_ml` — for drinks only
   - `has_nutrition_label` — whether a label was visible
   - `needs_manual_entry` — whether the user should verify
   - `confidence` — 0.0 to 1.0
   - `best_image_index` — which frame best shows this item
   - `nutrition_summary` — brief facts if label visible (e.g., "140cal, 8g fat per serving")

### 6. Response Parsing (`FoodAnalysisResult.swift`)

Gemini returns JSON like:
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
      "best_image_index": 3,
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

This is decoded into `FoodAnalysisResult` → `[FoodItem]`. Then `attachImages(from:)` maps each `best_image_index` to the actual `UIImage` from the deduped frames.

### 7. UI Display (`CalGlassesView.swift`)

**Results list:** Each food item shows as a tappable card with thumbnail, name, quantity, portions, calories.

**Detail view:** Tapping a card opens a full sheet with:
- Full-size photo from the glasses
- Name, type, quantity, portions, calories
- Confidence score
- Nutrition label detection status
- Full nutrition summary (if label was read)

## Audio Path

The glasses microphone streams at 8kHz via HFP Bluetooth. `GlassesAudioCapture` resamples to 16kHz mono and feeds to:
1. **SileroVAD** — voice activity detection (speech probability)
2. **MoonshineTranscriber** — on-device speech-to-text

The transcript is published to `PipelineCoordinator.transcriptText`, which the view observes and feeds into `FoodRecordingBuffer.addTranscript()` during recording.

## API Key

The Gemini API key is hardcoded in `GeminiService.swift` for development. For production, move to a gitignored config file or keychain.
