import sys
import re

with open('.github/workflows/final.yml', 'r', encoding='utf-8') as f:
    text = f.read()

new_steps = r'''      - name: 📦 Resolve SPM Dependencies
        run: |
          set -o pipefail
          xcodebuild -resolvePackageDependencies \
            -workspace ios/Runner.xcworkspace \
            -scheme Runner \
            -derivedDataPath build/DerivedData || true
            
      - name: 🩹 Patch MapboxMaps Concurrency
        run: |
          python3 - <<'PY'
          import os, re
          path = "build/DerivedData/SourcePackages/checkouts/mapbox-maps-ios/Sources/MapboxMaps/Style/StyleManager.swift"
          if os.path.exists(path):
              print(f"Found {path}, patching concurrency error...")
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

      - name: 🚀 Build iOS app'''

text = re.sub(r'      - name: .*Build iOS app', lambda m: new_steps, text)

with open('.github/workflows/final.yml', 'w', encoding='utf-8') as f:
    f.write(text)
