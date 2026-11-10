"""dconst.py lo hi [min]: functions in [lo,hi) ranked by how many double constants they build (movz/movk 64-bit values,
fmov d,#imm). With 'show <func>' prints the constants of one function in order with the store that follows."""
import sys, struct; sys.path.insert(0, '/tmp/cbr/tools'); from macho import *
import bisect
def fmov_imm(imm8):
    s = (imm8 >> 7) & 1; e = (imm8 >> 4) & 7; m = imm8 & 15
    exp = (e ^ 4) - 3 if True else 0
    # VFPExpandImm for double: sign, NOT(b6), Replicate(b6,8), b5:b0, zeros
    b6 = (imm8 >> 6) & 1
    bits = (s << 63) | ((b6 ^ 1) << 62) | ((0xff if b6 else 0) << 54) | ((imm8 & 0x3f) << 48)
    return struct.unpack('<d', struct.pack('<Q', bits))[0]
def consts(start, n):
    w = words(); base = TEXT[0]; regs = {}; out = []
    for k in range((start - base) // 4, (start + n - base) // 4):
        x = w[k]; pc = base + k * 4
        if x & 0x7f800000 == 0x52800000 and x >> 31:  # movz x
            hw = (x >> 21) & 3; regs[x & 31] = ((x >> 5) & 0xffff) << (16 * hw)
        elif x & 0x7f800000 == 0x72800000 and x >> 31:  # movk x
            r = x & 31; hw = (x >> 21) & 3
            if r in regs:
                v = regs[r] & ~(0xffff << (16 * hw)) | (((x >> 5) & 0xffff) << (16 * hw)); regs[r] = v
                if hw == 3:
                    d = struct.unpack('<d', struct.pack('<Q', v))[0]
                    if v >> 52 & 0x7ff in range(0x3e0, 0x420) or v == 0: out.append((pc, d, 'x%d' % r))
        elif x & 0xff201fe0 == 0x1e601000:  # fmov d, #imm
            out.append((pc, fmov_imm((x >> 13) & 0xff), 'd%d' % (x & 31)))
        elif x & 0xfffffc00 == 0x9e670000:  # fmov d, x
            pass
    return out
if sys.argv[1] == 'show':
    s = int(sys.argv[2], 16); fs, n = func_of(s)
    for pc, d, r in consts(fs, n): print(hex(pc), r, repr(d))
else:
    lo, hi = int(sys.argv[1], 16), int(sys.argv[2], 16); mn = int(sys.argv[3]) if len(sys.argv) > 3 else 15
    fl = sorted(int(l, 16) for l in open('/tmp/cbr/funcs.txt'))
    i = bisect.bisect_left(fl, lo)
    res = []
    while i < len(fl) - 1 and fl[i] < hi:
        c = consts(fl[i], fl[i + 1] - fl[i])
        if len(c) >= mn: res.append((len(c), fl[i], fl[i + 1] - fl[i], len(set(round(d, 6) for _, d, _ in c))))
        i += 1
    for r in sorted(res, reverse=True)[:40]: print(r[0], hex(r[1]), r[2], 'distinct', r[3])
