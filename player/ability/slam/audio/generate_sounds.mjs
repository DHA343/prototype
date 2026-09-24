import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

// The supplied charge recording sets the sound direction: airy, rough and
// swelling. These cues use new noise textures so its background music is absent.
const DIRECTORY = path.dirname(fileURLToPath(import.meta.url));
const SAMPLE_RATE = 48000;
const CHANNELS = 2;
const TAU = Math.PI * 2;

function noise(seed) {
  let state = seed >>> 0;
  return () => {
    state ^= state << 13;
    state ^= state >>> 17;
    state ^= state << 5;
    return (state >>> 0) / 2147483648 - 1;
  };
}

function lowpass(cutoff) {
  const alpha = 1 - Math.exp(-TAU * cutoff / SAMPLE_RATE);
  let value = 0;
  return (sample) => {
    value += alpha * (sample - value);
    return value;
  };
}

function resonantNoise(center, width) {
  const omega = TAU * center / SAMPLE_RATE;
  const alpha = Math.sin(omega) / (2 * width);
  const divisor = 1 + alpha;
  const b0 = alpha / divisor;
  const b2 = -alpha / divisor;
  const a1 = -2 * Math.cos(omega) / divisor;
  const a2 = (1 - alpha) / divisor;
  let z1 = 0;
  let z2 = 0;
  return (sample) => {
    const output = b0 * sample + z1;
    z1 = z2 - a1 * output;
    z2 = b2 * sample - a2 * output;
    return output;
  };
}

function makeAudio(seconds, voices) {
  const frames = Math.round(seconds * SAMPLE_RATE);
  const samples = new Float32Array(frames * CHANNELS);
  for (let frame = 0; frame < frames; frame++) {
    const time = frame / SAMPLE_RATE;
    for (let channel = 0; channel < CHANNELS; channel++) {
      samples[frame * CHANNELS + channel] = voices[channel](time);
    }
  }
  return samples;
}

function normalize(samples, peak) {
  let maximum = 0;
  for (const sample of samples) maximum = Math.max(maximum, Math.abs(sample));
  const gain = peak / Math.max(maximum, 0.00001);
  for (let i = 0; i < samples.length; i++) samples[i] *= gain;
  return samples;
}

function fadeEnds(samples, attackMs, releaseMs) {
  const frames = samples.length / CHANNELS;
  const attack = Math.round(attackMs * SAMPLE_RATE / 1000);
  const release = Math.round(releaseMs * SAMPLE_RATE / 1000);
  for (let frame = 0; frame < frames; frame++) {
    const gain = Math.max(0, Math.min(1,
      frame / Math.max(attack, 1),
      (frames - 1 - frame) / Math.max(release, 1)));
    for (let channel = 0; channel < CHANNELS; channel++) {
      samples[frame * CHANNELS + channel] *= gain;
    }
  }
  return samples;
}

function crossfadeLoop(samples, overlapMs) {
  const overlap = Math.round(overlapMs * SAMPLE_RATE / 1000);
  const sourceFrames = samples.length / CHANNELS;
  const loopFrames = sourceFrames - overlap;
  const result = new Float32Array(loopFrames * CHANNELS);
  result.set(samples.subarray(0, result.length));
  for (let frame = 0; frame < overlap; frame++) {
    const blend = frame / overlap;
    for (let channel = 0; channel < CHANNELS; channel++) {
      const index = frame * CHANNELS + channel;
      const tail = samples[(loopFrames + frame) * CHANNELS + channel];
      result[index] = tail * (1 - blend) + result[index] * blend;
    }
  }
  return result;
}

function roomTail(samples, taps) {
  const dry = samples.slice();
  const frames = samples.length / CHANNELS;
  for (const [delayMs, gain] of taps) {
    const delay = Math.round(delayMs * SAMPLE_RATE / 1000);
    for (let frame = delay; frame < frames; frame++) {
      for (let channel = 0; channel < CHANNELS; channel++) {
        samples[frame * CHANNELS + channel] +=
          dry[(frame - delay) * CHANNELS + channel] * gain;
      }
    }
  }
  return samples;
}

