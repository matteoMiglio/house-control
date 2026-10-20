import Foundation
import Testing
@testable import HouseCore

@MainActor
struct HomeStoreTests {
    static let plan: [String: Any] = [
        "name": "Test home", "outdoorTemp": 30,
        "lights": [
            ["id": "lamp", "room": "living", "capabilities": ["brightness", "temp", "color"]],
            ["id": "plug", "room": "living"],
            ["id": "bed", "room": "bedroom", "capabilities": ["brightness"]],
        ],
        "acs": [["id": "ac", "room": "living", "min": 16, "max": 30]],
        "scenes": [
            ["id": "bright", "lights": ["*": ["on": true, "brightness": 1, "temp": 4200]]],
            ["id": "cozy", "lights": ["*": ["on": false], "lamp": ["on": true, "color": "#ff7a3c"]], "acs": ["*": ["target": 22]]],
        ],
    ]

    /// A pretend hub: keeps every command and answers when the test says so.
    final class Devices {
        var sent: [[String: Any]] = []
        var replies: [([String: Any]) -> Void] = []
        var transmit: HomeStore.Transmit {
            { [unowned self] message, reply in
                self.sent.append(message)
                self.replies.append(reply)
            }
        }
        func answer(_ index: Int, _ reply: [String: Any] = ["ok": true]) { replies[index](reply) }
    }

    func light(_ store: HomeStore, _ id: String, _ key: String) -> JSONValue? { store.lights[id]?[key] }

    @Test func setLightKeepsOnlyWhatTheLampCanDo() {
        let devices = Devices()
        let store = HomeStore(plan: Self.plan, file: nil, transmit: devices.transmit)
        store.setLight("plug", ["on": true, "brightness": 0.3])
        store.setLight("lamp", ["brightness": 2, "temp": 9000])
        #expect(light(store, "plug", "on") == .bool(true))
        #expect(light(store, "plug", "brightness") == .number(0.8))
        #expect(light(store, "lamp", "brightness") == .number(1))
        #expect(light(store, "lamp", "temp") == .number(6500))
        #expect(devices.sent.count == 2)
        #expect((devices.sent[0]["patch"] as? [String: Any])?.keys.sorted() == ["on"])
    }

    @Test func changesWhileACommandIsInFlightAreMergedIntoOneFollowUp() async throws {
        let devices = Devices()
        let store = HomeStore(plan: Self.plan, file: nil, transmit: devices.transmit)
        store.setLight("lamp", ["brightness": 0.5])
        store.setLight("lamp", ["brightness": 0.6])
        store.setLight("lamp", ["brightness": 0.7, "on": true])
        #expect(devices.sent.count == 1)
        devices.answer(0)
        try await Task.sleep(nanoseconds: 450_000_000)
        #expect(devices.sent.count == 2)
        let follow = devices.sent[1]["patch"] as? [String: Any]
        #expect(follow?["brightness"] as? Double == 0.7)
        #expect(follow?["on"] as? Bool == true)
    }

    @Test func aRefusedChangeIsRolledBack() async throws {
        let devices = Devices()
        let store = HomeStore(plan: Self.plan, file: nil, transmit: devices.transmit)
        var errors: [String] = []
        store.onDeviceError = { id, message in errors.append("\(id): \(message)") }
        store.setLight("lamp", ["on": true, "brightness": 0.4])
        devices.answer(0, ["error": "offline", "failed": ["brightness"]])
        #expect(light(store, "lamp", "on") == .bool(true))
        #expect(light(store, "lamp", "brightness") == .number(0.8))
        #expect(errors == ["lamp: offline"])
    }

    @Test func remoteStateIsNeverSentBack() {
        let devices = Devices()
        let store = HomeStore(plan: Self.plan, file: nil, transmit: devices.transmit)
        var changes = 0
        store.onChange = { _ in changes += 1 }
        store.applyRemote(["lights": ["lamp": ["on": true]], "acs": ["ac": ["on": true, "roomTemp": 25.5]],
                           "features": ["ac": ["modes": ["cool"]]]])
        #expect(devices.sent.isEmpty)
        #expect(changes == 1)
        #expect(store.acs["ac"]?["roomTemp"] == .number(25.5))
        #expect(store.features["ac"] != nil)
        store.applyRemote(["lights": ["lamp": ["on": true]]])
        #expect(changes == 1)
    }

    @Test func aSceneSetsWhiteOverColourAndIsRemembered() {
        let store = HomeStore(plan: Self.plan, file: nil, transmit: nil)
        store.setLight("lamp", ["color": "#00ff00"])
        store.applyScene("bright")
        #expect(store.scene == "bright")
        #expect(light(store, "lamp", "color") == .null)
        #expect(light(store, "bed", "brightness") == .number(1))
        store.toggleLight("bed")
        #expect(store.scene == nil)
    }

    @Test func theStateIsSavedAndReadBackForTheSameHomeOnly() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("home-state-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = HomeStore(plan: Self.plan, file: file, transmit: nil)
        store.applyScene("cozy")
        store.save()
        let again = HomeStore(plan: Self.plan, file: file, transmit: nil)
        #expect(again.restored)
        #expect(again.scene == "cozy")
        #expect(light(again, "lamp", "color") == .string("#ff7a3c"))
        var other = Self.plan
        other["name"] = "Another home"
        #expect(!HomeStore(plan: other, file: file, transmit: nil).restored)
    }

