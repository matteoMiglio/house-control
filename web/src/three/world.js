// The 3D stage: renderer, camera rig, picking and the per-frame animation loop.
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { buildHouse } from './house.js';
import { buildSite } from './site.js';
import { CameraUnit, cameraColor, cameraQuaternion, halfAngles } from './cctv.js';
import { coverage, coverageCanvas } from '../coverage.js';
import { OUTSIDE } from '../config.js';
import { buildFurniture } from './furniture.js';
import { LightUnit } from './lights.js';
import { ACUnit } from './ac.js';

export const STAGE_BG = '#0a0e1a';

const rad = THREE.MathUtils.degToRad;
const clamp = THREE.MathUtils.clamp;
const ORBIT_AZ = 40;       // degrees of freedom either side of the plan's default view
const EL_MIN = 26;
const EL_MAX = 70;
const ZOOM_MIN = 0.55;     // closest
const ZOOM_MAX = 1.2;
// Outside, the house can be walked around and looked at from close to the ground.
const OUT_EL_MIN = 6;
const OUT_EL_MAX = 84;
const OUT_EL = 28;
const OUT_ZOOM_MIN = 0.3;
const OUT_ZOOM_MAX = 1.6;

// Seen through a security camera: what lies outside its picture is dimmed and the edge drawn.
const PictureFrame = {
  uniforms: { tDiffuse: { value: null }, rect: { value: new THREE.Vector4(0, 0, 1, 1) }, res: { value: new THREE.Vector2(1, 1) } },
  vertexShader: 'varying vec2 vUv; void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
  fragmentShader: `
    uniform sampler2D tDiffuse; uniform vec4 rect; uniform vec2 res; varying vec2 vUv;
    void main() {
      vec4 c = texture2D(tDiffuse, vUv);
      vec2 p = vUv * res; vec2 lo = rect.xy * res; vec2 hi = rect.zw * res;
      float inside = step(lo.x, p.x) * step(p.x, hi.x) * step(lo.y, p.y) * step(p.y, hi.y);
      float d = min(min(p.x - lo.x, hi.x - p.x), min(p.y - lo.y, hi.y - p.y));
      c.rgb = mix(c.rgb * 0.05, c.rgb, inside); // linear light: this is about a quarter as bright on screen
      c.rgb = mix(c.rgb, vec3(1.0), inside * (1.0 - smoothstep(0.0, 2.0, d)) * 0.6);
      gl_FragColor = c;
    }`,
};

