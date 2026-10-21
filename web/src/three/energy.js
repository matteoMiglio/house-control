// The plan's energy section in 3D: solar panels on the roof that light up with what they make,
// a home battery whose front shows its charge, and lines of light carrying the power between
// the panels, the battery, the house and the grid. Every value eases towards the latest
// reading, so a sensor that reports every few seconds moves the scene smoothly.
import * as THREE from 'three';
import { LineSegments2 } from 'three/addons/lines/LineSegments2.js';
import { LineSegmentsGeometry } from 'three/addons/lines/LineSegmentsGeometry.js';
import { LineMaterial } from 'three/addons/lines/LineMaterial.js';
import { box, mat, at } from './kit.js';
import { ROOF_T } from './site.js';
import { PANEL_MODULE } from '../config.js';
import { energyFlows, consumption, IDLE_WATTS } from '../energy.js';

/** The colour of power by where it comes from: the sun, the battery, the grid. */
export const FLOW_COLORS = { solar: '#ffc24a', battery: '#4fe0b0', grid: '#6aa6ff' };
/** A battery's charge as its front shows it: green, amber when low, red when nearly empty. */
export const chargeColor = (c) => (c == null ? FLOW_COLORS.battery : c < 15 ? '#ff6b5a' : c < 35 ? FLOW_COLORS.solar : FLOW_COLORS.battery);

const TILT = THREE.MathUtils.degToRad(10); // panels on a flat roof stand on racks, raised at the back
const RACK = 0.12;     // the low edge, above the roof
const GAP = 0.025;     // between two modules
const EASE = 1.2;      // per second: how fast shown values follow a new reading
const STREAK = 0.38;   // metres
const PEAK_FLOOR = 120; // W per m² of panels: what counts as bright before anything brighter was seen

const ease = (dt, rate = EASE) => 1 - Math.exp(-dt * rate);
const fade = (watts) => THREE.MathUtils.clamp((Math.abs(watts) - IDLE_WATTS) / 80, 0, 1);

/* ---------- panels ---------- */

// One array of modules on its rack. The tilt turns about the low edge, which faces `rot`.
function panelArray(p, H, look) {
  const [w, d] = p.size;
  const cols = Math.max(1, Math.round(w / PANEL_MODULE[0]));
  const rows = Math.max(1, Math.round(d / PANEL_MODULE[1]));
  const cw = w / cols;
  const cd = d / rows;

  const group = new THREE.Group();
  group.position.set(p.pos[0], H + ROOF_T, p.pos[1]);
  group.rotation.y = THREE.MathUtils.degToRad(p.rot || 0);
  const tilted = new THREE.Group();
  tilted.position.set(0, RACK, d / 2);
  tilted.rotation.x = TILT;
  group.add(tilted);

  // Seen whole: an aluminium frame with dark cells on it, standing on posts at the back.
  const solid = new THREE.Group();
  solid.add(at(box(w + 0.04, 0.03, d + 0.04, look.frame, { r: 0.01 }), 0, 0, -d / 2));
  const cells = new THREE.InstancedMesh(new THREE.BoxGeometry(cw - GAP, 0.02, cd - GAP), look.cells, cols * rows);
  const m = new THREE.Matrix4();
  for (let c = 0; c < cols; c++) {
    for (let r = 0; r < rows; r++) {
      cells.setMatrixAt(c * rows + r, m.makeTranslation(-w / 2 + cw * (c + 0.5), 0.035, -d + cd * (r + 0.5)));
    }
  }
  solid.add(cells);
  tilted.add(solid);
  const high = RACK + d * Math.sin(TILT);
  const back = d / 2 - d * Math.cos(TILT) + 0.06;
  const posts = new THREE.Group();
  for (const x of [-w / 2 + 0.12, w / 2 - 0.12, ...(w > 3 ? [0] : [])]) posts.add(at(box(0.04, high, 0.04, look.frame, { r: 0 }), x, 0, back));
  group.add(posts);
  solid.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
  posts.traverse((o) => { o.castShadow = true; });

  // Cut open, there is no roof to stand on: only the outline of each module, and a glow.
  const ghost = new THREE.Group();
  const fill = new THREE.InstancedMesh(new THREE.PlaneGeometry(cw - GAP * 2, cd - GAP * 2).rotateX(-Math.PI / 2), look.ghostFill, cols * rows);
  fill.instanceMatrix = cells.instanceMatrix;
  const outline = [];
  for (let c = 0; c <= cols; c++) outline.push(-w / 2 + cw * c, 0.04, 0, -w / 2 + cw * c, 0.04, -d);
  for (let r = 0; r <= rows; r++) outline.push(-w / 2, 0.04, -cd * r, w / 2, 0.04, -cd * r);
  const lines = new THREE.BufferGeometry().setAttribute('position', new THREE.Float32BufferAttribute(outline, 3));
  ghost.add(fill, new THREE.LineSegments(lines, look.ghostLine));
  tilted.add(ghost);

  return { group, solid: [solid, posts], ghost: [ghost], area: w * d, top: new THREE.Vector3(p.pos[0], H + ROOF_T + (RACK + high) / 2, p.pos[1]) };
}

