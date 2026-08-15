package su.vpnonline.vpnonline_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.vpnonline.app/tunnel"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "startTunnel" -> {
                        val connectionString = call.argument<String>("connection_string")
                        if (connectionString != null) {
                            result.success(true)
                        } else {
                            result.error("BAD_ARGS", "Missing connection string parameters", null)
                        }
                    }
                    "stopTunnel" -> {
                        result.success(true)
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            } catch (e: Exception) {
                result.error("UNEXPECTED_CRASH", "Native runtime exception: ${e.message}", null)
            }
        }
    }
}
