"""constblobs.py lo hi: adrp+add/ldr targets in __TEXT,__const from code in [lo,hi) whose bytes read as runs of plausible doubles."""
import sys, struct, bisect; sys.path.insert(0, '/tmp/cbr/tools'); from macho import *
lo, hi = int(sys.argv[1], 16), int(sys.argv[2], 16)
ca, cs, co = sects[('__TEXT', '__const')]
w = words(); base = TEXT[0]
hits = {}
for k in range((lo - base) // 4, (hi - base) // 4):
    x = w[k]
    if x & 0x9f000000 != 0x90000000: continue
    rd = x & 31; imm = (((x >> 5) & 0x7ffff) << 2) | ((x >> 29) & 3)
    if imm & (1 << 20): imm -= 1 << 21
    pc = base + k * 4; page = (pc & ~0xfff) + (imm << 12)
    if not (ca <= page < ca + cs + 0x1000): continue
    for j in range(k + 1, min(k + 8, len(w))):
        u = w[j]
        if ((u >> 5) & 31) != rd: continue
        if u & 0xffc00000 == 0x91000000: t = page + ((u >> 10) & 0xfff)
        elif u & 0xffc00000 == 0xfd400000: t = page + ((u >> 10) & 0xfff) * 8   # ldr d
        elif u & 0xffc00000 == 0x3dc00000: t = page + ((u >> 10) & 0xfff) * 16  # ldr q
        else: break
        hits.setdefault(t, []).append(pc); break
def plaus(v):
    if v == 0: return True
    e = (v >> 52) & 0x7ff
    return 0x3e0 <= e <= 0x40f
for t in sorted(hits):
    if not (ca <= t < ca + cs): continue
    vals = []
    for i in range(64):
        v = u64(t + 8 * i)
        if not plaus(v): break
        vals.append(struct.unpack('<d', struct.pack('<Q', v))[0])
    if vals and any(x != 0 for x in vals):
        fs = func_of(hits[t][0])[0]
        print(hex(t), 'from', [hex(p) for p in hits[t][:3]], 'func', hex(fs), len(vals), [round(x, 6) for x in vals[:40]])
