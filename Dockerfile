# Multi-stage Dockerfile for building libcamera 0.5.2+rpt20250903 with IMX519 AF patches
# Target: Raspberry Pi Zero 2 W (VC4 pipeline, arm64, Debian Bookworm)
# Build: docker buildx build --builder local-arm64 --platform linux/arm64 --output type=local,dest=./dist .

# --- Stage 1: Build ---
FROM debian:bookworm AS build

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    meson \
    ninja-build \
    cmake \
    pkg-config \
    python3 \
    python3-jinja2 \
    python3-yaml \
    python3-ply \
    openssl \
    libgnutls28-dev \
    liblttng-ust-dev \
    libudev-dev \
    libyaml-dev \
    libevent-dev \
    libdw-dev \
    libunwind-dev \
    libjpeg-dev \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    libyuv-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . /src

RUN meson setup build \
    --prefix=/usr \
    --libdir=lib/aarch64-linux-gnu \
    -Dbuildtype=release \
    -Dpipelines=rpi/vc4 \
    -Dipas=rpi/vc4 \
    -Dpycamera=disabled \
    -Dqcam=disabled \
    -Dcam=disabled \
    -Ddocumentation=disabled \
    -Dtest=false \
    -Dv4l2=enabled \
    -Dgstreamer=enabled \
    -Dwerror=false

RUN ninja -C build -j$(nproc)

RUN DESTDIR=/pkg ninja -C build install

# Strip dev-only files that belong to libcamera-dev on the target system
RUN rm -rf /pkg/usr/include \
    && rm -rf /pkg/usr/lib/aarch64-linux-gnu/pkgconfig \
    && rm -f /pkg/usr/lib/aarch64-linux-gnu/libcamera.so \
    && rm -f /pkg/usr/lib/aarch64-linux-gnu/libcamera-base.so \
    && rm -f /pkg/usr/bin/lc-compliance

# Build .deb package — use the SAME package name as the system package so dpkg
# treats this as an upgrade, not a conflict (avoids breaking rpicam-apps-core dep).
RUN DEB_DIR=/pkg/DEBIAN && mkdir -p "$DEB_DIR" \
    && cat > "$DEB_DIR/control" <<'CTRL'
Package: libcamera0.5
Version: 0.5.2+rpt20250903+imx519af1-1~bpo12+1
Architecture: arm64
Multi-Arch: same
Maintainer: Steve <steve@local>
Depends: libc6, libgnutls30, liblttng-ust1, libstdc++6, libudev1, libyaml-0-2, libyuv0, libdw1, libgcc-s1, libevent-2.1-7, libunwind8, libjpeg62-turbo
Provides: libcamera-ipa (= 0.5.2+rpt20250903+imx519af1-1~bpo12+1)
Replaces: libcamera-ipa
Description: libcamera 0.5.2 with IMX519 autofocus (PDAF) support
 Custom build of raspberrypi/libcamera v0.5.2+rpt20250903 with
 Arducam IMX519 PDAF autofocus patches for VC4 pipeline.
 Includes VC4 IPA module (replaces libcamera-ipa).
CTRL

RUN mkdir -p /out && dpkg-deb --build /pkg /out/libcamera0.5_0.5.2+rpt20250903+imx519af1-1~bpo12+1_arm64.deb

# --- Stage 2: Export ---
FROM scratch AS export
COPY --from=build /out/*.deb /
