#!/usr/bin/env python3
"""extract_defaults.py [arc-arm64]: reads Arc 1.170's built-in ranking configuration (ASE2.Configuration), default
boost list, missing-feature values and feature directions straight from the binary and prints them as JSON.

Where each number comes from (addresses in the arm64 slice of Arc 1.170, build 89123):
- 0x101d35e94..0x101d35f94 (in the ASE configuration client, 0x101d35c38): when no StorableASEConfiguration.json is
  loaded, the default Configuration is built on the stack from 16-byte constants (ldr q / fmov.2d / dup.2d) and
  then copied (0x101d35f98..0x101d36070) into the Configuration's memory: 51 doubles in declaration order, then the
  boosts array. LAYOUT below lists, per 16-byte slot of the Configuration, the source of its two doubles.
- 0x101d73324: the default boosts: for each Boost case 0..13, weight = table 0x10378e130[case],
  score = table 0x10378e0c0[case] (BoostConfiguration {boost, weight, score}).
- 0x101d76a94: the value used for a feature a candidate does not have: table 0x10378e6b0[feature].
- 0x101d76e48: 'lower is better' features (bit mask 0x54924, plus every case above 19); the normaliser
  (0x101d3e6dc) and the category scorer (0x101d3bb48) negate the z-score of those features.
"""
import struct, sys, json
BIN = sys.argv[1] if len(sys.argv) > 1 else '/tmp/cbr/arc'
f = open(BIN, 'rb').read()
ncmds = struct.unpack('<I', f[16:20])[0]; o = 32; segs = []
for _ in range(ncmds):
    cmd, sz = struct.unpack('<II', f[o:o+8])
    if cmd == 0x19:
        vm, vs, fo, fs = struct.unpack('<QQQQ', f[o+24:o+56]); segs.append((vm, fo, fs))
    o += sz
def off(a):
    for vm, fo, fs in segs:
        if vm <= a < vm + fs: return fo + a - vm
    raise ValueError(hex(a))
def d(a): return struct.unpack('<d', f[off(a):off(a)+8])[0]
def q(a): return (d(a), d(a + 8))
# Stack slots written by the default branch (x19 + offset -> two doubles)
stack = {
    0x160: q(0x103793a30), 0x150: q(0x103793a40), 0x140: q(0x103793a50), 0x130: q(0x10369ce20),
    0x120: q(0x103793a60), 0x110: q(0x103793a70), 0x100: q(0x103793a80), 0xf0: q(0x103793a90),
    0xe0: q(0x103793aa0), 0xd0: q(0x103793ab0), 0xc0: q(0x103793ac0), 0xb0: q(0x103793ad0),
    0xa0: q(0x103793ae0), 0x80: (103.5, 103.5), 0x90: q(0x103793af0),   # dup.2d of 0x4059e00000000000
    0x70: (2.0, 2.0), 0x50: (1.5, 1.5), 0x60: q(0x103793b00), 0x30: (0.5, 0.5), 0x40: q(0x103793b10),
    0x10: (1.0, 1.0), 0x20: (101.0, 101.0),                             # dup.2d of 0x4059400000000000
    0x00: q(0x103793b20),
}
# Copy order 0x101d35f98..0x101d36068: Configuration slot k (16 bytes) <- stack offset
LAYOUT = [0x00, 0x20, 0x40, 0x60, 0x80, 0x90, 0x10, 0xa0, 0xb0, 0xc0, 0xd0, 0xe0, 0xf0, 0x100, 0x10,
          0x30, 0x110, 0x50, 0x120, 0x130, 0x70, 0x10, 0x140, 0x150, 0x160]
vals = []
for s in LAYOUT: vals += list(stack[s])
vals.append(3.0)  # fmov d8, #3.0 stored at Configuration+0x190
ARCH = ['searchAutocomplete', 'tab', 'list', 'project', 'navigateWhatYouTyped', 'searchWhatYouTyped', 'askGPTWhatYouTyped',
        'document', 'easel', 'typeTravel', 'topDomains', 'scopedSearch', 'please', 'instantLinks', 'memoryStore', 'askAssistant',
        'assistantHistory', 'chromiumSearchWhatYouTyped', 'chromiumSearchSuggestion', 'chromiumSearchHistory', 'chromiumHistory',
        'chromiumNavigateWhatYouTyped', 'chromiumNavigateSuggestion', 'chromiumSearchOtherEngine', 'chromiumSearchCalculatorAnswer']
SECTIONS = [('archetype', ARCH),
            ('match', ['urlMatchScore', 'urlMatchPosition', 'urlMatchPercentage', 'titleMatchScore', 'titleMatchPosition',
                       'titleMatchPercentage', 'hotWordsMatchScore', 'hotWordsMatchPosition', 'hotWordsMatchPercentage', 'fuzzySearchConfidence']),
            ('importance', ['frequencyEver', 'typedCountEver', 'mostVisitedRank', 'siteEngagementScore', 'globalSiteRank', 'typeTravelCandidateBump']),
            ('recency', ['lastNavigated']), ('chromium', ['chromiumRank', 'chromiumRelevanceScore']), ('save', ['level'])]
it = iter(vals); conf = {}
for name, items in SECTIONS:
    conf[name] = {'weight': next(it), 'items': {k: next(it) for k in items}}
assert next(it, None) is None, 'layout does not use all 51 doubles'
BOOSTS = ['exactBaseDomain', 'exactURL', 'exactHotWord', 'baseDomain', 'autocompleteDefault', 'autocompleteSearchOnly',
          'chromiumSpecialSearchFunction', 'customTitlePrefix', 'veryRecentTabOrDocumentBoost', 'topApp', 'recentlyUseTypeTravel',
          'typeTravelPrefixForLongQuery', 'unboxingPromotedAction', 'highFuzzySearchConfidence']
conf['boosts'] = [{'boost': b, 'weight': d(0x10378e130 + 8 * i), 'score': d(0x10378e0c0 + 8 * i)} for i, b in enumerate(BOOSTS)]
FEATURES = ['archetype', 'urlMatchScore', 'urlMatchPosition', 'urlMatchPercentage', 'titleMatchScore', 'titleMatchPosition',
            'titleMatchPercentage', 'hotWordsMatchScore', 'hotWordsMatchPosition', 'hotWordsMatchPercentage', 'fuzzySearchConfidence',
            'lastNavigated', 'frequencyEver', 'typedCountEver', 'mostVisitedRank', 'siteEngagementScore', 'globalSiteRank',
            'typeTravelCandidateBump', 'chromiumRank', 'chromiumRelevanceScore', 'saveLevel']
lower = lambda i: i > 19 or bool((0x54924 >> i) & 1)
features = [{'feature': n, 'valueWhenMissing': d(0x10378e6b0 + 8 * i), 'lowerIsBetter': lower(i)} for i, n in enumerate(FEATURES)]
print(json.dumps({'source': 'Arc 1.170.0 (89123) arm64', 'defaultConfiguration': conf, 'features': features}, indent=2))
