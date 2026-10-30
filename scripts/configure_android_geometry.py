"""Add the local geometry bridge after the existing Android update bridge."""
from pathlib import Path
import re
import shutil


def configure(project):
    source = project / 'android/app/src/main'
    activities = list((source / 'kotlin').rglob('MainActivity.kt'))
    if len(activities) != 1:
        raise ValueError('MainActivity nicht eindeutig.')
    activity = activities[0]
    text = activity.read_text()
    match = re.search(r'(?m)^package ([A-Za-z_][\w.]*)\s*$', text)
    anchor = 'OptimizerUpdater(this).register(flutterEngine.dartExecutor.binaryMessenger)'
    if not match or anchor not in text:
        raise ValueError('Vorbereitete Update-Bridge fehlt; benutzerdefinierten Code nicht ersetzen.')
    package = match.group(1)
    register = 'OptimizerGeometry().register(flutterEngine.dartExecutor.binaryMessenger)'
    if register not in text:
        activity.write_text(text.replace(anchor, anchor + '\n        ' + register))
    root = Path(__file__).resolve().parent
    kotlin = (root / 'android_geometry/OptimizerGeometry.kt').read_text().replace('__PACKAGE__', package)
    (activity.parent / 'OptimizerGeometry.kt').write_text(kotlin)
    cpp = source / 'cpp'
    cpp.mkdir(parents=True, exist_ok=True)
    for path in (root.parent / 'native/model_geometry').iterdir():
        if path.is_file():
            shutil.copy2(path, cpp / path.name)
    jni = cpp / 'geometry_jni.cpp'
    jni.write_text(jni.read_text().replace('__JNI_PACKAGE__', package.replace('_', '_1').replace('.', '_')))
    gradle = project / 'android/app/build.gradle.kts'
    current = gradle.read_text()
    (project / 'android/app/optimizer-geometry.pro').write_text(f'-keep class {package}.OptimizerGeometry {{ *; }}\n')
    marker = '// Optimizer native geometry'
    if marker not in current:
        gradle.write_text(current + '''
// Optimizer native geometry
android {
    buildTypes.getByName("release") { proguardFiles(file("optimizer-geometry.pro")) }
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }
    defaultConfig {
        externalNativeBuild {
            cmake { arguments += listOf("-DANDROID_STL=c++_static") }
        }
    }
}
''')
    print('Lokale Android-Geometrie eingerichtet.')


if __name__ == '__main__':
    configure(Path.cwd())
