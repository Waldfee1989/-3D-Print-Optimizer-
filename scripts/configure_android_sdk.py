from pathlib import Path
import re
app=Path('android/app/build.gradle.kts')
text,count=re.subn(r'compileSdk\s*=\s*(?:flutter\.compileSdkVersion|\d+)','compileSdk = 36',app.read_text())
if count!=1:raise SystemExit('compileSdk nicht eindeutig.')
app.write_text(text)
for path in (Path.home()/'.pub-cache/hosted/pub.dev').glob('file_picker-*/android/build.gradle*'):
    original=path.read_text()
    if path.suffix=='.kts':text,count=re.subn(r'compileSdk\s*=\s*\d+','compileSdk = 36',original)
    else:text,count=re.subn(r'compileSdk(?:Version)?\s*(?:=\s*)?\d+','compileSdkVersion 36',original)
    if not count:raise SystemExit('file_picker compileSdk fehlt.')
    path.write_text(text)
