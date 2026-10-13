#!/usr/bin/env bash
# build-ffmpeg-windows.sh — FFmpeg n9.0 全功能静态 SDK 构建脚本 (Windows x86_64, MinGW/MSYS2)
# 产物：dist/ffmpeg-n9.0-windows-amd64-full.zip
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

FFMPEG_VER="${FFMPEG_VER:-9.0}"
NV_CODEC_VER="${NV_CODEC_VER:-n12.2.72.0}"
AMF_TAG="${AMF_TAG:-v1.4.36}"

INSTALL_PREFIX="${1:-${INSTALL_PREFIX:-/c/tools/ffmpeg-n9}}"
DIST_DIR="${2:-${DIST_DIR:-${ROOT_DIR}/dist}}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"

log()  { echo "[ffmpeg-win-build] $*"; }
fail() { echo "[ffmpeg-win-build] FATAL: $*" >&2; exit 1; }

mkdir -p "$INSTALL_PREFIX/include" "$INSTALL_PREFIX/lib/pkgconfig" "$DIST_DIR"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

fetch_tarball() {
    rm -f "$2"
    curl -fsSL --retry 3 -H "User-Agent: $UA" -o "$2" "$1" || fail "下载失败: $1"
    [ -s "$2" ] || fail "下载为空: $1"
}

# 1. 硬件加速头文件
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
cp -r "$WORK_DIR/amf/amf/public/include/." "$INSTALL_PREFIX/include/AMF/"

# 2. 下载 FFmpeg n9.0 源码
log "下载 FFmpeg $FFMPEG_VER 源码..."
fetch_tarball "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VER.tar.xz" "$WORK_DIR/ffmpeg.tar.xz"
mkdir -p "$WORK_DIR/ffmpeg"
tar xJf "$WORK_DIR/ffmpeg.tar.xz" -C "$WORK_DIR/ffmpeg" --strip-components=1

# 3. 配置与编译 FFmpeg
export PKG_CONFIG_PATH="$INSTALL_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

CFG_ARGS=(
    --prefix="$INSTALL_PREFIX"
    --pkg-config-flags="--static"
    --enable-static --disable-shared --enable-pic
    --enable-gpl --enable-version3
    --enable-schannel
    --enable-libx264 --enable-libx265 --enable-libvpx --enable-libopus --enable-libmp3lame
    --enable-libaom --enable-libdav1d --enable-libsvtav1
    --enable-libass --enable-libfreetype --enable-libfontconfig --enable-libharfbuzz --enable-libfribidi
    --enable-ffnvcodec --enable-cuda --enable-cuvid --enable-nvenc --enable-nvdec
    --enable-amf --enable-libvpl --enable-mediafoundation
    --enable-d3d11va --enable-dxva2
    --enable-hwaccel=h264_d3d11va --enable-hwaccel=hevc_d3d11va --enable-hwaccel=av1_d3d11va
    --enable-hwaccel=h264_dxva2 --enable-hwaccel=hevc_dxva2
    --enable-hwaccel=h264_nvdec --enable-hwaccel=hevc_nvdec
    --enable-encoder=h264_nvenc --enable-encoder=hevc_nvenc --enable-encoder=av1_nvenc
    --enable-encoder=h264_qsv --enable-encoder=hevc_qsv --enable-encoder=av1_qsv --enable-encoder=mjpeg_qsv
    --enable-encoder=h264_amf --enable-encoder=hevc_amf --enable-encoder=av1_amf
    --enable-encoder=h264_mf --enable-encoder=hevc_mf
    --enable-decoder=h264_cuvid --enable-decoder=hevc_cuvid --enable-decoder=av1_cuvid
    --enable-decoder=mjpeg_cuvid --enable-decoder=vp9_cuvid
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
    --disable-doc --disable-programs
    --extra-cflags="-I$INSTALL_PREFIX/include"
    --extra-ldflags="-L$INSTALL_PREFIX/lib"
)

log "运行 configure (Windows x86_64)..."
cd "$WORK_DIR/ffmpeg"
./configure "${CFG_ARGS[@]}" || { tail -50 ffbuild/config.log 2>/dev/null || true; fail "FFmpeg configure 失败"; }

log "编译 FFmpeg (make -j$JOBS)..."
make -j"$JOBS"
make install
rm -f "$INSTALL_PREFIX/lib/"*.dll.a "$INSTALL_PREFIX/bin/"*.dll 2>/dev/null || true

# 4. 打包归档 zip
log "打包归档 SDK..."
PKG_NAME="ffmpeg-n${FFMPEG_VER}-windows-amd64-full.zip"
WIN_ZIP="$(cygpath -w "${DIST_DIR}/${PKG_NAME}" 2>/dev/null || echo "${DIST_DIR}/${PKG_NAME}")"
WIN_SRC="$(cygpath -w "${INSTALL_PREFIX}" 2>/dev/null || echo "${INSTALL_PREFIX}")"
powershell -NoProfile -Command "Compress-Archive -Path '${WIN_SRC}\\*' -DestinationPath '${WIN_ZIP}' -Force"
log "✓ 已生成归档: ${DIST_DIR}/${PKG_NAME}"
