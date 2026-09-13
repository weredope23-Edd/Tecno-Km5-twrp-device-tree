#!/usr/bin/env bash
set -euo pipefail

# KM5n lightweight vendor_boot port.
# Keep the KM5n stock vendor_boot layout/kernel/platform ramdisk and replace
# only the vendor_boot v4 recovery ramdisk with the recovery component taken
# from a compatible donor TWRP vendor_boot image.

usage() {
  echo "Usage: $0 <stock_vendor_boot.img> <donor_twrp_vendor_boot.img> <output_vendor_boot.img>" >&2
  exit 2
}

[[ $# -eq 3 ]] || usage
STOCK=$1
DONOR=$2
OUT=$3

command -v magiskboot >/dev/null || { echo 'ERROR: magiskboot not found'; exit 1; }
for f in "$STOCK" "$DONOR"; do
  [[ -s "$f" ]] || { echo "ERROR: image missing: $f"; exit 1; }
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/stock" "$WORK/donor"
cp "$STOCK" "$WORK/stock/boot.img"
cp "$DONOR" "$WORK/donor/boot.img"

# MagiskBoot returns code 3 for a valid vendor_boot image. It still writes
# the unpacked components, so code 3 is expected and must not abort the port.
unpack_vendor_boot() {
  local dir=$1
  (
    cd "$dir"
    set +e
    magiskboot unpack -h boot.img
    local rc=$?
    set -e
    if [[ "$rc" -ne 0 && "$rc" -ne 3 ]]; then
      echo "ERROR: magiskboot failed to unpack vendor_boot (rc=$rc)" >&2
      return "$rc"
    fi
  )
}

unpack_vendor_boot "$WORK/stock"
unpack_vendor_boot "$WORK/donor"

for d in stock donor; do
  [[ -s "$WORK/$d/vendor_ramdisk_recovery.cpio" ]] || {
    echo "ERROR: $d vendor_boot did not expose vendor_ramdisk_recovery.cpio" >&2
    echo "--- $d unpack output ---" >&2
    find "$WORK/$d" -maxdepth 1 -type f -printf '%f %s bytes\n' | sort >&2
    exit 1
  }
done

# Preserve the complete KM5n stock vendor_boot and swap only the recovery
# component. This leaves KM5n's stock kernel, DTB, platform ramdisk, vendor
# modules, bootconfig and cmdline intact. init_boot remains a separate image.
cp "$WORK/donor/vendor_ramdisk_recovery.cpio" "$WORK/stock/vendor_ramdisk_recovery.cpio"

(
  cd "$WORK/stock"
  magiskboot repack boot.img
)

[[ -s "$WORK/stock/new-boot.img" ]] || { echo 'ERROR: magiskboot produced no output'; exit 1; }
cp "$WORK/stock/new-boot.img" "$OUT"

SIZE=$(stat -c '%s' "$OUT")
[[ "$SIZE" -eq 67108864 ]] || {
  echo "ERROR: output vendor_boot is $SIZE bytes; expected exactly 67108864 bytes" >&2
  exit 1
}

sha256sum "$OUT"
echo "OK: stock KM5n vendor_boot repacked with donor TWRP recovery fragment: $OUT ($SIZE bytes)"
