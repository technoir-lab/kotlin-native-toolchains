pluginManagement {
    repositories {
        gradlePluginPortal()
        mavenLocal()
        mavenCentral()
    }
    plugins {
        id("io.technoirlab.native-toolchains") version "dev"
        id("org.jetbrains.kotlin.multiplatform") version "2.4.21"
    }
}

dependencyResolutionManagement {
    repositories {
        mavenCentral()
    }
}

rootProject.name = "native-toolchains-sample"
