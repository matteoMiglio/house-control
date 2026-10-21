// Loads and normalises a floor plan ("home.json"). Everything the 3D scene and the UI
// know about the apartment comes from this one document, so swapping the file swaps the home.

const LIGHT_TYPES = ['ceiling', 'pendant', 'spots', 'floor', 'table', 'strip', 'lantern', 'post', 'flood'];
const WALLS = ['north', 'south', 'east', 'west'];

export class ConfigError extends Error {}

export const LIGHT_KINDS = LIGHT_TYPES;
// Fixtures for outside: a wall lantern, a garden post light and a floodlight.
export const OUTDOOR_LIGHTS = ['lantern', 'post', 'flood'];
// Lamps hung on a wall face away from it, the way `rot` turns furniture.
export const WALL_LIGHTS = ['lantern', 'flood'];

/** A plain on/off lamp is a smart plug, unless it is plainly a light outside (a lantern, a post…). */
export const lampIcon = (cfg) => (cfg.capabilities.length || OUTDOOR_LIGHTS.includes(cfg.type) ? cfg.type : 'plug');

/** The built-in group for lamps and plugs outside the house: `"room": "outside"`. */
export const OUTSIDE = 'outside';
export const OUTSIDE_NAME = 'Outside';

// A lamp or an AC is real when it is linked to a device of a connected platform:
// `link: { service, id }` (Home Assistant, Philips Hue, Apple Home) or, for Smart Life,
// `tuya: { deviceId }`. An AC's `sensor: { service, id }` is a thermometer for its room.
export const LINK_FIELDS = ['tuya', 'link', 'sensor'];

export function linkOf(d) {
  if (d?.link?.service && d.link.id) return { service: d.link.service, id: d.link.id };
  if (d?.tuya?.deviceId) return { service: 'smartlife', id: d.tuya.deviceId };
  return null;
}

export const isLinked = (d) => Boolean(linkOf(d));

/** The platforms House Control can link to, in the order the editor lists them. */
export const SERVICES = {
  smartlife: { name: 'Smart Life', short: 'Smart Life' },
  homeassistant: { name: 'Home Assistant', short: 'Home Assistant' },
  hue: { name: 'Philips Hue', short: 'Hue' },
  homekit: { name: 'Apple Home', short: 'Apple Home' },
};
export const FLOOR_KINDS = ['oak', 'walnut', 'tile', 'stone'];

// Outside the house: lines (fences, walls…), trees, parked vehicles, and rectangles (sheds, paving).
export const OUTDOOR_LINES = ['fence', 'wall', 'hedge', 'gate'];
export const OUTDOOR_KINDS = [...OUTDOOR_LINES, 'tree', 'car', 'van', 'building', 'paving'];
export const OUTDOOR_HEIGHT = { fence: 1.8, wall: 2, hedge: 1.6, gate: 1.8, tree: 5, car: 1.5, van: 2.3, building: 2.6, paving: 0 };
// Length and width of a vehicle, in metres; it stands at `pos` and turns by `rot` like furniture.
export const VEHICLE_SIZE = { car: [4.5, 1.85], van: [5.3, 2.05] };
/** A tree as it is drawn (three/site.js) and as it blocks the view (coverage.js). */
export function treeShape(o) {
  const r = o.radius;
  const trunk = Math.max(0.6, o.height - r * 1.6);
  const squash = Math.min(1.25, (o.height - trunk) / (2 * r) + 0.15); // the crown's height over its width
  return {
    trunkHeight: trunk + r * 0.4, trunkRadius: [0.1 + r * 0.04, 0.14 + r * 0.05], // it reaches up into the crown
    crownRadius: r, crownSquash: squash, crownBottom: o.height - 2 * r * squash,
  };
}

export const outdoorShape = (type) => (OUTDOOR_LINES.includes(type) ? 'line' : type === 'tree' ? 'point'
  : VEHICLE_SIZE[type] ? 'vehicle' : 'rect');
export const GROUND_KINDS = ['grass', 'gravel', 'concrete'];

