// Writes the renders, codes and key table the Swift tests compare against, from the JavaScript engine.
//
//   node scripts/make-fixtures.mjs           rewrite Tests/ToneCoreTests/Fixtures/engine.json
//   node scripts/make-fixtures.mjs --check   fail if it's out of date (CI runs this)
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { DEFAULT, PRESETS, KEYS, WIDTHS, encode, designHash, pressSeed, designGain, render, keyFor } from "../docs/engine/tonecap.js";

const path = new URL("../Tests/ToneCoreTests/Fixtures/engine.json", import.meta.url);
const round = (x) => Number(x.toPrecision(7));
// Every fourth sample is kept, which is plenty to catch any difference and keeps the file small.
const STRIDE = 4;

const designs = [{ name: "Default", design: { ...DEFAULT } }, ...PRESETS];
const cases = [];
for (const [index, { name, design }] of designs.entries()) {
  // A spread of key sizes, variants, presses and releases, and both common sample rates.
  const width = WIDTHS[index % WIDTHS.length];
  // Bright and clicky builds also at 48 kHz, where the top keycap and click modes are in range.
  const runs = [[1, 0, false, 16000], [width, index % 8, index % 2 === 1, 22050]];
  if (["Bright clack", "Crisp click", "Hollow plastic"].includes(name)) runs.push([1, 2, false, 48000], [2.25, 5, true, 44100]);
  for (const [w, variant, up, rate] of runs) {
    const samples = render(design, w, variant, up, rate);
    cases.push({ name, width: w, variant, up, sampleRate: rate, gain: round(designGain(design, rate)), length: samples.length, stride: STRIDE, samples: Array.from(samples.filter((_, i) => i % STRIDE === 0), round) });
  }
}

const fixture = {
  note: "Made by scripts/make-fixtures.mjs from docs/engine/tonecap.js. Don't edit by hand.",
  designs: designs.map(({ name, design }) => ({
    name, design, code: encode(design), hash: designHash(design),
    seeds: [[1, 0, false], [2.25, 5, true], [6.25, 7, false]].map(([w, v, up]) => ({ width: w, variant: v, up, seed: pressSeed(design, w, v, up) })),
  })),
  keys: KEYS.map(([code, keyCode, x, width]) => ({ code, keyCode, x, width, pan: round(keyFor(code).pan) })),
  cases,
};
const text = JSON.stringify(fixture) + "\n";

if (process.argv.includes("--check")) {
  let current = "";
  try { current = readFileSync(path, "utf8"); } catch {}
  if (current !== text) {
    console.error("Tests/ToneCoreTests/Fixtures/engine.json is out of date: run node scripts/make-fixtures.mjs");
    process.exit(1);
  }
  console.log("Fixtures are up to date.");
} else {
  mkdirSync(new URL(".", path), { recursive: true });
  writeFileSync(path, text);
  console.log(`Wrote ${cases.length} renders to ${path.pathname}`);
}
