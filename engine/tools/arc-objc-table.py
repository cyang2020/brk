#!/usr/bin/env python3
"""Turn `otool -arch arm64 -ov` text into one readable table per class and protocol. Reads text only; the text is data."""
import re, sys, json
path, out = sys.argv[1], sys.argv[2]
lines = open(path, errors='replace').read().split('\n')
# selector refs: address -> name
sel = {}
start = next(i for i, l in enumerate(lines) if '__objc_selrefs' in l)
base = int(sys.argv[3], 16)
n = 0
for l in lines[start + 1:]:
    if l.startswith('Contents of'): break
    m = re.match(r'^\s*0x[0-9a-f]+\s+(\S.*)$', l)
    if m:
        sel[base + 8 * n] = m.group(1)
    n += 1
classes, protos, cur = {}, {}, None
name_re = re.compile(r'^\s+name\s+0x[0-9a-f]+\s+(\S+)$')
meth_re = re.compile(r'^\s+name\s+0x[0-9a-f]+\s+\((0x[0-9a-f]+)\)')
abs_meth = re.compile(r'^\s+name\s+0x[0-9a-f]+\s+(\S+)$')
i = 0
section = None
stack = []
results = {}
for i, l in enumerate(lines):
    if l.startswith('Contents of'):
        section = l
        continue
    if section and '__objc_classlist' in section:
        m = re.match(r'^[0-9a-f]{16} 0x[0-9a-f]+ ?(\S*)$', l)
        if m:
            cur = {'name': None, 'super': None, 'meta': False, 'inst': [], 'class': [], 'protos': [], 'props': []}
            results[len(results)] = cur
            depth = 'inst'
            continue
        if cur is None: continue
        s = l.strip()
        if s.startswith('superclass'):
            parts = s.split()
            sup = parts[2] if len(parts) > 2 else None
            if cur['super'] is None: cur['super'] = sup
        elif s.startswith('Meta Class'):
            depth = 'class'
        elif s.startswith('baseProtocols'):
            mode = 'protos'
        m = re.match(r'^\s{8}name\s+0x[0-9a-f]+\s+(\S+)$', l)
        if m and cur['name'] is None:
            cur['name'] = m.group(1)
        m = re.match(r'^\s{12}name\s+0x[0-9a-f]+\s+\((0x[0-9a-f]+)\)', l)
        if m:
            a = int(m.group(1), 16)
            cur[depth].append(sel.get(a, hex(a)))
        m = re.match(r'^\s{16}name\s+0x[0-9a-f]+\s+(\S+)$', l)
        if m:
            cur['protos'].append(m.group(1))
        m = re.match(r'^\s{12}name\s+(?:0x[0-9a-f]+\s+)?([A-Za-z_][A-Za-z0-9_]*)$', l)
        if m and not l.strip().startswith('name    0x') :
            pass
with open(out, 'w') as f:
    for c in results.values():
        if not c['name']: continue
        f.write(f"@class {c['name']} : {c['super']}\n")
        if c['protos']: f.write('  protocols: ' + ', '.join(sorted(set(c['protos']))) + '\n')
        for m in c['class']: f.write(f"  + {m}\n")
        for m in c['inst']: f.write(f"  - {m}\n")
print(len(results), 'classes;', len(sel), 'selrefs')
