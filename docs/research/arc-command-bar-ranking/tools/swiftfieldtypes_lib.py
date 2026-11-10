"""swiftfieldtypes.py <out.tsv>: every Swift field descriptor in Arc's arm64 slice with field names AND field type names
(symbolic references resolved to context names, written as <Module.Type>)."""
import struct, sys; sys.path.insert(0, '/tmp/cbr/tools'); from macho import *
def rd(a, n): o = off(a); return f[o:o+n]
def ctxname(a, depth=0):
    if a is None or depth > 8: return '?'
    try: fl, par, nm = struct.unpack('<Iii', rd(a, 12))
    except Exception: return '?ext'
    kind = fl & 0x1f; name = None
    if kind in (0, 16, 17, 18, 19, 3):
        try: name = cstr(a + 8 + nm)
        except Exception: name = '?'
    pa = None
    if par != 0:
        if par & 1:
            try: pa = u64(a + 4 + (par & ~1)) & 0xfffffffff
            except Exception: pa = None
            if pa is not None and pa < 0x100000000: pa += 0x100000000
        else: pa = a + 4 + par
    parent = ctxname(pa, depth + 1) if pa else ''
    if name is None: return parent or '?ext'
    return (parent + '.' if parent else '') + name
def mangled(a):
    out = []; i = 0
    while True:
        b = rd(a + i, 1)[0]
        if b == 0: break
        if 1 <= b <= 0x17:
            rel = struct.unpack('<i', rd(a + i + 1, 4))[0]; t = a + i + 1 + rel
            if b == 2:
                try:
                    t = u64(t) & 0xfffffffff
                    if t and t < 0x100000000: t += 0x100000000
                except Exception: t = 0
            out.append('<' + (ctxname(t) if t else '?bind') + '>'); i += 5
        elif 0x18 <= b <= 0x1f: out.append('<?%x>' % b); i += 9
        else: out.append(chr(b)); i += 1
        if i > 400: break
    return ''.join(out)
