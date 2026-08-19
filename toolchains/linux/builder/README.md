# Linux toolchain builder

This source-controlled builder uses crosstool-NG 1.26.0. It:

- builds both Kotlin/Native Linux targets in one Ubuntu 24.04 container;
- pins crosstool-NG 1.26.0 and checks its source archive digest;
- selects GCC 13.2.0, glibc 2.35, Linux 5.15.118 headers, and binutils 2.40;
- builds and installs target zlib 1.2.13;
- retains canonical lowercase Linux UAPI headers where compatibility aliases
  would otherwise collide on a case-insensitive macOS filesystem; and
- exports unpacked toolchain roots for the repository's common packager.

Upstream sources:

- <https://github.com/crosstool-ng/crosstool-ng/releases/tag/crosstool-ng-1.26.0>
