#!/usr/bin/env python3
"""Give Brk and its CEF helpers the usage descriptions required for approved site requests."""
import plistlib
from pathlib import Path
import sys

app = Path(sys.argv[1])
descriptions = {
    'NSCameraUsageDescription': 'Use your camera only for websites that you approve in Brk.',
    'NSMicrophoneUsageDescription': 'Use your microphone only for websites that you approve in Brk.',
    'NSLocationUsageDescription': 'Share your location only with websites that you approve in Brk.',
    'NSLocationWhenInUseUsageDescription': 'Share your location only with websites that you approve in Brk.',
}
plists = [app/'Contents/Info.plist', *sorted((app/'Contents/Frameworks').glob('*.app/Contents/Info.plist'))]
for path in plists:
    with path.open('rb') as stream:
        value = plistlib.load(stream)
    value.update(descriptions)
    with path.open('wb') as stream:
        plistlib.dump(value, stream)
print('[site-permissions] declared device and location use in', len(plists), 'bundles')
