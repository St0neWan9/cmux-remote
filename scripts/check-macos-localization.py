#!/usr/bin/env python3
"""Verify Mac Companion/extension localization separately from the iPhone catalog."""
from pathlib import Path
import re
import plistlib

root = Path(__file__).resolve().parents[1]
pattern = re.compile(r'^"([^\"]+)"\s*=', re.M)
keys = {locale: set(pattern.findall((root / 'mac/Resources' / f'{locale}.lproj/Localizable.strings').read_text())) for locale in ('en', 'zh-Hans')}
assert keys['en'] == keys['zh-Hans'], f"Mac locale mismatch: {keys['en'] ^ keys['zh-Hans']}"
used = set()
for source in (root / 'mac').rglob('*.swift'):
    used.update(re.findall(r'String\(localized:\s*"([^\"]+)"', source.read_text()))
assert used <= keys['en'], f"Missing Mac localization: {used - keys['en']}"
for source in (root / 'mac').rglob('*.plist'):
    plistlib.loads(source.read_bytes())
print(f"Mac localization: {len(keys['en'])} matching English/Simplified Chinese keys")
