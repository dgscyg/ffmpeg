#!/usr/bin/env bash
# build-ffmpeg-linux.sh — FFmpeg n9.0 全功能静态 SDK 构建脚本 (Linux x86_64 / arm64)
# 默认原生全量支持:
#   - Intel QSV / oneVPL (x86_64)
#   - NVIDIA NVENC / NVDEC / CUDA (x86_64)
#   - AMD AMF (x86_64)
#   - 华为昇腾 Huawei Ascend DVPP (h264_ascend / hevc_ascend, x86_64 & aarch64)
#   - 瑞芯微 Rockchip RK3588/RK3568 (rkmpp + librga 2D + libdrm + v4l2-m2m, aarch64)
# 产物：dist/ffmpeg-n9.0-linux-<arch>-full.tar.gz
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

FFMPEG_VER="${FFMPEG_VER:-9.0}"
NV_CODEC_VER="${NV_CODEC_VER:-n12.2.72.0}"
AMF_TAG="${AMF_TAG:-v1.5.3}"
DAV1D_VER="${DAV1D_VER:-1.5.1}"
SVT_VER="${SVT_VER:-v4.0.1}"
MPP_COMMIT="${MPP_COMMIT:-develop}"
RGA_COMMIT="${RGA_COMMIT:-main}"

INSTALL_PREFIX="${1:-${INSTALL_PREFIX:-/opt/ffmpeg-n9}}"
DIST_DIR="${2:-${DIST_DIR:-${ROOT_DIR}/dist}}"
mkdir -p "$INSTALL_PREFIX" "$DIST_DIR"
INSTALL_PREFIX="$(cd "$INSTALL_PREFIX" && pwd)"
DIST_DIR="$(cd "$DIST_DIR" && pwd)"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64|amd64) ARCH="x86_64" ;;
    aarch64|arm64) ARCH="aarch64" ;;
    *) echo "不支持的架构: $ARCH" >&2; exit 1 ;;
esac

PKG_ARCH="$ARCH"
[ "$PKG_ARCH" = "x86_64" ] && PKG_ARCH="amd64"
[ "$PKG_ARCH" = "aarch64" ] && PKG_ARCH="arm64"

log()  { echo "[ffmpeg-build] $*"; }
fail() { echo "[ffmpeg-build] FATAL: $*" >&2; exit 1; }

SUDO=""
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
fi

install_apt_deps() {
    if ! command -v apt-get >/dev/null 2>&1; then return 0; fi
    log "安装系统构建依赖..."
    $SUDO apt-get update -qq
    $SUDO apt-get install -y -qq --no-install-recommends \
        ca-certificates curl git patch pkg-config xz-utils \
        build-essential cmake ninja-build meson nasm yasm python3 \
        libssl-dev zlib1g-dev \
        libx264-dev libx265-dev libnuma-dev libvpx-dev libopus-dev libmp3lame-dev libaom-dev \
        libfreetype-dev libfontconfig1-dev libharfbuzz-dev libass-dev libfribidi-dev libunibreak-dev \
        libbz2-dev libpng-dev libbrotli-dev libexpat1-dev libglib2.0-dev libgraphite2-dev \
        libsrtp2-dev libva-dev libdrm-dev \
        $(case "$ARCH" in x86_64) echo "libvpl-dev" ;; esac)
}

install_apt_deps
mkdir -p "$INSTALL_PREFIX" "$DIST_DIR"
if [ "$(id -u)" -ne 0 ]; then
    $SUDO chown -R "$(id -u):$(id -g)" "$INSTALL_PREFIX" 2>/dev/null || true
fi

mkdir -p "$INSTALL_PREFIX/include" "$INSTALL_PREFIX/lib/pkgconfig"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

fetch_tarball() {
    rm -f "$2"
    curl -fsSL --retry 5 --retry-delay 2 --retry-connrefused -H "User-Agent: $UA" -o "$2" "$1" || fail "下载失败: $1"
    [ -s "$2" ] || fail "下载为空: $1"
}

# 1. 硬件加速头文件
log "安装 Huawei AscendCL / DVPP 硬件加速头文件..."
mkdir -p "$INSTALL_PREFIX/include/acl/ops"
cp -rf "$ROOT_DIR/include/acl/"* "$INSTALL_PREFIX/include/acl/"

