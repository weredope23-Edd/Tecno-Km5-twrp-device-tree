#!/usr/bin/env bash
set -euo pipefail

DEVICE_PATH="${1:-device/tecno/km5n}"
BC="$DEVICE_PATH/BoardConfig.mk"
DM="$DEVICE_PATH/device.mk"
AP="$DEVICE_PATH/AndroidProducts.mk"
FSTAB="$DEVICE_PATH/recovery/root/system/etc/recovery.fstab"
INV="$DEVICE_PATH/STOCK_CRYPTO_INVENTORY.txt"
INIT="$DEVICE_PATH/recovery/root/init.recovery.mt6768.rc"

fail(){ echo "ERROR: $*" >&2; exit 1; }
need(){ test -f "$1" || fail "missing required file: $1"; }
need "$BC"; need "$DM"; need "$AP"; need "$FSTAB"; need "$INV"; need "$INIT"

if grep -RInE 'twrp371|twrp-14|twrp_km5n-next|configs/twrp371|TARGET_RELEASE[[:space:]]*[:?+]?=[[:space:]]*next' "$DEVICE_PATH" \
  --include='*.mk' --include='*.bp' --include='*.xml' --include='*.rc'; then
  fail "legacy TWRP 3.7.1/TWRP-14 configuration remains"
fi

# Android 15 treats PRODUCT_USE_DYNAMIC_PARTITIONS as a readonly product
# variable during BoardConfig evaluation. It must be declared at product level.
if grep -q '^PRODUCT_USE_DYNAMIC_PARTITIONS[[:space:]]*:=' "$BC"; then
  fail "PRODUCT_USE_DYNAMIC_PARTITIONS must not be assigned in BoardConfig.mk"
fi
grep -q '^PRODUCT_USE_DYNAMIC_PARTITIONS := true$' "$DM" || fail "dynamic partitions are not enabled at product level"

# TWRP 16 is an Android 16 platform.  The device's shipping/vendor API is
# 35, but BOARD_SYSTEMSDK_VERSIONS must not be pinned to 35: that would hide
# Android 16's current system SDK from platform modules that use system_current.
# build/make derives the appropriate current board System SDK automatically
# when the board variable is unset.
if grep -q '^BOARD_SYSTEMSDK_VERSIONS[[:space:]]*:=' "$BC"; then
  fail "BOARD_SYSTEMSDK_VERSIONS must remain unset for the TWRP 16 platform"
fi

grep -q '^BOARD_BOOT_HEADER_VERSION := 4$' "$BC" || fail "boot header is not v4"
grep -q '^BOARD_KERNEL_PAGESIZE := 4096$' "$BC" || fail "kernel page size is not 4096"
grep -q '^BOARD_RAMDISK_USE_LZ4 := true$' "$BC" || fail "vendor ramdisk compression is not LZ4"
grep -q '^BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT := true$' "$BC" || fail "recovery resources are not moved to vendor_boot"
grep -q '^BOARD_INCLUDE_RECOVERY_RAMDISK_IN_VENDOR_BOOT := true$' "$BC" || fail "recovery ramdisk is not included in vendor_boot"
grep -q '^TARGET_NO_RECOVERY := true$' "$BC" || fail "legacy recovery partition is still enabled"
grep -q '^BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 67108864$' "$BC" || fail "vendor_boot partition size is not 64 MiB"

grep -q '^PRODUCT_SHIPPING_API_LEVEL := 35$' "$DM" || fail "shipping API is not 35"
grep -q 'twrp_km5n-bp2a-eng' "$AP" || fail "BP2A lunch target missing"

for p in system system_ext product vendor vendor_dlkm odm_dlkm system_dlkm; do
  key="TARGET_COPY_OUT_${p^^}"
  grep -q "^${key} := ${p}$" "$BC" || fail "$key is missing or incorrect"
  grep -qE "^${p} /${p} (erofs|ext4)" "$FSTAB" || fail "fstab missing logical partition $p"
done

for v in BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE BOARD_ODMIMAGE_FILE_SYSTEM_TYPE BOARD_ODM_DLKMIMAGE_FILE_SYSTEM_TYPE BOARD_SYSTEM_DLKMIMAGE_FILE_SYSTEM_TYPE BOARD_VENDOR_DLKMIMAGE_FILE_SYSTEM_TYPE; do
  grep -q "^${v} := erofs$" "$BC" || fail "$v is not EROFS"
done

grep -q '^BOARD_FLASH_BLOCK_SIZE := 262144$' "$BC" || fail "flash block size is not 256 KiB"
grep -q '^BOARD_USES_METADATA_PARTITION := true$' "$BC" || fail "metadata partition is not enabled"
grep -q '^TARGET_USERIMAGES_USE_F2FS := true$' "$BC" || fail "F2FS support is not enabled"

if grep -q '^TW_FORCE_KEYMASTER_VER' "$BC"; then
  fail "legacy TW_FORCE_KEYMASTER_VER must not be used with stock KeyMint 3.0"
fi
grep -q 'KeyMint service: /vendor/bin/hw/android.hardware.security.keymint@3.0-service.trustonic' "$INV" || fail "stock KeyMint 3.0 inventory mismatch"
grep -q '^TW_INCLUDE_CRYPTO_FBE := true$' "$BC" || fail "FBE crypto support missing"
grep -q '^TW_INCLUDE_FBE_METADATA_DECRYPT := true$' "$BC" || fail "metadata-FBE support missing"
grep -q 'fileencryption=aes-256-xts:aes-256-cts:v2' "$FSTAB" || fail "stock FBE policy missing from recovery.fstab"
grep -q '/metadata/vold/metadata_encryption' "$FSTAB" || fail "metadata encryption key directory missing"

if grep -nE 'android\.hardware\.boot@1\.2-mtkimpl|mtk_plpath_utils' "$DM"; then
  fail "MTK proprietary modules must be supplied as source/prebuilt modules before being added to PRODUCT_PACKAGES"
fi

test -f "$DEVICE_PATH/stock_vendor_overlay/vendor/bin/mcDriverDaemon" || fail "Trustonic mcDriverDaemon overlay missing"
test -f "$DEVICE_PATH/stock_vendor_overlay/vendor/bin/hw/android.hardware.security.keymint@3.0-service.trustonic" || fail "Trustonic KeyMint 3.0 overlay missing"
test -f "$DEVICE_PATH/stock_vendor_overlay/vendor/bin/hw/android.hardware.gatekeeper-service.trustonic" || fail "Trustonic Gatekeeper overlay missing"

echo "PASS: KM5n TWRP 16 compatibility audit"
echo "  Android platform/API: 16/36 (device shipping API 35)"
echo "  release: BP2A"
echo "  boot: vendor_boot v4, 64 MiB, 4 KiB pages, LZ4 ramdisk"
echo "  logical partitions: EROFS + dynamic partitions"
echo "  userdata: F2FS + metadata-encrypted FBE"
echo "  crypto: Trustonic KeyMint 3.0 (no legacy Keymaster forcing)"
echo "  proprietary MTK packages: deferred until source/prebuilt definitions exist"
