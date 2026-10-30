package __PACKAGE__

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class OptimizerGeometry {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private external fun nativeCut(vertices: FloatArray, scale: Double, axis: Int, fraction: Double,
                                   pins: Boolean, diameter: Double, length: Double, clearance: Double): Array<FloatArray>
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "print_optimizer/model_cut").setMethodCallHandler { call, result ->
            if (call.method != "cut") { result.notImplemented(); return@setMethodCallHandler }
            val vertices = call.argument<FloatArray>("vertices")
            val scale = call.argument<Number>("scale")?.toDouble()
            val axis = call.argument<Number>("axis")?.toInt()
            val fraction = call.argument<Number>("fraction")?.toDouble()
            val diameter = call.argument<Number>("diameter")?.toDouble()
            val length = call.argument<Number>("length")?.toDouble()
            val clearance = call.argument<Number>("clearance")?.toDouble()
            if (vertices == null || scale == null || axis == null || fraction == null || diameter == null || length == null || clearance == null) {
                result.error("INVALID_CUT", "Schnittdaten fehlen.", null); return@setMethodCallHandler
            }
            val pins = call.argument<Boolean>("pins") ?: true
            worker.execute {
                try {
                    System.loadLibrary("optimizer_geometry")
                    val pieces = nativeCut(vertices, scale, axis, fraction, pins, diameter, length, clearance)
                    main.post { result.success(pieces.toList()) }
                } catch (error: Throwable) {
                    main.post { result.error("CUT_FAILED", error.message ?: "Schnitt fehlgeschlagen.", null) }
                }
            }
        }
    }
}
