#!/bin/bash
# Cal Reflections — Appium Setup Script
# Run this once to install all dependencies

set -e

echo "=== Installing Appium ==="
npm install -g appium

echo ""
echo "=== Installing XCUITest Driver ==="
appium driver install xcuitest

echo ""
echo "=== Installing Python dependencies ==="
pip install -r requirements.txt

echo ""
echo "=== Verifying installation ==="
echo "Appium version: $(appium -v)"
echo "Drivers installed:"
appium driver list --installed

echo ""
echo "=== Setup complete! ==="
echo ""
echo "Next steps:"
echo "1. Find your Apple Team ID in Xcode (Signing & Capabilities → Team)"
echo "2. Update TEAM_ID in config.py"
echo "3. Find Cal AI's bundle ID: run ./find_bundle_id.sh"
echo "4. Start Appium: appium"
echo "5. Run the automation: python cal_ai_automate.py"
