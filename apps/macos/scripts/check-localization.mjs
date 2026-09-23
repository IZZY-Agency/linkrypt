#!/usr/bin/env node
// Fails if any String Catalog key is missing a French or Ukrainian translation,
// or has one in a non-final state. `en` is the source language (the key itself),
// so only fr/uk are required. Run from the repo root:
//   node apps/macos/scripts/check-localization.mjs
import { readFileSync } from 'node:fs';

const path =
  process.argv[2] ??
  'apps/macos/Linkrypt/Linkrypt/Resources/Localizable.xcstrings';

const cat = JSON.parse(readFileSync(path, 'utf8'));
const required = ['fr', 'uk']; // en is implicit (the source key)
const bad = [];

const checkUnit = (lang, key, unit) => {
  if (!unit || !unit.value?.trim()) {
    bad.push(`${lang}: ${JSON.stringify(key)} (missing)`);
    return;
  }
  if (['new', 'needs_review', 'stale'].includes(unit.state)) {
    bad.push(`${lang}: ${JSON.stringify(key)} (${unit.state})`);
  }
};

for (const [key, entry] of Object.entries(cat.strings ?? {})) {
  if (entry.shouldTranslate === false) continue;
  const locs = entry.localizations ?? {};
  for (const lang of required) {
    const loc = locs[lang];
    if (loc?.variations) {
      // plural/device variations: every leaf stringUnit must be complete
      for (const kind of Object.values(loc.variations)) {
        for (const v of Object.values(kind)) checkUnit(lang, key, v.stringUnit);
      }
    } else {
      checkUnit(lang, key, loc?.stringUnit);
    }
  }
}

const total = Object.keys(cat.strings ?? {}).length;
if (bad.length) {
  console.error(`Localization INCOMPLETE — ${bad.length} issue(s):\n` + bad.join('\n'));
  process.exit(1);
}
console.log(`Localization complete: ${total} keys × {fr, uk} all translated.`);
