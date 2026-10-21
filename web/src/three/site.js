// What is around the house, for the view from outside: the ground, the property line,
// fences, walls, hedges, gates, trees, sheds and paving, and a flat roof on the house.
import * as THREE from 'three';
import { box, cyl, mat, at, shadows, rng, canvasTexture, shade, floorMesh } from './kit.js';
import { EXT_T } from './house.js';
import { outdoorShape, treeShape, VEHICLE_SIZE } from '../config.js';

const MARGIN = 14;   // ground beyond everything on the plan, in metres
const EAVE = 0.3;    // roof overhang beyond the outer face of the walls
export const ROOF_T = 0.18; // the flat roof, laid on the walls (solar panels stand on it: energy.js)
const GROUND_TILE = 3;

function speckle(base, dots, spread) {
  return canvasTexture(512, (g, s) => {
    const rand = rng(base.charCodeAt(1) * 131 + dots);
    g.fillStyle = base;
    g.fillRect(0, 0, s, s);
    for (let i = 0; i < dots; i++) {
      g.fillStyle = shade(base, (rand() - 0.5) * spread);
      const r = 1 + rand() * 3;
      g.fillRect(rand() * s, rand() * s, r, r * (0.6 + rand()));
    }
  });
}

const GROUNDS = {
  grass: () => speckle('#4d6a3a', 9000, 0.16),
  gravel: () => speckle('#8c877d', 12000, 0.22),
  concrete: () => canvasTexture(512, (g, s) => {
    g.fillStyle = '#9da1a3';
    g.fillRect(0, 0, s, s);
    g.fillStyle = 'rgba(0,0,0,0.22)';
    g.fillRect(0, s / 2, s, 2);
    g.fillRect(s / 2, 0, 2, s);
  }),
};

const groundMaterials = new Map();
function groundMaterial(kind) {
  if (!groundMaterials.has(kind)) {
    const map = (GROUNDS[kind] || GROUNDS.grass)();
    map.repeat.set(1 / GROUND_TILE, 1 / GROUND_TILE);
    groundMaterials.set(kind, new THREE.MeshStandardMaterial({ map, roughness: 0.95 }));
  }
  return groundMaterials.get(kind);
}

// A flat polygon on the ground; its UVs are plan metres, like the floors'.
function flat(points, y, material) {
  const shape = new THREE.Shape(points.map(([x, z]) => new THREE.Vector2(x, -z)));
  const geo = new THREE.ShapeGeometry(shape);
  geo.rotateX(-Math.PI / 2);
  const mesh = new THREE.Mesh(geo, material);
  mesh.position.y = y;
  mesh.receiveShadow = true;
  return mesh;
}

// A box `length` long lying along the line from..to, standing on the ground.
function along(from, to, width, height, material, y = 0, r = 0.02) {
  const dx = to[0] - from[0];
  const dz = to[1] - from[1];
  const m = box(Math.hypot(dx, dz), height, width, material, { r });
  m.position.set((from[0] + to[0]) / 2, y, (from[1] + to[1]) / 2);
  m.rotation.y = Math.atan2(-dz, dx);
  return m;
}

const lerp = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];

function lineItem(o) {
  const g = new THREE.Group();
  const { from, to, height: h } = o;
  const len = Math.hypot(to[0] - from[0], to[1] - from[1]);
  if (o.type === 'wall') {
    g.add(along(from, to, 0.22, h, mat('#c4bcad', { rough: 0.95 })),
      along(from, to, 0.28, 0.06, mat('#8f887b', { rough: 0.9 }), h));
  } else if (o.type === 'hedge') {
    g.add(along(from, to, 0.7, h, mat('#3d6634', { rough: 1 }), 0, 0.25));
  } else if (o.type === 'fence') {
    const wood = mat('#7d6a54', { rough: 0.9 });
    const posts = Math.max(1, Math.ceil(len / 2));
    for (let i = 0; i <= posts; i++) {
      const [x, z] = lerp(from, to, i / posts);
      g.add(at(box(0.09, h, 0.09, wood), x, 0, z));
    }
    g.add(along(from, to, 0.04, 0.06, wood, 0.12), along(from, to, 0.04, 0.06, wood, h - 0.16),
      along(from, to, 0.02, h - 0.1, mat('#9a8670', { rough: 0.9, opacity: 0.72 }), 0.05, 0));
  } else {
    // gate: posts, a frame and bars
    const metal = mat('#2e3340', { rough: 0.45, metal: 0.5 });
    for (const p of [from, to]) g.add(at(box(0.14, h + 0.1, 0.14, metal), p[0], 0, p[1]));
    g.add(along(from, to, 0.05, 0.06, metal, 0.08), along(from, to, 0.05, 0.06, metal, h - 0.08));
    const bars = Math.min(80, Math.floor(len / 0.13));
    for (let i = 1; i < bars; i++) {
      const [x, z] = lerp(from, to, i / bars);
      g.add(at(box(0.025, h - 0.1, 0.025, metal, { r: 0 }), x, 0.08, z));
    }
  }
  return g;
}

