FROM ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90

ARG DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    WINEDEBUG=-all \
    WINEPREFIX=/tmp/wine

RUN apt-get update \
    && apt-get install --yes --no-install-recommends wine64 \
    && rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["/usr/lib/wine/wine64"]
