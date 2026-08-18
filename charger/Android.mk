LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := gtel3g_charger_animation
LOCAL_MODULE_STEM := animation.txt
LOCAL_MODULE_TAGS := optional
LOCAL_MODULE_CLASS := ETC
LOCAL_SRC_FILES := animation.txt
LOCAL_MODULE_PATH := $(TARGET_ROOT_OUT)/res/values/charger
include $(BUILD_PREBUILT)
