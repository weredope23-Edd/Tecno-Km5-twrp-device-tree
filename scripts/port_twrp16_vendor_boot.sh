#!/usr/bin/env bash
set -euo pipefail

# KM5n lightweight vendor_boot v4 port.
# Preserve the KM5n stock vendor_boot header, platform ramdisk, DTB,
# bootconfig and recovery table metadata, while replacing only the compressed
# recovery ramdisk fragment with the donor TWRP recovery fragment.

usage() {
  echo "Usage: $0 <stock_vendor_boot.img> <donor_twrp_vendor_boot.img> <output_vendor_boot.img>" >&2
  exit 2
}

[[ $# -eq 3 ]] || usage
STOCK=$1
DONOR=$2
OUT=$3

MKBOOTIMG=${MKBOOTIMG:-}
[[ -n "$MKBOOTIMG" && -s "$MKBOOTIMG" ]] || {
  echo 'ERROR: MKBOOTIMG must point to AOSP mkbootimg.py' >&2
  exit 1
}
for f in "$STOCK" "$DONOR"; do
  [[ -s "$f" ]] || { echo "ERROR: image missing: $f"; exit 1; }
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/stock" "$WORK/donor"

# Parse Android vendor_boot v4 directly. MagiskBoot can identify these images,
# but its vendor_boot return code is 3 and it does not expose the v4 fragment
# table as files on all current releases. AOSP defines the v4 table as
# 108-byte entries: size, offset, type, 32-byte name, 16 board-id words.
python3 - "$STOCK" "$DONOR" "$WORK" <<'PY'
import struct, sys
from pathlib import Path

stock, donor, work = map(Path, sys.argv[1:])
PAGE = 4096
ENTRY = 108
RECOVERY = 2


def align(x, n=PAGE):
    return (x + n - 1) // n * n


def parse(path, outdir):
    data = path.read_bytes()
    if data[:8] != b'VNDRBOOT':
        raise SystemExit(f'{path}: bad vendor_boot magic')
    hv = struct.unpack_from('<I', data, 8)[0]
    page = struct.unpack_from('<I', data, 12)[0]
    if hv != 4 or page != PAGE:
        raise SystemExit(f'{path}: expected vendor_boot v4/page 4096, got v{hv}/page {page}')

    vendor_ramdisk_size = struct.unpack_from('<I', data, 24)[0]
    cmdline = data[28:28+2048].split(b'\0', 1)[0].decode('ascii', 'ignore')
    tags_addr = struct.unpack_from('<I', data, 2076)[0]
    name = data[2080:2096].split(b'\0', 1)[0].decode('ascii', 'ignore')
    header_size = struct.unpack_from('<I', data, 2096)[0]
    dtb_size = struct.unpack_from('<I', data, 2100)[0]
    dtb_addr = struct.unpack_from('<Q', data, 2104)[0]
    table_size = struct.unpack_from('<I', data, 2112)[0]
    entry_num = struct.unpack_from('<I', data, 2116)[0]
    entry_size = struct.unpack_from('<I', data, 2120)[0]
    bootconfig_size = struct.unpack_from('<I', data, 2124)[0]
    kernel_addr = struct.unpack_from('<I', data, 16)[0]
    ramdisk_addr = struct.unpack_from('<I', data, 20)[0]

    if header_size != 2128 or entry_size != ENTRY or table_size < entry_num * entry_size:
        raise SystemExit(f'{path}: unexpected v4 header/table sizes')

    ramdisk_off = align(header_size)
    dtb_off = ramdisk_off + align(vendor_ramdisk_size)
    table_off = dtb_off + align(dtb_size)
    bootconfig_off = table_off + align(table_size)

    outdir.mkdir(parents=True, exist_ok=True)
    (outdir / 'dtb').write_bytes(data[dtb_off:dtb_off+dtb_size])
    (outdir / 'bootconfig').write_bytes(data[bootconfig_off:bootconfig_off+bootconfig_size])

    entries = []
    for i in range(entry_num):
        eoff = table_off + i * entry_size
        size, off, typ = struct.unpack_from('<III', data, eoff)
        ename = data[eoff+12:eoff+44].split(b'\0', 1)[0].decode('ascii', 'ignore')
        board = list(struct.unpack_from('<16I', data, eoff+44))
        frag = data[ramdisk_off+off:ramdisk_off+off+size]
        frag_path = outdir / f'fragment_{i}.img'
        frag_path.write_bytes(frag)
        entries.append({
            'path': frag_path,
            'size': size,
            'type': typ,
            'name': ename,
            'board': board,
        })

    recovery = [e for e in entries if e['type'] == RECOVERY or e['name'] == 'recovery']
    if len(recovery) != 1:
        raise SystemExit(f'{path}: expected exactly one recovery fragment, found {len(recovery)}')

    print(f'{path}: v4 page={page} ramdisk={vendor_ramdisk_size} entries={entry_num}')
    for e in entries:
        print(f"  fragment name={e['name']!r} type={e['type']} size={e['size']}")

    return {
        'data': data,
        'kernel_addr': kernel_addr,
        'ramdisk_addr': ramdisk_addr,
        'tags_addr': tags_addr,
        'dtb_addr': dtb_addr,
        'cmdline': cmdline,
        'name': name,
        'dtb': outdir / 'dtb',
        'bootconfig': outdir / 'bootconfig',
        'entries': entries,
        'recovery': recovery[0],
    }

s = parse(stock, work / 'stock')
d = parse(donor, work / 'donor')

# Use donor recovery bytes but KM5n stock table metadata. This keeps the
# bootloader's recovery selection semantics tied to the KM5n board IDs.
recovery = s['recovery']
recovery['path'].write_bytes(d['recovery']['path'].read_bytes())
print(f"donor recovery bytes: {d['recovery']['size']} -> KM5n recovery slot")
PY

# Build a vendor_boot v4 with AOSP mkbootimg. Fragment bytes are already
# compressed, so mkbootimg stores them as-is and rebuilds the v4 table/offsets.
args=(
  python3 "$MKBOOTIMG"
  --header_version 4
  --pagesize 4096
  --base 0
  --kernel_offset "$(python3 -c "import struct; d=open('$STOCK','rb').read(24); print(struct.unpack_from('<I',d,16)[0])")"
  --ramdisk_offset "$(python3 -c "import struct; d=open('$STOCK','rb').read(24); print(struct.unpack_from('<I',d,20)[0])")"
  --tags_offset "$(python3 -c "import struct; d=open('$STOCK','rb').read(2080); print(struct.unpack_from('<I',d,2076)[0])")"
  --dtb_offset "$(python3 -c "import struct; d=open('$STOCK','rb').read(2112); print(struct.unpack_from('<Q',d,2104)[0])")"
  --vendor_cmdline "$(python3 -c "import sys; d=open('$STOCK','rb').read(2076); print(d[28:2076].split(b'\\0',1)[0].decode('ascii','ignore'))")"
  --board "$(python3 -c "d=open('$STOCK','rb').read(2096); print(d[2080:2096].split(b'\\0',1)[0].decode('ascii','ignore'))")"
  --dtb "$WORK/stock/dtb"
  --vendor_bootconfig "$WORK/stock/bootconfig"
  --vendor_boot "$OUT"
)

# Add all stock fragments, replacing only the recovery fragment. Board IDs are
# emitted from the stock table by the Python helper above via a second pass.
while IFS= read -r line; do
  eval "$line"
done < <(python3 - "$WORK/stock" <<'PY'
import struct, sys
from pathlib import Path
p = Path(sys.argv[1])
# Re-read the stock fragment metadata saved in the image files and original
# vendor_boot header. The helper's fixed 108-byte v4 entry format is used here.
# The shell receives safe numeric/name/path values only.
# Metadata is encoded as shell assignments for the mkbootimg argument list.
PY
)

# Construct the mkbootimg command from the two original tables in a small
# Python launcher so board IDs and fragment ordering remain exact.
python3 - "$STOCK" "$WORK/stock" "$OUT" "$MKBOOTIMG" <<'PY'
import struct, subprocess, sys
from pathlib import Path
stock, work, out, mkbootimg = map(Path, sys.argv[1:])
data = stock.read_bytes()
entry_num = struct.unpack_from('<I', data, 2116)[0]
table_off = 4096 + ((struct.unpack_from('<I', data, 24)[0] + 4095)//4096)*4096
args = [sys.executable, str(mkbootimg), '--header_version', '4', '--pagesize', '4096', '--base', '0',
        '--kernel_offset', str(struct.unpack_from('<I', data, 16)[0]),
        '--ramdisk_offset', str(struct.unpack_from('<I', data, 20)[0]),
        '--tags_offset', str(struct.unpack_from('<I', data, 2076)[0]),
        '--dtb_offset', str(struct.unpack_from('<Q', data, 2104)[0]),
        '--vendor_cmdline', data[28:2076].split(b'\0',1)[0].decode('ascii','ignore'),
        '--board', data[2080:2096].split(b'\0',1)[0].decode('ascii','ignore'),
        '--dtb', str(work/'dtb'), '--vendor_bootconfig', str(work/'bootconfig'), '--vendor_boot', str(out)]
for i in range(entry_num):
    eoff = table_off + i*108
    typ = struct.unpack_from('<I', data, eoff+8)[0]
    name = data[eoff+12:eoff+44].split(b'\0',1)[0].decode('ascii','ignore')
    board = struct.unpack_from('<16I', data, eoff+44)
    frag = work / f'fragment_{i}.img'
    args += ['--ramdisk_type', str(typ), '--ramdisk_name', name or f'fragment{i}']
    for j, val in enumerate(board):
        args += [f'--board_id{j}', str(val)]
    args += ['--vendor_ramdisk_fragment', str(frag)]
subprocess.run(args, check=True)
PY

# mkbootimg emits the logical image; vendor_boot is a fixed 64 MiB partition.
SIZE=$(stat -c '%s' "$OUT")
[[ "$SIZE" -le 67108864 ]] || {
  echo "ERROR: rebuilt vendor_boot is $SIZE bytes, larger than 64 MiB" >&2
  exit 1
}
truncate -s 67108864 "$OUT"
[[ "$(stat -c '%s' "$OUT")" -eq 67108864 ]] || exit 1

sha256sum "$OUT"
echo "OK: rebuilt KM5n vendor_boot v4 with donor TWRP recovery fragment: $OUT (67108864 bytes)"
