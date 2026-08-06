## Specify phone tech before including full_phone	
$(call inherit-product, vendor/lineage/config/telephony.mk)

# Release name
PRODUCT_RELEASE_NAME := gtel3g

# Inherit some common Lineage stuff.
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

# Inherit device configuration
$(call inherit-product, device/samsung/gtel3g/gtel3g.mk)

## Device identifier. This must come after all inclusions
PRODUCT_DEVICE := gtel3g
PRODUCT_NAME := lineage_gtel3g
PRODUCT_BRAND := samsung
PRODUCT_MODEL := SM-T561
PRODUCT_MANUFACTURER := samsung
PRODUCT_CHARACTERISTICS := tablet

# Stock build fingerprint
BUILD_FINGERPRINT := "samsung/gtel3gxx/gtel3g:4.4.4/KTU84P/T561XXU0AQA2:user/release-keys"
PRIVATE_BUILD_DESC := "gtel3gxx-user 4.4.4 KTU84P T561XXU0AQA2 release-keys"

PRODUCT_PROPERTY_OVERRIDES += \
	ro.build.fingerprint=$(BUILD_FINGERPRINT)