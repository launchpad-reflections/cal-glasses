# Reflections — Monolith

## Vision

Reflections is an AI-powered wearable assistant built on Meta Ray-Ban glasses. It sees what you see, hears what you hear, and whispers real-time coaching through the glasses' speakers — turning every conversation into a guided interaction.

The system combines on-device ML (face recognition, voice activity detection, live transcription) with cloud AI (Claude API for contextual reasoning) and calendar integration to deliver situational awareness that feels like a superpower.

## Cal-Reflections: Calendar-Aware Conversational AI

This branch (`cal-reflections`) extends the core Reflections pipeline with a calendar-integrated coaching layer:

### Core Loop

1. **Pre-meeting briefing**: Before a calendar event, the glasses whisper context — who you're meeting, what was discussed last time, key talking points, and your goals for this interaction.

2. **Live conversation coaching**: During the meeting, the system listens via transcription, identifies speakers via face recognition, and provides real-time whispered cues — suggested questions, fact corrections, follow-up reminders, or social cues.

3. **Post-meeting memory**: After the conversation, key takeaways, action items, and relationship notes are persisted to a local memory layer, available for the next interaction with that person.

### Architecture (Planned)

```
┌─────────────────────────────────────────────────────────┐
│                    Meta Ray-Ban Glasses                   │
│  Camera (720p) ──► iPhone ◄── Microphone (HFP 8kHz)    │
│                    Speakers ◄── TTS Audio                │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│                  On-Device Pipeline                       │
│                                                           │
│  Video ──► Face Detection (Vision) ──► Face Recognition  │
│            (MobileFaceNet)                                │
│                                                           │
│  Audio ──► VAD (Silero) ──► Transcription (Moonshine)   │
│            Speaker State (FusionEngine)                   │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│                  Calendar + Context Layer                 │
│                                                           │
│  EventKit ──► Upcoming meetings, attendees, location     │
│  FaceGallery ──► Match recognized faces to contacts      │
│  MemoryStore ──► Past interactions, notes, preferences   │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│                  AI Reasoning (Cloud)                     │
│                                                           │
│  Claude API ──► Contextual prompt generation             │
│    Inputs: calendar context, identified faces,           │
│            live transcript, memory/history                │
│    Output: coaching whispers, briefings, follow-ups      │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│                  Audio Output                             │
│                                                           │
│  GlassesSpeaker (AVSpeechSynthesizer) ──► HFP speakers  │
│  Future: ElevenLabs / custom voice for natural whispers  │
└─────────────────────────────────────────────────────────┘
```

### Key Components to Build

| Component | Status | Description |
|-----------|--------|-------------|
| Glasses streaming | Done | MWDAT SDK, 720p raw, 24fps |
| Face detection + recognition | Done | Vision + MobileFaceNet pipeline |
| Voice activity detection | Done | Silero VAD via ONNX Runtime |
| Live transcription | Done | Moonshine v2 small-streaming |
| TTS to glasses | Done | AVSpeechSynthesizer over HFP |
| Calendar integration | Planned | EventKit read access, upcoming events |
| Contact ↔ Face linking | Planned | Map FaceGallery entries to calendar attendees |
| Memory/history store | Planned | Persist conversation summaries per person |
| Claude API integration | Planned | Generate contextual coaching from combined signals |
| Pre-meeting briefing | Planned | Trigger briefing N minutes before calendar event |
| Live coaching whispers | Planned | Real-time contextual suggestions during conversation |
| Post-meeting summary | Planned | Auto-generate takeaways and action items |

### User Scenarios

**Scenario 1: Conference Networking**
> You walk up to someone at a conference. The glasses recognize their face from a previous enrollment. Claude whispers: "That's Sarah Chen, CTO at Meridian. Last time you discussed their migration to Rust. She mentioned they're hiring senior engineers." You now have perfect recall.

