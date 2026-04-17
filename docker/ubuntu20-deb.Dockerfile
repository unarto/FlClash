FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

# ---------- 1. Tsinghua apt mirror + system packages ----------
# HTTP before ca-certificates is installed to avoid TLS bootstrap issues.
RUN sed -i 's@http://archive.ubuntu.com/ubuntu/@http://mirrors.tuna.tsinghua.edu.cn/ubuntu/@g' /etc/apt/sources.list \
    && sed -i 's@http://security.ubuntu.com/ubuntu/@http://mirrors.tuna.tsinghua.edu.cn/ubuntu/@g' /etc/apt/sources.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        clang \
        cmake \
        curl \
        file \
        git \
        libayatana-appindicator3-dev \
        libfuse2 \
        libgtk-3-dev \
        libkeybinder-3.0-dev \
        liblzma-dev \
        libsecret-1-dev \
        mlocate \
        ninja-build \
        patchelf \
        pkg-config \
        rpm \
        sudo \
        unzip \
        wget \
        xz-utils \
        zip \
    && rm -rf /var/lib/apt/lists/*

# ---------- 2. Go (Aliyun mirror; Tsinghua golang mirror is gone) ----------
ARG GO_VERSION=1.24.1
ARG TARGETARCH=amd64
RUN curl -fsSL \
        "https://mirrors.aliyun.com/golang/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" \
        -o /tmp/go.tgz \
    && tar -C /usr/local -xzf /tmp/go.tgz \
    && rm -f /tmp/go.tgz

# ---------- 3. Flutter (tarball from flutter-io.cn, much faster than git clone) ----------
ARG FLUTTER_VERSION=3.35.7
RUN curl -fSL \
        "https://storage.flutter-io.cn/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
        -o /tmp/flutter.tar.xz \
    && mkdir -p /opt \
    && tar -xJf /tmp/flutter.tar.xz -C /opt \
    && rm -f /tmp/flutter.tar.xz

# ---------- 4. Environment ----------
ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:/usr/local/go/bin:/root/.pub-cache/bin:${PATH}"
ENV PUB_HOSTED_URL="https://mirrors.tuna.tsinghua.edu.cn/dart-pub"
ENV FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
ENV GOPROXY="https://goproxy.cn,direct"

# Rewrite SSH submodule URLs to HTTPS so cloning works without SSH keys,
# and mark any mounted volume as safe for git.
RUN git config --global url."https://github.com/".insteadOf "git@github.com:" \
    && git config --global --add safe.directory '*'

WORKDIR /work

# ---------- 5. Extra build deps (separate layer to preserve Flutter cache) ----------
RUN apt-get update \
    && apt-get install -y --no-install-recommends g++ libx11-dev \
    && rm -rf /var/lib/apt/lists/*

# ---------- 6. Pre-cache toolchains ----------
RUN flutter config --enable-linux-desktop \
    && flutter --disable-analytics \
    && flutter --version \
    && dart --version \
    && go version
