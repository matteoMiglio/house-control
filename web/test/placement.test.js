import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { normalize } from '../src/config.js';
import { coverage, entrances } from '../src/coverage.js';
import { EXT_T } from '../src/three/house.js';
import { suggestCameras } from '../src/placement.js';

function plan(cameras = []) {
  return normalize({
    rooms: [{ id: 'r', name: 'Room', rect: [0, 0, 6, 4] }],
    openings: [{ type: 'door', from: [2.5, 4], to: [3.5, 4] }],
    site: { boundary: [[-6, -6], [12, -6], [12, 10], [-6, 10]] },
    cameras,
  });
}

const difference = (a, b) => Math.abs(((a - b) % 360 + 540) % 360 - 180);

test('one camera identifies the exterior door from its wall', () => {
  const config = plan();
  const result = suggestCameras(config, { count: 1 });
  assert.equal(result.cameras.length, 1);
  assert.equal(result.before.ways[0].level, 0);
  assert.equal(result.after.ways[0].level, 4);
  const [cam] = result.cameras;
  assert.equal(cam.pos[1], 4 + EXT_T / 2 + 0.08);
  assert.ok(cam.pos[0] >= 0.3 && cam.pos[0] <= 5.7);
  assert.equal(cam.y, config.wallHeight - 0.15);
  assert.match(cam.where, /south/);
  assert.equal('id' in cam, false);
  assert.equal(result.after.ways[0].camera, cam.name);
  assert.deepEqual(entrances({ ...config, cameras: [{ ...cam, id: cam.name }] }), result.after.ways);
});

test('two cameras see more of the plot than one', () => {
  const one = suggestCameras(plan(), { count: 1 });
  const two = suggestCameras(plan(), { count: 2 });
  assert.equal(two.cameras.length, 2);
  assert.ok(two.after.seenShare > one.after.seenShare);
  assert.ok(Math.abs(two.after.byLevelShare.reduce((a, b) => a + b, 0) - two.after.seenShare) < 1e-12);
});

test('kept cameras stay fixed and additional cameras avoid the same spot and aim', () => {
  const existing = { id: 'kept', pos: [3, 4.18], y: 2.45, rot: 0, tilt: 25, fov: 104, range: 12 };
  const config = plan([existing]);
  const snapshot = JSON.stringify(config);
  const result = suggestCameras(config, { count: 3 });
  assert.equal(JSON.stringify(config), snapshot);
  const cameras = [...config.cameras];
  for (const cam of result.cameras) {
    assert.ok(cameras.every((c) => Math.hypot(cam.pos[0] - c.pos[0], cam.pos[1] - c.pos[1]) >= 1.5
      || difference(cam.rot, c.rot) >= 50));
    cameras.push(cam);
  }
  assert.ok(result.after.seenShare > result.before.seenShare);
  assert.equal(suggestCameras(config, { count: 1, keep: [] }).before.seenShare, 0);
});

test('suggestions are deterministic and report what the coverage panel shows', () => {
  const config = plan();
  const options = { count: 2, cell: 0.5, camera: { fov: 90, resolution: [1920, 1080], range: 10 } };
  const first = suggestCameras(config, options);
  assert.deepEqual(suggestCameras(config, options), first);
  // The search may use a coarser grid; the numbers shown are measured on the panel's own.
  const map = coverage(config, { cameras: first.cameras });
  assert.equal(first.after.seenShare, map.stats.seen / map.stats.plot);
  assert.deepEqual(first.after.byLevelShare, map.stats.byLevel.map((v) => v / map.stats.plot));
  for (const cam of first.cameras) {
    assert.equal(cam.fov, 90);
    assert.deepEqual(cam.resolution, [1920, 1080]);
    assert.equal(cam.range, 10);
  }
});

test('the demo gains coverage, reports the gate outcome, and finishes promptly', (t) => {
  const config = normalize(JSON.parse(readFileSync(new URL('../public/plans/home.json', import.meta.url))));
  const start = performance.now();
  const result = suggestCameras(config, { count: 3 });
  const elapsed = performance.now() - start;
  const before = result.before.ways.find((w) => w.kind === 'gate');
  const after = result.after.ways.find((w) => w.kind === 'gate');
  assert.equal(result.cameras.length, 3);
  assert.ok(result.after.seenShare > result.before.seenShare);
  assert.ok(elapsed < 8000, `${elapsed.toFixed(1)} ms`);
  assert.ok(after.level > before.level, `gate level ${before.level} → ${after.level}`);
  t.diagnostic(`Demo placement: ${elapsed.toFixed(1)} ms; ${JSON.stringify(result)}`);
});

test('nothing worth adding, nothing suggested', () => {
  // A tiny house on a huge plot, cameras with a 1 m range: no spot sees any of the plot.
  const config = normalize({
    rooms: [{ id: 'r', rect: [0, 0, 6, 4] }],
    site: { boundary: [[-1000, -1000], [1000, -1000], [1000, 1000], [-1000, 1000]] },
  });
  const r = suggestCameras(config, { count: 2, camera: { fov: 20, resolution: [640, 360], range: 0.2 } });
  assert.equal(r.cameras.length, 0);
});

test('something far off on the plan does not blow up the work', () => {
  const config = normalize({
    rooms: [{ id: 'r', rect: [0, 0, 6, 4] }],
    cameras: [{ id: 'far', pos: [10000, 10000] }],
  });
  const t = Date.now();
  suggestCameras(config, { count: 1 });
  assert.ok(Date.now() - t < 5000, `took ${Date.now() - t} ms`);
});
