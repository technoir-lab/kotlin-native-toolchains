# Kotlin/Native target toolchains

| Scope | Pin |
| --- | --- |
| Kotlin / Kotlin Gradle plugin | `2.4.21` |
| Kotlin source | [`9180ce6a7a7d3627f88b424717583f28ddca052d`](https://github.com/JetBrains/kotlin/tree/9180ce6a7a7d3627f88b424717583f28ddca052d) |
| Kotlin compiler-side LLVM | Kotlin LLVM `21.1.6`; Clang/LLD `21.1.6` |
| Verification date | 2026-11-02 |
| Names | Gradle: `linuxX64`; Konan: `linux_x64`; triple: `x86_64-unknown-linux-gnu` |

## Selection, resolution, download, and cache

```text
Gradle target DSL
  -> KonanTarget
  -> compiler argument: -target <konan-target>
  -> HostManager host detection
  -> configurables selected by target family
  -> host/target properties resolved from konan.properties
  -> dependency names + host LLVM + libffi
  -> local candidate, extracted cache, or JetBrains download
  -> Clang/LLVM code generation
  -> target-family linker + target sysroot/runtime inputs
```

| Stage | Input | Resolution | Result | Source |
| --- | --- | --- | --- | --- |
| Gradle target | `linuxX64()`, `androidNativeArm64()`, … | Kotlin Gradle plugin maps the preset to `KonanTarget` | Compile/link arguments contain `-target <target.name>` | [`KotlinNativeCompilerArgBuilder.kt`](https://github.com/JetBrains/kotlin/blob/9180ce6a7a7d3627f88b424717583f28ddca052d/libraries/tools/kotlin-gradle-plugin/src/common/kotlin/org/jetbrains/kotlin/gradle/targets/native/tasks/KotlinNativeCompilerArgBuilder.kt) |
| Default target | No `-target`, or `-target host` | Current supported host | Host Konan target | [`TargetManager.kt`](https://github.com/JetBrains/kotlin/blob/9180ce6a7a7d3627f88b424717583f28ddca052d/native/utils/src/org/jetbrains/kotlin/konan/target/TargetManager.kt) |
| Host | JVM `os.name` + `os.arch` | `Mac OS X/x86_64`, `Mac OS X/aarch64`, `Linux/x86_64`, `Windows/x86_64` | `macos_x64`, `macos_arm64`, `linux_x64`, `mingw_x64` | [`HostManager.kt`](https://github.com/JetBrains/kotlin/blob/9180ce6a7a7d3627f88b424717583f28ddca052d/native/utils/src/org/jetbrains/kotlin/konan/target/HostManager.kt) |
| Target family | `KonanTarget.family` | Linux → GCC configurables; Apple → Apple configurables; Android → Android configurables; MinGW → MinGW configurables | Family-specific compiler, linker, sysroot, and dependency properties | [`ConfigurablesImpl.kt`](https://github.com/JetBrains/kotlin/blob/9180ce6a7a7d3627f88b424717583f28ddca052d/native/utils/src/org/jetbrains/kotlin/konan/target/ConfigurablesImpl.kt) |
| Target configuration | `<Kotlin/Native>/konan/konan.properties` | Target and host-target keys | `targetToolchain`, `targetSysRoot`, `gccToolchain`, `libGcc`, `linker`, flags | [`konan.properties`](https://github.com/JetBrains/kotlin/blob/9180ce6a7a7d3627f88b424717583f28ddca052d/kotlin-native/konan/konan.properties) |
| Dependencies | `dependencies.<host[-target]>` | Target dependencies + predefined host LLVM + predefined host libffi | Ordered dependency identifiers | [`KonanProperties.kt`](https://github.com/JetBrains/kotlin/blob/9180ce6a7a7d3627f88b424717583f28ddca052d/native/utils/src/org/jetbrains/kotlin/konan/target/KonanProperties.kt) |
| Candidate | `<dependency>.<profile>`; profiles default to `default alt` | First viable candidate in profile/list order: existing local path, public remote, or available internal remote | Local directory or remote dependency | [`DependencyProcessor.kt`](https://github.com/JetBrains/kotlin/blob/9180ce6a7a7d3627f88b424717583f28ddca052d/native/utils/src/org/jetbrains/kotlin/konan/util/DependencyProcessor.kt) |
| Public download | No explicit default candidate | `https://download.jetbrains.com/kotlin/native/<dependency>.<extension>` | `.tar.gz` on macOS/Linux; `.zip` on Windows | [`DependencyProcessor.kt`](https://github.com/JetBrains/kotlin/blob/9180ce6a7a7d3627f88b424717583f28ddca052d/native/utils/src/org/jetbrains/kotlin/konan/util/DependencyProcessor.kt) |
| Use | Resolved absolute paths | `ClangArgs`, `AndroidLinker`, `MacOSBasedLinker`, `GccBasedLinker`, `MingwLinker` | Compiler/linker command | [`ClangArgs.kt`](https://github.com/JetBrains/kotlin/blob/9180ce6a7a7d3627f88b424717583f28ddca052d/native/utils/src/org/jetbrains/kotlin/konan/target/ClangArgs.kt), [`Linker.kt`](https://github.com/JetBrains/kotlin/blob/9180ce6a7a7d3627f88b424717583f28ddca052d/native/utils/src/org/jetbrains/kotlin/konan/target/Linker.kt) |

### Property precedence

| Lookup | First | Fallback |
| --- | --- | --- |
| Distribution properties | `-Xoverride-konan-properties` entry | `<Kotlin/Native>/konan/konan.properties` |
| Target property `key` | `key.<target>` | `key` |
| Host property `key` | `key.<host>` | `key` |
| Host-target property, native target | `key.<host>` | `key` |
| Host-target property, cross target | `key.<host>-<target>` | `key` |
| `$property/path` value | Recursively resolved property value + `/path` | — |
| `${property}suffix` value | Recursively resolved property value + `suffix` | — |
| Single-value lookup without a literal `key.<suffix>` or `key` | Key containing `$property` that resolves to `key.<suffix>` | — |

Sources: [`Distribution.kt`](https://github.com/JetBrains/kotlin/blob/9180ce6a7a7d3627f88b424717583f28ddca052d/native/utils/src/org/jetbrains/kotlin/konan/target/Distribution.kt), [`TargetProperties.kt`](https://github.com/JetBrains/kotlin/blob/9180ce6a7a7d3627f88b424717583f28ddca052d/native/utils/src/org/jetbrains/kotlin/konan/target/TargetProperties.kt), [`PropertyFileUtils.kt`](https://github.com/JetBrains/kotlin/blob/9180ce6a7a7d3627f88b424717583f28ddca052d/compiler/util-io/src/org/jetbrains/kotlin/io/PropertyFileUtils.kt).

### Cache layout

```text
${KONAN_DATA_DIR:-<user-home>/.konan}/
├── kotlin-native-prebuilt-<host-os>-<host-arch>-2.4.21/
│   └── konan/konan.properties
└── dependencies/
    ├── .extracted
    ├── cache/
    │   ├── .lock
    │   └── <dependency>.<tar.gz|zip>  # deleted after successful extraction
    ├── llvm-21-<host>-essentials-<revision>/
    ├── <target-toolchain>/
    └── <target-sysroot>/
```

| Item | Kotlin 2.4.21 behavior |
| --- | --- |
| Root override | `KONAN_DATA_DIR`; default `<user-home>/.konan` |
| Extracted dependency | `<root>/dependencies/<dependency>` |
| Download archive | `<root>/dependencies/cache/<dependency>.<tar.gz\|zip>` |
| Complete marker | `<root>/dependencies/.extracted` |
| Concurrency | JVM-wide lock + `<root>/dependencies/cache/.lock` file lock |
| Existing extraction | Reused when marked, present, directory, and non-empty |
| Archive retention | Deleted after extraction by default |
| Offline mode | `airplaneMode=true`; missing local dependency is an error |

Source: [`DependencyDirectories.kt`](https://github.com/JetBrains/kotlin/blob/9180ce6a7a7d3627f88b424717583f28ddca052d/native/utils/src/org/jetbrains/kotlin/konan/util/DependencyDirectories.kt), [`DependencyProcessor.kt`](https://github.com/JetBrains/kotlin/blob/9180ce6a7a7d3627f88b424717583f28ddca052d/native/utils/src/org/jetbrains/kotlin/konan/util/DependencyProcessor.kt).

## Local overrides

```text
-Xoverride-konan-properties=key1=value1;key2=value2;key3=
```

| Constraint | Value |
| --- | --- |
| Delimiter | `;` |
| Empty property | `key=` |
| Local path | Absolute |
| Unsafe path characters | Whitespace; `;` |
| Compiler option source | [`NativeCompilerArguments.kt`](https://github.com/JetBrains/kotlin/blob/9180ce6a7a7d3627f88b424717583f28ddca052d/compiler/arguments/src/org/jetbrains/kotlin/arguments/description/NativeCompilerArguments.kt) |

### Property sets

| Family | Required local properties | Stock-download suppression | Retained Kotlin tools |
| --- | --- | --- | --- |
| Android | `targetToolchain.<host>-<target>`; `targetSysRoot.<target>` | `dependencies.<host>-<target>=` | Host LLVM for code generation and cinterop; `llvm-ar` |
| Linux | `gccToolchain.<target>`; `targetSysRoot.<target>`; `libGcc.<target>` | `dependencies.<host>-<target>=`; `dependencies.<host>=` when host = target | Host LLVM/Clang; configured host-target linker; `llvm-ar` |
| MinGW on macOS/Linux | `targetSysRoot.mingw_x64` | `dependencies.<host>-mingw_x64=` | Host LLVM `clang++`, LLD, `llvm-ar` |
| MinGW on Windows | Above + `targetToolchain.mingw_x64` when replacing MSYS2 tools | `dependencies.mingw_x64=` | Host LLVM `clang++`, LLD, `llvm-ar` |
| Apple | `DEVELOPER_DIR=<Xcode>/Contents/Developer` | Not applicable | Local Xcode toolchain and SDK selected by `Xcode.findCurrent()` |

```text
# Android ARM64; macOS ARM64 host
-Xoverride-konan-properties=targetToolchain.macos_arm64-android_arm64=/opt/tc/toolchain;targetSysRoot.android_arm64=/opt/tc/konan-sysroot;dependencies.macos_arm64-android_arm64=

# Linux x64; macOS ARM64 host
-Xoverride-konan-properties=gccToolchain.linux_x64=/opt/tc/targets/linux_x64;targetSysRoot.linux_x64=/opt/tc/targets/linux_x64/x86_64-unknown-linux-gnu/sysroot;libGcc.linux_x64=../../lib/gcc/x86_64-unknown-linux-gnu/13.4.0;dependencies.macos_arm64-linux_x64=

# MinGW x64; macOS ARM64 host
-Xoverride-konan-properties=targetSysRoot.mingw_x64=/opt/tc/konan-sysroot;dependencies.macos_arm64-mingw_x64=

# Apple target; alternate local Xcode
DEVELOPER_DIR=/Applications/Xcode-26.4.app/Contents/Developer kotlinc-native -target ios_arm64 ...
```

| Gradle consumer | Required placement |
| --- | --- |
| Kotlin compilation | `KotlinNativeCompile.compilerOptions.freeCompilerArgs` |
| Final binary | `KotlinNativeLink` compiler arguments / binary `freeCompilerArgs` |
| C interop | `cinterops.<name>.extraOpts("-Xoverride-konan-properties", "...")` |
| This project | `io.technoirlab.native-toolchains` applies all three |

## Kotlin 2.4.21 hosts and targets

### Hosts

| Host id | OS | Host architecture | Final binary targets |
| --- | --- | --- | --- |
| `macos_arm64` | macOS | ARM64 | All listed targets |
| `macos_x64` | macOS | x86-64 | All listed targets |
| `linux_x64` | Linux | x86-64 | Linux, Android, MinGW |
| `mingw_x64` | Windows | x86-64 | Linux, Android, MinGW |

Source: [`HostManager.kt`](https://github.com/JetBrains/kotlin/blob/9180ce6a7a7d3627f88b424717583f28ddca052d/native/utils/src/org/jetbrains/kotlin/konan/target/HostManager.kt), [Kotlin/Native host support](https://kotlinlang.org/docs/native-target-support.html#hosts).

### Targets

| Family | Gradle target | Konan id | Architecture | Target triple | Status |
| --- | --- | --- | --- | --- | --- |
| Android | `androidNativeArm32` | `android_arm32` | ARM32 | `arm-unknown-linux-androideabi` | Supported |
| Android | `androidNativeArm64` | `android_arm64` | ARM64 | `aarch64-unknown-linux-android` | Supported |
| Android | `androidNativeX86` | `android_x86` | x86 | `i686-unknown-linux-android` | Supported |
| Android | `androidNativeX64` | `android_x64` | x86-64 | `x86_64-unknown-linux-android` | Supported |
| Linux | `linuxX64` | `linux_x64` | x86-64 | `x86_64-unknown-linux-gnu` | Supported |
| Linux | `linuxArm64` | `linux_arm64` | ARM64 | `aarch64-unknown-linux-gnu` | Supported |
| Linux | `linuxArm32Hfp` | `linux_arm32_hfp` | ARM32 hard-float | `arm-unknown-linux-gnueabihf` | Deprecated |
| MinGW | `mingwX64` | `mingw_x64` | x86-64 | `x86_64-pc-windows-gnu` | Supported |
| macOS | `macosArm64` | `macos_arm64` | ARM64 | `arm64-apple-macos` | Supported |
| macOS | `macosX64` | `macos_x64` | x86-64 | `x86_64-apple-macos` | Deprecated |
| iOS | `iosArm64` | `ios_arm64` | ARM64 | `arm64-apple-ios` | Supported |
| iOS | `iosX64` | `ios_x64` | x86-64 simulator | `x86_64-apple-ios-simulator` | Supported |
| iOS | `iosSimulatorArm64` | `ios_simulator_arm64` | ARM64 simulator | `arm64-apple-ios-simulator` | Supported |
| watchOS | `watchosArm32` | `watchos_arm32` | ARM32 | `armv7k-apple-watchos` | Supported |
| watchOS | `watchosArm64` | `watchos_arm64` | ARM64 ILP32 | `arm64_32-apple-watchos` | Supported |
| watchOS | `watchosDeviceArm64` | `watchos_device_arm64` | ARM64 | `arm64-apple-watchos` | Supported |
| watchOS | `watchosSimulatorArm64` | `watchos_simulator_arm64` | ARM64 simulator | `arm64-apple-watchos-simulator` | Supported |
| watchOS | `watchosX64` | `watchos_x64` | x86-64 simulator | `x86_64-apple-watchos-simulator` | Deprecated |
| tvOS | `tvosArm64` | `tvos_arm64` | ARM64 | `arm64-apple-tvos` | Supported |
| tvOS | `tvosSimulatorArm64` | `tvos_simulator_arm64` | ARM64 simulator | `arm64-apple-tvos-simulator` | Supported |
| tvOS | `tvosX64` | `tvos_x64` | x86-64 simulator | `x86_64-apple-tvos-simulator` | Deprecated |

Sources: [`KonanTarget.kt`](https://github.com/JetBrains/kotlin/blob/9180ce6a7a7d3627f88b424717583f28ddca052d/native/utils/src/org/jetbrains/kotlin/konan/target/KonanTarget.kt), [`konan.properties`](https://github.com/JetBrains/kotlin/blob/9180ce6a7a7d3627f88b424717583f28ddca052d/kotlin-native/konan/konan.properties).

## Kotlin 2.4.21 toolchains

### Compiler-side host LLVM

| Host | Dependency | Compiler / linker tools | Target inputs supplied |
| --- | --- | --- | --- |
| Linux x64 | `llvm-21-x86_64-linux-essentials-116` | Kotlin LLVM, Clang, LLD `21.1.6`; `llvm-ar` | Clang resource headers; compiler-rt |
| macOS x64 | `llvm-21-x86_64-macos-essentials-83` | Kotlin LLVM, Clang, LLD `21.1.6`; `llvm-ar` | Clang resource headers; compiler-rt |
| macOS ARM64 | `llvm-21-aarch64-macos-essentials-97` | Kotlin LLVM, Clang, LLD `21.1.6`; `llvm-ar` | Clang resource headers; compiler-rt |
| Windows x64 | `llvm-21-x86_64-windows-essentials-150` | Kotlin LLVM, Clang, LLD `21.1.6`; `llvm-ar` | Clang resource headers; compiler-rt |

### Family summary

| Target toolchain | Konan targets | Build hosts | Compile / final link | Component versions | Supplied headers | Supplied libraries and objects |
| --- | --- | --- | --- | --- | --- | --- |
| Xcode | All macOS, iOS, watchOS, tvOS targets | macOS x64, macOS ARM64 | Kotlin LLVM `21.1.6`; Xcode-bundled Apple Clang and `ld` | Xcode `26.4` (`17E192`); SDK `26.4`; Apple Clang/linker have no independent Kotlin pin | Selected macOS/iPhoneOS/iPhoneSimulator/AppleTVOS/AppleTVSimulator/WatchOS/WatchSimulator SDK headers; Clang resource headers; libc++ | SDK `.tbd` libraries, libc++, libSystem, Objective-C runtime, platform frameworks; compiler-rt; startup/runtime objects |
| Android NDK | `android_arm32`, `android_arm64`, `android_x86`, `android_x64` | macOS x64/ARM64, Linux x64, Windows x64 | Host Kotlin LLVM for codegen/cinterop; NDK Clang driver + GNU target linker for final link | NDK r20 (`20.0.5594570`); Clang/LLVM/LLD `8.0.7`; GNU binutils `2.27.0.20170315`; Yasm `1.3.0`; Kotlin API `21` | Unified NDK C/C++ headers; libc++ headers; target-specific headers; old-layout API sysroots `16`–`29` | libc, libm, libdl, liblog, libandroid; libc++ static, libc++abi; compiler-rt, libatomic, libunwind; API CRT objects |
| Linux x64 GCC | `linux_x64` | macOS x64/ARM64, Linux x64, Windows x64 | Host Kotlin LLVM/Clang; LLD `21.1.6` on macOS/Linux; GNU Gold on Windows | GCC `8.3.0`; glibc `2.19`; Linux headers `4.9.156`; binutils `2.32`; zlib `1.2.11` | GCC/libstdc++ headers; glibc headers; Linux UAPI headers | glibc shared/static/linker scripts; CRT objects; libstdc++, libgcc/libgcc_eh; zlib; ELF loader |
| Linux ARM64 GCC | `linux_arm64` | macOS x64/ARM64, Linux x64, Windows x64 | Host Kotlin LLVM/Clang; LLD `21.1.6` on macOS/Linux; GNU Gold on Windows | GCC `8.3.0`; glibc `2.25`; Linux headers `4.9.156`; binutils `2.29.1`; zlib `1.2.11` | GCC/libstdc++ headers; glibc headers; Linux UAPI headers | glibc shared/static/linker scripts; CRT objects; libstdc++, libgcc/libgcc_eh; zlib; ELF loader |
| Linux ARM32 HFP GCC | `linux_arm32_hfp` | macOS x64/ARM64, Linux x64, Windows x64 | Host Kotlin LLVM/Clang; GNU `ld` on Linux; LLD `21.1.6` on macOS; GNU Gold on Windows | GCC `8.3.0`; glibc `2.12.1`; Linux headers `4.9.156`; binutils `2.32`; zlib `1.2.11`; QEMU dependency `5.1.0` on Linux host | GCC/libstdc++ headers; glibc headers; Linux UAPI headers | glibc shared/static/linker scripts; CRT objects; libstdc++, libgcc/libgcc_eh; zlib; ELF loader |
| MSYS2 MinGW-w64 | `mingw_x64` | macOS x64/ARM64, Linux x64, Windows x64 | Host Kotlin LLVM `clang++`; LLD `21.1.6`; host `llvm-ar` | GCC `9.2.0`; MinGW-w64 `7.0.0`; binutils `2.32`; zlib `1.2.11`; Z3 `4.8.5` | MinGW-w64 Windows API/CRT headers; GCC/libstdc++ headers | MSVCRT/UCRT and Windows import libraries; CRT objects; libstdc++, libgcc/libgcc_eh; winpthreads; zlib; Z3; libffi |

### Dependency identifiers

| Family | Dependency identifiers |
| --- | --- |
| Apple internal CI | `target-toolchain-xcode_26.4_17E192`; `target-sysroot-xcode_26.4_17E192-{macosx,iphoneos,iphonesimulator,appletvos,appletvsimulator,watchos,watchsimulator}`; `xcode-addon-xcode_26.4_17E192` |
| Apple user build | Active local Xcode toolchain and SDKs; internal archives are not downloaded |
| Android macOS | `target-toolchain-2-osx-android_ndk`; `target-sysroot-1-android_ndk` |
| Android Linux | `target-toolchain-2-linux-android_ndk`; `target-sysroot-1-android_ndk` |
| Android Windows | `target-toolchain-2-windows-android_ndk`; `target-sysroot-1-android_ndk` |
| Linux x64 | `x86_64-unknown-linux-gnu-gcc-8.3.0-glibc-2.19-kernel-4.9-2` |
| Linux ARM64 | `aarch64-unknown-linux-gnu-gcc-8.3.0-glibc-2.25-kernel-4.9-2` |
| Linux ARM32 HFP | `arm-unknown-linux-gnueabihf-gcc-8.3.0-glibc-2.12.1-kernel-4.9-1` |
| MinGW x64 | `msys2-mingw-w64-x86_64-2` |

### Installed layouts

```text
# Android
dependencies/
├── target-toolchain-2-<os>-android_ndk/
│   ├── bin/{clang,clang++,<api-target>-clang,ld.lld,<triple>-ld.*,llvm-*}
│   ├── lib{,64}/clang/8.0.7/
│   ├── sysroot/usr/{include,lib}/
│   └── <library-triple>/bin/
└── target-sysroot-1-android_ndk/
    └── android-{16..29}/arch-{arm,arm64,x86,x86_64}/

# Linux
dependencies/<gcc-package>/
├── bin/<triple>-{gcc,g++,ar,ld,ld.gold,ranlib,...}
├── lib/gcc/<triple>/8.3.0/
└── <triple>/
    ├── include/c++/8.3.0/
    └── sysroot/{lib,lib64,usr/include,usr/lib}/

# MinGW
dependencies/msys2-mingw-w64-x86_64-2/
├── bin/{gcc,g++,ar,ld,ld.gold,...}.exe
├── include/c++/9.2.0/
├── lib/gcc/x86_64-w64-mingw32/9.2.0/
└── x86_64-w64-mingw32/{include,lib}/

# Apple local provider
Xcode.app/Contents/Developer/
├── Toolchains/XcodeDefault.xctoolchain/usr/{bin,lib/clang}/
└── Platforms/<platform>.platform/Developer/SDKs/<sdk>.sdk/
    ├── usr/{include,lib}/
    └── System/Library/Frameworks/
```

## This project

### Family summary

| Artifact family | Konan targets | Build/consumer hosts | Compile / final link | Component versions | Supplied headers | Supplied libraries and objects |
| --- | --- | --- | --- | --- | --- | --- |
| `android_ndk_r29` | `android_arm32`, `android_arm64`, `android_x86`, `android_x64` | macOS ARM64 (`darwin-x86_64` NDK tag); Linux x64 (`linux-x86_64`) | NDK Clang driver and LLD | NDK `29.0.14206865`; Clang/LLVM/LLD `21.0.0`; API `21`; Vulkan headers `1.3.275` | Complete NDK r29 unified sysroot: Android/Bionic, libc++, Linux UAPI, EGL/GLES, Vulkan and platform headers | API 21 libc/libm/libdl/liblog/libandroid stubs and CRT; libc++/libc++abi; compiler-rt builtins; libatomic; libunwind; ARM32 legacy-sync archive |
| `linux_gcc13_glibc2.25` | `linux_x64`, `linux_arm64` | macOS ARM64; Linux x64 | Kotlin LLVM/Clang `21.1.6`; Kotlin host LLD `21.1.6`; the artifact contains no host programs | crosstool-NG `1.29.0`; GCC `13.4.0`; glibc `2.25`; Linux headers `5.15.209`; binutils `2.29.1`; zlib `1.2.13`; X.Org protocol `2023.2`; Xtrans `1.5.0`; libX11 `1.8.7`; libXext `1.3.4`; xcb-proto `1.15.2`; libxcb `1.15`; Wayland `1.22.0`; libxkbcommon `1.6.0`; Vulkan headers `1.3.275`; ALSA `1.2.11`; PulseAudio `16.1`; PipeWire `1.0.5`; JACK2 `1.9.21`; sndio `1.9.0` | libstdc++ headers; glibc headers; Linux 5.15.209 UAPI headers; zlib headers; X11, Xlib-xcb, Xext, and Xtrans headers; xcb headers; Wayland client, server, cursor, and EGL headers; xkbcommon headers; Vulkan and Vulkan Video headers; ALSA, PulseAudio, PipeWire and SPA, JACK, and sndio headers | glibc shared/static/linker scripts; CRT objects; libstdc++; libgcc/libgcc_eh; zlib; target ELF loaders. No X11, Xext, xcb, Wayland, xkbcommon, Vulkan, or audio libraries |
| `mingw_gcc13_mingw-w64_14_msvcrt` | `mingw_x64` | macOS ARM64; Linux x64 | Kotlin LLVM `clang++` `21.1.6`; Kotlin host LLD `21.1.6`; the artifact contains no host programs | crosstool-NG `1.29.0`; GCC `13.4.0`; MinGW-w64 `14.0.0`; binutils `2.40`; zlib `1.2.13`; MSVCRT; POSIX threads | Complete MinGW-w64 Windows API/CRT headers; DirectX and DDK headers; libstdc++ headers | MSVCRT and Windows import libraries; CRT objects; libstdc++; libgcc/libgcc_eh; winpthreads; zlib |

Sources: [`android.properties`](../toolchains/android/android.properties), [`build-android-toolchain.sh`](../scripts/build-android-toolchain.sh), [`linux.properties`](../toolchains/linux/linux.properties), [`build-linux-toolchain.sh`](../scripts/build-linux-toolchain.sh), [`sources.lock`](../toolchains/linux/builder/image/sources.lock), [`mingw.properties`](../toolchains/mingw/mingw.properties), [`build-mingw-toolchain.sh`](../scripts/build-mingw-toolchain.sh).

### Target mapping

| Platform | Konan target | Architecture | Kotlin triple | Toolchain/library triple | Dynamic loader / API |
| --- | --- | --- | --- | --- | --- |
| Android | `android_arm32` | ARM32 | `arm-unknown-linux-androideabi` | `arm-linux-androideabi`; Clang `armv7a-linux-androideabi21` | API 21; `/system/bin/linker` |
| Android | `android_arm64` | ARM64 | `aarch64-unknown-linux-android` | `aarch64-linux-android`; Clang `aarch64-linux-android21` | API 21; `/system/bin/linker64` |
| Android | `android_x86` | x86 | `i686-unknown-linux-android` | `i686-linux-android`; Clang `i686-linux-android21` | API 21; `/system/bin/linker` |
| Android | `android_x64` | x86-64 | `x86_64-unknown-linux-android` | `x86_64-linux-android`; Clang `x86_64-linux-android21` | API 21; `/system/bin/linker64` |
| Linux | `linux_x64` | x86-64 | `x86_64-unknown-linux-gnu` | Same | `/lib64/ld-linux-x86-64.so.2` |
| Linux | `linux_arm64` | ARM64 | `aarch64-unknown-linux-gnu` | Same | `/lib/ld-linux-aarch64.so.1` |
| MinGW | `mingw_x64` | x86-64 | `x86_64-pc-windows-gnu` | `x86_64-w64-mingw32` | MSVCRT |

### Kotlin property overrides applied by the consumer plugin

| Platform | Override |
| --- | --- |
| Android, every target | `targetToolchain.<host>-<target>=<artifact>/toolchain` |
| Android, every target | `targetSysRoot.<target>=<artifact>/konan-sysroot` |
| Android, every target | `dependencies.<host>-<target>=` |
| Android, every target | `linkerKonanFlags.<target>=-lm -lc++_static -lc++abi -landroid -llog -latomic --target=<api-qualified-clang-target>` |
| Android ARM32 | Above + `<artifact>/compat/liblegacy-sync-arm32.a` |
| Linux, every target | `gccToolchain.<target>=<artifact>/targets/<target>` |
| Linux, every target | `targetSysRoot.<target>=<artifact>/targets/<target>/<triple>/sysroot` |
| Linux, every target | `libGcc.<target>=../../lib/gcc/<triple>/13.4.0` |
| Linux, every target | `dependencies.<host>-<target>=`; `dependencies.<host>=` when host = target |
| MinGW | `targetSysRoot.mingw_x64=<artifact>/konan-sysroot` |
| MinGW | `dependencies.<host>-mingw_x64=` |

### Artifact layouts

```text
# Android
io.technoirlab-target-toolchain-1-<host>-android_ndk_r29/
├── compat/liblegacy-sync-arm32.a
├── konan-sysroot/android-21/
│   └── arch-{arm,arm64,x86,x86_64} -> ../../toolchain/sysroot
├── manifest.properties
└── toolchain/
    ├── bin/{clang,ld.lld,llvm-*,<api-target>-clang}
    ├── lib/clang/21/
    └── sysroot/usr/{include,lib}/

# Linux
io.technoirlab-target-toolchain-1-<host>-linux_gcc13_glibc2.25/
├── builder.properties
├── manifest.properties
└── targets/
    ├── linux_x64/
    │   ├── lib/gcc/x86_64-unknown-linux-gnu/13.4.0/
    │   └── x86_64-unknown-linux-gnu/
    │       ├── include/c++/13.4.0/
    │       └── sysroot/
    └── linux_arm64/
        ├── lib/gcc/aarch64-unknown-linux-gnu/13.4.0/
        └── aarch64-unknown-linux-gnu/
            ├── include/c++/13.4.0/
            └── sysroot/

# MinGW
io.technoirlab-target-toolchain-1-<host>-mingw_gcc13_mingw-w64_14_msvcrt/
├── builder.properties
├── konan-sysroot/
│   ├── include/c++ -> ../../toolchain/x86_64-w64-mingw32/include/c++
│   ├── lib/gcc -> ../../toolchain/lib/gcc
│   ├── mingw -> x86_64-w64-mingw32
│   └── x86_64-w64-mingw32 -> ../toolchain/x86_64-w64-mingw32/sysroot/usr/x86_64-w64-mingw32
├── manifest.properties
└── toolchain/
    ├── lib/gcc/x86_64-w64-mingw32/13.4.0/
    └── x86_64-w64-mingw32/
        ├── include/c++/13.4.0/
        └── sysroot/usr/x86_64-w64-mingw32/{include,lib}/
```

For `--sysroot=<sysroot>`, Clang's MinGW driver takes the GCC version from
`<sysroot>/lib/gcc/x86_64-w64-mingw32/<version>/` and searches
`<sysroot>/include/c++/<version>`, among other directories, for the libstdc++
headers. None of those directories reaches crosstool-NG's
`toolchain/x86_64-w64-mingw32/include/c++`, so `konan-sysroot/include/c++`
links it.

### Build and verification

| Platform | Build | Existing-artifact verification | Full pipeline |
| --- | --- | --- | --- |
| Android | `make toolchain PLATFORM=android` | `make check PLATFORM=android` | `make pipeline PLATFORM=android` |
| Linux | `make toolchain PLATFORM=linux` | `make check PLATFORM=linux` | `make pipeline PLATFORM=linux` |
| MinGW | `make toolchain PLATFORM=mingw` | `make check PLATFORM=mingw` | `make pipeline PLATFORM=mingw` |

## Evidence

| Evidence | Source |
| --- | --- |
| Kotlin 2.4.21 configuration | [`konan.properties` at `9180ce…`](https://github.com/JetBrains/kotlin/blob/9180ce6a7a7d3627f88b424717583f28ddca052d/kotlin-native/konan/konan.properties) |
| Kotlin resolver implementation | [`native/utils`](https://github.com/JetBrains/kotlin/tree/9180ce6a7a7d3627f88b424717583f28ddca052d/native/utils/src/org/jetbrains/kotlin/konan) |
| Supported targets/hosts | [Kotlin documentation](https://kotlinlang.org/docs/native-target-support.html) |
| Xcode bundle, SDKs, and minimum host | [Xcode 26.4 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_4-release-notes) |
| Xcode build number | [Apple releases: Xcode 26.4 (`17E192`)](https://developer.apple.com/news/releases/?id=01262026n) |
| Android r20 toolchain/sysroot inspected | [`target-toolchain-2-osx-android_ndk.tar.gz`](https://download.jetbrains.com/kotlin/native/target-toolchain-2-osx-android_ndk.tar.gz), [`target-sysroot-1-android_ndk.tar.gz`](https://download.jetbrains.com/kotlin/native/target-sysroot-1-android_ndk.tar.gz) |
| Linux x64 archive inspected | [`x86_64-unknown-linux-gnu-gcc-8.3.0-glibc-2.19-kernel-4.9-2.tar.gz`](https://download.jetbrains.com/kotlin/native/x86_64-unknown-linux-gnu-gcc-8.3.0-glibc-2.19-kernel-4.9-2.tar.gz) |
| Linux ARM64 archive inspected | [`aarch64-unknown-linux-gnu-gcc-8.3.0-glibc-2.25-kernel-4.9-2.tar.gz`](https://download.jetbrains.com/kotlin/native/aarch64-unknown-linux-gnu-gcc-8.3.0-glibc-2.25-kernel-4.9-2.tar.gz) |
| Linux ARM32 archive inspected | [`arm-unknown-linux-gnueabihf-gcc-8.3.0-glibc-2.12.1-kernel-4.9-1.tar.gz`](https://download.jetbrains.com/kotlin/native/arm-unknown-linux-gnueabihf-gcc-8.3.0-glibc-2.12.1-kernel-4.9-1.tar.gz) |
| MinGW archive inspected | [`msys2-mingw-w64-x86_64-2.tar.gz`](https://download.jetbrains.com/kotlin/native/msys2-mingw-w64-x86_64-2.tar.gz) |
| Project descriptors and layout contract | [`toolchains/README.md`](../toolchains/README.md) |
| Project consumer | [`sample/build.gradle.kts`](../sample/build.gradle.kts) |
