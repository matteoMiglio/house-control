// A security camera: a bullet camera on a bracket, and the edges of its field of view out to
// its range. What it actually sees on the ground, past what stands in the way, is coverage.js.
import * as THREE from 'three';
import { LineSegments2 } from 'three/addons/lines/LineSegments2.js';
import { LineSegmentsGeometry } from 'three/addons/lines/LineSegmentsGeometry.js';
import { LineMaterial } from 'three/addons/lines/LineMaterial.js';
import { box, cyl, mat, at } from './kit.js';

const rad = THREE.MathUtils.degToRad;

/** One colour per camera, in plan order, so overlapping views can be told apart. */
export const CAMERA_COLORS = ['#3fc8ff', '#ffb547', '#7ae89a', '#ff7ab6', '#b69cff', '#ffe066', '#5ef0e0', '#ff8f6b'];
export const cameraColor = (index) => CAMERA_COLORS[index % CAMERA_COLORS.length];

// A rectilinear lens cannot show 180°; past this the view is drawn as if it were this wide.
const MAX_PROJECTED_FOV = 160;
const EDGE_SAMPLES = 12;
const LENS = 0.17; // from the mount to the front of the lens

/** Half the horizontal and vertical angle of view, in radians. */
export function halfAngles(cfg) {
  const h = rad(Math.min(cfg.fov, MAX_PROJECTED_FOV)) / 2;
  const [w, hh] = cfg.resolution;
  return { h, v: Math.atan(Math.tan(h) * hh / w) };
}

/** The camera's orientation: `rot` turns it like furniture (0° faces south), `tilt` looks down. */
export function cameraQuaternion(cfg, out = new THREE.Quaternion()) {
  return out.setFromEuler(new THREE.Euler(rad(cfg.tilt), rad(cfg.rot), 0, 'YXZ'));
}

/** Where the lens is, in world space. */
export function lensPosition(cfg, out = new THREE.Vector3()) {
  return out.set(0, 0, LENS).applyQuaternion(cameraQuaternion(cfg)).add(new THREE.Vector3(cfg.pos[0], cfg.y, cfg.pos[1]));
}

/**
 * Rays along the edge of the picture, each cut where it meets the ground or runs out of range.
 * Their ends, dropped onto the ground, outline what the camera covers there; the first ray of
 * each side (0, n, 2n, 3n) is a corner of the picture.
 */
export function viewEdge(cfg) {
  const { h, v } = halfAngles(cfg);
  const q = cameraQuaternion(cfg);
  const eye = lensPosition(cfg);
  const tu = Math.tan(h);
  const tv = Math.tan(v);
  const ring = [];
  const side = (u0, v0, u1, v1) => {
    for (let i = 0; i < EDGE_SAMPLES; i++) {
      const t = i / EDGE_SAMPLES;
      ring.push([u0 + (u1 - u0) * t, v0 + (v1 - v0) * t]);
    }
  };
  side(-1, -1, 1, -1); side(1, -1, 1, 1); side(1, 1, -1, 1); side(-1, 1, -1, -1);

  const ends = ring.map(([u, w]) => {
    // Camera space looks along +z with +y up the picture.
    const d = new THREE.Vector3(u * tu, w * tv, 1).normalize().applyQuaternion(q);
    let t = d.y < -1e-4 ? (eye.y - 0.01) / -d.y : Infinity;
    const flatLen = Math.hypot(d.x, d.z);
    if (flatLen * t > cfg.range) t = cfg.range / Math.max(flatLen, 1e-4);
    if (!Number.isFinite(t)) t = cfg.range;
    return eye.clone().addScaledVector(d, t);
  });
  return { eye, ends, corners: [0, 1, 2, 3].map((k) => ends[k * EDGE_SAMPLES]) };
}

export class CameraUnit {
  constructor(cfg, color) {
    this.cfg = cfg;
    this.id = cfg.id;
    this.color = new THREE.Color(color);

    this.group = new THREE.Group();
    this.group.position.set(cfg.pos[0], cfg.y, cfg.pos[1]);
    this.group.rotation.y = rad(cfg.rot);

    // The body tilts on its bracket; the bracket stays level against the wall.
    const shell = mat('#eef0f2', { rough: 0.4 });
    const dark = mat('#1b1e24', { rough: 0.3 });
    const body = new THREE.Group();
    body.rotation.x = rad(cfg.tilt);
    const barrel = cyl(0.045, 0.05, 0.2, shell, 20);
    barrel.rotation.x = Math.PI / 2;
    barrel.position.z = -0.03;
    const lens = cyl(0.032, 0.032, 0.012, dark, 20);
    lens.rotation.x = Math.PI / 2;
    lens.position.z = LENS - 0.006;
    this.led = new THREE.MeshStandardMaterial({ color: '#000', emissive: this.color, emissiveIntensity: 2.2 });
    const led = at(new THREE.Mesh(new THREE.SphereGeometry(0.008, 8, 6), this.led), 0.032, 0.03, LENS - 0.01);
    body.add(barrel, lens, led, at(box(0.11, 0.012, 0.24, shell, { r: 0.004 }), 0, 0.05, 0.0));
    this.group.add(
      at(box(0.04, 0.05, 0.12, shell, { r: 0.01 }), 0, -0.07, -0.08),
      at(box(0.11, 0.14, 0.02, shell, { r: 0.008 }), 0, -0.12, -0.15),
      body);
    this.group.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
    this.body = body;

    this.hit = new THREE.Mesh(new THREE.BoxGeometry(0.45, 0.4, 0.5), new THREE.MeshBasicMaterial());
    this.hit.position.set(0, -0.04, 0);
    this.hit.visible = false;
    this.hit.userData = { kind: 'camera', id: cfg.id };
    this.group.add(this.hit);

    this.view = this.buildView();
    this.hover = 0;
    this.hoverGoal = 0;
  }

  /** The lens, in world space. */
  eye(out = new THREE.Vector3()) {
    return lensPosition(this.cfg, out);
  }

  anchor(out) {
    return this.eye(out).add(new THREE.Vector3(0, 0.22, 0));
  }

  buildView() {
    const { eye, ends, corners } = viewEdge(this.cfg);
    const group = new THREE.Group();
    // The outline on the ground, and the four corners of the picture back to the lens.
    const pts = [];
    ends.forEach((p, i) => {
      const n = ends[(i + 1) % ends.length];
      pts.push(p.x, 0.03, p.z, n.x, 0.03, n.z);
    });
    for (const c of corners) pts.push(eye.x, eye.y, eye.z, c.x, c.y, c.z);
    const lineGeo = new LineSegmentsGeometry();
    lineGeo.setPositions(pts);
    const lines = new LineSegments2(lineGeo, new LineMaterial({
      color: this.color, linewidth: 1.4, transparent: true, opacity: 0.7, depthWrite: false, toneMapped: false,
    }));
    lines.renderOrder = 3;
    group.add(lines);
    this.ground = ends.map((p) => [p.x, p.z]);
    return group;
  }

  update(dt) {
    this.hover += (this.hoverGoal - this.hover) * (1 - Math.exp(-dt * 14));
    this.group.scale.setScalar(1 + this.hover * 0.25);
    return Math.abs(this.hoverGoal - this.hover) > 0.004;
  }

  dispose() {
    this.view.traverse((o) => { o.geometry?.dispose(); o.material?.dispose(); });
  }
}
