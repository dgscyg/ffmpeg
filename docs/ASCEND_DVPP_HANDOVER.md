# 华为昇腾 Ascend 310P (DVPP VDEC) 硬件解码器现状、问题与接手重构指南

本文档用于记录 `dgscyg/ffmpeg`（FFmpeg n9.0）工程中集成华为昇腾 DVPP 硬件解码器（`h264_ascend` / `hevc_ascend`）的技术现状、已知缺陷、底层架构缺口以及下一阶段模型/开发者的具体接手重构方案。

---

## 0. 当前状态（2026-11-02 重构后）

`patches/ffmpeg9_ascend_dvpp.patch` 已完成真实 VDEC 调用链重构，不再是丢包桩：

| 项目 | 状态 |
| :--- | :--- |
| `aclvdecSetChannelDescChannelId/ThreadId/Callback` | 三者在 `aclvdecCreateChannel` 之前全部设置 |
| `aclvdecSendFrame` | 按 CANN 真实原型 5 参数调用，输入/输出描述符逐帧新建 |
| 异步回调线程 | `pthread` + `aclrtProcessReport(100)`，线程 ID 通过 `pthread_self()` 绑定 |
| 输出显存 | `acldvppMalloc(size = stride_w * stride_h * 3 / 2)`，回调/出帧两处均 `acldvppFree` |
| Annex-B | 解码器 `bsfs` 强制 `h264_mp4toannexb` / `hevc_mp4toannexb` |
| 帧交付 | 回调入有界队列，`ascend_receive_frame` 按 stride 逐行 `aclrtMemcpy(D2H)` 到 `AVFrame` |
| EOS / flush | 发送 `acldvppSetStreamDescEos(1)` 空码流，flush 重建通道 |
| 多实例 | `aclInit`/`aclFinalize`、`aclrtSetDevice`/`ResetDevice` 进程级引用计数；`channel_id` 自动分配 |

已验证（非真机）：

```bash
# 干净 FFmpeg 9.0 源码树
patch -p1 < patches/ffmpeg9_ascend_dvpp.patch
./configure --enable-ascend --enable-decoder=h264_ascend --enable-decoder=hevc_ascend ...
make -j4 libavcodec/libavcodec.a     # ascenddec.o 编译通过，无 error
```

**尚未完成**：TaiShan 200 + Ascend 310P3 真机验收（单流画面、`npu-smi` VDEC 负载、16~32 路并发）。见第 6 节。

---

## 1. 核心误区澄清：为什么补丁不是“华为官方”补丁？

在构建日志中，脚本输出了：
```bash
[ffmpeg-build] 应用补丁: ffmpeg9_ascend_dvpp.patch (华为昇腾 DVPP 硬解)
```
**澄清说明**：
1. **华为官方从未发布过针对 FFmpeg 9.0（或 FFmpeg 5.x/6.x/7.x）的标准 in-tree 解码器补丁**。
   华为官方对 DVPP 的支持主要集中在：
   - 官方独立 C++/Python 样例（如 `Ascend/samples`、`ACLLite`）；
   - 华为自研的推理框架（MindX SDK / ModelArts）；
   - 早期旧版本（如 FFmpeg 4.2）的非官方侵入式定制分支。
2. **本仓库现有补丁的真实来源与定位**：
   本仓库现存的 `patches/ffmpeg9_ascend_dvpp.patch`（查看文件头注释即可见 `Copyright (c) 2026 Antigravity`）是一个**动态加载（Zero-Dependency Dynamic Loader）的框架桩（Stub）**。
   - 其设计初衷：在 GitHub Actions（Ubuntu 24.04 等无 NPU 驱动的机器）上编译跨平台全功能静态 SDK 时，能够无依赖地把 `--enable-ascend`、`h264_ascend`、`hevc_ascend` 编入二进制，并向外暴露接口符号；
   - 现状：由于历史原因，该补丁仅完成了动态符号加载结构与解封装框架，**尚未编写真实的 Device 显存搬运与硬件解码调用链**。

---

## 2. 当前阻断性缺陷排查与代码现状

### 缺陷 1（已修复）：DVPP 通道创建校验失败
* **报错现象**：
  ```text
  [ERROR] ASCENDCL(644709,ffmpeg):... aclvdecCreateChannel: [CREATE][DEFAULT][Check][channelDesc->callback]param must not be null.
  [Ascend] 创建 DVPP 解码通道失败
  ```
