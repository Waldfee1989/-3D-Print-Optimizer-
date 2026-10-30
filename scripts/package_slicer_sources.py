"""Package the exact modified engine and dependencies alongside a release APK."""
from pathlib import Path
import json
import subprocess
import sys
import urllib.request
import zipfile
from build_slicer_engine import ENGINE,STB,CURA

output=Path(sys.argv[1]).resolve()
if not (output/'source/src/main.cpp').is_file() or not (output/'deps/stb/stb_image.h').is_file():raise SystemExit('Built source trees missing')
resource=output/'resources';resource.mkdir(exist_ok=True)
for name in ['fdmprinter.def.json','fdmextruder.def.json']:
    with urllib.request.urlopen(f'https://raw.githubusercontent.com/Ultimaker/Cura/{CURA}/resources/definitions/{name}',timeout=60) as response:
        (resource/name).write_bytes(response.read())
subprocess.run(['git','archive','--format=tar','-o',str(output/'PrintOptimizer-source.tar'),'HEAD'],check=True)
revision=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
info={'engine':ENGINE,'stb':STB,'cura_definitions':CURA,'app_commit':revision,'engine_version':'4.13.1-optimizer'}
(output/'source-info.json').write_text(json.dumps(info,indent=2))
readme='''CuraEngine 4.13.1, separate command-line component (AGPLv3 or later).
The accompanying source tree includes all Print Optimizer platform adaptations.
Clipper, RapidJSON and stb notices are retained in their source trees and the app.
Cura definition resources are LGPLv3; both LGPL and GPL text are included.

To rebuild the engine, extract this archive, install Python 3.12+, CMake and a
C++17 compiler, then run:
  python3 build_slicer_engine.py --output engine
For Android ARM64, install Android NDK, set ANDROID_NDK_HOME and run:
  python3 build_slicer_engine.py --output engine --android
The source/dependency directories are already present; they are not downloaded.
For the Flutter app, extract PrintOptimizer-source.tar and follow its workflows.
The app source archive and resolved pubspec.lock are from this same build.
No license of the entire Print Optimizer repository has been changed.
'''
with zipfile.ZipFile(output/'CuraEngine-source.zip','w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as package:
    for folder,inside in [(output/'source','engine/source'),(output/'deps/stb','engine/deps/stb'),(resource,'resources')]:
        for path in folder.rglob('*'):
            if path.is_file():package.write(path,str(Path(inside)/path.relative_to(folder)))
    for source,name in [(Path('scripts/build_slicer_engine.py'),'build_slicer_engine.py'),(Path('scripts/package_slicer_sources.py'),'package_slicer_sources.py'),
        (output/'platform-patch.json','engine/platform-patch.json'),(output/'PrintOptimizer-source.tar','PrintOptimizer-source.tar'),
        (output/'source-info.json','source-info.json')]:package.write(source,name)
    for source in Path('assets/licenses').glob('*.txt'):package.write(source,'licenses/'+source.name)
    if Path('pubspec.lock').exists():package.write('pubspec.lock','pubspec.lock')
    package.writestr('REPRODUCE.txt',readme)
print('Exact engine sources packaged: '+str(output/'CuraEngine-source.zip'))
