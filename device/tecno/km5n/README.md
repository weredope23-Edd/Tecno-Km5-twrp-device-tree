# TECNO KM5n / Spark 40 — TWRP 16.0 bring-up tree

This tree is generated from the supplied stock KM5n dump.

## Stock architecture verified

- MT6768
- Android 15 / API 35
- kernel 6.6.102-android15-8
- `vendor_boot` header v4
- separate platform + recovery vendor-ramdisk fragments
- recovery is in `vendor_boot`; there is no dedicated recovery partition
- vendor and vendor_dlkm are EROFS
- userdata is F2FS with `aes-256-xts:aes-256-cts:v2`, `inlinecrypt`, and metadata-encryption keys under `/metadata/vold/metadata_encryption`
- Trustonic KeyMint 3.0 + Gatekeeper + TEE stack

## Important crypto decision

The recovery fstab mounts the stock logical `vendor` partition at `/vendor` as EROFS. That is intentional: the Trustonic binaries and their complete OEM dependency graph should come from the exact stock vendor image rather than copying an incomplete set of proprietary blobs into recovery.

The tree includes the stock Trustonic service rc files and VINTF declarations in the recovery ramdisk so recovery init can start the same services after `/vendor` is mounted.

The `stock_vendor_overlay/` directory contains the Trustonic binaries successfully extracted from the stock EROFS for auditing/reference. It is **not** automatically installed over `/vendor`.

## Build

Use TWRP 16.0:

```bash
repo init --depth=1 -u https://github.com/TWRP-Test/platform_manifest_twrp_aosp.git -b twrp-16.0
repo sync
mkdir -p device/tecno
cp -a twrp_device_tecno_km5n device/tecno/km5n
source build/envsetup.sh
lunch twrp_km5n-eng
mka adbd vendorbootimage -j$(nproc)
```

The expected target is a **vendor_boot** image, not a legacy recovery.img.

## First hardware test

Do not flash over the stock vendor_boot initially. Keep the original vendor_boot backed up and test the generated image using the device's supported temporary boot path if available.

Test in this order:

1. display
2. touch
3. USB/ADB
4. `/vendor` mount
5. partition table and dynamic partitions
6. backup/restore
7. `/data` detection
8. FBE metadata + user credential decryption

The crypto stack is not declared proven until `/data` actually decrypts on the exact firmware represented by the supplied stock dump.

## v4 bring-up notes

This revision carries the exact `lib/modules` set from the stock vendor_boot recovery ramdisk, including `modules.load.recovery` and `modules.softdep`. The build is configured for vendor_boot v4 recovery resources and excludes a separate recovery kernel.

The stock Trustonic KeyMint/Gatekeeper services are retained in `stock_vendor_overlay/` as an audit/reference copy. The runtime plan is to mount the real OEM `/vendor` partition and use its matching Trustonic stack rather than mixing incompatible vendor blobs.

## Build status

This tree is a bring-up tree. It has not been hardware-boot-tested yet. The GitHub Actions workflow builds `vendor_boot.img`, validates its header/size, and uploads the result plus diagnostics. Do not flash an image until its header, size, unpacked ramdisk layout, and device-side boot behavior have been checked.
