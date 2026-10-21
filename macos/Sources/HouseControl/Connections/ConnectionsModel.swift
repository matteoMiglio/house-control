import Foundation
import Observation
import HouseCore
import HouseSmartLife

/// The Connections screen: the smart home platforms the plan's lamps and ACs can be linked to,
/// and connecting each one. The counterpart of web/src/editor/connections.js and the editor's
/// Smart Life panel; linking a lamp or an AC to a device stays in the editor.
@MainActor
@Observable
final class ConnectionsModel {
    enum Service: String, CaseIterable, Hashable, Identifiable {
        case smartLife = "smartlife", homeAssistant = "homeassistant", hue, homeKit = "homekit"

        var id: String { rawValue }

        var name: String {
            switch self {
            case .smartLife: "Smart Life"
            case .homeAssistant: "Home Assistant"
            case .hue: "Philips Hue"
            case .homeKit: "Apple Home"
            }
        }

        var blurb: String {
            switch self {
            case .smartLife: "Tuya, Smart Life and the many brands built on them"
            case .homeAssistant: "Everything it runs: Zigbee, Matter, Nest, Xiaomi, Sonoff…"
            case .hue: "A Hue Bridge on this network. No account needed"
            case .homeKit: "HomeKit and Matter accessories, through your iPhone"
            }
        }

        /// The Lucide icon and the tint of its tile, as connections.js has them.
        var icon: String {
            switch self {
            case .smartLife: "plug"
            case .homeAssistant: "homeassistant"
            case .hue: "bulb"
            case .homeKit: "home"
            }
        }

        var tint: String {
            switch self {
            case .smartLife: "#ff7a3d"
            case .homeAssistant: "#18bcf2"
            case .hue: "#c38bff"
            case .homeKit: "#ffb340"
            }
        }
    }

    /// A device of a connected platform, in the editor's terms (`DeviceHub.allDevices`).
    struct Device: Identifiable {
        let service: String
        let id: String
        let kind: String
        let name: String
        let line: String
        let online: Bool

        var key: String { "\(service)|\(id)" }

        init(_ d: [String: Any]) {
            service = d["service"] as? String ?? ""
            id = d["id"] as? String ?? ""
            kind = d["kind"] as? String ?? "light"
            name = d["name"] as? String ?? id
            let parts = [d["room"] as? String, d["detail"] as? String].compactMap { $0 }.filter { !$0.isEmpty }
            line = parts.isEmpty ? id : parts.joined(separator: " · ")
            online = d["online"] as? Bool ?? false
        }

        /// A Smart Life device as `tuya.devices` reports it: its product and its data points.
        init(tuya d: [String: Any]) {
            service = Service.smartLife.rawValue
            id = d["id"] as? String ?? ""
            kind = ""
            name = d["name"] as? String ?? id
            let codes = d["codes"] as? [String] ?? []
            let product = [d["product"] as? String, d["category"] as? String].compactMap { $0 }.first { !$0.isEmpty } ?? "device"
            line = "\(product) · \(codes.isEmpty ? "no functions reported" : codes.joined(separator: ", "))"
            online = d["online"] as? Bool ?? false
        }
    }

    /// A short message where the web showed a toast.
    struct Notice: Equatable {
        let id = UUID()
        let text: String
        let bad: Bool
    }

    /// Waiting for the round button on a Hue Bridge.
    struct HuePairing {
        let host: String
        let bridgeId: String?
        let name: String
        var secondsLeft = 60
        var error: String?
    }

    static let regions = [("eu", "Central Europe"), ("eu-w", "Western Europe"), ("us", "Western America"), ("us-e", "Eastern America"),
                          ("cn", "China"), ("in", "India"), ("sg", "Singapore")]

    /// The screens shown over the overview (at most one platform).
    var path: [Service] = []
    private(set) var info: [String: [String: Any]] = [:]
    private(set) var tuya: [String: Any] = [:]
    /// The Smart Life account: `connected`, `account`, `userCode`.
    private(set) var account: [String: Any] = [:]
    /// Every connected platform's devices, once asked for; what went wrong per platform ("all": the whole call).
    private(set) var devices: [Device]?
    private(set) var errors: [String: String] = [:]
    private(set) var loading = false
    private(set) var found: [Service: [[String: Any]]] = [:]
    private(set) var scanning: Set<Service> = []
    private(set) var notice: Notice?
    /// The active plan: which of its lamps and ACs use which device.
    var plan: [String: Any]? { didSet { used = Self.usedMap(plan) } }
    private(set) var used: [String: String] = [:]

