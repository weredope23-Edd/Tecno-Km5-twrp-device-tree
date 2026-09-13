# TECNO KM5n — TWRP 14.1 device tree

This tree targets the TECNO KM5n (MT6768) stock Android 15 firmware while building the recovery with the TWRP 14.1 source branch.

## Current target

- TWRP source: `TWRP-Test/platform_manifest_twrp_aosp`, branch `twrp-14.1`
- Product: `twrp_km5n-eng`
- Architecture: arm64 / MT6768
- Recovery container: Android vendor_boot v4
- Vendor boot partition size: 64 MiB
- Stock vendor and vendor_dlkm: EROFS
- Stock userdata: F2FS with FBE metadata encryption
- Stock recovery kernel modules: 191

The device tree is based on the stock recovery ramdisk and kernel-module set previously extracted from the supplied firmware. The recovery ramdisk contains the OEM MTK storage/display/touch support needed for this hardware.

## Important crypto design

The stock firmware uses Trustonic KeyMint/Gatekeeper/TEE components. The tree therefore preserves the stock recovery-side integration and does not replace it with an arbitrary partial TEE stack. `/vendor` should remain the OEM vendor source at runtime.

## Build

```bash
repo init --depth=1 -u https://github.com/TWRP-Test/platform_manifest_twrp_aosp.git -b twrp-14.1
repo sync
mkdir -p device/tecno
cp -a twrp_device_tecno_km5n device/tecno/km5n
source build/envsetup.sh
lunch twrp_km5n-eng
mka vendorbootimage -j$(nproc)
```

Expected output:

`out/target/product/km5n/vendor_boot.img`

## Hardware test order

Do not overwrite the original stock vendor_boot until the generated image has passed structural validation. Test in this order: boot without flashing over the original, display/touch, USB/ADB, logical partitions and `/vendor`, `/data` F2FS, FBE metadata decryption, then backup/restore.

Keep backups of the original `vendor_boot.img`, `boot.img`, `init_boot.img`, `dtbo.img`, `vbmeta*`, and `vendor_dlkm.img`.

## Status

This branch is a TWRP 14.1 build target. A successful compilation and device boot test are not yet claimed.
