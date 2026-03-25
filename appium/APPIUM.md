# Cal AI Automation via Appium — How It All Works

## Overview

We automate the Cal AI iOS app to upload food photos without manual interaction. A Python script on your Mac controls your real iPhone over USB, navigating Cal AI's UI to select and upload the most recent photo from the camera roll.

## The Three Services

Three things must be running simultaneously for this to work:

### 1. pymobiledevice3 Tunnel

```bash
sudo pymobiledevice3 remote start-tunnel
```

**What it does:** iOS 17+ requires a secure tunnel between the Mac and iPhone for developer tools to communicate. This replaced the old usbmuxd approach. The tunnel creates a virtual network interface (utun8) between your Mac and iPhone over USB.

**Why it's needed:** Without this tunnel, Appium can't find your device. The tunnel provides a TCP connection that WebDriverAgent uses to send/receive commands.

**What happens when you run it:**
1. Asks for your Mac password (needs root to create network interface)
2. Your iPhone shows a "Trust" prompt (first time only)
3. Creates a tunnel with an RSD address (e.g., `fd23:a87b:ac87::1:50787`)
4. Stays running — if you close the terminal, the tunnel dies

### 2. Appium Server

```bash
appium
```

**What it does:** Appium is a Node.js server that acts as a bridge between your Python script and the iPhone. It speaks the WebDriver protocol (same protocol used for browser automation like Selenium) and translates commands into iOS-specific actions via the XCUITest driver.

**Architecture:**
```
Python script → HTTP (WebDriver protocol) → Appium server (localhost:4723)
    → XCUITest Driver → WebDriverAgent (on iPhone) → iOS UI actions
```

**What happens when you run it:**
1. Loads the XCUITest driver plugin
2. Starts an HTTP server on port 4723
3. Waits for WebDriver session requests
4. When a session starts, it builds/deploys WebDriverAgent to the iPhone

### 3. WebDriverAgent (WDA)

**What it is:** A special app that runs ON the iPhone. It's an XCTest runner that can find and interact with UI elements in any app. Think of it as a robot sitting inside the phone that can tap buttons, read text, and take screenshots.

**How it got there:** We opened the WebDriverAgent Xcode project, signed it with your developer certificate (`com.mohulshukla.WebDriverAgentRunner`), and built it to your phone with Cmd+U. This installs a test runner app that Appium can control.

**Why Xcode Cmd+U is needed:** WDA needs to be launched as an XCTest session, which requires Xcode's authorization. Running Cmd+U in Xcode authorizes the test session, and then Appium can connect to the already-running WDA. Without this authorization step, you get "Not authorized for performing UI testing actions."

## The Python Script

### `cal_ai_automate.py upload`

**What it does, step by step:**

1. **Creates a WebDriver session** — connects to Appium at localhost:4723 with your device's UDID, team ID, and Cal AI's bundle ID (`com.viraldevelopment.CalAI`)

2. **Appium launches Cal AI** — tells WDA on the phone to open Cal AI

3. **Navigates to Home tab** — taps the "Home" button to ensure we're on the main screen

4. **Taps the + button** — finds the floating action button (accessibility name: "plus", position: bottom-right at 311,760) and taps it. This opens a 4-option menu: Log exercise, Saved foods, Food Database, Scan food

5. **Taps "Scan food"** — opens the camera view with tabs for Scan Food, Barcode, and Food label

6. **Taps "Photo"** — switches from camera to photo library picker. This shows a grid of photos from the camera roll

7. **Selects the first cell** — taps the first `XCUIElementTypeCell` in the photo grid, which is the most recent photo

8. **Cal AI analyzes** — the app automatically starts analyzing the selected photo ("17%, Analyzing Image, We'll notify you when done!")

9. **Re-activates Cal AI** — calls `activate_app()` to ensure Cal AI stays in the foreground

10. **Waits 40 seconds** — keeps the session alive so Cal AI stays visible while it processes

11. **Closes session** — `driver.quit()` ends the WebDriver session. Cal AI remains on the phone.

## How We Discovered the UI Flow

### Exploration Process

We didn't know Cal AI's button labels, accessibility IDs, or navigation structure ahead of time. We discovered everything through systematic exploration:

**Step 1: `explore` command** — Opened Cal AI and dumped every UI element:
- Found 20 buttons with labels like "Home", "Progress", "Add", "Scan food"
- Found the calorie/macro display buttons
- Identified the tab bar structure

