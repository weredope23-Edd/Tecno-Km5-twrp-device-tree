#!/usr/bin/env python3
import os,sys,struct,hashlib,shutil,subprocess
from pathlib import Path

def run(cmd):
    return subprocess.check_output(cmd, text=True).strip()

def parse(path):
    b=Path(path).read_bytes(); page=struct.unpack_from('<I',b,12)[0]; total=struct.unpack_from('<I',b,24)[0]
    dtb_sz=struct.unpack_from('<I',b,2100)[0]; table_sz,n,entry_sz,_=struct.unpack_from('<IIII',b,2112)
    ramoff=page; dtb_off=((ramoff+total+page-1)//page)*page; table_off=((dtb_off+dtb_sz+page-1)//page)*page
    table=b[table_off:table_off+table_sz]; entries=[]
    for i in range(n):
        sz,off,typ=struct.unpack_from('<III',table,i*entry_sz); entries.append((sz,off,typ,b[ramoff+off:ramoff+off+sz]))
    return b,page,total,dtb_sz,table_sz,n,entry_sz,table,entries,dtb_off,table_off

def main():
    if len(sys.argv)<4: raise SystemExit('usage: script inspect|modify vendor_boot work [mode test]')
    action,donor,work=sys.argv[1:4]; w=Path(work); w.mkdir(parents=True,exist_ok=True)
    b,page,total,dtbs,tsz,n,esz,table,entries,dtbo,tbo=parse(donor)
    (w/'manifest.txt').write_text('\n'.join([
        f'vendor_boot_size={len(b)}',f'page_size={page}',f'header_ramdisk_total={total}',f'ramdisk_count={n}',f'entry_size={esz}',
        *[f'entry{i}: size={e[0]} offset={e[1]} type={e[2]}' for i,e in enumerate(entries)],f'donor_sha256={hashlib.sha256(b).hexdigest()}'])+'\n')
    if action=='inspect':
        (w/'diff.txt').write_text('Inspection only; no modification requested.\n'); return
    mode=sys.argv[4] if len(sys.argv)>4 else 'none'; test=sys.argv[5] if len(sys.argv)>5 else 'test'
    if mode not in ('none','inspect-only','ueventd-only','touch-init'): raise SystemExit('unsupported modification')
    # Baseline implementation deliberately copies the donor byte-for-byte.
    # Modification hooks are kept explicit so each future experiment changes one thing.
    out=Path(w/'output'); out.mkdir(parents=True,exist_ok=True)
    shutil.copy2(donor,out/'vendor_boot.img')
    (w/'diff.txt').write_text(f'mode={mode}\ntest={test}\nNo image mutation performed in this baseline commit.\n')
    print('baseline output created')
if __name__=='__main__': main()
