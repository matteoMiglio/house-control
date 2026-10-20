import AppKit
import UniformTypeIdentifiers
import HouseCore
import HouseSmartLife

extension AppModel {
    // MARK: - Messages from the web UI

    func handle(_ message: [String: Any], from host: WebHost) {
        switch message["type"] as? String {
        case "ready":
            // The panel and the island draw the store's state; the store tells the menu bar icon.
            if host === hosts[.primary] || host === hosts[.island] { stateViewReady(host, message: message) }
            // The editor's page catches up with a screen asked for while it was loading.
            if host === hosts[.editor] { showEditorWant() }
            if host === hosts[.primary] {
                widgets.isReady = true
                router.markReady()
                primaryLoaded()
            }
        case "intent":
            receiveIntent(message, from: host)
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
        case "openEditor": router.show(.editor(section: message["section"] as? String))
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
        case "tuya.save":
            do {
                try smartLife.saveTuya(accessId: message["accessId"] as? String ?? "",
                                 accessSecret: message["accessSecret"] as? String ?? "",
                                 region: message["region"] as? String ?? "eu")
                host.reply(to: message, smartLife.tuyaInfo)
            } catch {
                host.reply(to: message, ["error": error.localizedDescription])
            }
        case "tuya.devices":
            Task { @MainActor in
                do {
                    host.reply(to: message, ["devices": try await smartLife.listDevices()])
                } catch {
                    host.reply(to: message, ["error": error.localizedDescription])
                }
            }
        case "smartlife.begin":
            let userCode = message["userCode"] as? String ?? ""
            Task { @MainActor in
                do {
                    let login = try await smartLife.beginLogin(userCode: userCode)
                    let png = QRCode.png(for: login.qrContent).map { "data:image/png;base64,\($0.base64EncodedString())" }
                    host.reply(to: message, ["token": login.token, "qr": png ?? ""])
                } catch {
                    host.reply(to: message, ["error": error.localizedDescription])
                }
            }
        case "smartlife.poll":
            let token = message["token"] as? String ?? ""
            let userCode = message["userCode"] as? String ?? ""
            Task { @MainActor in
                let done = await smartLife.finishLogin(token: token, userCode: userCode)
                host.reply(to: message, ["connected": done, "info": smartLife.smartLifeInfo])
                if done { sync.broadcast() }
            }
        case "smartlife.signOut":
            smartLife.signOut()
            host.reply(to: message, smartLife.smartLifeInfo)
            sync.broadcast()

        // Home Assistant, Philips Hue, Apple Home
        case "services.info":
            host.reply(to: message, hub.servicesInfo)
        case "devices.all":
            Task { @MainActor in
                let (devices, errors) = await hub.allDevices()
                host.reply(to: message, ["devices": devices, "errors": errors])
            }
        case "services.discover":
            let service = message["service"] as? String ?? ""
            Task { @MainActor in
                let found = service == "hue" ? await ServiceDiscovery.hueBridges() : await ServiceDiscovery.homeAssistants()
                host.reply(to: message, ["found": found])
            }
        case "homeassistant.connect":
            Task { @MainActor in
                do {
                    try await hub.connectHomeAssistant(url: message["url"] as? String ?? "", token: message["token"] as? String ?? "")
                    connectionsChanged()
                    host.reply(to: message, hub.servicesInfo)
                } catch {
                    host.reply(to: message, ["error": error.localizedDescription])
                }
            }
        case "hue.pair":
            Task { @MainActor in
                do {
                    try await hub.pairHue(host: message["host"] as? String ?? "", bridgeId: message["bridgeId"] as? String,
                                          name: message["name"] as? String)
                    connectionsChanged()
                    host.reply(to: message, hub.servicesInfo)
                } catch is HueService.ButtonNotPressed {
                    host.reply(to: message, ["waiting": true])
                } catch {
                    host.reply(to: message, ["error": error.localizedDescription])
                }
            }
        case "service.disconnect":
            hub.disconnect(service: message["service"] as? String ?? "")
            connectionsChanged()
            host.reply(to: message, hub.servicesInfo)
        default:
            break
        }
    }

}
