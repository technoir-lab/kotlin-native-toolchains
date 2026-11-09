# Shared image for the crosstool-NG toolchain builders. The build context is
# the platform's builder directory, which supplies everything platform
# specific: image/prepare.sh, configs/, and the build script. Each ARG is
# declared just before its first use so that changing it rebuilds only the
# layers that depend on it.
#
# The base stage installs the shared packages. The prepare stage runs the
# platform's image/prepare.sh on top of it, independently of crosstool-NG, so
# BuildKit builds the two in parallel and caches each until its own inputs
# change. The builder image is the final stage.

ARG UBUNTU_IMAGE=ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90
FROM ${UBUNTU_IMAGE} AS base

ARG DEBIAN_FRONTEND=noninteractive
ARG BUILDER_ARCH=amd64

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC \
    BUILDER_ARCH=${BUILDER_ARCH}

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        autoconf \
        automake \
        bison \
        bzip2 \
        ca-certificates \
        curl \
        file \
        flex \
        g++ \
        gawk \
        gcc \
        git \
        gperf \
        help2man \
        libncurses-dev \
        libtool \
        libtool-bin \
        make \
        patch \
        pkg-config \
        python3-dev \
        rsync \
        tar \
        texinfo \
        unzip \
        wget \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

# The platform prepares its inputs as root, before the build user exists. Only
# /opt/toolchain-builder is copied into the builder image, so packages that the
# stage installs to prepare the inputs stay behind. The stage is reused until
# the platform's image/ directory changes.
FROM base AS prepare
# Build arguments do not carry over from the base stage.
ARG DEBIAN_FRONTEND=noninteractive
COPY image /opt/toolchain-builder/image
RUN /opt/toolchain-builder/image/prepare.sh

FROM base

ARG CROSSTOOL_NG_VERSION=1.29.0
ARG CROSSTOOL_NG_ARCHIVE_SHA512=d1a80e42fdb09bfc1ce10f179427f894a6215e78af83e41a41e11037b3163af82cf867a42cc70f55ddebcd050675f625e7077d96a3b4b94a8fcbeb0ad135a66d
RUN curl --fail --location --retry 3 \
        --output /tmp/crosstool-ng.tar.gz \
        "https://codeload.github.com/crosstool-ng/crosstool-ng/tar.gz/refs/tags/crosstool-ng-${CROSSTOOL_NG_VERSION}" \
    && printf '%s  %s\n' \
        "${CROSSTOOL_NG_ARCHIVE_SHA512}" \
        /tmp/crosstool-ng.tar.gz | sha512sum --check --strict \
    && mkdir /tmp/crosstool-ng \
    && tar --extract --gzip --file /tmp/crosstool-ng.tar.gz \
        --directory /tmp/crosstool-ng --strip-components=1 \
    && cd /tmp/crosstool-ng \
    && ./bootstrap \
    && ./configure --prefix=/usr/local \
    && make -j"$(nproc)" \
    && make install \
    && rm -rf /tmp/crosstool-ng /tmp/crosstool-ng.tar.gz

COPY --from=prepare /opt/toolchain-builder /opt/toolchain-builder

ARG BUILDER_UID=10001
ARG BUILDER_GID=10001
RUN groupadd --non-unique --gid "${BUILDER_GID}" ct \
    && useradd --non-unique --uid "${BUILDER_UID}" --gid ct \
        --create-home --shell /bin/bash ct \
    && mkdir -p /home/ct/src /home/ct/x-tools \
    && chown -R ct:ct /home/ct

ARG BUILD_SCRIPT
COPY --chown=ct:ct configs /opt/toolchain-builder/configs
COPY --chown=ct:ct ${BUILD_SCRIPT} /opt/toolchain-builder/build.sh

USER ct
WORKDIR /home/ct
ENTRYPOINT ["/opt/toolchain-builder/build.sh"]
