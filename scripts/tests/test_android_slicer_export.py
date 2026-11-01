import importlib.util
from pathlib import Path
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[1]
def load(name):
    spec=importlib.util.spec_from_file_location(name,ROOT/f'configure_android_{name}.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
class SlicerExportConfigurationTest(unittest.TestCase):
    def test_export_and_voice_results_coexist_and_reconfiguration_is_idempotent(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);activity=root/'android/app/src/main/kotlin/MainActivity.kt';activity.parent.mkdir(parents=True)
            activity.write_text('package com.example\nclass MainActivity : FlutterActivity() {\n override fun configureFlutterEngine(flutterEngine: FlutterEngine) {\n OptimizerGeometry().register(flutterEngine.dartExecutor.binaryMessenger)\n }\n}\n')
            (root/'android/app/src/main/AndroidManifest.xml').write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application /></manifest>')
            (root/'android/app/build.gradle.kts').write_text('')
            load('voice').configure(root)
            binary=root/'engine';binary.write_bytes(b'fake-binary-only-for-configuration-test')
            module=load('slicer');module.configure(root,binary);module.configure(root,binary)
            text=activity.read_text()
            self.assertEqual(text.count('optimizerSlicer.register('),1)
            self.assertEqual(text.count('optimizerSlicer.handleResult('),1)
            self.assertEqual(text.count('optimizerVoice.handleResult('),1)
            self.assertEqual(text.count('super.onActivityResult('),1)
            self.assertIn('private val optimizerSlicer',text)
            self.assertEqual((root/'android/app/build.gradle.kts').read_text().count('// Optimizer standalone slicer'),1)
