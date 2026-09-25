import sys
import re

with open('.github/workflows/final.yml', 'r', encoding='utf-8') as f:
    text = f.read()

text = text.replace(
    '            import os, re, subprocess\n            path =',
    '              import os, re, subprocess\n              path ='
)
text = text.replace(
    '            import os, re, subprocess\n              path =',
    '              import os, re, subprocess\n              path ='
)

with open('.github/workflows/final.yml', 'w', encoding='utf-8') as f:
    f.write(text)
