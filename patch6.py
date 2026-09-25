import sys
import re

with open('.github/workflows/final.yml', 'r', encoding='utf-8') as f:
    text = f.read()

new_code = r'''import os, re, subprocess
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
                print(f"File not found: {path}")'''

text = re.sub(r'import os, re\s*path =.*?(?=          PY)', lambda m: new_code + '\n', text, flags=re.DOTALL)

with open('.github/workflows/final.yml', 'w', encoding='utf-8') as f:
    f.write(text)
