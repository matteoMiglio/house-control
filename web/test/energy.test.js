// Solar panels and a home battery: the plan's energy section, how the power flow splits over
// the lines of the 3D view, the panel's words for it, the simulated day, the store, and the 3D
// view easing between readings.
import { test } from 'node:test';
import assert from 'node:assert/strict';

const saved = new Map();
globalThis.window = { __HOUSE_BOOT__: { platform: 'web' } };
globalThis.localStorage = {
  getItem(key) { return saved.get(key) ?? null; },
  setItem(key, value) { saved.set(key, value); },
};

const { normalize, tidyEnergy } = await import('../src/config.js');
const {
  energyFlows: flows, consumption, gridPower, energySimulation, stepEnergy, SIM_DAY, IDLE_WATTS,
  formatWatts, formatCharge, gridStatus, batteryStatus, energyHas, energyName, energyStatus,
} = await import('../src/energy.js');
const { createStore } = await import('../src/store.js');
const { EnergyUnit } = await import('../src/three/energy.js');

const rooms = [{ id: 'living', rect: [0, 0, 6, 4] }, { id: 'garage', rect: [6, 0, 3, 4] }];
const plan = (energy) => normalize({ rooms, energy });
const sum = (f) => Object.values(f).reduce((a, b) => a + (b ?? 0), 0);

