LOCAL_PATH := device/tecno/km5n

# Android 15 / API 35 device configuration for TWRP 16.0.
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

# Stock vendor API level.
PRODUCT_SHIPPING_API_LEVEL := 35

# TWRP/Android recovery-side packages that are present in the minimal
# TWRP/AOSP source.  Do not list MTK proprietary modules here: the minimal
# manifest does not provide their source definitions.  Stock MTK services
# remain a separate runtime/vendor integration task.
PRODUCT_PACKAGES += \
    android.hardware.fastboot@1.0-impl-mock \
    android.hardware.fastboot@1.0-impl-mock.recovery \
    fastbootd \
    android.hardware.health@2.1-impl \
    android.hardware.health@2.1-service

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/recovery/root/init.recovery.mt6768.rc:$(TARGET_RECOVERY_ROOT_OUT)/init.recovery.mt6768.rc \
    $(LOCAL_PATH)/recovery/root/system/etc/recovery.fstab:$(TARGET_RECOVERY_ROOT_OUT)/system/etc/recovery.fstab