* **代码位置**：`patches/ffmpeg9_ascend_dvpp.patch` 中 `ascenddec.c` 的 `ascend_init_decoder`。
* **原因**：
  昇腾 CANN 8.0 底层驱动（`video_processor.cpp`）在 `aclvdecCreateChannel` 时有强制非空断言：**必须绑定回调函数，否则拒绝创建通道**。代码中解析了 `aclvdecSetChannelDescCallback` 函数指针，但在 `aclvdecCreateChannel` 之前漏掉了调用。
* **附带要求**：
  CANN 规范要求同时调用 `aclvdecSetChannelDescThreadId(ctx->channel_desc, (uint64_t)pthread_self())` 绑定事件处理线程。

---

### 缺陷 2（已修复）：`ascend_receive_frame` 曾为占位桩
* **代码位置**：`patches/ffmpeg9_ascend_dvpp.patch` 中 `ascenddec.c` 的 `ascend_receive_frame`：
  ```c
  static int ascend_receive_frame(AVCodecContext *avctx, AVFrame *frame) {
      ...
      AVPacket *const pkt = ctx->pkt;
      int ret = ff_decode_get_packet(avctx, pkt);
      ...
      ret = ff_get_buffer(avctx, frame, 0); // 仅分配空白内存
      frame->pts = pkt->pts;
      frame->pkt_dts = pkt->dts;
      frame->format = AV_PIX_FMT_NV12;
      av_packet_unref(pkt);                 // 码流被直接丢弃！未送入 NPU
      return 0;                             // 输出黑屏/假帧
  }
  ```
* **影响**：
  即便修复缺陷 1，此时用 `ffmpeg -c:v h264_ascend` 跑测试，NPU 的 VDEC 硬件解码利用率（`npu-smi info -t usages -i 0`）依然是 **0%**。这无法进行任何真实的多路视频硬解压力测试。

---

## 3. 完整 DVPP VDEC 硬件解码生命周期与重构规范

接手模型/开发者必须按照以下华为 CANN 8.0 DVPP 官方标准生命周期对 `ascenddec.c` 进行重构：

```
                    ┌─────────────────────────────────────────┐
                    │               Host 侧 (CPU)              │
                    └────────────────────┬────────────────────┘
                                         │ AVPacket (H.264/HEVC 码流)
                                         ▼
                                acldvppMalloc (Device)
                                aclrtMemcpy (H2D)
                                         │
                    ┌────────────────────▼────────────────────┐
                    │              Device 侧 (NPU)             │
                    │                                         │
                    │   acldvppStreamDesc (输入码流描述)       │
                    │   acldvppPicDesc    (输出图片描述+内存)  │
                    │                    │                    │
                    │                    ▼                    │
                    │         aclvdecSendFrame()              │
                    │                    │                    │
                    │                    ▼                    │
                    │       [ 310P3 硬件 VDEC 引擎解码 ]      │
                    └────────────────────┬────────────────────┘
                                         │ 硬件解码完成事件
                                         ▼
                    ┌─────────────────────────────────────────┐
                    │            后台事件响应线程             │
                    │                                         │
                    │     aclrtProcessReport(thread_id, 100)  │
                    │                    │                    │
                    │                    ▼                    │
                    │         触发 aclvdecCallback            │
                    │    (将完成的 PicDesc 推入就绪帧队列)    │
                    └────────────────────┬────────────────────┘
                                         │
                                         ▼
                                ascend_receive_frame
                        从就绪队列取帧 -> aclrtMemcpy (D2H) 
                               拷入 AVFrame -> 输出
```

### 关键规范 1：显存申请与释放
1. **必须使用 DVPP 专用显存 API**：
   - 输出显存必须使用 `acldvppMalloc` 申请、`acldvppFree` 释放；
   - 输入码流可以使用 `acldvppMalloc/acldvppFree`，也可以使用 `aclrtMalloc/aclrtFree`（CANN 官方允许二者之一）。当前实现使用 `acldvppMalloc` 以保持一致。