// The energy section's sensors, by what they report (EnergyRole in core/…/Energy.swift), and
// the kind of device each one takes. `signed`: the sensor's sign says which way the power
// flows, and platforms disagree about it, so the plan can say `invert`.
export const ENERGY_ROLES = {
  solar: { name: 'Solar production', kind: 'power' },
  grid: { name: 'Grid', kind: 'power', signed: true },
  load: { name: 'House consumption', kind: 'power' },
  battery: { name: 'Battery power', kind: 'power', signed: true },
  charge: { name: 'Battery charge', kind: 'battery' },
};
// One module of a panel array, in metres: across, and up the slope.
export const PANEL_MODULE = [1.0, 1.7];
// A camera's sensor when the plan does not say: 2K at 16:9.
export const CAMERA_RESOLUTION = [2560, 1440];

/** A camera as written in the plan, with the defaults filled in. */
export function withCameraDefaults(c) {
  return {
    ...c, name: c.name || c.id, y: c.y ?? 2.5, rot: c.rot ?? 0, tilt: c.tilt ?? 25, fov: c.fov ?? 100, range: c.range ?? 12,
    resolution: c.resolution ?? CAMERA_RESOLUTION,
  };
}

// The plan exactly as written on disk (the editor works on this form).
export async function loadRawConfig() {
  const boot = window.__HOUSE_BOOT__;
  if (boot?.config) return boot.config;
  const plan = (boot?.plan !== 'custom' && boot?.plan) || new URLSearchParams(location.search).get('plan') || 'home';
  const res = await fetch(`./plans/${plan}.json`);
  if (!res.ok) throw new ConfigError(`Plan "${plan}" not found (HTTP ${res.status})`);
  try {
    return await res.json();
  } catch (e) {
    throw new ConfigError(`Plan "${plan}" is not valid JSON: ${e.message}`);
  }
}

export async function loadConfig() {
  return normalize(await loadRawConfig());
}

function need(cond, msg) {
  if (!cond) throw new ConfigError(msg);
}

const isPoint = (p) => Array.isArray(p) && p.length === 2 && p.every(Number.isFinite);

