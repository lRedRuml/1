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
                            val isStarted = nativeStartVlessEngine(connectionString)
                            if (isStarted) {
                                result.success(true)
                            } else {
                                result.error("ENGINE_FAILURE", "Failed to compile VLESS profile configuration", null)
                            }
                        } else {
                            result.error("BAD_ARGS", "Missing connection string parameters", null)
                        }
                    }
                    "stopTunnel" -> {
                        val isStopped = nativeStopVlessEngine()
                        if (isStopped) {
                            result.success(true)
                        } else {
                            result.error("ENGINE_FAILURE", "Failed to shutdown the network extension tunnel", null)
                        }
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

    private fun nativeStartVlessEngine(config: String): Boolean {
        return true
    }

    private fun nativeStopVlessEngine(): Boolean {
        return true
    }
}
