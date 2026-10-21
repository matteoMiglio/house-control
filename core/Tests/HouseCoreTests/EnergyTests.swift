import Foundation
import Testing
@testable import HouseCore

/// Solar panels and a home battery: Home Assistant's power and battery sensors in the editor's
/// catalog and in the panel's terms, the hub reading them for a plan's energy section, and
/// the store keeping (or simulating) the power flow.
@MainActor
struct EnergyTests {
    /// States shaped like those of Home Assistant's Fronius integration (a Symo GEN24 with a BYD
    /// battery), plus what other integrations do differently.
    static func state(_ id: String, _ value: String, _ attributes: [String: Any]) -> [String: Any] {
        ["entity_id": id, "state": value, "attributes": attributes]
    }
    static let power: [String: Any] = ["device_class": "power", "unit_of_measurement": "W", "state_class": "measurement"]

    static let photovoltaics = state("sensor.solarnet_power_photovoltaics", "3245.62",
                                     power.merging(["friendly_name": "SolarNet Power photovoltaics"]) { $1 })
    static let grid = state("sensor.solarnet_power_grid", "-1180.3", power.merging(["friendly_name": "SolarNet Power grid"]) { $1 })
    static let load = state("sensor.solarnet_power_load", "-865.2", power.merging(["friendly_name": "SolarNet Power load"]) { $1 })
    static let battery = state("sensor.solarnet_power_battery", "-1200", power.merging(["friendly_name": "SolarNet Power battery"]) { $1 })
    static let charge = state("sensor.byd_battery_box_premium_hv_state_of_charge", "78.4",
                              ["device_class": "battery", "unit_of_measurement": "%", "state_class": "measurement",
                               "friendly_name": "BYD Battery-Box Premium HV State of charge"])
    /// The inverter asleep at night.
    static let asleep = state("sensor.symo_gen24_10_0_ac_power", "unavailable",
                              power.merging(["friendly_name": "Symo GEN24 10.0 AC power"]) { $1 })
    /// Another integration, in kilowatts.
    static let kilowatts = state("sensor.pv_power", "3.25", ["device_class": "power", "unit_of_measurement": "kW", "friendly_name": "PV power"])
    static let energyToday = state("sensor.solarnet_energy_day", "12450", ["device_class": "energy", "unit_of_measurement": "Wh",
                                                                       "state_class": "total_increasing"])
    static let autonomy = state("sensor.solarnet_relative_autonomy", "100", ["unit_of_measurement": "%", "state_class": "measurement"])

    // MARK: - Home Assistant

    @Test func powerAndBatterySensorsAreListed() {
        let solar = HomeAssistantService.device(from: Self.photovoltaics)
        #expect(solar?.kind == .power)
        #expect(solar?.name == "SolarNet Power photovoltaics")
        #expect(solar?.detail == "power sensor · W")
        #expect(HomeAssistantService.device(from: Self.kilowatts)?.detail == "power sensor · kW")
        let soc = HomeAssistantService.device(from: Self.charge)
        #expect(soc?.kind == .battery)
        #expect(soc?.detail == "battery level")
        #expect(soc?.dictionary(service: "homeassistant")["kind"] as? String == "battery")
        let night = HomeAssistantService.device(from: Self.asleep)
        #expect(night?.kind == .power)
        #expect(night?.online == false)
        // An energy total, a share in % and a power sensor without a unit are not power sensors.
        #expect(HomeAssistantService.device(from: Self.energyToday) == nil)
        #expect(HomeAssistantService.device(from: Self.autonomy) == nil)
        #expect(HomeAssistantService.device(from: Self.state("sensor.x", "3", ["device_class": "power"])) == nil)
        // A thermometer is still a thermometer.
        #expect(HomeAssistantService.device(from: Self.state("sensor.t", "21", ["unit_of_measurement": "°C"]))?.kind == .sensor)
    }

    @Test func readingsAreInWattsAndPercent() {
        #expect(HomeAssistantService.reading(from: Self.photovoltaics).power == 3245.62)
        #expect(HomeAssistantService.reading(from: Self.grid).power == -1180.3)
        #expect(HomeAssistantService.reading(from: Self.kilowatts).power == 3250)
        #expect(HomeAssistantService.reading(from: Self.state("sensor.m", "-0.5", ["unit_of_measurement": "MW"])).power == -500_000)
        let soc = HomeAssistantService.reading(from: Self.charge)
        #expect(soc.batteryLevel == 78.4)
        #expect(soc.power == nil && soc.temperature == nil)
        let night = HomeAssistantService.reading(from: Self.asleep)
        #expect(night.online == false)
        #expect(night.power == nil)
        #expect(HomeAssistantService.reading(from: Self.state("sensor.solarnet_power_grid", "unknown", Self.power)).online == false)
        #expect(HomeAssistantService.reading(from: Self.state("sensor.t", "70", ["unit_of_measurement": "°F"])).temperature ?? 0 > 21)
    }

