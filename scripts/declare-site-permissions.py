#!/usr/bin/env python3
"""Give Brk and its Chromium helpers the usage descriptions for everything a website can make Chromium ask macOS for.

macOS kills an app outright (TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION) when it touches camera, microphone, Bluetooth,
system audio or speech recognition without the matching key, and Chromium touches some of these on its own: on a
passkey sign-in page (Canva's) it lists paired Bluetooth devices for "use a phone", which killed Brk 0.1.0 (16).
The folder and local network keys do not kill; they replace macOS's empty prompt text with a reason.
"""
import plistlib
from pathlib import Path
import sys

app = Path(sys.argv[1])
location = 'Share your location only with websites that you approve in Brk.'
bluetooth = 'Use Bluetooth only for websites that you approve in Brk, such as signing in with a passkey on your phone.'
descriptions = {
    'NSCameraUsageDescription': 'Use your camera only for websites that you approve in Brk.',
    'NSMicrophoneUsageDescription': 'Use your microphone only for websites that you approve in Brk.',
    'NSAudioCaptureUsageDescription': 'Share your Mac\'s sound only when you share your screen with a website.',
    'NSSpeechRecognitionUsageDescription': 'Turn speech into text only for websites that you approve in Brk.',
    'NSLocationUsageDescription': location,
    'NSLocationWhenInUseUsageDescription': location,
    'NSLocationAlwaysAndWhenInUseUsageDescription': location,
    'NSBluetoothAlwaysUsageDescription': bluetooth,
    'NSBluetoothPeripheralUsageDescription': bluetooth,
    'NSWebBrowserPublicKeyCredentialUsageDescription': 'Sign in to websites with passkeys saved on this Mac.',
    'NSLocalNetworkUsageDescription': 'Open pages and devices on your local network when you visit them in Brk.',
    'NSDesktopFolderUsageDescription': 'Upload files from your Desktop folder and save downloads there when you choose.',
    'NSDocumentsFolderUsageDescription': 'Upload files from your Documents folder and save downloads there when you choose.',
    'NSDownloadsFolderUsageDescription': 'Save downloads to your Downloads folder and upload files from it.',
    'NSRemovableVolumesUsageDescription': 'Upload files from external drives and save downloads there when you choose.',
    'NSNetworkVolumesUsageDescription': 'Upload files from network drives and save downloads there when you choose.',
}
plists = [app/'Contents/Info.plist', *sorted((app/'Contents/Frameworks').rglob('*.app/Contents/Info.plist'))]
for path in plists:
    with path.open('rb') as stream:
        value = plistlib.load(stream)
    value.update(descriptions)
    with path.open('wb') as stream:
        plistlib.dump(value, stream)
print('[site-permissions] declared', len(descriptions), 'usage descriptions in', len(plists), 'bundles')
