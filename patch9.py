import sys
import re

with open('.github/workflows/final.yml', 'r', encoding='utf-8') as f:
    text = f.read()

# Replace the whole block!
import_str = r'''    import os, re, subprocess
              path ='''

# Let's just find the entire python3 - <<'PY' block and replace it cleanly!
# We can just match from python3 - <<'PY' up to PY

new_block = r'''          run: |
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
            PY'''

text = re.sub(r'          run: \|\n            python3 - <<\'PY\'.*?            PY', lambda m: new_block, text, flags=re.DOTALL)

with open('.github/workflows/final.yml', 'w', encoding='utf-8') as f:
    f.write(text)