if [ "$ARCH" = "x86_64" ]; then
    log "安装 nv-codec-headers ($NV_CODEC_VER)..."
    fetch_tarball "https://api.github.com/repos/FFmpeg/nv-codec-headers/tarball/$NV_CODEC_VER" "$WORK_DIR/nvcodec.tgz"
    mkdir -p "$WORK_DIR/nvcodec"
    tar xzf "$WORK_DIR/nvcodec.tgz" -C "$WORK_DIR/nvcodec" --strip-components=1
    make -C "$WORK_DIR/nvcodec" install PREFIX="$INSTALL_PREFIX" >/dev/null

    log "安装 AMD AMF 头文件 ($AMF_TAG)..."
    fetch_tarball "https://api.github.com/repos/GPUOpen-LibrariesAndSDKs/AMF/tarball/$AMF_TAG" "$WORK_DIR/amf.tgz"
    mkdir -p "$WORK_DIR/amf"
    tar xzf "$WORK_DIR/amf.tgz" -C "$WORK_DIR/amf" --strip-components=1
    mkdir -p "$INSTALL_PREFIX/include/AMF"
    cp -rf "$WORK_DIR/amf/amf/public/include/"* "$INSTALL_PREFIX/include/AMF/"
fi

# 2. 自编静态依赖库 (dav1d + SVT-AV1)
log "编译 dav1d $DAV1D_VER (静态库)..."
fetch_tarball "https://code.videolan.org/videolan/dav1d/-/archive/$DAV1D_VER/dav1d-$DAV1D_VER.tar.gz" "$WORK_DIR/dav1d.tgz"
mkdir -p "$WORK_DIR/dav1d"
tar xzf "$WORK_DIR/dav1d.tgz" -C "$WORK_DIR/dav1d" --strip-components=1
meson setup "$WORK_DIR/dav1d/build" "$WORK_DIR/dav1d" \
    --prefix "$INSTALL_PREFIX" --libdir lib --buildtype release --default-library static \
    -Denable_tools=false -Denable_tests=false -Denable_examples=false >/dev/null
ninja -C "$WORK_DIR/dav1d/build" -j"$JOBS" install >/dev/null

log "编译 SVT-AV1 $SVT_VER (静态库)..."
fetch_tarball "https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/$SVT_VER/SVT-AV1-$SVT_VER.tar.gz" "$WORK_DIR/svt.tgz"
mkdir -p "$WORK_DIR/svt"
tar xzf "$WORK_DIR/svt.tgz" -C "$WORK_DIR/svt" --strip-components=1
cmake -S "$WORK_DIR/svt" -B "$WORK_DIR/svt/build" -G Ninja \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_APPS=OFF -DENABLE_TESTING=OFF \
    -DENABLE_LTO=OFF -DENABLE_IPO=OFF >/dev/null
ninja -C "$WORK_DIR/svt/build" -j"$JOBS" install >/dev/null

# 3. 若 aarch64 则构建 rockchip_mpp 与 librga 静态库 (支持 RK3588/RK3568 全量硬件加速)
if [ "$ARCH" = "aarch64" ]; then
    log "编译 rockchip_mpp (aarch64 静态库)..."
    fetch_tarball "https://api.github.com/repos/rockchip-linux/mpp/tarball/$MPP_COMMIT" "$WORK_DIR/mpp.tgz"
    mkdir -p "$WORK_DIR/mpp"
    tar xzf "$WORK_DIR/mpp.tgz" -C "$WORK_DIR/mpp" --strip-components=1
    cmake -S "$WORK_DIR/mpp" -B "$WORK_DIR/mpp/build" -G Ninja \
        -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF -DBUILD_TEST=OFF >/dev/null
    ninja -C "$WORK_DIR/mpp/build" -j"$JOBS" install >/dev/null

    log "安装 rockchip librga (aarch64 库与头文件)..."
    fetch_tarball "https://api.github.com/repos/airockchip/librga/tarball/$RGA_COMMIT" "$WORK_DIR/rga.tgz"
    mkdir -p "$WORK_DIR/rga"
    tar xzf "$WORK_DIR/rga.tgz" -C "$WORK_DIR/rga" --strip-components=1
    mkdir -p "$INSTALL_PREFIX/include/rga" "$INSTALL_PREFIX/lib/pkgconfig"
    cp -rf "$WORK_DIR/rga/include/"* "$INSTALL_PREFIX/include/rga/"
    cp -rf "$WORK_DIR/rga/include/"* "$INSTALL_PREFIX/include/"
    if [ -d "$WORK_DIR/rga/libs/Linux/gcc-aarch64" ]; then
        cp -af "$WORK_DIR/rga/libs/Linux/gcc-aarch64/"* "$INSTALL_PREFIX/lib/"
    fi
    cat << EOF > "$INSTALL_PREFIX/lib/pkgconfig/librga.pc"
