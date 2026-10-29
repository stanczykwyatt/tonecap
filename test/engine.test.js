// The engine's tests: `node --test`. No dependencies.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  DEFAULT, PRESETS, FIELDS, KEYS, WIDTHS, normalize, encode, decode, designHash, pressSeed,
  render, renderRaw, designGain, duration, keyFor, panFor, nearestWidth, encodeWav, renderTake,
} from "../docs/engine/tonecap.js";
import { spectrum } from "../scripts/analyze.mjs";

const fs = 48000;
const preset = (name) => PRESETS.find((p) => p.name === name).design;
const energy = (s) => s.reduce((sum, x) => sum + x * x, 0);
const peakIndex = (s) => s.reduce((best, x, i) => (Math.abs(x) > Math.abs(s[best]) ? i : best), 0);

test("the same press always renders the same samples", () => {
  const a = render(DEFAULT, 1, 3, false, fs);
  const b = render(DEFAULT, 1, 3, false, fs);
  assert.deepEqual(a, b);
});

test("each variant of a press is a little different", () => {
  const variants = [0, 1, 2, 3].map((v) => render(DEFAULT, 1, v, false, fs));
  for (let i = 1; i < variants.length; i++) assert.notDeepEqual(variants[0], variants[i]);
  // ...but only a little: the same loudness within about 20%.
  const levels = variants.map(energy);
  assert.ok(Math.max(...levels) / Math.min(...levels) < 1.5);
});

test("renders are the right length, finite and within full scale", () => {
  for (const { design } of PRESETS) {
    for (const width of WIDTHS) {
      for (const up of [false, true]) {
        const s = render(design, width, 1, up, 44100);
        assert.equal(s.length, Math.round(duration(width, up) * 44100));
        assert.ok(s.every((x) => Number.isFinite(x) && Math.abs(x) <= 1));
        assert.ok(energy(s) > 0);
        assert.ok(s[s.length - 1] === 0, "ends in silence");
      }
    }
  }
});

test("a letter key peaks at the set level for every preset", () => {
  for (const { design } of PRESETS) {
    const s = render(design, 1, 0, false, fs);
    assert.ok(Math.abs(Math.abs(s[peakIndex(s)]) - 0.7) < 1e-6);
  }
});

test("a release is quieter than a press", () => {
  for (const { design } of PRESETS) {
    assert.ok(energy(render(design, 1, 0, true, fs)) < energy(render(design, 1, 0, false, fs)));
  }
});

test("thocky builds are deeper than clacky ones", () => {
  const thock = spectrum(render(preset("Deep thock"), 1, 0, false, fs), fs);
  const clack = spectrum(render(preset("Bright clack"), 1, 0, false, fs), fs);
  assert.ok(thock.centroid < 1400, `thock centroid ${thock.centroid}`);
  assert.ok(clack.centroid > 1900, `clack centroid ${clack.centroid}`);
  assert.ok(thock.low > 2 * clack.low);
});

test("a clicky switch adds a bright click before it bottoms out", () => {
  const clicky = { ...DEFAULT, switch: "clicky" };
  const linear = { ...DEFAULT, switch: "linear" };
  const c = render(clicky, 1, 0, false, fs);
  const l = render(linear, 1, 0, false, fs);
  assert.ok(spectrum(c, fs).high > 2 * spectrum(l, fs).high);
  assert.ok(peakIndex(c) < peakIndex(l), "the click comes first");
});

test("each setting changes the sound in the direction it says", () => {
  const centroid = (design, width = 1) => spectrum(render(design, width, 0, false, fs), fs).centroid;
  const base = { ...DEFAULT, foam: 0 };
  assert.ok(centroid({ ...base, keycap: "pbt", thickness: 100 }) < centroid({ ...base, keycap: "abs", thickness: 0 }), "thick PBT is deeper than thin ABS");
  assert.ok(centroid({ ...base, profile: "tall" }) < centroid({ ...base, profile: "low" }), "tall caps are deeper");
  assert.ok(centroid({ ...base, bottomOut: 0 }) < centroid({ ...base, bottomOut: 100 }), "soft bottom-out is duller");
  assert.ok(centroid(base, 6.25) < centroid(base, 1), "the spacebar is deeper");
  assert.ok(centroid({ ...base, plate: "polycarbonate" }) < centroid({ ...base, plate: "aluminum" }), "polycarbonate is softer than aluminum");
  // Lube quiets the scratch and the spring.
  const raw = (design) => energy(renderRaw(design, 1, 0, false, fs));
  assert.ok(raw({ ...base, lube: 100 }) < raw({ ...base, lube: 0 }));
});

