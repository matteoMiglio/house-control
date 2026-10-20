# Changelog

What changed in each release of House Control. The Mac app is on
[Releases](https://github.com/0xProbabillity/house-control/releases); the iPhone app is on TestFlight.

## Unreleased

### A window when you need one

- **Open House Control** (in the menu bar icon's menu and the panel's gear menu, or open the app again) gives it a
  window: the home in 3D with all its controls (on a wide window the controls sit in a column beside the model), and
  in the sidebar **Edit Home** and **Connections** (the editor), **AI Access**, **Pair iPhone** and **Settings**. The panel and the window show the same home, which moves between them. The editor
  keeps unsaved changes when you switch to another screen.
- It stays a menu bar app: the window opens by itself only the very first time, and the Dock icon is there only
  while it is open.
- **Settings** (in the sidebar, ⌘, or the gear menu): Open at Login, the island, the floor plan files, About.
- **Needs macOS 14 Sonoma.** Version 1.0 keeps working on macOS 13.
- **Zoom in the editor on the Mac:** pinch (or ⌘-scroll) to zoom the plan around the pointer, scroll or drag with
  Space held to move around it (never so far that the home slides out of sight), ⌘+ / ⌘− / ⌘0 and buttons in its
  corner.
- **Cameras only show from outside:** the cut-open rooms no longer show the ones hung on the house.
- **The island says when everything is off:** a dimmed house and *Off*, instead of hiding behind the notch. On a
  display without a notch it still steps out of the menu bar then, rather than cover the menu bar items.
- The island now shows the same controls as the panel for real air conditioners, and follows what the widgets change.
- On the Mac the state of every lamp and AC is now kept by the app itself, not by the panel's web page: the panel,
  the island, the widgets and AI Access all change one shared state, and what you set is kept in the app's data
  folder (taken over once from where the panel kept it before).

### The view from outside, for planning security cameras

- **Outside view:** the trees button shows the whole house on its plot, in daylight, with a roof, and lets you walk
  all the way round it. On the iPhone the button sits in the corner of the 3D view.
- **The plot** in the editor: a property line with draggable corners, and fences, garden walls, hedges, gates,
  trees, sheds, paving, and a parked car or van.
- **Security cameras:** drop one on the outside of a wall and it hangs there, looking away from it; drag its knob to
  aim it. Its angle of view, height, tilt, resolution and range are set in the editor, and the ground it covers is
  drawn on the plan and in 3D. Pick a camera to see the house through its lens.
- **Camera coverage:** the ground is coloured by what the cameras make out there, past walls, fences, hedges,
  sheds and cars, at four levels of detail (detect, observe, recognise, identify, after IEC 62676-4), with blind
  spots on the plot in red. **Camera coverage** in the editor adds it up and rates every door and gate; each camera
  says how far out it identifies a face.
- **Suggested cameras:** say how many more cameras and which lens, and House Control works out where on the outside
  walls they cover the most of the plot, doors and gates at Identify first. They are shown dotted on the plan with
  the difference they make, until you add them.
- **Outside lamps:** an **Outside** group in the panel next to the rooms, for lamps and plugs outside the house;
  picking it shows the house from outside. New fixtures for there: a wall lantern, a garden post light and a
  floodlight. In the editor a lamp dragged out of the house joins the group, and a lantern or floodlight dropped by
  an outer wall hangs on it.
  On the iPhone, Devices lists them under Outside, and **Add devices** can put lamps there.
- The outside view is now early evening, so lamps outside show.
- The demo apartment has a garden, a drive with a van on it, three cameras and four lamps outside to try it on.

### Mac

- **Open at Login**, in the menu bar icon's right-click menu and in the panel's gear menu: House Control starts with
  your Mac. It is the app's entry under System Settings → General → Login Items, so it can be switched off there too.
  Run from the disk image, the app asks to be moved to Applications first; moved there later, the login item follows it.

## 1.0.0 — 2026-10-15

### Widgets, controls and quick actions

- **Widgets** for the iPhone's Home Screen, Lock Screen and StandBy, and for the Mac's desktop: Home in 3D,
  Scenes, Light, Room, Climate and Home Status.
- **Control Center controls** on the iPhone: All Lights, a Light, a Scene and an Air Conditioner.
- **Quick actions** on the iPhone's app icon, chosen in Settings.
- Every widget is live: tap a lamp, a scene or an AC and it switches without opening the app. On the Mac the app in
  the menu bar carries it out; on the iPhone the widget talks to Home Assistant, Hue and Smart Life itself.
  See [docs/widgets.md](https://github.com/0xProbabillity/house-control/blob/main/docs/widgets.md).

### An iPhone app that needs no Mac

- **Floor plan editor on the phone:** the Mac's editor laid out for a finger — tap to select, drag what is selected,
  pan, pinch to zoom, details in a sheet from the bottom. **New home** starts from one room or a demo layout.
- **Home Assistant and Philips Hue** screens on the phone; servers and bridges on the Wi-Fi are found by themselves.
- **Devices:** link each lamp and AC to a real device from one searchable list, or add several devices to a room
  already linked.
- **Smart Life on a single phone:** save the sign-in code to Photos and scan it from the Smart Life app.
- **Sync both ways.** A paired Mac is optional. Plans edited on either side reach the other, and so do Home Assistant
  and Hue connections (the newest wins, a disconnect included). If both changed the plan while apart, the phone
  asks which one to keep.

### Two iPhone editions

- **App Store edition:** Home Assistant, Philips Hue and Apple Home.
- **Smart Life edition:** all of that plus Smart Life / Tuya, for TestFlight and your own phone.
- Smart Life now lives in its own module (`HouseSmartLife`), linked only by the Mac app and the Smart Life
  edition. The two editions are separate apps and can sit on one phone.

### Also

- **About** links (website, privacy policy, support, source) on the iPhone and in the Mac's menu.
- The editor only offers the platforms the app has.
- A privacy manifest for the widgets.
- From this release on, every Mac disk image carries a build provenance attestation:
  `gh attestation verify HouseControl-1.0.0.dmg --repo 0xProbabillity/house-control`
  ([#5](https://github.com/0xProbabillity/house-control/issues/5)).

### Fixed

- The iPhone never found Hue Bridges or Home Assistant servers on the network: iOS only browses the Bonjour types an
  app declares, and those two were missing.
- Widgets could jump back to an older state when the app started with widget taps still queued.

## 0.1.0 — 2026-10-14

The first public release: the home as a live 3D model in the Mac menu bar and on the iPhone, the island under the
notch, the floor plan editor, AI Access, and Smart Life, Home Assistant, Philips Hue and Apple Home.

This image was built while the repository was still private, so it has no build provenance attestation — only its
SHA-256 can be checked.