function tree(o) {
  const rand = rng(Math.round(o.pos[0] * 73 + o.pos[1] * 37));
  const g = new THREE.Group();
  const t = treeShape(o);
  g.add(cyl(...t.trunkRadius, t.trunkHeight, mat('#5a4434', { rough: 1 }), 10));
  const leaves = new THREE.MeshStandardMaterial({ color: shade('#47763a', (rand() - 0.5) * 0.08), roughness: 1, flatShading: true });
  const canopy = new THREE.Mesh(new THREE.IcosahedronGeometry(t.crownRadius, 1), leaves);
  canopy.scale.set(1, t.crownSquash, 1);
  canopy.rotation.y = rand() * Math.PI;
  canopy.position.y = o.height - t.crownRadius * t.crownSquash;
  g.add(canopy);
  g.position.set(o.pos[0], 0, o.pos[1]);
  return g;
}

// A parked car or van, nose to +z before `rot` turns it.
function vehicle(o) {
  const [len, wid] = VEHICLE_SIZE[o.type];
  const h = o.height;
  const van = o.type === 'van';
  const paint = mat(o.color || (van ? '#e6e8eb' : '#3d5a80'), { rough: 0.35, metal: 0.3 });
  const glass = mat('#1c2533', { rough: 0.15, metal: 0.4 });
  const tyre = mat('#16181c', { rough: 0.9 });
  const clearance = 0.28;
  const g = new THREE.Group();
  if (van) {
    // A box body with a short sloping bonnet and a windscreen across the front.
    g.add(at(box(wid, h - clearance, len - 0.7, paint, { r: 0.12 }), 0, clearance, -0.35),
      at(box(wid - 0.04, 0.75, 0.8, paint, { r: 0.12 }), 0, clearance, len / 2 - 0.45),
      at(box(wid - 0.1, 0.62, 0.06, glass, { r: 0.02 }), 0, clearance + 0.95, len / 2 - 0.72));
  } else {
    const body = 0.62;
    g.add(at(box(wid, body, len, paint, { r: 0.16 }), 0, clearance, 0),
      at(box(wid - 0.16, h - clearance - body, len * 0.5, glass, { r: 0.14 }), 0, clearance + body - 0.02, -len * 0.06),
      at(box(wid - 0.12, 0.05, len * 0.42, paint, { r: 0.02 }), 0, h - 0.06, -len * 0.06));
  }
  for (const sx of [-1, 1]) {
    for (const sz of [-1, 1]) {
      const wheel = cyl(0.33, 0.33, 0.24, tyre, 18);
      wheel.geometry.translate(0, -0.12, 0);
      wheel.rotation.z = Math.PI / 2;
      wheel.position.set(sx * (wid / 2 - 0.1), 0.33, sz * (len / 2 - 0.85));
      g.add(wheel);
    }
  }
  g.position.set(o.pos[0], 0, o.pos[1]);
  g.rotation.y = THREE.MathUtils.degToRad(o.rot || 0);
  return g;
}

function rectItem(o) {
  const [x, z, w, d] = o.rect;
  if (o.type === 'paving') {
    const m = floorMesh({ x, z, w, d }, 'stone');
    m.position.y = -0.01;
    return m;
  }
  const g = new THREE.Group();
  g.add(at(box(w, o.height, d, mat('#d9d4ca', { rough: 0.95 })), x + w / 2, 0, z + d / 2),
    at(box(w + 0.3, 0.15, d + 0.3, mat('#4a505e', { rough: 0.8 })), x + w / 2, o.height, z + d / 2));
  return g;
}

/** The ground and everything outside; `roof` is kept apart so it can be left off. */
export function buildSite(config) {
  const group = new THREE.Group();
  const { minX, minZ, maxX, maxZ } = config.siteBounds;

  const surround = new THREE.Mesh(
    new THREE.PlaneGeometry(maxX - minX + MARGIN * 2, maxZ - minZ + MARGIN * 2).rotateX(-Math.PI / 2),
    mat('#29321f', { rough: 1 }));
  surround.position.set((minX + maxX) / 2, -0.03, (minZ + maxZ) / 2);
  surround.receiveShadow = true;
  group.add(surround);

  // The plot itself: inside the property line, or a lawn around the house when there is none.
  const b = config.bounds;
  const lot = config.site.boundary
    || [[b.minX - 4, b.minZ - 4], [b.maxX + 4, b.minZ - 4], [b.maxX + 4, b.maxZ + 4], [b.minX - 4, b.maxZ + 4]];
  group.add(flat(lot, -0.02, groundMaterial(config.site.ground)));
  if (config.site.boundary) {
    const line = mat('#e8e1cc', { rough: 0.7 });
    lot.forEach((p, i) => group.add(along(p, lot[(i + 1) % lot.length], 0.06, 0.03, line, -0.02, 0)));
  }

  for (const o of config.outdoor) {
    const shape = outdoorShape(o.type);
    group.add(shape === 'line' ? lineItem(o) : shape === 'point' ? tree(o) : shape === 'vehicle' ? vehicle(o) : rectItem(o));
  }
  shadows(group);
  surround.castShadow = false;

  const roof = new THREE.Group();
  if (config.roof) {
    const slate = mat('#3b404c', { rough: 0.85 });
    const over = EXT_T / 2 + EAVE;
    for (const r of config.rooms) {
      roof.add(at(box(r.w + over * 2, ROOF_T, r.d + over * 2, slate, { r: 0.01 }), r.x + r.w / 2, config.wallHeight, r.z + r.d / 2));
    }
    shadows(roof);
  }
  return { group, roof };
}
