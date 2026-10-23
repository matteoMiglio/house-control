import Foundation
import Testing
@testable import HouseCore

/// HomeConfig reads a plan the way web/src/config.js does (Fixtures/ is written by
/// scripts/config-fixtures.mjs from normalize()).
@MainActor
struct HomeConfigTests {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../..").standardized

    static func json(_ path: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: repo.appendingPathComponent(path))) as? [String: Any] ?? [:]
    }

    @Test(arguments: ["home", "studio"])
    func readsTheDemoPlansLikeTheWeb(plan: String) throws {
        let config = HomeConfig(plan: try Self.json("web/public/plans/\(plan).json"))
        let web = try Self.json("core/Tests/HomeStoreTests/Fixtures/\(plan).json")
        #expect(config.name == web["name"] as? String)
        let groups = (web["groups"] as? [[String: Any]] ?? []).map { HomeConfig.Group(id: $0["id"] as! String, name: $0["name"] as! String, outside: $0["outside"] as! Bool) }
        #expect(config.groups == groups)
        let lights = web["lights"] as? [[String: Any]] ?? []
        #expect(config.lights.map(\.id) == lights.map { $0["id"] as! String })
        for (light, expected) in zip(config.lights, lights) {
            #expect(light.name == expected["name"] as? String)
            #expect(light.room == expected["room"] as? String)
            #expect(light.capabilities == expected["capabilities"] as? [String])
            #expect(light.icon == expected["icon"] as? String)
        }
        let acs = web["acs"] as? [[String: Any]] ?? []
        #expect(config.acs.map(\.id) == acs.map { $0["id"] as! String })
        #expect(config.acs.map(\.min) == acs.map { ($0["min"] as! NSNumber).doubleValue })
        let scenes = web["scenes"] as? [[String: Any]] ?? []
        #expect(config.scenes.map(\.icon) == scenes.map { $0["icon"] as! String })
        #expect(config.scenes.map(\.name) == scenes.map { $0["name"] as! String })
        let energy = web["energy"] as? [String: Any]
        #expect((config.energy == nil) == (energy == nil))
        if let energy, let mine = config.energy {
            #expect(mine.panels == energy["panels"] as? Int)
            #expect(mine.battery == energy["battery"] as? Bool)
            #expect(mine.batteryRoom == energy["batteryRoom"] as? String)
            #expect(mine.peak == (energy["peak"] as? NSNumber)?.doubleValue)
            let sensors = energy["sensors"] as? [String: [String: Any]] ?? [:]
            #expect(mine.sensors.keys.map(\.rawValue).sorted() == sensors.keys.sorted())
            for (role, sensor) in mine.sensors {
                #expect(sensor.id == sensors[role.rawValue]?["id"] as? String)
                #expect(sensor.invert == sensors[role.rawValue]?["invert"] as? Bool)
            }
        }
    }

    @Test func theEnergySectionReadsLikeTheWeb() {
        let config = HomeConfig(plan: ["energy": [
            "panels": [["pos": [1, 1], "size": [2, 2]]],
            "sensors": ["grid": ["service": "homeassistant", "id": "sensor.grid", "invert": true],
                        "load": ["service": "homeassistant", "id": ""]],
        ]])
        #expect(config.energy?.panels == 1)
        #expect(config.energy?.battery == false)
        #expect(config.energy?.sensors == [.grid: .init(service: "homeassistant", id: "sensor.grid", invert: true)])
        #expect(config.energy?.simulated == false)
        #expect(HomeConfig(plan: ["energy": ["battery": ["pos": [1, 1]]]]).energy?.simulated == true)
    }

    /// The same words as energy.js (web/test/energy.test.js checks the same cases).
    @Test func thePowerFlowReadsLikeTheWeb() {
        #expect(EnergyState.format(watts: 640) == "640 W")
        #expect(EnergyState.format(watts: 0) == "0 W")
        #expect(EnergyState.format(watts: 999.4) == "999 W")
        #expect(EnergyState.format(watts: 999.6) == "1.0 kW")
        #expect(EnergyState.format(watts: 3245.62) == "3.2 kW")
        #expect(EnergyState.format(watts: 3250) == "3.3 kW")
        #expect(EnergyState.format(watts: 12040) == "12.0 kW")
        #expect(EnergyState.format(watts: -1180.3) == "1.2 kW")
        #expect(EnergyState.format(watts: nil) == "—")
        #expect(EnergyState.format(charge: 78.4) == "78%")
        #expect(EnergyState.format(charge: nil) == "—")

        let panelsOnly = HomeConfig(plan: ["energy": ["panels": [["pos": [3, 2], "size": [4, 3.4]]]]]).energy!
        #expect(panelsOnly.gridStatus(EnergyState(grid: 640)) == "Importing 640 W")
        #expect(panelsOnly.gridStatus(EnergyState(grid: -1180)) == "Exporting 1.2 kW")
        #expect(panelsOnly.gridStatus(EnergyState(grid: 10)) == "Idle")
        #expect(panelsOnly.gridStatus(EnergyState(solar: 1000, load: 1500)) == "Importing 500 W")
        #expect(panelsOnly.gridStatus(EnergyState(solar: 1000)) == "—")
        #expect(EnergyState(battery: -700).batteryStatus == "Charging 700 W")
        #expect(EnergyState(battery: 1250).batteryStatus == "Discharging 1.3 kW")
        #expect(EnergyState(battery: 5).batteryStatus == "Idle")
        #expect(EnergyState().batteryStatus == "—")
    }

    @Test func theSolarTileShowsWhatThePlanHas() {
        let panel: [String: Any] = ["pos": [3, 2], "size": [4, 3.4]]
        let sensor: [String: Any] = ["service": "homeassistant", "id": "x"]
        func energy(_ section: [String: Any]) -> HomeConfig.Energy { HomeConfig(plan: ["energy": section]).energy! }
        let both = energy(["panels": [panel], "battery": ["pos": [1, 1], "room": "living"]])
        let panelsOnly = energy(["panels": [panel]])
        let batteryOnly = energy(["battery": ["pos": [1, 1]]])
        let sensorsOnly = energy(["sensors": ["solar": sensor, "charge": sensor]])
        #expect(both.batteryRoom == "living" && batteryOnly.batteryRoom == nil)
        #expect([both.hasSolar, both.hasBattery] == [true, true])
        #expect([panelsOnly.hasSolar, panelsOnly.hasBattery] == [true, false])
        #expect([batteryOnly.hasSolar, batteryOnly.hasBattery] == [false, true])
        #expect([sensorsOnly.hasSolar, sensorsOnly.hasBattery] == [true, true])
        #expect(both.name == "Solar" && batteryOnly.name == "Battery" && energy([:]).name == "Solar")

        #expect(both.status(EnergyState(solar: 3245, charge: 78.4)) == "3.2 kW · 78%")
        #expect(panelsOnly.status(EnergyState(solar: 640, charge: 78)) == "640 W")
        #expect(batteryOnly.status(EnergyState(solar: 0, charge: 78)) == "78%")
        #expect(both.status(EnergyState(charge: 78)) == "— · 78%")
        #expect(both.status(EnergyState(solar: 640)) == "640 W · —")
        #expect(both.status(EnergyState()) == "—")
        #expect(energy([:]).status(EnergyState()) == "—")
    }

    /// energy.js checks the same cases ("what depends on a reading that is not known…").
    @Test func whatDependsOnAnUnknownReadingIsNotKnown() {
        let full = HomeConfig(plan: ["energy": ["panels": [["pos": [3, 2], "size": [4, 3.4]]], "battery": ["pos": [1, 1]]]]).energy!
        let batteryOnly = HomeConfig(plan: ["energy": ["battery": ["pos": [1, 1]]]]).energy!
        let offline = EnergyState(grid: nil, load: 600, battery: 0)
        #expect(full.gridPower(offline) == nil)
        #expect(full.gridStatus(offline) == "—")
        #expect(full.consumption(EnergyState(grid: 300, battery: 0)) == nil)
        #expect(batteryOnly.consumption(EnergyState(grid: 300, battery: 0)) == 300)
        #expect(batteryOnly.gridPower(EnergyState(load: 600, battery: 100)) == 500)
        #expect(full.consumption(EnergyState(solar: 1000, grid: -200, battery: -300)) == 500)
        #expect(full.consumption(EnergyState(grid: 9, load: 640)) == 640)
    }

    @Test func theIslandShowsProductionOnlyWhileThereIsSome() {
        let panels = HomeConfig(plan: ["energy": ["panels": [["pos": [3, 2], "size": [4, 3.4]]]]]).energy!
        let batteryOnly = HomeConfig(plan: ["energy": ["battery": ["pos": [1, 1]]]]).energy!
        #expect(panels.production(EnergyState(solar: 3245)) == "3.2 kW")
        #expect(panels.production(EnergyState(solar: 640)) == "640 W")
        #expect(panels.production(EnergyState(solar: 0)) == nil) // night
        #expect(panels.production(EnergyState(solar: EnergyState.idleWatts - 1)) == nil)
        #expect(panels.production(EnergyState()) == nil) // not known
        #expect(batteryOnly.production(EnergyState(solar: 3000)) == nil)
    }

    @Test func theIslandsRightEarFollowsTheSetting() {
        let sun = IslandEar.solar("3.2 kW")
        // Auto: a running AC first, then the sun.
        #expect(IslandEar.resting(.auto, acRunning: true, production: "3.2 kW") == .ac)
        #expect(IslandEar.resting(.auto, acRunning: false, production: "3.2 kW") == sun)
        #expect(IslandEar.resting(.auto, acRunning: false, production: nil) == nil)
        // AC: never the sun.
        #expect(IslandEar.resting(.ac, acRunning: true, production: "3.2 kW") == .ac)
        #expect(IslandEar.resting(.ac, acRunning: false, production: "3.2 kW") == nil)
        // Solar: the sun even over a running AC, the AC at night.
        #expect(IslandEar.resting(.solar, acRunning: true, production: "3.2 kW") == sun)
        #expect(IslandEar.resting(.solar, acRunning: true, production: nil) == .ac)
        #expect(IslandEar.resting(.solar, acRunning: false, production: nil) == nil)
        #expect(IslandEar.Choice(rawValue: "solar") == .solar && IslandEar.Choice(rawValue: "sun") == nil)
    }

    @Test func noPanelsMakeNoSunWhateverThePeak() {
        var sim = EnergySimulation(peak: 5000, area: 0, battery: true)
        #expect(sim.step(at: EnergySimulation.day / 2, seconds: 3).solar == 0)
        let plan: [String: Any] = ["energy": ["peak": 5000, "battery": ["pos": [1, 1]]]]
        var fromPlan = EnergySimulation(plan: plan)
        #expect(fromPlan?.step(at: EnergySimulation.day / 2, seconds: 3).solar == 0)
    }

    @Test func aRoomCalledOutsideIsNotTheOutsideGroup() {
        let config = HomeConfig(plan: ["rooms": [["id": "outside", "name": "Patio"]],
                                       "lights": [["id": "l", "room": "outside", "type": "post"]]])
        #expect(config.groups == [HomeConfig.Group(id: "outside", name: "Patio", outside: false)])
    }

    @Test func aDeviceIsLinkedByItsLinkOrItsTuyaId() {
        let config = HomeConfig(plan: [
            "lights": [["id": "ha", "link": ["service": "ha", "id": "light.x"]], ["id": "tuya", "tuya": ["deviceId": "abc"]],
                       ["id": "half", "link": ["service": "ha", "id": ""]], ["id": "none"]],
            "acs": [["id": "ac", "link": ["service": "ha", "id": "climate.x"]], ["id": "fake"]],
        ])
        #expect(config.lights.map(\.linked) == [true, true, false, false])
        #expect(config.acs.map(\.linked) == [true, false])
    }

    @Test func stateAndStatusComeFromTheStore() {
        let store = HomeStore(plan: ["lights": [["id": "a", "capabilities": ["brightness"]], ["id": "p"]]], file: nil, transmit: nil)
        store.setLight("a", ["on": true, "brightness": 0.42])
        store.setLight("p", ["on": true])
        let config = HomeConfig(plan: ["lights": [["id": "a", "capabilities": ["brightness"]], ["id": "p"]]])
        #expect(store.lightState("a").status(config.light("a")!) == "42%")
        #expect(store.lightState("p").status(config.light("p")!) == "On")
        #expect(config.light("p")!.icon == "plug")
        #expect(store.acFeatures("none").modes.count == 5)
    }

    @Test func aBrokenPlanStillReadsSafely() {
        let config = HomeConfig(plan: [
            "rooms": [["id": "r"], ["id": "r"]],
            "lights": [["id": "a", "name": "First"], ["id": "a", "name": "Second"]],
            "acs": [["id": "ac", "min": 30, "max": 16], ["id": "flat", "min": 20, "max": 20]],
        ])
        #expect(config.groups.count == 1)
        #expect(config.lights.map(\.name) == ["First"])
        #expect(config.ac("ac").map { $0.min...$0.max } == 16...30)
        #expect(config.ac("flat").map { $0.min...$0.max } == 20...21)
    }
}
