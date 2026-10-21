import AppKit
import UniformTypeIdentifiers
import HouseCore

extension AppModel {
    // MARK: - Messages from the web UI

    func handle(_ message: [String: Any], from host: WebHost) {
        switch message["type"] as? String {
        case "ready":
            // The panel and the island draw the store's state; the store tells the menu bar icon.
            if host === hosts[.primary] || host === hosts[.island] { stateViewReady(host, message: message) }
            // A (re)loaded island page catches up with an island that is already open.
            if host === hosts[.island], islandModel?.revealed == true { host.call("islandState", "expanded") }
            if host === hosts[.primary] {
                // A page that could not start shows why; the native controls step aside.
                home.pageError = message["error"] as? String
                // A reloaded page starts from scratch: show it what the controls show.
                home.resendView()
                openDeviceOnLaunch()
                widgets.isReady = true
                router.markReady()
                primaryLoaded()
            }
        case "intent":
            receiveIntent(message, from: host)
        case "pick":
            if host === hosts[.primary] { home.picked(message) }
        case "toast":
            home.showToast(message["text"] as? String ?? "", ai: message["ai"] as? String)
        case "widgets":
            if host === hosts[.primary] { widgets.publish(message) }
        case "close":
            // Escape in the panel closes it; in the main window the page stays.
            dismissPanel()
        case "selectPlan":
            if let plan = message["plan"] as? String {
                plans.select(plan)
                reloadAll()
                hosts[.editor]?.load()
            }
        case "loadPlan": loadPlan()
        case "openAgent": router.show(.agent)
        case "openWindow": router.show(.home)
        case "openSettings": router.show(.settings)
        case "revealPlan": revealPlan()
        case "openEditor": router.show(.editor)
        case "openConnections": router.show(.connections(service: message["service"] as? String))
        case "quit": NSApp.terminate(nil)
        case "setOpenAtLogin": setOpenAtLogin(message["on"] as? Bool ?? false)

        // Editor
        case "savePlan":
            guard let config = message["config"] as? [String: Any] else { return }
            do {
                try plans.saveCustom(config)
                reloadAll()
                host.reply(to: message, ["ok": true, "path": plans.customPlanURL.path])
            } catch {
                host.reply(to: message, ["error": error.localizedDescription])
            }
        case "importPlan":
            let open = NSOpenPanel()
            open.allowedContentTypes = [.json]
            guard open.runModal() == .OK, let url = open.url,
                  let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                host.reply(to: message, ["cancelled": true])
                return
            }
            host.reply(to: message, ["config": json])
        case "exportPlan":
            guard let config = message["config"] as? [String: Any] else { return }
            let save = NSSavePanel()
            save.allowedContentTypes = [.json]
            save.nameFieldStringValue = "\((config["name"] as? String ?? "home").lowercased()).json"
            guard save.runModal() == .OK, let url = save.url else {
                host.reply(to: message, ["cancelled": true])
                return
            }
            do {
                try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: url)
                host.reply(to: message, ["ok": true])
            } catch {
                host.reply(to: message, ["error": error.localizedDescription])
            }
        // The editor's "Real device" pickers (connecting a platform is the native Connections screen)
        case "services.info":
            host.reply(to: message, hub.servicesInfo)
        case "devices.all":
            Task { @MainActor in
                let (devices, errors) = await hub.allDevices()
                host.reply(to: message, ["devices": devices, "errors": errors])
            }
        default:
            break
        }
    }

}
