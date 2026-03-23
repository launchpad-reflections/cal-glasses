# Reflections — Monolith

## What is Reflections?

Reflections is a real-time active speaker detection and identification system. It combines audio analysis, facial recognition, and live transcription to detect who is speaking, identify them by name, and transcribe what they say — all running on-device on an iPhone.

The project supports two video sources:
1. **iPhone front camera** — selfie mode for face-to-face conversations
2. **Meta Ray-Ban glasses** — first-person POV streaming from smart glasses

## Project Structure

```
monolith/
├── ActiveSpeaker/                    # iOS app (Xcode project)
│   ├── ActiveSpeaker.xcodeproj/
│   ├── ActiveSpeaker/
│   │   ├── App/                      # App entry point, Info.plist
│   │   ├── Capture/                  # Camera + audio capture (CaptureManager, CameraPreviewView)
│   │   ├── Glasses/                  # Meta glasses integration (MWDAT SDK)
│   │   ├── Models/                   # Data models (SpeakerState, IdentifiedFace, FaceGallery)
│   │   ├── Pipeline/                 # Core processing pipeline (PipelineCoordinator, FusionEngine)
│   │   ├── Processors/              # ML processors (SileroVAD, MouthMovement, FaceEmbedding, Moonshine)
│   │   ├── UI/                       # SwiftUI views
│   │   └── Utilities/               # RollingBuffer, helpers
│   ├── MobileFaceNet.mlpackage/     # CoreML face embedding model
│   ├── silero_vad.onnx              # Voice activity detection model
│   └── small-streaming-en/          # Moonshine transcription models (not in git, see MODELS.md)
├── scripts/                          # Python scripts for model conversion
├── MODELS.md                         # Instructions to download large model files
└── CLAUDE.md                         # This file
```

## Architecture

### Pipeline (PipelineCoordinator)

The central orchestrator receives audio and video buffers and routes them through:

1. **Audio path** (dedicated queue):
   - **SileroVAD** — ONNX Runtime inference for voice activity detection (speech probability 0–1)
   - **MoonshineTranscriber** — real-time speech-to-text via Moonshine v2 small-streaming model

2. **Video path** (dedicated queue):
   - **FaceDetectionProvider** — Apple Vision framework face landmark detection
   - **MouthMovementProcessor** — lip aperture tracking with EMA smoothing + rolling variance
   - **FaceEmbeddingProcessor** — MobileFaceNet CoreML model for face recognition against enrolled gallery

3. **FusionEngine** — combines audio probability + mouth variance into speaker state (SPEAKING/MAYBE/SILENT)

### Tabs

- **Camera** — live selfie camera with face detection overlays, speaker state border, and transcription
- **Enroll** — capture face embeddings to build a recognition gallery (up to 5 photos per person)
- **Glasses** — connect Meta Ray-Ban glasses, stream live video, and run the same pipeline on glasses frames

### Meta Glasses Integration

Uses **Meta Wearables Device Access Toolkit (MWDAT) 0.5.0** SDK:
- SPM package: `https://github.com/facebook/meta-wearables-dat-ios`
- Products: `MWDATCore`, `MWDATCamera`
- Connection flow: `Wearables.configure()` → `startRegistration()` → Meta AI app callback → `handleUrl()`
- Video: `StreamSession` with `.raw` codec, `.high` resolution (720x1280), 24fps
- Audio: HFP Bluetooth microphone capture, resampled 8kHz → 16kHz
- Video frames are converted to `CVPixelBuffer` via `CMSampleBuffer` for Vision pipeline processing

### Key Configuration

- **Info.plist**: URL scheme `activespeaker-meta://`, external accessory protocol `com.meta.ar.wearable`, background modes (bluetooth-peripheral, external-accessory), MWDAT config
- **Entitlements**: `com.apple.external-accessory.wireless-configuration`
- **Minimum iOS**: 17.0
- **Swift**: 6.0 tools version (for MWDAT SPM compatibility)

## Building

1. Open `ActiveSpeaker/ActiveSpeaker.xcodeproj` in Xcode
2. Download Moonshine models (see `MODELS.md`)
3. Add MWDAT SPM package if not already resolved: `https://github.com/facebook/meta-wearables-dat-ios` (0.5.0+)
4. Set signing team and bundle identifier
5. Build and run on a physical iPhone (iOS 17+, A13 chip or later)

## Thread Safety

- Audio and video processing run on separate dedicated `DispatchQueue`s (`.userInteractive` QoS)
- Transcription runs on its own serial queue to avoid blocking VAD
- Cross-queue state (`audioProb`, `mouthVariance`) protected by `os_unfair_lock`
- `FaceGallery` persistence protected by `os_unfair_lock`
- All `@Published` UI state updated exclusively on the main thread

## Models (not in git)

Large model files are gitignored. See `MODELS.md` for download instructions:
- `small-streaming-en/` — Moonshine v2 transcription models (~160MB)

Models tracked in git:
- `silero_vad.onnx` — Silero voice activity detection (~2.3MB)
- `MobileFaceNet.mlpackage/` — face embedding model for recognition
