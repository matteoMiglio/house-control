import Foundation
import Observation
import HouseCore

/// What the native home controls draw and do: the active plan (`HomeConfig`), the state
/// `HomeStore` holds for it, and what is on screen (the room picked, the sheet open, the view
/// from outside). The counterpart of web/src/ui/panel.js; the page keeps the 3D model.
@MainActor
@Observable
final class HomeModel {
    enum Sheet: Hashable {
        case light(String)
        case ac(String)
        /// A security camera, with how far it makes out each level of detail (from the page).
        case camera(Camera)
    }

    /// A camera's sheet: its numbers, and its reach for each DORI level (coverage.js).
    struct Camera: Hashable {
        struct Level: Hashable { let name: String; let color: String; let reach: Double }
        let id, name: String
        let fov, y, tilt, range: Double
        let levels: [Level]
    }

    struct Toast: Equatable {
        let id = UUID()
        let text: String
        /// Who, when an AI assistant made the change (instead of a device refusing one).
        let ai: String?
    }

    /// Tells the 3D page what to show: `focus`, `setOutside`, `setCoverageShown`, `bump`.
    @ObservationIgnored var tellPage: ((_ function: String, _ args: [Any]) -> Void)?
    /// The header's gear (the floor plan menu) and AI badge.
    @ObservationIgnored var onGear: (() -> Void)?
    @ObservationIgnored var onAgentBadge: (() -> Void)?

    private(set) var config = HomeConfig(plan: [:])
    private(set) var lights: [String: LightState] = [:]
    private(set) var acs: [String: ACState] = [:]
    private(set) var features: [String: ACFeatures] = [:]
    private(set) var scene: String?

    /// The group the device list shows: "all" or a group id.
    private(set) var room = "all"
    private(set) var sheet: Sheet?
    /// The whole house on its plot instead of the cut-open rooms.
    private(set) var outside = false
    /// Outside because the Outside group was picked (leaving it goes back in).
    @ObservationIgnored private var autoOutside = false
    var agentLive = false
    private(set) var toast: Toast?
    /// The page could not start (a plan the web refuses, no WebGL): it shows why, and the
    /// controls stay out of its way.
    var pageError: String?
    /// The AC option card whose menu is open ("mode", "fan", "swing"), and where it and its menu
    /// are in the window (SwiftUI's coordinates), so a click elsewhere closes it.
    var openMenu: String? {
        didSet { if openMenu != oldValue { menuFrames = [] } }
    }
    @ObservationIgnored var menuFrames: [CGRect] = []

    @ObservationIgnored private weak var store: HomeStore?
    @ObservationIgnored private var toastTimer: Task<Void, Never>?

    // MARK: - Plan and state

    /// A new plan (or the same one again): the whole home, nothing open, the rooms seen from inside.
    func load(plan: [String: Any], store: HomeStore) {
        self.store = store
        config = HomeConfig(plan: plan)
        room = "all"
        sheet = nil
        outside = false
        autoOutside = false
        refresh()
    }

    /// Copies the store's state, after its changes (once per turn of the run loop).
    func refresh() {
        guard let store else { return }
        let lights = Dictionary(config.lights.map { ($0.id, store.lightState($0.id)) }) { first, _ in first }
        let acs = Dictionary(config.acs.map { ($0.id, store.acState($0.id)) }) { first, _ in first }
        let features = Dictionary(config.acs.map { ($0.id, store.acFeatures($0.id)) }) { first, _ in first }
        if lights != self.lights { self.lights = lights }
        if acs != self.acs { self.acs = acs }
        if features != self.features { self.features = features }
        if store.scene != scene { scene = store.scene }
    }

    // MARK: - Reading

    func light(_ id: String) -> LightState { lights[id] ?? LightState() }
    func ac(_ id: String) -> ACState { acs[id] ?? ACState() }
    func features(_ id: String) -> ACFeatures { features[id] ?? ACFeatures() }
    func groupName(_ id: String) -> String { config.group(id)?.name ?? id }

    var lightsOn: Int { config.lights.filter { light($0.id).on }.count }
    var firstACOn: ACState? { config.acs.map { ac($0.id) }.first(where: \.on) }
    var anyOn: Bool { lightsOn > 0 || firstACOn != nil }

    /// Lamps on in a group ("all" for the whole home).
    func onCount(in group: String) -> Int {
        config.lights.filter { (group == "all" || $0.room == group) && light($0.id).on }.count
    }

    func inScope(_ room: String) -> Bool { self.room == "all" || room == self.room }

    // MARK: - Doing

    func toggleLight(_ id: String) {
        tellPage?("bump", [id])
        store?.toggleLight(id)
    }

    func setLight(_ id: String, _ patch: [String: Any]) { store?.setLight(id, patch) }
    func setAC(_ id: String, _ patch: [String: Any]) { store?.setAC(id, patch) }
    func applyScene(_ id: String) { store?.applyScene(id) }

