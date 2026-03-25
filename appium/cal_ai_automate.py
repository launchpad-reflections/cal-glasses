"""
Cal AI Automation via Appium
Automates: Open Cal AI → + → Scan food → Photo → Select latest photo

Usage:
  1. Ensure pymobiledevice3 tunnel is running: sudo pymobiledevice3 remote start-tunnel
  2. Start Appium server: appium
  3. Run: python cal_ai_automate.py
"""

import time
import sys
from appium import webdriver
from appium.options.ios import XCUITestOptions
from appium.webdriver.common.appiumby import AppiumBy

from config import DEVICE_UDID, DEVICE_NAME, TEAM_ID, CAL_AI_BUNDLE_ID, APPIUM_SERVER


def create_driver():
    """Create Appium driver for Cal AI on real iPhone."""
    if not TEAM_ID:
        print("ERROR: Set TEAM_ID in config.py")
        sys.exit(1)

    options = XCUITestOptions()
    options.platform_name = "iOS"
    options.device_name = DEVICE_NAME
    options.udid = DEVICE_UDID
    options.bundle_id = CAL_AI_BUNDLE_ID
    options.xcode_org_id = TEAM_ID
    options.xcode_signing_id = "iPhone Developer"
    options.auto_accept_alerts = True
    options.new_command_timeout = 300
    options.updated_wda_bundle_id = "com.mohulshukla.WebDriverAgentRunner"
    options.set_capability("useXctestrunFile", False)
    options.set_capability("wdaLaunchTimeout", 60000)
    options.set_capability("derivedDataPath",
        "/Users/mohulshukla/Library/Developer/Xcode/DerivedData/"
        "WebDriverAgent-hkuowqrpnlpmkpcvynbgcpqinsnh")
    options.set_capability("allowProvisioningUpdates", True)

    print(f"Connecting to {DEVICE_NAME}...")
    driver = webdriver.Remote(command_executor=APPIUM_SERVER, options=options)
    driver.implicitly_wait(10)
    print("✓ Connected\n")
    return driver


def upload_latest_photo():
    """
    Full automation: open Cal AI, navigate to photo upload,
    select the most recent photo from camera roll.
    Cal AI will automatically analyze it.
    """
    driver = create_driver()
    try:
        time.sleep(2)

        # Go to home tab
        try:
            driver.find_element(AppiumBy.ACCESSIBILITY_ID, "Home").click()
            time.sleep(1)
        except:
            pass

        # Step 1: Tap + (plus FAB)
        print("Step 1: Tap +")
        driver.find_element(AppiumBy.ACCESSIBILITY_ID, "plus").click()
        time.sleep(1)

        # Step 2: Tap "Scan food"
        print("Step 2: Tap Scan food")
        driver.find_element(AppiumBy.ACCESSIBILITY_ID, "Scan food").click()
        time.sleep(2)

        # Step 3: Tap "Photo" (photo library picker)
        print("Step 3: Tap Photo")
        driver.find_element(AppiumBy.IOS_CLASS_CHAIN,
            "**/XCUIElementTypeButton[`label == 'Photo'`]").click()
        time.sleep(3)

        # Step 4: Select the first photo (most recent in camera roll)
        print("Step 4: Select latest photo")
        cells = driver.find_elements(AppiumBy.CLASS_NAME, "XCUIElementTypeCell")
        if not cells:
            print("✗ No photos found in picker")
            return False

        cells[0].click()
        print(f"✓ Selected photo (first of {len(cells)})")
        time.sleep(3)

        # Verify Cal AI is analyzing
        buttons = driver.find_elements(AppiumBy.CLASS_NAME, "XCUIElementTypeButton")
        for btn in buttons:
            label = btn.get_attribute("label") or ""
            if "Analyzing" in label:
                print(f"✓ Cal AI is analyzing: {label}")
                break

        # Re-activate Cal AI so it stays in foreground after WDA disconnects
        driver.activate_app(CAL_AI_BUNDLE_ID)

        print("\n✓ DONE — photo uploaded to Cal AI for analysis")
        print("Keeping session open for 40 seconds...")
        time.sleep(40)
        return True

    except Exception as e:
        print(f"\n✗ Failed: {e}")
        driver.save_screenshot("error.png")
        return False
    finally:
        # Terminate WDA session without killing Cal AI
        driver.quit()


def explore():
    """Explore Cal AI's current screen UI elements."""
    driver = create_driver()
    try:
        time.sleep(2)
        print("=== Buttons ===")
        for i, btn in enumerate(driver.find_elements(AppiumBy.CLASS_NAME, "XCUIElementTypeButton")):
            label = btn.get_attribute("label") or "(none)"
            name = btn.get_attribute("name") or ""
            rect = btn.rect
            print(f"  [{i}] '{label}' name='{name}' ({rect['x']},{rect['y']} {rect['width']}x{rect['height']})")

        print("\n=== Text ===")
        for i, txt in enumerate(driver.find_elements(AppiumBy.CLASS_NAME, "XCUIElementTypeStaticText")[:20]):
            print(f"  [{i}] '{txt.get_attribute('label') or ''}'")
    finally:
        driver.quit()


if __name__ == "__main__":
    if len(sys.argv) > 1:
        cmd = sys.argv[1]
        if cmd == "explore":
            explore()
        elif cmd == "upload":
            upload_latest_photo()
        else:
            print(f"Unknown command: {cmd}")
    else:
        print("Cal AI Automation")
        print("  python cal_ai_automate.py upload   — Upload latest photo to Cal AI")
        print("  python cal_ai_automate.py explore   — Explore current UI elements")
