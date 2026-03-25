# Cal AI Automation via Appium

Automates food photo logging into the Cal AI iOS app using Appium + XCUITest.

## Setup

```bash
# 1. Install dependencies
chmod +x setup.sh
./setup.sh

# 2. Find Cal AI's bundle ID
chmod +x find_bundle_id.sh
./find_bundle_id.sh

# 3. Update config.py with:
#    - TEAM_ID (from Xcode → Signing & Capabilities)
#    - CAL_AI_BUNDLE_ID (from step 2)
```

## Usage

```bash
# Terminal 1: Start Appium server
appium

# Terminal 2: Explore Cal AI's UI first
python cal_ai_automate.py explore

# Terminal 2: Run the automation
python cal_ai_automate.py run
```

## How It Works

1. Appium connects to your iPhone via USB
2. WebDriverAgent (XCUITest) is deployed to the device
3. Cal AI is launched
4. The script finds and taps UI elements (Add Food → Select Photo → Confirm)
5. The most recent photo in the camera roll is selected

## Integration with Cal Reflections

The full flow:
1. Glasses app detects food → saves best photo to camera roll
2. Glasses app sends HTTP request to Mac
3. Mac runs this Appium script
4. Cal AI receives the photo and logs it

## Files

- `setup.sh` — One-time installation
- `config.py` — Device UDID, Team ID, bundle ID
- `find_bundle_id.sh` — Helper to find Cal AI's bundle ID
- `cal_ai_automate.py` — Main automation script
- `requirements.txt` — Python dependencies
