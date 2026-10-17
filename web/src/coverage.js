// What the security cameras can make out on the ground: which parts of the plot each one
// sees past walls, fences, trees and cars, and how much detail it has there. Pure maths on a
// normalised plan, so it runs (and is tested) under Node too.
import { wallSegments, DOOR_HEAD } from './three/house.js';
import { VEHICLE_SIZE, outdoorShape, treeShape } from './config.js';

const rad = (d) => (d * Math.PI) / 180;

/**
 * Detail levels after IEC 62676-4 ("DORI"): the pixels a camera puts on a metre of the scene
 * that it takes to detect someone, observe what they do, recognise someone you know, and
 * identify a stranger.
 */
export const LEVELS = [
  { id: 'detect', name: 'Detect', ppm: 25, color: '#fb923c' },
  { id: 'observe', name: 'Observe', ppm: 62.5, color: '#facc15' },
  { id: 'recognise', name: 'Recognise', ppm: 125, color: '#a3e635' },
  { id: 'identify', name: 'Identify', ppm: 250, color: '#34d399' },
];
export const BLIND_COLOR = '#f43f5e';

// A cell's level: 0 not seen, 1–4 a LEVELS index + 1. Cells under the house, a shed or a car
// are SOLID: nobody stands there.
export const SOLID = 255;

const BODY = 1.0; // a person counts as seen when the middle of them is
const FACE = 1.6; // at a door, the face is what matters

/** Pixels per metre a camera puts on something `d` metres away. */
export function pixelsPerMetre(cam, d) {
  const width = cam.resolution[0];
  // Up to ~150° a lens draws straight lines straight; wider ones (fisheyes) spread evenly by angle.
  return cam.fov <= 150 ? width / (2 * d * Math.tan(rad(cam.fov) / 2)) : width / (d * rad(cam.fov));
}

/** How far each level reaches for this camera, in metres (capped by its range). */
export function levelDistances(cam) {
  return LEVELS.map((l) => {
    const d = cam.fov <= 150 ? cam.resolution[0] / (2 * l.ppm * Math.tan(rad(cam.fov) / 2)) : cam.resolution[0] / (l.ppm * rad(cam.fov));
    return Math.min(d, cam.range);
  });
}

function levelAt(cam, d) {
  if (d > cam.range) return 0;
  const ppm = pixelsPerMetre(cam, d);
  let level = 0;
  LEVELS.forEach((l, i) => { if (ppm >= l.ppm) level = i + 1; });
  return level;
}

/* ---------- what stands in the way ---------- */

// A wall-like obstacle from a to b between heights y0..y1, or a round one (a trunk, a crown).
const seg = (a, b, y0, y1) => ({ a, b, y0, y1 });
const disc = (c, r, y0, y1) => ({ c, r, y0, y1 });

function rectEdges([x, z, w, d], y0, y1, out) {
  const p = [[x, z], [x + w, z], [x + w, z + d], [x, z + d]];
  p.forEach((q, i) => out.push(seg(q, p[(i + 1) % 4], y0, y1)));
}

function vehicleCorners(o) {
  const [len, wid] = VEHICLE_SIZE[o.type];
  const a = rad(o.rot || 0);
  const fwd = [Math.sin(a), Math.cos(a)]; // the way it faces, like furniture
  const side = [Math.cos(a), -Math.sin(a)];
  return [[1, 1], [1, -1], [-1, -1], [-1, 1]].map(([f, s]) => [
    o.pos[0] + fwd[0] * f * len / 2 + side[0] * s * wid / 2,
    o.pos[1] + fwd[1] * f * len / 2 + side[1] * s * wid / 2,
  ]);
}

