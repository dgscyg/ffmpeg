/**
 * AscendCL (ACL) Minimal Header for Compilation
 * Provides definitions for Ascend NPU runtime and DVPP APIs
 */
#ifndef INC_EXTERNAL_ACL_ACL_H_
#define INC_EXTERNAL_ACL_ACL_H_

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum aclError {
    ACL_SUCCESS = 0,
    ACL_ERROR_INVALID_PARAM = 100000,
    ACL_ERROR_UNINITIALIZE = 100001,
    ACL_ERROR_REPEAT_INITIALIZE = 100002,
    ACL_ERROR_INVALID_FILE_PATH = 100003,
    ACL_ERROR_WRITE_FILE_FAILURE = 100004,
    ACL_ERROR_INVALID_FILE_TYPE = 100005,
    ACL_ERROR_STORAGE_OVER_LIMIT = 100006,
    ACL_ERROR_FAILURE = 500000
} aclError;

typedef enum aclrtMemMallocPolicy {
    ACL_MEM_MALLOC_HUGE_FIRST = 0,
    ACL_MEM_MALLOC_HUGE_ONLY = 1,
    ACL_MEM_MALLOC_NORMAL_ONLY = 2,
    ACL_MEM_MALLOC_HUGE_FIRST_P2P = 3,
    ACL_MEM_MALLOC_HUGE_ONLY_P2P = 4,
    ACL_MEM_MALLOC_NORMAL_ONLY_P2P = 5
} aclrtMemMallocPolicy;

typedef enum aclrtMemcpyKind {
    ACL_MEMCPY_HOST_TO_HOST = 0,
    ACL_MEMCPY_HOST_TO_DEVICE = 1,
    ACL_MEMCPY_DEVICE_TO_HOST = 2,
    ACL_MEMCPY_DEVICE_TO_DEVICE = 3
} aclrtMemcpyKind;

typedef void *aclrtContext;
typedef void *aclrtStream;

typedef enum acldvppStreamFormat {
    H265_MAIN_LEVEL = 0,
    H264_BASELINE_LEVEL = 1,
    H264_MAIN_LEVEL = 2,
    H264_HIGH_LEVEL = 3
} acldvppStreamFormat;

typedef enum acldvppPixelFormat {
    PIXEL_FORMAT_YUV_400 = 0,
    PIXEL_FORMAT_YUV_SEMIPLANAR_420 = 1, // NV12
    PIXEL_FORMAT_VU_SEMIPLANAR_420 = 2,  // NV21
    PIXEL_FORMAT_YUV_422_PACKED = 3,
    PIXEL_FORMAT_YUYV_PACKED_422 = 4,
    PIXEL_FORMAT_YVYU_PACKED_422 = 5,
    PIXEL_FORMAT_UYVY_PACKED_422 = 6,
    PIXEL_FORMAT_VYUY_PACKED_422 = 7,
    PIXEL_FORMAT_YUV_PACKED_444 = 8,
    PIXEL_FORMAT_RGB_888 = 9,
    PIXEL_FORMAT_BGR_888 = 10,
    PIXEL_FORMAT_ARGB_8888 = 11,
    PIXEL_FORMAT_RGBA_8888 = 12,
    PIXEL_FORMAT_ABGR_8888 = 13,
    PIXEL_FORMAT_BGRA_8888 = 14
} acldvppPixelFormat;

typedef struct aclvdecChannelDesc aclvdecChannelDesc;
typedef struct aclvencChannelDesc aclvencChannelDesc;
typedef struct acldvppChannelDesc acldvppChannelDesc;
typedef struct acldvppStreamDesc acldvppStreamDesc;
typedef struct acldvppPicDesc acldvppPicDesc;
typedef struct aclvdecFrameConfig aclvdecFrameConfig;
typedef struct aclvencFrameConfig aclvencFrameConfig;
typedef struct acldvppRoiConfig acldvppRoiConfig;
typedef struct acldvppResizeConfig acldvppResizeConfig;

typedef void (*aclvdecCallback)(acldvppStreamDesc *input, acldvppPicDesc *output, void *userData);
typedef void (*aclvencCallback)(acldvppPicDesc *input, acldvppStreamDesc *output, void *userdata);

#ifdef __cplusplus
}
#endif

#endif // INC_EXTERNAL_ACL_ACL_H_
