#!/usr/bin/env bash
set -euo pipefail
usage() { echo "Usage: $0 <stock_vendor_boot.img> <donor_twrp_vendor_boot.img> <output_vendor_boot.img>" >&2; exit 2; }
[[ $# -eq 3 ]] || usage
STOCK=$1; DONOR=$2; OUT=$3
MKBOOTIMG=${MKBOOTIMG:-}
[[ -n "$MKBOOTIMG" && -s "$MKBOOTIMG" ]] || { echo 'ERROR: MKBOOTIMG must point to AOSP mkbootimg.py' >&2; exit 1; }
for f in "$STOCK" "$DONOR"; do [[ -s "$f" ]] || { echo "ERROR: image missing: $f" >&2; exit 1; }; done
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/stock" "$WORK/donor"

python3 - "$STOCK" "$DONOR" "$WORK" <<'PY'
import json, struct, sys, shutil
from pathlib import Path
PAGE = 4096
ENTRY = 108
align = lambda x: (x + PAGE - 1) // PAGE * PAGE

def parse(path, out):
    d = Path(path).read_bytes()
    if d[:8] != b'VNDRBOOT': raise SystemExit(f'{path}: bad magic')
    hv, page = struct.unpack_from('<II', d, 8)
    if hv != 4 or page != PAGE: raise SystemExit(f'{path}: expected v4/page 4096')
    rsz = struct.unpack_from('<I', d, 24)[0]
    hs = struct.unpack_from('<I', d, 2096)[0]
    dtbsz = struct.unpack_from('<I', d, 2100)[0]
    tsz, n, esz = struct.unpack_from('<III', d, 2112)
    bcsz = struct.unpack_from('<I', d, 2124)[0]
    if hs != 2128 or esz != ENTRY or tsz != n * esz:
        raise SystemExit(f'{path}: invalid v4 table header')
    ramoff = align(hs)
    dtboff = ramoff + align(rsz)
    tableoff = dtboff + align(dtbsz)
    table_end = tableoff + tsz
    bootconfig_end = align(table_end) + bcsz
    if bootconfig_end > len(d):
        raise SystemExit(f'{path}: v4 sections exceed image')

    entries = []
    logical = 0
    for i in range(n):
        e = tableoff + i * esz
        size, off, typ = struct.unpack_from('<III', d, e)
        name = d[e+12:e+44].split(b'\0', 1)[0]
        board = struct.unpack_from('<16I', d, e+44)
        if off != logical or logical + size > rsz or typ > 3:
            raise SystemExit(f'{path}: invalid ramdisk table entry {i}')
        entries.append({'size': size, 'offset': off, 'type': typ,
                        'name': name.decode('ascii', 'strict'), 'board': list(board)})
        logical += size
    if logical != rsz:
        raise SystemExit(f'{path}: table sizes {logical} != ramdisk_size {rsz}')

    out.mkdir(parents=True, exist_ok=True)
    (out / 'dtb').write_bytes(d[dtboff:dtboff+dtbsz])
    (out / 'bootconfig').write_bytes(d[align(table_end):align(table_end)+bcsz])
    for i, entry in enumerate(entries):
        start = ramoff + entry['offset']
        (out / f'fragment_{i}.img').write_bytes(d[start:start+entry['size']])
    meta = {'ramdisk_size': rsz, 'dtb_size': dtbsz, 'table_size': tsz,
            'num_entries': n, 'entry_size': esz, 'bootconfig_size': bcsz,
            'ramdisk_offset': ramoff, 'dtb_offset': dtboff,
            'table_offset': tableoff, 'entries': entries}
    (out / 'meta.json').write_text(json.dumps(meta, indent=2))
    print(f'{path}: ramdisk={rsz} dtb={dtbsz} entries={n} table=0x{tableoff:x}')
    for x in entries: print(f"  {x['name']!r} type={x['type']} size={x['size']} offset={x['offset']}")
    return meta

s = parse(sys.argv[1], Path(sys.argv[3]) / 'stock')
d = parse(sys.argv[2], Path(sys.argv[3]) / 'donor')
sidx = next(i for i, x in enumerate(s['entries']) if x['type'] == 2 or x['name'] == 'recovery')
didx = next(i for i, x in enumerate(d['entries']) if x['type'] == 2 or x['name'] == 'recovery')
shutil.copyfile(Path(sys.argv[3]) / 'donor' / f'fragment_{didx}.img', Path(sys.argv[3]) / 'stock' / f'fragment_{sidx}.img')
print(f"recovery payload replaced: stock {s['entries'][sidx]['size']} -> donor {d['entries'][didx]['size']} bytes")
PY

python3 - "$STOCK" "$WORK/stock" "$OUT" "$MKBOOTIMG" <<'PY'
import json, struct, subprocess, sys
from pathlib import Path
stock, work, out, mk = map(Path, sys.argv[1:])
d = stock.read_bytes()
m = json.loads((work / 'meta.json').read_text())
args = [sys.executable, str(mk), '--header_version', '4', '--pagesize', '4096',
        '--base', '0', '--kernel_offset', str(struct.unpack_from('<I', d, 16)[0]),
        '--ramdisk_offset', str(struct.unpack_from('<I', d, 20)[0]),
        '--tags_offset', str(struct.unpack_from('<I', d, 2076)[0]),
        '--dtb_offset', str(struct.unpack_from('<Q', d, 2104)[0]),
        '--vendor_cmdline', d[28:2076].split(b'\0', 1)[0].decode('ascii', 'ignore'),
        '--board', d[2080:2096].split(b'\0', 1)[0].decode('ascii', 'ignore'),
        '--dtb', str(work / 'dtb'), '--vendor_bootconfig', str(work / 'bootconfig'),
        '--vendor_boot', str(out)]
for i, e in enumerate(m['entries']):
    args += ['--ramdisk_type', str(e['type']), '--ramdisk_name', e['name'] or f'fragment{i}']
    for j, v in enumerate(e['board']): args += [f'--board_id{j}', str(v)]
    args += ['--vendor_ramdisk_fragment', str(work / f'fragment_{i}.img')]
subprocess.run(args, check=True)
size = out.stat().st_size
if size > 67108864: raise SystemExit(f'ERROR: generated vendor_boot is {size} bytes > 64MiB')
with out.open('ab') as f: f.write(b'\0' * (67108864 - size))
print(f'OK: {out} padded to exactly 67108864 bytes')
PY
sha256sum "$OUT"