/** Everything a camera cannot see through, and the footprints nobody stands in. */
export function obstacles(config) {
  const blocks = [];
  const solids = [];
  const H = config.wallHeight;
  // Outer walls block whole (a closed door or a window is still not a way to see in or out);
  // inner walls only where they are not a doorway — and a doorway still has a lintel over it.
  for (const s of wallSegments(config)) {
    const gap = s.opening && (s.opening.type === 'open' || (s.kind === 'interior' && s.opening.type === 'door'));
    const a = s.axis === 'x' ? [s.a, s.c] : [s.c, s.a];
    const b = s.axis === 'x' ? [s.b, s.c] : [s.c, s.b];
    if (!gap) blocks.push(seg(a, b, 0, H));
    else if (H > DOOR_HEAD) blocks.push(seg(a, b, DOOR_HEAD, H));
  }
  for (const r of config.rooms) solids.push({ rect: [r.x, r.z, r.w, r.d] });

  for (const o of config.outdoor) {
    const shape = outdoorShape(o.type);
    if (shape === 'line') {
      if (o.type !== 'gate') blocks.push(seg(o.from, o.to, 0, o.height)); // a gate's bars are see-through
    } else if (shape === 'point') {
      // The trunk, and the crown above it, as three/site.js draws them.
      const t = treeShape(o);
      blocks.push(disc(o.pos, t.trunkRadius[1], 0, t.trunkHeight), disc(o.pos, t.crownRadius, t.crownBottom, o.height));
    } else if (shape === 'vehicle') {
      const p = vehicleCorners(o);
      p.forEach((q, i) => blocks.push(seg(q, p[(i + 1) % 4], 0, o.height)));
      solids.push({ poly: p });
    } else if (o.type === 'building') {
      rectEdges(o.rect, 0, o.height, blocks);
      solids.push({ rect: o.rect });
    }
  }
  return { blocks, solids };
}

/* ---------- geometry ---------- */

// Where the sight line e→t (2D) meets segment a→b, as fractions [t0, t1] along e→t (one point
// when they cross; a stretch when the line runs along the segment, a fence seen end on), or null.
function crossSegment(ex, ez, tx, tz, a, b) {
  const rx = tx - ex;
  const rz = tz - ez;
  const sx = b[0] - a[0];
  const sz = b[1] - a[1];
  const qx = a[0] - ex;
  const qz = a[1] - ez;
  const den = rx * sz - rz * sx;
  const rr = rx * rx + rz * rz;
  if (Math.abs(den) < 1e-9 * Math.max(1, rr)) {
    if (Math.abs(qx * rz - qz * rx) > 1e-6 * Math.sqrt(rr) || rr < 1e-12) return null; // parallel, apart
    const ta = (qx * rx + qz * rz) / rr;
    const tb = ((b[0] - ex) * rx + (b[1] - ez) * rz) / rr;
    const t0 = Math.max(1e-6, Math.min(ta, tb));
    const t1 = Math.min(1 - 1e-6, Math.max(ta, tb));
    return t0 <= t1 ? [t0, t1] : null;
  }
  const t = (qx * sz - qz * sx) / den;
  const u = (qx * rz - qz * rx) / den;
  return t > 1e-6 && t < 1 - 1e-6 && u >= 0 && u <= 1 ? [t, t] : null;
}

// The part of the sight line inside a circle, as fractions [t0, t1], or null.
function crossDisc(ex, ez, tx, tz, c, r) {
  const dx = tx - ex;
  const dz = tz - ez;
  const fx = ex - c[0];
  const fz = ez - c[1];
  const A = dx * dx + dz * dz;
  const B = 2 * (fx * dx + fz * dz);
  const C = fx * fx + fz * fz - r * r;
  const disc2 = B * B - 4 * A * C;
  if (A < 1e-12 || disc2 < 0) return null;
  const sq = Math.sqrt(disc2);
  const t0 = Math.max(1e-6, (-B - sq) / (2 * A));
  const t1 = Math.min(1 - 1e-6, (-B + sq) / (2 * A));
  return t0 < t1 ? [t0, t1] : null;
}

/** Whether the straight line from the eye to a point is clear of everything in the way. */
export function clear(eye, target, blocks) {
  const [ex, ey, ez] = eye;
  const [tx, ty, tz] = target;
  for (const o of blocks) {
    // Blocked when the sight line is between the obstacle's bottom and top anywhere it passes it.
    const span = o.a ? crossSegment(ex, ez, tx, tz, o.a, o.b) : crossDisc(ex, ez, tx, tz, o.c, o.r);
    if (!span) continue;
    const ya = ey + (ty - ey) * span[0];
    const yb = ey + (ty - ey) * span[1];
    if (Math.max(ya, yb) >= o.y0 && Math.min(ya, yb) <= o.y1) return false;
  }
  return true;
}