/* ---------- battery ---------- */

const SEGMENTS = 10;

function batteryModel() {
  const group = new THREE.Group();
  const shell = mat('#eceef1', { rough: 0.4 });
  group.add(
    at(box(0.56, 0.06, 0.16, mat('#2a2f3a', { rough: 0.7 }), { r: 0.01 }), 0, 0, 0),
    at(box(0.62, 1.0, 0.2, shell, { r: 0.045 }), 0, 0.05, 0),
    at(box(0.13, 0.76, 0.012, mat('#161a22', { rough: 0.25, metal: 0.3 }), { r: 0.006 }), 0, 0.17, 0.1),
  );
  group.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
  // The charge: a column of segments behind the glass, lit from the bottom up.
  const segments = Array.from({ length: SEGMENTS }, (_, i) => {
    const m = new THREE.MeshStandardMaterial({ color: '#20262f', roughness: 0.4, emissive: '#000000' });
    group.add(at(box(0.075, 0.056, 0.008, m, { r: 0 }), 0, 0.2 + i * 0.07, 0.106));
    return m;
  });
  const led = new THREE.MeshStandardMaterial({ color: '#30343c', roughness: 0.4, emissive: '#000000' });
  group.add(at(box(0.07, 0.012, 0.006, led, { r: 0 }), 0, 0.97, 0.1));
  return { group, segments, led };
}

/* ---------- flow lines ---------- */

// A path the power takes, drawn as streaks of light running along it (like the AC's airflow)
// over a faint track. Its watts set how bright, thick and fast; the sign, which way.
class FlowLine {
  constructor(curve) {
    this.points = curve.getSpacedPoints(64);
    this.length = curve.getLength();
    this.count = THREE.MathUtils.clamp(Math.round(this.length * 2.6), 4, 40);

    const track = new LineSegmentsGeometry();
    track.setPositions(this.points.flatMap((p, i) => (i ? [...this.points[i - 1].toArray(), ...p.toArray()] : [])));
    this.trackMat = new LineMaterial({
      linewidth: 1.2, transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: false,
    });
    this.track = new LineSegments2(track, this.trackMat);

    const geo = new LineSegmentsGeometry();
    geo.setPositions(new Float32Array(this.count * 6));
    geo.setColors(new Float32Array(this.count * 6));
    this.pos = geo.attributes.instanceStart.data;
    this.col = geo.attributes.instanceColorStart.data;
    this.pos.setUsage(THREE.DynamicDrawUsage);
    this.col.setUsage(THREE.DynamicDrawUsage);
    this.mat = new LineMaterial({
      linewidth: 2, vertexColors: true, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true, toneMapped: false,
    });
    this.streaks = new LineSegments2(geo, this.mat);
    for (const l of [this.track, this.streaks]) { l.frustumCulled = false; l.visible = false; }
    this.group = new THREE.Group();
    this.group.add(this.track, this.streaks);

    this.watts = 0;
    this.goal = 0;
    this.phase = 0;
    this.color = new THREE.Color();
    this.shown = true;
  }