export function normalize(raw) {
  need(raw && typeof raw === 'object', 'Plan must be a JSON object');
  need(Array.isArray(raw.rooms) && raw.rooms.length > 0, 'Plan needs at least one room in "rooms"');

  const ids = new Set();
  const unique = (id, what) => {
    need(typeof id === 'string' && id, `${what} is missing an "id"`);
    need(!ids.has(id), `Duplicate id "${id}"`);
    ids.add(id);
  };

  const rooms = raw.rooms.map((r) => {
    unique(r.id, 'A room');
    need(Array.isArray(r.rect) && r.rect.length === 4 && r.rect.every(Number.isFinite),
      `Room "${r.id}" needs "rect": [x, z, width, depth]`);
    const [x, z, w, d] = r.rect;
    need(w > 0 && d > 0, `Room "${r.id}" has an empty rect`);
    return { id: r.id, name: r.name || r.id, x, z, w, d, floor: r.floor || 'oak' };
  });
  const roomIds = new Set(rooms.map((r) => r.id));
  // A plan may still have a room of its own called "outside": then that room is meant.
  const outsideIsArea = !roomIds.has(OUTSIDE);

  const openings = (raw.openings || []).map((o, i) => {
    need(isPoint(o.from) && isPoint(o.to), `Opening #${i + 1} needs "from" and "to" points`);
    need(o.from[0] === o.to[0] || o.from[1] === o.to[1], `Opening #${i + 1} must be axis-aligned`);
    return { type: o.type || 'door', from: o.from, to: o.to, sill: o.sill ?? 0.85, head: o.head ?? 2.1 };
  });

  const lights = (raw.lights || []).map((l) => {
    unique(l.id, 'A light');
    need(roomIds.has(l.room) || (outsideIsArea && l.room === OUTSIDE),
      `Light "${l.id}" refers to unknown room "${l.room}" (or use "${OUTSIDE}" for a lamp outside the house)`);
    need(LIGHT_TYPES.includes(l.type), `Light "${l.id}" has unknown type "${l.type}" (use ${LIGHT_TYPES.join(', ')})`);
    need(isPoint(l.pos), `Light "${l.id}" needs "pos": [x, z]`);
    return {
      ...l,
      name: l.name || l.id,
      rot: l.rot || 0,
      capabilities: l.capabilities || [], // plain smart plugs: on/off only
    };
  });

  const acs = (raw.acs || []).map((a) => {
    unique(a.id, 'An AC');
    need(roomIds.has(a.room), `AC "${a.id}" refers to unknown room "${a.room}"`);
    need(isPoint(a.pos), `AC "${a.id}" needs "pos": [x, z]`);
    need(WALLS.includes(a.wall), `AC "${a.id}" needs "wall": one of ${WALLS.join(', ')}`);
    return { ...a, name: a.name || a.id, y: a.y ?? 2.2, min: a.min ?? 16, max: a.max ?? 30 };
  });

  const scenes = (raw.scenes || []).map((s) => {
    need(typeof s.id === 'string' && s.id, 'A scene is missing an "id"');
    return { id: s.id, name: s.name || s.id, icon: s.icon || 'sun', lights: s.lights || {}, acs: s.acs || {} };
  });

  const outdoor = (raw.outdoor || []).map((o, i) => {
    const where = `Outdoor item #${i + 1}`;
    need(OUTDOOR_KINDS.includes(o.type), `${where} has unknown type "${o.type}" (use ${OUTDOOR_KINDS.join(', ')})`);
    const shape = outdoorShape(o.type);
    if (shape === 'line') {
      need(isPoint(o.from) && isPoint(o.to), `${where} (${o.type}) needs "from" and "to" points`);
      need(o.from[0] !== o.to[0] || o.from[1] !== o.to[1], `${where} (${o.type}) has no length`);
    } else if (shape === 'point' || shape === 'vehicle') {
      need(isPoint(o.pos), `${where} (${o.type}) needs "pos": [x, z]`);
      need(o.rot == null || Number.isFinite(o.rot), `${where} (${o.type}) has a "rot" that is not a number`);
    } else {
      need(Array.isArray(o.rect) && o.rect.length === 4 && o.rect.every(Number.isFinite) && o.rect[2] > 0 && o.rect[3] > 0,
        `${where} (${o.type}) needs "rect": [x, z, width, depth]`);
    }
    const height = o.height ?? OUTDOOR_HEIGHT[o.type];
    // A vehicle's radius is half its length: what it can reach whichever way it is turned.
    const radius = VEHICLE_SIZE[o.type] ? VEHICLE_SIZE[o.type][0] / 2 : o.radius ?? 1.5;
    need(Number.isFinite(height) && (o.type === 'paving' ? height >= 0 : height > 0), `${where} (${o.type}) needs a "height" in metres above 0`);
    need(Number.isFinite(radius) && radius > 0, `${where} (${o.type}) needs a "radius" in metres above 0`);
    return { ...o, height, radius };
  });

  let boundary = null;
  if (raw.site?.boundary != null) {
    boundary = raw.site.boundary;
    need(Array.isArray(boundary) && boundary.length >= 3 && boundary.every(isPoint),
      'The property line ("site.boundary") needs at least three [x, z] corners');
  }
  const site = { boundary, ground: GROUND_KINDS.includes(raw.site?.ground) ? raw.site.ground : 'grass' };

  const cameras = (raw.cameras || []).map((c) => {
    unique(c.id, 'A camera');
    need(isPoint(c.pos), `Camera "${c.id}" needs "pos": [x, z]`);
    const cam = withCameraDefaults(c);
    need(Number.isFinite(cam.fov) && cam.fov >= 20 && cam.fov <= 180, `Camera "${c.id}" needs a "fov" between 20 and 180 degrees`);
    need(Number.isFinite(cam.range) && cam.range > 0, `Camera "${c.id}" needs a "range" in metres`);
    need([cam.y, cam.rot, cam.tilt].every(Number.isFinite), `Camera "${c.id}" has a height, rotation or tilt that is not a number`);
    need(isPoint(cam.resolution) && cam.resolution.every((v) => v > 0), `Camera "${c.id}" needs "resolution": [width, height] in pixels`);
    return cam;
  });

  const energy = raw.energy == null ? null : normalizeEnergy(raw.energy, roomIds);

  const minX = Math.min(...rooms.map((r) => r.x));
  const minZ = Math.min(...rooms.map((r) => r.z));
  const maxX = Math.max(...rooms.map((r) => r.x + r.w));
  const maxZ = Math.max(...rooms.map((r) => r.z + r.d));

  // Everything outside counts too when the whole site is shown.
  const xs = [minX, maxX];
  const zs = [minZ, maxZ];
  const take = ([x, z]) => { xs.push(x); zs.push(z); };
  // Without a property line the house stands on a lawn a few metres wide (three/site.js).
  for (const p of boundary || [[minX - 4, minZ - 4], [maxX + 4, maxZ + 4]]) take(p);
  for (const o of outdoor) {
    if (o.from) { take(o.from); take(o.to); }
    else if (o.pos) { take([o.pos[0] - o.radius, o.pos[1] - o.radius]); take([o.pos[0] + o.radius, o.pos[1] + o.radius]); }
    else { take(o.rect); take([o.rect[0] + o.rect[2], o.rect[1] + o.rect[3]]); }
  }
  for (const c of cameras) take(c.pos);
  if (energy?.battery) take(energy.battery.pos);
  if (outsideIsArea) for (const l of lights) if (l.room === OUTSIDE) take(l.pos);

  return {
    name: raw.name || 'Home',
    wallHeight: raw.wallHeight ?? 2.6,
    interiorWallHeight: raw.interiorWallHeight ?? 1.25,
    camera: { azimuth: raw.camera?.azimuth ?? 34, elevation: raw.camera?.elevation ?? 47 },
    outdoorTemp: raw.outdoorTemp ?? 27,
    rooms,
    openings,
    furniture: raw.furniture || [],
    lights,
    acs,
    scenes,
    // What the panel lists devices by: the rooms, then the outside when a lamp is out there.
    groups: [...rooms.map((r) => ({ id: r.id, name: r.name })),
      ...(outsideIsArea && lights.some((l) => l.room === OUTSIDE) ? [{ id: OUTSIDE, name: OUTSIDE_NAME, outside: true }] : [])],
    // Whether "outside" means the built-in group (and not a room someone called that).
    outsideArea: outsideIsArea,
    roof: raw.roof !== false,
    site,
    outdoor,
    cameras,
    energy,
    bounds: { minX, minZ, maxX, maxZ },
    siteBounds: { minX: Math.min(...xs), minZ: Math.min(...zs), maxX: Math.max(...xs), maxZ: Math.max(...zs) },
  };
}