    @Test func rolesTakeTheirSignConvention() {
        func value(_ role: EnergyRole, _ state: [String: Any], invert: Bool = false) -> Double? {
            role.value(HomeAssistantService.reading(from: state), invert: invert)
        }
        #expect(value(.solar, Self.photovoltaics) == 3245.62)
        #expect(value(.load, Self.load) == 865.2) // Fronius counts the house's use as negative
        #expect(value(.grid, Self.grid) == -1180.3)
        #expect(value(.grid, Self.grid, invert: true) == 1180.3)
        #expect(value(.battery, Self.battery) == -1200)
        #expect(value(.battery, Self.battery, invert: true) == 1200)
        #expect(value(.charge, Self.charge) == 78.4)
        #expect(EnergyRole.charge.value(DeviceReading(batteryLevel: 104)) == 100)
        #expect(value(.solar, Self.asleep) == nil)
        #expect(value(.charge, Self.photovoltaics) == nil)
        #expect(EnergyRole.charge.kind == .battery)
        #expect(EnergyRole.grid.kind == .power)
    }

    // MARK: - The plan's energy section

    static let plan: [String: Any] = [
        "name": "Sunny", "rooms": [["id": "garage", "rect": [0, 0, 4, 4]]],
        "energy": [
            "panels": [["pos": [2, 2], "size": [4, 3.4], "rot": 0]],
            "battery": ["pos": [0.2, 1], "room": "garage"],
            "sensors": [
                "solar": ["service": "homekit", "id": "PV"],
                "grid": ["service": "homekit", "id": "GRID", "invert": true],
                "load": ["service": "homekit", "id": "LOAD"],
                "charge": ["service": "homekit", "id": "SOC"],
                "battery": ["service": "homekit", "id": ""],
                "sun": ["service": "homekit", "id": "X"],
            ],
        ],
    ]

    @Test func homeConfigReadsTheEnergySection() {
        let energy = HomeConfig(plan: Self.plan).energy
        #expect(energy?.panels == 1)
        #expect(energy?.battery == true)
        #expect(energy?.peak == nil)
        #expect(energy?.sensors.keys.map(\.rawValue).sorted() == ["charge", "grid", "load", "solar"])
        #expect(energy?.sensors[.grid] == HomeConfig.Energy.Sensor(service: "homekit", id: "GRID", invert: true))
        #expect(energy?.simulated == false)
        #expect(HomeConfig(plan: ["rooms": []]).energy == nil)
        #expect(PlanEditor(plan: Self.plan).usedDevices[.init(service: "homekit", id: "SOC")] == "Battery charge")
    }

    @Test func theHubReadsTheEnergySensors() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let meters = MeterService()
        let hub = DeviceHub(directory: dir, secret: { _ in MemorySecretStore() }, homeKit: meters)
        hub.setLinks(from: Self.plan)
        #expect(hub.canPoll)
        #expect(meters.watched == ["PV", "GRID", "LOAD", "SOC"])
        let energy = await hub.poll()?["energy"] as? [String: Any]
        #expect(energy?["solar"] as? Double == 2400)
        #expect(energy?["grid"] as? Double == 300) // inverted: the meter counts export as positive
        #expect(energy?["load"] as? Double == 700)
        #expect(energy?["charge"] is NSNull) // offline
        #expect(energy?["battery"] == nil)   // not linked
        hub.setLinks(from: ["energy": ["panels": [["pos": [1, 1], "size": [2, 2]]]]])
        #expect(!hub.canPoll)
    }

    // MARK: - The store

    @Test func theStoreKeepsWhatTheSensorsReport() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = HomeStore(plan: Self.plan, file: file, transmit: nil)
        #expect(store.energyState.isEmpty) // linked sensors: nothing is made up
        var changes: [HomeStore.Change] = []
        store.onChange = { changes.append($0) }
        store.applyRemote(["lights": [:], "acs": [:], "features": [:],
                           "energy": ["solar": 2400.0, "grid": 300.0, "load": 700.0, "charge": NSNull()]])
        #expect(store.energyState == EnergyState(solar: 2400, grid: 300, load: 700))
        #expect(changes.count == 1 && changes[0].tick)
        store.applyRemote(["energy": ["solar": 2400.0, "grid": 300.0, "load": 700.0, "charge": NSNull()]])
        #expect(changes.count == 1) // nothing new
        store.applyRemote(["energy": ["solar": NSNull(), "charge": 51.0]])
        #expect(store.energyState == EnergyState(grid: 300, load: 700, charge: 51))
        #expect((store.json["energy"] as? [String: Any])?["charge"] as? Double == 51)
        store.save()
        let saved = (try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        #expect(saved != nil && saved?["energy"] == nil)
    }

    @Test func aPlanWithoutSensorsIsSimulated() {
        var plan = Self.plan
        var energy = plan["energy"] as? [String: Any] ?? [:]
        energy["sensors"] = nil
        plan["energy"] = energy
        let store = HomeStore(plan: plan, file: nil, transmit: nil)
        let first = store.energyState
        #expect(first.load != nil && first.solar != nil && first.charge != nil)
        #expect(store.simulateEnergy(at: Date().addingTimeInterval(9)))
        #expect(HomeStore(plan: ["name": "No sun"], file: nil, transmit: nil).energyState.isEmpty)
    }

    @Test func theSimulatedDayAddsUp() {
        var sim = EnergySimulation(peak: nil, area: 13.6, battery: true)
        let day = EnergySimulation.day
        let midnight = (Date().timeIntervalSince1970 / day).rounded(.down) * day
        let night = sim.step(at: midnight + day * 2 / 24, seconds: 3)
        #expect(night.solar == 0)
        #expect((night.battery ?? 0) > 0) // the battery runs the house
        var noon = night
        for s in stride(from: day * 10 / 24, to: day * 12 / 24, by: 3) { noon = sim.step(at: midnight + s, seconds: 3) }
        #expect((noon.solar ?? 0) > 1000)
        #expect((noon.battery ?? 0) <= 0) // charging, or full
        for state in [night, noon] {
            let balance = (state.solar ?? 0) + (state.battery ?? 0) + (state.grid ?? 0) - (state.load ?? 0)
            #expect(abs(balance) < 0.001)
            #expect(state.consumption == state.load)
            #expect((0...100).contains(state.charge ?? -1))
        }
        #expect(EnergyState(solar: 1000, grid: -200, battery: -300).consumption == 500)
        #expect(EnergyState(solar: 1000).consumption == nil)
        var noBattery = EnergySimulation(peak: 5000, area: 0, battery: false)
        let alone = noBattery.step(at: midnight + day / 2, seconds: 3)
        #expect(alone.battery == nil && alone.charge == nil)
        #expect(alone.grid == (alone.load ?? 0) - (alone.solar ?? 0))
    }
}