  // A point at `t` (0…1) along the path.
  at(t, out, o) {
    const f = THREE.MathUtils.clamp(t, 0, 1) * (this.points.length - 1);
    const i = Math.min(this.points.length - 2, Math.floor(f));
    const a = this.points[i];
    const b = this.points[i + 1];
    const k = f - i;
    out[o] = a.x + (b.x - a.x) * k;
    out[o + 1] = a.y + (b.y - a.y) * k;
    out[o + 2] = a.z + (b.z - a.z) * k;
  }

  /** Eases towards the goal and moves the streaks; `colors`: [positive, negative] direction. */
  update(dt, scale, colors) {
    this.watts += (this.goal - this.watts) * ease(dt);
    if (Math.abs(this.goal - this.watts) < 0.5) this.watts = this.goal;
    const alpha = this.shown ? fade(this.watts) : 0;
    const on = alpha > 0.004;
    this.track.visible = this.streaks.visible = on;
    if (!on) return this.watts !== this.goal;

    const s = Math.sqrt(Math.min(1, Math.abs(this.watts) / scale));
    const dir = Math.sign(this.watts);
    this.color.set(colors[dir > 0 ? 0 : 1]);
    this.mat.linewidth = 1.6 + 3.2 * s;
    this.trackMat.linewidth = 1 + 1.4 * s;
    this.trackMat.color.copy(this.color);
    this.trackMat.opacity = 0.16 * alpha;
    // The phase moves on by the speed of this frame, so a change of speed never makes the streaks jump.
    this.phase = (this.phase + (dt * dir * (0.45 + 1.5 * s)) / this.length + 1) % 1;

    const tail = (STREAK / this.length) * dir;
    const { r, g, b } = this.color;
    const pos = this.pos.array;
    const col = this.col.array;
    for (let i = 0; i < this.count; i++) {
      const t = (this.phase + i / this.count) % 1;
      this.at(t, pos, i * 6);
      this.at(t - tail, pos, i * 6 + 3);
      // Streaks come and go softly at the ends of the path.
      const glow = Math.sqrt(Math.sin(Math.PI * t)) * alpha * (0.6 + 0.9 * s);
      col[i * 6] = r * glow; col[i * 6 + 1] = g * glow; col[i * 6 + 2] = b * glow;
      col[i * 6 + 3] = r * glow * 0.08; col[i * 6 + 4] = g * glow * 0.08; col[i * 6 + 5] = b * glow * 0.08;
    }
    this.pos.needsUpdate = true;
    this.col.needsUpdate = true;
    return true;
  }
}

// A gentle arc from a to b, rising a little over its middle so it clears what stands between.
function arc(a, b, lift = 0.18) {
  const mid = a.clone().add(b).multiplyScalar(0.5);
  mid.y += a.distanceTo(b) * lift;
  return new THREE.QuadraticBezierCurve3(a, mid, b);
}

/* ---------- the whole ---------- */

