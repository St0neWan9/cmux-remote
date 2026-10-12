#!/usr/bin/env python3
from pathlib import Path
import re
root = Path(__file__).resolve().parents[1]
pattern = re.compile(r'^"([^"]+)"\s*=', re.M)
english = set(pattern.findall((root/'ios/Resources/en.lproj/Localizable.strings').read_text()))
chinese = set(pattern.findall((root/'ios/Resources/zh-Hans.lproj/Localizable.strings').read_text()))
used = set()
for source in (root/'ios/Sources').glob('*.swift'):
    used.update(re.findall(r'String\(localized:\s*"([^"]+)"', source.read_text()))
assert english == chinese, f'Locale mismatch: {english ^ chinese}'
assert used <= english, f'Missing localization: {used - english}'
print(f'Localization: {len(english)} matching English/Simplified Chinese keys')