2. **输出图像对齐规范（Alignment）**：
   - DVPP 输出格式固定为 `PIXEL_FORMAT_YUV_SEMIPLANAR_420` (NV12)；
   - **宽对齐**：CANN 8.x 官方约束为 `widthStride = FFALIGN(width, 16)`；**当 width < 16 时最小为 32**；
   - **高对齐**：`heightStride = FFALIGN(height, 2)`；
   - 注意：`aclvdecSendFrame` 的 output 描述符若设置宽高，必须 **width/height/widthStride/heightStride 四个一起设置**，只设部分会返回错误；
   - 当前实现为稳妥起见按 `FFALIGN(w, 128)` 申请输出内存（大于等于 16 对齐要求），但从 desc 读取真实 stride 后再拷贝，因此不会出现花屏；
   - **显存大小**：`stride_width * stride_height * 3 / 2`；
   - 必须使用 `acldvppSetPicDescData` 与 `acldvppSetPicDescSize` 设置。

### 关键规范 2：码流要求（Bitstream Format）
- DVPP 硬件解码器**只接收 Annex-B 格式**（以 `00 00 00 01` 或 `00 00 01` 为开头的 NALU）。
- 在 `ascenddec.c` 中：
  - `ff_h264_ascend_decoder.bsfs` 必须指定为 `"h264_mp4toannexb"`；
  - `ff_hevc_ascend_decoder.bsfs` 必须指定为 `"hevc_mp4toannexb"`。
  - 当前补丁已配置此项，需继续保持。

### 关键规范 3：异步事件分发模型（Worker Thread & Callback）
1. **回调线程**：
   在 `ascend_init_decoder` 中启动一个 `pthread` 独立线程，绑定当前 Device 上下文 (`aclrtSetCurrentContext`)，循环执行：
   ```c
   while (ctx->running) {
       aclrtProcessReport(100); // CANN 只有 timeout 一个参数
   }
   ```
   **API 原型修正**：`aclError aclrtProcessReport(int32_t timeout);`（不是 `(threadId, timeout)`）。
   `aclrtSubscribeReport(threadId, stream)` 只在需要绑定自定义 stream 回调时使用；`aclvdecSendFrame` 内部已封装 `aclrtLaunchCallback`，VDEC 路径无需再调用。
2. **回调函数**：
   ```c
   static void vdec_callback(acldvppStreamDesc *input, acldvppPicDesc *output, void *userData) {
       AscendDecodeContext *ctx = (AscendDecodeContext *)userData;
       // 1. 获取输入显存并释放输入描述符和内存
       void *inputDev = acldvppGetStreamDescData(input);
       if (inputDev) ctx->acldvppFree(inputDev);
       ctx->acldvppDestroyStreamDesc(input);

       // 2. 检查输出状态
       uint32_t retCode = acldvppGetPicDescRetCode(output);
       if (retCode == 0) {
           // 成功：将 output (acldvppPicDesc*) 入队到就绪队列
           enqueue_frame(ctx, output);
       } else {
           // 失败：释放 output
           void *outDev = acldvppGetPicDescData(output);
           if (outDev) ctx->acldvppFree(outDev);
           ctx->acldvppDestroyPicDesc(output);
       }
   }
   ```
3. **帧收取 `ascend_receive_frame`**：
   - 尝试从就绪队列获取已解码的 `acldvppPicDesc`；
   - 若队列为空且未 EOF，调用 `ff_decode_get_packet` 读包，送入 `aclvdecSendFrame`，然后等待条件变量（`pthread_cond_wait`）；
   - **关键时序**：VDEC 是异步的，`aclvdecSendFrame` 返回时帧还在解码。必须用 `in_flight` 计数限制在途帧数（推荐 4~8），否则多路并发时容易出现 `507018`（队列/资源挤压）；
   - 从就绪队列拿到解码帧后，分配 `AVFrame`，通过 `aclrtMemcpy(..., ACL_MEMCPY_DEVICE_TO_HOST)` 将 Device NV12 复制到 `AVFrame->data`；
   - NV12 必须 **按行拷 Y 与 UV**：源 pitch 用 `acldvppGetPicDescWidthStride()`，目标 pitch 用 `frame->linesize[n]`，不能整块 memcpy，否则画面斜切；
   - 释放该帧的 Device 显存与 `acldvppPicDesc`。

---

## 4. 必需补齐的动态符号清单

当前 `AscendDecodeContext` 仅加载了少量符号。重构需要动态加载以下全部符号（通过 `dlsym`）：

