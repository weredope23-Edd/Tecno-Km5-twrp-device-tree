#!/usr/bin/env python3
import hashlib
import shutil
import struct
import sys
from pathlib import Path
import lz4.block


def parse(path):
    b = Path(path).read_bytes()
    if len(b) < 4096 or b[:8] != b"VNDRBOOT":
        raise RuntimeError(f"not a vendor_boot image: {path}")
    page = struct.unpack_from("<I", b, 12)[0]
    total = struct.unpack_from("<I", b, 24)[0]
    dtb_sz = struct.unpack_from("<I", b, 2100)[0]
    table_sz, n, entry_sz, _ = struct.unpack_from("<IIII", b, 2112)
    ramoff = page
    dtb_off = ((ramoff + total + page - 1) // page) * page
    table_off = ((dtb_off + dtb_sz + page - 1) // page) * page
    table = b[table_off:table_off + table_sz]
    entries = []
    for i in range(n):
        sz, off, typ = struct.unpack_from("<III", table, i * entry_sz)
        entries.append((sz, off, typ, b[ramoff + off:ramoff + off + sz]))
    return b, page, total, dtb_sz, table_sz, n, entry_sz, table, entries, dtb_off, table_off


def dec_legacy(frame):
    if frame[:4] != b"\x02\x21\x4c\x18":
        raise RuntimeError(f"unsupported ramdisk compression/magic: {frame[:8].hex()}")
    p = 4
    out = bytearray()
    while p + 4 <= len(frame):
        sz = struct.unpack_from("<I", frame, p)[0]
        p += 4
        if sz == 0:
            break
        c = frame[p:p + sz]
        p += sz
        decoded = None
        for us in (16 << 20, 8 << 20, 4 << 20, 2 << 20, 1 << 20, 512 << 10, 256 << 10, 128 << 10, 64 << 10, 32 << 10, 16 << 10, 8 << 10):
            try:
                decoded = lz4.block.decompress(c, uncompressed_size=us)
                break
            except Exception:
                pass
        if decoded is None:
            raise RuntimeError("cannot decompress LZ4 ramdisk block")
        out += decoded
    return bytes(out)


def cpio_read(data):
    files = {}
    p = 0
    while p + 110 <= len(data) and data[p:p + 6] == b"070701":
        hx = lambda a: int(data[p + a:p + a + 8], 16)
        mode, uid, gid, size, nz = hx(14), hx(22), hx(30), hx(54), hx(94)
        name = data[p + 110:p + 110 + nz - 1].decode(errors="replace")
        off = (p + 110 + nz + 3) & ~3
        files[name] = (mode, uid, gid, data[off:off + size])
        p = (off + size + 3) & ~3
        if name == "TRAILER!!!":
            break
    if "TRAILER!!!" not in files:
        raise RuntimeError("recovery ramdisk is not a valid newc cpio archive")
    return files


def cpio_write(files):
    def align(x): return (x + 3) & ~3
    out = bytearray(); ino = 1
    for name in sorted(k for k in files if k != "TRAILER!!!"):
        mode, uid, gid, payload = files[name]
        vals = [ino, mode, 0, uid, gid, 1, 0, len(payload), 0, 0, 0, 0, len(name) + 1, 0]
        out += b"070701" + b"".join(f"{x:08x}".encode() for x in vals) + name.encode() + b"\0"
        out += b"\0" * (align(len(out)) - len(out)); out += payload
        out += b"\0" * (align(len(out)) - len(out)); ino += 1
    name = "TRAILER!!!"
    vals = [ino, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, len(name) + 1, 0]
    out += b"070701" + b"".join(f"{x:08x}".encode() for x in vals) + name.encode() + b"\0"
    out += b"\0" * (align(len(out)) - len(out))
    return bytes(out)


def enc_legacy(data):
    out = bytearray(b"\x02\x21\x4c\x18")
    for i in range(0, len(data), 8 << 20):
        c = lz4.block.compress(data[i:i + (8 << 20)], store_size=False, mode="high_compression", compression=12)
        out += struct.pack("<I", len(c)) + c
    out += struct.pack("<I", 0)
    return bytes(out)


def rebuild(donor, newrec):
    b, page, total, dtbs, tsz, n, esz, table, entries, dtbo, tbo = parse(donor)
    if n < 2: raise RuntimeError("vendor_boot has no recovery ramdisk entry")
    platform = entries[0][3]; ram = platform + newrec
    h = bytearray(b[:page]); struct.pack_into("<I", h, 24, len(ram))
    nt = bytearray(table)
    struct.pack_into("<III", nt, 0, len(platform), 0, entries[0][2])
    struct.pack_into("<III", nt, esz, len(newrec), len(platform), entries[1][2])
    out = bytes(h) + ram
    out += b"\0" * ((-len(out)) % page); out += b[dtbo:dtbo + dtbs]
    out += b"\0" * ((-len(out)) % page); out += nt
    return out.ljust(64 * 1024 * 1024, b"\0")[:64 * 1024 * 1024]


TOUCH_MODULES = [
    "adaptive-ts.ko", "novatek_nt36xxx.ko", "omnivision_td4160.ko",
    "nt36528a_hdp_dsi_vdo_hx_hxt9_120hz_km5.ko",
    "td4160_hdp_dsi_vdo_dpt_hkc_120hz_km5.ko",
    "td4160_hdp_dsi_vdo_txd_boe_120hz_km5.ko",
    "mtk_disp_notify.ko", "tran_drm_panel_i2c.ko", "mtk_panel_ext.ko",
    "tnek.ko", "transsion_tranlog.ko",
]


def transplant_touch(donor_rec, tree_root):
    module_dir = Path(tree_root) / "lib" / "modules"
    missing = [m for m in TOUCH_MODULES if not (module_dir / m).is_file()]
    if missing: raise RuntimeError("missing KM5n touch modules: " + ", ".join(missing))
    changed = []
    for module in TOUCH_MODULES:
        src = module_dir / module; dst = "lib/modules/" + module
        old = donor_rec.get(dst, (0o100644, 0, 0, b""))
        donor_rec[dst] = (old[0], old[1], old[2], src.read_bytes()); changed.append(dst)
    load_path = "lib/modules/modules.load.recovery"
    old = donor_rec.get(load_path, (0o100644, 0, 0, b""))
    lines = old[3].decode(errors="replace").splitlines()
    for module in TOUCH_MODULES:
        if module not in lines: lines.append(module)
    donor_rec[load_path] = (old[0], old[1], old[2], ("\n".join(lines) + "\n").encode())
    changed.append(load_path)
    return changed


def main():
    if len(sys.argv) < 4: raise SystemExit("usage: script inspect|modify donor work [mode test stock]")
    action, donor, work = sys.argv[1:4]; w = Path(work); w.mkdir(parents=True, exist_ok=True)
    b, page, total, dtbs, tsz, n, esz, table, entries, dtbo, tbo = parse(donor)
    (w / "manifest.txt").write_text("\n".join([f"vendor_boot_size={len(b)}", f"page_size={page}", f"header_ramdisk_total={total}", f"ramdisk_count={n}", f"entry_size={esz}", *[f"entry{i}: size={e[0]} offset={e[1]} type={e[2]}" for i, e in enumerate(entries)], f"donor_sha256={hashlib.sha256(b).hexdigest()}"]) + "\n")
    if action == "inspect": return
    mode = sys.argv[4] if len(sys.argv) > 4 else "none"; test = sys.argv[5] if len(sys.argv) > 5 else "test"
    out = w / "output"; out.mkdir(parents=True, exist_ok=True)
    if mode in ("none", "inspect-only"):
        shutil.copy2(donor, out / "vendor_boot.img"); (w / "diff.txt").write_text(f"mode={mode}\ntest={test}\nNo image mutation.\n"); return
    if mode == "repack-only":
        donor_rec = cpio_read(dec_legacy(entries[1][3]))
        newrec = enc_legacy(cpio_write(donor_rec))
        (out / "vendor_boot.img").write_bytes(rebuild(donor, newrec))
        (w / "diff.txt").write_text(f"mode={mode}\ntest={test}\nNo file changes; donor recovery ramdisk decoded and repacked only.\n")
        return
    if mode not in ("ueventd-only", "touch-init", "stock-dtb-touch"):
        raise SystemExit("unsupported modification: " + mode)
    if len(sys.argv) < 7: raise SystemExit(f"{mode} requires stock vendor_boot path")
    stock = sys.argv[6]; _, _, _, _, _, _, _, _, sentries, _, _ = parse(stock)
    donor_rec = cpio_read(dec_legacy(entries[1][3])); stock_rec = cpio_read(dec_legacy(sentries[1][3])); changed = []
    stock_bytes = Path(stock).read_bytes()
    _, stock_page, _, stock_dtbs, _, _, _, _, _, stock_dtb_off, _ = parse(stock)
    donor_dtb = b[dtbo:dtbo + dtbs]
    stock_dtb = stock_bytes[stock_dtb_off:stock_dtb_off + stock_dtbs
    if mode == "ueventd-only":
        common = [name for name in stock_rec if name != "TRAILER!!!" and "ueventd" in name.lower() and name in donor_rec]
        if not common: raise SystemExit("No common ueventd files found")
        for name in common: donor_rec[name] = stock_rec[name]; changed.append(name)
    else:
        changed = transplant_touch(donor_rec, "device/tecno/km5n/recovery/root")
    rebuilt = rebuild(donor, enc_legacy(cpio_write(donor_rec)))
    if mode == "stock-dtb-touch":
        if stock_page != page:
            raise SystemExit("page-size mismatch: donor=" + str(page) + " stock=" + str(stock_page))
        if stock_dtbs <= 0:
            raise SystemExit("stock vendor_boot has no DTB payload")
        ram = enc_legacy(cpio_write(donor_rec))
        dtb_off = ((page + len(ram) + page - 1) // page) * page
        rebuilt_b = bytearray(rebuilt)
        rebuilt_b[dtb_off:dtb_off + stock_dtbs] = stock_dtb
        rebuilt = bytes(rebuilt_b)
        changed.append("vendor_boot DTB replaced with stock DTB")
        print("DTB comparison: donor=", hashlib.sha256(donor_dtb).hexdigest(), "stock=", hashlib.sha256(stock_dtb).hexdigest())
    (out / "vendor_boot.img").write_bytes(rebuilt)
    (w / "diff.txt").write_text(f"mode={mode}\ntest={test}\nChanged files:\n" + "\n".join(changed) + "\n")
    print("Changed:", ", ".join(changed))

if __name__ == "__main__": main()
