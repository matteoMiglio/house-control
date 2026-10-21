// The home's power flow: what the energy sensors report, in the panel's terms (EnergyState in
// core/…/Energy.swift), how it splits over the lines the 3D view draws, and a made-up day of
// sun for a plan whose energy section has no sensors.
//
// Every value is in watts, with the house as the point of view: `solar` produced, `load` used,
// `grid` positive while importing and negative while exporting, `battery` positive while it
// discharges and negative while it charges; `charge` is the battery's state of charge in %.
// A value that is not known is null (or missing), and so is anything worked out from it.

/** Below this a line of the power flow is idle: not drawn. */
export const IDLE_WATTS = 20;

const known = (v) => Number.isFinite(v);

/** What a plan's energy section has: production when it has panels or a solar sensor, a
 *  battery when one stands in the plan or a sensor reports one. Known or not right now. */
export function energyHas(energy) {
  const s = energy?.sensors || {};
  return { solar: Boolean(energy?.panels.length || s.solar), battery: Boolean(energy?.battery || s.battery || s.charge) };
}

// The panels' and the battery's power, to work the rest out with: 0 for what the plan does not
// have, null for what it has but is not known right now (a sensor offline, or none linked).
function sources(e, energy) {
  const has = energyHas(energy);
  const part = (v, present) => (known(v) ? v : present ? null : 0);
  return { solar: part(e.solar, has.solar), battery: part(e.battery, has.battery) };
}

/** What the house uses: its own sensor's reading, or what flows in from the rest when all of
 *  that is known. */
export function consumption(e, energy) {
  if (known(e.load)) return e.load;
  const { solar, battery } = sources(e, energy);
  if (!known(e.grid) || solar === null || battery === null) return null;
  return Math.max(0, e.grid + solar + battery);
}

/** From the grid, in W (negative: exporting): its own sensor's reading, or what the house uses
 *  beyond what the panels and the battery give it, when all of that is known. */
export function gridPower(e, energy) {
  if (known(e.grid)) return e.grid;
  const { solar, battery } = sources(e, energy);
  if (!known(e.load) || solar === null || battery === null) return null;
  return e.load - Math.max(0, solar) - battery;
}

/**
 * The power on each line of the 3D view, in W. Solar power goes to the battery while it
 * charges and the rest to the house (and on through it to the grid); a battery charged
 * from the grid draws through the house.
 *   roofHouse     panels → house, never negative
 *   roofBattery   panels → battery, never negative
 *   batteryHouse  battery → house; negative: house → battery (charging from the grid)
 *   gridHouse     grid → house; negative: house → grid (exporting)
 * A line whose power cannot be worked out (a reading it depends on is not known) is null.
 */
export function energyFlows(e, energy) {
  const { solar, battery } = sources(e, energy);
  const sun = solar === null ? null : Math.max(0, solar);
  const charging = battery === null ? null : Math.max(0, -battery);
  // What the panels send to the battery: nothing when either gives nothing, else both must be known.
  const solarToBattery = sun === 0 || charging === 0 ? 0 : sun === null || charging === null ? null : Math.min(sun, charging);
  return {
    roofHouse: sun === null || solarToBattery === null ? null : sun - solarToBattery,
    roofBattery: solarToBattery,
    batteryHouse: battery === null || solarToBattery === null ? null : Math.max(0, battery) - (charging - solarToBattery),
    gridHouse: gridPower(e, energy),
  };
}

/* ---------- in words ---------- */

/** A power as the panel writes it, whichever way it flows: in W below 1 kW ("640", "W"), in kW
 *  with one decimal from there ("3.2", "kW"); null when not known. */
export function wattsParts(w) {
  if (!known(w)) return null;
  const watts = Math.round(Math.abs(w));
  if (watts < 1000) return { number: String(watts), unit: 'W' };
  const tenths = Math.round(watts / 100);
  return { number: `${Math.floor(tenths / 10)}.${tenths % 10}`, unit: 'kW' };
}

/** "640 W", "3.2 kW", or "—" when not known. */
export function formatWatts(w) {
  const p = wattsParts(w);
  return p ? `${p.number} ${p.unit}` : '—';
}

/** A battery's charge: "78%", or "—". */
export const formatCharge = (c) => (known(c) ? `${Math.round(c)}%` : '—');

