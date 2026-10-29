from pathlib import Path
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import configure_android_updates as updates


class AndroidUpdateConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name)
        self.source = self.project / "android/app/src/main"
        self.activity = self.source / "kotlin/com/example/print_optimizer/MainActivity.kt"
        self.activity.parent.mkdir(parents=True)
        self.activity.write_text('''package com.example.print_optimizer
import io.flutter.embedding.android.FlutterActivity
class MainActivity : FlutterActivity()
''')
        (self.source / "AndroidManifest.xml").write_text('''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
<uses-permission android:name="android.permission.INTERNET"/>
<application android:label="Optimizer"><activity android:name=".MainActivity" android:exported="true"/></application>
</manifest>''')
        (self.project / "android/app/build.gradle.kts").write_text("plugins {}\nandroid {}\n")

    def test_provider_exposes_only_private_update_cache_and_keeps_existing_manifest(self):
        updates.configure(self.project)
        android = "{" + updates.ANDROID + "}"
        root = ET.parse(self.source / "AndroidManifest.xml").getroot()
        permissions = {p.get(android + "name") for p in root.findall("uses-permission")}
        self.assertEqual(permissions, {"android.permission.INTERNET", "android.permission.REQUEST_INSTALL_PACKAGES"})
        app = root.find("application")
        self.assertEqual(app.get(android + "label"), "Optimizer")
        self.assertIsNotNone(app.find("activity"))
        provider = app.find("provider")
        self.assertEqual(provider.get(android + "exported"), "false")
        self.assertEqual(provider.get(android + "grantUriPermissions"), "true")
        self.assertEqual(provider.get(android + "authorities"), "${applicationId}.optimizer_updates")
        paths = ET.parse(self.source / "res/xml/optimizer_update_paths.xml").getroot()
        self.assertEqual([(p.tag, p.get("path")) for p in paths], [("cache-path", "app_updates/")])
        native = (self.activity.parent / "OptimizerUpdater.kt").read_text()
        self.assertNotIn("__PACKAGE__", native)
        self.assertIn("OptimizerUpdater(this).register", self.activity.read_text())

    def test_custom_native_activity_is_never_overwritten(self):
        original = self.activity.read_text().replace("FlutterActivity()", "FlutterActivity() { fun custom() {} }")
        self.activity.write_text(original)
        with self.assertRaises(ValueError):
            updates.configure(self.project)
        self.assertEqual(self.activity.read_text(), original)


if __name__ == "__main__":
    unittest.main()
