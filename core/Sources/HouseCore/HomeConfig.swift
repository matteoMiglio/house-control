import Foundation

/// What a floor plan says about the things that can be controlled: rooms, lamps, ACs, scenes,
/// cameras and the energy section, with the defaults web/src/config.js `normalize()` fills in. Read by the native
/// controls; the 3D view still reads the plan itself.
public struct HomeConfig: Equatable, Sendable {
    public struct Group: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
        /// The built-in Outside group (lamps with `"room": "outside"`).
        public let outside: Bool
    }

    public struct Light: Identifiable, Equatable, Sendable {
        public let id, name, room, type: String
        /// Which of "brightness", "temp", "color" it supports; none for a plain smart plug.
        public let capabilities: [String]
        /// Linked to a real device (otherwise simulated, or "Not linked").
        public let linked: Bool

        public var dimmable: Bool { capabilities.contains("brightness") }
        /// Brightness, white or colour can be set: the lamp has a sheet.
        public var hasSheet: Bool { !capabilities.isEmpty }
        /// The icon the UI shows: a plain on/off lamp is a smart plug, unless it is plainly a
        /// light outside (config.js `lampIcon`).
        public var icon: String {
            capabilities.isEmpty && !HomeConfig.outdoorLightTypes.contains(type) ? "plug" : type
        }
    }

    public struct AC: Identifiable, Equatable, Sendable {
        public let id, name, room: String
        public let min, max: Double
        /// Linked to a real device (otherwise simulated, or "Not linked").
        public let linked: Bool
    }

    public struct Scene: Identifiable, Equatable, Sendable {
        public let id, name, icon: String
    }

    public static let outsideId = "outside"
    public static let outdoorLightTypes = ["lantern", "post", "flood"]

    public let name: String
    /// The rooms, then Outside when a lamp is out there (config.js `groups`).
    public let groups: [Group]
    public let lights: [Light]
    public let acs: [AC]
    public let scenes: [Scene]
    /// Solar panels, a home battery and their sensors (see Energy.swift); nil without them.
    public let energy: Energy?

    public init(plan: [String: Any]) {
        func text(_ value: Any?) -> String? { (value as? String).flatMap { $0.isEmpty ? nil : $0 } }
        func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }
        name = text(plan["name"]) ?? "Home"
        var roomIds = Set<String>()
        let rooms = (plan["rooms"] as? [[String: Any]] ?? []).compactMap { r -> Group? in
            guard let id = r["id"] as? String, roomIds.insert(id).inserted else { return nil }
            return Group(id: id, name: text(r["name"]) ?? id, outside: false)
        }
        // A repeated id counts once (the web refuses such a plan; the app must not crash on it).
        func unique<T: Identifiable>(_ list: [T]) -> [T] where T.ID == String {
            var seen = Set<String>()
            return list.filter { seen.insert($0.id).inserted }
        }
        lights = unique((plan["lights"] as? [[String: Any]] ?? []).compactMap { l in
            guard let id = l["id"] as? String else { return nil }
            return Light(id: id, name: text(l["name"]) ?? id, room: l["room"] as? String ?? "",
                         type: l["type"] as? String ?? "ceiling", capabilities: l["capabilities"] as? [String] ?? [],
                         linked: Self.isLinked(l))
        })
        acs = unique((plan["acs"] as? [[String: Any]] ?? []).compactMap { a in
            guard let id = a["id"] as? String else { return nil }
            // A set-point range the wrong way round (or empty) still makes a usable one.
            let low = number(a["min"]) ?? 16, high = number(a["max"]) ?? 30
            return AC(id: id, name: text(a["name"]) ?? id, room: a["room"] as? String ?? "",
                      min: Swift.min(low, high), max: Swift.max(high, low, Swift.min(low, high) + 1),
                      linked: Self.isLinked(a))
        })
        scenes = unique((plan["scenes"] as? [[String: Any]] ?? []).compactMap { s in
            guard let id = s["id"] as? String, !id.isEmpty else { return nil }
            return Scene(id: id, name: text(s["name"]) ?? id, icon: text(s["icon"]) ?? "sun")
        })
        energy = Energy(plan["energy"])
        // A plan may have a room of its own called "outside": then that room is meant.
        let outsideIsArea = !rooms.contains { $0.id == Self.outsideId }
        let lights = lights
        groups = rooms + (outsideIsArea && lights.contains { $0.room == Self.outsideId }
            ? [Group(id: Self.outsideId, name: "Outside", outside: true)] : [])
    }

    /// A lamp or an AC as the plan writes it is linked to a real device (config.js `isLinked`).
    public static func isLinked(_ device: [String: Any]) -> Bool {
        if let link = device["link"] as? [String: Any], let service = link["service"] as? String, !service.isEmpty,
           let id = link["id"] as? String, !id.isEmpty { return true }
        if let id = (device["tuya"] as? [String: Any])?["deviceId"] as? String, !id.isEmpty { return true }
        return false
    }

    public func light(_ id: String) -> Light? { lights.first { $0.id == id } }
    public func ac(_ id: String) -> AC? { acs.first { $0.id == id } }
    public func group(_ id: String) -> Group? { groups.first { $0.id == id } }
}

