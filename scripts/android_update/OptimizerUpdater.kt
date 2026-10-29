package __PACKAGE__

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicInteger

class OptimizerUpdateFileProvider : FileProvider()

class OptimizerUpdater(private val activity: Activity) {
    private val generation = AtomicInteger(0)

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "print_optimizer/app_updates").setMethodCallHandler { call, result ->
            when (call.method) {
                "updateDirectory" -> {
                    val directory = File(activity.cacheDir, "app_updates")
                    if (directory.isDirectory || directory.mkdirs()) result.success(directory.absolutePath)
                    else result.error("CACHE_UNAVAILABLE", "Updatespeicher nicht verfügbar.", null)
                }
                "cancelInstall" -> { generation.incrementAndGet(); result.success(null) }
                "openInstallPermissionSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= 26) {
                            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:${activity.packageName}")))
                        }
                        result.success(null)
                    } catch (_: Exception) {
                        result.error("SETTINGS_UNAVAILABLE", "Android-Einstellung nicht verfügbar.", null)
                    }
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    val digest = call.argument<String>("sha256")
                    if (path == null || digest == null) {
                        result.error("INVALID_APK", "Updatedatei fehlt.", null)
                    } else {
                        val ticket = generation.incrementAndGet()
                        Thread {
                            try {
                                val file = checkedApk(path, digest)
                                activity.runOnUiThread {
                                    if (generation.get() != ticket || activity.isFinishing || activity.isDestroyed) {
                                        result.error("CANCELLED", "Update abgebrochen.", null)
                                    } else {
                                        try {
                                            if (Build.VERSION.SDK_INT >= 26 &&
                                                !activity.packageManager.canRequestPackageInstalls()) {
                                                result.success("permissionRequired")
                                            } else {
                                                val uri = FileProvider.getUriForFile(activity,
                                                    "${activity.packageName}.optimizer_updates", file)
                                                val intent = Intent(Intent.ACTION_VIEW).apply {
                                                    setDataAndType(uri, "application/vnd.android.package-archive")
                                                    clipData = ClipData.newRawUri("App update", uri)
                                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                                }
                                                activity.startActivity(intent)
                                                result.success("installerOpened")
                                            }
                                        } catch (_: Exception) {
                                            result.error("INSTALL_UNAVAILABLE", "Installationsdialog nicht verfügbar.", null)
                                        }
                                    }
                                }
                            } catch (_: Exception) {
                                activity.runOnUiThread {
                                    result.error("INVALID_APK", "Updatedatei oder App-Signatur ist ungültig.", null)
                                }
                            }
                        }.start()
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun checkedApk(path: String, expectedDigest: String): File {
        require(expectedDigest.matches(Regex("[0-9a-f]{64}")))
        val directory = File(activity.cacheDir, "app_updates").canonicalFile
        val file = File(path).canonicalFile
        require(file.parentFile == directory && file.isFile)
        val name = Regex("update-(\\d+)\\.apk").matchEntire(file.name) ?: error("Invalid filename")
        require(file.length() in 1..(200L * 1024 * 1024))
        val hash = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(65536)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                hash.update(buffer, 0, count)
            }
        }
        require(hex(hash.digest()) == expectedDigest)
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES
                    else PackageManager.GET_SIGNATURES
        val manager = activity.packageManager
        val apk = manager.getPackageArchiveInfo(file.absolutePath, flags) ?: error("Invalid APK")
        val installed = manager.getPackageInfo(activity.packageName, flags)
        require(apk.packageName == activity.packageName)
        val version = if (Build.VERSION.SDK_INT >= 28) apk.longVersionCode else apk.versionCode.toLong()
        val installedVersion = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode
                               else installed.versionCode.toLong()
        require(version > installedVersion && version == name.groupValues[1].toLong())
        val currentSigners = signers(installed)
        require(currentSigners.isNotEmpty() && signers(apk) == currentSigners)
        return file
    }

    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners
                         else info.signatures
        return signatures?.map { hex(MessageDigest.getInstance("SHA-256").digest(it.toByteArray())) }
            ?.toSet() ?: emptySet()
    }

    private fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it.toInt() and 255) }
}
