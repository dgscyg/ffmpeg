/**
 * Ascend DVPP Minimal Header for Compilation
 */
#ifndef INC_EXTERNAL_ACL_OPS_ACL_DVPP_H_
#define INC_EXTERNAL_ACL_OPS_ACL_DVPP_H_

#include "../acl.h"

#ifdef __cplusplus
extern "C" {
#endif

/* VDEC */
aclvdecChannelDesc *aclvdecCreateChannelDesc(void);
aclError aclvdecDestroyChannelDesc(aclvdecChannelDesc *channelDesc);
aclError aclvdecSetChannelDescChannelId(aclvdecChannelDesc *channelDesc, uint32_t channelId);
aclError aclvdecSetChannelDescThreadId(aclvdecChannelDesc *channelDesc, uint64_t threadId);
aclError aclvdecSetChannelDescCallback(aclvdecChannelDesc *channelDesc, aclvdecCallback callback);
aclError aclvdecSetChannelDescEnType(aclvdecChannelDesc *channelDesc, acldvppStreamFormat enType);
aclError aclvdecSetChannelDescOutPicFormat(aclvdecChannelDesc *channelDesc, acldvppPixelFormat outPicFormat);
aclError aclvdecSetChannelDescOutPicWidth(aclvdecChannelDesc *channelDesc, uint32_t outPicWidth);
aclError aclvdecSetChannelDescOutPicHeight(aclvdecChannelDesc *channelDesc, uint32_t outPicHeight);
aclError aclvdecCreateChannel(aclvdecChannelDesc *channelDesc);
aclError aclvdecDestroyChannel(aclvdecChannelDesc *channelDesc);

/* StreamDesc */
acldvppStreamDesc *acldvppCreateStreamDesc(void);
aclError acldvppDestroyStreamDesc(acldvppStreamDesc *streamDesc);
aclError acldvppSetStreamDescData(acldvppStreamDesc *streamDesc, void *dataDev);
aclError acldvppSetStreamDescSize(acldvppStreamDesc *streamDesc, uint32_t size);
aclError acldvppSetStreamDescTimestamp(acldvppStreamDesc *streamDesc, uint64_t timestamp);
aclError acldvppSetStreamDescRetCode(acldvppStreamDesc *streamDesc, uint32_t retCode);
aclError acldvppSetStreamDescEos(acldvppStreamDesc *streamDesc, uint8_t eos);
void *acldvppGetStreamDescData(const acldvppStreamDesc *streamDesc);
uint32_t acldvppGetStreamDescSize(const acldvppStreamDesc *streamDesc);
uint64_t acldvppGetStreamDescTimestamp(const acldvppStreamDesc *streamDesc);
uint32_t acldvppGetStreamDescRetCode(const acldvppStreamDesc *streamDesc);

/* PicDesc */
acldvppPicDesc *acldvppCreatePicDesc(void);
aclError acldvppDestroyPicDesc(acldvppPicDesc *picDesc);
aclError acldvppSetPicDescData(acldvppPicDesc *picDesc, void *dataDev);
aclError acldvppSetPicDescSize(acldvppPicDesc *picDesc, uint32_t size);
aclError acldvppSetPicDescFormat(acldvppPicDesc *picDesc, acldvppPixelFormat format);
aclError acldvppSetPicDescWidth(acldvppPicDesc *picDesc, uint32_t width);
aclError acldvppSetPicDescHeight(acldvppPicDesc *picDesc, uint32_t height);
aclError acldvppSetPicDescWidthStride(acldvppPicDesc *picDesc, uint32_t widthStride);
aclError acldvppSetPicDescHeightStride(acldvppPicDesc *picDesc, uint32_t heightStride);
aclError acldvppSetPicDescRetCode(acldvppPicDesc *picDesc, uint32_t retCode);
void *acldvppGetPicDescData(const acldvppPicDesc *picDesc);
uint32_t acldvppGetPicDescSize(const acldvppPicDesc *picDesc);
acldvppPixelFormat acldvppGetPicDescFormat(const acldvppPicDesc *picDesc);
uint32_t acldvppGetPicDescWidth(const acldvppPicDesc *picDesc);
uint32_t acldvppGetPicDescHeight(const acldvppPicDesc *picDesc);
uint32_t acldvppGetPicDescWidthStride(const acldvppPicDesc *picDesc);
uint32_t acldvppGetPicDescHeightStride(const acldvppPicDesc *picDesc);
uint32_t acldvppGetPicDescRetCode(const acldvppPicDesc *picDesc);

/* VDEC Send */
aclvdecFrameConfig *aclvdecCreateFrameConfig(void);
aclError aclvdecDestroyFrameConfig(aclvdecFrameConfig *config);
aclError aclvdecSendFrame(aclvdecChannelDesc *channelDesc, acldvppStreamDesc *input,
                          acldvppPicDesc *output, aclvdecFrameConfig *config,
                          void *userData);

/* VENC */
aclvencChannelDesc *aclvencCreateChannelDesc(void);
aclError aclvencDestroyChannelDesc(aclvencChannelDesc *channelDesc);
aclError aclvencSetChannelDescThreadId(aclvencChannelDesc *channelDesc, uint64_t threadId);
aclError aclvencSetChannelDescCallback(aclvencChannelDesc *channelDesc, aclvencCallback callback);
aclError aclvencSetChannelDescEnType(aclvencChannelDesc *channelDesc, acldvppStreamFormat enType);
aclError aclvencSetChannelDescPicFormat(aclvencChannelDesc *channelDesc, acldvppPixelFormat picFormat);
aclError aclvencSetChannelDescPicWidth(aclvencChannelDesc *channelDesc, uint32_t picWidth);
aclError aclvencSetChannelDescPicHeight(aclvencChannelDesc *channelDesc, uint32_t picHeight);
aclError aclvencSetChannelDescKeyFrameInterval(aclvencChannelDesc *channelDesc, uint32_t keyFrameInterval);
aclError aclvencSetChannelDescRcMode(aclvencChannelDesc *channelDesc, uint32_t rcMode);
aclError aclvencSetChannelDescSrcRate(aclvencChannelDesc *channelDesc, uint32_t srcRate);
aclError aclvencSetChannelDescMaxBitRate(aclvencChannelDesc *channelDesc, uint32_t maxBitRate);
aclError aclvencCreateChannel(aclvencChannelDesc *channelDesc);
aclError aclvencDestroyChannel(aclvencChannelDesc *channelDesc);

aclvencFrameConfig *aclvencCreateFrameConfig(void);
aclError aclvencDestroyFrameConfig(aclvencFrameConfig *config);
aclError aclvencSetFrameConfigForceIFrame(aclvencFrameConfig *config, uint8_t forceIFrame);
aclError aclvencSetFrameConfigEos(aclvencFrameConfig *config, uint8_t eos);
aclError aclvencSendFrame(aclvencChannelDesc *channelDesc, acldvppPicDesc *input,
                          void *reserve, aclvencFrameConfig *config, void *userdata);

/* VPC */
acldvppChannelDesc *acldvppCreateChannelDesc(void);
aclError acldvppDestroyChannelDesc(acldvppChannelDesc *channelDesc);
aclError acldvppCreateChannel(acldvppChannelDesc *channelDesc);
aclError acldvppDestroyChannel(acldvppChannelDesc *channelDesc);

acldvppRoiConfig *acldvppCreateRoiConfig(uint32_t left, uint32_t right, uint32_t top, uint32_t bottom);
aclError acldvppDestroyRoiConfig(acldvppRoiConfig *roiConfig);
aclError acldvppSetRoiConfig(acldvppRoiConfig *config, uint32_t left, uint32_t right, uint32_t top, uint32_t bottom);

acldvppResizeConfig *acldvppCreateResizeConfig(void);
aclError acldvppDestroyResizeConfig(acldvppResizeConfig *resizeConfig);
aclError acldvppSetResizeConfigInterpolation(acldvppResizeConfig *resizeConfig, uint32_t interpolation);

aclError acldvppVpcResizeAsync(acldvppChannelDesc *channelDesc, acldvppPicDesc *inputDesc,
                               acldvppPicDesc *outputDesc, acldvppResizeConfig *resizeConfig,
                               aclrtStream stream);
aclError acldvppVpcCropResizeAsync(acldvppChannelDesc *channelDesc, acldvppPicDesc *inputDesc,
                                   acldvppPicDesc *outputDesc, acldvppRoiConfig *cropArea,
                                   acldvppResizeConfig *resizeConfig, aclrtStream stream);

#ifdef __cplusplus
}
#endif

#endif // INC_EXTERNAL_ACL_OPS_ACL_DVPP_H_