export function createWorld(canvas, config, store, { onHover, onPick, background = STAGE_BG, outside: startOutside = false }) {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, alpha: false, powerPreference: 'high-performance' });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.05;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFShadowMap;
  renderer.shadowMap.autoUpdate = false; // the model is static: shadow maps are rendered once

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(background);

  const camera = new THREE.PerspectiveCamera(24, 1, 0.5, 120);

  const { minX, minZ, maxX, maxZ } = config.bounds;
  const H = config.wallHeight;
  const center = new THREE.Vector3((minX + maxX) / 2, 0, (minZ + maxZ) / 2);
  const span = Math.max(maxX - minX, maxZ - minZ);
  const sb = config.siteBounds;
  const siteCenter = new THREE.Vector3((sb.minX + sb.maxX) / 2, 0, (sb.minZ + sb.maxZ) / 2);
  const siteSpan = Math.max(sb.maxX - sb.minX, sb.maxZ - sb.minZ, span);
  // A big plot is framed from far away: the far end of it must not be clipped.
  camera.far = Math.max(120, siteSpan * 8);

  const baseAz = config.camera.azimuth;
  const camDir = new THREE.Vector3(Math.sin(rad(baseAz)), 0, Math.cos(rad(baseAz)));

  /* ---------- content ---------- */

  // The house is built one of two ways: cut open to look into the rooms, or whole, standing on
  // its site, for the view from outside and through a security camera.
  let outside = false;
  let pov = null; // the id of the camera looked through
  let house = null;
  let site = null;
  // What the cameras see, drawn on the ground outside: all of them (null) or one camera's id.
  let coverageOf = null;
  let coverageShown = true;
  let coverageMesh = null;
  const coverageMaps = new Map();
  scene.add(buildFurniture(config.furniture));

  const lights = new Map();
  for (const cfg of config.lights) {
    const unit = new LightUnit(cfg, H);
    lights.set(cfg.id, unit);
    scene.add(unit.group);
  }
  const acs = new Map();
  for (const cfg of config.acs) {
    const unit = new ACUnit(cfg);
    acs.set(cfg.id, unit);
    scene.add(unit.group);
  }
  const cameras = new Map();
  config.cameras.forEach((cfg, i) => {
    const unit = new CameraUnit(cfg, cameraColor(i));
    cameras.set(cfg.id, unit);
    scene.add(unit.group, unit.view);
  });
  const outdoorLights = config.outsideArea ? [...lights.values()].filter((u) => u.cfg.room === OUTSIDE) : [];
  // Cut open, the model has no ground around it: only cameras on the house itself are shown.
  const onHouse = (cfg) => cfg.pos[0] > minX - 0.4 && cfg.pos[0] < maxX + 0.4 && cfg.pos[1] > minZ - 0.4 && cfg.pos[1] < maxZ + 0.4;
  let hitTargets = [];

  // Night-time ambience: enough to read the model with every lamp off.
  const night = new THREE.Group();
  scene.add(night);
  night.add(new THREE.HemisphereLight(0x8ea6ff, 0x0b0e17, 0.42));
  const moon = new THREE.DirectionalLight(0xa9c0ff, 0.6);
  // Steep and coming from the viewer's side, so the faces we look at stay readable.
  moon.position.copy(center).add(new THREE.Vector3(camDir.x * 3.2 + 1.5, 10, camDir.z * 3.2 - 1.5));
  moon.target.position.copy(center);
  moon.castShadow = true;
  moon.shadow.mapSize.set(2048, 2048);
  const sc = moon.shadow.camera;
  sc.left = sc.bottom = -span * 0.85;
  sc.right = sc.top = span * 0.85;
  sc.near = 1;
  sc.far = 30;
  moon.shadow.bias = -0.0008;
  moon.shadow.normalBias = 0.04;
  moon.shadow.radius = 4;
  night.add(moon, moon.target);

  // Outside it is early evening: light enough to read the façades and the garden, dark enough
  // for the lamps outside to show.
  const day = new THREE.Group();
  day.visible = false;
  scene.add(day);
  day.add(new THREE.HemisphereLight(0xc4d2f0, 0x2e3828, 0.75));
  const sun = new THREE.DirectionalLight(0xffd9b0, 1.25);
  sun.position.copy(siteCenter).add(new THREE.Vector3(siteSpan * 0.45, siteSpan * 0.7 + 8, siteSpan * 0.3));
  sun.target.position.copy(siteCenter);
  sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048);
  const ssc = sun.shadow.camera;
  ssc.left = ssc.bottom = -siteSpan * 0.75 - 4;
  ssc.right = ssc.top = siteSpan * 0.75 + 4;
  ssc.near = 1;
  ssc.far = siteSpan * 3 + 30;
  sun.shadow.bias = -0.0006;
  sun.shadow.normalBias = 0.04;
  day.add(sun, sun.target);
  const fog = new THREE.Fog(background, siteSpan * 2.2, siteSpan * 5 + 20);

  const povCamera = new THREE.PerspectiveCamera(60, 1, 0.05, 250);
  const flip = new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), Math.PI); // cameras look down -z

  /* ---------- post-processing ---------- */

  const target = new THREE.WebGLRenderTarget(4, 4, { type: THREE.HalfFloatType, samples: 4 });
  const composer = new EffectComposer(renderer, target);
  const renderPass = new RenderPass(scene, camera);
  composer.addPass(renderPass);
  const bloom = new UnrealBloomPass(new THREE.Vector2(4, 4), 0.34, 0.5, 1.0);
  composer.addPass(bloom);
  const frame = new ShaderPass(PictureFrame);
  frame.enabled = false;
  composer.addPass(frame);
  composer.addPass(new OutputPass());

  /* ---------- camera rig ---------- */

  const rig = {
    az: baseAz, el: config.camera.elevation, dist: 30, target: center.clone(),
    goal: { az: baseAz, el: config.camera.elevation, dist: 30, target: center.clone() },
    zoom: 1, focus: null,
  };
  let width = 1;
  let height = 1;
  let topInset = 0;    // pixels at the top covered by the header
  let bottomInset = 0; // pixels at the bottom covered by the panel

  const v = new THREE.Vector3();
  const right = new THREE.Vector3();
  const up = new THREE.Vector3();
  const fwd = new THREE.Vector3();

  function basis(az, el) {
    const a = rad(az);
    const e = rad(el);
    fwd.set(-Math.sin(a) * Math.cos(e), -Math.sin(e), -Math.cos(a) * Math.cos(e));
    right.set(Math.cos(a), 0, -Math.sin(a));
    up.crossVectors(right, fwd);
  }

  // Smallest distance at which `box` fits the usable part of the viewport.
  function fitDistance(box, az, el, fill) {
    basis(az, el);
    const c = box.getCenter(new THREE.Vector3());
    const usableH = Math.max(0.3, (height - topInset - bottomInset) / height);
    const tanV = Math.tan(rad(camera.fov / 2)) * fill * usableH;
    const tanH = Math.tan(rad(camera.fov / 2)) * camera.aspect * fill;
    let dist = 0;
    for (let i = 0; i < 8; i++) {
      v.set(i & 1 ? box.max.x : box.min.x, i & 2 ? box.max.y : box.min.y, i & 4 ? box.max.z : box.min.z).sub(c);
      const depth = v.dot(fwd);
      dist = Math.max(dist, Math.abs(v.dot(right)) / tanH - depth, Math.abs(v.dot(up)) / tanV - depth);
    }
    return { dist, center: c };
  }

  function frameGoal() {
    const f = rig.focus;
    let box;
    let fill = 0.96;
    const r = f?.kind === 'room' && config.rooms.find((x) => x.id === f.id);
    if (r) {
      box = new THREE.Box3(new THREE.Vector3(r.x, 0, r.z), new THREE.Vector3(r.x + r.w, H * 0.75, r.z + r.d));
      fill = 0.84;
    } else if (f?.kind === 'ac') {
      const unit = acs.get(f.id);
      const p = unit.group.position;
      const out = new THREE.Vector3(0, 0, 1).applyQuaternion(unit.group.quaternion);
      box = new THREE.Box3().setFromCenterAndSize(
        new THREE.Vector3(p.x + out.x * 1.3, 1.25, p.z + out.z * 1.3), new THREE.Vector3(3.6, 2.6, 3.6));
      fill = 0.92;
    } else if (f?.kind === 'camera' && cameras.has(f.id)) {
      const unit = cameras.get(f.id);
      box = new THREE.Box3().setFromPoints([unit.eye(), ...unit.ground.map(([x, z]) => new THREE.Vector3(x, 0, z))]);
      fill = 0.9;
    } else if (outside) {
      box = new THREE.Box3(new THREE.Vector3(sb.minX, 0, sb.minZ), new THREE.Vector3(sb.maxX, H, sb.maxZ));
    } else {
      box = new THREE.Box3(new THREE.Vector3(minX, 0, minZ), new THREE.Vector3(maxX, H * 0.8, maxZ));
    }
    const { dist, center: c } = fitDistance(box, rig.goal.az, rig.goal.el, fill);
    rig.goal.dist = dist * rig.zoom;
    rig.goal.target.copy(c);
  }

  function updateRig(dt, instant = false) {
    const k = instant ? 1 : 1 - Math.exp(-dt * 5.5);
    const g = rig.goal;
    const delta = Math.abs(g.az - rig.az) + Math.abs(g.el - rig.el) + Math.abs(g.dist - rig.dist) * 2
      + rig.target.distanceTo(g.target) * 4;
    rig.az += (g.az - rig.az) * k;
    rig.el += (g.el - rig.el) * k;
    rig.dist += (g.dist - rig.dist) * k;
    rig.target.lerp(g.target, k);
    basis(rig.az, rig.el);
    camera.position.copy(rig.target).addScaledVector(fwd, -rig.dist);
    camera.up.set(0, 1, 0);
    camera.lookAt(rig.target);
    return delta > 0.002;
  }

  /* ---------- state sync ---------- */

  /* ---------- inside / outside ---------- */

  function buildShell() {
    const whole = outside || Boolean(pov);
    if (house && house.whole === whole) return;
    if (house) {
      scene.remove(house.group);
      house.group.traverse((o) => o.geometry?.dispose());
    }
    house = { ...buildHouse(config, whole ? null : camDir), whole };
    scene.add(house.group);
    if (whole && !site) {
      site = buildSite(config);
      scene.add(site.group, site.roof);
    }
    if (site) site.group.visible = site.roof.visible = whole;
    night.visible = !whole;
    day.visible = whole;
    scene.fog = whole ? fog : null;
    shadowFrames = 3;
  }

  // Cameras and lamps outside the house only show when the ground around it does (or they hang on it).
  function showCameras() {
    for (const unit of cameras.values()) {
      unit.group.visible = unit.id !== pov && (outside || onHouse(unit.cfg));
      unit.view.visible = outside && !pov;
    }
    for (const unit of outdoorLights) unit.group.visible = house.whole || onHouse(unit.cfg);
    drawCoverage();
    // Under the roof the rooms and their devices cannot be seen, so they cannot be picked either.
    const indoors = house.whole && config.roof ? []
      : [...[...lights.values()].filter((u) => !outdoorLights.includes(u)).map((u) => u.hit), ...[...acs.values()].map((u) => u.hit), ...house.floors];
    hitTargets = [...[...cameras.values(), ...outdoorLights].filter((u) => u.group.visible).map((u) => u.hit), ...indoors];
  }

  function drawCoverage() {
    if (coverageMesh) {
      scene.remove(coverageMesh);
      coverageMesh.geometry.dispose();
      coverageMesh.material.map.dispose();
      coverageMesh.material.dispose();
      coverageMesh = null;
    }
    if (!outside || pov || !coverageShown || !config.cameras.length) return;
    const key = coverageOf ?? '*';
    if (!coverageMaps.has(key)) {
      coverageMaps.set(key, coverage(config, { cameras: coverageOf ? config.cameras.filter((c) => c.id === coverageOf) : config.cameras }));
    }
    const map = coverageMaps.get(key);
    const texture = new THREE.CanvasTexture(coverageCanvas(map, { blind: !coverageOf }));
    texture.colorSpace = THREE.SRGBColorSpace;
    const w = map.cols * map.size;
    const d = map.rows * map.size;
    coverageMesh = new THREE.Mesh(new THREE.PlaneGeometry(w, d).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({
      map: texture, transparent: true, depthWrite: false, toneMapped: false,
      polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
    }));
    coverageMesh.position.set(map.x0 + w / 2, 0.02, map.z0 + d / 2);
    coverageMesh.renderOrder = 2;
    scene.add(coverageMesh);
  }

  // The picture of the camera looked through, fitted into the part of the stage that is not covered.
  function aimPOV() {
    const unit = cameras.get(pov);
    if (!unit) return;
    const { h: ha, v: va } = halfAngles(unit.cfg);
    const aspect = Math.tan(ha) / Math.tan(va);
    const usable = Math.max(40, height - topInset - bottomInset);
    let w = width * 0.94;
    let hh = w / aspect;
    if (hh > usable * 0.92) { hh = usable * 0.92; w = hh * aspect; }
    povCamera.aspect = width / height;
    povCamera.fov = THREE.MathUtils.radToDeg(2 * Math.atan(Math.tan(va) * height / hh));
    povCamera.setViewOffset(width, height, 0, -(topInset - bottomInset) / 2, width, height);
    povCamera.updateProjectionMatrix();
    unit.eye(povCamera.position);
    cameraQuaternion(unit.cfg, povCamera.quaternion).multiply(flip);
    const cy = topInset + usable / 2;
    frame.uniforms.rect.value.set((width - w) / 2 / width, 1 - (cy + hh / 2) / height, (width + w) / 2 / width, 1 - (cy - hh / 2) / height);
    const pr = renderer.getPixelRatio();
    frame.uniforms.res.value.set(width * pr, height * pr);
  }

  function setPov(id) {
    const next = id && cameras.has(id) ? id : null;
    if (next === pov) return;
    pov = next;
    buildShell();
    showCameras();
    renderPass.camera = pov ? povCamera : camera;
    frame.enabled = Boolean(pov);
    if (pov) { setHover(null); aimPOV(); }
    wake(3);
  }

  function setOutside(on) {
    if (on === outside) return;
    outside = on;
    buildShell();
    showCameras();
    rig.zoom = 1;
    rig.focus = null;
    if (outside) {
      rig.goal.el = OUT_EL;
    } else {
      // Back inside the orbit is fenced in again: come back round the short way.
      rig.az = baseAz + ((((rig.az - baseAz) % 360) + 540) % 360) - 180;
      rig.goal.az = baseAz;
      rig.goal.el = config.camera.elevation;
    }
    frameGoal();
    wake(3);
  }

  function syncAll(opts = {}) {
    let i = 0;
    for (const [id, unit] of lights) {
      unit.apply(store.state.lights[id], { ...opts, delay: opts.stagger ? 0.25 + i++ * 0.06 : 0 });
    }
    for (const [id, unit] of acs) unit.apply(store.state.acs[id], opts);
    wake();
  }

  const unsubscribe = store.on((change) => {
    if (change.type === 'tick') return;
    if (change.type === 'light') lights.get(change.id).apply(store.state.lights[change.id]);
    else if (change.type === 'ac') acs.get(change.id).apply(store.state.acs[change.id]);
    else syncAll();
    wake();
  });

  /* ---------- picking ---------- */

  const raycaster = new THREE.Raycaster();
  const ndc = new THREE.Vector2();
  let hovered = null;
  let drag = null;

  function pick(ev) {
    const r = canvas.getBoundingClientRect();
    ndc.set(((ev.clientX - r.left) / r.width) * 2 - 1, -((ev.clientY - r.top) / r.height) * 2 + 1);
    raycaster.setFromCamera(ndc, camera);
    const hits = raycaster.intersectObjects(hitTargets, false);
    if (!hits.length) return null;
    // Devices win over the floor they stand on.
    const device = hits.find((h) => h.object.userData.kind !== 'room');
    return (device || hits[0]).object.userData;
  }

  function unitOf(t) {
    return t?.kind === 'light' ? lights.get(t.id) : t?.kind === 'ac' ? acs.get(t.id) : t?.kind === 'camera' ? cameras.get(t.id) : null;
  }

  function screenAnchor(t) {
    const unit = unitOf(t);
    if (!unit) return null;
    unit.anchor(v).project(camera);
    return { x: (v.x * 0.5 + 0.5) * width, y: (-v.y * 0.5 + 0.5) * height };
  }

  function setHover(t) {
    const same = hovered?.kind === t?.kind && hovered?.id === t?.id;
    if (same) return;
    const prev = unitOf(hovered);
    if (prev) prev.hoverGoal = 0;
    hovered = t && t.kind !== 'room' ? t : null;
    const next = unitOf(hovered);
    if (next) next.hoverGoal = 1;
    canvas.style.cursor = hovered ? 'pointer' : drag?.moved ? 'grabbing' : 'grab';
    onHover(hovered ? { ...hovered, ...screenAnchor(hovered) } : null);
    wake();
  }

  // Two fingers pinch to zoom, the way the scroll wheel does with a mouse.
  const fingers = new Map();
  let pinch = null;
  const spread = () => {
    const [a, b] = [...fingers.values()];
    return Math.max(1, Math.hypot(a.x - b.x, a.y - b.y));
  };

  canvas.addEventListener('pointerdown', (ev) => {
    if (pov) return; // a camera's picture holds still
    canvas.setPointerCapture(ev.pointerId);
    fingers.set(ev.pointerId, { x: ev.clientX, y: ev.clientY });
    if (fingers.size === 2) {
      pinch = { spread: spread(), zoom: rig.zoom };
      drag = null;
      setHover(null);
      return;
    }
    if (fingers.size > 2) return;
    drag = { x: ev.clientX, y: ev.clientY, az: rig.goal.az, el: rig.goal.el, moved: false };
  });
  canvas.addEventListener('pointermove', (ev) => {
    if (fingers.has(ev.pointerId)) fingers.set(ev.pointerId, { x: ev.clientX, y: ev.clientY });
    if (pinch) {
      if (fingers.size >= 2) {
        rig.zoom = clampZoom(pinch.zoom * pinch.spread / spread());
        frameGoal();
        wake();
      }
      return;
    }
    if (drag) {
      const dx = ev.clientX - drag.x;
      const dy = ev.clientY - drag.y;
      if (!drag.moved && Math.hypot(dx, dy) > 5) { drag.moved = true; setHover(null); canvas.style.cursor = 'grabbing'; }
      if (drag.moved) {
        rig.goal.az = outside ? drag.az - dx * 0.35 : clamp(drag.az - dx * 0.35, baseAz - ORBIT_AZ, baseAz + ORBIT_AZ);
        rig.goal.el = outside ? clamp(drag.el + dy * 0.3, OUT_EL_MIN, OUT_EL_MAX) : clamp(drag.el + dy * 0.3, EL_MIN, EL_MAX);
        frameGoal();
        wake();
      }
      return;
    }
    if (!pov) setHover(pick(ev));
  });
  const release = (ev) => {
    fingers.delete(ev.pointerId);
    if (pinch) { if (!fingers.size) pinch = null; return; } // lifting after a pinch picks nothing
    if (!drag) return;
    const wasDrag = drag.moved;
    drag = null;
    canvas.style.cursor = 'grab';
    if (wasDrag) return;
    const t = pick(ev);
    if (!t) { onPick(null); return; }
    if (t.kind === 'light') lights.get(t.id).bump();
    onPick(t);
    wake();
  };
  canvas.addEventListener('pointerup', release);
  canvas.addEventListener('pointercancel', (ev) => {
    fingers.delete(ev.pointerId);
    if (!fingers.size) pinch = null;
    drag = null;
  });
  canvas.addEventListener('pointerleave', () => { if (!drag) setHover(null); });
  const clampZoom = (z) => (outside ? clamp(z, OUT_ZOOM_MIN, OUT_ZOOM_MAX) : clamp(z, ZOOM_MIN, ZOOM_MAX));
  canvas.addEventListener('wheel', (ev) => {
    ev.preventDefault();
    if (pov) return;
    rig.zoom = clampZoom(rig.zoom * Math.exp(ev.deltaY * 0.0015));
    frameGoal();
    wake();
  }, { passive: false });
  canvas.style.cursor = 'grab';

  /* ---------- loop ---------- */

  let raf = 0;
  let last = 0;
  let awake = 0;       // frames still owed after the last change
  let running = false;
  let shadowFrames = 3;

  function wake(frames = 2) {
    awake = Math.max(awake, frames);
    if (running && !raf) { last = performance.now(); raf = requestAnimationFrame(tick); }
  }

  function tick(now) {
    raf = 0;
    const dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    let active = updateRig(dt);
    for (const unit of lights.values()) active = unit.update(dt) || active;
    for (const unit of acs.values()) active = unit.update(dt) || active;
    for (const unit of cameras.values()) active = unit.update(dt) || active;
    if (shadowFrames > 0) { renderer.shadowMap.needsUpdate = true; shadowFrames--; active = true; }
    if (active || awake > 0) {
      composer.render(dt);
      awake = Math.max(0, awake - 1);
      if (hovered && active) onHover({ ...hovered, ...screenAnchor(hovered) });
    }
    if (running && (active || awake > 0)) raf = requestAnimationFrame(tick);
  }

  function resize() {
    const r = canvas.getBoundingClientRect();
    if (!r.width || !r.height) return;
    width = r.width;
    height = r.height;
    const pr = Math.min(window.devicePixelRatio || 1, 2);
    renderer.setPixelRatio(pr);
    renderer.setSize(width, height, false);
    composer.setPixelRatio(pr);
    composer.setSize(width, height);
    camera.aspect = width / height;
    // Centre the model between header and panel by shifting the projection window.
    camera.setViewOffset(width, height, 0, -(topInset - bottomInset) / 2, width, height);
    camera.updateProjectionMatrix();
    aimPOV();
    frameGoal();
    wake(3);
  }

  const world = {
    lights,
    acs,
    cameras,

    get outside() { return outside; },
    /** The whole house on its site, seen from outside — or cut open to look into the rooms. */
    setOutside,
    get pov() { return pov; },
    /** Shows the picture of a security camera, or (null) the model again. */
    lookThrough: setPov,
    /** Whether the coverage is drawn at all: not while the lamps outside are what is being looked at. */
    setCoverageShown(on) {
      if (on === coverageShown) return;
      coverageShown = on;
      drawCoverage();
      wake();
    },
    /** Draws on the ground what all the cameras (null) or one of them can see, outside. */
    showCoverage(id = null) {
      const next = id && cameras.has(id) ? id : null;
      if (next === coverageOf) return;
      coverageOf = next;
      drawCoverage();
      wake();
    },

    setInsets(top, bottom) { topInset = top; bottomInset = bottom; resize(); },
    resize,

    focus(next) {
      if (next?.kind === 'camera') { setPov(next.id); return; }
      setPov(null);
      rig.focus = next;
      rig.zoom = 1;
      if (!outside) {
        rig.goal.az = baseAz + (next?.kind === 'ac' ? (WALL_SIDE[acs.get(next.id).cfg.wall] ?? 0) : 0);
        rig.goal.el = next?.kind === 'ac' ? 30 : config.camera.elevation;
      }
      frameGoal();
      wake();
    },

    // Camera sweep + staggered light-up, played whenever the panel appears.
    intro() {
      syncAll({ instant: true });
      for (const unit of lights.values()) { unit.level = 0; unit.write(); }
      for (const unit of acs.values()) unit.power = 0;
      syncAll({ stagger: true });
      frameGoal();
      rig.az = rig.goal.az - 16;
      rig.el = rig.goal.el + 9;
      rig.dist = rig.goal.dist * 1.28;
      rig.target.copy(rig.goal.target);
      wake(4);
    },

    setRunning(on) {
      running = on;
      if (on) wake(4);
      else if (raf) { cancelAnimationFrame(raf); raf = 0; }
    },

    dispose() {
      unsubscribe();
      for (const unit of cameras.values()) unit.dispose();
      coverageOf = null;
      outside = false;
      drawCoverage();
      running = false;
      if (raf) cancelAnimationFrame(raf);
      raf = 0;
      composer.dispose();
      target.dispose();
      renderer.dispose();
      renderer.forceContextLoss();
    },

    // Jump every running animation to its end state (used by tests and screenshots).
    settle(seconds = 6) {
      for (let t = 0; t < seconds; t += 0.05) {
        updateRig(0.05);
        for (const unit of lights.values()) unit.update(0.05);
        for (const unit of acs.values()) unit.update(0.05);
        for (const unit of cameras.values()) unit.update(0.05);
      }
      renderer.shadowMap.needsUpdate = true;
      composer.render(0);
    },
  };

  buildShell();
  showCameras();
  if (startOutside) setOutside(true);
  syncAll({ instant: true });
  resize();
  updateRig(0, true);
  return world;
}

// Looking at an AC slightly from the side shows its airflow better.
const WALL_SIDE = { north: -14, west: 14, south: 0, east: 0 };
