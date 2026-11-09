#!/usr/bin/env bash
# Prepares the MinGW builder image. The shared Dockerfile runs this as root in
# its prepare stage. MinGW needs nothing beyond the shared builder image:
# crosstool-NG downloads and verifies the GCC, binutils, and MinGW-w64 sources
# while the toolchain builds.
set -euo pipefail