function writeWav(filename, samples) {
  const dataSize = samples.length * 2;
  const wav = Buffer.alloc(44 + dataSize);
  wav.write("RIFF", 0);
  wav.writeUInt32LE(36 + dataSize, 4);
  wav.write("WAVEfmt ", 8);
  wav.writeUInt32LE(16, 16);
  wav.writeUInt16LE(1, 20);
  wav.writeUInt16LE(CHANNELS, 22);
  wav.writeUInt32LE(SAMPLE_RATE, 24);
  wav.writeUInt32LE(SAMPLE_RATE * CHANNELS * 2, 28);
  wav.writeUInt16LE(CHANNELS * 2, 32);
  wav.writeUInt16LE(16, 34);
  wav.write("data", 36);
  wav.writeUInt32LE(dataSize, 40);
  for (let i = 0; i < samples.length; i++) {
    wav.writeInt16LE(Math.round(Math.max(-1, Math.min(1, samples[i])) * 32767), 44 + i * 2);
  }
  fs.writeFileSync(path.join(DIRECTORY, filename), wav);
}

function chargeVoice(seed, phase) {
  const next = noise(seed);
  const low = lowpass(360);
  const lowFloor = lowpass(65);
  const mid = lowpass(3100);
  const midFloor = lowpass(800);
  const air = lowpass(8700);
  const airFloor = lowpass(3300);
  const whine = resonantNoise(1850 + phase * 300, 4.5);
  return (time) => {
    const raw = next();
    const breath = (low(raw) - lowFloor(raw)) * 0.24
      + (mid(raw) - midFloor(raw)) * 0.72
      + (air(raw) - airFloor(raw)) * 0.23
      + whine(raw) * 0.32;
    const swell = 0.76 + 0.16 * Math.sin(TAU * time / 1.28 + phase)
      + 0.06 * Math.sin(TAU * time * 3.1 + phase);
    return breath * swell;
  };
}

const charge = makeAudio(1.65, [
  chargeVoice(0x218f35, 0.0),
  chargeVoice(0x83b4a1, 0.1),
]);
writeWav("charge_loop.wav", normalize(crossfadeLoop(charge, 70), 0.30));

function stageVoice(seed) {
  const next = noise(seed);
  const mid = lowpass(7000);
  const floor = lowpass(550);
  const low = lowpass(450);
  return (time) => {
    const raw = next();
    const envelope = (1 - Math.exp(-time * 500)) * Math.exp(-time * 12);
    const burst = (mid(raw) - floor(raw)) * 0.75 + low(raw) * 0.18;
    return burst * envelope;
  };
}

const stage = makeAudio(0.27, [
  stageVoice(0x40bc17),
  stageVoice(0x62d18e),
]);
writeWav("charge_stage.wav", normalize(fadeEnds(stage, 2, 28), 0.48));

function slamVoice(seed) {
  const next = noise(seed);
  const crackFloor = lowpass(950);
  const mid = lowpass(4200);
  const midFloor = lowpass(240);
  const low = lowpass(250);
  const sub = lowpass(85);
  return (time) => {
    const raw = next();
    const crack = (raw - crackFloor(raw)) * 0.24 * Math.exp(-time * 90);
    const rough = (mid(raw) - midFloor(raw)) * 0.55 * Math.exp(-time * 17);
    const thump = low(raw) * 0.95 * Math.exp(-time * 10);
    const weight = sub(raw) * 1.1 * Math.exp(-time * 8);
    return crack + rough + thump + weight;
  };
}

const slam = makeAudio(0.57, [
  slamVoice(0x51f42c),
  slamVoice(0x2ac713),
]);
writeWav("slam.wav", normalize(
  fadeEnds(roomTail(slam, [[33, 0.23], [69, 0.15], [117, 0.08]]), 1, 65), 0.65));

function hitVoice(seed) {
  const next = noise(seed);
  const crackFloor = lowpass(1150);
  const mid = lowpass(5300);
  const midFloor = lowpass(380);
  const low = lowpass(300);
  return (time) => {
    const raw = next();
    const snap = (raw - crackFloor(raw)) * 0.21 * Math.exp(-time * 105);
    const crunch = (mid(raw) - midFloor(raw)) * 0.55 * Math.exp(-time * 32);
    const knock = low(raw) * 0.7 * Math.exp(-time * 24);
    return snap + crunch + knock;
  };
}

const hit = makeAudio(0.23, [
  hitVoice(0x9125d4),
  hitVoice(0x341c8f),
]);
writeWav("hit.wav", normalize(fadeEnds(hit, 1, 33), 0.55));
