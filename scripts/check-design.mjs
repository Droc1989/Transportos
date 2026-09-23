#!/usr/bin/env node
// Verifică faptul că tokenurile de design aprobate (docs/design/README.md) nu au fost schimbate.
// Rulat în CI. Pentru o schimbare aprobată de proprietar: se modifică ÎMPREUNĂ acest fișier,
// globals.css și docs/design/README.md, în același PR, cu aprobarea scrisă menționată.
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const LOCKED = {
  '--sign-blue': '#0b4ea2',
  '--sign-blue-dark': '#083a7a',
  '--accent': '#ffc726',
  '--ink': '#0e1a2b',
  '--muted': '#46546a',
  '--line': '#c9d1db',
  '--ground': '#eef1f4',
  '--danger': '#b42318',
  '--success': '#0a7a47',
  '--font': "'Overpass'",
  '--font-mono': "'Overpass Mono'",
};

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const css = readFileSync(join(root, 'apps', 'web', 'app', 'globals.css'), 'utf8');
const block = css.match(/:root\s*\{([\s\S]*?)\}/)?.[1] ?? '';
let failed = false;
for (const [token, expected] of Object.entries(LOCKED)) {
  const value = block.match(new RegExp(`${token}:\\s*([^;]+);`))?.[1]?.trim() ?? '';
  if (!value.toLowerCase().startsWith(expected.toLowerCase())) {
    console.error(`✗ tokenul ${token} e „${value}”, designul aprobat cere „${expected}”`);
    failed = true;
  }
}
for (let i = 1; i <= 12; i += 1) {
  // ecranele aprobate trebuie să rămână în repository
  const prefix = String(i).padStart(2, '0');
  try {
    const list = readFileSync(join(root, 'docs', 'design', 'README.md'), 'utf8');
    if (!list.includes(`${prefix}-`)) throw new Error();
  } catch {
    console.error(`✗ ecranul ${prefix} lipsește din docs/design/README.md`);
    failed = true;
  }
}
if (failed) {
  console.error('Designul e fixat (docs/design/README.md). Schimbările cer aprobarea proprietarului.');
  process.exit(1);
}
console.log(`✔ ${Object.keys(LOCKED).length} tokenuri de design neschimbate`);
