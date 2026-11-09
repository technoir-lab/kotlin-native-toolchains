# Native toolchain registry

Each `*.properties` descriptor declares one Kotlin/Native target-toolchain
family. Generic build and verification entry points dispatch only descriptors
whose `platform.status` is `enabled`. Package-coordinate keys are required when
a platform is enabled; placeholders may defer them until their target-family
contract is known. Android, Linux, and MinGW are currently enabled.

## Descriptor contract

| Key | Meaning |
| --- | --- |
| `schema.version` | Descriptor schema, currently `1`. |
| `platform.id` | Stable CLI id and descriptor filename. |
| `platform.status` | `enabled` or `placeholder`. |
| `konan.targets` | Comma-separated Kotlin/Native target ids. |
| `builder.script` | Project-relative platform builder. |
| `verifier.script` | Project-relative sample verifier. |
| `package.namespace` | Publisher namespace that avoids first-party package-name collisions. |
| `package.role` | Artifact role, such as `target-toolchain`. |
| `package.revision` | Revision of this packaging contract. |
| `package.target.family` | Stable target family, such as `android_ndk_r29`. |

An enabled artifact must emit these common manifest keys in addition to its
platform-specific metadata:

```properties
format.version=1
artifact.platform=<platform.id>
artifact.layout.version=1
artifact.package.namespace=<publisher namespace>
artifact.package.role=<artifact role>
artifact.package.revision=<package revision>
artifact.package.host=<Kotlin/Native host id>
artifact.package.target.family=<target family>
artifact.package.name=<namespace>-<role>-<revision>-<host>-<target family>
artifact.identity=<namespace>:<role>:<revision>:<host>:<target family>
host.os=<macos|linux>
host.arch=<arm64|x64>
host.konan=<Kotlin/Native host id>
host.tag=<upstream toolchain host tag>
konan.targets=<comma-separated target ids>
```

The package host must equal `host.konan`, and the OS, architecture, and Konan
host must form a supported tuple. This project supports macOS ARM64 and Linux
x64.
`artifact.identity` is the stable coordinate form of the package identity.
Existing format-version-1 artifacts without `artifact.package.*` keys remain
valid for migration, but if any package key or identity is present the full set
must satisfy the naming contract.

## Docker builders

Linux and MinGW build in the shared `common/builder/Dockerfile`, driven by
`scripts/lib/docker-builder.sh`. Neither takes platform-specific parameters:
the Docker build context is the platform's builder directory, which provides:

- `image/prepare.sh`, run as root in the Dockerfile's prepare stage, on top of
  the shared packages but without crosstool-NG, before the build user exists.
  It writes the platform's pinned sources or prebuilt inputs under
  `/opt/toolchain-builder`, and may do nothing. The builder image receives
  only that directory from the stage, so packages that `prepare.sh` installs
  to produce its inputs stay out of the builder image. Docker reuses the stage
  until a file in `image/` changes.
- `configs/`, the crosstool-NG configurations.
- The build script named by the platform builder, which runs as the container
  entry point and writes the toolchain to the `/artifacts` bind mount.

## Adding a platform family

To enable another family:

1. Implement the descriptor's builder and verifier scripts.
2. Define its package revision and target family, then produce the common
   manifest contract and a relocatable artifact.
3. Add the corresponding KMP targets and their Konan property overrides.
4. Add platform-specific binary inspection and runtime tests.
5. Change `platform.status` only after at least one host passes the complete
   builder and verifier flow.

Android, Linux, and MinGW use the complete builder/verifier flow described in
the root README. Their supported build hosts are macOS ARM64 and Linux x64.
