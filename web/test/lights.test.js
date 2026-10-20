// A lamp switching off or on fades its light and its glowing bulb together, with no jump.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { LightUnit } from '../src/three/lights.js';

function fade(unit, on) {
  unit.apply({ on, brightness: 0.8, temp: 3000, color: null });
  const glow = [];
  for (let i = 0; i < 240 && unit.update(1 / 60); i++) glow.push(unit.glow[0].emissiveIntensity);
  return glow;
}

const biggestStep = (series) => Math.max(...series.slice(1).map((v, i) => Math.abs(v - series[i])));

for (const type of ['ceiling', 'pendant', 'floor', 'table', 'strip']) {
  test(`a ${type} lamp's glow fades out and back in without a jump`, () => {
    const unit = new LightUnit({ id: 'lamp', type, pos: [0, 0], capabilities: ['brightness'], length: 1 }, 2.6);
    unit.apply({ on: true, brightness: 0.8, temp: 3000, color: null }, { instant: true });
    const off = fade(unit, false);
    assert.equal(off.at(-1), 0);
    assert.ok(biggestStep(off) < 0.2, `switching off jumps by ${biggestStep(off).toFixed(2)}`);
    const on = fade(unit, true);
    assert.ok(biggestStep(on) < 0.4, `switching on jumps by ${biggestStep(on).toFixed(2)}`);
  });
}
