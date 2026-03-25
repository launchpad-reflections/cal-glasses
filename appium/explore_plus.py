"""
Find the + button in Cal AI and tap it.
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

driver = create_driver()
print("Connected!\n")
time.sleep(2)

# First go home
try:
    driver.find_element(AppiumBy.IOS_CLASS_CHAIN,
        "**/XCUIElementTypeButton[`label == 'Home'`]").click()
    time.sleep(1)
except:
    pass

# Dump ALL elements with their types and positions
print("=== ALL ELEMENTS (looking for +) ===\n")

# Check all buttons with names containing + or plus or add
for el_type in ["XCUIElementTypeButton", "XCUIElementTypeImage", "XCUIElementTypeOther"]:
    elements = driver.find_elements(AppiumBy.CLASS_NAME, el_type)
    for i, el in enumerate(elements):
        label = el.get_attribute("label") or ""
        name = el.get_attribute("name") or ""
        value = el.get_attribute("value") or ""
        rect = el.rect
        if label or name:
            print(f"  {el_type}[{i}] label='{label}' name='{name}' pos=({rect['x']},{rect['y']}) size=({rect['width']}x{rect['height']})")

# Try tapping the center-bottom area where a + FAB usually is
print("\n--- Trying to tap center bottom (FAB area) ---")
screen = driver.get_window_size()
center_x = screen['width'] // 2
bottom_y = screen['height'] - 100
print(f"Screen: {screen['width']}x{screen['height']}, tapping ({center_x}, {bottom_y})")

from appium.webdriver.common.touch_action import TouchAction
action = TouchAction(driver)
action.tap(x=center_x, y=bottom_y).perform()
time.sleep(2)

# Dump what appeared
print("\n=== AFTER TAP ===")
for i, btn in enumerate(driver.find_elements(AppiumBy.CLASS_NAME, "XCUIElementTypeButton")):
    label = btn.get_attribute("label") or "(none)"
    print(f"  Button[{i}] {label}")

driver.save_screenshot("after_plus_tap.png")
print("\nScreenshot: after_plus_tap.png")

driver.quit()