// The camera's frame: forward, right and up as unit vectors, from `rot` and `tilt` (see cctv.js).
function frame(cam) {
  const r = rad(cam.rot);
  const t = rad(cam.tilt);
  const fwd = [Math.sin(r) * Math.cos(t), -Math.sin(t), Math.cos(r) * Math.cos(t)];
  const right = [-Math.cos(r), 0, Math.sin(r)]; // the camera's right, seen from behind it
  const up = [right[1] * fwd[2] - right[2] * fwd[1], right[2] * fwd[0] - right[0] * fwd[2], right[0] * fwd[1] - right[1] * fwd[0]];
  const h = Math.min(cam.fov, 160) / 2;
  const tanH = Math.tan(rad(h));
  return { fwd, right, up, tanH, tanV: tanH * cam.resolution[1] / cam.resolution[0] };
}

const LENS = 0.17; // keep in step with cctv.js

function eyeOf(cam, f) {
  return [cam.pos[0] + f.fwd[0] * LENS, cam.y + f.fwd[1] * LENS, cam.pos[1] + f.fwd[2] * LENS];
}

/** The detail level one camera has on a point (x, height, z): 0 when it cannot see it. */
export function cameraLevel(cam, point, blocks, f = frame(cam), eye = eyeOf(cam, f)) {
  const v = [point[0] - eye[0], point[1] - eye[1], point[2] - eye[2]];
  const z = v[0] * f.fwd[0] + v[1] * f.fwd[1] + v[2] * f.fwd[2];
  if (z <= 0.05) return 0;
  const x = v[0] * f.right[0] + v[2] * f.right[2];
  const y = v[0] * f.up[0] + v[1] * f.up[1] + v[2] * f.up[2];
  if (Math.abs(x) > z * f.tanH || Math.abs(y) > z * f.tanV) return 0;
  const level = levelAt(cam, Math.hypot(v[0], v[1], v[2]));
  if (!level) return 0;
  return clear(eye, point, blocks) ? level : 0;
}

function insidePolygon(x, z, poly) {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, zi] = poly[i];
    const [xj, zj] = poly[j];
    if ((zi > z) !== (zj > z) && x < ((xj - xi) * (z - zi)) / (zj - zi) + xi) inside = !inside;
  }
  return inside;
}

const inSolid = (x, z, s) => (s.rect
  ? x >= s.rect[0] && x <= s.rect[0] + s.rect[2] && z >= s.rect[1] && z <= s.rect[1] + s.rect[3]
  : insidePolygon(x, z, s.poly));

/** The plot: inside the property line, or the lawn around the house when there is none. */
export function plot(config) {
  if (config.site.boundary) return config.site.boundary;
  const b = config.bounds;
  return [[b.minX - 4, b.minZ - 4], [b.maxX + 4, b.minZ - 4], [b.maxX + 4, b.maxZ + 4], [b.minX - 4, b.maxZ + 4]];
}

/**
 * A grid over the site with, per cell, the best level any of `cameras` (all by default) has on a
 * person standing there; and how much of the plot that adds up to.
 */
export function coverage(config, { cameras = config.cameras, cell } = {}) {
  const sb = config.siteBounds;
  const span = Math.max(sb.maxX - sb.minX, sb.maxZ - sb.minZ);
  const size = cell ?? Math.max(0.2, span / 140);
  const x0 = sb.minX - 2;
  const z0 = sb.minZ - 2;
  const cols = Math.ceil((sb.maxX - sb.minX + 4) / size);
  const rows = Math.ceil((sb.maxZ - sb.minZ + 4) / size);
  const level = new Uint8Array(cols * rows);
  const onPlot = new Uint8Array(cols * rows);
  const { blocks, solids } = obstacles(config);
  const lot = plot(config);
  const cams = cameras.map((c) => { const f = frame(c); return { c, f, eye: eyeOf(c, f) }; });

  const area = size * size;
  const stats = { plot: 0, seen: 0, byLevel: [0, 0, 0, 0] };
  for (let j = 0; j < rows; j++) {
    const z = z0 + (j + 0.5) * size;
    for (let i = 0; i < cols; i++) {
      const x = x0 + (i + 0.5) * size;
      const k = j * cols + i;
      if (solids.some((s) => inSolid(x, z, s))) { level[k] = SOLID; continue; }
      let best = 0;
      for (const { c, f, eye } of cams) {
        const l = cameraLevel(c, [x, BODY, z], blocks, f, eye);
        if (l > best) best = l;
        if (best === LEVELS.length) break;
      }
      level[k] = best;
      if (insidePolygon(x, z, lot)) {
        onPlot[k] = 1;
        stats.plot += area;
        if (best) { stats.seen += area; stats.byLevel[best - 1] += area; }
      }
    }
  }
  return { x0, z0, size, cols, rows, level, onPlot, stats };
}

