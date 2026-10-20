import Foundation

/// The state of every lamp and AC of the active home, kept by the app: the one place a
/// change is made, sent to the real device, rolled back when the device refuses it, and
/// saved. The web pages (the panel, the island) draw what it holds and send it what the
/// user does. A port of `web/src/store.js`, which does the same in a plain browser.
@MainActor
public final class HomeStore {
    /// Sends one device's change: the hub's `command`. Replies `["ok": true]`, or `"error"`
    /// with the `"failed"` fields when the device refused some of them.
    public typealias Transmit = (_ message: [String: Any], _ reply: @escaping ([String: Any]) -> Void) -> Void

    public struct Change {
        /// Who made it when it was not the person at the screen: "Widget", "ChatGPT"…
        public var source: String?
        /// Only a simulated room temperature moved.
        public var tick = false
    }

    nonisolated public static let acModes = ["cool", "heat", "dry", "fan", "auto"]
    nonisolated public static let acFans = ["auto", "low", "medium", "high", "turbo"]

    public private(set) var lights: [String: [String: JSONValue]] = [:]
    public private(set) var acs: [String: [String: JSONValue]] = [:]
    /// What each real AC can do, as its platform reports it.
    public private(set) var features: [String: JSONValue] = [:]
    /// The scene the home is in, until something is changed by hand.
    public private(set) var scene: String?
    /// True when the state was read back from disk (or taken from a page that had it saved).
    public private(set) var restored = false

    public let name: String
    /// Any lamp or AC linked to a real device.
    public let isLinked: Bool
    public var onChange: ((Change) -> Void)?
    /// A real device refused a change: its id and why.
    public var onDeviceError: ((_ id: String, _ message: String) -> Void)?

    private struct LightConfig { let id: String; let room: String; let caps: Set<String> }
    private struct ACConfig { let id: String; let min: Double; let max: Double; let sensed: Bool }
    private struct Scene { let id: String; let lights: [String: [String: JSONValue]]; let acs: [String: [String: JSONValue]] }

    private let lightConfigs: [LightConfig]
    private let acConfigs: [String: ACConfig]
    private let acOrder: [String]
    private let scenes: [Scene]
    private let outdoorTemp: Double
    private let file: URL?
    private let transmit: Transmit?
    private var saveTask: Task<Void, Never>?
    private var simulation: Timer?
    /// Replaced by the store of another plan: it sends, saves and tells nothing any more.
    private var retired = false
    /// A retired store still finishing the commands it had started (see `retire`).
    private var draining = true
    /// What the devices reported before the state was restored, laid over whatever is
    /// restored late (`restoreIfNew`), since it is newer.
    private var reported: [String: [String: Any]] = [:]

