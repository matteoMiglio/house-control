import Foundation

/// What a plan's `energy.sensors` can link: the home's power flow, as any platform's sensors
/// report it (Home Assistant's Fronius integration, SolarEdge, a Shelly on the meter…).
public enum EnergyRole: String, CaseIterable, Sendable {
    /// Solar production.
    case solar
    /// The grid: positive while the house imports, negative while it exports.
    case grid
    /// What the house uses.
    case load
    /// The home battery: positive while it discharges, negative while it charges.
    case battery
    /// The battery's state of charge, in %.
    case charge

    /// The kind of sensor the role takes: a battery level for the charge, a power sensor for the rest.
    public var kind: DeviceKind { self == .charge ? .battery : .power }

    /// What the editor and Connections call it (config.js `ENERGY_ROLES`).
    public var title: String {
        switch self {
        case .solar: return "Solar production"
        case .grid: return "Grid"
        case .load: return "House consumption"
        case .battery: return "Battery power"
        case .charge: return "Battery charge"
        }
    }

    /// A reading in the panel's convention (see `EnergyState`). Platforms disagree about the sign
    /// of a grid or battery sensor, hence `invert`; production and consumption are taken as they
    /// come, whichever sign the sensor gives them (Fronius reports the house's load as negative).
    public func value(_ reading: DeviceReading, invert: Bool = false) -> Double? {
        guard reading.online else { return nil }
        if self == .charge { return reading.batteryLevel.map { Swift.min(100, Swift.max(0, $0)) } }
        guard let watts = reading.power else { return nil }
        switch self {
        case .solar, .load: return abs(watts)
        default: return invert ? -watts : watts
        }
    }
}

/// The home's power flow right now, with the house as the point of view. Nil: not known
/// (no sensor for it, or it is offline).
public struct EnergyState: Equatable, Sendable {
    /// Produced by the solar panels, in W.
    public var solar: Double?
    /// From the grid, in W: positive while importing, negative while exporting.
    public var grid: Double?
    /// Used by the house, in W.
    public var load: Double?
    /// From the battery, in W: positive while it discharges, negative while it charges.
    public var battery: Double?
    /// The battery's state of charge, 0…100 %.
    public var charge: Double?

    public init(solar: Double? = nil, grid: Double? = nil, load: Double? = nil, battery: Double? = nil, charge: Double? = nil) {
        self.solar = solar
        self.grid = grid
        self.load = load
        self.battery = battery
        self.charge = charge
    }

    init(_ s: [String: JSONValue]) {
        solar = s["solar"]?.number
        grid = s["grid"]?.number
        load = s["load"]?.number
        battery = s["battery"]?.number
        charge = s["charge"]?.number
    }

    /// As `HomeStore` keeps it and the pages read it, without what is not known.
    var json: [String: JSONValue] {
        let values: [(EnergyRole, Double?)] = [(.solar, solar), (.grid, grid), (.load, load), (.battery, battery), (.charge, charge)]
        return Dictionary(uniqueKeysWithValues: values.compactMap { role, v in v.map { (role.rawValue, JSONValue.number($0)) } })
    }

    /// Nothing is known.
    public var isEmpty: Bool { [solar, grid, load, battery, charge].allSatisfy { $0 == nil } }
}

// MARK: - In words

/// The power flow as the panel writes it (energy.js `formatWatts`, `batteryStatus`…).
public extension EnergyState {
    /// Below this a flow is idle (energy.js `IDLE_WATTS`).
    static let idleWatts = 20.0

    /// A power, whichever way it flows: in W below 1 kW ("640", "W"), in kW with one decimal from
    /// there ("3.2", "kW"); nil when not known.
    static func watts(_ w: Double?) -> (number: String, unit: String)? {
        guard let w, w.isFinite else { return nil }
        let watts = Int(abs(w).rounded())
        if watts < 1000 { return ("\(watts)", "W") }
        let tenths = Int((Double(watts) / 100).rounded())
        return ("\(tenths / 10).\(tenths % 10)", "kW")
    }

    /// "640 W", "3.2 kW", or "—" when not known.
    static func format(watts w: Double?) -> String { watts(w).map { "\($0.number) \($0.unit)" } ?? "—" }