test("foam shortens the ring", () => {
  const tail = (design) => {
    const s = render(design, 1, 0, false, fs);
    return energy(s.slice(Math.round(0.04 * fs)));
  };
  assert.ok(tail({ ...DEFAULT, case: "aluminum", foam: 100 }) < tail({ ...DEFAULT, case: "aluminum", foam: 0 }) / 2);
});

test("tuned stabilizers rattle less", () => {
  const high = (design) => spectrum(render(design, 6.25, 0, false, fs), fs).centroid;
  assert.ok(high({ ...DEFAULT, stabilizers: 100 }) < high({ ...DEFAULT, stabilizers: 0 }));
  // On a letter key they make no difference beyond the design's own random variation.
  const letter = (stabilizers) => spectrum(render({ ...DEFAULT, stabilizers }, 1, 0, false, fs), fs).centroid;
  assert.ok(Math.abs(letter(0) - letter(100)) / letter(100) < 0.1);
});

test("the level stays put across sample rates", () => {
  for (const rate of [22050, 44100, 48000, 96000]) {
    assert.ok(designGain(DEFAULT, rate) > 0);
    const s = render(DEFAULT, 1, 0, false, rate);
    assert.ok(Math.abs(Math.abs(s[peakIndex(s)]) - 0.7) < 1e-6);
  }
});

test("share codes round-trip every preset", () => {
  for (const { design } of PRESETS) {
    const code = encode(design);
    assert.match(code, /^[A-Za-z0-9_-]{19}$/);
    assert.deepEqual(decode(code), normalize(design));
  }
});

test("share codes are read from whole links", () => {
  const code = encode(preset("Crisp click"));
  for (const link of [`https://stanczykwyatt.github.io/tonecap/#s=${code}`, `https://x.test/?s=${code}&n=Mine`, `#s=${code}`, `  ${code}\n`]) {
    assert.deepEqual(decode(link), preset("Crisp click"));
  }
});

test("damaged or foreign codes are refused, not guessed", () => {
  const code = encode(DEFAULT);
  const flipped = code.slice(0, 5) + (code[5] === "A" ? "B" : "A") + code.slice(6);
  for (const bad of ["", "abc", flipped, code.slice(0, -1), code + "AA", "!!!!", null, 42, "s=" + "A".repeat(19), "A".repeat(65)]) {
    assert.equal(decode(bad), null, String(bad));
  }
  // A slider out of range or an option that doesn't exist, even with a good check byte.
  const forge = (bytes) => {
    let sum = 0; for (const b of bytes) sum = (sum + b) & 255;
    const all = [...bytes, sum ^ 0xa5];
    return Buffer.from(all).toString("base64url");
  };
  const good = [1, 0, 50, 60, 60, 45, 0, 0, 40, 0, 60, 1, 70];
  assert.deepEqual(decode(forge(good)), DEFAULT);
  assert.equal(decode(forge(good.map((b, i) => (i === 2 ? 101 : b)))), null);
  assert.equal(decode(forge(good.map((b, i) => (i === 1 ? 3 : b)))), null);
  assert.equal(decode(forge([2, ...good.slice(1)])), null, "a newer version");
});

test("each design has exactly one code, and links are read the same way everywhere", () => {
  const code = encode(DEFAULT);
  // The last character carries two spare bits; any other value for them is refused.
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
  const last = alphabet.indexOf(code.at(-1));
  for (const spare of [1, 2, 3]) assert.equal(decode(code.slice(0, -1) + alphabet[last ^ spare]), null);
  assert.deepEqual(decode(`https://x.test/?s=broken#s=${code}`), DEFAULT, "the code after the # wins");
  assert.deepEqual(decode(`\uFEFF${code}`), DEFAULT);
});

