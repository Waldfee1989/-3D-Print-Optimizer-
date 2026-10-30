import importlib.util
from pathlib import Path
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('voice',ROOT/'configure_android_voice.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class VoiceConfigurationTest(unittest.TestCase):
    def test_preserves_native_bridges_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);activity=root/'android/app/src/main/kotlin/com/example/MainActivity.kt';activity.parent.mkdir(parents=True)
            activity.write_text('package com.example\nclass MainActivity : FlutterActivity() {\n override fun configureFlutterEngine(flutterEngine: FlutterEngine) {\n OptimizerGeometry().register(flutterEngine.dartExecutor.binaryMessenger)\n OptimizerSlicer(this).register(flutterEngine.dartExecutor.binaryMessenger)\n }\n}\n')
            manifest=root/'android/app/src/main/AndroidManifest.xml';manifest.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application /></manifest>')
            module.configure(root);module.configure(root);text=activity.read_text()
            self.assertEqual(text.count('optimizerVoice.register'),1);self.assertIn('super.onActivityResult',text);self.assertIn('OptimizerSlicer(this)',text)
            self.assertEqual(manifest.read_text().count('android.speech.action.RECOGNIZE_SPEECH'),1)
            self.assertNotIn('RECORD_AUDIO',manifest.read_text())
    def test_custom_activity_result_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);activity=root/'android/app/src/main/kotlin/MainActivity.kt';activity.parent.mkdir(parents=True)
            text='package com.example\nclass MainActivity : FlutterActivity() {\n OptimizerGeometry().register(x)\n override fun onActivityResult() {}\n}'
            activity.write_text(text)
            with self.assertRaises(ValueError):module.configure(root)
            self.assertEqual(activity.read_text(),text)
if __name__=='__main__':unittest.main()
