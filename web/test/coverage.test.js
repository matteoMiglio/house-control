import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { normalize, treeShape } from '../src/config.js';
import { levelDistances, pixelsPerMetre, cameraLevel, obstacles, coverage, entrances, LEVELS, SOLID } from '../src/coverage.js';

// A 6 × 4 m house with its south-west corner at the origin, a plot around it,
// and whatever cameras and outdoor items a test adds.
function plan({ cameras = [], outdoor = [], openings = [] } = {}) {
  return normalize({
    rooms: [{ id: 'r', rect: [0, 0, 6, 4] }],
    openings,
    site: { boundary: [[-10, -10], [16, -10], [16, 14], [-10, 14]] },
    outdoor,
    cameras,
  });
}

// Looking south from the middle of the south wall, level, 90° wide.
const south = { id: 'c', pos: [3, 4.18], y: 2.5, rot: 0, tilt: 0, fov: 90, range: 30, resolution: [2560, 1440] };

test('pixels per metre and how far each level reaches', () => {
  const cam = plan({ cameras: [south] }).cameras[0];
  // 2560 px over a 90° view: at d metres the picture is 2d wide.
  assert.ok(Math.abs(pixelsPerMetre(cam, 1) - 1280) < 1e-9);
  const [detect, observe, recognise, identify] = levelDistances(cam);
  for (const [d, ppm] of [[identify, 250], [recognise, 125], [observe, 62.5]]) assert.ok(Math.abs(d - 2560 / (2 * ppm)) < 1e-9);
  assert.equal(detect, 30); // 51 m, cut down to its range
});

test('a camera sees what is in front of it, not behind or beside it', () => {
  const config = plan({ cameras: [south] });
  const cam = config.cameras[0];
  const { blocks } = obstacles(config);
  // Level and 2.5 m up, it sees down to about 29° below the horizon: from ~2.7 m out at waist height.
  assert.equal(cameraLevel(cam, [3, 1, 6.5], blocks), 0, 'too close below it');
  assert.equal(cameraLevel(cam, [3, 1, 8], blocks), LEVELS.length, 'close in front: identify');
  assert.equal(cameraLevel(cam, [3, 1, 30], blocks), 1, 'far in front: detect only');
  assert.equal(cameraLevel(cam, [3, 1, 40], blocks), 0, 'past its range');
  assert.equal(cameraLevel(cam, [12, 1, 6], blocks), 0, 'outside its 90° view');
  assert.equal(cameraLevel(cam, [3, 1, -3], blocks), 0, 'behind it, through the house');
});

test('a tall fence hides what is behind it; a low wall does not', () => {
  const cam = { ...south, tilt: 10 };
  const fence = plan({ cameras: [cam], outdoor: [{ type: 'fence', from: [0, 9], to: [6, 9] }] });
  const low = plan({ cameras: [cam], outdoor: [{ type: 'wall', from: [0, 6], to: [6, 6], height: 1 }] });
  const behind = [3, 1, 10.5];
  assert.equal(cameraLevel(fence.cameras[0], behind, obstacles(fence).blocks), 0);
  assert.ok(cameraLevel(low.cameras[0], behind, obstacles(low).blocks) > 0);
  assert.ok(cameraLevel(fence.cameras[0], [3, 1, 8], obstacles(fence).blocks) > 0, 'in front of the fence is seen');
});

test('a van hides what is behind it and is itself a place nobody stands', () => {
  const config = plan({ cameras: [south], outdoor: [{ type: 'van', pos: [3, 9], rot: 90 }] });
  const { blocks, solids } = obstacles(config);
  assert.equal(cameraLevel(config.cameras[0], [3, 1, 12], blocks), 0);
  assert.equal(solids.length, 2); // the room and the van
});

test('the crown of a tree lets the camera see under it; its trunk does not', () => {
  const config = plan({ cameras: [south], outdoor: [{ type: 'tree', pos: [3, 10], radius: 2, height: 6 }] });
  const { blocks } = obstacles(config);
  const cam = config.cameras[0];
  assert.equal(cameraLevel(cam, [3, 1, 13], blocks), 0, 'straight behind the trunk');
  assert.ok(cameraLevel(cam, [4, 1, 12], blocks) > 0, 'beside the trunk, under the crown');
});