test("normalize fills gaps and clamps", () => {
  assert.deepEqual(normalize({}), DEFAULT);
  assert.deepEqual(normalize(null), DEFAULT);
  const d = normalize({ spring: 140, lube: -3, foam: "12.6", plate: "steel", switch: "clicky" });
  assert.equal(d.spring, 100);
  assert.equal(d.lube, 0);
  assert.equal(d.foam, 13);
  assert.equal(d.plate, DEFAULT.plate);
  assert.equal(d.switch, "clicky");
  assert.equal(Object.keys(d).length, FIELDS.length);
  const blanks = normalize({ spring: null, lube: "", foam: true, thickness: "  " });
  assert.equal(blanks.spring, DEFAULT.spring);
  assert.equal(blanks.lube, DEFAULT.lube);
  assert.equal(blanks.foam, DEFAULT.foam);
  assert.equal(blanks.thickness, DEFAULT.thickness);
});

test("seeds differ by key size, variant and direction", () => {
  const seeds = new Set();
  for (const width of WIDTHS) for (let v = 0; v < 8; v++) for (const up of [false, true]) seeds.add(pressSeed(DEFAULT, width, v, up));
  assert.equal(seeds.size, WIDTHS.length * 16);
});

test("the key table is complete and sane", () => {
  const codes = new Set(KEYS.map((k) => k[0]));
  const keyCodes = new Set(KEYS.map((k) => k[1]));
  assert.equal(codes.size, KEYS.length);
  assert.equal(keyCodes.size, KEYS.length);
  for (const code of ["KeyA", "Space", "Enter", "ShiftLeft", "Backspace", "ArrowLeft"]) assert.ok(codes.has(code));
  assert.equal(keyFor("Space").width, 6.25);
  assert.ok(keyFor("KeyQ").pan < 0 && keyFor("KeyP").pan > keyFor("KeyQ").pan && keyFor("ArrowRight").pan > 0);
  assert.deepEqual(keyFor("SomethingNew"), { width: 1, pan: 0 });
  assert.ok(Math.abs(panFor(-10)) <= 0.7 && Math.abs(panFor(100)) <= 0.7);
  assert.equal(nearestWidth(2.1), 2);
  assert.equal(nearestWidth(1.3), 1.25);
});

test("WAV files have a correct header and samples", () => {
  const left = new Float32Array([0, 0.5, -0.5, 1, -1, 2]);
  const bytes = encodeWav([left, left], 48000);
  const view = new DataView(bytes.buffer);
  assert.equal(String.fromCharCode(...bytes.slice(0, 4)), "RIFF");
  assert.equal(String.fromCharCode(...bytes.slice(8, 16)), "WAVEfmt ");
  assert.equal(view.getUint16(22, true), 2);
  assert.equal(view.getUint32(24, true), 48000);
  assert.equal(view.getUint32(40, true), 6 * 2 * 2);
  assert.equal(bytes.length, 44 + 24);
  assert.equal(view.getInt16(44 + 4, true), 16384);
  assert.equal(view.getInt16(44 + 20, true), 32767, "clipped, not wrapped");
});

test("a typed take places each key on the timeline, panned", () => {
  const [left, right] = renderTake(DEFAULT, [["KeyQ", 0.05, 0.12], ["KeyP", 0.3, 0.37]], 24000);
  assert.equal(left.length, right.length);
  const window = (s, from, to) => energy(s.slice(Math.round(from * 24000), Math.round(to * 24000)));
  assert.ok(window(left, 0.05, 0.12) > window(right, 0.05, 0.12), "Q is on the left");
  assert.ok(window(right, 0.3, 0.37) > window(left, 0.3, 0.37), "P is on the right");
  assert.ok(window(left, 0.25, 0.3) < 1e-9, "silence between them");
});