prefix=${INSTALL_PREFIX}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: librga
Description: Userspace interface to Rockchip RGA 2D accelerator
Version: 2.1.0
Requires.private: libdrm
Libs: -L\${libdir} -lrga
Cflags: -I\${includedir} -I\${includedir}/rga
EOF
fi

# 4. 下载 FFmpeg n9.0 源码并打补丁
log "下载 FFmpeg $FFMPEG_VER 源码..."
mkdir -p "$WORK_DIR/ffmpeg"
FFMPEG_URL="https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n${FFMPEG_VER}.tar.gz"
if curl -fsSL --retry 5 --retry-delay 2 --retry-connrefused -H "User-Agent: $UA" -o "$WORK_DIR/ffmpeg.tgz" "$FFMPEG_URL" && [ -s "$WORK_DIR/ffmpeg.tgz" ]; then
    tar xzf "$WORK_DIR/ffmpeg.tgz" -C "$WORK_DIR/ffmpeg" --strip-components=1
else
    log "GitHub 归档拉取失败，回退至 ffmpeg.org..."
    fetch_tarball "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VER.tar.xz" "$WORK_DIR/ffmpeg.tar.xz"
    tar xJf "$WORK_DIR/ffmpeg.tar.xz" -C "$WORK_DIR/ffmpeg" --strip-components=1
fi

if [ -f "$ROOT_DIR/patches/ffmpeg9_rkmpp_enc_frame_lifetime.patch" ]; then
    log "应用补丁: ffmpeg9_rkmpp_enc_frame_lifetime.patch"
    patch -d "$WORK_DIR/ffmpeg" -p1 -N -r - < "$ROOT_DIR/patches/ffmpeg9_rkmpp_enc_frame_lifetime.patch" || true
fi

if [ -f "$ROOT_DIR/patches/ffmpeg9_ascend_dvpp.patch" ]; then
    log "应用补丁: ffmpeg9_ascend_dvpp.patch (华为昇腾 DVPP 硬解)"
    # 该补丁现在承载真实 VDEC 调用链，应用失败必须让构建失败，
    # 否则会退化成“没有 h264_ascend/hevc_ascend”的静默错误产物。
    patch -d "$WORK_DIR/ffmpeg" -p1 -N -r - < "$ROOT_DIR/patches/ffmpeg9_ascend_dvpp.patch" \
        || fail "昇腾 DVPP 补丁应用失败（FFmpeg 版本或基线变动？）"
fi

# 5. 配置与编译 FFmpeg
export PKG_CONFIG_PATH="$INSTALL_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

CFG_ARGS=(
    --prefix="$INSTALL_PREFIX"
    --pkg-config-flags="--static"
    --enable-static --disable-shared --enable-pic
    --enable-gpl --enable-version3
    --enable-libx264 --enable-libx265 --enable-libvpx --enable-libopus --enable-libmp3lame
    --enable-libaom --enable-libdav1d --enable-libsvtav1
    --enable-libass --enable-libfreetype --enable-libfontconfig --enable-libharfbuzz --enable-libfribidi
    --enable-decoder=h264 --enable-decoder=hevc --enable-decoder=vp8 --enable-decoder=vp9
    --enable-decoder=av1 --enable-decoder=libdav1d --enable-decoder=mjpeg --enable-decoder=mpeg4
    --enable-decoder=aac --enable-decoder=mp3 --enable-decoder=opus --enable-decoder=pcm_alaw --enable-decoder=pcm_mulaw
    --enable-encoder=libx264 --enable-encoder=libx265 --enable-encoder=libvpx_vp8 --enable-encoder=libvpx_vp9
    --enable-encoder=libsvtav1 --enable-encoder=libaom_av1 --enable-encoder=mjpeg
    --enable-encoder=aac --enable-encoder=libmp3lame --enable-encoder=libopus
    --enable-encoder=pcm_alaw --enable-encoder=pcm_mulaw
    --enable-demuxer=mov --enable-demuxer=flv --enable-demuxer=rtsp --enable-demuxer=rtp
    --enable-demuxer=mpegts --enable-demuxer=avi --enable-demuxer=h264 --enable-demuxer=hevc
    --enable-demuxer=hls --enable-demuxer=matroska --enable-demuxer=image2
    --enable-muxer=mp4 --enable-muxer=flv --enable-muxer=null --enable-muxer=matroska
    --enable-muxer=mpegts --enable-muxer=avi --enable-muxer=hls --enable-muxer=image2
    --enable-protocol=file --enable-protocol=tcp --enable-protocol=udp --enable-protocol=rtmp
    --enable-protocol=pipe --enable-protocol=http --enable-protocol=https
    --enable-filter=scale --enable-filter=format --enable-filter=fps --enable-filter=null
    --enable-filter=drawtext --enable-filter=overlay --enable-filter=crop --enable-filter=pad
    --enable-filter=transpose --enable-filter=vflip --enable-filter=hflip
    --enable-filter=subtitles --enable-filter=ass
    --enable-swresample --enable-swscale --enable-avfilter --enable-avformat
    --disable-doc --disable-ffplay
    --enable-ascend
    --enable-decoder=h264_ascend --enable-decoder=hevc_ascend
    --enable-encoder=h264_ascend --enable-encoder=hevc_ascend
    --enable-filter=scale_ascend --enable-filter=hwupload --enable-filter=hwdownload
    --extra-cflags="-fPIC -DENABLE_DVPP_INTERFACE -I$INSTALL_PREFIX/include -I$INSTALL_PREFIX/include/rga"
    --extra-ldflags="-L$INSTALL_PREFIX/lib"
)

