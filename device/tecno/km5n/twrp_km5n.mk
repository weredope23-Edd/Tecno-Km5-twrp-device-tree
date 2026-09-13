LOCAL_PATH := device/tecno/km5n

PRODUCT_DEVICE := km5n
PRODUCT_NAME := twrp_km5n
PRODUCT_BRAND := TECNO
PRODUCT_MODEL := TECNO KM5n
PRODUCT_MANUFACTURER := TECNO

$(call inherit-product, $(LOCAL_PATH)/device.mk)
$(call inherit-product, vendor/twrp/config/common.mk)
