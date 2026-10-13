# FFmpeg n9.0 Full-Featured Static SDK

全功能 FFmpeg `n9.0` 跨平台静态库构建工程（支持 Linux x86_64、Linux aarch64 与 Windows x86_64）。包含硬件加速编解码、全套开源软编软解、字幕与文字滤镜，以及瑞芯微 RKMPP 厂商寿命周期补丁。

专为 `mediaCenter`、`gb`、`ZLMediaKit` 等流媒体及 CGO 项目提供零冗余、开箱即用的静态 SDK。

## 产物矩阵（GitHub Release: `n9.0-full`）

| 平台 | 架构 | 文件名 | 说明 |
| :--- | :--- | :--- | :--- |
| **Linux** | `amd64` (x86_64) | `ffmpeg-n9.0-linux-amd64-full.tar.gz` | NVENC / QSV / AMF / VAAPI / x264 / x265 / AV1 / SVT-AV1 / dav1d |
| **Linux** | `arm64` (aarch64) | `ffmpeg-n9.0-linux-arm64-full.tar.gz` | Rockchip MPP 硬件编解码 (带补丁) / x264 / x265 / SVT-AV1 / dav1d |
| **Windows** | `amd64` (x86_64) | `ffmpeg-n9.0-windows-amd64-full.zip` | NVENC / QSV / AMF / MediaFoundation / D3D11VA / DXVA2 / SChannel |

## 包含能力清单

- **软编码**：`libx264`、`libx265`、`libvpx` (VP8/VP9)、`libsvtav1` (AV1)、`libaom` (AV1)、`libopus`、`libmp3lame`、`aac`、`mjpeg`、`pcm_alaw`、`pcm_mulaw`
- **软解码**：`h264`、`hevc`、`vp8`、`vp9`、`av1` (含 `libdav1d` 极速解码)、`mpeg4`、`mjpeg`、`aac`、`mp3`、`opus`、`pcm`
- **硬件编解码**：
  - NVIDIA NVENC / CUVID (`nv-codec-headers n12.2.72.0`)
  - Intel QSV / oneVPL (`libvpl`)
  - AMD AMF (`v1.4.36`)
  - Windows 原生 MediaFoundation (`h264_mf` / `hevc_mf`) 与 D3D11VA / DXVA2
  - Rockchip MPP (`patches/ffmpeg9_rkmpp_enc_frame_lifetime.patch` 修复帧寿命周期)
- **滤镜与协议**：
  - `scale` / `format` / `fps` / `overlay` / `crop` / `pad` / `transpose`
  - `drawtext` (freetype2 + harfbuzz) / `subtitles` + `ass` (`libass` + `libunibreak` + `fribidi`)
  - `file` / `tcp` / `udp` / `rtmp` / `pipe` / `http` / `https` (SChannel on Windows, OpenSSL on Linux)

## 下游项目快速引用 (秒级就绪)

### Linux (直接解压到 `/opt/ffmpeg-n9`)
```bash
sudo mkdir -p /opt/ffmpeg-n9
curl -fsSL https://github.com/dgscyg/ffmpeg/releases/download/n9.0-full/ffmpeg-n9.0-linux-amd64-full.tar.gz | sudo tar -xzf - -C /opt/ffmpeg-n9
export PKG_CONFIG_PATH=/opt/ffmpeg-n9/lib/pkgconfig:$PKG_CONFIG_PATH
```

### Windows (直接解压到 `C:\tools\ffmpeg-n9`)
```powershell
Invoke-WebRequest -Uri "https://github.com/dgscyg/ffmpeg/releases/download/n9.0-full/ffmpeg-n9.0-windows-amd64-full.zip" -OutFile "$env:TEMP\ffmpeg.zip"
Expand-Archive -Path "$env:TEMP\ffmpeg.zip" -DestinationPath "C:\tools\ffmpeg-n9" -Force
```