// Solar panels on the roof, a home battery, and the sensors that report the power flow. Every
// part is optional: panels without a battery, a battery and a grid meter without panels…
function normalizeEnergy(e, roomIds) {
  const isObject = (v) => v && typeof v === 'object' && !Array.isArray(v);
  need(isObject(e), 'The energy section ("energy") must be an object');
  need(e.panels == null || Array.isArray(e.panels), '"energy.panels" must be a list of panel arrays');
  const panels = (e.panels || []).map((p, i) => {
    const where = `Solar panel array #${i + 1}`;
    need(isPoint(p?.pos), `${where} needs "pos": [x, z]`);
    need(isPoint(p.size) && p.size[0] > 0 && p.size[1] > 0, `${where} needs "size": [width, depth] in metres above 0`);
    need(p.rot == null || Number.isFinite(p.rot), `${where} has a "rot" that is not a number`);
    return { pos: p.pos, size: p.size, rot: p.rot || 0 };
  });

  let battery = null;
  if (e.battery != null) {
    const b = e.battery;
    need(isObject(b) && isPoint(b.pos), 'The battery ("energy.battery") needs "pos": [x, z]');
    need(b.room == null || roomIds.has(b.room), `The battery refers to unknown room "${b.room}" (leave "room" out for one outside)`);
    need(b.rot == null || Number.isFinite(b.rot), 'The battery has a "rot" that is not a number');
    battery = { pos: b.pos, room: b.room ?? null, rot: b.rot || 0 };
  }

  need(e.sensors == null || isObject(e.sensors), '"energy.sensors" must be an object: role → { service, id }');
  const sensors = {};
  for (const [role, s] of Object.entries(e.sensors || {})) {
    need(role in ENERGY_ROLES, `Energy sensor "${role}" is not one of ${Object.keys(ENERGY_ROLES).join(', ')}`);
    need(isObject(s) && typeof s.service === 'string' && typeof s.id === 'string', `Energy sensor "${role}" needs "service" and "id"`);
    need(s.invert == null || typeof s.invert === 'boolean', `Energy sensor "${role}" has an "invert" that is not true or false`);
    if (s.service && s.id) sensors[role] = { service: s.service, id: s.id, invert: Boolean(s.invert) };
  }

  need(e.peak == null || (Number.isFinite(e.peak) && e.peak > 0), 'The panels\' peak ("energy.peak") must be a power in W above 0');
  return { panels, battery, sensors, peak: e.peak ?? null };
}