test('coverage of the plot adds up', () => {
  const none = coverage(plan(), { cell: 0.5 });
  assert.equal(none.stats.plot, 26 * 24 - 6 * 4, 'the plot less the house');
  assert.equal(none.stats.seen, 0);
  const one = coverage(plan({ cameras: [south] }), { cell: 0.5 });
  assert.ok(one.stats.seen > 50 && one.stats.seen < one.stats.plot / 2, `seen ${one.stats.seen} m²`);
  assert.equal(one.stats.byLevel.reduce((a, b) => a + b, 0), one.stats.seen);
  const k = Math.floor((2 - one.z0) / one.size) * one.cols + Math.floor((3 - one.x0) / one.size);
  assert.equal(one.level[k], SOLID, 'inside the house');
});

test('doors and gates report the best camera on them', () => {
  const config = plan({
    cameras: [south],
    openings: [{ type: 'door', from: [2.5, 4], to: [3.4, 4] }, { type: 'door', from: [2.5, 0], to: [3.4, 0] }],
    outdoor: [{ type: 'gate', from: [2, 12], to: [4, 12] }],
  });
  const all = entrances(config);
  const front = all.find((e) => /south/.test(e.name));
  const back = all.find((e) => /north/.test(e.name));
  const gate = all.find((e) => e.kind === 'gate');
  assert.equal(all.length, 3);
  assert.equal(front.kind, 'door');
  // The camera hangs over the door looking out: the face of someone just outside is below and behind its view.
  assert.equal(front.level, 0);
  assert.equal(back.level, 0, 'round the back');
  assert.equal(gate.kind, 'gate');
  assert.equal(gate.camera, 'c');
  assert.ok(gate.level >= 2, `gate level ${gate.level}`);
});

test('the demo plan: every camera sees something, and the van hides part of the drive', () => {
  const raw = JSON.parse(readFileSync(new URL('../public/plans/home.json', import.meta.url)));
  const config = normalize(raw);
  for (const cam of config.cameras) {
    assert.ok(coverage(config, { cameras: [cam], cell: 0.5 }).stats.seen > 5, `${cam.id} sees nothing`);
  }
  const withVan = coverage(config, { cell: 0.5 }).stats.seen;
  const noVan = coverage(normalize({ ...raw, outdoor: raw.outdoor.filter((o) => o.type !== 'van') }), { cell: 0.5 }).stats.seen;
  assert.ok(withVan < noVan, `${withVan} m² with the van, ${noVan} m² without`);
});

test('a doorway lets the view through below its lintel, not above it', () => {
  // Two rooms side by side with an open passage between them; a camera in the corner of the left one.
  const config = normalize({
    rooms: [{ id: 'a', rect: [0, 0, 4, 4] }, { id: 'b', rect: [4, 0, 4, 4] }],
    openings: [{ type: 'open', from: [4, 1.5], to: [4, 2.5] }],
    cameras: [{ id: 'c', pos: [0.5, 2], y: 2.5, rot: 90, tilt: 0, fov: 90, range: 20 }],
  });
  const { blocks } = obstacles(config);
  const [cam] = config.cameras;
  assert.ok(cameraLevel(cam, [7, 1.6, 2], blocks) > 0, 'through the passage at face height');
  assert.equal(cameraLevel(cam, [7, 2.4, 2], blocks), 0, 'the lintel above 2.1 m is in the way');
});

test('a fence seen end on still blocks the view along it', () => {
  const config = plan({ cameras: [{ ...south, pos: [3, 4.18], rot: 0 }], outdoor: [{ type: 'fence', from: [3, 7], to: [3, 9] }] });
  const { blocks } = obstacles(config);
  assert.equal(cameraLevel(config.cameras[0], [3, 1, 11], blocks), 0, 'straight along the fence');
  assert.ok(cameraLevel(config.cameras[0], [3.6, 1, 11], blocks) > 0, 'just beside it');
});

test('a tree crown blocks where it is drawn', () => {
  // 5 m tall, 1.5 m crown: three/site.js draws the crown from 2.15 m up.
  const crown = treeShape({ height: 5, radius: 1.5 });
  assert.ok(Math.abs(crown.crownBottom - 2.15) < 1e-9);
  const config = plan({ cameras: [{ ...south, y: 2.6 }], outdoor: [{ type: 'tree', pos: [3, 7.5], radius: 1.5, height: 5 }] });
  const { blocks } = obstacles(config);
  // Level from 2.6 m up past the crown's side (clear of the trunk): the crown is in the way.
  assert.equal(cameraLevel(config.cameras[0], [4, 2.4, 11], blocks), 0);
});
