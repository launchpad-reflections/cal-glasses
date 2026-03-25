#!/bin/bash
# Find Cal AI's bundle ID on the connected iPhone
# Requires: brew install libimobiledevice ideviceinstaller

echo "Looking for Cal AI on connected device..."
echo ""

# Method 1: ideviceinstaller (if installed)
if command -v ideviceinstaller &> /dev/null; then
    echo "=== Apps matching 'cal' ==="
    ideviceinstaller -l 2>/dev/null | grep -i cal || echo "(no matches)"
    echo ""
fi

# Method 2: cfgutil (Apple Configurator)
if command -v cfgutil &> /dev/null; then
    echo "=== Via Apple Configurator ==="
    cfgutil list-apps 2>/dev/null | grep -i cal || echo "(not available)"
    echo ""
fi

# Method 3: pymobiledevice3
if command -v pymobiledevice3 &> /dev/null; then
    echo "=== Via pymobiledevice3 ==="
    pymobiledevice3 apps list 2>/dev/null | grep -i cal || echo "(not available)"
    echo ""
fi

echo "If none of the above worked, install libimobiledevice:"
echo "  brew install libimobiledevice ideviceinstaller"
echo ""
echo "Or install pymobiledevice3:"
echo "  pip install pymobiledevice3"
echo ""
echo "Alternative: Use Appium Inspector to connect to the device and check the app list."