    /// All on / All off for the group shown.
    func bulk(_ on: Bool) {
        if room == "all" {
            store?.setAllLights(on)
        } else {
            for l in config.lights where l.room == room { store?.setLight(l.id, ["on": on]) }
        }
    }

    /// The power button: everything off when anything is on, else every lamp on.
    func toggleEverything() {
        if anyOn {
            store?.setAllLights(false)
            for a in config.acs { store?.setAC(a.id, ["on": false]) }
        } else {
            store?.setAllLights(true)
        }
    }

    /// A room tab: that room, or the whole home again when it was already picked.
    func selectRoom(_ id: String) {
        room = room == id ? "all" : id
        let isOutside = config.group(room)?.outside == true
        // The Outside group is seen from outside; leaving it goes back in, unless outside was chosen by hand.
        if isOutside, !outside {
            autoOutside = true
            setOutsideView(true)
        } else if !isOutside, autoOutside {
            autoOutside = false
            setOutsideView(false)
        }
        tellPage?("setCoverageShown", [!isOutside])
        focus(groupFocus(room))
    }

    /// The trees button: the view from outside, or back in.
    func toggleOutside() {
        autoOutside = false
        setOutsideView(!outside)
    }

    private func setOutsideView(_ on: Bool) {
        outside = on
        tellPage?("setOutside", [on])
    }

    func openSheet(_ next: Sheet) {
        sheet = next
        switch next {
        case .light(let id): focus(groupFocus(config.light(id)?.room ?? "all"))
        case .ac(let id): focus(["kind": "ac", "id": id])
        case .camera(let camera): focus(["kind": "camera", "id": camera.id])
        }
    }

    @discardableResult
    func closeSheet() -> Bool {
        guard sheet != nil else { return false }
        openMenu = nil
        sheet = nil
        focus(groupFocus(room))
        return true
    }

    /// Escape: an open menu first, then the sheet. False when there was neither.
    func closeTopmost() -> Bool {
        if openMenu != nil {
            openMenu = nil
            return true
        }
        return closeSheet()
    }

    /// The page went off screen: next time it starts on the whole home, nothing open.
    func reset() {
        let hadSheet = closeSheet()
        if room != "all" { selectRoom(room) } else if hadSheet { focus(nil) }
    }

    /// Everything the 3D view should show, again (after the page moved or reloaded).
    func resendView() {
        tellPage?("setOutside", [outside])
        tellPage?("setCoverageShown", [config.group(room)?.outside != true])
        switch sheet {
        case .ac(let id)?: focus(["kind": "ac", "id": id])
        case .camera(let camera)?: focus(["kind": "camera", "id": camera.id])
        case .light(let id)?: focus(groupFocus(config.light(id)?.room ?? "all"))
        case nil: focus(groupFocus(room))
        }
    }

    /// A widget's link or HOUSE_OPEN_DEVICE: a lamp's or an AC's sheet, or a room.
    func open(device id: String) {
        if config.ac(id) != nil {
            openSheet(.ac(id))
        } else if config.light(id) != nil {
            openSheet(.light(id))
        } else if config.group(id) != nil {
            closeSheet()
            if room != id { selectRoom(id) }
        }
    }

    /// Something was clicked in the 3D view (lamps toggle in the page itself).
    func picked(_ message: [String: Any]) {
        let id = message["id"] as? String ?? ""
        switch message["kind"] as? String {
        case "ac": openSheet(.ac(id))
        case "room": selectRoom(id)
        case "camera":
            guard let c = message["camera"] as? [String: Any] else { return }
            func n(_ key: String) -> Double { (c[key] as? NSNumber)?.doubleValue ?? 0 }
            let levels = (c["levels"] as? [[String: Any]] ?? []).map {
                Camera.Level(name: $0["name"] as? String ?? "", color: $0["color"] as? String ?? "#ffffff",
                             reach: ($0["reach"] as? NSNumber)?.doubleValue ?? 0)
            }
            openSheet(.camera(Camera(id: id, name: c["name"] as? String ?? id, fov: n("fov"), y: n("y"),
                                     tilt: n("tilt"), range: n("range"), levels: levels)))
        default: break
        }
    }

    private func focus(_ target: [String: Any]?) {
        tellPage?("focus", [target ?? NSNull()])
    }

    /// What the 3D view frames for a group: a room, or the whole model (the outside is all of it).
    private func groupFocus(_ group: String) -> [String: Any]? {
        guard let g = config.group(group), !g.outside else { return nil }
        return ["kind": "room", "id": g.id]
    }

    func showToast(_ text: String, ai: String? = nil) {
        toast = Toast(text: text, ai: ai)
        toastTimer?.cancel()
        toastTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    /// A real device refused a change.
    func deviceError(_ id: String, _ message: String) {
        let name = config.light(id)?.name ?? config.ac(id)?.name ?? id
        showToast("\(name): \(message)")
    }
}
