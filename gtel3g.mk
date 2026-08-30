# Copyright (C) 2017 The Lineage Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

LOCAL_PATH := device/samsung/gtel3g

# Telephony base
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Overlays
DEVICE_PACKAGE_OVERLAYS += $(LOCAL_PATH)/overlay

# Inherit from vendor tree
$(call inherit-product-if-exists, vendor/samsung/gtel3g/gtel3g-vendor.mk)

# Inherit from SC8830 platform configuration
$(call inherit-product, device/samsung/scx35-common/common.mk)

# Telephony / RIL
PRODUCT_PACKAGES += \
	SamsungServiceMode \
	librilutils \
	libril_shim \
	libphoneserver_shim \
	libatchannel \
	libsecril-client \
	libsecril-shim \
	modemd \
	modem_control

PRODUCT_PROPERTY_OVERRIDES += \
	ro.radio.modemtype=w \
	rild.libpath=/system/vendor/lib/libsecril-shim.so \
	ro.com.android.mobiledata=false

PRODUCT_COPY_FILES += \
	frameworks/native/data/etc/android.hardware.telephony.gsm.xml:$(TARGET_COPY_OUT_SYSTEM)/etc/permissions/android.hardware.telephony.gsm.xml \
	$(LOCAL_PATH)/ril/init/at_distributor.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/at_distributor.rc \
	$(LOCAL_PATH)/ril/init/data.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/data.rc \
	$(LOCAL_PATH)/ril/init/dns.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/dns.rc \
	$(LOCAL_PATH)/ril/init/engpc.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/engpc.rc \
	$(LOCAL_PATH)/ril/init/gtel3g-ril.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/gtel3g-ril.rc \
	$(LOCAL_PATH)/ril/init/kill_phone.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/kill_phone.rc \
	$(LOCAL_PATH)/ril/init/modem_control.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/modem_control.rc \
	$(LOCAL_PATH)/ril/init/modemd.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/modemd.rc \
	$(LOCAL_PATH)/ril/init/nvitemd.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/nvitemd.rc \
	$(LOCAL_PATH)/ril/init/phoneserver.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/phoneserver.rc \
	$(LOCAL_PATH)/ril/init/refnotify.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/refnotify.rc \
	$(LOCAL_PATH)/ril/init/rild.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/rild.legacy.rc \
	$(LOCAL_PATH)/ril/init/smd_symlink.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/smd_symlink.rc

# Boot animation
TARGET_SCREEN_HEIGHT := 1280
TARGET_SCREEN_WIDTH := 800

# Keylayouts
PRODUCT_COPY_FILES += \
	$(LOCAL_PATH)/keylayout/sec_touchscreen.kl:$(TARGET_COPY_OUT_VENDOR)/usr/keylayout/sec_touchscreen.kl \
	$(LOCAL_PATH)/keylayout/samsung-keypad.kl:$(TARGET_COPY_OUT_VENDOR)/usr/keylayout/samsung-keypad.kl \
	$(LOCAL_PATH)/keylayout/sci-keypad.kl:$(TARGET_COPY_OUT_VENDOR)/usr/keylayout/sci-keypad.kl

# Media
PRODUCT_PACKAGES += \
	media_profiles_V1_0.xml

PRODUCT_PROPERTY_OVERRIDES += \
	media.stagefright.legacyencoder=true \
	media.stagefright.less-secure=true

# Camera
PRODUCT_PACKAGES += \
	Snap \
	camera.sc8830 \
	libmemoryheapion_sprd_legacy

# Sensors
PRODUCT_PACKAGES += \
	sensors.sc8830

# WiFi
$(call inherit-product, hardware/broadcom/wlan/bcmdhd/config/config-bcm.mk)

# Set those variables here to overwrite the inherited values.
PRODUCT_NAME := full_gtel3g
PRODUCT_DEVICE := gtel3g
PRODUCT_BRAND := samsung
PRODUCT_MANUFACTURER := samsung
PRODUCT_MODEL := SM-T561

# Offline charging percentage
PRODUCT_PACKAGES += \
    font_log.png \
    sprd_charger_animation

# Excluded hardware features
PRODUCT_COPY_FILES += device/samsung/gtel3g/configs/permissions/gtel3g_excluded_hardware.xml:$(TARGET_COPY_OUT_SYSTEM)/etc/permissions/gtel3g_excluded_hardware.xml

# Root filesystem
PRODUCT_PACKAGES += \
    fstab.sc8830