**Scenario 2: Investor Meeting**
> 10 minutes before your pitch, the glasses whisper a briefing based on your calendar: "Meeting with Sequoia — partner is Alex. Your deck focuses on the $2M ARR milestone. Last meeting they asked about churn metrics — have your answer ready." During the meeting, as you discuss pricing, Claude whispers: "Alex seems skeptical — pivot to the unit economics slide."

**Scenario 3: Daily Standups**
> The glasses recognize each team member as they speak, transcribe their updates, and after the meeting auto-generate a summary with action items sent to your notes app.

## Project Structure

```
monolith/
├── ActiveSpeaker/                    # iOS app (Xcode project)
│   ├── ActiveSpeaker.xcodeproj/
│   ├── ActiveSpeaker/
│   │   ├── App/                      # App entry point, Info.plist
│   │   ├── Capture/                  # Camera + audio capture (CaptureManager, CameraPreviewView)
│   │   ├── Glasses/                  # Meta glasses integration (MWDAT SDK)
│   │   │   ├── GlassesConnectionManager.swift  # Registration + device discovery
│   │   │   ├── GlassesStreamManager.swift      # Video/audio streaming + pipeline feed
│   │   │   ├── GlassesAudioCapture.swift       # HFP Bluetooth mic capture
│   │   │   ├── GlassesSpeaker.swift            # TTS output to glasses speakers
│   │   │   ├── GlassesPrompt.swift             # Prompt text loader
│   │   │   └── GlassesConnectionState.swift    # Connection state enum
│   │   ├── Models/                   # Data models (SpeakerState, IdentifiedFace, FaceGallery)
│   │   ├── Pipeline/                 # Core processing (PipelineCoordinator, FusionEngine)
│   │   ├── Processors/              # ML processors (SileroVAD, MouthMovement, FaceEmbedding, Moonshine)
│   │   ├── UI/                       # SwiftUI views
│   │   ├── Utilities/               # RollingBuffer, helpers
│   │   └── prompts/                 # Markdown prompt files for TTS
│   ├── MobileFaceNet.mlpackage/     # CoreML face embedding model
│   ├── silero_vad.onnx              # Voice activity detection model
│   └── small-streaming-en/          # Moonshine transcription models (not in git)
├── scripts/                          # Python scripts for model conversion
├── MODELS.md                         # Instructions to download large model files
└── CLAUDE.md                         # This file
```

## Building

1. Open `ActiveSpeaker/ActiveSpeaker.xcodeproj` in Xcode
2. Download Moonshine models (see `MODELS.md`)
3. Add MWDAT SPM package if not already resolved: `https://github.com/facebook/meta-wearables-dat-ios` (0.5.0+)
4. Set signing team and bundle identifier
5. Build and run on a physical iPhone (iOS 17+, A13 chip or later)

## Meta Glasses Integration

Uses **Meta Wearables Device Access Toolkit (MWDAT) 0.5.0** SDK:
- SPM package: `https://github.com/facebook/meta-wearables-dat-ios`
- Products: `MWDATCore`, `MWDATCamera`
- Connection: `Wearables.configure()` → `startRegistration()` → Meta AI app callback → `handleUrl()`
- Video: `StreamSession` with `.raw` codec, `.high` resolution (720x1280), 24fps
- Audio input: HFP Bluetooth mic, resampled 8kHz → 16kHz
- Audio output: `AVSpeechSynthesizer` routes TTS through HFP to glasses speakers
- Video frames fed to pipeline via `CMSampleBuffer` → `CVPixelBuffer` (zero-copy)

## Thread Safety

- Audio and video processing on separate `DispatchQueue`s (`.userInteractive`)
- Transcription on its own serial queue
- Cross-queue state protected by `os_unfair_lock`
- `FaceGallery` persistence protected by `os_unfair_lock`
- All `@Published` UI state updated on main thread

## Models

Large model files are gitignored — see `MODELS.md` for download instructions:
- `small-streaming-en/` — Moonshine v2 transcription (~160MB)

Models tracked in git:
- `silero_vad.onnx` — Silero voice activity detection (~2.3MB)
- `MobileFaceNet.mlpackage/` — face embedding model
