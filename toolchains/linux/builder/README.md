# Linux toolchain builder

This source-controlled builder uses crosstool-NG 1.29.0. It:

- builds both Kotlin/Native Linux targets in one Ubuntu 24.04 container;
- pins crosstool-NG 1.29.0 and checks its source archive digest;
- selects GCC 13.4.0, glibc 2.25, Linux 5.15.209 headers, and binutils 2.29.1,
  and configures glibc with `MAKEINFO=:` because the builder's texinfo 7
  cannot build the glibc 2.25 manual;
- builds target zlib 1.2.13 with the prefix `/usr` and stages it into each
  sysroot, so `zlib.pc` works with `PKG_CONFIG_SYSROOT_DIR`;
- installs X.Org protocol 2023.2, Xtrans 1.5.0, libX11 1.8.7, libXext 1.3.4,
  xcb-proto 1.15.2, libxcb 1.15, Wayland 1.22.0, libxkbcommon 1.6.0, and
  Vulkan 1.3.275 headers, without their libraries;
- installs ALSA 1.2.11, PulseAudio 16.1, PipeWire 1.0.5, JACK2 1.9.21, and
  sndio 1.9.0 headers, without their libraries;
- ships the license files of zlib and every graphics and audio component under
  `share/licenses/<name>/` in each target;
- retains canonical lowercase Linux UAPI headers where compatibility aliases
  would otherwise collide on a case-insensitive macOS filesystem;
- once zlib and the header checks have run the target GCC, removes the GCC and
  binutils programs and the other files Kotlin/Native never uses; and
- exports unpacked toolchain roots for the repository's common packager.

## Image inputs

The shared Dockerfile copies `image/` into the builder image before the
toolchain build:

- `sources.lock` pins every source archive the builder downloads itself: its
  version, license files, download URL, and SHA-512 digest. The image build,
  the container build, the host-side artifact checks, and `builder.properties`
  and `manifest.properties` all read it, so updating a source means changing
  its version and digest on one line.
- `graphics-headers.txt` lists the headers every target sysroot must provide.
  The image build checks the header bundle against it, and the host-side
  artifact check requires each entry in both targets.
- `prepare.sh` runs as root in the shared Dockerfile's prepare stage. It
  installs the tools the graphics headers need, downloads and verifies every
  pinned source, collects their license files, and builds the header bundle.
  The builder image receives only `/opt/toolchain-builder` from the stage:
  the header bundle, the license files, and zlib's source, which the
  container build compiles. The tools and the other sources stay out of it.
  Docker reuses the stage until a file in `image/` changes.
- `sources.sh` holds the helpers that read the lock and the header list.

The header bundle carries both the graphics and the audio headers. libX11's
and alsa-lib's headers need only `configure`, so neither library is compiled.
libxcb and Wayland generate their headers only during a full build, so
`prepare.sh` builds those libraries and keeps only their headers. PulseAudio
and PipeWire need many build dependencies just to configure, so `prepare.sh`
installs the headers their meson builds list and generates their `version.h`
the same way. PipeWire's and SPA's headers keep their versioned `pipewire-0.3`
and `spa-0.2` directories, which consumers add to the include path as
PipeWire's pkg-config files do. `build-toolchains.sh` merges the bundle into
each sysroot, refuses any header that would replace an existing one or differ
from one only by case, and compiles the graphics and audio headers with each
target's GCC.

JACK2's root `COPYING` is the GPL, while its headers are LGPL 2.1, whose text
the archive carries only in `android/NOTICE`; both files ship. sndio has no
separate license file, so its ISC license ships as the `sndio.h` header that
contains it.

Upstream sources:

- <https://github.com/crosstool-ng/crosstool-ng/releases/tag/crosstool-ng-1.29.0>
- <https://www.x.org/releases/individual/>
- <https://xcb.freedesktop.org/dist/>
- <https://wayland.freedesktop.org/releases.html>
- <https://xkbcommon.org/>
- <https://github.com/KhronosGroup/Vulkan-Headers/releases/tag/v1.3.275>
- <https://www.alsa-project.org/files/pub/lib/>
- <https://www.freedesktop.org/software/pulseaudio/releases/>
- <https://gitlab.freedesktop.org/pipewire/pipewire/-/tags/1.0.5>
- <https://github.com/jackaudio/jack2/releases/tag/v1.9.21>
- <https://sndio.org/>
