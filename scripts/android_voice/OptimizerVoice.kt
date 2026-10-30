package __PACKAGE__

import android.app.Activity
import android.content.Intent
import android.speech.RecognizerIntent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class OptimizerVoice(private val activity: Activity) {
    private var pending: MethodChannel.Result?=null
    private val requestCode=7263
    private fun intent()=Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        putExtra(RecognizerIntent.EXTRA_LANGUAGE,"de-DE")
        putExtra(RecognizerIntent.EXTRA_PROMPT,"Adapter beschreiben oder die fehlende Größe nennen")
        putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE,true)
        putExtra(RecognizerIntent.EXTRA_MAX_RESULTS,1)
    }
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger,"print_optimizer/voice").setMethodCallHandler { call,result ->
            if(call.method=="available") {result.success(intent().resolveActivity(activity.packageManager)!=null);return@setMethodCallHandler}
            if(call.method!="recognize") {result.notImplemented();return@setMethodCallHandler}
            if(pending!=null){result.error("BUSY","Eine Spracheingabe ist bereits offen.",null);return@setMethodCallHandler}
            try {
                val request=intent()
                if(request.resolveActivity(activity.packageManager)==null){result.error("NO_PROVIDER","Keine Android-Spracherkennung installiert.",null);return@setMethodCallHandler}
                pending=result;activity.startActivityForResult(request,requestCode)
            }catch(error:Exception){pending=null;result.error("VOICE_FAILED",error.message,null)}
        }
    }
    fun handleResult(code:Int,status:Int,data:Intent?):Boolean {
        if(code!=requestCode)return false
        val result=pending;pending=null
        if(status==Activity.RESULT_OK)result?.success(data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull())
        else result?.success(null)
        return true
    }
}
