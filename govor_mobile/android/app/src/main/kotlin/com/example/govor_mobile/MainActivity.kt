package app.govor.client

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.URL
import java.net.HttpURLConnection
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private var installing = false
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "app.govor.client/updates").setMethodCallHandler { call, result ->
            when (call.method) {
                "abis" -> result.success(Build.SUPPORTED_ABIS.toList())
                "install" -> {
                    if (installing) { result.error("busy", "Download in progress", null); return@setMethodCallHandler }
                    if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
                        startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + packageName)))
                        result.error("permission", "Allow installation, then retry", null)
                        return@setMethodCallHandler
                    }
                    val url = call.argument<String>("url") ?: ""
                    val size = call.argument<Number>("size")?.toLong() ?: 0
                    val digest = call.argument<String>("digest") ?: ""
                    if (!url.startsWith("https://github.com/") || size <= 0 || size > 512L * 1024 * 1024 || !digest.matches(Regex("[a-fA-F0-9]{64}"))) {
                        result.error("invalid", "Invalid update", null); return@setMethodCallHandler
                    }
                    installing = true
                    Thread {
                        val folder = File(cacheDir, "updates").apply { mkdirs() }
                        val file = File(folder, "update.apk")
                        try {
                            val connection = URL(url).openConnection() as HttpURLConnection
                            connection.connectTimeout = 20000
                            connection.readTimeout = 30000
                            try {
                                check(connection.responseCode == 200)
                                check(connection.url.protocol == "https")
                                val hash = MessageDigest.getInstance("SHA-256")
                                var count = 0L
                                connection.inputStream.use { input -> file.outputStream().use { output ->
                                    val buffer = ByteArray(65536)
                                    while (true) {
                                        val n = input.read(buffer)
                                        if (n < 0) break
                                        count += n
                                        check(count <= size)
                                        hash.update(buffer, 0, n)
                                        output.write(buffer, 0, n)
                                    }
                                } }
                                check(count == size)
                                check(hash.digest().joinToString("") { "%02x".format(it) }.equals(digest, true))
                            } finally { connection.disconnect() }
                            val archive = packageManager.getPackageArchiveInfo(file.path, 0)
                            check(archive?.packageName == packageName)
                            val installed = packageManager.getPackageInfo(packageName, 0)
                            val nextCode = if (Build.VERSION.SDK_INT >= 28) archive!!.longVersionCode else archive!!.versionCode.toLong()
                            val currentCode = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
                            check(nextCode > currentCode)
                            runOnUiThread {
                                try {
                                    val uri = FileProvider.getUriForFile(this, packageName + ".updates", file)
                                    startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                                    result.success(null)
                                } catch (e: Exception) { result.error("install", e.message, null) }
                                finally { installing = false }
                            }
                        } catch (e: Exception) {
                            file.delete()
                            runOnUiThread { installing = false; result.error("download", e.message, null) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }
}
