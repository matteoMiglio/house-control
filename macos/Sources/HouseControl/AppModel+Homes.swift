import AppKit
import HouseCore

/// One home on the Floor Plans screen: My home, or a bundled demo.
struct HomeEntry: Identifiable {
    let id: String
    let name: String
    let rooms: Int
    /// Lamps, ACs and energy sensors linked to real devices (none in a demo).
    let linked: Int
    var demo: Bool { id != "custom" }
}

extension AppModel {
    // MARK: - Homes

    /// My home, when there is one.
    var ownHome: HomeEntry? {
        _ = homesVersion
        return plans.customPlan().map { entry("custom", $0, name: plans.customPlanName ?? "My home") }
    }

    var demoHomes: [HomeEntry] {
        Self.demos.compactMap { id, name in demoPlan(id).map { entry(id, $0, name: name) } }
    }

    var activeHome: String {
        _ = homesVersion
        return plans.activePlan
    }

    private func entry(_ id: String, _ plan: [String: Any], name: String) -> HomeEntry {
        HomeEntry(id: id, name: name, rooms: (plan["rooms"] as? [Any])?.count ?? 0,
                  linked: id == "custom" ? HomeConfig(plan: plan).linkedCount : 0)
    }

    /// Asks before `what` takes My home's place; true straight away when there is none to lose.
    func confirmReplacingHome(with what: String) -> Bool {
        guard plans.hasCustomPlan else { return true }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Replace My home with “\(what)”?"
        alert.informativeText = "“\(plans.customPlanName ?? "My home")” and its links to real devices are replaced. This cannot be undone; export it first to keep a copy."
        alert.addButton(withTitle: "Replace My home").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// A demo, copied as My home to make your own from; the demo stays as it was.
    func startFromDemo(_ id: String) {
        guard var plan = demoPlan(id), let name = Self.demos.first(where: { $0.0 == id })?.1,
              confirmReplacingHome(with: "\(name) demo") else { return }
        plan["name"] = "My home"
        do {
            try plans.saveCustom(plan)
            reloadAll()
            hosts[.editor]?.load()
            home.showToast("My home, from the \(name) demo: edit it in Edit Home")
        } catch {
            alert("Could not make My home", error.localizedDescription)
        }
    }

    /// Forgets My home, after asking; the demo apartment is shown instead.
    func removeOwnHome() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remove “\(plans.customPlanName ?? "My home")”?"
        alert.informativeText = "Its floor plan and its links to real devices are deleted from this Mac. Your connections to Home Assistant, Hue and Smart Life stay. This cannot be undone; export it first to keep a copy."
        alert.addButton(withTitle: "Remove").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        plans.removeCustom()
        reloadAll()
        hosts[.editor]?.load()
    }

    /// Saves a copy of My home's plan file wherever the user picks.
    func exportOwnHome() {
        guard let data = try? Data(contentsOf: plans.customPlanURL) else { return }
        NSApp.activate(ignoringOtherApps: true)
        let save = NSSavePanel()
        save.allowedContentTypes = [.json]
        save.nameFieldStringValue = "\(plans.customPlanName ?? "My home").json"
        guard save.runModal() == .OK, let url = save.url else { return }
        do { try data.write(to: url, options: .atomic) } catch { alert("Could not export the plan", error.localizedDescription) }
    }
}
