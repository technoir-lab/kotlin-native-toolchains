ARG UBUNTU_IMAGE=ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90
FROM ${UBUNTU_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive
ARG BUILDER_ARCH=amd64
ARG BUILDER_UID=10001
ARG BUILDER_GID=10001
ARG BUILD_SCRIPT
ARG DOWNLOAD_ZLIB_ARCHIVE=false
ARG CROSSTOOL_NG_VERSION=1.26.0
ARG CROSSTOOL_NG_ARCHIVE_SHA512=7667826f20d6d444bfcd818a21b97d39c9054cdfc8306d7d0fdbeb30e94c099976144771990904d30e236c94af745da1a0b5c79011c34614605fa21c0dd9eda2
ARG ZLIB_VERSION=1.2.13
ARG ZLIB_ARCHIVE_SHA512=99f0e843f52290e6950cc328820c0f322a4d934a504f66c7caa76bd0cc17ece4bf0546424fc95135de85a2656fed5115abb835fd8d8a390d60ffaf946c8887ad

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
        python3-dev \
        rsync \
        tar \
        texinfo \
        unzip \
        wget \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

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

RUN if [ "${DOWNLOAD_ZLIB_ARCHIVE}" = true ]; then \
        curl --fail --location --retry 3 \
            --output /opt/zlib.tar.gz \
            "https://zlib.net/fossils/zlib-${ZLIB_VERSION}.tar.gz" \
        && printf '%s  %s\n' \
            "${ZLIB_ARCHIVE_SHA512}" \
            /opt/zlib.tar.gz | sha512sum --check --strict; \
    fi

RUN groupadd --non-unique --gid "${BUILDER_GID}" ct \
    && useradd --non-unique --uid "${BUILDER_UID}" --gid ct \
        --create-home --shell /bin/bash ct \
    && mkdir -p /opt/toolchain-builder /home/ct/src /home/ct/x-tools \
    && chown -R ct:ct /home/ct

COPY --chown=ct:ct configs /opt/toolchain-builder/configs
COPY --chown=ct:ct ${BUILD_SCRIPT} /opt/toolchain-builder/build.sh

USER ct
WORKDIR /home/ct
ENTRYPOINT ["/opt/toolchain-builder/build.sh"]
