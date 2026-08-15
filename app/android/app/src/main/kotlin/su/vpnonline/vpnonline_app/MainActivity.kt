package su.vpnonline.vpnonline_app

import android.os.Bundle
import androidx.annotation.Keep

@Keep
class MainActivity : android.app.Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Динамический вызов инициализации контейнера движка через рефлексию 
        // для обхода бага изоляции классов компилятора Kotlin под Gradle 8+
        try {
            val flutterActivityClass = Class.forName("io.flutter.embedding.android.FlutterActivity")
            val intent = flutterActivityClass.getMethod("createDefaultIntent", android.content.Context::class.java)
                .invoke(null, this) as android.content.Intent
            startActivity(intent)
            finish()
        } catch (e: Exception) {
            android.util.Log.e("VPN_ONLINE_LAUNCHER", "Failed to boot isolate bridge context: ${e.message}")
        }
    }
}