/// One lamp's state, as `HomeStore` keeps it.
public struct LightState: Equatable, Sendable {
    public var on = false
    public var brightness = 0.8
    /// White temperature in kelvin.
    public var temp = 3000.0
    /// "#rrggbb" while it shows a colour instead of white.
    public var color: String?

    public init(on: Bool = false, brightness: Double = 0.8, temp: Double = 3000, color: String? = nil) {
        self.on = on
        self.brightness = brightness
        self.temp = temp
        self.color = color
    }

    init(_ s: [String: JSONValue]) {
        on = s["on"]?.bool ?? false
        brightness = s["brightness"]?.number ?? 0.8
        temp = s["temp"]?.number ?? 3000
        color = s["color"]?.string
    }

    /// "80%", "On" or "Off" (panel.js `lightStatus`).
    public func status(_ light: HomeConfig.Light) -> String {
        guard on else { return "Off" }
        return light.dimmable ? "\(Int((brightness * 100).rounded()))%" : "On"
    }
}

/// One AC's state, as `HomeStore` keeps it.
public struct ACState: Equatable, Sendable {
    public var on = false
    public var target = 24.0
    public var mode = "cool"
    public var fan = "auto"
    public var swing = "swing"
    public var sleep = false
    public var eco = false
    public var roomTemp = 26.0
    /// On, but not running right now: the room is already warm (or cool) enough.
    public var idle = false

    public init() {}

    init(_ s: [String: JSONValue]) {
        on = s["on"]?.bool ?? false
        target = s["target"]?.number ?? 24
        mode = s["mode"]?.string ?? "cool"
        fan = s["fan"]?.string ?? "auto"
        swing = s["swing"]?.string ?? "swing"
        sleep = s["sleep"]?.bool ?? false
        eco = s["eco"]?.bool ?? false
        roomTemp = s["roomTemp"]?.number ?? 26
        idle = s["idle"]?.bool ?? false
    }
}

/// What an AC can do: what its platform reported, or everything for a simulated one
/// (store.js `acFeatures`).
public struct ACFeatures: Equatable, Sendable {
    public var modes = HomeStore.acModes
    public var fans = HomeStore.acFans
    public var sleep = true
    public var eco = true
    public var swing = true

    public init() {}

    init(_ value: JSONValue?) {
        guard case .object(let o)? = value else { return }
        if case .array(let modes)? = o["modes"] { self.modes = modes.compactMap(\.string) }
        if case .array(let fans)? = o["fans"] { self.fans = fans.compactMap(\.string) }
        sleep = o["sleep"]?.bool ?? true
        eco = o["eco"]?.bool ?? true
        swing = o["swing"]?.bool ?? true
    }
}

public extension HomeStore {
    func lightState(_ id: String) -> LightState { lights[id].map(LightState.init) ?? LightState() }
    func acState(_ id: String) -> ACState { acs[id].map(ACState.init) ?? ACState() }
    func acFeatures(_ id: String) -> ACFeatures { ACFeatures(features[id]) }
    /// The power flow right now: what the energy sensors report, or the simulation.
    var energyState: EnergyState { EnergyState(energy) }
}
