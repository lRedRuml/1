allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.layout.buildDirectory.set(rootProject.rootDir.resolve("../build"))

subprojects {
    project.layout.buildDirectory.set(rootProject.layout.buildDirectory.get().asFile.resolve(project.name))
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
