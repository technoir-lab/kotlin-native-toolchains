import io.technoirlab.native.toolchains.api.NativeToolchainPackageNaming
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
        register("android") {
            val defaultPackageName = NativeToolchainPackageNaming
                .android(NativeToolchainPackageNaming.currentKonanHost())
                .packageName
            val configuredDownloadUrl =
                providers.gradleProperty("androidToolchainUrl")
            val configuredDownloadSha256 =
                providers.gradleProperty("androidToolchainSha256")
            val localSource = providers.gradleProperty("androidToolchain")
                .map<ToolchainArtifactSource> {
                    ToolchainArtifactSource.Directory(file(it))
                }
                .orElse(
                    ToolchainArtifactSource.Directory(
                        layout.projectDirectory
                            .dir("../build/toolchains/$defaultPackageName")
                            .asFile,
                    ),
                )
            source = configuredDownloadUrl
                .zip(configuredDownloadSha256.orElse("")) { url, sha256 ->
                    ToolchainArtifactSource.Url(URI(url), sha256)
                }
                .map<ToolchainArtifactSource> { it }
                .orElse(localSource)
            archiveRootDirectory =
                providers.gradleProperty("androidToolchainArchiveRoot")
                    .orElse(defaultPackageName)
        }
        register("linux") {
            val defaultPackageName = NativeToolchainPackageNaming
                .linux(NativeToolchainPackageNaming.currentKonanHost())
                .packageName
            val configuredDownloadUrl =
                providers.gradleProperty("linuxToolchainUrl")
            val configuredDownloadSha256 =
                providers.gradleProperty("linuxToolchainSha256")
            val localSource = providers.gradleProperty("linuxToolchain")
                .map<ToolchainArtifactSource> {
                    ToolchainArtifactSource.Directory(file(it))
                }
                .orElse(
                    ToolchainArtifactSource.Directory(
                        layout.projectDirectory
                            .dir("../build/toolchains/$defaultPackageName")
                            .asFile,
                    ),
                )
            source = configuredDownloadUrl
                .zip(configuredDownloadSha256.orElse("")) { url, sha256 ->
                    ToolchainArtifactSource.Url(URI(url), sha256)
                }
                .map<ToolchainArtifactSource> { it }
                .orElse(localSource)
            archiveRootDirectory =
                providers.gradleProperty("linuxToolchainArchiveRoot")
                    .orElse(defaultPackageName)
        }
        register("mingw") {
            val defaultPackageName = NativeToolchainPackageNaming
                .mingw(NativeToolchainPackageNaming.currentKonanHost())
                .packageName
            val configuredDownloadUrl =
                providers.gradleProperty("mingwToolchainUrl")
            val configuredDownloadSha256 =
                providers.gradleProperty("mingwToolchainSha256")
            val localSource = providers.gradleProperty("mingwToolchain")
                .map<ToolchainArtifactSource> {
                    ToolchainArtifactSource.Directory(file(it))
                }
                .orElse(
                    ToolchainArtifactSource.Directory(
                        layout.projectDirectory
                            .dir("../build/toolchains/$defaultPackageName")
                            .asFile,
                    ),
                )
            source = configuredDownloadUrl
                .zip(configuredDownloadSha256.orElse("")) { url, sha256 ->
                    ToolchainArtifactSource.Url(URI(url), sha256)
                }
                .map<ToolchainArtifactSource> { it }
                .orElse(localSource)
            archiveRootDirectory =
                providers.gradleProperty("mingwToolchainArchiveRoot")
                    .orElse(defaultPackageName)
        }
        // Cinterops consume these providers during their configuration.
        names.forEach { named(it).get() }
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
        val buildHello = tasks.register(
            "build${targetName.replaceFirstChar { it.uppercase() }}Hello",
        ) {
            group = "build"
            description =
                "Links the debug and release Hello World executables for $targetName."
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
