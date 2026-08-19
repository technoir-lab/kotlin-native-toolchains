pluginManagement {
    repositories {
        mavenLocal()
        gradlePluginPortal()
        mavenCentral()
    }
    plugins {
        id("io.technoirlab.native-toolchains") version "dev"
        id("org.jetbrains.kotlin.multiplatform") version "2.4.10"
    }
}

dependencyResolutionManagement {
    repositories {
        mavenCentral()
    }
}

rootProject.name = "native-toolchains-sample"