    /// `plan` is the floor plan as written (home.json); `file` is where the state is kept
    /// (nil: not kept); `transmit` reaches the devices (nil: everything is simulated).
    public init(plan: [String: Any], file: URL?, transmit: Transmit?) {
        name = (plan["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Home"
        outdoorTemp = (plan["outdoorTemp"] as? NSNumber)?.doubleValue ?? 27
        let rawLights = plan["lights"] as? [[String: Any]] ?? []
        let rawACs = plan["acs"] as? [[String: Any]] ?? []
        lightConfigs = rawLights.compactMap { l in
            guard let id = l["id"] as? String else { return nil }
            return LightConfig(id: id, room: l["room"] as? String ?? "", caps: Set(l["capabilities"] as? [String] ?? []))
        }
        var acConfigs: [String: ACConfig] = [:]
        var acOrder: [String] = []
        for a in rawACs {
            guard let id = a["id"] as? String else { continue }
            let sensed = ((a["tuya"] as? [String: Any])?["sensorId"] as? String).map { !$0.isEmpty } == true
                || ((a["sensor"] as? [String: Any])?["id"] as? String).map { !$0.isEmpty } == true
                || ((a["link"] as? [String: Any])?["id"] as? String).map { !$0.isEmpty } == true
            acConfigs[id] = ACConfig(id: id, min: (a["min"] as? NSNumber)?.doubleValue ?? 16,
                                     max: (a["max"] as? NSNumber)?.doubleValue ?? 30, sensed: sensed)
            acOrder.append(id)
        }
        self.acConfigs = acConfigs
        self.acOrder = acOrder
        scenes = (plan["scenes"] as? [[String: Any]] ?? []).compactMap { s in
            guard let id = s["id"] as? String else { return nil }
            func patches(_ value: Any?) -> [String: [String: JSONValue]] {
                (value as? [String: Any] ?? [:]).compactMapValues { ($0 as? [String: Any])?.compactMapValues(JSONValue.init(any:)) }
            }
            return Scene(id: id, lights: patches(s["lights"]), acs: patches(s["acs"]))
        }
        isLinked = (rawLights + rawACs).contains { device in
            if let link = device["link"] as? [String: Any], let service = link["service"] as? String, !service.isEmpty,
               let id = link["id"] as? String, !id.isEmpty { return true }
            if let id = (device["tuya"] as? [String: Any])?["deviceId"] as? String, !id.isEmpty { return true }
            return false
        }
        self.file = file
        self.transmit = transmit

        for l in rawLights {
            guard let id = l["id"] as? String else { continue }
            lights[id] = ["on": .bool(false), "brightness": .number(0.8), "temp": .number(3000),
                          "color": (l["color"] as? String).map(JSONValue.string) ?? .null]
        }
        for id in acOrder {
            acs[id] = ["on": .bool(false), "target": .number(24), "mode": .string("cool"), "fan": .string("auto"),
                       "swing": .string("swing"), "sleep": .bool(false), "eco": .bool(false),
                       "roomTemp": .number(Swift.min(outdoorTemp - 2, 27))]
        }
        if let file, let data = try? Data(contentsOf: file),
           let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            restore(saved)
        }
    }

    // MARK: - Reading

    /// Everything a page needs to draw the home, in the shape `web/src/store.js` keeps.
    public var json: [String: Any] {
        ["lights": lights.mapValues { $0.mapValues(\.any) }, "acs": acs.mapValues { $0.mapValues(\.any) },
         "features": features.mapValues(\.any), "scene": (scene as Any?) ?? NSNull()]
    }

    /// For the menu bar icon: how many lamps are on, and the first running AC.
    public var summary: [String: Any] {
        let running = acOrder.compactMap { id in acs[id].flatMap { $0["on"]?.bool == true ? $0 : nil } }
        return ["lightsOn": lights.values.filter { $0["on"]?.bool == true }.count,
                "lightsTotal": lights.count,
                "acOn": running.count,
                "acTarget": running.first?["target"]?.number.map { Int($0) } as Any? ?? NSNull(),
                "acMode": running.first?["mode"]?.string as Any? ?? NSNull()]
    }

    // MARK: - Changes

    public func setLight(_ id: String, _ patch: [String: Any], source: String? = nil) {
        guard writeLight(id, json(patch)) else { return }
        scene = nil
        emit(source)
    }

    public func toggleLight(_ id: String, source: String? = nil) {
        guard let on = lights[id]?["on"]?.bool else { return }
        setLight(id, ["on": !on], source: source)
    }

    public func setAllLights(_ on: Bool, source: String? = nil) {
        var any = false
        for l in lightConfigs { any = writeLight(l.id, ["on": .bool(on)]) || any }
        guard any else { return }
        scene = nil
        emit(source)
    }

    public func setAC(_ id: String, _ patch: [String: Any], source: String? = nil) {
        if writeAC(id, json(patch)) { emit(source) }
    }

    public func applyScene(_ id: String, source: String? = nil) {
        guard let definition = scenes.first(where: { $0.id == id }) else { return }
        for l in lightConfigs {
            var patch = (definition.lights["*"] ?? [:]).merging(definition.lights[l.id] ?? [:]) { $1 }
            // A scene that sets a white temperature should not be overridden by a stale colour.
            if patch["color"] == nil, patch["temp"] != nil { patch["color"] = .null }
            writeLight(l.id, patch)
        }
        for acId in acOrder {
            let patch = (definition.acs["*"] ?? [:]).merging(definition.acs[acId] ?? [:]) { $1 }
            if !patch.isEmpty { writeAC(acId, patch) }
        }
        scene = id
        emit(source)
    }

    /// A widget's or a control's action, with toggles resolved against the state here.
    public func run(_ action: HomeAction, source: String? = "Widget") {
        switch action.kind {
        case .light:
            guard let id = action.id, let on = lights[id]?["on"]?.bool else { return }
            setLight(id, ["on": action.on ?? !on], source: source)
        case .room:
            guard let id = action.id else { return }
            let ids = lightConfigs.filter { $0.room == id }.map(\.id)
            let on = action.on ?? !ids.contains { lights[$0]?["on"]?.bool == true }
            for l in ids { setLight(l, ["on": on], source: source) }
        case .allLights:
            setAllLights(action.on ?? !lights.values.contains { $0["on"]?.bool == true }, source: source)
        case .scene:
            if let id = action.id { applyScene(id, source: source) }
        case .acPower:
            guard let id = action.id, let on = acs[id]?["on"]?.bool else { return }
            setAC(id, ["on": action.on ?? !on], source: source)
        case .acTarget:
            guard let id = action.id, let target = action.target, acs[id] != nil else { return }
            setAC(id, ["target": target], source: source)
        }
    }

    /// A page's `intent` message: what the user did there.
    public func perform(_ intent: [String: Any]) {
        let source = intent["source"] as? String
        let id = intent["id"] as? String ?? ""
        let patch = intent["patch"] as? [String: Any] ?? [:]
        switch intent["op"] as? String {
        case "setLight": setLight(id, patch, source: source)
        case "setAllLights": setAllLights(intent["on"] as? Bool ?? false, source: source)
        case "setAC": setAC(id, patch, source: source)
        case "applyScene": applyScene(id, source: source)
        default: break
        }
    }

    /// State the real devices reported. Never sent back to them as a command.
    public func applyRemote(_ update: [String: Any]) {
        if !restored {
            for key in ["lights", "acs", "features"] {
                for (id, value) in update[key] as? [String: Any] ?? [:] {
                    let merged = (reported[key]?[id] as? [String: Any] ?? [:]).merging(value as? [String: Any] ?? [:]) { $1 }
                    reported[key, default: [:]][id] = key == "features" ? value : merged
                }
            }
        }
        if adopt(update) { emit(nil, local: false) }
    }

    /// State another device already made true (a widget that reached the lamp itself):
    /// shown here, never sent to the devices again.
    public func adoptDelivered(_ state: [String: Any], source: String? = "Widget") {
        var any = adopt(state)
        let next = state["scene"] as? String // NSNull: no scene
        if state["scene"] != nil, next != scene {
            scene = next
            any = true
        }
        if any { emit(source) }
    }

    /// Takes what a page had saved in the browser, from before the app kept the state.
    /// Only while nothing has been saved here yet.
    public func restoreIfNew(_ saved: [String: Any]) {
        guard !restored, saved["home"] as? String == name else { return }
        restore(saved)
        guard restored else { return }
        _ = adopt(reported)
        reported = [:]
        emit(nil)
    }

    /// A first look at a home nothing was saved for: the cozy scene and the first AC at 23°.
    /// Never for real hardware, which reports its own state.
    public func startIfNew() {
        guard !restored, !isLinked else { return }
        restored = true
        reported = [:]
        let first = scenes.first { $0.id == "cozy" } ?? (scenes.count > 1 ? scenes[1] : scenes.first)
        if let first { applyScene(first.id) }
        if let ac = acOrder.first { setAC(ac, ["on": true, "target": 23]) }
        save()
    }

    // MARK: - Simulated room temperature

    /// Without a real sensor the room temperature drifts towards the set-point while an AC
    /// runs, and back towards the outdoor-ish ambient when it is off.
    public func startSimulation(every interval: TimeInterval = 3) {
        simulation?.invalidate()
        simulation = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.simulate() }
        }
    }

    /// Stops, for a store another plan's replaces: nothing it does later is saved or shown.
    /// With `keepSending` (the devices are linked as before) what it still had to send goes
    /// out; otherwise that is dropped, since the same ids may now reach other devices.
    public func retire(keepSending: Bool) {
        save()
        retired = true
        stopSimulation()
        saveTask?.cancel()
        onChange = nil
        if !keepSending {
            outbox.removeAll()
            draining = false
            onDeviceError = nil
        }
    }

    /// The plan's device links, to tell whether a new plan reaches the same devices.
    public static func linkKey(_ plan: [String: Any]?) -> Data? {
        var links: [String: Any] = [:]
        for device in (plan?["lights"] as? [[String: Any]] ?? []) + (plan?["acs"] as? [[String: Any]] ?? []) {
            guard let id = device["id"] as? String else { continue }
            links[id] = ["tuya", "link", "sensor"].reduce(into: [String: Any]()) { $0[$1] = device[$1] }
        }
        return try? JSONSerialization.data(withJSONObject: links, options: .sortedKeys)
    }

    public func stopSimulation() {
        simulation?.invalidate()
        simulation = nil
    }

    func simulate() {
        var any = false
        let ambient = Swift.min(outdoorTemp - 2, 27)
        for id in acOrder {
            guard let config = acConfigs[id], !config.sensed, var ac = acs[id],
                  let room = ac["roomTemp"]?.number else { continue }
            let on = ac["on"]?.bool == true
            let goal = on && ac["mode"]?.string != "fan" ? ac["target"]?.number ?? ambient : ambient
            let step = on ? 0.2 : 0.1
            let next = abs(goal - room) <= step ? goal : room + (goal > room ? step : -step)
            guard next != room else { continue }
            ac["roomTemp"] = .number((next * 10).rounded() / 10)
            acs[id] = ac
            any = true
        }
        guard any else { return }
        onChange?(Change(source: nil, tick: true))
        scheduleSave()
    }

    // MARK: - Writing

    private func json(_ patch: [String: Any]) -> [String: JSONValue] { patch.compactMapValues(JSONValue.init(any:)) }

    /// What `remote` writes leave alone: nothing is sent, nothing is rolled back.
    @discardableResult
    private func writeLight(_ id: String, _ patch: [String: JSONValue], remote: Bool = false) -> Bool {
        guard var current = lights[id], let caps = lightConfigs.first(where: { $0.id == id })?.caps else { return false }
        var clean: [String: JSONValue] = [:]
        if let on = patch["on"] { clean["on"] = .bool(on.truthy) }
        if caps.contains("brightness"), let b = patch["brightness"]?.number { clean["brightness"] = .number(Swift.min(1, Swift.max(0.05, b))) }
        if caps.contains("temp"), let t = patch["temp"]?.number {
            clean["temp"] = .number(Swift.min(6500, Swift.max(2200, t)))
            clean["color"] = .null
        }
        if caps.contains("color"), let color = patch["color"] { clean["color"] = color }
        // Only what actually changed is worth sending to the device.
        let diff = clean.filter { current[$0.key] != $0.value }
        guard !diff.isEmpty else { return false }
        let before = diff.keys.reduce(into: [String: JSONValue]()) { $0[$1] = current[$1] ?? .null }
        current.merge(clean) { $1 }
        lights[id] = current
        if !remote { dispatch(.light, id, diff, before) }
        return true
    }

    @discardableResult
    private func writeAC(_ id: String, _ patch: [String: JSONValue], remote: Bool = false) -> Bool {
        guard var current = acs[id], let config = acConfigs[id] else { return false }
        var clean = patch
        if let t = clean["target"]?.number { clean["target"] = .number(Swift.min(config.max, Swift.max(config.min, t.rounded()))) }
        let diff = clean.filter { current[$0.key] != $0.value }
        guard !diff.isEmpty else { return false }
        let before = diff.keys.reduce(into: [String: JSONValue]()) { $0[$1] = current[$1] ?? .null }
        current.merge(clean) { $1 }
        acs[id] = current
        var sendable = diff
        sendable["roomTemp"] = nil
        if !remote, !sendable.isEmpty { dispatch(.ac, id, sendable, before) }
        return true
    }

    /// Takes lights, acs and features from another view of the home, without sending anything.
    private func adopt(_ other: [String: Any]) -> Bool {
        var any = false
        for (id, s) in other["lights"] as? [String: Any] ?? [:] {
            if let s = s as? [String: Any] { any = writeLight(id, json(s), remote: true) || any }
        }
        for (id, s) in other["acs"] as? [String: Any] ?? [:] {
            if let s = s as? [String: Any] { any = writeAC(id, json(s), remote: true) || any }
        }
        for (id, f) in other["features"] as? [String: Any] ?? [:] {
            guard acs[id] != nil, let value = JSONValue(any: f), features[id] != value else { continue }
            features[id] = value
            any = true
        }
        return any
    }

    private func restore(_ saved: [String: Any]) {
        guard saved["home"] as? String == name else { return }
        for (id, s) in saved["lights"] as? [String: Any] ?? [:] {
            guard lights[id] != nil, let s = s as? [String: Any] else { continue }
            lights[id]?.merge(json(s)) { $1 }
        }
        for (id, s) in saved["acs"] as? [String: Any] ?? [:] {
            guard acs[id] != nil, let s = s as? [String: Any] else { continue }
            acs[id]?.merge(json(s)) { $1 }
        }
        for (id, f) in saved["features"] as? [String: Any] ?? [:] where acs[id] != nil {
            features[id] = JSONValue(any: f)
        }
        scene = saved["scene"] as? String
        restored = true
    }

    /// `local`: the user (or a widget, or an AI) changed something. That settles the state:
    /// nothing saved earlier or invented for a new home replaces it any more.
    private func emit(_ source: String?, local: Bool = true) {
        if local {
            restored = true
            reported = [:]
        }
        onChange?(Change(source: source))
        scheduleSave()
    }

    private func scheduleSave() {
        guard file != nil, !retired else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Writes the state now (also on quit, so the last change is not lost).
    public func save() {
        guard let file, !retired else { return }
        saveTask?.cancel()
        var out = json
        out["home"] = name
        guard let data = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]) else { return }
        try? data.write(to: file, options: .atomic)
    }

    // MARK: - Sending to the devices

    // One command per device is in flight at a time. Whatever changes meanwhile is merged
    // into a single follow-up, so dragging a slider costs a couple of requests (or infrared
    // key presses) instead of dozens. A change the device refuses is rolled back.
    private static let coolDown: [DeviceKind: Double] = [.light: 0.3, .ac: 0.9]
    private static let lostReply: Double = 20

    private final class Slot {
        var pending: [String: JSONValue]?
        /// The oldest value of each pending field: what a refused follow-up returns to.
        var before: [String: JSONValue] = [:]
    }
    private var outbox: [String: Slot] = [:]

    private func dispatch(_ kind: DeviceKind, _ id: String, _ patch: [String: JSONValue], _ before: [String: JSONValue]) {
        guard transmit != nil, !retired else { return }
        if let slot = outbox[id] {
            slot.pending = (slot.pending ?? [:]).merging(patch) { $1 }
            slot.before = before.merging(slot.before) { $1 }
            return
        }
        let slot = Slot()
        outbox[id] = slot
        send(kind, id, patch, before, slot)
    }

    private func send(_ kind: DeviceKind, _ id: String, _ patch: [String: JSONValue], _ before: [String: JSONValue], _ slot: Slot) {
        let started = Date()
        let state = (kind == .light ? lights[id] : acs[id]) ?? [:]
        let message: [String: Any] = ["kind": kind.rawValue, "id": id, "patch": patch.mapValues(\.any), "state": state.mapValues(\.any)]
        var answered = false
        let finish: ([String: Any]) -> Void = { [weak self] reply in
            guard !answered, let self, !self.retired || self.draining else { return }
            answered = true
            if let error = reply["error"] as? String {
                self.rollback(kind, id, patch, before, slot, failed: reply["failed"] as? [String], message: error)
            }
            let wait = Swift.max(0, (Self.coolDown[kind] ?? 0.3) - Date().timeIntervalSince(started))
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                MainActor.assumeIsolated { self.next(kind, id, slot) }
            }
        }
        // Never let a lost reply block the device for good.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.lostReply) { MainActor.assumeIsolated { finish(["ok": true]) } }
        transmit?(message) { reply in
            if Thread.isMainThread {
                MainActor.assumeIsolated { finish(reply) }
            } else {
                let copy = NSDictionary(dictionary: reply)
                DispatchQueue.main.async { MainActor.assumeIsolated { finish(copy as? [String: Any] ?? [:]) } }
            }
        }
    }

    private func next(_ kind: DeviceKind, _ id: String, _ slot: Slot) {
        guard !retired || draining else { return }
        guard let pending = slot.pending else {
            outbox[id] = nil
            return
        }
        let before = slot.before
        slot.pending = nil
        slot.before = [:]
        send(kind, id, pending, before, slot)
    }

    private func rollback(_ kind: DeviceKind, _ id: String, _ patch: [String: JSONValue], _ before: [String: JSONValue],
                          _ slot: Slot, failed: [String]?, message: String) {
        guard var current = kind == .light ? lights[id] : acs[id] else { return }
        var any = false
        for key in failed ?? Array(patch.keys) {
            guard let sent = patch[key] else { continue }
            // Changed again in the meantime: that follow-up now falls back to the last good value.
            if slot.pending?[key] != nil { slot.before[key] = before[key]; continue }
            if current[key] != sent { continue } // a real device reported something newer
            current[key] = before[key] ?? .null
            any = true
        }
        if kind == .light { lights[id] = current } else { acs[id] = current }
        if any { emit(nil, local: false) }
        onDeviceError?(id, message)
    }
}

private extension JSONValue {
    /// JavaScript's `Boolean(value)`.
    var truthy: Bool {
        switch self {
        case .null: return false
        case .bool(let b): return b
        case .number(let n): return n != 0 && !n.isNaN
        case .string(let s): return !s.isEmpty
        case .array, .object: return true
        }
    }
}
