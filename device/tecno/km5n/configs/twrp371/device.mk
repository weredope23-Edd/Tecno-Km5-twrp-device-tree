LOCAL_PATH := device/tecno/km5n

# Android 14-based TWRP 3.7.1 device configuration. The target device
# actually ships an Android 15 (API 35) vendor, so retain shipping API 35
# for vendor compatibility while using the TWRP-14 source branch.
$(call inherit-product, $(SRC_TARGET_DIR)/product/virtual_ab_ota/launch_with_vendor_ramdisk.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/virtual_ab_ota/compression.mk)

ENABLE_VIRTUAL_AB := true
AB_OTA_UPDATER := true
PRODUCT_USE_DYNAMIC_PARTITIONS := true

AB_OTA_PARTITIONS += \
    boot \
    init_boot \
    dtbo \
    vendor_boot \
    vendor_dlkm \
    system \
    system_ext \
    product \
    vendor \
    odm_dlkm \
    system_dlkm \
    vbmeta \
    vbmeta_system \
    vbmeta_vendor

PRODUCT_SHIPPING_API_LEVEL := 35

PRODUCT_PACKAGES += \
    android.hardware.boot@1.2-mtkimpl \
    android.hardware.boot@1.2-mtkimpl.recovery \
    android.hardware.health@2.1-impl \
    android.hardware.health@2.1-service \
    fastbootd

PRODUCT_PACKAGES += \
    mtk_plpath_utils \
    mtk_plpath_utils.recovery

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/recovery/root/init.recovery.mt6768.rc:$(TARGET_RECOVERY_ROOT_OUT)/init.recovery.mt6768.rc \
    $(LOCAL_PATH)/recovery/root/system/etc/recovery.fstab:$(TARGET_RECOVERY_ROOT_OUT)/system/etc/recovery.fstab