```c
/* libascendcl.so */
aclError (*aclInit)(const char *);
aclError (*aclFinalize)(void);
aclError (*aclrtSetDevice)(int32_t);
aclError (*aclrtResetDevice)(int32_t);
aclError (*aclrtCreateContext)(aclrtContext *, int32_t);
aclError (*aclrtDestroyContext)(aclrtContext);
aclError (*aclrtSetCurrentContext)(aclrtContext);
aclError (*aclrtMemcpy)(void *, size_t, const void *, size_t, aclrtMemcpyKind);
aclError (*aclrtMemcpy2d)(void *, size_t, const void *, size_t, size_t, size_t, aclrtMemcpyKind);

/* 直接链接的符号（不是 dlsym） */
aclError aclrtProcessReport(int32_t timeout);

/* libacl_dvpp.so */
aclError (*acldvppMalloc)(void **, size_t);
aclError (*acldvppFree)(void *);

aclvdecChannelDesc *(*aclvdecCreateChannelDesc)(void);
aclError (*aclvdecDestroyChannelDesc)(aclvdecChannelDesc *);
aclError (*aclvdecSetChannelDescChannelId)(aclvdecChannelDesc *, uint32_t);
aclError (*aclvdecSetChannelDescThreadId)(aclvdecChannelDesc *, uint64_t);
aclError (*aclvdecSetChannelDescCallback)(aclvdecChannelDesc *, aclvdecCallback);
aclError (*aclvdecSetChannelDescEnType)(aclvdecChannelDesc *, acldvppStreamFormat);
aclError (*aclvdecSetChannelDescOutPicFormat)(aclvdecChannelDesc *, acldvppPixelFormat);
aclError (*aclvdecSetChannelDescOutPicWidth)(aclvdecChannelDesc *, uint32_t);   /* 可选 */
aclError (*aclvdecSetChannelDescOutPicHeight)(aclvdecChannelDesc *, uint32_t);  /* 可选 */
aclError (*aclvdecCreateChannel)(aclvdecChannelDesc *);
aclError (*aclvdecDestroyChannel)(aclvdecChannelDesc *);

acldvppStreamDesc *(*acldvppCreateStreamDesc)(void);
aclError (*acldvppDestroyStreamDesc)(acldvppStreamDesc *);
aclError (*acldvppSetStreamDescData)(acldvppStreamDesc *, void *);
aclError (*acldvppSetStreamDescSize)(acldvppStreamDesc *, uint32_t);
aclError (*acldvppSetStreamDescEos)(acldvppStreamDesc *, uint8_t);
void *(*acldvppGetStreamDescData)(const acldvppStreamDesc *);

acldvppPicDesc *(*acldvppCreatePicDesc)(void);
aclError (*acldvppDestroyPicDesc)(acldvppPicDesc *);
aclError (*acldvppSetPicDescData)(acldvppPicDesc *, void *);
aclError (*acldvppSetPicDescSize)(acldvppPicDesc *, uint32_t);
aclError (*acldvppSetPicDescFormat)(acldvppPicDesc *, acldvppPixelFormat);
aclError (*acldvppSetPicDescWidth)(acldvppPicDesc *, uint32_t);
aclError (*acldvppSetPicDescHeight)(acldvppPicDesc *, uint32_t);
aclError (*acldvppSetPicDescWidthStride)(acldvppPicDesc *, uint32_t);
aclError (*acldvppSetPicDescHeightStride)(acldvppPicDesc *, uint32_t);
void *(*acldvppGetPicDescData)(const acldvppPicDesc *);
uint32_t (*acldvppGetPicDescWidthStride)(const acldvppPicDesc *);
uint32_t (*acldvppGetPicDescHeightStride)(const acldvppPicDesc *);
uint32_t (*acldvppGetPicDescRetCode)(const acldvppPicDesc *);

/* CANN 真实原型：5 参数，含 config 与 userData */
aclError (*aclvdecSendFrame)(aclvdecChannelDesc *, acldvppStreamDesc *,
                             acldvppPicDesc *, aclvdecFrameConfig *, void *);
```

> 链接：官方样例 `CMakeLists.txt` 使用 `target_link_libraries(main ascendcl acl_dvpp pthread stdc++)`。
> 本补丁把 AscendCL 全部 dlsym 化，`aclrtProcessReport` 以弱链接方式解析（`ascend_deps="libdl"`）。

