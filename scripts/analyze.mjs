// Prints how each preset's sounds are spread across the spectrum, and optionally writes WAVs.
//
//   node scripts/analyze.mjs [folder-for-wavs]
import { writeFileSync } from "node:fs";
import { PRESETS, render, encodeWav } from "../docs/engine/tonecap.js";

const fs = 48000;
const out = process.argv[2];

/** Energy-weighted mean frequency, and the share of energy below 1 kHz and above 4 kHz. */
export function spectrum(samples, rate) {
  const n = 8192;
  const re = new Float64Array(n), im = new Float64Array(n);
  for (let i = 0; i < Math.min(n, samples.length); i++) re[i] = samples[i];
  // Plain radix-2 FFT.
  for (let i = 1, j = 0; i < n; i++) {
    let bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) { [re[i], re[j]] = [re[j], re[i]]; [im[i], im[j]] = [im[j], im[i]]; }
  }
  for (let len = 2; len <= n; len <<= 1) {
    const a = (-2 * Math.PI) / len;
    for (let i = 0; i < n; i += len) for (let k = 0; k < len / 2; k++) {
      const c = Math.cos(a * k), s = Math.sin(a * k);
      const xr = re[i + k + len / 2] * c - im[i + k + len / 2] * s, xi = re[i + k + len / 2] * s + im[i + k + len / 2] * c;
      re[i + k + len / 2] = re[i + k] - xr; im[i + k + len / 2] = im[i + k] - xi; re[i + k] += xr; im[i + k] += xi;
    }
  }
  let total = 0, weighted = 0, low = 0, high = 0;
  for (let k = 1; k < n / 2; k++) {
    const f = (k * rate) / n, p = re[k] ** 2 + im[k] ** 2;
    total += p; weighted += p * f;
    if (f < 1000) low += p; if (f > 4000) high += p;
  }
  return { centroid: weighted / total, low: low / total, high: high / total };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  for (const { name, design } of PRESETS) {
    for (const [label, width, up] of [["key", 1, false], ["up", 1, true], ["space", 6.25, false]]) {
      const s = render(design, width, 0, up, fs);
      const sp = spectrum(s, fs);
      let peakAt = 0; for (let i = 0; i < s.length; i++) if (Math.abs(s[i]) > Math.abs(s[peakAt])) peakAt = i;
      let rms = 0; for (const x of s) rms += x * x; rms = Math.sqrt(rms / s.length);
      console.log(`${name.padEnd(15)} ${label.padEnd(5)} centroid ${sp.centroid.toFixed(0).padStart(5)} Hz  <1k ${(sp.low * 100).toFixed(0).padStart(3)}%  >4k ${(sp.high * 100).toFixed(0).padStart(3)}%  peak ${(peakAt / fs * 1000).toFixed(1)} ms  rms ${rms.toFixed(3)}`);
      if (out) writeFileSync(`${out}/${name.replace(/ /g, "-")}-${label}.wav`, encodeWav([s], fs));
    }
  }
}
