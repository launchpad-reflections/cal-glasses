"""
Explore Cal AI's Add flow — find the photo upload path.
"""
import time
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
    options.updated_wda_bundle_id = "com.mohulshukla.WebDriverAgentRunner"
    options.set_capability("useXctestrunFile", False)
    options.set_capability("wdaLaunchTimeout", 60000)
    options.set_capability("derivedDataPath", "/Users/mohulshukla/Library/Developer/Xcode/DerivedData/WebDriverAgent-hkuowqrpnlpmkpcvynbgcpqinsnh")
    options.set_capability("allowProvisioningUpdates", True)
    driver = webdriver.Remote(command_executor=APPIUM_SERVER, options=options)
    driver.implicitly_wait(10)
    return driver

def dump(driver, label=""):
    if label:
        print(f"\n=== {label} ===")
    print("\nButtons:")
    for i, btn in enumerate(driver.find_elements(AppiumBy.CLASS_NAME, "XCUIElementTypeButton")):
        name = btn.get_attribute("label") or btn.get_attribute("name") or "(none)"
        print(f"  [{i}] {name}")
    print("\nText:")
    for i, txt in enumerate(driver.find_elements(AppiumBy.CLASS_NAME, "XCUIElementTypeStaticText")[:20]):
        name = txt.get_attribute("label") or "(empty)"
        print(f"  [{i}] {name}")
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
        print(f">>> NOT FOUND: {label}")
        return False

driver = create_driver()
print("Connected!\n")
time.sleep(2)

# Go to home first
tap(driver, "Home")
time.sleep(1)

dump(driver, "HOME")
driver.save_screenshot("1_home.png")

# Try tapping "Add" button
print("\n--- Tapping ADD ---")
tap(driver, "Add")
dump(driver, "AFTER ADD")
driver.save_screenshot("2_after_add.png")

driver.quit()
print("Done!")
