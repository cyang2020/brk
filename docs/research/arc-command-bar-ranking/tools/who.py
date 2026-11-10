"""who.py <hexaddr>...: every reference to an address: bl/b, adrp+add/ldr, absolute 64-bit pointers (chained rebase) and 32-bit relative pointers in non-code sections."""
import sys, struct; sys.path.insert(0, '/tmp/cbr/tools'); from macho import *
want = {int(a, 16) for a in sys.argv[1:]}
w = words(); base = TEXT[0]
for i, x in enumerate(w):
    if x & 0x7c000000 == 0x14000000:
        imm = x & 0x3ffffff
        if imm & (1 << 25): imm -= 1 << 26
        pc = base + i * 4; t = pc + imm * 4
        if t in want:
            fs, n = func_of(pc); print('branch', hex(t), 'from', hex(pc), 'in', hex(fs), n, 'bl' if x >> 31 else 'b')
for pc, t in adrp_refs(want):
    fs, n = func_of(pc); print('adrp', hex(t), 'from', hex(pc), 'in', hex(fs), n)
for (sg, sn), (a, s, o) in sects.items():
    if sn in ('__text', '__objc_stubs', '__stubs', '__auth_stubs', '__cstring', '__swift5_reflstr', '__objc_methname'): continue
    if s == 0 or o == 0: continue
    buf = f[o:o+s]
    for k in range(0, s - 3, 4):
        r = struct.unpack_from('<i', buf, k)[0]
        if a + k + r in want: print('rel32', hex(a + k + r), 'at', hex(a + k), sg, sn)
        if k % 8 == 0 and k + 8 <= s:
            v = struct.unpack_from('<Q', buf, k)[0]
            if not v >> 63:
                t = v & 0xfffffffff; t = 0x100000000 + t if t < 0x100000000 else t
                if t in want: print('ptr64', hex(t), 'at', hex(a + k), sg, sn)
