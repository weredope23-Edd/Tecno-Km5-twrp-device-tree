# KM5n TWRP build notes

## Current target

The stock KM5n dump uses a 64 MiB Android boot header v4 `vendor_boot.img` and places recovery in the vendor ramdisk. Therefore this tree targets `vendorbootimage`, not a legacy `recoveryimage`.

TeamWin's current device-tree examples use `BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE` and `BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT` for vendor-boot devices, and TWRP's vendor-boot v4 repacking path uses `vendor_ramdisk_recovery.cpio`. citeturn0search3turn0search1

## Crypto status

The stock device uses F2FS + metadata-encrypted FBE and a Trustonic KeyMint/Gatekeeper/TEE stack. The tree keeps the stock Trustonic extraction under `stock_vendor_overlay/` for auditing, but does not pretend that copied proprietary blobs are sufficient. The first hardware test must establish whether TWRP can mount `/vendor` and then start the exact OEM crypto services needed to decrypt `/data`.

## Build source

The GitHub Actions workflow uses the `TWRP-Test/platform_manifest_twrp_aosp` manifest on `twrp-16.0`, matching current TWRP 16 device-tree workflows. citeturn1search9

## Validation

After a successful build:

```bash
scripts/validate_vendor_boot.sh out/target/product/km5n/vendor_boot.img
```

The script verifies the Android vendor_boot magic and that the generated image fits inside the stock 64 MiB vendor_boot partition. If `unpack_bootimg` is available, it also parses the image.

## Hardware testing order

1. Boot without overwriting the original stock vendor_boot.
2. Display and touch.
3. USB and ADB.
4. `/vendor` and logical partition discovery.
5. Data partition detection.
6. F2FS `/data` mount.
7. FBE metadata decryption.
8. Backup/restore only after the above are stable.

A successful build is **not** equivalent to a successful or safe hardware boot. Keep the original stock `vendor_boot.img`, `boot.img`, `init_boot.img`, `dtbo.img`, `vbmeta*`, and `vendor_dlkm.img` backed up.
