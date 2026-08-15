plugins {
    id("com.android.application")
    // Плагин Flutter должен подключаться после Android плагина
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "su.vpnionline.vpnionline_app"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Укажите ваш уникальный Application ID
        applicationId = "su.vpnionline.vpnionline_app"
        
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
