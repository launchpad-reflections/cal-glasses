# Cal Reflections — Smart Calorie Logging via Meta Ray-Ban Glasses

## Vision

Cal Reflections turns Meta Ray-Ban glasses into a hands-free calorie logging device. Instead of manually photographing every meal and typing into an app, you just look at your food, say what you're eating, and the system handles the rest — identifying food, reading nutrition labels, estimating portions, and logging everything into Cal AI automatically.

## How It Works

### User Flow

1. **Start streaming** from the glasses tab in the app
2. **Activate "detect food" mode** — either say "log food" or make a hand gesture
3. **For the next ~30 seconds**, the system records what you see and say:
   - **Option A: Nutrition labels** — Look at the label/ingredient info and say how much you're having (e.g., "I had 30 chips" while looking at a Doritos bag)
   - **Option B: Plated food** — Just look at your dish if there's no label
   - **Option C: Water** — Say "I drank a glass of water"
4. **AI pipeline processes the recording** — combining visual frames + audio transcript to understand what and how much you consumed
5. **Results are logged into Cal AI** — the system fills in the Cal AI app with the right data

### AI Pipeline (30-Second Clip Processing)

```
┌──────────────────────────────────────────────────────────┐
│              30-Second Recording Window                    │
│                                                            │
│  Glasses Camera (720p @ 24fps) ──► Video frames           │
│  Glasses Mic (HFP 8kHz→16kHz) ──► Audio / transcript      │
└──────────────────────────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────┐
│              Frame + Audio Analysis                        │
│                                                            │
│  1. Deduplicate frames — extract unique food images:       │
│     - Nutrition labels (prefer the side with more info)    │
│     - Plated dishes                                        │
│     - Drinks / beverages                                   │
│     No duplicates (e.g., front + back of same package      │
│     → keep only the nutrition facts side)                  │
│                                                            │
│  2. Combine visual + audio cues:                           │
│     - "I had 30 chips" + Doritos bag in frame              │
│       → calculate servings from label                      │
│     - "Half a plate of pasta" + dish in frame              │
│       → estimate calories from visual                      │
│     - "Two glasses of water"                               │
│       → log water intake                                   │
│                                                            │
│  3. Categorize each item:                                  │
│     - LABELED: has nutrition info visible → extract values  │
│     - DISH: no label, visual estimation needed              │
│     - WATER: hydration tracking                             │
└──────────────────────────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────┐
│              Cal AI Integration                            │
│                                                            │
│  For LABELED items:                                        │
│    → Upload nutrition label photo to Cal AI                 │
│    → Verify/adjust detected values (servings, calories)    │
│    → Correct any misreads in the app UI                    │
│                                                            │
│  For DISH items:                                           │
│    → Upload dish photo using Cal AI's photo estimation      │
│    → Let Cal AI's built-in food recognition handle it      │
│                                                            │
│  For WATER:                                                │
│    → Use Cal AI's water tracking UI element                 │
│    → Log the specified amount                               │
└──────────────────────────────────────────────────────────┘
```

### Key Technical Challenges

| Challenge | Approach |
|-----------|----------|
| Frame deduplication | Perceptual hashing or CLIP embeddings to group similar frames, keep the most informative one per food item |
| Nutrition label OCR | Vision framework text recognition or cloud OCR on the best frame |
| Portion estimation from speech | Transcript parsing — map spoken quantities to serving sizes using label data |
| Cal AI automation | iOS accessibility APIs or Shortcuts integration to fill in the Cal AI app programmatically |
| 30-second window management | Circular buffer of frames + audio, triggered by voice command or gesture |
| Food vs non-food filtering | Vision classifier or CLIP zero-shot to discard frames without food |

### Components to Build

| Component | Status | Description |
|-----------|--------|-------------|
| Glasses streaming (720p) | Done | MWDAT SDK, raw codec, 24fps |
| HFP audio capture | Done | 8kHz → 16kHz resampled |
| Live transcription | Done | Moonshine v2 on-device |
| TTS to glasses | Done | AVSpeechSynthesizer over HFP |
| Voice trigger ("log food") | Planned | Keyword detection in transcript stream |
| 30-second recording buffer | Planned | Circular buffer of frames + audio with start/stop trigger |
| Frame deduplication | Planned | Extract unique food images from clip |
| Nutrition label detection | Planned | Identify frames containing nutrition labels |
| Visual + audio fusion | Planned | Combine transcript quantities with visual food identification |
| Cal AI integration | Planned | Automate data entry into Cal AI app |
| Water tracking | Planned | Parse water mentions from transcript, log via Cal AI |
| Hand gesture detection | Planned | Optional activation method alongside voice |

## Existing Infrastructure (from Reflections core)

This branch builds on the existing monolith codebase:

### Project Structure

```
monolith/
├── ActiveSpeaker/                    # iOS app (Xcode project)
│   ├── ActiveSpeaker/
│   │   ├── App/                      # App entry point, Info.plist
│   │   ├── Capture/                  # Camera + audio capture
│   │   ├── Glasses/                  # Meta glasses integration (MWDAT SDK)
│   │   │   ├── GlassesConnectionManager.swift
│   │   │   ├── GlassesStreamManager.swift
│   │   │   ├── GlassesAudioCapture.swift
│   │   │   ├── GlassesSpeaker.swift
│   │   │   └── GlassesPrompt.swift
│   │   ├── Models/                   # Data models
│   │   ├── Pipeline/                 # PipelineCoordinator, FusionEngine
│   │   ├── Processors/              # SileroVAD, MouthMovement, FaceEmbedding, Moonshine
│   │   ├── UI/                       # SwiftUI views
│   │   └── prompts/                 # Prompt text files
│   ├── MobileFaceNet.mlpackage/
│   ├── silero_vad.onnx
│   └── small-streaming-en/          # Moonshine models (not in git)
├── scripts/
├── MODELS.md
└── CLAUDE.md                         # This file
```

### Meta Glasses Integration

- **SDK**: MWDAT 0.5.0 (`https://github.com/facebook/meta-wearables-dat-ios`)
- **Products**: `MWDATCore`, `MWDATCamera`
- **Video**: `.raw` codec, `.high` resolution (720x1280), 24fps
- **Audio in**: HFP Bluetooth mic → 16kHz mono
- **Audio out**: `AVSpeechSynthesizer` → HFP speakers
- **Pipeline**: video frames fed via `CMSampleBuffer` → `CVPixelBuffer`

## Building

1. Open `ActiveSpeaker/ActiveSpeaker.xcodeproj` in Xcode
2. Download Moonshine models (see `MODELS.md`)
3. Add MWDAT SPM package: `https://github.com/facebook/meta-wearables-dat-ios` (0.5.0+)
4. Set signing team and bundle identifier
5. Build and run on physical iPhone (iOS 17+)
