allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://googleapis.com") }
    }
}

val rootProjectBuildDir = project.layout.buildDirectory.dir("../../build").get().asFile
subprojects {
    project.layout.buildDirectory.set(rootProjectBuildDir.resolve(project.name))
}
subprojects {
    plugins.withType<com.android.build.gradle.BasePlugin> {
        configure<com.android.build.gradle.BaseExtension> {
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
    }
}