if [ "$ARCH" = "x86_64" ]; then
    CFG_ARGS+=(
        --enable-libvpl
        --enable-ffnvcodec --enable-cuda --enable-cuvid --enable-nvenc --enable-nvdec
        --enable-amf
        --enable-hwaccel=h264_nvdec --enable-hwaccel=hevc_nvdec
        --enable-encoder=h264_nvenc --enable-encoder=hevc_nvenc --enable-encoder=av1_nvenc
        --enable-encoder=h264_qsv --enable-encoder=hevc_qsv --enable-encoder=av1_qsv --enable-encoder=mjpeg_qsv
        --enable-encoder=h264_amf --enable-encoder=hevc_amf --enable-encoder=av1_amf
        --enable-decoder=h264_cuvid --enable-decoder=hevc_cuvid --enable-decoder=av1_cuvid
        --enable-decoder=mjpeg_cuvid --enable-decoder=vp9_cuvid
    )
fi

if [ "$ARCH" = "aarch64" ]; then
    CFG_ARGS+=(
        --enable-libdrm
        --enable-v4l2-m2m
        --enable-rkmpp
        --enable-decoder=h264_rkmpp --enable-decoder=hevc_rkmpp --enable-decoder=vp8_rkmpp --enable-decoder=vp9_rkmpp
        --enable-encoder=h264_rkmpp --enable-encoder=hevc_rkmpp
    )
fi

log "运行 configure ($ARCH)..."
cd "$WORK_DIR/ffmpeg"
./configure "${CFG_ARGS[@]}" || { tail -50 ffbuild/config.log 2>/dev/null || true; fail "FFmpeg configure 失败"; }

log "编译 FFmpeg (make -j$JOBS)..."
make -j"$JOBS"
make install
rm -f "$INSTALL_PREFIX/lib/"libav*.so* "$INSTALL_PREFIX/lib/"libsw*.so*
strip -s "$INSTALL_PREFIX/bin/ffmpeg" "$INSTALL_PREFIX/bin/ffprobe" 2>/dev/null || true

# 拷贝 x86_64 下的 libvpl 依赖到 SDK 库目录，避免下游编译机因缺失 libvpl-dev 报错
if [ "$ARCH" = "x86_64" ]; then
    log "复制系统 libvpl 依赖到 SDK 库目录..."
    for f in /usr/lib/x86_64-linux-gnu/libvpl.so*; do
        [ -e "$f" ] && cp -a "$f" "$INSTALL_PREFIX/lib/" 2>/dev/null || true
    done
fi

# 6. 打包归档
log "打包归档 SDK 与可执行程序..."
PKG_NAME="ffmpeg-n${FFMPEG_VER}-linux-${PKG_ARCH}-full.tar.gz"
tar -czf "${DIST_DIR}/${PKG_NAME}" -C "${INSTALL_PREFIX}" .
log "✓ 已生成归档: ${DIST_DIR}/${PKG_NAME} ($(ls -lh "${DIST_DIR}/${PKG_NAME}" | awk '{print $5}'))"

# 复制独立 CLI 二进制到 dist 供 Release 直接下载
cp -a "$INSTALL_PREFIX/bin/ffmpeg" "${DIST_DIR}/ffmpeg-n${FFMPEG_VER}-linux-${PKG_ARCH}" 2>/dev/null || true
cp -a "$INSTALL_PREFIX/bin/ffprobe" "${DIST_DIR}/ffprobe-n${FFMPEG_VER}-linux-${PKG_ARCH}" 2>/dev/null || true
