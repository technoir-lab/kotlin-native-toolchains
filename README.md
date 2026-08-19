# Kotlin/Native toolchains

This proof of concept builds Kotlin/Native executables for all four Android
Native targets, Linux x64 and ARM64, and MinGW x64 from macOS ARM64 or Linux
x64 hosts. Android replaces Kotlin/Native's cached target Clang and sysroot
with Android NDK r29. Linux replaces the cached GCC distributions with
source-built GCC 13/glibc 2.35 sysroots. MinGW supplies a source-built GCC
13/MinGW-w64 10 MSVCRT sysroot. Linux and MinGW retain Kotlin/Native's host
LLVM and LLD.

The shared project environment is pinned to:

- Kotlin/Kotlin Gradle plugin 2.4.10
- Gradle 9.7.0
- JDK 21

The toolchain builder and platform registry live at the repository root. The
self-contained Kotlin Multiplatform example and its Gradle wrapper live under
`sample/`. The Gradle plugin is maintained in
[kmp-gradle-plugins](https://github.com/technoir-lab/kmp-gradle-plugins/tree/main/native-toolchains-gradle-plugin).
Until it is released, publish its `dev` version to Maven Local before building
the sample:

```bash
../kmp-gradle-plugins/gradlew \
  -p ../kmp-gradle-plugins \
  :native-toolchains-gradle-plugin:publishToMavenLocal
```

The sample resolves `io.technoirlab.native-toolchains` from `mavenLocal()`.

On macOS, install the dependencies required by the automated test suite with
Homebrew:

```bash
brew install openjdk@21 shellcheck
```

## What is customized

There are two different LLVM-related components in a Kotlin/Native build:

1. Kotlin/Native's compiler-side LLVM translates Kotlin IR and bitcode.
2. The target toolchain supplies target headers, libraries, CRT objects, and
   runtime archives; Android also supplies target Clang and linker tools.

This project changes only the second component. It does not build LLVM from
source, set `kotlin.native.llvm`, or use `-Xllvm-variant`. JetBrains documents
those compiler-side options separately in
[BUILDING_LLVM.md](https://github.com/JetBrains/kotlin/blob/master/kotlin-native/BUILDING_LLVM.md).

Kotlin/Native reads target settings from `konan.properties`. The project uses
the supported `-Xoverride-konan-properties` mechanism described in
[HACKING.md](https://github.com/JetBrains/kotlin/blob/master/kotlin-native/HACKING.md)
instead of modifying the Kotlin/Native installation.

## Platform registry

Target-specific toolchain files live in `toolchains/<platform>`, with each
platform descriptor stored alongside its builder inputs and compatibility
files:

| Platform  | Kotlin/Native targets                                          |
|-----------|----------------------------------------------------------------|
| `android` | `android_arm32`, `android_arm64`, `android_x86`, `android_x64` |
| `linux`   | `linux_x64`, `linux_arm64`                                     |
| `mingw`   | `mingw_x64`                                                    |

The root Makefile resolves each selected platform through these descriptors.
Platform-dependent targets require an explicit `PLATFORM` selection:

```bash
make toolchain PLATFORM=android  # build the selected artifact
make lint                        # run ShellCheck over all shell sources
make test                        # run all automated tests and lint
make sample PLATFORM=android     # verify the artifact and compile/link every sample
make check PLATFORM=android      # test, verify, and compile/link using an existing artifact
make pipeline PLATFORM=android   # build the artifact, then run the complete check
```

`make lint` (or `make shellcheck`) requires `shellcheck` on `PATH`. ShellCheck
also runs as part of `make test`.

Builder inputs and outputs can be selected without bypassing the generic
dispatcher:

```bash
make pipeline PLATFORM=android NDK_DIR=/absolute/path/to/android-ndk-r29
make pipeline PLATFORM=linux
make pipeline PLATFORM=mingw
make archive PLATFORM=android OUTPUT_DIR=/absolute/path/to/toolchain
make sample PLATFORM=linux TOOLCHAIN_DIR=/absolute/path/to/existing/toolchain
```

`OUTPUT_DIR` is automatically reused as `TOOLCHAIN_DIR` by later pipeline
stages. Set `FORCE=1` only when the exact builder output may be replaced, and
use `GRADLE_ARGS='--configuration-cache'` to forward Gradle options. `make
clean` removes Gradle outputs and the intermediate Kotlin/Native verification
caches, while deliberately keeping `build/toolchains` artifacts and
publishable archives.

Host detection is shared by platform builders and normalizes macOS and Linux
into a host OS, architecture, and Kotlin/Native host id. Android, Linux, and
MinGW support macOS ARM64 and Linux x64. Other host combinations are rejected;
Kotlin/Native 2.4.10 does not provide a Linux ARM64 compiler host.

## Build the toolchain

### Android

The Android toolchain is pinned to:

- Android NDK 29.0.14206865
- Android API 21

The Android builder reads the NDK from `$ANDROID_HOME`:

```bash
make toolchain PLATFORM=android
```

Use the NDK package for the current host: `darwin-x86_64` on macOS ARM64 (the
upstream NDK host tag retains that name) or `linux-x86_64` on Linux x64. The
builder requires Bash, `rsync`, and either `shasum` or `sha256sum`.

Artifact packages use the stable form
`<namespace>-<role>-<revision>-<konan-host>-<target-family>`. This follows the
useful structure of Kotlin/Native dependency package names without reusing a
JetBrains identifier. On a macOS ARM64 host, the resulting directory is:

```text
build/toolchains/io.technoirlab-target-toolchain-1-macos_arm64-android_ndk_r29/
├── compat/
│   └── liblegacy-sync-arm32.a
├── konan-sysroot/
│   └── android-21/
│       ├── arch-arm -> ../../toolchain/sysroot
│       ├── arch-arm64 -> ../../toolchain/sysroot
│       ├── arch-x86 -> ../../toolchain/sysroot
│       └── arch-x86_64 -> ../../toolchain/sysroot
├── manifest.properties
└── toolchain/
    └── ...complete NDK LLVM prebuilt...
```

The complete copy is roughly the size of the NDK host prebuilt and remains
usable if the source NDK is moved or removed. All internal compatibility links
are relative. Linux x86_64 builds use `linux_x64` in the package name. The
package revision is independent from the upstream NDK revision: bump it when
the packaging contract changes, while `android_ndk_r29` identifies the target
family.

Make variables for the builder:

```text
NDK_DIR=/absolute/path
OUTPUT_DIR=/absolute/path
ARCHIVE=1
FORCE=1
```

`ARCHIVE=1` creates `build/dist/<artifact-name>.tar.gz`. Archives are
reproducible: entries are sorted, ownership is fixed to root, timestamps are
fixed to `2000-01-01T00:00:00Z`, and gzip omits its filename and timestamp
header. The
manifest records the stable
`namespace:role:revision:host:target-family` artifact identity and does not
record the local source NDK path. Existing output is never replaced unless
`FORCE=1` is explicit. Additional platform-specific options can be passed
through `BUILDER_ARGS`. Output paths containing whitespace, semicolons, or
newlines are unsupported because Kotlin/Native's property encoding cannot
represent them safely.

### Linux

The Linux toolchain builder is pinned to:

- crosstool-NG 1.26.0
- GCC 13.2.0, glibc 2.35, Linux 5.15.118 headers, binutils 2.40, and
  zlib 1.2.13
- Ubuntu 24.04 builder container

Docker must be available. The builder always uses a digest-pinned container
matching the host architecture (`linux/arm64` on Apple Silicon and
`linux/amd64` on Linux x64), and builds both target distributions
sequentially with a shared crosstool-NG source cache. Its container user adopts
the invoking uid/gid so native-Linux bind-mount outputs stay host-writable:

```bash
make toolchain PLATFORM=linux
make archive PLATFORM=linux
```

The source-controlled crosstool-NG configuration and build script are under
`toolchains/linux/builder`. The builder verifies source archive digests. A
Linux x64 host produces the same layout with `linux_x64` in the package name;
a macOS ARM64 host produces:

```text
build/toolchains/io.technoirlab-target-toolchain-1-macos_arm64-linux_gcc13_glibc2.35/
├── builder.properties
├── manifest.properties
└── targets/
    ├── linux_x64/   # x86_64-unknown-linux-gnu toolchain and sysroot
    └── linux_arm64/ # aarch64-unknown-linux-gnu toolchain and sysroot
```

The compiled toolchain programs are Linux-hosted build products. Kotlin/Native
uses their sysroots, CRT objects, static C++ and GCC runtimes; its own host
LLVM/LLD performs compilation and linking.

### MinGW

The MinGW x64 toolchain builder is pinned to:

- crosstool-NG 1.26.0
- GCC 13.2.0, MinGW-w64 10.0.0, binutils 2.40, and zlib 1.2.13
- the MSVCRT runtime and POSIX thread model
- Ubuntu 24.04 builder container

Docker must be available. As with the Linux builder, the digest-pinned
container matches the host architecture and writes its bind-mounted output as
the invoking uid/gid:

```bash
make toolchain PLATFORM=mingw
make archive PLATFORM=mingw
```

The crosstool-NG configuration, source build script, and provenance are under
`toolchains/mingw/builder`. A macOS ARM64 host produces:

```text
build/toolchains/io.technoirlab-target-toolchain-1-macos_arm64-mingw_gcc13_mingw-w64_10_msvcrt/
├── builder.properties
├── konan-sysroot/
│   ├── lib/gcc -> ../../toolchain/lib/gcc
│   ├── mingw -> x86_64-w64-mingw32
│   └── x86_64-w64-mingw32 -> ../toolchain/x86_64-w64-mingw32/sysroot/usr/x86_64-w64-mingw32
├── manifest.properties
└── toolchain/ # complete x86_64-w64-mingw32 crosstool-NG distribution
```

Linux x64 hosts use `linux_x64` in the package name. The compiled GCC and
binutils programs are Linux-hosted build products; Kotlin/Native consumes the
relocatable headers, CRT objects, MinGW import libraries, and GCC runtimes
through the compatibility links while continuing to compile and link with its
own host LLVM and LLD.

## Build all Kotlin/Native samples

The sample has one shared `main` function. Build the Android targets and run
their artifact verifiers with:

```bash
make sample PLATFORM=android
```

To use a moved or extracted artifact:

```bash
make sample PLATFORM=android \
  TOOLCHAIN_DIR=/absolute/path/to/io.technoirlab-target-toolchain-1-macos_arm64-android_ndk_r29
```

For Linux, select the platform and its artifact:

```bash
make sample PLATFORM=linux \
  TOOLCHAIN_DIR=/absolute/path/to/io.technoirlab-target-toolchain-1-macos_arm64-linux_gcc13_glibc2.35
```

For MinGW x64:

```bash
make sample PLATFORM=mingw \
  TOOLCHAIN_DIR=/absolute/path/to/io.technoirlab-target-toolchain-1-macos_arm64-mingw_gcc13_mingw-w64_10_msvcrt
```

Linux verification builds debug and release ELF files for both targets with an
isolated persistent Kotlin/Native cache under `build/konan-linux-check`,
verifies their architectures, dynamic loaders, Linux 5.15.118 ABI note, and
glibc 2.34+ symbol requirements, then executes all four binaries in
digest-pinned Ubuntu 22.04 containers. Kotlin Gradle may eagerly cache its
default GCC or MSYS2 packages for declared targets, so verification checks
produced binaries rather than treating cache presence as toolchain selection.

Verification requires `file`, `objdump`, Docker, and multi-architecture
container execution for the non-native sample architecture.

MinGW verification builds debug and release x86-64 PE files, confirms that
each contains the source-built GCC 13.2.0 runtime marker, imports MSVCRT rather
than UCRT, and rejects dynamic GCC, C++, or winpthreads runtime DLL
dependencies. It then executes both binaries in a digest-pinned amd64 Ubuntu
24.04 Wine container and checks their program output. Android verification
links both build types for all four targets and confirms that every expected
executable exists.

Executables are written beneath:

```text
sample/build/bin/androidNativeArm32/debugExecutable/hello.kexe
sample/build/bin/androidNativeArm32/releaseExecutable/hello.kexe
sample/build/bin/androidNativeArm64/{debug,release}Executable/hello.kexe
sample/build/bin/androidNativeX86/{debug,release}Executable/hello.kexe
sample/build/bin/androidNativeX64/{debug,release}Executable/hello.kexe
sample/build/bin/linuxX64/debugExecutable/hello.kexe
sample/build/bin/linuxX64/releaseExecutable/hello.kexe
sample/build/bin/linuxArm64/{debug,release}Executable/hello.kexe
sample/build/bin/mingwX64/debugExecutable/hello.exe
sample/build/bin/mingwX64/releaseExecutable/hello.exe
```

## Compatibility details

Kotlin/Native 2.4.10 expects an older NDK layout:

- separate `android-21/arch-*` sysroots;
- `<triple>/bin/ar` inside the target toolchain;
- a linker target without the API level;
- several legacy ARM32 `__sync_*` helpers.

NDK r29 uses a unified sysroot and LLVM tools. The builder supplies only the
compatibility layout needed by Kotlin/Native: relative sysroot links, `ar`
links to `llvm-ar`, API-qualified linker targets, and a small ARM32 archive
implemented with Clang's `__atomic_*` operations.

The compatibility code is intentionally pinned to Kotlin/Native 2.4.10 and the
eight symbols observed in that runtime. Re-test every ABI before changing the
Kotlin or NDK version.

## Run on a device or emulator

Android Native outputs cannot run on macOS. For a device matching the selected
ABI:

```bash
adb push sample/build/bin/androidNativeArm64/debugExecutable/hello.kexe \
  /data/local/tmp/hello
adb shell chmod 755 /data/local/tmp/hello
adb shell /data/local/tmp/hello
```

Expected output:

```text
Hello from Kotlin/Native
```

Use the ARM32 binary for `armeabi-v7a` devices and the x86/x86_64 binaries for
matching emulators.

## Clean up

Gradle outputs and the isolated Linux and MinGW Kotlin/Native verification
caches can be removed with `make clean`. Generated artifacts and publishable
archives live under the root `build` directory, but `make clean` preserves
`build/toolchains` and `build/dist`. Remove exact published outputs separately
when they are no longer needed.
