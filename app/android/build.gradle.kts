plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "su.vpnonline.vpnonline_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "su.vpnonline.vpnonline_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // [ИСПРАВЛЕНО] flutter_vless запускает Xray-core как отдельный
    // исполняемый процесс (не просто JNI-библиотеку через
    // System.loadLibrary) — для этого libxray.so должен быть физически
    // распакован на диск при установке. Современный AGP по умолчанию
    // держит .so сжатыми прямо внутри APK ("uncompressed native libs"),
    // из-за чего плагин не находил файл ("Xray executable not found").
    // Раньше это пытались исправить через android:extractNativeLibs="true"
    // в AndroidManifest.xml — но именно эта версия AGP требует делать это
    // здесь, в packagingOptions, а не в манифесте (манифест теперь даёт
    // ошибку сборки при явном extractNativeLibs).
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}