/** "Importing 640 W", "Exporting 1.2 kW", "Idle", or "—". */
export function gridStatus(e, energy) {
  const g = gridPower(e, energy);
  if (!known(g)) return '—';
  if (Math.abs(g) < IDLE_WATTS) return 'Idle';
  return `${g > 0 ? 'Importing' : 'Exporting'} ${formatWatts(g)}`;
}

/** The battery in a line: "78% · Charging 1.2 kW", what is known of it, or "—". */
export function batteryLine(e) {
  const parts = [known(e.charge) && formatCharge(e.charge), known(e.battery) && batteryStatus(e)].filter(Boolean);
  return parts.length ? parts.join(' · ') : '—';
}

/** "Charging 700 W", "Discharging 1.2 kW", "Idle", or "—". */
export function batteryStatus(e) {
  if (!known(e.battery)) return '—';
  if (Math.abs(e.battery) < IDLE_WATTS) return 'Idle';
  return `${e.battery < 0 ? 'Charging' : 'Discharging'} ${formatWatts(e.battery)}`;
}

/** What the panel calls it: Solar, or Battery for a battery without panels. */
export function energyName(energy) {
  const has = energyHas(energy);
  return has.battery && !has.solar ? 'Battery' : 'Solar';
}

/** The Solar tile's line: production · charge, of what the plan has ("3.2 kW · 78%", "640 W",
 *  "— · 78%"); "—" when nothing is known. */
export function energyStatus(e, energy) {
  const has = energyHas(energy);
  const parts = [has.solar && formatWatts(e.solar), has.battery && formatCharge(e.charge)].filter(Boolean);
  return parts.every((p) => p === '—') ? '—' : parts.join(' · ');
}

/* ---------- simulation ---------- */

// A day passes in six minutes, so the panels, the battery and the grid all get their turn.
export const SIM_DAY = 360;
const CAPACITY = 10000; // Wh
const BATTERY_POWER = 3000; // W
const WATTS_PER_M2 = 200;

/** The state of a simulated power flow for a plan's energy section, or null when it has
 *  real sensors or nothing to simulate (no panels, no battery). */
export function energySimulation(energy) {
  if (!energy || Object.keys(energy.sensors).length) return null;
  const area = energy.panels.reduce((sum, p) => sum + p.size[0] * p.size[1], 0);
  if (!(area > 0) && !energy.battery) return null;
  // No panels make nothing, whatever peak the plan still has.
  return { peak: area > 0 ? energy.peak ?? area * WATTS_PER_M2 : 0, battery: Boolean(energy.battery), charge: 55 };
}

/** The simulated power flow at `time` (seconds since 1970), `seconds` after the last step. */
export function stepEnergy(sim, time, seconds) {
  const hour = ((time / SIM_DAY) % 1) * 24;
  const sun = hour > 6 && hour < 20 ? Math.sin(Math.PI * (hour - 6) / 14) ** 1.3 : 0;
  const clouds = 1 - 0.35 * (0.5 + 0.5 * Math.sin(time / 23)) ** 3 * (0.5 + 0.5 * Math.sin(time / 7.3));
  const solar = Math.round(sim.peak * 0.88 * sun * clouds);
  const around = (from, to, watts) => (hour >= from && hour < to ? watts : 0);
  const load = Math.round(330 + 120 * (0.5 + 0.5 * Math.sin(time / 11)) + around(7, 8, 650) + around(12, 13, 1100)
    + around(18.5, 20, 1500) + around(20, 23, 280));
  let battery = 0;
  if (sim.battery) {
    const surplus = solar - load;
    if (surplus > 0 && sim.charge < 99.5) battery = -Math.min(surplus, BATTERY_POWER);
    else if (surplus < 0 && sim.charge > 8) battery = Math.min(-surplus, BATTERY_POWER);
    const hours = seconds * 24 / SIM_DAY;
    sim.charge = Math.min(100, Math.max(0, sim.charge - battery * hours / CAPACITY * 100));
  }
  return {
    solar, grid: load - solar - battery, load,
    battery: sim.battery ? battery : null, charge: sim.battery ? Math.round(sim.charge * 10) / 10 : null,
  };
}
