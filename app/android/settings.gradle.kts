pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        val propertiesFile = file("local.properties")
        if (propertiesFile.exists()) {
            propertiesFile.reader(Charsets.UTF_8).use { reader ->
                properties.load(reader)
            }
        }
        val sdkPath = properties.getProperty("flutter.sdk") ?: System.getenv("FLUTTER_ROOT")
        sdkPath ?: throw GradleException("Flutter SDK not found. Define flutter.sdk in local.properties or FLUTTER_ROOT in environment variables.")
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("com.android.application") version "7.4.2" apply false
    id("org.jetbrains.kotlin.android") version "1.8.22" apply false
    id("dev.flutter.flutter-gradle-plugin") version "1.0.0" apply false
}

include(":app")
