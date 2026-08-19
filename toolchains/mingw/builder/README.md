# MinGW toolchain builder

This source-controlled builder uses crosstool-NG 1.26.0 to build an
`x86_64-w64-mingw32` cross toolchain with GCC 13.2.0, binutils 2.40, and
MinGW-w64 10.0.0. It selects the MSVCRT C runtime and the POSIX thread model so
the resulting libraries satisfy Kotlin/Native 2.4.10's `mingw_x64` linker
contract. The sample verifier enforces static GCC, C++, and winpthreads runtime
linkage at the generated PE boundary.

The build runs in a digest-pinned Ubuntu 24.04 container. Crosstool-NG verifies
the source archives against its checked-in package digests and installs the
component license files into the resulting distribution.

Upstream sources:

- <https://github.com/crosstool-ng/crosstool-ng/releases/tag/crosstool-ng-1.26.0>
- <https://www.mingw-w64.org/>
- <https://gcc.gnu.org/>
