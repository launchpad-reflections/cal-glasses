# Cal Glasses — Hands-Free Calorie Logging with Meta Ray-Ban Glasses

Log calories by just looking at your food. Cal Glasses pairs Meta Ray-Ban smart glasses with [Cal AI](https://apps.apple.com/us/app/cal-ai-calorie-tracker/id6480417616) to automatically identify food, estimate nutrition, and upload photos to Cal AI — all hands-free.

## How It Works

1. **Wear your Meta Ray-Ban glasses** and open the app
2. **Say "log food"** (or tap the button) to start a 10-second recording
3. **Look at your food** — the glasses capture high-quality photos
4. **Describe what you're eating** — "I had two RX Bars" (optional, improves accuracy)
5. **Gemini AI analyzes** the photos + transcript → identifies food, reads nutrition labels, estimates calories
6. **Photos are automatically uploaded to Cal AI** via Appium automation on your Mac

```
Meta Glasses → capture photos → Gemini analyzes → save to camera roll → Appium uploads to Cal AI
```

## Demo

https://x.com/mohul_shukla/status/2037226258459656246

## Requirements

### Hardware
- **Meta Ray-Ban glasses** (any model with camera)
- **iPhone** (iOS 17+, A13 chip or later)
- **Mac** (for Appium automation server)
- **USB cable** connecting iPhone to Mac

### Software
- **Xcode 15+** (with iOS 17+ SDK)
- **Node.js** (for Appium)
- **Python 3.8+**
- **Meta AI app** on iPhone (for glasses pairing)
- **Cal AI app** on iPhone

### API Keys
- **Google Gemini API key** — get one at [ai.google.dev](https://ai.google.dev)

## Setup

### Step 1: Clone and Open in Xcode

```bash
git clone https://github.com/launchpad-reflections/cal-glasses.git
cd cal-glasses
open ActiveSpeaker/ActiveSpeaker.xcodeproj
```

### Step 2: Download Moonshine Models (~160MB)

The on-device speech-to-text models are not included in git:

```bash
curl -L -o /tmp/ios-examples.tar.gz \
  https://github.com/moonshine-ai/moonshine/releases/latest/download/ios-examples.tar.gz
tar -xzf /tmp/ios-examples.tar.gz -C /tmp Transcriber/models/
cp -r /tmp/Transcriber/models/small-streaming-en ActiveSpeaker/small-streaming-en
```

In Xcode, verify `small-streaming-en` appears in the project navigator. If not, drag the folder in (Create folder references → Add to targets: ActiveSpeaker).

### Step 3: Add Meta Wearables SDK

In Xcode: **File → Add Package Dependencies** → paste:
```
https://github.com/facebook/meta-wearables-dat-ios
```
Set version to **0.5.0+**, add both **MWDATCore** and **MWDATCamera** to the ActiveSpeaker target.

### Step 4: Configure API Key

Open `ActiveSpeaker/ActiveSpeaker/Glasses/GlassesStreamManager.swift` and replace:
```swift
private let gemini = GeminiService(apiKey: "YOUR_GEMINI_API_KEY")
```

### Step 5: Configure Signing

In Xcode:
1. Select the **ActiveSpeaker** target → **Signing & Capabilities**
2. Set your **Team** (Apple ID)
3. Change **Bundle Identifier** to something unique (e.g., `com.yourname.calglasses`)

### Step 6: Build and Run

1. Connect your iPhone via USB
2. Select your iPhone as the build target
3. **Cmd+R** to build and run
4. Grant camera, microphone, and Bluetooth permissions when prompted

### Step 7: Connect Glasses

1. Tap **Connect Glasses** in the app
2. You'll be redirected to the Meta AI app to authorize
3. Return to the app — glasses should show as connected
4. Tap **Start Glasses** to begin streaming

## Cal AI Automation (Appium)

This is the part that automatically uploads food photos to Cal AI on your iPhone.

### Step 7: Install Appium

```bash
cd appium
npm install -g appium
appium driver install xcuitest
pip install -r requirements.txt
```

### Step 8: Configure Device

Find your device UDID and Team ID:
```bash
xcrun xctrace list devices
```

Edit `appium/config.py`:
```python
DEVICE_UDID = "YOUR_DEVICE_UDID"
TEAM_ID = "YOUR_TEAM_ID"
CAL_AI_BUNDLE_ID = "com.viraldevelopment.CalAI"  # This is Cal AI's bundle ID
```

### Step 9: Install WebDriverAgent

WebDriverAgent is a test runner that Appium uses to control your iPhone's UI.

```bash
open ~/.appium/node_modules/appium-xcuitest-driver/node_modules/appium-webdriveragent/WebDriverAgent.xcodeproj
```

In Xcode:
1. Select **WebDriverAgentRunner** target
2. **Signing & Capabilities** → set your Team
3. Change **Bundle Identifier** to `com.yourname.WebDriverAgentRunner`
4. Select your iPhone as device
5. **Cmd+U** (Product → Test) to build and install WDA

### Step 10: Enable iPhone Developer Settings

On your iPhone:
1. **Settings → Privacy & Security → Developer Mode** → ON
2. **Settings → Developer → Enable UI Automation** → ON

### Step 11: Start the Automation Stack

You need **4 terminal tabs** running:

**Terminal 1 — Tunnel** (required for iOS 17+):
```bash
sudo pymobiledevice3 remote start-tunnel
```

**Terminal 2 — Appium server:**
```bash
appium
```

**Terminal 3 — WebDriverAgent:**
Open WebDriverAgent.xcodeproj in Xcode → **Cmd+U**

**Terminal 4 — Automation server:**
```bash
cd appium
python server.py
```

### Step 12: Test

Test the Cal AI upload independently:
```bash
cd appium
python cal_ai_automate.py upload        # Upload most recent photo
python cal_ai_automate.py upload 2      # Upload 2nd most recent
python cal_ai_automate.py upload 3 --inclusive  # Upload last 3 photos
```

## Full End-to-End Flow

With everything running:

1. Open the app on your iPhone
2. Connect glasses → Start streaming
3. Say **"log food"** or tap **Log Food**
4. **Look at your food** for 10 seconds while describing it
5. Gemini analyzes → identifies items → saves photos
6. App automatically triggers Mac server → Appium opens Cal AI → uploads photos
7. Cal AI analyzes and logs the food

## Architecture

```
┌─────────────────────────────────────────────┐
│           Meta Ray-Ban Glasses               │
│  Camera (720p@24fps) + Microphone (HFP 8kHz)│
└──────────────┬──────────────────────────────┘
               │ Bluetooth
┌──────────────▼──────────────────────────────┐
│              iPhone App                       │
│                                               │
│  Stream video ──► Live display                │
│  Capture photos ──► High-quality JPEGs        │
│  Audio ──► SileroVAD + Moonshine transcription│
│                                               │
│  "log food" detected ──► 10s recording        │
│  Photos + transcript ──► Gemini 2.5 Flash     │
│  Results ──► Save photos to camera roll       │
│  HTTP POST ──► Mac automation server          │
└──────────────┬──────────────────────────────┘
               │ HTTP (local network)
┌──────────────▼──────────────────────────────┐
│              Mac (server.py)                  │
│                                               │
│  Receives upload request ──► runs Appium      │
│  Appium ──► WebDriverAgent on iPhone          │
│  WDA ──► Opens Cal AI                         │
│  WDA ──► Tap + → Scan food → Photo → Select  │
│  Cal AI analyzes and logs the food            │
└─────────────────────────────────────────────┘
```

## Project Structure

```
cal-glasses/
├── ActiveSpeaker/                  # iOS app (Xcode project)
│   ├── ActiveSpeaker/
│   │   ├── App/                    # Entry point, Info.plist
│   │   ├── Glasses/                # Meta glasses integration
│   │   │   ├── GlassesStreamManager.swift    # Stream + food logging orchestration
│   │   │   ├── GlassesConnectionManager.swift # Glasses pairing
│   │   │   ├── GlassesAudioCapture.swift     # HFP Bluetooth mic
│   │   │   ├── GlassesSpeaker.swift          # TTS to glasses speakers
│   │   │   ├── FoodRecordingBuffer.swift     # 10s frame + transcript buffer
│   │   │   └── FrameDeduplicator.swift       # Perceptual hash dedup
│   │   ├── Services/
│   │   │   ├── GeminiService.swift           # Gemini API client
│   │   │   └── CalAITriggerService.swift     # HTTP trigger to Mac
│   │   ├── Models/
│   │   │   └── FoodAnalysisResult.swift      # Structured food data
│   │   ├── Pipeline/                # Audio/video processing
│   │   ├── Processors/              # VAD, transcription, face detection
│   │   └── UI/
│   │       └── CalGlassesView.swift          # Main UI
│   ├── MobileFaceNet.mlpackage/
│   └── silero_vad.onnx
├── appium/                         # Cal AI automation
│   ├── cal_ai_automate.py          # Main automation script
│   ├── server.py                   # HTTP server for app triggers
│   ├── config.py                   # Device config
│   ├── setup.sh                    # One-time installation
│   └── APPIUM.md                   # Detailed Appium docs
├── scripts/
│   └── tts.py                      # Text-to-speech generator
├── PIPELINE.md                     # Food logging pipeline docs
├── MODELS.md                       # Model download instructions
└── CLAUDE.md                       # AI assistant context
```

## Configuration Flags

In `GlassesStreamManager.swift`:

| Flag | Default | Description |
|------|---------|-------------|
| `DEFAULT_CAMERA` | `false` | `true`: use capturePhoto() for high-quality images. `false`: use deduplicated stream frames |
| `TEST` | `true` | `true`: skip camera roll save, always upload last 2 photos. `false`: normal flow |

## Tech Stack

- **Swift / SwiftUI** — iOS app
- **Meta MWDAT SDK 0.5.0** — glasses connectivity and streaming
- **Gemini 2.5 Flash** — multimodal food analysis (images + text)
- **Moonshine v2** — on-device speech-to-text
- **Silero VAD** — voice activity detection (ONNX Runtime)
- **MobileFaceNet** — face recognition (CoreML)
- **Appium + XCUITest** — iOS UI automation
- **pymobiledevice3** — iOS 17+ device tunnel
- **Python** — automation server and scripts

## License

MIT
