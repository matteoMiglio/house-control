# The floor plan file

A home is one JSON document. The 3D scene, the panel and the editor are all built from it, so swapping the
file swaps the home.

- Your plan: `~/Library/Application Support/HouseControl/plan.json`
- Bundled demos: [`web/public/plans/home.json`](../web/public/plans/home.json) and
  [`studio.json`](../web/public/plans/studio.json)

You rarely need to write it by hand — **Edit Home…** does it for you — but it is plain, stable and easy to
generate or version. Load a file with **Load Floor Plan…** in the menu bar icon's right-click menu, or with
**Import…** in the editor.

<p align="center">
  <img src="studio.png" width="300" alt="The Studio demo plan">
</p>

## Coordinates

Everything is in metres, seen from above: `x` grows to the right (east), `z` grows downwards (south).
Heights (`y`, `sill`, `head`) are metres above the floor. Angles are degrees.

## A complete small example

```jsonc
{
  "name": "Home",
  "wallHeight": 2.6,
  "interiorWallHeight": 1.25,
  "outdoorTemp": 29,
  "camera": { "azimuth": 34, "elevation": 47 },

  "rooms": [
    { "id": "living", "name": "Living", "rect": [0, 0, 6.4, 4.6], "floor": "oak" },
    { "id": "bath",   "name": "Bathroom", "rect": [6.4, 0, 2.2, 3.6], "floor": "tile" }
  ],

  "openings": [
    { "type": "door",   "from": [6.4, 1.0], "to": [6.4, 1.9] },
    { "type": "window", "from": [0, 1.0],   "to": [0, 2.6], "sill": 0.85, "head": 2.1 }
  ],

  "furniture": [
    { "type": "sofa", "pos": [3.9, 2.4], "rot": -90, "width": 2.5, "color": "#8b93a7" },
    { "type": "rug",  "pos": [2.6, 2.4], "size": [2.4, 1.6] }
  ],

  "lights": [
    { "id": "living.main", "name": "Ceiling", "room": "living", "type": "ceiling", "pos": [2.9, 2.3],
      "capabilities": ["brightness", "temp"] },
    { "id": "living.floor", "name": "Floor lamp", "room": "living", "type": "floor", "pos": [5.8, 0.6] },
    { "id": "living.tv", "name": "TV backlight", "room": "living", "type": "strip", "pos": [0.13, 2.3],
      "y": 1.05, "rot": 90, "length": 1.5, "capabilities": ["brightness", "color"], "color": "#7b5cff" }
  ],

  "acs": [
    { "id": "living.ac", "name": "Living AC", "room": "living", "wall": "west", "pos": [0, 0.8], "y": 2.2 }
  ],

  "scenes": [
    { "id": "movie", "name": "Movie", "icon": "film",
      "lights": { "*": { "on": false }, "living.tv": { "on": true, "brightness": 0.9, "color": "#6a4cff" } },
      "acs": { "*": { "target": 23 } } }
  ]
}
```

## Top level

| Field | Default | Meaning |
| --- | --- | --- |
| `name` | `"Home"` | Shown in the panel header |
| `wallHeight` | `2.6` | Height of the outer walls |
| `interiorWallHeight` | `1.25` | How much of the inner walls is drawn, so they do not hide the rooms |
| `outdoorTemp` | `27` | Used to estimate the room temperature of an AC that has no sensor |
| `camera.azimuth`, `camera.elevation` | `34`, `47` | Default view. Walls facing the camera are cut away, so the azimuth decides which side is open |
| `roof` | `true` | `false` leaves the flat roof off in the view from outside, so the rooms show from above |

## `rooms`

| Field | Meaning |
| --- | --- |
| `id` | Unique. Lights and ACs refer to it |
| `name` | Shown in the room filter |
| `rect` | `[x, z, width, depth]` |
| `floor` | `oak`, `walnut`, `tile` or `stone` |

Rooms are rectangles. Where two of them touch, an inner wall appears on its own; make an L-shaped room out of two.

## `openings`

A gap in a wall, given by its two end points on that wall. It must be horizontal or vertical.

