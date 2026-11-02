/**
 * Ascend DVPP Minimal Header for Compilation
 */
#ifndef INC_EXTERNAL_ACL_OPS_ACL_DVPP_H_
#define INC_EXTERNAL_ACL_OPS_ACL_DVPP_H_

#include "../acl.h"

#ifdef __cplusplus
extern "C" {
#endif

aclvdecChannelDesc *aclvdecCreateChannelDesc(void);
aclError aclvdecDestroyChannelDesc(aclvdecChannelDesc *channelDesc);
aclError aclvdecSetChannelDescThreadId(aclvdecChannelDesc *channelDesc, uint64_t threadId);
aclError aclvdecSetChannelDescCallback(aclvdecChannelDesc *channelDesc, aclvdecCallback callback);
aclError aclvdecSetChannelDescEnType(aclvdecChannelDesc *channelDesc, acldvppStreamFormat enType);
aclError aclvdecSetChannelDescOutPicFormat(aclvdecChannelDesc *channelDesc, acldvppPixelFormat outPicFormat);
aclError aclvdecCreateChannel(aclvdecChannelDesc *channelDesc);
aclError aclvdecDestroyChannel(aclvdecChannelDesc *channelDesc);

acldvppStreamDesc *acldvppCreateStreamDesc(void);
aclError acldvppDestroyStreamDesc(acldvppStreamDesc *streamDesc);
aclError acldvppSetStreamDescData(acldvppStreamDesc *streamDesc, void *dataDev);
aclError acldvppSetStreamDescSize(acldvppStreamDesc *streamDesc, uint32_t size);

acldvppPicDesc *acldvppCreatePicDesc(void);
aclError acldvppDestroyPicDesc(acldvppPicDesc *picDesc);
aclError acldvppSetPicDescData(acldvppPicDesc *picDesc, void *dataDev);
aclError acldvppSetPicDescSize(acldvppPicDesc *picDesc, uint32_t size);
void *acldvppGetPicDescData(const acldvppPicDesc *picDesc);
uint32_t acldvppGetPicDescSize(const acldvppPicDesc *picDesc);
uint32_t acldvppGetPicDescWidth(const acldvppPicDesc *picDesc);
uint32_t acldvppGetPicDescHeight(const acldvppPicDesc *picDesc);

aclError aclvdecSendFrame(aclvdecChannelDesc *channelDesc, acldvppStreamDesc *streamDesc, acldvppPicDesc *picDesc, void *userData);

#ifdef __cplusplus
}
#endif

#endif // INC_EXTERNAL_ACL_OPS_ACL_DVPP_H_
