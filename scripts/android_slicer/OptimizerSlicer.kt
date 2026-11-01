package __PACKAGE__

import android.app.Activity
import android.content.Intent
import android.provider.DocumentsContract
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

class OptimizerSlicer(private val activity: Activity) {
    private val worker=Executors.newSingleThreadExecutor()
    private val timer=Executors.newSingleThreadScheduledExecutor()
    private val main=Handler(Looper.getMainLooper())
    private val process=AtomicReference<Process?>(null)
    private val running=AtomicBoolean(false)
    private val cancelled=AtomicBoolean(false)
    private var exportResult: MethodChannel.Result?=null
    private var exportSource: File?=null
    private val exportRequest=47821
    fun handleResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if(requestCode!=exportRequest)return
        val reply=exportResult?:return
        val source=exportSource
        val uri=data?.data
        if(resultCode!=Activity.RESULT_OK||uri==null||source==null){
            exportResult=null;exportSource=null;reply.success(false);return
        }
        worker.execute {
            try {
                require(uri.scheme=="content") { "Ungültiger Speicherort." }
                val expected=source.length()
                require(expected in 1..536870912L) { "Ungültige Druckdateigröße." }
                activity.contentResolver.openOutputStream(uri,"w").use { output ->
                    require(output!=null) { "Speicherort nicht beschreibbar." }
                    source.inputStream().use { input ->
                        val copied=input.copyTo(output,65536)
                        require(copied==expected) { "Die Druckdatei wurde nicht vollständig gespeichert." }
                    }
                    output.flush()
                }
                main.post{exportResult=null;exportSource=null;reply.success(true)}
            } catch(error: Exception) {
                try { DocumentsContract.deleteDocument(activity.contentResolver,uri) }catch(_: Exception){}
                main.post{exportResult=null;exportSource=null;reply.error("EXPORT_FAILED","G-Code konnte nicht vollständig gespeichert werden. Speicherplatz prüfen.",null)}
            }
        }
    }
    private fun path(value: String?): File {
        require(value!=null) { "Slicer-Dateipfad fehlt." }
        val file=File(value).canonicalFile
        require(file.path.startsWith(activity.cacheDir.canonicalPath+File.separator)) { "Slicer-Datei liegt außerhalb des Arbeitsordners." }
        return file
    }
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger,"print_optimizer/slicer").setMethodCallHandler { call,result ->
            if(call.method=="export") {
                if(exportResult!=null){result.error("BUSY","Eine Datei wird bereits gespeichert.",null);return@setMethodCallHandler}
                try {
                    val source=path(call.argument<String>("path"))
                    require(source.isFile&&source.extension=="gcode"&&source.length() in 1..536870912L) { "Ungültige Druckdatei." }
                    val name=(call.argument<String>("name")?:"Druckmodell.gcode").replace(Regex("[^A-Za-z0-9._-]"),"_").take(160)
                    exportSource=source;exportResult=result
                    val intent=Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE);type="application/octet-stream"
                        putExtra(Intent.EXTRA_TITLE,name)
                    }
                    activity.startActivityForResult(intent,exportRequest)
                } catch(error: Exception) {
                    exportResult=null;exportSource=null;result.error("EXPORT_FAILED","Der Speicherdialog konnte nicht geöffnet werden.",null)
                }
                return@setMethodCallHandler
            }
            if(call.method=="cancel") {
                cancelled.set(true);process.get()?.destroy();result.success(null)
                return@setMethodCallHandler
            }
            if(call.method!="slice") { result.notImplemented();return@setMethodCallHandler }
            if(!running.compareAndSet(false,true)) {result.error("BUSY","Ein Slicer-Lauf ist bereits aktiv.",null);return@setMethodCallHandler}
            cancelled.set(false)
            val model: File;val settings: File;val output: File
            try {
                model=path(call.argument<String>("model"));settings=path(call.argument<String>("settings"));output=path(call.argument<String>("output"))
                require(model.isFile&&model.length()<=105000000&&settings.isFile&&settings.length()<=1048576) { "Slicer-Eingabe fehlt oder ist zu groß." }
            } catch(error: Exception) {running.set(false);result.error("INVALID_INPUT",error.message,null);return@setMethodCallHandler}
            worker.execute {
                var watchdog: java.util.concurrent.ScheduledFuture<*>?=null
                val timedOut=AtomicBoolean(false)
                try {
                    if(cancelled.get())throw InterruptedException("Berechnung abgebrochen.")
                    val engine=File(activity.applicationInfo.nativeLibraryDir,"liboptimizer_slicer.so")
                    require(engine.isFile&&engine.canExecute()) { "Die lokale Slicer-Komponente fehlt in dieser Installation." }
                    val child=ProcessBuilder(engine.absolutePath,"slice","-p","-j",settings.path,"-o",output.path,"-l",model.path)
                        .directory(output.parentFile).redirectErrorStream(true).start()
                    process.set(child)
                    if(cancelled.get())child.destroy()
                    watchdog=timer.schedule({timedOut.set(true);child.destroy()},25,TimeUnit.MINUTES)
                    val tail=StringBuilder()
                    child.inputStream.bufferedReader().useLines { lines -> lines.forEach { line ->
                        tail.append(line).append('\n');if(tail.length>12000)tail.delete(0,tail.length-12000)
                        if(output.exists()&&output.length()>536870912){child.destroy();throw IllegalStateException("G-Code ist größer als 512 MB.")}
                    }}
                    val code=child.waitFor()
                    if(cancelled.get())throw InterruptedException("Berechnung abgebrochen.")
                    if(timedOut.get())throw IllegalStateException("Zeitlimit erreicht. Modell vereinfachen oder gröbere Schichten wählen.")
                    if(code!=0||!output.isFile||output.length()==0L)throw IllegalStateException("Slicer konnte das Modell nicht verarbeiten. "+tail.takeLast(1200))
                    if(output.length()>536870912)throw IllegalStateException("G-Code ist größer als 512 MB.")
                    main.post{result.success(output.path)}
                }catch(error: Throwable){
                    process.get()?.destroy()
                    main.post{result.error(if(cancelled.get())"CANCELLED" else "SLICE_FAILED",error.message?:"Slicing fehlgeschlagen.",null)}
                }finally{watchdog?.cancel(false);process.set(null);running.set(false)}
            }
        }
    }
}