    /// A battery's charge: "78%", or "—".
    static func format(charge c: Double?) -> String { c.map { "\(Int($0.rounded()))%" } ?? "—" }

    /// "Charging 700 W", "Discharging 1.2 kW", "Idle", or "—".
    var batteryStatus: String {
        guard let b = battery else { return "—" }
        if abs(b) < Self.idleWatts { return "Idle" }
        return "\(b < 0 ? "Charging" : "Discharging") \(Self.format(watts: b))"
    }
}

public extension HomeConfig {
    /// A plan's `energy` section: solar panels on the roof, a home battery, and the sensors that
    /// report the power flow (config.js `normalize`).
    struct Energy: Equatable, Sendable {
        public struct Sensor: Equatable, Sendable {
            public let service, id: String
            /// The sensor counts the other way round from the panel (see `EnergyRole.value`).
            public let invert: Bool
        }

        /// How many arrays of panels are on the roof.
        public let panels: Int
        /// A home battery stands in the plan.
        public let battery: Bool
        /// The room it stands in; nil outside the house (or without a battery).
        public let batteryRoom: String?
        /// The output, in W, at which the panels look their brightest; nil: the most seen so far.
        public let peak: Double?
        public let sensors: [EnergyRole: Sensor]

        init?(_ value: Any?) {
            guard let e = value as? [String: Any] else { return nil }
            panels = (e["panels"] as? [Any])?.count ?? 0
            battery = e["battery"] is [String: Any]
            batteryRoom = (e["battery"] as? [String: Any])?["room"] as? String
            peak = (e["peak"] as? NSNumber)?.doubleValue
            var sensors: [EnergyRole: Sensor] = [:]
            for (key, link) in e["sensors"] as? [String: Any] ?? [:] {
                guard let role = EnergyRole(rawValue: key), let link = link as? [String: Any],
                      let service = link["service"] as? String, let id = link["id"] as? String,
                      !service.isEmpty, !id.isEmpty else { continue }
                sensors[role] = Sensor(service: service, id: id, invert: link["invert"] as? Bool ?? false)
            }
            self.sensors = sensors
        }

        /// Without a single real sensor the power flow is simulated, like an unlinked lamp.
        public var simulated: Bool { sensors.isEmpty }

        /// Production to show: there are panels, or a solar sensor (energy.js `energyHas`).
        public var hasSolar: Bool { panels > 0 || sensors[.solar] != nil }
        /// A battery to show: one stands in the plan, or a sensor reports one.
        public var hasBattery: Bool { battery || sensors[.battery] != nil || sensors[.charge] != nil }

        /// What the panel calls it: Solar, or Battery for a battery without panels (energy.js `energyName`).
        public var name: String { hasBattery && !hasSolar ? "Battery" : "Solar" }

        /// The panels' and the battery's power, to work the rest out with: 0 for what the plan does
        /// not have, nil for what it has but is not known right now (energy.js `sources`).
        private func sources(_ s: EnergyState) -> (solar: Double, battery: Double)? {
            let solar = s.solar ?? (hasSolar ? nil : 0), battery = s.battery ?? (hasBattery ? nil : 0)
            guard let solar, let battery else { return nil }
            return (solar, battery)
        }

        /// What the house uses: its own sensor's reading, or what flows in from the grid, the panels
        /// and the battery when all of that is known (energy.js `consumption`).
        public func consumption(_ s: EnergyState) -> Double? {
            if let load = s.load { return load }
            guard let grid = s.grid, let from = sources(s) else { return nil }
            return Swift.max(0, grid + from.solar + from.battery)
        }

        /// From the grid, in W (negative: exporting): its own sensor's reading, or what the house uses
        /// beyond what the panels and the battery give it, when all of that is known (energy.js `gridPower`).
        public func gridPower(_ s: EnergyState) -> Double? {
            if let grid = s.grid { return grid }
            guard let load = s.load, let from = sources(s) else { return nil }
            return load - Swift.max(0, from.solar) - from.battery
        }

        /// "Importing 640 W", "Exporting 1.2 kW", "Idle", or "—" (energy.js `gridStatus`).
        public func gridStatus(_ s: EnergyState) -> String {
            guard let g = gridPower(s) else { return "—" }
            if abs(g) < EnergyState.idleWatts { return "Idle" }
            return "\(g > 0 ? "Importing" : "Exporting") \(EnergyState.format(watts: g))"
        }