/// The lab's Home Assistant (tools/lab/homeassistant.sh), with its pretend Fronius sensors:
/// listed, read, and changes arriving over the WebSocket. Runs with `HOUSE_TEST_HA_URL` and
/// `HOUSE_TEST_HA_TOKEN` set.
@MainActor
struct LiveEnergyTests {
    static let env = ProcessInfo.processInfo.environment

    @Test(.enabled(if: env["HOUSE_TEST_HA_URL"] != nil && env["HOUSE_TEST_HA_TOKEN"] != nil))
    func theLabsSolarSensorsAreListedReadAndWatched() async throws {
        let url = try #require(Self.env["HOUSE_TEST_HA_URL"]), token = try #require(Self.env["HOUSE_TEST_HA_TOKEN"])
        let service = HomeAssistantService(vault: MemorySecretStore())
        try await service.connect(url: url, token: token)
        defer { service.disconnect() }
        let devices = try await service.devices()
        let solar = "sensor.solarnet_power_photovoltaics", soc = "sensor.byd_battery_box_premium_hv_state_of_charge"
        #expect(devices.first { $0.id == solar }?.kind == .power)
        #expect(devices.first { $0.id == soc }?.kind == .battery)
        #expect(devices.first { $0.id == "sensor.pv_power" }?.detail == "power sensor · kW")

        func setSolar(_ watts: Int) async throws {
            var request = URLRequest(url: try #require(URL(string: url + "/api/services/input_number/set_value")))
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["entity_id": "input_number.lab_solar", "value": watts])
            _ = try await URLSession.shared.data(for: request)
        }
        try await setSolar(2500)
        var changes = 0
        service.onChange = { changes += 1 }
        service.watch([solar])
        try await Task.sleep(nanoseconds: 1_500_000_000) // the WebSocket subscribes
        try await setSolar(4100)
        for _ in 0..<50 where changes == 0 { try await Task.sleep(nanoseconds: 100_000_000) }
        #expect(changes > 0, "a change of a watched sensor arrives over the WebSocket")
        let readings = try await service.read([solar, "sensor.pv_power", soc, "sensor.solarnet_power_load"])
        #expect(readings[solar]?.power == 4100)
        #expect(abs((readings["sensor.pv_power"]?.power ?? 0) - 4100) < 0.01) // 4.1 kW
        #expect(readings[soc]?.batteryLevel != nil)
        #expect(EnergyRole.load.value(try #require(readings["sensor.solarnet_power_load"])) ?? -1 >= 0)
    }
}

/// A platform whose meters report a fixed power flow; the charge sensor is offline.
private final class MeterService: DeviceService {
    let id = "homekit"
    let title = "Meters"
    var onChange: (() -> Void)?
    var isConnected: Bool { true }
    var info: [String: Any] { ["connected": true] }
    var watched: Set<String> = []

    func devices() async throws -> [ServiceDevice] { [] }
    func read(_ ids: Set<String>) async throws -> [String: DeviceReading] {
        [
            "PV": DeviceReading(power: 2400),
            "GRID": DeviceReading(power: -300),
            "LOAD": DeviceReading(power: -700),
            "SOC": DeviceReading(online: false),
        ].filter { ids.contains($0.key) }
    }
    func send(kind: DeviceKind, id: String, patch: [String: Any], state: [String: Any]) async throws {}
    func watch(_ ids: Set<String>) { watched = ids }
    func disconnect() {}
}
