package __PACKAGE__

import android.app.Activity
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
    private fun path(value: String?): File {
        require(value!=null) { "Slicer-Dateipfad fehlt." }
        val file=File(value).canonicalFile
        require(file.path.startsWith(activity.cacheDir.canonicalPath+File.separator)) { "Slicer-Datei liegt außerhalb des Arbeitsordners." }
        return file
    }
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger,"print_optimizer/slicer").setMethodCallHandler { call,result ->
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
                        if(output.exists()&&output.length()>134217728){child.destroy();throw IllegalStateException("G-Code ist größer als 128 MB.")}
                    }}
                    val code=child.waitFor()
                    if(cancelled.get())throw InterruptedException("Berechnung abgebrochen.")
                    if(timedOut.get())throw IllegalStateException("Zeitlimit erreicht. Modell vereinfachen oder gröbere Schichten wählen.")
                    if(code!=0||!output.isFile||output.length()==0L)throw IllegalStateException("Slicer konnte das Modell nicht verarbeiten. "+tail.takeLast(1200))
                    if(output.length()>134217728)throw IllegalStateException("G-Code ist größer als 128 MB.")
                    main.post{result.success(output.path)}
                }catch(error: Throwable){
                    process.get()?.destroy()
                    main.post{result.error(if(cancelled.get())"CANCELLED" else "SLICE_FAILED",error.message?:"Slicing fehlgeschlagen.",null)}
                }finally{watchdog?.cancel(false);process.set(null);running.set(false)}
            }
        }
    }
}