test('every part of the energy section is optional, and checked', () => {
  assert.equal(normalize({ rooms }).energy, null);
  const e = plan({
    panels: [{ pos: [3, 2], size: [4, 3.4] }],
    battery: { pos: [8.6, 0.2], room: 'garage' },
    sensors: { grid: { service: 'homeassistant', id: 'sensor.grid', invert: true }, load: { service: 'homeassistant', id: '' } },
  });
  assert.deepEqual(e.energy.panels, [{ pos: [3, 2], size: [4, 3.4], rot: 0 }]);
  assert.deepEqual(e.energy.battery, { pos: [8.6, 0.2], room: 'garage', rot: 0 });
  assert.deepEqual(e.energy.sensors, { grid: { service: 'homeassistant', id: 'sensor.grid', invert: true } });
  assert.equal(e.energy.peak, null);
  assert.deepEqual(plan({ battery: { pos: [20, 20] } }).energy.battery.room, null);
  assert.equal(plan({ battery: { pos: [20, 20] } }).siteBounds.maxX, 20);

  assert.throws(() => plan([]), /must be an object/);
  assert.throws(() => plan({ panels: [{ pos: [1, 1] }] }), /Solar panel array #1 needs "size"/);
  assert.throws(() => plan({ panels: [{ pos: [1, 1], size: [0, 2] }] }), /above 0/);
  assert.throws(() => plan({ battery: { pos: [1, 1], room: 'cellar' } }), /unknown room "cellar"/);
  assert.throws(() => plan({ sensors: { sun: { service: 'homeassistant', id: 'x' } } }), /"sun" is not one of solar, grid, load, battery, charge/);
  assert.throws(() => plan({ sensors: { grid: { id: 'x' } } }), /needs "service" and "id"/);
  assert.throws(() => plan({ sensors: { grid: { service: 'homeassistant', id: 'x', invert: 'yes' } } }), /"invert"/);
  assert.throws(() => plan({ peak: -5 }), /peak/);
  assert.throws(() => plan({ sensors: { toString: { service: 'homeassistant', id: 'x' } } }), /"toString" is not one of/,
    'only its own roles, as on the Mac');
});

test('the editor tidies the energy section: a battery goes with its room, a peak with the last panels', () => {
  // The garage was deleted.
  const doc = {
    rooms: rooms.filter((r) => r.id !== 'garage'),
    energy: { peak: 6000, panels: [], battery: { pos: [1, 1], room: 'garage' }, sensors: { charge: { service: 'homeassistant', id: 'soc' } } },
  };
  tidyEnergy(doc);
  assert.deepEqual(doc.energy, { sensors: { charge: { service: 'homeassistant', id: 'soc' } } });
  assert.doesNotThrow(() => normalize(doc), 'the plan can be saved again');
  const kept = { rooms: [{ id: 'living' }], energy: { peak: 6000, panels: [{ pos: [3, 2], size: [4, 3.4] }], battery: { pos: [1, 1], room: 'living' } } };
  tidyEnergy(kept);
  assert.equal(kept.energy.peak, 6000);
  assert.equal(kept.energy.battery.room, 'living');
  const outside = { rooms: [], energy: { battery: { pos: [1, 1] }, sensors: {} } };
  tidyEnergy(outside);
  assert.deepEqual(outside.energy, { battery: { pos: [1, 1] } }, 'a battery outside belongs to no room');
  const empty = { rooms: [], energy: { panels: [], peak: 5000 } };
  tidyEnergy(empty);
  assert.equal(empty.energy, undefined);
});

test('the power flow splits over the lines and adds up', () => {
  const full = plan({ panels: [{ pos: [3, 2], size: [4, 3.4] }], battery: { pos: [1, 1], room: 'living' } }).energy;
  const energyFlows = (e, energy = full) => flows(e, energy);
  // Noon: the panels run the house, fill the battery and export the rest.
  const noon = { solar: 5000, load: 800, battery: -2500, grid: -1700 };
  assert.deepEqual(energyFlows(noon), { roofHouse: 2500, roofBattery: 2500, batteryHouse: 0, gridHouse: -1700 });
  // Evening: the battery runs the house, the grid tops it up.
  assert.deepEqual(energyFlows({ solar: 0, load: 1500, battery: 1200, grid: 300 }),
    { roofHouse: 0, roofBattery: 0, batteryHouse: 1200, gridHouse: 300 });
  // Charging from the grid at night draws through the house.
  assert.deepEqual(energyFlows({ solar: 0, load: 400, battery: -2000, grid: 2400 }),
    { roofHouse: 0, roofBattery: 0, batteryHouse: -2000, gridHouse: 2400 });
  // What arrives at the house is what it uses.
  for (const e of [noon, { solar: 300, load: 900, battery: -500, grid: 1100 }]) {
    const f = energyFlows(e);
    assert.equal(f.roofHouse + f.batteryHouse + f.gridHouse, e.load);
  }
  // Without a grid sensor it follows from the rest; without either it is not known.
  const panelsOnly = plan({ panels: [{ pos: [3, 2], size: [4, 3.4] }] }).energy;
  assert.equal(energyFlows({ solar: 1000, load: 1500 }, panelsOnly).gridHouse, 500, 'no battery: nothing from it');
  assert.equal(energyFlows({ solar: 1000 }).gridHouse, null);
  assert.equal(consumption({ solar: 1000, grid: -200, battery: -300 }, full), 500);
  assert.equal(consumption({ load: 640, grid: 9 }, full), 640);
  assert.equal(consumption({ solar: 1000 }, full), null);
});

test('what depends on a reading that is not known is not known either', () => {
  const full = plan({ panels: [{ pos: [3, 2], size: [4, 3.4] }], battery: { pos: [1, 1], room: 'living' } }).energy;
  const batteryOnly = plan({ battery: { pos: [1, 1] } }).energy;
  // The solar sensor offline: no import made up from the house's use.
  const offline = { solar: null, battery: 0, load: 600, grid: null };
  assert.equal(gridPower(offline, full), null);
  assert.equal(gridStatus(offline, full), '—');
  assert.deepEqual(flows(offline, full), { roofHouse: null, roofBattery: 0, batteryHouse: 0, gridHouse: null });
  assert.equal(consumption({ grid: 300, solar: null, battery: 0 }, full), null);
  // A plan without panels has no solar to wait for.
  assert.equal(consumption({ grid: 300, solar: null, battery: 0 }, batteryOnly), 300);
  assert.equal(gridPower({ load: 600, battery: 100 }, batteryOnly), 500);
  // The battery offline: where the sun's power goes is not known, a discharge is.
  assert.deepEqual(flows({ solar: 2000, battery: null, grid: -500 }, full), { roofHouse: null, roofBattery: null, batteryHouse: null, gridHouse: -500 });
  assert.deepEqual(flows({ solar: null, battery: 400, grid: 0 }, full), { roofHouse: null, roofBattery: 0, batteryHouse: 400, gridHouse: 0 });
});

test('the panel writes powers in W below 1 kW, in kW from there', () => {
  assert.equal(formatWatts(640), '640 W');
  assert.equal(formatWatts(0), '0 W');
  assert.equal(formatWatts(999.4), '999 W');
  assert.equal(formatWatts(999.6), '1.0 kW', 'rounded to the watt first');
  assert.equal(formatWatts(3245.62), '3.2 kW');
  assert.equal(formatWatts(3250), '3.3 kW', 'half a tenth rounds up, as on the Mac');
  assert.equal(formatWatts(12040), '12.0 kW');
  assert.equal(formatWatts(-1180.3), '1.2 kW', 'whichever way it flows');
  assert.equal(formatWatts(null), '—');
  assert.equal(formatWatts(undefined), '—');
  assert.equal(formatCharge(78.4), '78%');
  assert.equal(formatCharge(null), '—');

  assert.equal(gridStatus({ grid: 640 }), 'Importing 640 W');
  assert.equal(gridStatus({ grid: -1180 }), 'Exporting 1.2 kW');
  assert.equal(gridStatus({ grid: IDLE_WATTS / 2 }), 'Idle');
  const panelsOnly = plan({ panels: [{ pos: [3, 2], size: [4, 3.4] }] }).energy;
  assert.equal(gridStatus({ solar: 1000, load: 1500 }, panelsOnly), 'Importing 500 W', 'worked out without a grid sensor');
  assert.equal(gridStatus({ solar: 1000 }, panelsOnly), '—');
  assert.equal(batteryStatus({ battery: -700 }), 'Charging 700 W');
  assert.equal(batteryStatus({ battery: 1250 }), 'Discharging 1.3 kW');
  assert.equal(batteryStatus({ battery: 5 }), 'Idle');
  assert.equal(batteryStatus({}), '—');
});

test('the Solar tile shows what the plan has, and a dash for what is not known', () => {
  const sensor = { service: 'homeassistant', id: 'x' };
  const both = plan({ panels: [{ pos: [3, 2], size: [4, 3.4] }], battery: { pos: [1, 1], room: 'living' } }).energy;
  const panelsOnly = plan({ panels: [{ pos: [3, 2], size: [4, 3.4] }] }).energy;
  const batteryOnly = plan({ battery: { pos: [1, 1] } }).energy;
  const sensorsOnly = plan({ sensors: { solar: sensor, charge: sensor } }).energy;
  assert.deepEqual(energyHas(both), { solar: true, battery: true });
  assert.deepEqual(energyHas(panelsOnly), { solar: true, battery: false });
  assert.deepEqual(energyHas(batteryOnly), { solar: false, battery: true });
  assert.deepEqual(energyHas(sensorsOnly), { solar: true, battery: true });
  assert.deepEqual(energyHas(plan({}).energy), { solar: false, battery: false });
  assert.equal(energyName(both), 'Solar');
  assert.equal(energyName(batteryOnly), 'Battery');
  assert.equal(energyName(plan({}).energy), 'Solar');

  assert.equal(energyStatus({ solar: 3245, charge: 78.4 }, both), '3.2 kW · 78%');
  assert.equal(energyStatus({ solar: 640, charge: 78 }, panelsOnly), '640 W', 'no battery: production alone');
  assert.equal(energyStatus({ solar: 0, charge: 78 }, batteryOnly), '78%', 'no panels: the charge alone');
  assert.equal(energyStatus({ solar: null, charge: 78 }, both), '— · 78%', 'a sensor offline');
  assert.equal(energyStatus({ solar: 640 }, both), '640 W · —');
  assert.equal(energyStatus({}, both), '—', 'nothing known');
  assert.equal(energyStatus({}, plan({}).energy), '—');
});

test('a plan without sensors gets a simulated day that adds up', () => {
  const energy = plan({ panels: [{ pos: [3, 2], size: [4, 3.4] }], battery: { pos: [1, 1], room: 'living' } }).energy;
  assert.equal(energySimulation({ ...energy, sensors: { grid: { service: 'homeassistant', id: 'x' } } }), null);
  assert.equal(energySimulation(plan({}).energy), null);
  const sim = energySimulation(energy);
  assert.equal(sim.peak, 4 * 3.4 * 200);
  const midnight = Math.floor(Date.now() / 1000 / SIM_DAY) * SIM_DAY;
  const night = stepEnergy(sim, midnight + SIM_DAY * 2 / 24, 3);
  assert.equal(night.solar, 0);
  assert.ok(night.battery > 0, 'the battery runs the house at night');
  let morning;
  for (let s = SIM_DAY * 10 / 24; s < SIM_DAY * 12 / 24; s += 3) morning = stepEnergy(sim, midnight + s, 3);
  assert.ok(morning.solar > 1000);
  assert.ok(morning.battery <= 0, 'charging, or full');
  for (const e of [night, morning]) {
    assert.ok(Math.abs(e.solar + e.battery + e.grid - e.load) < 1e-9);
    assert.ok(e.charge >= 0 && e.charge <= 100);
  }
  // The same day as core/…/Energy.swift EnergySimulation (its tests check the same balance).
  const alone = stepEnergy(energySimulation(plan({ panels: [{ pos: [3, 2], size: [2, 2] }], peak: 5000 }).energy), midnight + SIM_DAY / 2, 3);
  // A battery whose panels were all taken away keeps no sun, whatever peak is left.
  const dark = energySimulation(plan({ battery: { pos: [1, 1] }, peak: 5000 }).energy);
  assert.equal(dark.peak, 0);
  assert.equal(stepEnergy(dark, midnight + SIM_DAY / 2, 3).solar, 0);
  assert.equal(alone.battery, null);
  assert.equal(alone.grid, alone.load - alone.solar);
});

test('the store simulates the flow, takes real readings, and never saves them', (t) => {
  t.mock.timers.enable({ apis: ['setTimeout', 'setInterval'] });
  const simulated = createStore(plan({ panels: [{ pos: [3, 2], size: [4, 3.4] }] }));
  assert.ok(Number.isFinite(simulated.state.energy.load));
  const changes = [];
  simulated.on((change) => changes.push(change.type));
  t.mock.timers.tick(3000);
  assert.ok(changes.length <= 1 && changes.every((c) => c === 'tick'));

  const real = createStore(plan({ sensors: { solar: { service: 'homeassistant', id: 's' } } }));
  assert.deepEqual(real.state.energy, {});
  const seen = [];
  real.on((change) => seen.push(change.type));
  real.applyRemote({ lights: {}, acs: {}, features: {}, energy: { solar: 2100, charge: null } });
  assert.deepEqual(seen, ['tick']);
  assert.deepEqual(real.state.energy, { solar: 2100, charge: null });
  real.applyRemote({ energy: { solar: 2100 } });
  assert.equal(seen.length, 1, 'the same reading changes nothing');
  t.mock.timers.tick(1000);
  assert.ok(![...saved.values()].some((v) => v.includes('"energy"')));
});

test('the 3D view eases between readings, and lines below the threshold go idle', () => {
  const config = plan({ panels: [{ pos: [3, 2], size: [4, 3.4] }], battery: { pos: [7.5, 0.2], room: 'garage' }, peak: 6000 });
  const unit = new EnergyUnit({ ...config, wallHeight: 2.6 }, { x: 0.56, z: 0.83 });
  unit.apply({ solar: 0, load: 400, battery: 400, grid: 0, charge: 60 }, { instant: true });
  unit.update(1 / 60);
  assert.equal(unit.lines.batteryHouse.streaks.visible, false, 'no power flow in the cut-open rooms');
  assert.equal(unit.ringMat.opacity, 0);
  unit.setWhole(true);
  unit.update(1 / 60);
  assert.equal(unit.look.cells.emissiveIntensity, 0, 'dark at night');
  assert.equal(unit.lines.roofHouse.streaks.visible, false);
  assert.equal(unit.lines.batteryHouse.streaks.visible, true);

  unit.apply({ solar: 6000, load: 500, battery: -3000, grid: -2500, charge: 61 });
  const watts = [];
  const glow = [];
  for (let i = 0; i < 600; i++) {
    unit.update(1 / 60);
    watts.push(unit.lines.roofHouse.watts);
    glow.push(unit.look.cells.emissiveIntensity);
  }
  const biggestStep = (series) => Math.max(...series.slice(1).map((v, i) => Math.abs(v - series[i])));
  assert.ok(biggestStep(watts) < 3000 * 0.05, `the line jumps by ${biggestStep(watts)} W in a frame`);
  assert.ok(biggestStep(glow) < 0.05, `the panels jump by ${biggestStep(glow)} in a frame`);
  assert.equal(watts.at(-1), 3000);
  assert.ok(glow.at(-1) > 0.85, 'bright at full output');
  assert.equal(unit.lines.batteryHouse.streaks.visible, false, 'the battery charges from the roof, not through the house');
  assert.equal(unit.lines.roofBattery.streaks.visible, true);

  unit.apply({ solar: 0, load: IDLE_WATTS / 2, battery: 0, grid: IDLE_WATTS / 2 });
  for (let i = 0; i < 900; i++) unit.update(1 / 60);
  assert.equal(unit.lines.gridHouse.streaks.visible, false, `${IDLE_WATTS / 2} W is idle`);
  assert.equal(unit.update(1 / 60), false, 'and the view comes to rest');
});

test('a battery outside the house shows from outside only', () => {
  const config = plan({ panels: [{ pos: [3, 2], size: [4, 3.4] }], battery: { pos: [-1, 1] } });
  const unit = new EnergyUnit({ ...config, wallHeight: 2.6 }, { x: 0.56, z: 0.83 });
  assert.equal(unit.battery.group.visible, false);
  assert.equal(unit.lines.roofBattery.shown, false);
  unit.setWhole(true);
  assert.equal(unit.battery.group.visible, true);
  assert.equal(unit.lines.batteryHouse.shown, true);
});

test('without a roof the panels show as an outline, and the rest still shows from outside', () => {
  const config = plan({ panels: [{ pos: [3, 2], size: [4, 3.4] }], battery: { pos: [-1, 1] } });
  const unit = new EnergyUnit({ ...config, wallHeight: 2.6 }, { x: 0.56, z: 0.83 });
  unit.setWhole(true, false);
  assert.ok(unit.arrays[0].solid.every((o) => !o.visible));
  assert.ok(unit.arrays[0].ghost.every((o) => o.visible));
  assert.equal(unit.battery.group.visible, true, 'the battery outside');
  assert.equal(unit.lines.gridHouse.shown, true, 'the power flow');
  unit.setWhole(true, true);
  assert.ok(unit.arrays[0].solid.every((o) => o.visible));
});
