import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { stream ->
        localProperties.load(stream)
    }
}

val flutterVersionCode = localProperties.getProperty("flutter.versionCode") ?: "1"
val flutterVersionName = localProperties.getProperty("flutter.versionName") ?: "1.0.0"

// Поиск пути к Flutter SDK для ручного маппинга зависимостей при сбоях компилятора Kotlin
val flutterRootPath = System.getenv("FLUTTER_ROOT") ?: localProperties.getProperty("flutter.sdk")

android {
    namespace = "su.vpnonline.vpnonline_app"
    compileSdk = 34

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    sourceSets {
        getByName("main").java.srcDirs("src/main/kotlin")
    }

    defaultConfig {
        applicationId = "su.vpnonline.vpnonline_app"
        minSdk = 21
        targetSdk = 34
        versionCode = flutterVersionCode.toInt()
        versionName = flutterVersionName
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

dependencies {
    // Жесткое перенаправление компилятора на встраиваемые системные JAR-архивы движка Flutter,
    // если внутренние Gradle-таски сборщика не смогли пробросить ссылки на классы 'io.flutter'
    if (flutterRootPath != null) {
        implementation(files("$flutterRootPath/packages/flutter_tools/gradle/flutter.jar"))
    }
}
