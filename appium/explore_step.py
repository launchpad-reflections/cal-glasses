"""
Step-by-step Cal AI exploration.
Tap a button, see what appears next.
"""
import time
import sys
from appium import webdriver
from appium.options.ios import XCUITestOptions
from appium.webdriver.common.appiumby import AppiumBy
from config import DEVICE_UDID, DEVICE_NAME, TEAM_ID, CAL_AI_BUNDLE_ID, APPIUM_SERVER

def create_driver():
    options = XCUITestOptions()
    options.platform_name = "iOS"
    options.device_name = DEVICE_NAME
    options.udid = DEVICE_UDID
    options.bundle_id = CAL_AI_BUNDLE_ID
    options.xcode_org_id = TEAM_ID
    options.xcode_signing_id = "iPhone Developer"
    options.auto_accept_alerts = True
    options.new_command_timeout = 300
    options.show_xcode_log = True
    options.updated_wda_bundle_id = "com.mohulshukla.WebDriverAgentRunner"
    options.set_capability("useXctestrunFile", False)
    options.set_capability("wdaLaunchTimeout", 60000)
    options.set_capability("derivedDataPath", "/Users/mohulshukla/Library/Developer/Xcode/DerivedData/WebDriverAgent-hkuowqrpnlpmkpcvynbgcpqinsnh")
    options.set_capability("allowProvisioningUpdates", True)

    driver = webdriver.Remote(command_executor=APPIUM_SERVER, options=options)
    driver.implicitly_wait(10)
    return driver

def dump_ui(driver):
    print("\n--- Buttons ---")
    for i, btn in enumerate(driver.find_elements(AppiumBy.CLASS_NAME, "XCUIElementTypeButton")):
        label = btn.get_attribute("label") or btn.get_attribute("name") or "(none)"
        print(f"  [{i}] {label}")

    print("\n--- Text ---")
    for i, txt in enumerate(driver.find_elements(AppiumBy.CLASS_NAME, "XCUIElementTypeStaticText")[:25]):
        label = txt.get_attribute("label") or "(empty)"
        print(f"  [{i}] {label}")

    print("\n--- Cells ---")
    for i, cell in enumerate(driver.find_elements(AppiumBy.CLASS_NAME, "XCUIElementTypeCell")[:10]):
        label = cell.get_attribute("label") or "(none)"
        print(f"  [{i}] {label}")
    print()

def tap(driver, label):
    try:
        el = driver.find_element(
            AppiumBy.IOS_CLASS_CHAIN,
            f"**/XCUIElementTypeButton[`label CONTAINS[c] '{label}'`]"
        )
        el.click()
        print(f">>> Tapped: {label}")
        time.sleep(2)
        return True
    except:
        print(f">>> Could not find: {label}")
        return False

driver = create_driver()
print("Connected! Cal AI should be open.\n")
time.sleep(2)

# Step 1: See home screen
print("=== HOME SCREEN ===")
dump_ui(driver)

# Step 2: Tap "Scan food"
print("=== Tapping 'Scan food' ===")
tap(driver, "Scan food")
dump_ui(driver)

# Take screenshot
driver.save_screenshot("after_scan_food.png")
print("Screenshot: after_scan_food.png")

driver.quit()
