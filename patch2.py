import sys
import re

with open('.github/workflows/final.yml', 'r', encoding='utf-8') as f:
    text = f.read()

text = re.sub(r'\s*- name: .*Select Xcode 15.2\s*uses: maxim-lobanov/setup-xcode@v1\s*with:\s*xcode-version: \'15.2.0\'', '', text)

with open('.github/workflows/final.yml', 'w', encoding='utf-8') as f:
    f.write(text)
