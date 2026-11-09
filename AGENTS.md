# Repository guidance

## Project overview

This repository is a proof of concept for building relocatable target
toolchains used by Kotlin/Native. It supports Android, Linux, and MinGW target
families from macOS ARM64 and Linux x64 hosts.

- The root `Makefile` is the public build and test interface.
- `scripts/` contains the shared Bash implementation and its tests.
- `toolchains/<platform>/` contains each platform descriptor, builder inputs,
  and compatibility files.
- `sample/` is a self-contained Kotlin Multiplatform consumer project. Its
  Gradle wrapper and build files live in that directory.
- Generated toolchains and archives live under `build/`; do not edit them as
  source files.
- Tags `v1`, `v2`, … run `.github/workflows/release.yaml`, which repeats
  `make test` and publishes a GitHub release. Archives are built locally and
  attached with `make upload PLATFORM=<id> RELEASE=v<N>`.
- The sample depends on the `dev` version of
  `io.technoirlab.native-toolchains`, published to Maven Local from the
  neighboring `kmp-gradle-plugins` repository.

The pinned development environment is Kotlin 2.4.21, Gradle 9.8.2, and JDK
25. Linux and MinGW builders require Docker. Android builds require Android
NDK 29.0.14206865.

## Command execution

Always run `gh` commands outside the sandbox; GitHub CLI does not work in the
sandbox. Always run Gradle wrapper commands outside the sandbox as well,
including `./gradlew`, `./sample/gradlew`, and wrappers in neighboring
repositories.

Prefer the root Make targets when they cover the task:

```bash
make lint
make test
make platforms
make toolchain PLATFORM=android
make sample PLATFORM=android
make check PLATFORM=android
make pipeline PLATFORM=android
```

Platform-dependent targets require an explicit `PLATFORM=android`,
`PLATFORM=linux`, or `PLATFORM=mingw`. Do not start a full toolchain build just
to validate an unrelated shell change: Android needs an NDK, while Linux and
MinGW builds are long-running Docker builds.

For focused tests, run the matching executable under `scripts/tests/`. Run
`make test` before handoff when practical; it includes ShellCheck and all
contract tests without building the toolchains. Use `make check
PLATFORM=<id>` only when a compatible existing artifact is available, and
`make pipeline PLATFORM=<id>` when the task specifically requires rebuilding
one.

## Implementation conventions

- Bash scripts use `#!/usr/bin/env bash` and `set -euo pipefail`.
- Quote path and variable expansions, use `local` for function variables, and
  preserve actionable `error:` messages on stderr.
- Shared behavior belongs in `scripts/lib/`; platform entry points should use
  the registry and lifecycle helpers rather than duplicate them.
- Keep `toolchains/<platform>/<platform>.properties` consistent with the
  descriptor and manifest contract documented in `toolchains/README.md`.
- Package names and artifact identities are stable interfaces. If packaging
  layout or semantics change, update the relevant package revision and tests.
- Toolchain artifacts must remain relocatable and reproducible. Avoid absolute
  source paths in artifacts, use relative internal symlinks, and preserve the
  fixed archive metadata rules.
- Add or update a focused shell test for behavioral changes. Test scripts use
  helpers from `scripts/tests/lib/assertions.sh` and should clean up temporary
  state with traps.
- Keep the sample small: it exists to prove that every configured native
  target compiles and links through the external Gradle plugin.

## Artifact safety

Builder output is intentionally not overwritten unless `FORCE=1` is explicit.
Preserve that guard. Treat `FORCE=1`, custom `OUTPUT_DIR` values, archive
creation, and cleanup changes as destructive or high-risk paths and verify the
exact target before running them. `make clean` is designed to retain built
toolchains and publishable archives; do not broaden its deletion scope without
corresponding safety tests and documentation.

`make upload` publishes archives to a GitHub release. Run it, and push release
tags, only when explicitly asked. It replaces existing release assets only when
`FORCE=1` is set, and then deletes them before uploading the replacements.
Preserve that guard and the digest check after the upload.

## Commits and Pull Requests

- Use descriptive branch names without AI harness prefixes (such as `codex/`, `claude/`, `cursor/`, or `junie/`).
- Keep commits focused and use short, imperative commit subjects.
- Do not add a `Co-Authored-By` trailer.
- PR descriptions should explain the problem, the changes made, and the resulting behavior. Include compatibility impacts, remaining limitations, and links to related issues when relevant. Do not include checks performed, validation commands, or validation results.
