"""
Cal AI Automation via Appium
Automates: Open Cal AI → + → Scan food → Photo → Select photo

Usage:
  python cal_ai_automate.py upload              Upload most recent photo (index 0)
  python cal_ai_automate.py upload 1            Upload most recent photo (index 0)
  python cal_ai_automate.py upload 2            Upload 2nd most recent photo (index 1)
  python cal_ai_automate.py upload 3            Upload 3rd most recent photo (index 2)
  python cal_ai_automate.py upload 2 --inclusive Upload both most recent AND 2nd most recent
  python cal_ai_automate.py upload 3 --inclusive Upload 1st, 2nd, AND 3rd most recent
  python cal_ai_automate.py explore             Explore current UI elements

Prerequisites:
  1. sudo pymobiledevice3 remote start-tunnel
  2. appium
  3. Xcode → WebDriverAgent → Cmd+U (authorize WDA)
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


def navigate_to_photo_picker(driver):
    """Navigate from home to the photo picker. Returns True if successful."""
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
    return True


def select_photo(driver, photo_number=0):
    """Select a photo from the picker grid by tapping coordinates.

    The photo grid is 3 columns. Most recent is top-left.
    Grid layout (photo_number → position):
      0 = top-left (most recent)
      1 = top-center (2nd most recent)
      2 = top-right (3rd most recent)
    """
    screen = driver.get_window_size()
    col_width = screen['width'] // 3

    # Grid starts at roughly y=310 (below search bar), each row ~175px tall
    grid_top_y = 300

    col = photo_number % 3
    row = photo_number // 3

    tap_x = col * col_width + col_width // 2
    tap_y = grid_top_y + row * 175

    ordinal = ["1st", "2nd", "3rd"][photo_number] if photo_number < 3 else f"{photo_number+1}th"
    print(f"  Tapping {ordinal} photo at ({tap_x}, {tap_y})")

    driver.execute_script("mobile: tap", {"x": tap_x, "y": tap_y})
    time.sleep(3)

    # Verify Cal AI is analyzing
    buttons = driver.find_elements(AppiumBy.CLASS_NAME, "XCUIElementTypeButton")
    for btn in buttons:
        label = btn.get_attribute("label") or ""
        if "Analyzing" in label:
            print(f"✓ Cal AI is analyzing: {label}")
            return True

    print("✓ Photo tapped (could not verify analysis status)")
    return True


def wait_and_keep_open(driver, seconds=40):
    """Keep Cal AI in foreground for a while."""
    driver.activate_app(CAL_AI_BUNDLE_ID)
    print(f"Keeping session open for {seconds} seconds...")
    time.sleep(seconds)


def upload_photo(n=1, inclusive=False):
    """
    Upload photo(s) to Cal AI.

    Args:
        n: Which photo to select (1=most recent, 2=second most recent, 3=third)
        inclusive: If True, upload all photos from 1 through n (runs multiple times)
    """
    if inclusive and n > 1:
        # Upload each photo from 1 to n
        for i in range(1, n + 1):
            print(f"\n{'='*50}")
            print(f"  Uploading photo {i} of {n}")
            print(f"{'='*50}\n")
            _upload_single(cell_index=i - 1)
            if i < n:
                print("\nWaiting 5 seconds before next upload...\n")
                time.sleep(5)
    else:
        # Upload just the nth photo
        _upload_single(cell_index=n - 1)


def _upload_single(cell_index=0):
    """Upload a single photo at the given cell index."""
    actual_cell = cell_index
    driver = create_driver()
    try:
        time.sleep(2)
        navigate_to_photo_picker(driver)

        ordinal = ["1st", "2nd", "3rd"][cell_index] if cell_index < 3 else f"{cell_index+1}th"
        print(f"Step 4: Select {ordinal} most recent photo (cell {actual_cell})")

        if not select_photo(driver, actual_cell):
            return False

        print(f"\n✓ DONE — {ordinal} most recent photo uploaded to Cal AI")
        wait_and_keep_open(driver)
        return True

    except Exception as e:
        print(f"\n✗ Failed: {e}")
        driver.save_screenshot("error.png")
        return False
    finally:
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
    args = sys.argv[1:]

    if not args:
        print("Cal AI Automation")
        print()
        print("  python cal_ai_automate.py upload              Most recent photo")
        print("  python cal_ai_automate.py upload 2            2nd most recent photo")
        print("  python cal_ai_automate.py upload 3            3rd most recent photo")
        print("  python cal_ai_automate.py upload 2 --inclusive Both 1st and 2nd")
        print("  python cal_ai_automate.py upload 3 --inclusive All three (1st, 2nd, 3rd)")
        print("  python cal_ai_automate.py explore             Explore UI elements")
        sys.exit(0)

    cmd = args[0]

    if cmd == "explore":
        explore()
    elif cmd == "upload":
        # Parse photo number (default 1)
        n = 1
        inclusive = False

        for arg in args[1:]:
            if arg == "--inclusive":
                inclusive = True
            elif arg.isdigit():
                n = int(arg)
                if n < 1:
                    n = 1
                if n > 3:
                    print("Warning: max 3 supported, capping at 3")
                    n = 3

        if inclusive:
            print(f"Uploading photos 1 through {n} (inclusive)")
        else:
            ordinal = ["1st", "2nd", "3rd"][n-1]
            print(f"Uploading {ordinal} most recent photo")

        upload_photo(n=n, inclusive=inclusive)
    else:
        print(f"Unknown command: {cmd}")