| Field | Meaning |
| --- | --- |
| `type` | `door`, `window`, or `open` (a doorway without a door, or a missing piece of wall) |
| `from`, `to` | `[x, z]` end points |
| `sill`, `head` | Bottom and top of a window. Defaults `0.85` and `2.1` |

## `furniture`

Decoration only. Every piece has `type`, `pos` (`[x, z]` of its centre) and an optional `rot`.

| `type` | Extra options |
| --- | --- |
| `sofa` | `width`, `color` |
| `armchair` | `color` |
| `coffeeTable` | `width` |
| `rug` | `size` (`[width, depth]`), `color` |
| `tv`, `sideboard`, `dresser`, `desk`, `vanity` | `width` |
| `diningSet` | `width`, `chairs` |
| `island` | `width`, `stools` |
| `kitchen` | `width`, `upper` (wall cabinets, `true` by default) |
| `bed` | `width`, `color` |
| `wardrobe`, `bookshelf` | `width`, `height` |
| `plant` | `height` |
| `fridge`, `nightstand`, `bathtub`, `toilet` | — |

## `lights`

| Field | Meaning |
| --- | --- |
| `id` | Unique |
| `name` | Shown on the tile |
| `room` | The `id` of its room, or `outside` for a lamp outside the house: those make up the panel's **Outside** group |
| `type` | `ceiling`, `pendant`, `spots`, `floor`, `table` or `strip`; outside, `lantern` (on a wall), `post` (a garden post light) or `flood` (a floodlight on a wall). A lantern or floodlight faces the way `rot` turns it, like furniture |
| `pos` | `[x, z]` |
| `y` | Height, if the default for the type does not fit |
| `rot` | Rotation, for strips and spots |
| `length` | Length of a `strip` |
| `capabilities` | Any of `brightness`, `temp`, `color`. Leave it out for a plain smart plug that only switches |
| `color` | Initial colour of a colour light |
| `link`, `tuya` | Link to a real device — see below |

## `acs`

| Field | Meaning |
| --- | --- |
| `id`, `name`, `room` | As for lights |
| `wall` | The wall it hangs on: `north`, `south`, `east` or `west` |
| `pos` | `[x, z]`, on that wall |
| `y` | Height. Default `2.2` |
| `min`, `max` | Range of the target temperature. Defaults `16` and `30` |
| `link`, `tuya` | Link to a real device — see below |
| `sensor` | A thermometer for the room — see below |

## The outside: `site` and `outdoor`