export class EnergyUnit {
  /** `camDir`: the side the cut-open view looks from (the grid's line leaves the house on the far side). */
  constructor(config, camDir) {
    const energy = config.energy;
    this.cfg = energy;
    const H = config.wallHeight;
    this.group = new THREE.Group();

    // Panels: shared materials, so every array shows the same production.
    this.look = {
      frame: mat('#a6adb8', { rough: 0.35, metal: 0.7 }),
      cells: new THREE.MeshStandardMaterial({ color: '#16203a', roughness: 0.35, metalness: 0.15, emissive: '#000000' }),
      ghostFill: new THREE.MeshBasicMaterial({
        color: '#4f8dff', transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: false,
        side: THREE.DoubleSide,
      }),
      ghostLine: new THREE.LineBasicMaterial({ color: '#8fb6ff', transparent: true, opacity: 0.3, depthWrite: false }),
    };
    this.arrays = energy.panels.map((p) => panelArray(p, H, this.look));
    for (const a of this.arrays) this.group.add(a.group);
    this.area = this.arrays.reduce((sum, a) => sum + a.area, 0);

    // The battery, at the back of its footprint, facing `rot`.
    const b = energy.battery;
    this.battery = b ? batteryModel() : null;
    if (b) {
      this.battery.group.position.set(b.pos[0], 0, b.pos[1]);
      this.battery.group.rotation.y = THREE.MathUtils.degToRad(b.rot || 0);
      this.group.add(this.battery.group);
    }

    // Where the lines meet: the house as a whole (one point over the middle of it, just clear
    // of the cut-down inner walls: the power goes to the house, never to a room or a device),
    // the panels nearest to it, the front of the battery, and the grid, out past the far wall
    // nearest that point.
    const { minX, minZ, maxX, maxZ } = config.bounds;
    const house = new THREE.Vector3((minX + maxX) / 2, Math.min(config.interiorWallHeight ?? 1.25, H) + 0.2, (minZ + maxZ) / 2);
    this.house = house;
    const roof = this.arrays.map((a) => a.top).sort((p, q) => p.distanceTo(house) - q.distanceTo(house))[0] || null;
    const front = b && new THREE.Vector3(b.pos[0], 0.55, b.pos[1])
      .add(new THREE.Vector3(0, 0, 0.14).applyAxisAngle(new THREE.Vector3(0, 1, 0), THREE.MathUtils.degToRad(b.rot || 0)));
    const sides = [
      { n: [-1, 0], at: () => new THREE.Vector3(minX - 1.8, 0.05, house.z), d: house.x - minX },
      { n: [1, 0], at: () => new THREE.Vector3(maxX + 1.8, 0.05, house.z), d: maxX - house.x },
      { n: [0, -1], at: () => new THREE.Vector3(house.x, 0.05, minZ - 1.8), d: house.z - minZ },
      { n: [0, 1], at: () => new THREE.Vector3(house.x, 0.05, maxZ + 1.8), d: maxZ - house.z },
    ];
    const far = sides.filter((s) => s.n[0] * camDir.x + s.n[1] * camDir.z < -0.1).sort((p, q) => p.d - q.d)[0] || sides[0];
    const grid = far.at();

    this.lines = {
      roofHouse: roof && new FlowLine(arc(roof, house, 0.1)),
      roofBattery: roof && front && new FlowLine(arc(roof, front, 0.1)),
      batteryHouse: front && new FlowLine(arc(front, house, 0.25)),
      gridHouse: new FlowLine(arc(grid, house, 0.12)),
    };
    for (const line of Object.values(this.lines)) if (line) this.group.add(line.group);

    // The house's own use: a faint ring where the lines meet.
    this.ringMat = new THREE.MeshBasicMaterial({
      color: '#ffe6c4', transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: false,
    });
    this.ring = new THREE.Mesh(new THREE.RingGeometry(0.17, 0.21, 48).rotateX(-Math.PI / 2), this.ringMat);
    this.ring.position.copy(house);
    this.group.add(this.ring);

    this.level = 0;      // the panels' output, 0…1 of their peak
    this.levelGoal = 0;
    this.peakSeen = 0;
    this.charge = null;  // eased state of charge, %
    this.chargeGoal = null;
    this.use = 0;        // the house's consumption, W
    this.useGoal = 0;
    this.clock = 0;
    this.setWhole(false);
  }

  /** Seen whole (from outside) or cut open. Panels stand on the roof: without one (cut open, or a
   *  plan without a roof) only their outline shows. The power flow belongs to the view from
   *  outside, roof or not; the cut-open rooms are about lamps and ACs. */
  setWhole(whole, roof = true) {
    this.whole = whole;
    for (const a of this.arrays) {
      for (const o of a.solid) o.visible = whole && roof;
      for (const o of a.ghost) o.visible = !(whole && roof);
    }
    // A battery outside the house belongs to the view from outside, like the lamps out there.
    if (this.battery) this.battery.group.visible = whole || Boolean(this.cfg.battery.room);
    for (const line of Object.values(this.lines)) if (line) line.shown = whole;
  }

  /** The output that looks brightest: the plan's peak, or the most seen so far. */
  get peak() {
    return this.cfg.peak ?? Math.max(this.peakSeen, this.area * PEAK_FLOOR, 300);
  }

