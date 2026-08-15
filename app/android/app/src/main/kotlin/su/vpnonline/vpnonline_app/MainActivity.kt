package su.vpnonline.vpnonline_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Нативные каналы связи будут инициализированы автоматически после успешного прохождения базового линкера
    }
}