        /// What the panels make, worth a glance beside the notch: "3.2 kW" while they make some
        /// (`idleWatts` or more); nil at night, while not known, or without panels.
        public func production(_ s: EnergyState) -> String? {
            guard hasSolar, let solar = s.solar, solar >= EnergyState.idleWatts else { return nil }
            return EnergyState.format(watts: solar)
        }

        /// The Solar tile's line: production · charge, of what the plan has ("3.2 kW · 78%", "640 W",
        /// "— · 78%"); "—" when nothing is known (energy.js `energyStatus`).
        public func status(_ s: EnergyState) -> String {
            let parts = (hasSolar ? [EnergyState.format(watts: s.solar)] : []) + (hasBattery ? [EnergyState.format(charge: s.charge)] : [])
            return parts.allSatisfy { $0 == "—" } ? "—" : parts.joined(separator: " · ")
        }
    }
}

/// A made-up day of solar production, household use and a battery between them, for plans
/// whose energy section has no real sensors (the demos). A day passes in six minutes, so the
/// panels, the battery and the grid all get their turn. The same as store.js `simulateEnergy`.
public struct EnergySimulation: Sendable {
    public static let day: Double = 360
    static let capacity: Double = 10_000 // Wh
    static let batteryPower: Double = 3_000 // W

    /// Full output, in W.
    let peak: Double
    let hasBattery: Bool
    /// The battery's state of charge, in %.
    var charge = 55.0

    /// `area`: square metres of panels; without a `peak` they make 200 W each. No panels make
    /// nothing, whatever the peak.
    public init(peak: Double?, area: Double, battery: Bool) {
        self.peak = area > 0 ? peak ?? area * 200 : 0
        hasBattery = battery
    }

    /// The plan's energy section as written, or nil when it has nothing to simulate.
    public init?(plan: [String: Any]) {
        guard let energy = HomeConfig.Energy(plan["energy"]), energy.simulated else { return nil }
        let section = plan["energy"] as? [String: Any] ?? [:]
        let area = (section["panels"] as? [[String: Any]] ?? []).reduce(0.0) { sum, p in
            let size = (p["size"] as? [NSNumber])?.map(\.doubleValue) ?? []
            return sum + (size.count == 2 ? Swift.max(0, size[0]) * Swift.max(0, size[1]) : 0)
        }
        guard area > 0 || energy.battery else { return nil }
        self.init(peak: energy.peak, area: area, battery: energy.battery)
    }

    /// The power flow at `time` (seconds since 1970), `seconds` after the last step.
    public mutating func step(at time: Double, seconds: Double) -> EnergyState {
        let hour = (time / Self.day).truncatingRemainder(dividingBy: 1) * 24
        let sun = hour > 6 && hour < 20 ? pow(sin(Double.pi * (hour - 6) / 14), 1.3) : 0
        let clouds = 1 - 0.35 * pow(0.5 + 0.5 * sin(time / 23), 3) * (0.5 + 0.5 * sin(time / 7.3))
        let solar = (peak * 0.88 * sun * clouds).rounded()
        func around(_ from: Double, _ to: Double, _ watts: Double) -> Double { hour >= from && hour < to ? watts : 0 }
        let load = (330 + 120 * (0.5 + 0.5 * sin(time / 11)) + around(7, 8, 650) + around(12, 13, 1_100)
            + around(18.5, 20, 1_500) + around(20, 23, 280)).rounded()
        var battery = 0.0
        if hasBattery {
            let surplus = solar - load
            if surplus > 0, charge < 99.5 { battery = -Swift.min(surplus, Self.batteryPower) }
            else if surplus < 0, charge > 8 { battery = Swift.min(-surplus, Self.batteryPower) }
            let hours = seconds * 24 / Self.day
            charge = Swift.min(100, Swift.max(0, charge - battery * hours / Self.capacity * 100))
        }
        return EnergyState(solar: solar, grid: load - solar - battery, load: load,
                           battery: hasBattery ? battery : nil, charge: hasBattery ? (charge * 10).rounded() / 10 : nil)
    }
}