---

## 5. 编译环境与构建脚本优化备忘

在修改 `patches/ffmpeg9_ascend_dvpp.patch` 的同时，必须同步检查 `scripts/build-ffmpeg-linux.sh`：
1. **移除 `libaom` 依赖**：
   - 目标测试机（Ubuntu 20.04 LTS aarch64）自带 `libaom-dev` 为 1.0.0，而 FFmpeg 9.0 要求 ≥2.0.0。
   - 脚本中已静态编译 `dav1d` 与 `svtav1`，故必须从 `build-ffmpeg-linux.sh` 的 `CFG_ARGS` 中删除 `--enable-libaom` 和 `--enable-encoder=libaom_av1`。
2. **CFLAGS 添加 DVPP 宏**：
   - 在 `--extra-cflags` 中增加 `-DENABLE_DVPP_INTERFACE`。
3. **动态库加载路径**：
   - 运行时需要 `LD_LIBRARY_PATH` 包含 `/usr/local/Ascend/ascend-toolkit/latest/lib64` 与 `.../runtime/lib64`；
   - 补丁内已内置上述路径的回退查找，但正式部署仍建议 source `set_env.sh`。
4. **更换稳定 Tarball 源**：
   - `SVT-AV1` 源更换为 `https://github.com/AOMediaCodec/SVT-AV1/archive/refs/tags/$SVT_VER.tar.gz`；
   - `mpp` 与 `rga` 更换为 GitHub Archive 直链，避免触发 GitHub API 限流。

---

## 6. 验证与验收基准（Acceptance Criteria）

接手者修复完成后，必须在真机（TaiShan 200 + Ascend 310P3，CANN 8.0.RC3）上通过以下三级验收：

1. **功能验收（单流解码）**：
   ```bash
   ffmpeg -y -c:v h264_ascend -i test_1080p.mp4 -f null -
   ```
   - 运行无报错退出，终端报告的 FPS 正常；
   - 播放或转存前 10 帧图像，确认画面解析正确、色彩与对齐正常（无花屏、条纹绿边）。
2. **真机硬件负载验收**：
   - 运行解码时，在另一终端执行：
     ```bash
     watch -n 0.5 npu-smi info -t usages -i 0
     ```
   - 确认 **`VDEC Usage` 字段有明显数值跳动（如 10%~40%）**，证明物理 VDEC 芯片已介入解码。
3. **极限并发压测验收**：
   - 同时启动 16 ~ 32 路 `ffmpeg -c:v h264_ascend` 解码任务；
   - 观察 `VDEC Usage` 逐步跑满（>80%~90%），并且没有内存泄漏（Memory Usage 不会无限增长）。

### 6.1 常见失败对照表

| 现象 | 根因 | 处理 |
| :--- | :--- | :--- |
| `aclvdecCreateChannel` 报 `channelDesc->callback param must not be null` | 只解析了 `aclvdecSetChannelDescCallback` 指针但没调用 | 在 create 前依次设置 ChannelId/ThreadId/Callback |
| `aclvdecCreateChannel` 报 `channelDesc->threadId ...` | 未设置回调线程 ID | `aclvdecSetChannelDescThreadId(desc, pthread_self())` 在回调线程内取 ID |
| `aclvdecSendFrame` 返回 `0xC0C6` / `507018` | 在途帧过多、输出/输入缓冲未及时回收、码流非 Annex-B | 限制在途帧、逐帧新建 desc、确认 BSF 生效 |
| 回调从不触发 | 没有线程循环调用 `aclrtProcessReport(100)`，或线程未 `aclrtSetCurrentContext` | 见规范 3 |
| 画面斜切 / 绿边 / 花屏 | 用 width 而非 `widthStride` 拷贝 NV12 | 按行拷 Y 与 UV，源 pitch 用 `acldvppGetPicDescWidthStride()` |
| `npu-smi` VDEC 利用率始终 0% | 仍在使用占位丢包实现 | 确认补丁已更新，且日志出现 `DVPP VDEC ready` |
| 多路解码第 2 路起失败 | `channel_id` 重复 | 现实现自动分配 `channel_id`，也可显式 `-channel_id N` |
| `acldvppMalloc` 失败 | DVPP 专用内存耗尽 | 输出内存复用池，不要每帧新申请（后续优化项） |
