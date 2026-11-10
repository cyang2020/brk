"""stubcalls.py <selector>...: finds objc_msgSend$<sel> stubs in __objc_stubs and every bl/b to them."""
import sys; sys.path.insert(0, '/tmp/cbr/tools'); from macho import *
sr = sects.get(('__DATA', '__objc_selrefs')) or sects.get(('__DATA_CONST', '__objc_selrefs'))
st = sects[('__TEXT', '__objc_stubs')]
names = sys.argv[1:]
sel_at = {}
for a in range(sr[0], sr[0] + sr[1], 8):
    p = ptr(a)
    if p is None: continue
    try: s = cstr(p)
    except Exception: continue
    if s in names: sel_at[a] = s
stubs = {}
for a in range(st[0], st[0] + st[1], 32):
    x = u32(a)
    if x & 0x9f000000 != 0x90000000: continue
    imm = (((x >> 5) & 0x7ffff) << 2) | ((x >> 29) & 3)
    if imm & (1 << 20): imm -= 1 << 21
    page = (a & ~0xfff) + (imm << 12); y = u32(a + 4)
    t = page + ((y >> 10) & 0xfff) * 8
    if t in sel_at: stubs[a] = sel_at[t]
print({hex(k): v for k, v in stubs.items()})
w = words(); base = TEXT[0]
for i, x in enumerate(w):
    if x & 0x7c000000 != 0x14000000: continue
    imm = x & 0x3ffffff
    if imm & (1 << 25): imm -= 1 << 26
    pc = base + i * 4; t = pc + imm * 4
    if t in stubs:
        fs, n = func_of(pc); print(stubs[t], hex(pc), 'in', hex(fs), n)
