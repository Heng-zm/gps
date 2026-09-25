import sys
import re

with open('.github/workflows/final.yml', 'r', encoding='utf-8') as f:
    text = f.read()

text = text.replace(
    'path = "build/DerivedData/SourcePackages/checkouts/mapbox-maps-ios/Sources/MapboxMaps/Style/StyleManager.swift"',
    'path = "build/DerivedData/SourcePackages/checkouts/mapbox-maps-ios/Sources/MapboxMaps/Style/StyleManager.swift"\n          if os.path.exists(path):\n              os.chmod(path, 0o666)'
)

with open('.github/workflows/final.yml', 'w', encoding='utf-8') as f:
    f.write(text)
