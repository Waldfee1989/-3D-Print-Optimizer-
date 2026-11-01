"""Package the standalone slicer executable; never link it into the app/JNI library."""
from pathlib import Path
import re
import shutil
import sys

def configure(project,binary,abi='arm64-v8a'):
    activities=list((project/'android/app/src/main/kotlin').rglob('MainActivity.kt'))
    if len(activities)!=1:raise ValueError('MainActivity nicht eindeutig.')
    activity=activities[0];text=activity.read_text()
    package=re.search(r'(?m)^package ([A-Za-z_][\w.]*)\s*$',text)
    anchor='OptimizerGeometry().register(flutterEngine.dartExecutor.binaryMessenger)'
    register='optimizerSlicer.register(flutterEngine.dartExecutor.binaryMessenger)'
    if not package or anchor not in text:raise ValueError('Bekannte Geometrie-Bridge fehlt; Aktivität nicht überschreiben.')
    if register not in text:
        class_anchor='class MainActivity : FlutterActivity() {'
        result_anchor='        optimizerVoice.handleResult(requestCode, resultCode, data)'
        if class_anchor not in text or result_anchor not in text:raise ValueError('Bekannte ActivityResult-Weiterleitung fehlt.')
        text=text.replace(class_anchor,class_anchor+'\n    private val optimizerSlicer by lazy { OptimizerSlicer(this) }')
        text=text.replace(anchor,anchor+'\n        '+register)
        text=text.replace(result_anchor,result_anchor+'\n        optimizerSlicer.handleResult(requestCode, resultCode, data)')
        activity.write_text(text)
    source=Path(__file__).parent/'android_slicer/OptimizerSlicer.kt'
    (activity.parent/'OptimizerSlicer.kt').write_text(source.read_text().replace('__PACKAGE__',package.group(1)))
    if not binary.is_file():raise ValueError('Slicer-Binary fehlt.')
    if abi not in ('arm64-v8a','x86_64'):raise ValueError('Unsupported slicer ABI')
    destination=project/f'android/app/src/main/jniLibs/{abi}/liboptimizer_slicer.so'
    destination.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(binary,destination)
    gradle=project/'android/app/build.gradle.kts';current=gradle.read_text()
    if '// Optimizer standalone slicer' not in current:
        gradle.write_text(current+'''
// Optimizer standalone slicer: extract executable into the installed, immutable
// native library directory. Keep its ELF entry point / program headers intact.
android {
    packaging {
        jniLibs {
            useLegacyPackaging = true
            keepDebugSymbols += "**/liboptimizer_slicer.so"
        }
    }
}
''')
    print('Lokaler Slicer eingerichtet.')

if __name__=='__main__':configure(Path.cwd(),Path(sys.argv[1]),sys.argv[2] if len(sys.argv)>2 else 'arm64-v8a')