/**
 * The ways in: doors and open passages in the outer walls, and gates. For each, the best level
 * any camera has on the face of someone standing just outside it, and which camera that is.
 */
export function entrances(config) {
  const { blocks } = obstacles(config);
  const cams = config.cameras.map((c) => { const f = frame(c); return { c, f, eye: eyeOf(c, f) }; });
  const best = (points) => {
    let out = { level: 0, camera: null };
    for (const p of points) {
      for (const { c, f, eye } of cams) {
        const l = cameraLevel(c, [p[0], FACE, p[1]], blocks, f, eye);
        if (l > out.level) out = { level: l, camera: c.id };
      }
    }
    return out;
  };
  const roomAt = ([x, z]) => config.rooms.find((r) => x >= r.x && x <= r.x + r.w && z >= r.z && z <= r.z + r.d);
  const side = (n) => (n[0] > 0 ? 'east' : n[0] < 0 ? 'west' : n[1] > 0 ? 'south' : 'north');

  const out = [];
  const seen = new Set();
  for (const s of wallSegments(config)) {
    if (s.kind !== 'exterior' || !s.opening || s.opening.type === 'window' || seen.has(s.opening)) continue;
    seen.add(s.opening);
    const n = s.axis === 'x' ? [0, -s.inside] : [-s.inside, 0];
    const o = s.opening;
    const mid = [(o.from[0] + o.to[0]) / 2, (o.from[1] + o.to[1]) / 2];
    const room = roomAt([mid[0] - n[0] * 0.3, mid[1] - n[1] * 0.3]);
    out.push({
      kind: 'door', name: `${o.type === 'open' ? 'Opening' : 'Door'} · ${room?.name || 'house'}, ${side(n)}`,
      at: mid, ...best([[mid[0] + n[0] * 0.8, mid[1] + n[1] * 0.8]]),
    });
  }
  config.outdoor.filter((o) => o.type === 'gate').forEach((o, i, gates) => {
    const mid = [(o.from[0] + o.to[0]) / 2, (o.from[1] + o.to[1]) / 2];
    const len = Math.hypot(o.to[0] - o.from[0], o.to[1] - o.from[1]) || 1;
    const n = [-(o.to[1] - o.from[1]) / len, (o.to[0] - o.from[0]) / len];
    // Whoever comes through passes both sides of it.
    out.push({
      kind: 'gate', name: gates.length > 1 ? `Gate ${i + 1}` : 'Gate', at: mid,
      ...best([[mid[0] + n[0] * 0.8, mid[1] + n[1] * 0.8], [mid[0] - n[0] * 0.8, mid[1] - n[1] * 0.8]]),
    });
  });
  return out;
}

/** The grid as an image, one pixel a cell: detail colours, blind spots on the plot in red. */
export function coverageCanvas(map, { blind = true } = {}) {
  const canvas = document.createElement('canvas');
  canvas.width = map.cols;
  canvas.height = map.rows;
  const g = canvas.getContext('2d');
  const img = g.createImageData(map.cols, map.rows);
  const rgb = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
  const colors = LEVELS.map((l) => rgb(l.color));
  const red = rgb(BLIND_COLOR);
  for (let k = 0; k < map.level.length; k++) {
    const l = map.level[k];
    let c = null;
    let a = 0;
    if (l > 0 && l !== SOLID) { c = colors[l - 1]; a = 120; }
    else if (l === 0 && blind && map.onPlot[k]) { c = red; a = 80; }
    if (!c) continue;
    img.data.set([...c, a], k * 4);
  }
  g.putImageData(img, 0, 0);
  return canvas;
}
