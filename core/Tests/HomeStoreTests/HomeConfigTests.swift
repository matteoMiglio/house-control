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
    }

    @Test func aRoomCalledOutsideIsNotTheOutsideGroup() {
        let config = HomeConfig(plan: ["rooms": [["id": "outside", "name": "Patio"]],
                                       "lights": [["id": "l", "room": "outside", "type": "post"]]])
        #expect(config.groups == [HomeConfig.Group(id: "outside", name: "Patio", outside: false)])
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
