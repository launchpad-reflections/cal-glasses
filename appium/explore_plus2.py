"""
Tap the + (plus) FAB and explore what opens.
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
        aname = btn.get_attribute("name") or ""
        print(f"  [{i}] label='{name}' name='{aname}'")
    print("\nText:")
    for i, txt in enumerate(driver.find_elements(AppiumBy.CLASS_NAME, "XCUIElementTypeStaticText")[:15]):
        name = txt.get_attribute("label") or "(empty)"
        print(f"  [{i}] {name}")
    print()

driver = create_driver()
print("Connected!\n")
time.sleep(2)

# Go home
try:
    driver.find_element(AppiumBy.ACCESSIBILITY_ID, "Home").click()
    time.sleep(1)
except:
    pass

# Tap the + button (name='plus')
print("--- Tapping + (plus) button ---")
try:
    plus_btn = driver.find_element(AppiumBy.ACCESSIBILITY_ID, "plus")
    plus_btn.click()
    print(">>> Tapped +")
    time.sleep(2)
except Exception as e:
    print(f">>> Failed: {e}")

dump(driver, "AFTER + TAP")
driver.save_screenshot("after_plus.png")

driver.quit()
print("Done!")
