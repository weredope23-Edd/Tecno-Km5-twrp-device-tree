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
import struct,sys
from pathlib import Path
PAGE=4096; ENTRY=108

def align(x): return (x+PAGE-1)//PAGE*PAGE

def parse(path,out):
 d=Path(path).read_bytes()
 if d[:8]!=b'VNDRBOOT': raise SystemExit(f'{path}: bad magic')
 hv,page=struct.unpack_from('<II',d,8)
 if hv!=4 or page!=PAGE: raise SystemExit(f'{path}: expected v4/page 4096')
 rsz=struct.unpack_from('<I',d,24)[0]
 hs=struct.unpack_from('<I',d,2096)[0]; dtbsz=struct.unpack_from('<I',d,2100)[0]
 tsz,n,esz=struct.unpack_from('<III',d,2112)
 bcsz=struct.unpack_from('<I',d,2124)[0]
 if hs!=2128 or esz!=ENTRY or tsz<n*esz: raise SystemExit(f'{path}: bad v4 table')
 ramoff=align(hs)
 tableoff=ramoff+sum(align(struct.unpack_from('<I',d,ramoff+i*4)[0]) for i in [])
 # Physical fragment positions follow table order; table offsets are logical raw offsets.
 tableoff=ramoff+sum(align(struct.unpack_from('<I',d,2100)[0]) for _ in [])
 # DTB follows the physically padded ramdisk section. Its size is in the header.
 tableoff=ramoff+align(rsz)+align(dtbsz)
 bootoff=tableoff+align(tsz)
 out.mkdir(parents=True,exist_ok=True)
 (out/'dtb').write_bytes(d[ramoff+align(rsz):ramoff+align(rsz)+dtbsz])
 (out/'bootconfig').write_bytes(d[bootoff:bootoff+bcsz])
 entries=[]; physical=ramoff
 for i in range(n):
  e=tableoff+i*esz
  size,logical,typ=struct.unpack_from('<III',d,e)
  name=d[e+12:e+44].split(b'\0',1)[0].decode('ascii','ignore')
  board=struct.unpack_from('<16I',d,e+44)
  if logical!=sum(x['size'] for x in entries):
   raise SystemExit(f'{path}: non-cumulative logical offset at entry {i}: {logical}')
  frag=d[physical:physical+size]
  if len(frag)!=size: raise SystemExit(f'{path}: fragment {i} truncated')
  fp=out/f'fragment_{i}.img'; fp.write_bytes(frag)
  entries.append({'size':size,'type':typ,'name':name,'board':board,'path':fp})
  physical+=align(size)
 if physical!=ramoff+sum(align(x['size']) for x in entries): raise SystemExit('ramdisk layout error')
 rec=[x for x in entries if x['type']==2 or x['name']=='recovery']
 if len(rec)!=1: raise SystemExit(f'{path}: expected one recovery entry, got {len(rec)}')
 print(f'{path}: ramdisk={rsz} entries={n}, physical_end=0x{physical:x}')
 for x in entries: print(f"  {x['name']!r} type={x['type']} size={x['size']}")
 return {'data':d,'entries':entries,'recovery':rec[0]}

s=parse(sys.argv[1],Path(sys.argv[3])/'stock')
d=parse(sys.argv[2],Path(sys.argv[3])/'donor')
s['recovery']['path'].write_bytes(d['recovery']['path'].read_bytes())
print('recovery payload replaced with donor TWRP fragment')
PY

python3 - "$STOCK" "$WORK/stock" "$OUT" "$MKBOOTIMG" <<'PY'
import struct,subprocess,sys
from pathlib import Path
stock,work,out,mk=map(Path,sys.argv[1:])
d=stock.read_bytes(); page=4096
align=lambda x:(x+page-1)//page*page
args=[sys.executable,str(mk),'--header_version','4','--pagesize','4096','--base','0',
 '--kernel_offset',str(struct.unpack_from('<I',d,16)[0]),
 '--ramdisk_offset',str(struct.unpack_from('<I',d,20)[0]),
 '--tags_offset',str(struct.unpack_from('<I',d,2076)[0]),
 '--dtb_offset',str(struct.unpack_from('<Q',d,2104)[0]),
 '--vendor_cmdline',d[28:2076].split(b'\0',1)[0].decode('ascii','ignore'),
 '--board',d[2080:2096].split(b'\0',1)[0].decode('ascii','ignore'),
 '--dtb',str(work/'dtb'),'--vendor_bootconfig',str(work/'bootconfig'),'--vendor_boot',str(out)]
rsz=struct.unpack_from('<I',d,24)[0]; n,esz=struct.unpack_from('<II',d,2116); tableoff=align(2128)+align(rsz)+align(struct.unpack_from('<I',d,2100)[0])
for i in range(n):
 e=tableoff+i*esz; typ=struct.unpack_from('<I',d,e+8)[0]; name=d[e+12:e+44].split(b'\0',1)[0].decode('ascii','ignore'); board=struct.unpack_from('<16I',d,e+44)
 args += ['--ramdisk_type',str(typ),'--ramdisk_name',name or f'fragment{i}']
 for j,v in enumerate(board): args += [f'--board_id{j}',str(v)]
 args += ['--vendor_ramdisk_fragment',str(work/f'fragment_{i}.img')]
subprocess.run(args,check=True)
size=out.stat().st_size
if size>67108864: raise SystemExit(f'output {size} > 64MiB')
out.open('r+b').truncate(67108864)
print(f'OK: {out} 67108864 bytes')
PY
sha256sum "$OUT"