  apply(energy = {}, { instant = false } = {}) {
    const flows = energyFlows(energy, this.cfg);
    for (const [key, line] of Object.entries(this.lines)) if (line) line.goal = flows[key] ?? 0;
    const solar = Number.isFinite(energy.solar) ? energy.solar : 0;
    this.peakSeen = Math.max(this.peakSeen, solar);
    this.levelGoal = Math.min(1, solar / this.peak);
    this.chargeGoal = Number.isFinite(energy.charge) ? energy.charge : null;
    if (this.chargeGoal == null || this.charge == null) this.charge = this.chargeGoal;
    this.useGoal = consumption(energy, this.cfg) ?? 0;
    if (instant) {
      for (const line of Object.values(this.lines)) if (line) line.watts = line.goal;
      this.level = this.levelGoal;
      this.charge = this.chargeGoal;
      this.use = this.useGoal;
    }
  }

  update(dt) {
    this.clock += dt;
    let active = false;
    const scale = Math.max(1500, this.peak);
    const { solar, battery, grid } = FLOW_COLORS;
    const colors = { roofHouse: [solar, solar], roofBattery: [solar, solar], batteryHouse: [battery, grid], gridHouse: [grid, solar] };
    for (const [key, line] of Object.entries(this.lines)) if (line) active = line.update(dt, scale, colors[key]) || active;

    const k = ease(dt);
    const moving = Math.abs(this.levelGoal - this.level) > 0.001 || Math.abs(this.useGoal - this.use) > 0.5
      || (this.charge != null && Math.abs(this.chargeGoal - this.charge) > 0.01);
    this.level += (this.levelGoal - this.level) * k;
    this.use += (this.useGoal - this.use) * k;
    if (this.charge != null) this.charge += (this.chargeGoal - this.charge) * k;
    this.writePanels();
    this.writeHouse();
    const busy = this.writeBattery();
    return active || moving || busy;
  }

  // Dark blue cells at night; in the sun they glow a brighter blue, the more the brighter.
  writePanels() {
    const l = this.level;
    const { cells, ghostFill, ghostLine } = this.look;
    cells.emissive.set('#123a9c').lerp(tmp.set('#5fb0ff'), Math.pow(l, 1.2));
    cells.emissiveIntensity = 0.9 * Math.pow(l, 0.9);
    cells.color.set('#16203a').lerp(tmp.set('#203a6e'), l);
    ghostFill.opacity = 0.015 + 0.075 * Math.pow(l, 0.9);
    ghostLine.opacity = 0.09 + 0.17 * l;
  }

  writeHouse() {
    const s = Math.sqrt(Math.min(1, this.use / 3000));
    const any = Object.values(this.lines).some((line) => line?.streaks.visible);
    this.ringMat.opacity = any ? (0.25 + 0.55 * s) * (0.85 + 0.15 * Math.sin(this.clock * 2.2)) : 0;
    this.ring.scale.setScalar(1 + 0.8 * s);
  }

  // The charge, lit from the bottom up in green, amber when low, red when nearly empty. While
  // charging a shimmer runs up the column and the light at the top breathes; while discharging
  // it drifts down. Returns whether it is animating.
  writeBattery() {
    if (!this.battery) return false;
    const net = this.lines.batteryHouse ? this.lines.batteryHouse.watts - (this.lines.roofBattery?.watts ?? 0) : 0;
    const charging = net < -IDLE_WATTS;
    const discharging = net > IDLE_WATTS;
    const c = this.charge;
    const hue = chargeColor(c);
    this.battery.segments.forEach((m, i) => {
      const lit = c == null ? 0 : THREE.MathUtils.clamp(c / 10 - i, 0, 1);
      const wave = charging ? 0.75 + 0.45 * Math.max(0, Math.sin(this.clock * 3 - i * 0.75))
        : discharging ? 0.85 + 0.15 * Math.sin(this.clock * 1.6 + i * 0.75) : 1;
      m.emissive.set(hue);
      m.emissiveIntensity = lit > 0 ? (0.25 + 1.5 * lit) * wave : 0;
      m.color.set(lit > 0 ? hue : '#20262f');
    });
    const led = this.battery.led;
    led.emissive.set(charging ? FLOW_COLORS.battery : discharging ? '#ffd9a0' : '#000000');
    led.emissiveIntensity = charging ? 1.2 + 0.9 * Math.sin(this.clock * 2.4) : discharging ? 1.1 : 0;
    return charging || discharging;
  }
}

const tmp = new THREE.Color();
