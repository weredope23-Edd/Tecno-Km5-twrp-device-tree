# KM5n MT6768 vendor_boot donor audit

## Donor selected

The closest TeamWin reference found is `TeamWin/android_device_infinix_X6532`, an official TWRP tree for an MT6768 device. Its Android 12.1 age means it is **not** a source tree to copy wholesale; its value is the hardware/boot-architecture precedent.

The official tree uses the same critical architecture as KM5n:

- `TARGET_BOARD_PLATFORM := mt6768`
- Android boot header v4
- 4096-byte boot page size
- LZ4 ramdisk
- 64 MiB `vendor_boot`
- generic kernel image
- recovery resources moved into `vendor_boot`
- recovery ramdisk included in `vendor_boot`
- `TARGET_NO_RECOVERY := true`
- metadata partition
- F2FS userdata
- dynamic partitions

TeamWin's Motorola `penangf` tree independently confirms the same MT6768/vendor_boot pattern, including boot header v4, 64 MiB vendor_boot, metadata, F2FS and recovery-in-vendor_boot.

The TeamWin Nothing Phone (2a) tree provides a second, newer vendor_boot precedent: it uses header v4, generic kernel, recovery modules in vendor_boot and the same recovery relocation flags. Its SoC is different, so it is used only for modern vendor_boot/TWRP structure, not MTK hardware details.

## What was changed in KM5n

The donor audit resulted in only low-risk, architecture-level changes:

1. Set `TARGET_CPU_VARIANT_RUNTIME := cortex-a55`, matching the CPU class used by the closest MT6768 donor.
2. Set `TARGET_NO_KERNEL := true`, because KM5n supplies a stock/GKI kernel environment and this recovery build is not supposed to compile a kernel from the TWRP tree. The closest TeamWin MT6768 donor uses the same approach.
3. Define `BOARD_PAGE_SIZE` from the existing 4096-byte `BOARD_KERNEL_PAGESIZE` and use it for `mkbootimg` arguments, matching TeamWin's MT6768 convention.

No donor-specific kernel command line, DTB addresses, partition sizes, crypto libraries, proprietary blobs, or display paths were copied. Those are device-specific and must remain derived from KM5n stock evidence.

## Important non-copy findings

The current KM5n `device.mk` contains Android 15/API 35 configuration and virtual-A/B inheritance. The TeamWin MT6768 donor is Android 12.1/API 31 and therefore cannot be used as an Android 15 product configuration template.

KM5n also uses EROFS system/vendor/product partitions and Trustonic KeyMint, which differ from the donor. Those values remain authoritative in KM5n.

## Build objective

The next build should therefore test the KM5n tree with the proven MT6768/vendor_boot architecture while avoiding a kernel build that is not required for this recovery image.
