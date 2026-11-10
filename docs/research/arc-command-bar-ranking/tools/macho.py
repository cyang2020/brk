"""Small Mach-O helpers for Arc's arm64 slice: segment mapping, reads, chained-fixup pointers, adrp xrefs."""
import struct, array, bisect, sys, os
BIN = os.environ.get('ARC_BIN', '/tmp/cbr/arc')
f = open(BIN, 'rb').read()
segs = []  # (vmaddr, vmsize, fileoff, filesize, name)
sects = {}
ncmds = struct.unpack('<I', f[16:20])[0]
o = 32
for _ in range(ncmds):
    cmd, sz = struct.unpack('<II', f[o:o+8])
    if cmd == 0x19:
        name = f[o+8:o+24].rstrip(b'\0').decode()
        vm, vs, fo, fs = struct.unpack('<QQQQ', f[o+24:o+56])
        segs.append((vm, vs, fo, fs, name))
        ns = struct.unpack('<I', f[o+64:o+68])[0]
        so = o + 72
        for k in range(ns):
            sn = f[so:so+16].rstrip(b'\0').decode(); sg = f[so+16:so+32].rstrip(b'\0').decode()
            a, s, off = struct.unpack('<QQI', f[so+32:so+52])
            sects[(sg, sn)] = (a, s, off)
            so += 80
    o += sz
def off(a):
    for vm, vs, fo, fs, n in segs:
        if vm <= a < vm + fs: return fo + (a - vm)
    raise ValueError(hex(a))
def u32(a): return struct.unpack('<I', f[off(a):off(a)+4])[0]
def i32(a): return struct.unpack('<i', f[off(a):off(a)+4])[0]
def u64(a): return struct.unpack('<Q', f[off(a):off(a)+8])[0]
def ptr(a):
    v = u64(a)
    if v >> 63: return None  # bind
    t = v & 0xfffffffff
    return 0x100000000 + t if t < 0x100000000 else t
def cstr(a):
    s = off(a); e = f.index(b'\0', s); return f[s:e].decode(errors='replace')
TEXT = sects[('__TEXT', '__text')]
_words = None
def words():
    global _words
    if _words is None:
        _words = array.array('I'); _words.frombytes(f[TEXT[2]:TEXT[2]+TEXT[1]])
    return _words
def adrp_refs(targets):
    """yield (pc, target) for adrp+add/ldr/ldr-x pairs computing a target address."""
    want = set(targets); pages = {t & ~0xfff for t in want}
    w = words(); n = len(w); base = TEXT[0]
    for i in range(n):
        x = w[i]
        if x & 0x9f000000 != 0x90000000: continue
        rd = x & 31
        imm = (((x >> 5) & 0x7ffff) << 2) | ((x >> 29) & 3)
        if imm & (1 << 20): imm -= 1 << 21
        pc = base + i * 4
        page = (pc & ~0xfff) + (imm << 12)
        if page not in pages: continue
        for j in range(i + 1, min(i + 12, n)):
            u = w[j]
            if ((u >> 5) & 31) != rd: continue
            if u & 0xffc00000 == 0x91000000: t = page + ((u >> 10) & 0xfff)
            elif u & 0xffc00000 == 0xf9400000: t = page + ((u >> 10) & 0xfff) * 8
            elif u & 0xffc00000 == 0xb9400000: t = page + ((u >> 10) & 0xfff) * 4
            else: continue
            if t in want: yield (base + j * 4, t)
            break
_funcs = None
def func_of(a):
    global _funcs
    if _funcs is None:
        _funcs = sorted(int(l, 16) for l in open('/tmp/cbr/funcs.txt'))
    i = bisect.bisect_right(_funcs, a) - 1
    return _funcs[i], _funcs[i+1] - _funcs[i]
def find_cstr(s):
    """vm addresses of an exact C string."""
    b = s.encode() + b'\0'; res = []
    for vm, vs, fo, fs, n in segs:
        seg = f[fo:fo+fs]; k = seg.find(b'\0' + b)
        while k >= 0:
            res.append(vm + k + 1); k = seg.find(b'\0' + b, k + 1)
    return res
