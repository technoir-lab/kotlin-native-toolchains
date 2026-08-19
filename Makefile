.DEFAULT_GOAL := help
.NOTPARALLEL:

NDK_DIR ?=
OUTPUT_DIR ?=
TOOLCHAIN_DIR ?= $(OUTPUT_DIR)
ARCHIVE ?= 0
FORCE ?= 0
BUILDER_ARGS ?=
GRADLE_ARGS ?=

SHELL_SOURCES := $(shell find scripts toolchains -type f -name '*.sh' -print | LC_ALL=C sort)
TOOLCHAIN_INTERMEDIATE_DIRS := build/konan-linux-check build/konan-mingw-check

TOOLCHAIN_BUILD_ARGS :=
ifneq ($(strip $(NDK_DIR)),)
TOOLCHAIN_BUILD_ARGS += --ndk-dir "$(NDK_DIR)"
endif
ifneq ($(strip $(OUTPUT_DIR)),)
TOOLCHAIN_BUILD_ARGS += --output-dir "$(OUTPUT_DIR)"
endif
ifeq ($(ARCHIVE),1)
TOOLCHAIN_BUILD_ARGS += --archive
endif
ifeq ($(FORCE),1)
TOOLCHAIN_BUILD_ARGS += --force
endif

.PHONY: help platforms require-platform toolchain archive lint shellcheck test test-platform-selection test-clean test-host test-sample-verifier test-sample-build-contract test-naming test-docker-builder test-linux-builder test-mingw-builder test-archive test-build-lifecycle test-builder-safety sample verify check pipeline build clean

help:
	@printf '%s\n' \
		'Kotlin/Native toolchain build pipeline' \
		'' \
		'Targets:' \
		'  make toolchain  Build the selected platform artifact.' \
		'  make archive    Build the artifact and a publishable archive in build/dist.' \
		'  make lint       Run ShellCheck over all shell sources.' \
		'  make test       Run all automated tests and lint.' \
		'  make sample     Verify the artifact and build platform samples.' \
		'  make check      Run tests, then verify and build samples.' \
		'  make pipeline   Build the artifact, then run make check.' \
		'  make build      Alias for make pipeline.' \
		'  make platforms  List registered platform implementations.' \
		'  make clean      Remove Gradle outputs and intermediate toolchain artifacts.' \
		'' \
		'Variables:' \
		'  PLATFORM=<id>             Required for platform-dependent targets.' \
		'                            Supported ids: android, linux, mingw.' \
		'  NDK_DIR=/path             Source NDK for the Android builder.' \
		'  OUTPUT_DIR=/path          Artifact destination; samples reuse it.' \
		'  TOOLCHAIN_DIR=/path       Existing artifact used by make sample.' \
		'  ARCHIVE=1                 Also create build/dist/<artifact-name>.tar.gz.' \
		'  FORCE=1                   Explicitly replace builder outputs.' \
		'  BUILDER_ARGS="..."        Additional platform-builder arguments.' \
		'  GRADLE_ARGS="..."         Additional sample Gradle arguments.'

platforms:
	@./scripts/build-native-toolchain.sh --help

require-platform:
ifeq ($(strip $(PLATFORM)),)
	@printf 'error: PLATFORM is required; choose android, linux, or mingw\n' >&2
	@exit 2
else
	@:
endif

toolchain: require-platform
	@./scripts/build-native-toolchain.sh "$(PLATFORM)" $(TOOLCHAIN_BUILD_ARGS) $(BUILDER_ARGS)

archive:
	@$(MAKE) toolchain ARCHIVE=1

lint: shellcheck

shellcheck:
	@command -v shellcheck >/dev/null 2>&1 || { \
		printf 'error: ShellCheck is required; install it with brew install shellcheck\n' >&2; \
		exit 127; \
	}
	@shellcheck -x $(SHELL_SOURCES)

test: lint test-platform-selection test-clean test-host test-sample-verifier test-sample-build-contract test-naming test-docker-builder test-linux-builder test-mingw-builder test-build-lifecycle test-builder-safety test-archive

test-platform-selection:
	@./scripts/tests/test-make-platform-required.sh

test-clean:
	@./scripts/tests/test-make-clean.sh

test-host:
	@./scripts/tests/test-native-toolchain-host.sh

test-sample-verifier:
	@./scripts/tests/test-sample-verifier.sh

test-sample-build-contract:
	@./scripts/tests/test-sample-build-contract.sh

test-naming:
	@./scripts/tests/test-native-toolchain-naming.sh

test-docker-builder:
	@./scripts/tests/test-docker-builder.sh

test-linux-builder:
	@./scripts/tests/test-linux-builder-contract.sh

test-mingw-builder:
	@./scripts/tests/test-mingw-builder-contract.sh

test-archive:
	@./scripts/tests/test-reproducible-archive.sh

test-build-lifecycle:
	@./scripts/tests/test-native-toolchain-build-lifecycle.sh

test-builder-safety:
	@./scripts/tests/test-build-output-safety.sh

sample: require-platform
	@NATIVE_TOOLCHAIN="$(TOOLCHAIN_DIR)" \
		./scripts/check-native-samples.sh "$(PLATFORM)" $(GRADLE_ARGS)

verify: sample

check: require-platform test sample

pipeline: toolchain check

build: pipeline

clean:
	@rm -rf -- $(TOOLCHAIN_INTERMEDIATE_DIRS)
	@./sample/gradlew -p sample clean $(GRADLE_ARGS)
