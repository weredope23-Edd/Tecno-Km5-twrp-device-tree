LOCAL_PATH := device/tecno/km5n

# Android 15 / Virtual A/B with recovery in vendor_boot.
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

# Android API / vendor ABI level taken from stock KM5n Android 15.
PRODUCT_SHIPPING_API_LEVEL := 35
PRODUCT_TARGET_VNDK_VERSION := 35

# MTK boot/health implementation used by current Transsion recovery trees.
PRODUCT_PACKAGES += \
    android.hardware.boot@1.2-mtkimpl \
    android.hardware.boot@1.2-mtkimpl.recovery \
    android.hardware.health@2.1-impl \
    android.hardware.health@2.1-service \
    fastbootd

# Android 15 security / crypto plumbing. The device-side Trustonic service
# binaries are supplied by the stock /vendor partition at runtime.
PRODUCT_PACKAGES += \
    android.system.keystore2 \
    android.hardware.security.keymint \
    android.hardware.security.secureclock \
    android.hardware.security.sharedsecret

PRODUCT_PACKAGES += \
    mtk_plpath_utils \
    mtk_plpath_utils.recovery

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/recovery/root/init.recovery.mt6768.rc:$(TARGET_RECOVERY_ROOT_OUT)/init.recovery.mt6768.rc \
    $(LOCAL_PATH)/recovery/root/system/etc/recovery.fstab:$(TARGET_RECOVERY_ROOT_OUT)/system/etc/recovery.fstab \
