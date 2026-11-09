import io.technoirlab.native.toolchains.api.NativeToolchainPackageCoordinates
import io.technoirlab.native.toolchains.api.NativeToolchainPackageNaming
import io.technoirlab.native.toolchains.api.NativeToolchainSpec
import io.technoirlab.native.toolchains.api.ToolchainArtifactSource
import org.jetbrains.kotlin.gradle.plugin.KotlinCompilation
import org.jetbrains.kotlin.gradle.plugin.mpp.KotlinNativeTarget
import org.jetbrains.kotlin.gradle.plugin.mpp.NativeBuildType.DEBUG
import org.jetbrains.kotlin.gradle.plugin.mpp.NativeBuildType.RELEASE
import java.net.URI

plugins {
    id("io.technoirlab.native-toolchains")
    kotlin("multiplatform")
}

nativeToolchains {
    toolchains {
        register("android") { selectSampleArtifact(NativeToolchainPackageNaming::android) }
        register("linux") { selectSampleArtifact(NativeToolchainPackageNaming::linux) }
        register("mingw") { selectSampleArtifact(NativeToolchainPackageNaming::mingw) }
    }
}

kotlin {
    androidNativeArm32()
    androidNativeArm64()
    androidNativeX86()
    androidNativeX64()
    linuxX64()
    linuxArm64()
    mingwX64()

    targets.withType<KotlinNativeTarget>().configureEach {
        val targetName = name
        compilations.named(KotlinCompilation.MAIN_COMPILATION_NAME) {
            cinterops.register("sample")
        }
        val buildHello = tasks.register("build${targetName.replaceFirstChar { it.uppercase() }}Hello") {
            group = "build"
            description = "Links the debug and release Hello World executables for $targetName."
        }
        binaries.executable(listOf(DEBUG, RELEASE)) {
            baseName = "hello"
            entryPoint = "main"
            val helloLinkTask = linkTaskProvider
            buildHello.configure {
                dependsOn(helloLinkTask)
            }
        }
    }
}

/**
 * Selects this toolchain's artifact from the sample's `<name>Toolchain*` Gradle properties.
 *
 * `<name>ToolchainUrl` selects an archive, which also requires `<name>ToolchainSha256`. Otherwise the toolchain uses the
 * `<name>Toolchain` directory, which defaults to the current host's artifact in the repository's `build/toolchains`
 * directory.
 */
fun NativeToolchainSpec.selectSampleArtifact(packageCoordinates: (konanHost: String) -> NativeToolchainPackageCoordinates) {
    val packageName = packageCoordinates(NativeToolchainPackageNaming.currentKonanHost()).packageName
    val projectDirectory = layout.projectDirectory
    val directorySource: Provider<ToolchainArtifactSource> = projectDirectory
        .dir(providers.gradleProperty("${name}Toolchain"))
        .orElse(projectDirectory.dir("../build/toolchains/$packageName"))
        .map { ToolchainArtifactSource.Directory(it.asFile) }
    val urlProperty = "${name}ToolchainUrl"
    val sha256Property = "${name}ToolchainSha256"
    val urlSource: Provider<ToolchainArtifactSource> = providers.gradleProperty(urlProperty)
        .zip(providers.gradleProperty(sha256Property).orElse("")) { url, sha256 ->
            if (sha256.isBlank()) {
                throw GradleException("-P$urlProperty requires -P$sha256Property with the archive's SHA-256")
            }
            ToolchainArtifactSource.Url(URI(url), sha256)
        }
    source = urlSource.orElse(directorySource)
    archiveRootDirectory = providers.gradleProperty("${name}ToolchainArchiveRoot").orElse(packageName)
}
