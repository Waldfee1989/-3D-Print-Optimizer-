"""Install the app-specific Android update bridge after flutter create."""

from pathlib import Path
import re
import xml.etree.ElementTree as ET

ANDROID = "http://schemas.android.com/apk/res/android"
ET.register_namespace("android", ANDROID)


def configure(project):
    source = project / "android/app/src/main"
    activities = list((source / "kotlin").rglob("MainActivity.kt"))
    if len(activities) != 1:
        raise ValueError("MainActivity nicht eindeutig gefunden.")
    activity = activities[0]
    original = activity.read_text()
    match = re.search(r"(?m)^package ([A-Za-z_][\w.]*)\s*$", original)
    if not match:
        raise ValueError("Android-Paketname fehlt.")
    package = match.group(1)
    # Refuse to overwrite custom native app code.
    if not re.search(r"class MainActivity\s*:\s*FlutterActivity\(\)(?:\s*\{\s*\})?\s*$", original):
        raise ValueError("Unerwartete MainActivity; manuell pruefen.")
    activity.write_text(f'''package {package}

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {{
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {{
        super.configureFlutterEngine(flutterEngine)
        OptimizerUpdater(this).register(flutterEngine.dartExecutor.binaryMessenger)
    }}
}}
''')
    template = Path(__file__).with_name("android_update") / "OptimizerUpdater.kt"
    (activity.parent / "OptimizerUpdater.kt").write_text(
        template.read_text().replace("__PACKAGE__", package))

    manifest = source / "AndroidManifest.xml"
    tree = ET.parse(manifest)
    root = tree.getroot()
    permission = "android.permission.REQUEST_INSTALL_PACKAGES"
    if not any(e.get(f"{{{ANDROID}}}name") == permission for e in root.findall("uses-permission")):
        ET.SubElement(root, "uses-permission", {f"{{{ANDROID}}}name": permission})
    app = root.find("application")
    if app is None:
        raise ValueError("Android-Anwendung fehlt.")
    # Stock Kobra LAN uploads use HTTP. The Dart client restricts requests to
    # a literal private printer IPv4 and validates the returned upload origin.
    app.set(f"{{{ANDROID}}}usesCleartextTraffic", "true")
    provider = ET.SubElement(app, "provider", {
        f"{{{ANDROID}}}name": f"{package}.OptimizerUpdateFileProvider",
        f"{{{ANDROID}}}authorities": "${applicationId}.optimizer_updates",
        f"{{{ANDROID}}}exported": "false",
        f"{{{ANDROID}}}grantUriPermissions": "true",
    })
    ET.SubElement(provider, "meta-data", {
        f"{{{ANDROID}}}name": "android.support.FILE_PROVIDER_PATHS",
        f"{{{ANDROID}}}resource": "@xml/optimizer_update_paths",
    })
    ET.indent(tree)
    tree.write(manifest, encoding="unicode")
    xml = source / "res/xml/optimizer_update_paths.xml"
    xml.parent.mkdir(parents=True, exist_ok=True)
    xml.write_text('''<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <cache-path name="updates" path="app_updates/" />
</paths>
''')
    gradle = project / "android/app/build.gradle.kts"
    gradle.write_text(gradle.read_text() + '''
dependencies {
    implementation("androidx.core:core:1.15.0")
}
''')
    print("Android-Updateinstallation eingerichtet.")


if __name__ == "__main__":
    configure(Path.cwd())
