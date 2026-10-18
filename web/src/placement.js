// Finds useful places for more cameras on exterior walls. Scores cached DORI views of the
// plot and entrances, then improves a greedy selection without moving cameras already planned.
import { wallSegments, EXT_T } from './three/house.js';
import { withCameraDefaults } from './config.js';
import { coverage, entrances, obstacles, plot, cameraLevel, frame, eyeOf } from './coverage.js';

const VALUE = [0, 1, 2, 3.5, 5];
const ENTRY = [0, 0.1, 0.25, 0.5, 1].map((v) => v * 40);
const normal = (s) => s.axis === 'x' ? [0, -s.inside] : [-s.inside, 0];
const side = ([x, z]) => x ? (x > 0 ? 'east' : 'west') : (z > 0 ? 'south' : 'north');
const point = (s, along) => s.axis === 'x' ? [along, s.c] : [s.c, along];
const distance = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
const angle = (a, b) => Math.abs(((a - b) % 360 + 540) % 360 - 180);
const stacked = (a, b) => distance(a.pos, b.pos) < 1.5 && angle(a.rot, b.rot) < 50;

function location(s, along, walls) {
  const n = normal(s);
  for (const end of [s.a, s.b]) {
    if (Math.abs(along - end) > 0.5 + 1e-9) continue;
    const corner = point(s, end);
    const other = walls.find((w) => w.axis !== s.axis
      && [w.a, w.b].some((e) => distance(corner, point(w, e)) < 1e-6));
    if (other) {
      const m = normal(other);
      return `${side([0, n[1] || m[1]])}-${side([n[0] || m[0], 0])} corner`;
    }
  }
  return `${side(n)} wall`;
}

// Use the entrance report's names/order and the same face targets, including both gate sides.
function entrancePoints(config, ways, walls) {
  let gate = 0;
  const gates = config.outdoor.filter((o) => o.type === 'gate');
  return ways.map((way) => {
    let n;
    if (way.kind === 'gate') {
      const o = gates[gate++];
      const len = distance(o.from, o.to) || 1;
      n = [-(o.to[1] - o.from[1]) / len, (o.to[0] - o.from[0]) / len];
    } else {
      const s = walls.find((w) => w.opening && w.opening.type !== 'window'
        && distance(way.at, [(w.opening.from[0] + w.opening.to[0]) / 2,
          (w.opening.from[1] + w.opening.to[1]) / 2]) < 1e-6);
      n = normal(s);
    }
    return (way.kind === 'gate' ? [1, -1] : [1]).map((sign) => [
      way.at[0] + sign * n[0] * 0.8, 1.6, way.at[1] + sign * n[1] * 0.8,
    ]);
  });
}

/** Suggest 1–8 additional wall cameras on a normalised plan; kept cameras stay fixed.
 * Shares use the walkable plot and mutually exclusive best DORI levels, as coverage() does.
 * In entrance reports a suggested camera is referenced by its name; returned cameras have no ids.
 */
