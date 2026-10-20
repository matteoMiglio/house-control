import Foundation
import HouseCore

extension AppModel {
    // MARK: - The home's state

    /// The pages that draw the home's state: the panel (also the main window's Home) and the island.
    private static let stateViews: [HostRole] = [.primary, .island]

    /// Makes the store for the active plan, when the plan changed (a new plan starts from
    /// what was saved for it, if anything). Before the hub takes the new plan's links, so
    /// the old store cannot send anything through them.
    func loadHomeStore() {
        let custom = plans.activePlan == "custom"
        let plan = custom ? plans.customPlan() : demoPlan(plans.activePlan)
        let key = plan.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: .sortedKeys) }
        if homeStore != nil, key == homePlanKey { return }
        homeStore?.retire(keepSending: HomeStore.linkKey(plan) == HomeStore.linkKey(homePlan))
        homePlanKey = key
        homePlan = plan
        let store = HomeStore(plan: plan ?? [:], file: plans.directory.appendingPathComponent("state-\(plans.activePlan).json"),
                              transmit: { [weak self] message, reply in
                                  guard let self else { return reply(["ok": true]) }
                                  self.hub.command(message, reply: reply)
                              })
        store.onChange = { [weak self] change in self?.schedulePush(change) }
        store.onDeviceError = { [weak self] id, message in self?.home.deviceError(id, message) }
        store.startSimulation()
        homeStore = store
        home.load(plan: plan ?? [:], store: store)
        islandModel?.reset()
        updateStatus(store.summary)
    }

    private func demoPlan(_ id: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: WebHost.assetRoot.appendingPathComponent("plans/\(id).json")) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Added to a state view's boot payload: the page starts from what the app holds.
    func stateBoot(_ boot: inout [String: Any]) {
        boot["nativeState"] = true
        if let homeStore { boot["state"] = homeStore.json }
    }

    /// A page's `intent`: what the user did there.
    func receiveIntent(_ message: [String: Any], from host: WebHost) {
        if let seq = message["seq"] as? Int { intentAcks[ObjectIdentifier(host)] = seq }
        homeStore?.perform(message)
        // Answered even when nothing changed: the page waits for this answer to take the state again.
        schedulePush(nil)
    }

    /// A state view has (re)loaded: it counts its intents from zero again. The panel's first
    /// `ready` also settles where a home nothing was saved for starts.
    func stateViewReady(_ host: WebHost, message: [String: Any]) {
        intentAcks[ObjectIdentifier(host)] = 0
        if host === hosts[.primary], let homeStore {
            if let legacy = message["legacy"] as? [String: Any] { homeStore.restoreIfNew(legacy) }
            homeStore.startIfNew()
        }
        schedulePush(nil)
    }

    /// Several changes in one turn of the run loop reach the pages as one.
    private func schedulePush(_ change: HomeStore.Change?) {
        let first = pendingPush == nil
        var next = pendingPush ?? PendingPush()
        if let change {
            next.tick = next.tick && change.tick
            if !change.tick { next.source = change.source ?? next.source }
        } else {
            next.tick = false
        }
        pendingPush = next
        guard first else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.push() }
        }
    }

    private func push() {
        let push = pendingPush
        pendingPush = nil
        guard let push, let homeStore else { return }
        let state = homeStore.json
        for role in Self.stateViews {
            guard let host = hosts[role], host.isReady else { continue }
            host.call("sync", ["state": state, "ack": intentAcks[ObjectIdentifier(host)] ?? 0,
                               "tick": push.tick, "source": (push.source as Any?) ?? NSNull()])
        }
        home.refresh()
        islandModel?.homeChanged(tick: push.tick, source: push.source)
        if !push.tick { updateStatus(homeStore.summary) }
    }
}

/// What the next push to the pages says about the changes it carries.
struct PendingPush {
    /// Only simulated room temperatures moved.
    var tick = true
    var source: String?
}
