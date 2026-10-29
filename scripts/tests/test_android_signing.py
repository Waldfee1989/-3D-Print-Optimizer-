import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import configure_android_signing as configure
import verify_android_signing as verify


TEMPLATE = '''plugins {
    id("com.android.application")
}

android {
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
'''


class SigningTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / "project"
        self.gradle = self.project / "android/app/build.gradle.kts"
        self.gradle.parent.mkdir(parents=True)
        self.gradle.write_text(TEMPLATE)
        self.properties = self.project / "android/key.properties"
        self.fake_secret = json.dumps({
            "schema": 1, "key_alias": "test-key", "store_password": "a" * 64,
            "keystore_base64": base64.b64encode(b"test" * 400).decode(),
        })

    def test_no_secret_never_creates_fallback_key(self):
        with patch.dict(os.environ, {"ANDROID_SIGNING_CONFIG": ""}):
            with self.assertRaises(configure.SigningError):
                configure.configure(self.project, self.root)
        self.assertEqual(self.gradle.read_text(), TEMPLATE)
        self.assertFalse(self.properties.exists())
        self.assertFalse((self.root / "optimizer-android-signing").exists())

    def test_changed_flutter_template_stops_build(self):
        with self.assertRaises(configure.SigningError):
            configure.configure_gradle(TEMPLATE.replace('"debug"', '"other"'))
        with self.assertRaises(configure.SigningError):
            configure.configure_gradle(TEMPLATE + TEMPLATE)

    def test_wrong_certificate_removes_private_files(self):
        with patch.dict(os.environ, {"ANDROID_SIGNING_CONFIG": self.fake_secret}), \
                patch.object(configure.subprocess, "run", return_value=
                             subprocess.CompletedProcess([], 0, stdout=b"wrong certificate")):
            with self.assertRaises(configure.SigningError):
                configure.configure(self.project, self.root)
        self.assertFalse(self.properties.exists())
        self.assertFalse((self.root / "optimizer-android-signing").exists())
        self.assertEqual(self.gradle.read_text(), TEMPLATE)

    def test_existing_properties_are_preserved(self):
        self.properties.write_text("existing configuration")
        with patch.dict(os.environ, {"ANDROID_SIGNING_CONFIG": self.fake_secret}):
            with self.assertRaises(configure.SigningError):
                configure.configure(self.project, self.root)
        self.assertEqual(self.properties.read_text(), "existing configuration")

    def test_correct_key_uses_release_config_and_private_permissions(self):
        certificate = b"test public certificate"
        with patch.dict(os.environ, {"ANDROID_SIGNING_CONFIG": self.fake_secret}), \
                patch.object(configure, "expected_fingerprint", return_value=
                             hashlib.sha256(certificate).hexdigest()), \
                patch.object(configure.subprocess, "run", return_value=
                             subprocess.CompletedProcess([], 0, stdout=certificate)):
            configure.configure(self.project, self.root)
        text = self.gradle.read_text()
        self.assertNotIn('getByName("debug")', text)
        self.assertIn('getByName("release")', text)
        self.assertNotIn("a" * 64, text)
        self.assertEqual(self.properties.stat().st_mode & 0o777, 0o600)
        key = self.root / "optimizer-android-signing/release.p12"
        self.assertEqual(key.stat().st_mode & 0o777, 0o600)

    def test_apk_verifier_rejects_invalid_signature_and_other_signer(self):
        tool = self.root / "build-tools/36.0.0/apksigner"
        tool.parent.mkdir(parents=True)
        tool.touch()
        with patch.dict(os.environ, {"ANDROID_HOME": str(self.root)}):
            with patch.object(verify.subprocess, "run", return_value=
                              subprocess.CompletedProcess([], 1, stdout="")):
                with self.assertRaises(RuntimeError):
                    verify.verify(self.root / "app.apk")
            output = "Signer #1 certificate SHA-256 digest: " + "0" * 64 + "\n"
            with patch.object(verify.subprocess, "run", return_value=
                              subprocess.CompletedProcess([], 0, stdout=output)):
                with self.assertRaises(RuntimeError):
                    verify.verify(self.root / "app.apk")


if __name__ == "__main__":
    unittest.main()
