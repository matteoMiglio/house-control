# The lab: smart homes to test against

Pretend versions of the platforms House Control connects to, so it can be built and tested without owning the
hardware. Each runs on your Mac and behaves like the real thing on the network: it is found by the app's
discovery, speaks the real protocol and prints every command it receives.

| Command | What it is |
| --- | --- |
| `./tools/lab/homeassistant.sh` | A real Home Assistant (installed into `tools/lab/.ha` on first run, about 1 GB) with its demo devices: lights with every colour mode, three climate devices, fans, a thermometer, and solar panels with a home battery (see below). Prints the address and an access token |
| `cd tools/lab && npm install && npm run hue` | A Philips Hue Bridge emulator: five lamps (colour, white ambiance, dimmable, a plug) in three rooms, a motion sensor with a thermometer. Press Enter to "press" the link button, or start it with `npm run hue -- --auto` |
| `cd tools/lab && npm run homekit` | A HomeKit bridge with lamps, a plug, two air conditioners and a thermometer, built on [HAP-NodeJS](https://github.com/homebridge/HAP-NodeJS). Add it in the Home app on your iPhone with **+ → Add Accessory → More options… → House Control Lab**, setup code **031-45-154** |

Needs [uv](https://github.com/astral-sh/uv) for Home Assistant (`brew install uv`) and Node.js for the other two.

## A full run

1. Start the lab Home Assistant and the Hue emulator (`npm run hue -- --auto`).
2. Start a throw-away House Control, so your own plan and sign-ins stay untouched:

   ```bash
   HOUSE_DATA_DIR=/tmp/house-lab HOUSE_OPEN_EDITOR=connections build/HouseControl.app/Contents/MacOS/HouseControl
   ```

3. **Connections → Home Assistant**: the lab server is listed; press **Use**, paste the token, **Connect**.
   **Connections → Philips Hue**: press **Pair**.
4. Link a few lamps and an AC under **Real device**, **Save & apply**, and use the panel. The emulators print each
   command; change something in Home Assistant's web UI and watch the panel follow.
5. To test the iPhone app, run it in the simulator and pair it with that instance (`scripts/ios-sim.sh`; see
   the README's development section). Home Assistant and Hue come over with the plan.

Apple Home needs a real iPhone: the iOS Simulator grants HomeKit access but cannot create a home without an
iCloud account. Add the lab's HomeKit bridge to your Home app, then **Settings → More connections → Apple Home**
in House Control on the phone.

## Solar panels and a home battery

The lab Home Assistant has sensors named and signed like those of the Fronius integration (a Symo GEN24 with a BYD
battery), driven by four sliders: **Settings → Devices & services → Helpers → Lab solar production**, **Lab house
consumption**, **Lab battery** (positive while discharging) and **Lab battery charge**. The grid sensor makes up
the difference, negative while exporting; *PV power* reports the panels in kW, as some other integrations do.

1. In **Edit Home → Solar & battery**, add panels on the roof and a battery, then link the sensors:
   *SolarNet Power photovoltaics* (solar production), *SolarNet Power grid*, *SolarNet Power load* (house
   consumption), *SolarNet Power battery* and *BYD Battery-Box Premium HV State of charge*. **Save & apply**.
2. Move a slider in Home Assistant: the panels, the battery and the lines in the 3D view follow within a second or
   two (the change arrives over the WebSocket; the panel also reads every 12 seconds while it is open).

From a script, `input_number.set_value` does the same:

```bash
curl -X POST -H "Authorization: Bearer $(cat tools/lab/.ha/token)" -H "Content-Type: application/json" \
  -d '{"entity_id": "input_number.lab_solar", "value": 5200}' http://127.0.0.1:8123/api/services/input_number/set_value
```

## Automated tests

The unit tests cover the translation to and from each platform and the hub's routing. Three more run against the lab:

```bash
cd core
HOUSE_TEST_HA_URL=http://127.0.0.1:8123 HOUSE_TEST_HA_TOKEN=$(cat ../tools/lab/.ha/token) \
HOUSE_TEST_HUE_HOST=localhost:8443 swift test --filter 'ServiceTests|LiveEnergyTests'
```

The Hue test expects the emulator started with `--auto`. `LiveEnergyTests` lists the solar sensors, moves the solar
slider and waits for the change to arrive over the WebSocket.

## Your real Tuya devices, through the lab

The lab Home Assistant is a real one: **Settings → Devices & services → Add integration → Tuya** signs in with
your Smart Life User Code, and your own lamps and air conditioners appear next to the demo devices — and in
House Control's Home Assistant list. (To put them into Apple Home as well, use **HomeKit Bridge** on a Home
Assistant that runs on its own box — a Raspberry Pi, Home Assistant Green, a Linux machine: the lab's cannot
announce a HomeKit bridge on macOS, see below.)

Run as a plain process on macOS, Home Assistant cannot use Bluetooth (macOS would stop it), so the lab replaces
that integration with a stub in `homeassistant/custom_components/bluetooth`. Its own Bonjour announcements do
not reach the network either; `homeassistant.sh` announces the server with `dns-sd`, in the same format (which
is enough for House Control, but not for a HomeKit Bridge).

Delete `tools/lab/.ha`, `.hue` or `.homekit` to start any of them from scratch.
