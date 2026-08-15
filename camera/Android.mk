LOCAL_PATH := $(call my-dir)

ifneq ($(filter gtel3g,$(TARGET_DEVICE)),)

include $(CLEAR_VARS)

LOCAL_MODULE := camera.sc8830
LOCAL_MODULE_RELATIVE_PATH := hw

LOCAL_SRC_FILES := CameraWrapper.cpp

LOCAL_C_INCLUDES := \
    system/media/camera/include

LOCAL_SHARED_LIBRARIES := \
    libhardware \
    liblog \
    libutils

LOCAL_CPPFLAGS := \
    -Wall \
    -Wextra \
    -Wno-unused-parameter

LOCAL_MULTILIB := 32
LOCAL_VENDOR_MODULE := true
LOCAL_MODULE_TAGS := optional

include $(BUILD_SHARED_LIBRARY)

endif

# Legacy Spreadtrum MemoryHeapIon ABI compatibility
include $(LOCAL_PATH)/memoryheapion_sprd_legacy/Android.mk
