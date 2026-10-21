// The home's power flow: what the energy sensors report, in the panel's terms (EnergyState in
// core/…/Energy.swift), how it splits over the lines the 3D view draws, and a made-up day of
// sun for a plan whose energy section has no sensors.
//
// Every value is in watts, with the house as the point of view: `solar` produced, `load` used,
// `grid` positive while importing and negative while exporting, `battery` positive while it
// discharges and negative while it charges; `charge` is the battery's state of charge in %.
// A value that is not known is null (or missing).

/** Below this a line of the power flow is idle: not drawn. */
export const IDLE_WATTS = 20;

const known = (v) => Number.isFinite(v);

/** What the house uses: its own sensor's reading, or what flows in from the rest. */
export function consumption(e) {
  if (known(e.load)) return e.load;
  if (!known(e.grid)) return null;
  return Math.max(0, e.grid + (known(e.solar) ? e.solar : 0) + (known(e.battery) ? e.battery : 0));
}

/**
 * The power on each line of the 3D view, in W. Solar power goes to the battery while it
 * charges and the rest to the house (and on through it to the grid); a battery charged
 * from the grid draws through the house.
 *   roofHouse     panels → house, never negative
 *   roofBattery   panels → battery, never negative
 *   batteryHouse  battery → house; negative: house → battery (charging from the grid)
 *   gridHouse     grid → house; negative: house → grid (exporting)
 * A line whose power cannot be worked out is null.
 */
export function energyFlows(e) {
  const solar = known(e.solar) ? Math.max(0, e.solar) : 0;
  const battery = known(e.battery) ? e.battery : 0;
  const grid = known(e.grid) ? e.grid : known(e.load) ? e.load - solar - battery : null;
  const charging = Math.max(0, -battery);
  const solarToBattery = Math.min(solar, charging);
  return {
    roofHouse: solar - solarToBattery,
    roofBattery: solarToBattery,
    batteryHouse: Math.max(0, battery) - (charging - solarToBattery),
    gridHouse: grid,
  };
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
  return { peak: energy.peak ?? area * WATTS_PER_M2, battery: Boolean(energy.battery), charge: 55 };
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