    // Home Assistant
    var haURL = ""
    var haToken = ""
    private(set) var haBusy = false
    private(set) var haError: String?

    // Philips Hue
    var hueHost = ""
    private(set) var huePairing: HuePairing?
    @ObservationIgnored private var hueTask: Task<Void, Never>?

    // Smart Life
    var userCode = ""
    private(set) var loginQR: String?
    private(set) var loginMessage = ""
    private(set) var loginFailed = false
    @ObservationIgnored private var loginTask: Task<Void, Never>?
    private(set) var tuyaDevices: [Device]?
    private(set) var tuyaBusy = false
    private(set) var tuyaError: String?
    var tuyaOpen = false
    var tuyaAccessId = ""
    var tuyaSecret = ""
    var tuyaRegion = "eu"

    @ObservationIgnored private let hub: DeviceHub
    @ObservationIgnored private let smartLife: SmartLifePlatform?
    /// A platform was connected or disconnected here: the app reads its links again and tells the
    /// phones and the editor's page.
    @ObservationIgnored var onChange: (() -> Void)?
    /// The Smart Life User Code a paired iPhone signed in with.
    @ObservationIgnored var phoneUserCode: () -> String = { "" }
    @ObservationIgnored var openEditor: (() -> Void)?
    @ObservationIgnored private var noticeTimer: Task<Void, Never>?
    /// Counts the device lists asked for: only the latest one asked is shown.
    @ObservationIgnored private var loadRound = 0
    @ObservationIgnored private var tuyaRound = 0

    init(hub: DeviceHub, smartLife: SmartLifePlatform?) {
        self.hub = hub
        self.smartLife = smartLife
        refreshInfo()
        fillTuyaFields()
    }

    // MARK: - Platforms

    /// The platforms this app offers, in the editor's order.
    var offered: [Service] { Service.allCases.filter { info[$0.rawValue] != nil } }

    func connected(_ service: Service) -> Bool { info[service.rawValue]?["connected"] as? Bool ?? false }

    var anyConnected: Bool { offered.contains(where: connected) }

    func info(_ service: Service) -> [String: Any] { info[service.rawValue] ?? [:] }

    func devices(of service: Service) -> [Device] { (devices ?? []).filter { $0.service == service.rawValue } }

