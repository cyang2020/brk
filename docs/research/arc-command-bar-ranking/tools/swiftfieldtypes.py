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
a0, size, o0 = sects[('__TEXT', '__swift5_fieldmd')]
KIND = {0: 'struct', 1: 'class', 2: 'enum', 3: 'enum', 4: 'protocol', 5: 'protocol', 6: 'objcproto', 7: 'objcclass'}
out = open(sys.argv[1], 'w'); a = a0; n = 0
while a < a0 + size:
    mt, sc = struct.unpack('<ii', rd(a, 8)); kind, frs, nf = struct.unpack('<HHI', rd(a + 8, 8))
    tn = mangled(a + mt) if mt else '?'
    fields = []
    for k in range(nf):
        r = a + 16 + k * frs
        fl, fmt, fnm = struct.unpack('<Iii', rd(r, 12))
        nm = cstr(r + 8 + fnm) if fnm else ''
        ty = mangled(r + 4 + fmt) if fmt else ''
        fields.append('%s: %s' % (nm, ty))
    out.write('%s\t%s\t%d\t%s\n' % (KIND.get(kind, kind), tn, nf, ' | '.join(fields)))
    a += 16 + nf * frs; n += 1
print(n)
