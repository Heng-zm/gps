#!/bin/bash
set -e

echo "======================================"
echo "    Clean iOS IPA Build Script"
echo "======================================"

echo "[1/3] Cleaning project..."
flutter clean
flutter pub get

echo "[2/3] Building iOS IPA..."
# We use --no-codesign because we are just packaging the IPA for OTA/sideloading
flutter build ipa --release --no-codesign

echo "[3/3] Build completed successfully!"
echo "Your IPA is located at: build/ios/ipa/"
