"""conformances.py [filter]: protocol conformance records of Arc (protocol name, conforming type, witness table pattern)."""
import sys, struct; sys.path.insert(0, '/tmp/cbr/tools'); from macho import *
sys.path.insert(0, '/tmp/cbr/tools')
from swiftfieldtypes_lib import ctxname
a0, size, _ = sects[('__TEXT', '__swift5_proto')]
flt = sys.argv[1] if len(sys.argv) > 1 else ''
def ind(a):
    r = i32(a)
    if r & 1:
        t = a + (r & ~1)
        try: v = ptr(t)
        except Exception: v = None
        return v
    return a + r
for e in range(a0, a0 + size, 4):
    cd = e + i32(e)
    try:
        proto = ind(cd); flags = u32(cd + 12); kind = (flags >> 3) & 7
        tr = cd + 4 + i32(cd + 4)
        if kind == 0: tname = ctxname(tr)
        elif kind == 1:
            t = ptr(tr) if True else None; tname = ctxname(t) if t else '?'
        elif kind in (2, 3):
            tname = 'objc:' + (cstr(tr) if kind == 2 else '?')
        else: tname = '?k%d' % kind
        pname = ctxname(proto) if proto else '?'
        wt = cd + 8 + i32(cd + 8)
    except Exception as ex:
        continue
    line = '%s\t%s\tdesc=%s\twt=%s' % (pname, tname, hex(cd), hex(wt))
    if flt in line: print(line)
