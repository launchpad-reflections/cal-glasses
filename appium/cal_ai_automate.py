"""
Cal AI Automation via Appium
Automates: Open Cal AI → Add Food → Select latest photo → Confirm

Usage:
  1. Start Appium server: appium
  2. Run: python cal_ai_automate.py

Prerequisites:
  - Appium installed with XCUITest driver
  - iPhone connected via USB
  - Cal AI installed on iPhone
  - config.py filled in with TEAM_ID and CAL_AI_BUNDLE_ID
"""

import time
import sys
from appium import webdriver
from appium.options.ios import XCUITestOptions
from appium.webdriver.common.appiumby import AppiumBy

from config import DEVICE_UDID, DEVICE_NAME, TEAM_ID, CAL_AI_BUNDLE_ID, APPIUM_SERVER


def create_driver():
    """Create an Appium driver connected to the real iPhone."""
    if not TEAM_ID:
        print("ERROR: Set TEAM_ID in config.py first!")
        print("Find it in Xcode → Signing & Capabilities → Team")
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

    print(f"Connecting to device {DEVICE_NAME} ({DEVICE_UDID[:8]}...)")
    print(f"Target app: {CAL_AI_BUNDLE_ID}")
    print(f"Appium server: {APPIUM_SERVER}")
    print()

    driver = webdriver.Remote(
        command_executor=APPIUM_SERVER,
        options=options,
    )
    driver.implicitly_wait(10)
    print("✓ Connected to device")
    return driver


def explore_ui(driver):
    """
    Print the current screen's UI hierarchy.
    Use this to figure out Cal AI's button labels and layout.
    """
    print("\n=== Current Screen UI Elements ===\n")

    # Get all interactable elements
    buttons = driver.find_elements(AppiumBy.CLASS_NAME, "XCUIElementTypeButton")
    print(f"Buttons ({len(buttons)}):")
    for i, btn in enumerate(buttons):
        label = btn.get_attribute("label") or btn.get_attribute("name") or "(no label)"
        print(f"  [{i}] {label}")

    static_texts = driver.find_elements(AppiumBy.CLASS_NAME, "XCUIElementTypeStaticText")
    print(f"\nText elements ({len(static_texts)}):")
    for i, txt in enumerate(static_texts[:20]):  # Cap at 20
        label = txt.get_attribute("label") or "(empty)"
        print(f"  [{i}] {label}")

    images = driver.find_elements(AppiumBy.CLASS_NAME, "XCUIElementTypeImage")
    print(f"\nImages: {len(images)}")

    cells = driver.find_elements(AppiumBy.CLASS_NAME, "XCUIElementTypeCell")
    print(f"Cells: {len(cells)}")

    print("\n=== End UI Dump ===\n")


def tap_element_by_label(driver, label, element_type="XCUIElementTypeButton"):
    """Find and tap an element by its label text."""
    try:
        element = driver.find_element(
            AppiumBy.IOS_CLASS_CHAIN,
            f"**/{element_type}[`label CONTAINS[c] '{label}'`]"
        )
        element.click()
        print(f"✓ Tapped: {label}")
        time.sleep(1)
        return True
    except Exception as e:
        print(f"✗ Could not find '{label}': {e}")
        return False


def select_latest_photo(driver):
    """Select the most recent photo from the photo picker."""
    time.sleep(2)  # Wait for picker to load

    # Try to find photo cells in collection view
    try:
        cells = driver.find_elements(AppiumBy.CLASS_NAME, "XCUIElementTypeCell")
        if cells:
            # Most recent photo is typically first
            cells[0].click()
            print(f"✓ Selected photo (first of {len(cells)} cells)")
            time.sleep(1)
            return True
    except Exception as e:
        print(f"✗ Failed to select photo: {e}")

    return False


def run_exploration():
    """
    Step 1: Just open Cal AI and explore the UI.
    Run this first to understand the app's layout.
    """
    driver = create_driver()
    try:
        print("\nCal AI should be open now. Exploring UI...\n")
        time.sleep(3)
        explore_ui(driver)

        input("\nPress Enter to explore the next screen (tap around first)...")
        explore_ui(driver)

    finally:
        driver.quit()
        print("✓ Session closed")


def run_add_food(photo_already_saved=True):
    """
    Step 2: Automate the full Add Food flow.
    Assumes the food photo is already in the camera roll.

    NOTE: Button labels below are PLACEHOLDERS.
    Run run_exploration() first to find the real labels,
    then update these strings.
    """
    driver = create_driver()
    try:
        print("\nStarting Cal AI food logging automation...\n")
        time.sleep(3)

        # Step 1: Find and tap "Add" or "+" button
        # UPDATE THESE LABELS after running explore_ui()
        found = (
            tap_element_by_label(driver, "Add") or
            tap_element_by_label(driver, "plus") or
            tap_element_by_label(driver, "Log") or
            tap_element_by_label(driver, "camera")
        )
        if not found:
            print("Could not find Add button. Exploring UI...")
            explore_ui(driver)
            return

        time.sleep(1)

        # Step 2: Tap "Photo" or "Camera Roll" option
        found = (
            tap_element_by_label(driver, "Photo") or
            tap_element_by_label(driver, "Camera Roll") or
            tap_element_by_label(driver, "Choose Photo") or
            tap_element_by_label(driver, "Gallery")
        )
        if not found:
            print("Could not find Photo option. Exploring UI...")
            explore_ui(driver)
            return

        time.sleep(2)

        # Step 3: Select the most recent photo
        if not select_latest_photo(driver):
            print("Could not select photo. Exploring UI...")
            explore_ui(driver)
            return

        # Step 4: Confirm / Submit
        found = (
            tap_element_by_label(driver, "Done") or
            tap_element_by_label(driver, "Use") or
            tap_element_by_label(driver, "Select") or
            tap_element_by_label(driver, "Add") or
            tap_element_by_label(driver, "Confirm")
        )

        # Take a screenshot of the result
        driver.save_screenshot("result.png")
        print("✓ Screenshot saved: result.png")

        print("\n✓ AUTOMATION COMPLETE")

    except Exception as e:
        print(f"\n✗ AUTOMATION FAILED: {e}")
        driver.save_screenshot("error.png")
        raise
    finally:
        driver.quit()
        print("✓ Session closed")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "explore":
        run_exploration()
    else:
        print("Usage:")
        print("  python cal_ai_automate.py explore   — Explore Cal AI's UI (run first!)")
        print("  python cal_ai_automate.py run       — Run the full automation")
        print()

        if len(sys.argv) > 1 and sys.argv[1] == "run":
            run_add_food()
        else:
            print("Start with 'explore' to map Cal AI's UI elements.")