    /// What a platform's card says under its name.
    func status(_ service: Service) -> String {
        let info = info(service)
        if service == .homeKit, info["remote"] as? Bool == true {
            let count = info["count"] as? Int ?? 0
            let from = (info["from"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "your iPhone"
            return connected(service) ? "\(count) devices from \(from)" : "Set up on your iPhone"
        }
        guard connected(service) else { return "Not connected" }
        let name: String? = switch service {
        case .homeAssistant, .hue: info["name"] as? String
        case .smartLife: info["account"] as? String
        case .homeKit: nil
        }
        let count = devices(of: service).count
        let parts = [name.flatMap { $0.isEmpty ? nil : $0 }, devices.map { _ in "\(count) device\(count == 1 ? "" : "s")" }].compactMap { $0 }
        return parts.isEmpty ? "Connected" : parts.joined(separator: " · ")
    }

    func refreshInfo() {
        var all: [String: [String: Any]] = [:]
        for (id, value) in hub.servicesInfo { all[id] = value as? [String: Any] }
        info = all
        tuya = smartLife?.tuyaInfo ?? [:]
        account = smartLife?.smartLifeInfo ?? [:]
    }

    /// The list of every connected platform's devices (`quiet`: what is shown stays meanwhile).
    func load(quiet: Bool = false) {
        guard anyConnected else {
            devices = nil
            return
        }
        loadRound += 1
        let round = loadRound
        if !quiet { loading = true }
        Task { @MainActor in
            let result = await hub.allDevices()
            guard round == self.loadRound else { return }
            self.devices = result.devices.map { Device($0) }
            self.errors = result.errors
            self.loading = false
        }
    }

    /// Something changed elsewhere: a paired iPhone sent its Apple Home devices or its connections.
    func servicesChanged() {
        refreshInfo()
        if tuyaSecret.isEmpty { fillTuyaFields() }
        load(quiet: true)
    }

    func scan(_ service: Service) {
        guard !scanning.contains(service) else { return }
        scanning.insert(service)
        Task { @MainActor in
            let list = service == .hue ? await ServiceDiscovery.hueBridges() : await ServiceDiscovery.homeAssistants()
            self.found[service] = list
            self.scanning.remove(service)
            // One server on the network: its address is the one to use.
            if service == .homeAssistant, self.haURL.isEmpty, list.count == 1 { self.haURL = list[0]["url"] as? String ?? "" }
        }
    }

    func disconnect(_ service: Service) {
        hub.disconnect(service: service.rawValue)
        refreshInfo()
        loadRound += 1 // a list still on its way would bring the platform's devices back
        loading = false
        devices = devices?.filter { $0.service != service.rawValue }
        changed()
        tell("\(service.name) disconnected")
    }

    /// A platform's screen was opened (or came back on screen).
    func appeared(_ service: Service) {
        if connected(service) {
            if service == .smartLife {
                if smartLifeSignedIn || tuya["configured"] as? Bool == true, tuyaDevices == nil, !tuyaBusy, tuyaError == nil { loadTuyaDevices() }
            } else if devices == nil, !loading {
                load()
            }
        } else if service == .homeAssistant || service == .hue, found[service] == nil {
            scan(service)
        }
        if service == .smartLife, userCode.isEmpty {
            userCode = (account["userCode"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? phoneUserCode()
        }
    }

    /// The platform's screen was left: no more waiting for the Hue Bridge's button. (A Smart Life
    /// login goes on waiting for its code to be scanned: the phone may be in another hand.)
    func left(_ service: Service) {
        if service == .hue { stopPairing() }
    }

    private func changed() {
        onChange?()
    }

    private func tell(_ text: String, bad: Bool = false) {
        let notice = Notice(text: text, bad: bad)
        self.notice = notice
        noticeTimer?.cancel()
        noticeTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled, self?.notice == notice else { return }
            self?.notice = nil
        }
    }

    // MARK: - Home Assistant

    var canConnectHomeAssistant: Bool {
        !haBusy && !haURL.trimmingCharacters(in: .whitespaces).isEmpty && !haToken.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func connectHomeAssistant() {
        guard canConnectHomeAssistant else { return }
        haBusy = true
        haError = nil
        Task { @MainActor in
            do {
                try await hub.connectHomeAssistant(url: haURL, token: haToken)
                haToken = ""
                refreshInfo()
                changed()
                tell("Connected to \(info(.homeAssistant)["name"] as? String ?? "Home Assistant")")
                load()
            } catch {
                haError = error.localizedDescription
            }
            haBusy = false
        }
    }

    // MARK: - Philips Hue

    /// Asks the bridge every two seconds, for a minute, whether its button was pressed.
    func pairHue(host: String, bridgeId: String? = nil, name: String = "Hue Bridge") {
        let host = host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }
        stopPairing()
        huePairing = HuePairing(host: host, bridgeId: bridgeId, name: name)
        hueTask = Task { @MainActor in
            for left in stride(from: 60, through: 0, by: -2) {
                huePairing?.secondsLeft = left
                do {
                    try await hub.pairHue(host: host, bridgeId: bridgeId, name: name)
                    // Paired, even if given up on meanwhile: the app and the phones take the bridge in.
                    refreshInfo()
                    changed()
                    load()
                    if !Task.isCancelled {
                        huePairing = nil
                        tell("Paired with \(info(.hue)["name"] as? String ?? "the Hue Bridge")")
                    }
                    return
                } catch is HueService.ButtonNotPressed {
                } catch {
                    if !Task.isCancelled { huePairing?.error = error.localizedDescription }
                    return
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { return }
            }
            huePairing?.error = "Nobody pressed the button in time. Try again."
        }
    }

    func retryPairing() {
        guard let p = huePairing else { return }
        pairHue(host: p.host, bridgeId: p.bridgeId, name: p.name)
    }

    func stopPairing() {
        hueTask?.cancel()
        hueTask = nil
        huePairing = nil
    }

    // MARK: - Smart Life

    /// Signed in with the Smart Life app (a Tuya Cloud project alone also connects the platform).
    var smartLifeSignedIn: Bool { account["connected"] as? Bool ?? false }

    /// Shows a QR code for the Smart Life app to scan, then waits (up to three minutes) for the login.
    func showLoginCode() {
        guard let smartLife else { return }
        stopLogin()
        loginFailed = false
        loginQR = nil
        loginMessage = "Requesting a login code…"
        let code = userCode.trimmingCharacters(in: .whitespaces)
        loginTask = Task { @MainActor in
            do {
                let login = try await smartLife.beginLogin(userCode: code)
                guard !Task.isCancelled else { return }
                loginQR = login.qrContent
                loginMessage = "Scan this code with the Smart Life app (the scan icon on the Home tab) and confirm the login. Waiting…"
                for _ in 0..<90 {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    if await smartLife.finishLogin(token: login.token, userCode: code) {
                        // Signed in, even if given up on meanwhile.
                        smartLifeChanged()
                        if !Task.isCancelled {
                            loginQR = nil
                            loginMessage = ""
                        }
                        return
                    }
                }
                loginQR = nil
                loginFailed = true
                loginMessage = "The code expired. Press “Show QR code” again."
            } catch is CancellationError {
            } catch {
                loginFailed = true
                loginMessage = error.localizedDescription
            }
        }
    }

    func stopLogin() {
        loginTask?.cancel()
        loginTask = nil
        loginQR = nil
        if !loginFailed { loginMessage = "" }
    }

    func signOut() {
        stopLogin()
        smartLife?.signOut()
        tuyaDevices = nil
        smartLifeChanged()
    }

    func loadTuyaDevices() {
        guard let smartLife else { return }
        tuyaRound += 1
        let round = tuyaRound
        tuyaBusy = true
        tuyaError = nil
        Task { @MainActor in
            let list: [Device]?
            let failure: String?
            do {
                list = try await smartLife.listDevices().map { Device(tuya: $0) }
                failure = nil
            } catch {
                list = nil
                failure = error.localizedDescription
            }
            guard round == tuyaRound else { return }
            tuyaDevices = list
            tuyaError = failure
            tuyaBusy = false
        }
    }

    /// Saves the Tuya Cloud project (an empty secret keeps the saved one; an empty Access ID removes it).
    func saveTuya() {
        guard let smartLife else { return }
        do {
            try smartLife.saveTuya(accessId: tuyaAccessId, accessSecret: tuyaSecret, region: tuyaRegion)
            tuyaSecret = ""
            smartLifeChanged()
        } catch {
            tell(error.localizedDescription, bad: true)
        }
    }

    private func smartLifeChanged() {
        refreshInfo()
        tuyaRound += 1 // what an account or project that is gone was listing
        tuyaBusy = false
        tuyaDevices = nil
        tuyaError = nil
        changed()
        load(quiet: true)
        if connected(.smartLife) { loadTuyaDevices() }
    }

    /// The Tuya Cloud project's fields, as saved.
    private func fillTuyaFields() {
        tuyaAccessId = tuya["accessId"] as? String ?? ""
        tuyaRegion = tuya["region"] as? String ?? "eu"
    }

    // MARK: - Used by the plan

    /// "service|id → plan item name" for every device the plan links (connections.js `usedMap`).
    static func usedMap(_ plan: [String: Any]?) -> [String: String] {
        var out: [String: String] = [:]
        let items = (plan?["lights"] as? [[String: Any]] ?? []) + (plan?["acs"] as? [[String: Any]] ?? [])
        for d in items {
            let name = (d["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? d["id"] as? String ?? ""
            let link = d["link"] as? [String: Any]
            let tuya = d["tuya"] as? [String: Any]
            if let service = link?["service"] as? String, !service.isEmpty, let id = link?["id"] as? String, !id.isEmpty {
                out["\(service)|\(id)"] = name
            } else if let id = tuya?["deviceId"] as? String, !id.isEmpty {
                out["smartlife|\(id)"] = name
            }
            let sensor = d["sensor"] as? [String: Any]
            if let service = sensor?["service"] as? String, let id = sensor?["id"] as? String, !id.isEmpty {
                out["\(service)|\(id)"] = "\(name) · room"
            }
            if let id = tuya?["sensorId"] as? String, !id.isEmpty { out["smartlife|\(id)"] = "\(name) · room" }
        }
        for (role, sensor) in HomeConfig(plan: plan ?? [:]).energy?.sensors ?? [:] {
            out["\(sensor.service)|\(sensor.id)"] = role.title
        }
        let thermostat = plan?["thermostat"] as? [String: Any]
        if let service = thermostat?["service"] as? String, let id = thermostat?["id"] as? String, !id.isEmpty {
            out["\(service)|\(id)"] = "Thermostat"
        }
        return out
    }
}