**Step 2: Tried "Add" button** — Tapped it, dumped UI again. Same screen — "Add" didn't navigate anywhere visible. Screenshot confirmed it was the wrong button.

**Step 3: Found the real + button** — Dumped ALL elements with positions. Found `Button[10] label='Add' name='plus' pos=(311,760) size=(62x62)` — the floating action button in the bottom right. Tapped by accessibility ID "plus" instead of label "Add".

**Step 4: After + tap** — Screenshot showed a 4-option popup: Log exercise, Saved foods, Food Database, Scan food. We identified "Scan food" as the path to camera/photo upload.

**Step 5: After Scan food** — Camera opened. Dumped elements and found: "Scan Food", "Barcode", "Food label" tabs, plus "Photo" button and "Flash Off". The "Photo" button opens the photo library.

**Step 6: After Photo** — Photo picker appeared with `XCUIElementTypeCell` elements representing photos. Tapping the first cell selects the most recent photo.

**Step 7: After selection** — Cal AI automatically started analyzing: `"14%, Analyzing Image, We'll notify you when done!"`. Success!

### Exploration Scripts Created

During discovery, we wrote several one-off scripts:
- `explore_step.py` — Initial UI dump + tap Scan food
- `explore_add.py` — Test the "Add" button (turned out wrong)
- `explore_plus.py` — Find the real + FAB with positions
- `explore_plus2.py` — Tap + by accessibility ID
- `explore_scan.py` — Chain: + → Scan food → dump camera screen
- `explore_photo.py` — Chain: + → Scan food → Photo → dump picker
- `full_flow.py` — Complete: + → Scan food → Photo → select → verify

## Configuration

### `config.py`

```python
DEVICE_UDID = "YOUR_DEVICE_UDID"      # Your iPhone's unique ID
DEVICE_NAME = "Mohul's iPhone"                   # Device name
TEAM_ID = "YOUR_TEAM_ID"                          # Apple Developer Team ID
CAL_AI_BUNDLE_ID = "com.viraldevelopment.CalAI"  # Cal AI's app identifier
APPIUM_SERVER = "http://localhost:4723"           # Appium server URL
```

**How we found these:**
- `DEVICE_UDID` — `xcrun xctrace list devices`
- `TEAM_ID` — from Xcode project build settings (`DEVELOPMENT_TEAM`)
- `CAL_AI_BUNDLE_ID` — `ideviceinstaller list | grep cal`

## Element Finding Strategies

Appium finds UI elements using several methods (fastest to slowest):

| Strategy | Example | Speed |
|----------|---------|-------|
| Accessibility ID | `find_element(AppiumBy.ACCESSIBILITY_ID, "plus")` | Fastest |
| iOS Class Chain | `find_element(AppiumBy.IOS_CLASS_CHAIN, "**/XCUIElementTypeButton[\`label == 'Photo'\`]")` | Fast |
| Class Name | `find_elements(AppiumBy.CLASS_NAME, "XCUIElementTypeCell")` | Medium |
| XPath | `find_element(AppiumBy.XPATH, "//XCUIElementTypeButton[@name='Add']")` | Slowest |

We use Accessibility ID for the + button ("plus") and iOS Class Chain for labeled buttons.

## Prerequisites Checklist

Before running the automation:

- [ ] iPhone connected via USB
- [ ] iPhone unlocked
- [ ] Developer Mode ON (Settings → Privacy & Security → Developer Mode)
- [ ] UI Automation ON (Settings → Developer → Enable UI Automation)
- [ ] WebDriverAgent built and installed (Xcode → WebDriverAgent.xcodeproj → Cmd+U)
- [ ] pymobiledevice3 tunnel running (`sudo pymobiledevice3 remote start-tunnel`)
- [ ] Appium server running (`appium`)
- [ ] Cal AI installed on iPhone
- [ ] At least one photo in camera roll

## Integration with Cal Reflections (Future)

The end-to-end flow:
```
Meta Glasses → capture food photo → Gemini analyzes → save best photo to camera roll
    → trigger Appium script → Cal AI receives photo → food logged automatically
```

The glasses app would:
1. Save the food photo to the iPhone's camera roll using `PHPhotoLibrary`
2. Send an HTTP request to a local server on the Mac
3. The Mac runs `python cal_ai_automate.py upload`
4. Cal AI processes the photo and logs the food
