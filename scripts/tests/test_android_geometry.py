import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('configure_geometry', ROOT / 'configure_android_geometry.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class GeometryConfigTest(unittest.TestCase):
    def test_idempotent_bridge_and_jni_escaping(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            activity = project / 'android/app/src/main/kotlin/com/example/print_optimizer/MainActivity.kt'
            activity.parent.mkdir(parents=True)
            activity.write_text('package com.example.print_optimizer\nclass MainActivity {\nOptimizerUpdater(this).register(flutterEngine.dartExecutor.binaryMessenger)\n}\n')
            gradle = project / 'android/app/build.gradle.kts'
            gradle.write_text('android {}\n')
            module.configure(project)
            module.configure(project)
            self.assertEqual(activity.read_text().count('OptimizerGeometry().register'), 1)
            self.assertEqual(gradle.read_text().count('// Optimizer native geometry'), 1)
            jni = (project / 'android/app/src/main/cpp/geometry_jni.cpp').read_text()
            self.assertIn('Java_com_example_print_1optimizer_OptimizerGeometry_nativeCut', jni)
            self.assertNotIn('__JNI_PACKAGE__', jni)
    def test_missing_known_anchor_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            activity = project / 'android/app/src/main/kotlin/MainActivity.kt'
            activity.parent.mkdir(parents=True)
            activity.write_text('package mine\nclass MainActivity { custom() }')
            with self.assertRaises(ValueError): module.configure(project)
            self.assertIn('custom()', activity.read_text())

if __name__ == '__main__': unittest.main()
