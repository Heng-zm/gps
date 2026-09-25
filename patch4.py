import sys

with open('.github/workflows/final.yml', 'r', encoding='utf-8') as f:
    text = f.read()

text = text.replace(
    'if os.path.exists(path):\n                os.chmod(path, 0o666)\n            if os.path.exists(path):',
    'if os.path.exists(path):\n                os.system(f"chmod -R 777 {os.path.dirname(path)}")\n                os.chmod(path, 0o666)'
)

with open('.github/workflows/final.yml', 'w', encoding='utf-8') as f:
    f.write(text)
