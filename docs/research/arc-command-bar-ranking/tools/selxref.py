"""selxref.py <selector>...: code that loads the ObjC selector reference (objc_msgSend call sites), with containing function."""
import sys; sys.path.insert(0, '/tmp/cbr/tools'); from macho import *
sr = sects[('__DATA', '__objc_selrefs')] if ('__DATA', '__objc_selrefs') in sects else sects[('__DATA_CONST', '__objc_selrefs')]
want = {}
names = sys.argv[1:]
for a in range(sr[0], sr[0] + sr[1], 8):
    p = ptr(a)
    if p is None: continue
    try: s = cstr(p)
    except Exception: continue
    if s in names: want[a] = s
print('selrefs', {hex(k): v for k, v in want.items()})
for pc, t in adrp_refs(want):
    fs, n = func_of(pc); print(want[t], hex(pc), 'in', hex(fs), n)
