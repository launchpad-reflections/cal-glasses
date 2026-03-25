"""
FULL Cal AI automation: + → Scan food → Photo → select latest → see result
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

driver = create_driver()
print("Connected!\n")
time.sleep(2)

# Go home first
try:
    driver.find_element(AppiumBy.ACCESSIBILITY_ID, "Home").click()
    time.sleep(1)
except:
    pass

# Step 1: Tap +
print("Step 1: Tap +")
driver.find_element(AppiumBy.ACCESSIBILITY_ID, "plus").click()
time.sleep(1)

# Step 2: Tap Scan food
print("Step 2: Tap Scan food")
driver.find_element(AppiumBy.ACCESSIBILITY_ID, "Scan food").click()
time.sleep(2)

# Step 3: Tap Photo (photo library)
print("Step 3: Tap Photo")
driver.find_element(AppiumBy.IOS_CLASS_CHAIN,
    "**/XCUIElementTypeButton[`label == 'Photo'`]").click()
time.sleep(3)

# Step 4: Select the first photo (most recent)
print("Step 4: Select latest photo")
cells = driver.find_elements(AppiumBy.CLASS_NAME, "XCUIElementTypeCell")
print(f"  Found {len(cells)} cells")
if cells:
    cells[0].click()
    print("  Tapped first cell")
    time.sleep(3)
else:
    print("  No cells found!")

# See what happened
dump(driver, "AFTER PHOTO SELECTION")
driver.save_screenshot("5_after_select.png")

print("\nDone! Check 5_after_select.png")
driver.quit()