export function suggestCameras(config, {
  count = 2, camera = { fov: 104, resolution: [2560, 1440], range: 12 },
  keep = config.cameras, cell,
} = {}) {
  if (!Number.isInteger(count) || count < 1 || count > 8) throw new RangeError('count must be an integer from 1 to 8');
  if (cell !== undefined && (!Number.isFinite(cell) || cell <= 0)) throw new RangeError('cell must be positive');
  const lot = plot(config);
  const xs = lot.map((p) => p[0]);
  const zs = lot.map((p) => p[1]);
  const width = Math.max(...xs) - Math.min(...xs);
  const depth = Math.max(...zs) - Math.min(...zs);
  // The grid spans the plot only (not everything on the plan, which may lie far off), at a size
  // that keeps it to a few thousand cells however big the plot is.
  const plotBounds = { minX: Math.min(...xs), minZ: Math.min(...zs), maxX: Math.max(...xs), maxZ: Math.max(...zs) };
  const grid = coverage({ ...config, siteBounds: plotBounds },
    { cameras: [], cell: Math.max(cell ?? 0, 0.2, Math.sqrt(((width + 4) * (depth + 4)) / 2500)) });
  const points = [];
  for (let k = 0; k < grid.onPlot.length; k++) {
    if (grid.onPlot[k]) points.push([grid.x0 + (k % grid.cols + 0.5) * grid.size, 1,
      grid.z0 + (Math.floor(k / grid.cols) + 0.5) * grid.size]);
  }
  const area = grid.size ** 2;
  const walls = wallSegments(config).filter((s) => s.kind === 'exterior');
  const kept = keep.map(withCameraDefaults);
  const ways = entrances({ ...config, cameras: [] });
  const targets = entrancePoints(config, ways, walls);
  const { blocks } = obstacles(config);
  const view = (cam) => {
    const f = frame(cam);
    const eye = eyeOf(cam, f);
    return {
      cam,
      cells: Uint8Array.from(points, (p) => cameraLevel(cam, p, blocks, f, eye)),
      entries: Uint8Array.from(targets, (ps) => Math.max(...ps.map((p) => cameraLevel(cam, p, blocks, f, eye)))),
    };
  };
  const empty = () => ({ cells: new Uint8Array(points.length), entries: new Uint8Array(ways.length) });
  const merge = (best, v) => {
    for (const key of ['cells', 'entries']) {
      for (let i = 0; i < best[key].length; i++) best[key][i] = Math.max(best[key][i], v[key][i]);
    }
    return best;
  };
  const gain = (best, v) => {
    let total = 0;
    for (let i = 0; i < best.cells.length; i++) {
      if (v.cells[i] > best.cells[i]) total += (VALUE[v.cells[i]] - VALUE[best.cells[i]]) * area;
    }
    for (let i = 0; i < best.entries.length; i++) {
      if (v.entries[i] > best.entries[i]) total += ENTRY[v.entries[i]] - ENTRY[best.entries[i]];
    }
    return total;
  };
  const initial = kept.reduce((best, cam) => merge(best, view(cam)), empty());
  const mount = (s, along, rot, tilt) => {
    const n = normal(s);
    const p = point(s, along);
    return {
      fov: camera.fov ?? 104, resolution: [...(camera.resolution ?? [2560, 1440])], range: camera.range ?? 12,
      // centimetres, like everything the editor writes
      pos: [p[0] + n[0] * (EXT_T / 2 + 0.08), p[1] + n[1] * (EXT_T / 2 + 0.08)].map((v) => Math.round(v * 100) / 100),
      y: Math.round(Math.min(2.8, config.wallHeight - 0.15) * 100) / 100, rot, tilt,
    };
  };
  const candidate = (s, along, rot, tilt) => ({ ...view(mount(s, along, rot, tilt)), s, along });
  const candidates = [];
  // About a metre apart, or further on a very long house: no more than ~150 spots in all.
  const perimeter = walls.reduce((sum, s) => sum + (s.b - s.a), 0);
  const spacing = Math.max(1, perimeter / 150);
  for (const s of walls) {
    if (s.b - s.a < 0.6) continue;
    const spots = [s.a + 0.3];
    for (let a = s.a + 0.3 + spacing; a < s.b - 0.3 - 1e-6; a += spacing) spots.push(a);
    if (s.b - 0.3 > spots[spots.length - 1] + 1e-6) spots.push(s.b - 0.3);
    const n = normal(s);
    const rot = Math.atan2(n[0], n[1]) * 180 / Math.PI;
    for (const along of spots) {
      for (const turn of [0, -35, 35]) {
        for (const tilt of [15, 25, 35]) candidates.push(candidate(s, along, rot + turn, tilt));
      }
    }
  }
  const selected = [];
  const best = merge(empty(), initial);
  for (let i = 0; i < count; i++) {
    let winner = null;
    let value = -Infinity;
    for (const v of candidates) {
      if ([...kept, ...selected.map((w) => w.cam)].some((c) => stacked(v.cam, c))) continue;
      const g = gain(best, v);
      if (g > value) { winner = v; value = g; }
    }
    if (!winner || value <= 0) break; // nowhere left where a camera would add anything
    selected.push(winner);
    merge(best, winner);
  }
  for (let i = 0; i < selected.length; i++) {
    const rest = selected.filter((_, j) => j !== i);
    const base = rest.reduce(merge, merge(empty(), initial));
    let winner = selected[i];
    let value = gain(base, winner);
    // One coordinate pass: improvements to aim carry into tilt and position trials.
    for (const coordinate of ['rot', 'tilt', 'along']) {
      const { s, along, cam } = winner;
      const deltas = coordinate === 'rot' ? [-10, 10, -20, 20] : coordinate === 'tilt' ? [-5, 5] : [-0.5, 0.5];
      for (const d of deltas) {
        const a = coordinate === 'along' ? Math.max(s.a + 0.3, Math.min(s.b - 0.3, along + d)) : along;
        const v = candidate(s, a, cam.rot + (coordinate === 'rot' ? d : 0), cam.tilt + (coordinate === 'tilt' ? d : 0));
        if ([...kept, ...rest.map((w) => w.cam)].some((c) => stacked(v.cam, c))) continue;
        const g = gain(base, v);
        if (g > value) { winner = v; value = g; }
      }
    }
    selected[i] = winner;
  }
  const cameras = selected.map((v, i) => ({
    name: `Suggested camera ${i + 1}`, ...v.cam, where: location(v.s, v.along, walls),
  }));
  // What the plot looks like with a set of cameras, measured as the coverage panel measures it
  // (its own grid), so the numbers shown before and after match the panel's.
  const report = (cams) => {
    const { stats } = coverage({ ...config, cameras: cams }, { cameras: cams });
    const total = stats.plot || 1;
    return {
      seenShare: stats.seen / total,
      byLevelShare: stats.byLevel.map((a) => a / total),
      ways: entrances({ ...config, cameras: cams }),
    };
  };
  return {
    cameras,
    before: report(kept),
    after: report([...kept, ...cameras.map((c) => ({ ...c, id: c.name }))]), // reports name them
  };
}
