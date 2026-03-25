# Device and signing configuration
DEVICE_UDID = "YOUR_DEVICE_UDID"
DEVICE_NAME = "Mohul's iPhone"
TEAM_ID = ""  # Your Apple Team ID — find in Xcode: Signing & Capabilities → Team

# Cal AI app — we need to find the real bundle ID
# To find it: install Cal AI, then run:
#   ideviceinstaller -l | grep -i cal
# or check in Appium Inspector
CAL_AI_BUNDLE_ID = "ai.cal.mobile"  # Placeholder — needs verification

# Appium server
APPIUM_SERVER = "http://localhost:4723"
