#!/bin/bash
set -e

echo "🚀 Starting iOS IPA Build Process..."

# 1. Clean Flutter & iOS
echo "🧹 Cleaning previous builds..."
flutter clean
flutter pub get
cd ios
rm -rf Pods
rm -f Podfile.lock
cd ..

# 2. Build iOS (No Codesign) to fetch CocoaPods and SPM dependencies
echo "📦 Fetching dependencies via flutter build ios..."
flutter build ios --no-codesign --release || true

# 3. Explicitly resolve SPM dependencies using xcodebuild
echo "📦 Resolving Swift Package Manager dependencies..."
xcodebuild -resolvePackageDependencies \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -derivedDataPath build/DerivedData || true

# 4. Patch MapboxMaps Concurrency Error
echo "🩹 Patching MapboxMaps Concurrency Error..."
python3 - <<'PY'
import os, re, subprocess
path = "build/DerivedData/SourcePackages/checkouts/mapbox-maps-ios/Sources/MapboxMaps/Style/StyleManager.swift"
if os.path.exists(path):
    print(f"Found {path}, patching concurrency error...")
    subprocess.run(["chmod", "-R", "777", os.path.dirname(path)])
    os.chmod(path, 0o666)
    with open(path, "r", encoding="utf-8") as f:
        code = f.read()
    
    code = re.sub(
        r'var cancelable:\s*Cancelable!',
        r'class _CancelableWrapper : @unchecked Sendable { var c: Cancelable? }; let _wrapper = _CancelableWrapper()',
        code
    )
    code = re.sub(
        r'\bcancelable\b(?=\s*(?:=|\?))',
        r'_wrapper.c',
        code
    )
    
    with open(path, "w", encoding="utf-8") as f:
        f.write(code)
    print("Patch applied successfully.")
else:
    print(f"File not found: {path}")
PY

# 5. Build Xcode Archive
echo "🔨 Building Xcode Archive..."
xcodebuild archive \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build/DerivedData \
  -archivePath build/ios/Runner.xcarchive \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  IPHONEOS_DEPLOYMENT_TARGET=14.0

# 6. Export IPA from Archive (requires an ExportOptions.plist in a real signed environment, but for unsigned we package the .app)
echo "📦 Packaging IPA..."
APP_PATH=$(find build/ios/Runner.xcarchive -name "Runner.app" | head -n 1)
if [ -n "$APP_PATH" ]; then
  mkdir -p build/ios/Payload
  cp -r "$APP_PATH" build/ios/Payload/
  cd build/ios
  zip -qr TrackPro-AI.ipa Payload
  rm -rf Payload
  echo "✅ Successfully built: build/ios/TrackPro-AI.ipa"
else
  echo "❌ Failed to find Runner.app inside xcarchive."
  exit 1
fi
