#!/usr/bin/env python3
import os,sys,struct,hashlib,shutil,subprocess,stat
from pathlib import Path
import lz4.block

def parse(path):
    b=Path(path).read_bytes(); page=struct.unpack_from('<I',b,12)[0]; total=struct.unpack_from('<I',b,24)[0]
    dtb_sz=struct.unpack_from('<I',b,2100)[0]; table_sz,n,entry_sz,_=struct.unpack_from('<IIII',b,2112)
    ramoff=page; dtb_off=((ramoff+total+page-1)//page)*page; table_off=((dtb_off+dtb_sz+page-1)//page)*page
    table=b[table_off:table_off+table_sz]; entries=[]
    for i in range(n):
        sz,off,typ=struct.unpack_from('<III',table,i*entry_sz); entries.append((sz,off,typ,b[ramoff+off:ramoff+off+sz]))
    return b,page,total,dtb_sz,table_sz,n,entry_sz,table,entries,dtb_off,table_off

def dec_legacy(frame):
    if frame[:4] != b'\\x02\\x21\\x4c\\x18': raise RuntimeError('unsupported ramdisk compression')
    p=4; out=bytearray()
    while p+4<=len(frame):
        sz=struct.unpack_from('<I',frame,p)[0]; p+=4
        if sz==0: break
        c=frame[p:p+sz]; p+=sz
        for us in (8<<20,4<<20,2<<20,1<<20,512<<10,256<<10,128<<10,64<<10,32<<10,16<<10,8<<10):
            try:
                out += lz4.block.decompress(c,uncompressed_size=us); break
            except Exception: pass
        else: raise RuntimeError('cannot decompress LZ4 ramdisk')
    return bytes(out)

def cpio_read(data):
    files={}; p=0
    while p+110<=len(data) and data[p:p+6]==b'070701':
        hx=lambda a:int(data[p+a:p+a+8],16)
        mode,uid,gid,size,nz=hx(14),hx(22),hx(30),hx(54),hx(94)
        name=data[p+110:p+110+nz-1].decode(errors='replace'); off=(p+110+nz+3)&~3
        files[name]=(mode,uid,gid,data[off:off+size])
        p=(off+size+3)&~3
        if name=='TRAILER!!!': break
    return files

def cpio_write(files):
    def a(x): return (x+3)&~3
    out=bytearray(); ino=1
    for name in sorted(k for k in files if k!='TRAILER!!!'):
        mode,uid,gid,payload=files[name]
        vals=[ino,mode,0,uid,gid,1,0,len(payload),0,0,0,0,len(name)+1,0]
        out+=b'070701'+b''.join(f'{x:08x}'.encode() for x in vals)+name.encode()+b'\\0'
        out+=b'\\0'*(a(len(out))-len(out)); out+=payload; out+=b'\\0'*(a(len(out))-len(out)); ino+=1
    name='TRAILER!!!'; vals=[ino,0,0,0,0,0,1,0,0,0,0,0,len(name)+1,0]
    out+=b'070701'+b''.join(f'{x:08x}'.encode() for x in vals)+name.encode()+b'\\0'; out+=b'\\0'*(a(len(out))-len(out))
    return bytes(out)

def enc_legacy(data):
    out=bytearray(b'\\x02\\x21\\x4c\\x18')
    for i in range(0,len(data),8<<20):
        c=lz4.block.compress(data[i:i+(8<<20)],store_size=False,mode='high_compression',compression=12)
        out+=struct.pack('<I',len(c))+c
    out+=struct.pack('<I',0)
    return bytes(out)

def rebuild(donor, newrec):
    b,page,total,dtbs,tsz,n,esz,table,entries,dtbo,tbo=parse(donor)
    if n<2: raise RuntimeError('vendor_boot has no recovery ramdisk entry')
    platform=entries[0][3]
    ram=platform+newrec
    h=bytearray(b[:page]); struct.pack_into('<I',h,24,len(ram))
    nt=bytearray(table)
    struct.pack_into('<III',nt,0,len(platform),0,entries[0][2])
    struct.pack_into('<III',nt,esz,len(newrec),len(platform),entries[1][2])
    out=bytes(h)+ram; out+=b'\\0'*((-len(out))%page); out+=b[dtbo:dtbo+dtbs]; out+=b'\\0'*((-len(out))%page); out+=nt
    return out.ljust(64*1024*1024,b'\\0')[:64*1024*1024]

def main():
    if len(sys.argv)<4: raise SystemExit('usage: script inspect|modify donor work [mode test stock]')
    action,donor,work=sys.argv[1:4]; w=Path(work); w.mkdir(parents=True,exist_ok=True)
    b,page,total,dtbs,tsz,n,esz,table,entries,dtbo,tbo=parse(donor)
    (w/'manifest.txt').write_text('\\n'.join([f'vendor_boot_size={len(b)}',f'page_size={page}',f'header_ramdisk_total={total}',f'ramdisk_count={n}',f'entry_size={esz}',*[f'entry{i}: size={e[0]} offset={e[1]} type={e[2]}' for i,e in enumerate(entries)],f'donor_sha256={hashlib.sha256(b).hexdigest()}'])+'\\n')
    if action=='inspect': return
    mode=sys.argv[4] if len(sys.argv)>4 else 'none'; test=sys.argv[5] if len(sys.argv)>5 else 'test'
    out=w/'output'; out.mkdir(parents=True,exist_ok=True)
    if mode=='none' or mode=='inspect-only':
        shutil.copy2(donor,out/'vendor_boot.img'); (w/'diff.txt').write_text(f'mode={mode}\\ntest={test}\\nNo image mutation.\\n'); return
    if mode!='ueventd-only': raise SystemExit('touch-init is intentionally disabled until boot-safe ueventd experiment is validated')
    if len(sys.argv)<7: raise SystemExit('ueventd-only requires stock vendor_boot path')
    stock=sys.argv[6]
    sb,_,_,_,_,sn,_,_,sentries,_,_=parse(stock)
    donor_rec=cpio_read(dec_legacy(entries[1][3])); stock_rec=cpio_read(dec_legacy(sentries[1][3]))
    names=[n for n in stock_rec if n!='TRAILER!!!' and ('ueventd' in n.lower())]
    common=[n for n in names if n in donor_rec]
    if not common: raise SystemExit('No common ueventd files found; refusing to make a guessed modification')
    changed=[]
    for n in common:
        donor_rec[n]=stock_rec[n]; changed.append(n)
    new=rebuild(donor,enc_legacy(cpio_write(donor_rec))); (out/'vendor_boot.img').write_bytes(new)
    (w/'diff.txt').write_text(f'mode={mode}\\ntest={test}\\nChanged files:\\n'+'\\n'.join(changed)+'\\n')
    print('Changed:',', '.join(changed))
if __name__=='__main__': main()
