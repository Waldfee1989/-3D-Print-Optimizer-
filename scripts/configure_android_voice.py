"""Add optional system speech UI without requesting audio permission for this app."""
from pathlib import Path
import re

def configure(project):
    activities=list((project/'android/app/src/main/kotlin').rglob('MainActivity.kt'))
    if len(activities)!=1:raise ValueError('MainActivity nicht eindeutig.')
    activity=activities[0];text=activity.read_text()
    package=re.search(r'(?m)^package ([A-Za-z_][\w.]*)\s*$',text)
    anchor='class MainActivity : FlutterActivity() {'
    register='optimizerVoice.register(flutterEngine.dartExecutor.binaryMessenger)'
    if not package or anchor not in text or 'OptimizerGeometry().register' not in text:raise ValueError('Bekannte MainActivity fehlt; benutzerdefinierten Code nicht ersetzen.')
    if register not in text:
        if 'override fun onActivityResult' in text:raise ValueError('Vorhandenen ActivityResult-Code nicht überschreiben.')
        text=text.replace(anchor,anchor+'\n    private val optimizerVoice by lazy { OptimizerVoice(this) }')
        native='OptimizerGeometry().register(flutterEngine.dartExecutor.binaryMessenger)'
        text=text.replace(native,native+'\n        '+register)
        pos=text.rfind('}')
        text=text[:pos]+'''    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        optimizerVoice.handleResult(requestCode, resultCode, data)
    }
'''+text[pos:]
        activity.write_text(text)
    kotlin=(Path(__file__).parent/'android_voice/OptimizerVoice.kt').read_text().replace('__PACKAGE__',package.group(1))
    (activity.parent/'OptimizerVoice.kt').write_text(kotlin)
    manifest=project/'android/app/src/main/AndroidManifest.xml';current=manifest.read_text()
    if 'android.speech.action.RECOGNIZE_SPEECH' not in current:
        query='''    <intent><action android:name="android.speech.action.RECOGNIZE_SPEECH" /></intent>'''
        if '<queries>' in current:current=current.replace('<queries>','<queries>\n'+query,1)
        else:current=current.replace('</manifest>','<queries>\n'+query+'\n</queries>\n</manifest>')
        manifest.write_text(current)
    print('Optionale Android-Spracheingabe eingerichtet.')

if __name__=='__main__':configure(Path.cwd())