The view from outside (the trees button in the panel, **Outside** in the editor's preview) shows the whole house
on its plot. Both sections are optional: without them the house stands on a lawn a few metres wide.

```jsonc
"site": { "boundary": [[-4, -3], [15, -3], [15, 13.5], [-4, 13.5]], "ground": "grass" },
"outdoor": [
  { "type": "fence",    "from": [-4, -3], "to": [-4, 13.5] },
  { "type": "gate",     "from": [10, 13.5], "to": [13.6, 13.5], "height": 1.5 },
  { "type": "tree",     "pos": [-1.6, 10.8], "radius": 1.7, "height": 5.5 },
  { "type": "building", "rect": [-3.2, -2.3, 2.4, 2], "height": 2.3 },
  { "type": "paving",   "rect": [10.4, 3.6, 3.2, 9.9] },
  { "type": "van",      "pos": [12, 8.6], "rot": 0 }
]
```

| Field | Meaning |
| --- | --- |
| `site.boundary` | The property line: at least three `[x, z]` corners, in order |
| `site.ground` | Inside the property line: `grass`, `gravel` or `concrete` |

Every `outdoor` item has a `type` and an optional `height` in metres:

| `type` | Shape | Default height |
| --- | --- | --- |
| `fence`, `wall`, `hedge`, `gate` | `from`, `to`: a line, at any angle | `1.8`, `2`, `1.6`, `1.8` |
| `tree` | `pos` (`[x, z]` of the trunk), `radius` of the crown (default `1.5`) | `5` |
| `car`, `van` | `pos` (`[x, z]` of its middle), `rot` (like furniture: `0` faces south), optional `color` | `1.5`, `2.3` |
| `building` (a shed, a garage) | `rect`: `[x, z, width, depth]` | `2.6` |
| `paving` (a drive, a terrace) | `rect` | — |

## `cameras`

Security cameras, for working out where to put them. Each one shows, from outside, the patch of ground it covers
out to its `range`; pick one (in the panel, or in the editor) to see the house through its lens.

```jsonc
{ "id": "cam.door", "name": "Front door", "pos": [10.58, 3.9], "y": 2.4, "rot": 55, "tilt": 22, "fov": 104, "range": 12 }
```

| Field | Default | Meaning |
| --- | --- | --- |
| `id`, `name` | | As for lights |
| `pos` | | `[x, z]`. On a wall, just outside its outer face: the editor puts it there when you drop it close to one |
| `y` | `2.5` | Height of the lens |
| `rot` | `0` | Which way it looks, like furniture: `0` south (down the plan), `90` east, `180` north, `-90` west |
| `tilt` | `25` | Degrees it looks down |
| `fov` | `100` | Horizontal angle of view, from the spec sheet: about 100–110° for a 2.8 mm lens, 80–90° for 4 mm |
| `resolution` | `[2560, 1440]` | Pixels across and down; the ratio sets the vertical angle of view |
| `range` | `12` | How far it sees at night, in metres: its infrared range from the spec sheet |

### Coverage

From outside, the ground is coloured by how much the cameras make out there, and **Camera coverage** in the
editor adds it up: how much of the plot is seen, at what detail, and how well each door and gate is watched.

- A spot counts as seen when a camera has a clear line to the middle of a person standing there (1 m up).
  Walls, fences, hedges, sheds and cars block it; a gate's bars and the space under a tree's crown do not.
  Inside the house and under sheds and cars nobody stands, so those are left out.
- Detail follows the pixels a camera puts on a metre of the scene there (IEC 62676-4, "DORI"): 25 to **detect**
  someone, 62.5 to **observe** what they do, 125 to **recognise** someone you know, 250 to **identify** a stranger.
  It follows from the resolution, the angle of view and the distance.
- For a door or a gate, it is the face (1.6 m up) of someone standing just outside it that counts.
- Ground on the plot that no camera sees is a blind spot, drawn in red.

### Suggested cameras

**Suggest where they go**, on the same screen, works out where a number of new cameras (with the lens you choose)
would do the most, on top of the ones already planned. It tries every spot about a metre apart along the outside
walls and by each corner, a little below the wall top, aimed straight out or along the wall and tilted 15–35°,
and picks the cameras one by one: as much of the plot seen, in as much detail, as it can, every door and gate at
Identify first. Then it adjusts each one's aim and place a little. They are shown dotted on the plan, with what
all the cameras would see together and the difference they make, until you add them (⌘Z takes them away again)
or discard them.

## `energy`

Solar panels on the roof, a home battery, and the sensors that report how power flows between them, the house and
the grid. In 3D the panels light up with what they make, the battery's front shows its charge, and lines of light
carry the power along: from the roof to the house and the battery, from the battery to the house, between the house
and the grid. Every part is optional — panels without a battery, a battery and a grid meter without panels…

```jsonc
"energy": {
  "peak": 6000,
  "panels": [
    { "pos": [2.6, 1.9], "size": [4, 3.4], "rot": 0 },
    { "pos": [7.9, 1.9], "size": [4, 3.4], "rot": 0 }
  ],
  "battery": { "pos": [5.95, 3.77], "room": "living" },
  "sensors": {
    "solar":   { "service": "homeassistant", "id": "sensor.solarnet_power_photovoltaics" },
    "grid":    { "service": "homeassistant", "id": "sensor.solarnet_power_grid" },
    "load":    { "service": "homeassistant", "id": "sensor.solarnet_power_load" },
    "battery": { "service": "homeassistant", "id": "sensor.solarnet_power_battery" },
    "charge":  { "service": "homeassistant", "id": "sensor.byd_battery_box_premium_hv_state_of_charge" }
  }
}
```

| Field | Meaning |
| --- | --- |
| `panels` | Arrays of panels on the roof. `pos` is the `[x, z]` of the middle of one, `size` its `[width, depth]` in metres (a module is about 1 × 1.7 m: width across, depth up the slope), `rot` the way it faces, like furniture: `0` south, `90` east |
| `battery` | `pos` (`[x, z]` of its middle), `room` (the room it stands in; leave it out for a battery outside the house, which then shows in the view from outside only), `rot` (which way its front faces) |
| `peak` | The output in W at which the panels look their brightest. Without it, the most they have made since the view opened |
| `sensors` | What reports the power flow, by role — see below |

| Role | A sensor of | Reads |
| --- | --- | --- |
| `solar` | power (W, kW) | What the panels make |
| `grid` | power | Positive while the house draws from the grid, negative while it exports |
| `load` | power | What the house uses. Either sign: Fronius counts it as negative |
| `battery` | power | Positive while the battery discharges, negative while it charges |
| `charge` | battery level (%) | How full the battery is |

`grid` and `battery` can have `"invert": true` for a sensor that counts the other way round. Leave out a role
you have no sensor for: without `grid`, it is worked out from the others where it can be. Until at least one
sensor is linked, the power flow is simulated — a sunny day passes in six minutes — the way an unlinked lamp is.
**Solar & battery** in the editor places the panels and the battery and links the sensors.

## `scenes`

| Field | Meaning |
| --- | --- |
| `id`, `name` | Unique id and the label of the button |
| `icon` | `sun`, `sofa`, `film`, `moon`, `door`, `table`, `bed`, `tv` or `sparkles` |
| `lights` | Light id → what to set: `on`, `brightness` (0–1), `temp` (2200–6500 K), `color` (`#rrggbb`) |
| `acs` | AC id → what to set: `on`, `target`, `mode` (`cool`, `heat`, `dry`, `fan`, `auto`), `fan` (`auto`, `low`, `medium`, `high`, `turbo`) |

In both maps the key `"*"` applies to every device, and a device's own entry overrides it.

## Linking real devices

A light or an AC becomes real when it is linked to a device of a connected platform. The editor fills the link
in when you pick a device under **Real device**; by hand it looks like this:

```jsonc
// Home Assistant (an entity id), Philips Hue (the bridge's light id), Apple Home (HomeKit's service id)
{ "id": "living.floor", "name": "Floor lamp", "room": "living", "type": "floor", "pos": [5.8, 0.6],
  "link": { "service": "homeassistant", "id": "light.floor_lamp" } }

// An AC with a thermometer from any platform for its room temperature
{ "id": "living.ac", "name": "Living AC", "room": "living", "wall": "west", "pos": [0, 0.8],
  "link": { "service": "homeassistant", "id": "climate.living_room" },
  "sensor": { "service": "hue", "id": "<id of a Hue motion sensor's thermometer>" } }

// Smart Life keeps its own object
{ "id": "bed.ac", "name": "Bedroom AC", "room": "bedroom", "wall": "north", "pos": [2, 0],
  "tuya": { "deviceId": "<device id>", "sensorId": "<id of a Smart Life temperature sensor in the room>" } }
```

| Field | Meaning |
| --- | --- |
| `link.service` | `homeassistant`, `hue` or `homekit` |
| `link.id` | The device on that platform |
| `sensor` | ACs only, optional: `{ "service", "id" }` of a temperature sensor whose reading is shown as the room temperature. A simulated AC can have one too |
| `tuya.deviceId` | The Smart Life device |
| `tuya.sensorId` | ACs linked to Smart Life only, optional: a Smart Life temperature sensor |
| `tuya.codes.switch` | Optional: the data point that switches the device, when it is not the usual one — e.g. `"switch_2"` for the second gang of a double switch |

Devices without a link stay simulated, so a plan can mix real and imaginary ones, and one home can mix
platforms: Hue lamps, a Home Assistant air conditioner and a Smart Life plug side by side.

Device IDs identify your hardware. Remove the `link`, `sensor` and `tuya` objects (and `energy.sensors`) before
you share a plan.

## Errors

A plan that does not add up — an unknown room, a duplicate id, an opening that is not axis-aligned — is not
rendered half-way: the panel says what is wrong and where, and the editor shows the same in its status bar.