    @Test func aNewHomeStartsCozyUnlessItIsReal() {
        let store = HomeStore(plan: Self.plan, file: nil, transmit: nil)
        store.startIfNew()
        #expect(store.scene == "cozy")
        #expect(store.acs["ac"]?["on"] == .bool(true))
        #expect(store.acs["ac"]?["target"] == .number(23))

        var linked = Self.plan
        linked["lights"] = [["id": "lamp", "room": "living", "link": ["service": "hue", "id": "1"]]]
        let real = HomeStore(plan: linked, file: nil, transmit: nil)
        real.startIfNew()
        #expect(real.scene == nil)
    }

    @Test func pageStateFromBeforeIsTakenOnce() {
        let store = HomeStore(plan: Self.plan, file: nil, transmit: nil)
        store.restoreIfNew(["home": "Test home", "lights": ["bed": ["on": true]], "scene": "x"])
        #expect(light(store, "bed", "on") == .bool(true))
        store.restoreIfNew(["home": "Test home", "lights": ["bed": ["on": false]]])
        #expect(light(store, "bed", "on") == .bool(true))
    }

    @Test func theRoomTemperatureDriftsTowardsTheSetPoint() {
        let store = HomeStore(plan: Self.plan, file: nil, transmit: nil)
        var ticks = 0
        store.onChange = { if $0.tick { ticks += 1 } }
        store.setAC("ac", ["on": true, "target": 20])
        let start = store.acs["ac"]?["roomTemp"]?.number ?? 0
        store.simulate()
        #expect(store.acs["ac"]?["roomTemp"]?.number == ((start - 0.2) * 10).rounded() / 10)
        #expect(ticks == 1)
    }

    @Test func widgetActionsAndPageIntents() {
        let store = HomeStore(plan: Self.plan, file: nil, transmit: nil)
        var sources: [String?] = []
        store.onChange = { sources.append($0.source) }
        store.run(.room("living"))
        #expect(light(store, "lamp", "on") == .bool(true))
        #expect(light(store, "plug", "on") == .bool(true))
        #expect(light(store, "bed", "on") == .bool(false))
        store.run(.acTarget("ac", 40))
        #expect(store.acs["ac"]?["target"] == .number(30))
        store.perform(["op": "setAllLights", "on": false, "source": "ChatGPT"])
        #expect(store.summary["lightsOn"] as? Int == 0)
        #expect(sources.last == "ChatGPT")
        #expect(sources.first == "Widget")
    }

    /// What arrives from a page or a device has been through JSONSerialization.
    func decoded(_ json: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]) ?? [:]
    }

    @Test func aBrightnessOfOneIsANumberNotTrue() {
        let devices = Devices()
        let store = HomeStore(plan: Self.plan, file: nil, transmit: devices.transmit)
        store.perform(decoded(#"{"op": "setLight", "id": "lamp", "patch": {"brightness": 1, "on": true}}"#))
        #expect(light(store, "lamp", "brightness") == .number(1))
        #expect(light(store, "lamp", "on") == .bool(true))
        #expect(JSONValue(any: true) == .bool(true))
        #expect(JSONValue(any: 0) == .number(0))
    }

    @Test func aRetiredStoreSendsNothingMore() async throws {
        let devices = Devices()
        let store = HomeStore(plan: Self.plan, file: nil, transmit: devices.transmit)
        store.setLight("lamp", ["on": true])
        store.setLight("lamp", ["brightness": 0.3])
        store.retire(keepSending: false)
        devices.answer(0)
        try await Task.sleep(nanoseconds: 450_000_000)
        store.setLight("bed", ["on": true])
        #expect(devices.sent.count == 1)
    }

    @Test func devicesReportedBeforeALateRestoreWin() {
        let store = HomeStore(plan: Self.plan, file: nil, transmit: nil)
        store.applyRemote(decoded(#"{"lights": {"lamp": {"on": true}}}"#))
        store.restoreIfNew(["home": "Test home", "lights": ["lamp": ["on": false, "brightness": 0.2]]])
        #expect(light(store, "lamp", "on") == .bool(true))
        #expect(light(store, "lamp", "brightness") == .number(0.2))
    }

    @Test func aStoreRetiredWithTheSameLinksFinishesWhatItStarted() async throws {
        let devices = Devices()
        let store = HomeStore(plan: Self.plan, file: nil, transmit: devices.transmit)
        store.setLight("lamp", ["on": true])
        store.setLight("lamp", ["brightness": 0.3])
        store.retire(keepSending: true)
        devices.answer(0)
        try await Task.sleep(nanoseconds: 450_000_000)
        #expect(devices.sent.count == 2)
        store.setLight("bed", ["on": true])
        #expect(devices.sent.count == 2)
    }

    @Test func aChangeMadeBeforeTheFirstPageIsReadyIsKept() {
        let store = HomeStore(plan: Self.plan, file: nil, transmit: nil)
        store.setLight("bed", ["on": true])
        store.restoreIfNew(["home": "Test home", "lights": ["bed": ["on": false]]])
        store.startIfNew()
        #expect(light(store, "bed", "on") == .bool(true))
        #expect(store.scene == nil)
    }
}
