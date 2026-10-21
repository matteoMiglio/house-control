import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers
import HouseCore
import HouseSmartLife

@MainActor
@Observable
final class AppModel: NSObject {
    @ObservationIgnored let plans = PlanStore()
    /// The Smart Life / Tuya side: device links, commands and state.
    @ObservationIgnored private var storedHub: DeviceHub?
    var hub: DeviceHub {
        if let storedHub { return storedHub }
        let hub = DeviceHub(directory: plans.directory, cloud: SmartLifePlatform.init)
        storedHub = hub
        return hub
    }
    /// Smart Life is always part of the Mac app.
    var smartLife: SmartLifePlatform { hub.smartLife! }
    /// The Connections screen.
    @ObservationIgnored var storedConnections: ConnectionsModel?
    var connections: ConnectionsModel {
        if let storedConnections { return storedConnections }
        let connections = ConnectionsModel(hub: hub, smartLife: smartLife)
        connections.plan = homePlan
        connections.onChange = { [weak self] in
            guard let self else { return }
            self.connectionsChanged()
            self.hosts[.editor]?.call("servicesChanged", self.hub.servicesInfo)
        }
        connections.phoneUserCode = { [weak self] in self?.phoneUserCode ?? "" }
        connections.openEditor = { [weak self] in self?.router.show(.editor) }
        storedConnections = connections
        return connections
    }
    /// Hands the floor plan to paired iPhones on the local network.
    @ObservationIgnored private var storedSync: SyncServer?
    var sync: SyncServer {
        if let storedSync { return storedSync }
        let sync = SyncServer(store: FileSecretStore(url: plans.directory.appendingPathComponent("sync.json")))
        storedSync = sync
        return sync
    }
    @ObservationIgnored var island: IslandController?
    @ObservationIgnored var loginWindow: NSWindow?
    @ObservationIgnored var loginWindowExpiry: DispatchWorkItem?
    @ObservationIgnored var statusItem: NSStatusItem!
    @ObservationIgnored var panel: PanelController!
    @ObservationIgnored var pollTimer: Timer?
    /// AI Access: the private link an AI assistant uses to run the home.
    @ObservationIgnored private var storedAgent: AgentController?
    var agent: AgentController {
        if let storedAgent { return storedAgent }
        let agent = AgentController(plans: plans, panel: { [unowned self] in self.hosts[.primary]! }, reloadAll: { [unowned self] in
            self.reloadAll()
            self.hosts[.editor]?.load()
        })
        agent.onLiveChange = { [weak self] live in
            guard let self else { return }
            self.agentLive = live
            self.home.agentLive = live
            self.hosts[.primary]?.call("agentLive", live)
            self.refreshStatusIcon()
        }
        agent.onHostChange = { [weak self] host in self?.hosts[.agent] = host }
        storedAgent = agent
        return agent
    }
    var lastSummary: [String: Any] = [:]
    var agentLive = false
    var loginState: LoginItem.State = .off
    var connectedDevices: [String] = []
    var islandShown = false
    /// What the closed island's right ear shows: Auto, AC or Solar (Settings).
    var islandEar = AppModel.storedIslandEar
    /// The main window's sidebar: which screen it shows, and whether it is shown at all (left as
    /// the user leaves it, with the toolbar's sidebar button).
    var section: MainSection = .home
    var sidebar: NavigationSplitViewVisibility = .all
    /// The home's name, for the main window's title.
    var homeName = "Home"
    /// Set by the delegate when macOS started the app as a login item: no window opens then.
    @ObservationIgnored var launchedAtLogin = false
    @ObservationIgnored var mainWindow: MainWindowController?
    @ObservationIgnored weak var homeSlot: WebSlotView?
    @ObservationIgnored var primaryPlace: PrimaryPlace = .none
    /// The main window is open and not minimised, as its controller last said.
    @ObservationIgnored var mainShown = false
    /// The main window is open (minimised counts as open): the Dock icon shows.
    @ObservationIgnored var mainOpen = false
    /// Counts requests to open the panel, so one still waiting for a snapshot can tell it was cancelled.
    @ObservationIgnored var panelRequest = 0
    /// The AI Access page, made the first time its screen is shown and kept from then on.
    @ObservationIgnored var agentPage: WebHost?
    /// Pair iPhone: the code to scan and how pairing is going.
    var pairingLink: String?
    var pairingStatus = PairingStatus(text: "", active: false)
    struct PairingStatus: Equatable { var text: String; var active: Bool }

    enum HostRole: CaseIterable { case primary, editor, agent, island }
    @ObservationIgnored var hosts: [HostRole: WebHost] = [:]
    /// The Smart Life User Code a paired iPhone signed in with, to save typing it here.
    @ObservationIgnored var phoneUserCode = ""
    /// Desktop widgets and Control Center controls: what they show, what they asked for.
    @ObservationIgnored let widgets = WidgetBridge()
    /// Every lamp's and AC's state: the pages draw it and send it what the user does.
    @ObservationIgnored var homeStore: HomeStore?
    /// The native controls over the 3D page, in the panel and in the window.
    @ObservationIgnored let home = HomeModel()
    /// Where the panel shows the page.
    @ObservationIgnored weak var panelSlot: WebSlotView?
    @ObservationIgnored var keyMonitor: Any?
    @ObservationIgnored var menuMonitor: Any?
    @ObservationIgnored var openedLaunchDevice = false
    @ObservationIgnored var islandModel: IslandModel?
    /// The plan the store was made for, to tell when it changes.
    @ObservationIgnored var homePlanKey: Data?
    @ObservationIgnored var homePlan: [String: Any]?
    /// Each page's last intent the store took in (see `sync` in web/src/store.js).
    @ObservationIgnored var intentAcks: [ObjectIdentifier: Int] = [:]
    @ObservationIgnored var pendingPush: PendingPush?

    /// All entry points share one route; the AppKit controllers still own their windows.
    @ObservationIgnored private var storedRouter: WindowRouter?
    var router: WindowRouter {
        if let storedRouter { return storedRouter }
        let router = WindowRouter { [weak self] destination in
            guard let self else { return }
            switch destination {
            case .home: self.showMainWindow(.home)
            // Without the menu bar icon (the island is used instead) there is no panel: the window.
            case .panel:
                if !self.statusItem.isVisible { self.showMainWindow(.home) } else if !self.panel.isVisible { self.togglePanel() }
            case .editor: self.showMainWindow(.editor)
            case .connections(let service): self.openConnections(service)
            case .agent: self.showMainWindow(.agent)
            case .pairing: self.showMainWindow(.pairing)
            case .settings: self.showMainWindow(.settings)
            }
        }
        storedRouter = router
        return router
    }

    func start() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = symbol("house.fill")
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "House Control"
        }

        let host = WebHost(mode: "panel", transparent: true) { [unowned self] in
            var boot = self.bootPayload()
            boot["nativeControls"] = true // the controls are drawn natively over this page
            return boot
        }
        host.onMessage = { [weak self, unowned host] message in self?.handle(message, from: host) }
        hosts[.primary] = host
        let surface = NSHostingView(rootView: HomeSurface(model: home, chrome: .menubar) { [weak self] slot, present in
            if present { self?.panelSlot = slot }
        })
        panel = PanelController(host: host, surface: surface)
        panel.takePage = { [weak self, unowned host] in
            surface.layoutSubtreeIfNeeded() // the slot reports itself once it is laid out
            self?.panelSlot?.lend(host.webView)
        }
        panel.onVisibilityChange = { [weak self] visible in self?.setPolling(visible) }
        // Going back to the main window, the page is not hidden: it keeps its room and sheet.
        panel.keepsPageLive = { [weak self] in self?.homeSlot != nil && self?.mainShown == true }
        panel.onHidden = { [weak self] in
            guard let self else { return }
            if self.panel.keepsPageLive?() != true { self.home.reset() }
            self.primaryPlace = .none
            self.placePrimary()
        }
        startHomeControls()
        hub.onStale = { [weak self] in self?.poll() }
        widgets.onActions = { [weak self] run, adopt in
            guard let store = self?.homeStore else { return }
            for object in run {
                guard let data = try? JSONSerialization.data(withJSONObject: object),
                      let action = try? JSONDecoder().decode(HomeAction.self, from: data) else { continue }
                store.run(action)
            }
            // What a widget changed by itself is shown, and not sent to the device again.
            if let adopt { store.adoptDelivered(adopt) }
        }
        reloadLinks()
        host.load()
        startSync()
        // macOS remembers a hidden menu bar icon: without the island it is shown again.
        if islandEnabled { showIsland() } else { updateStatusItem() }
        LoginItem.followMove()
        loginState = LoginItem.state

        // HOUSE_SNAPSHOT_DIR=<folder> writes panel.png and island.png there a few seconds
        // after launch: a look at the UI without a screen (see HOUSE_RENDER_HIDDEN).
        if let folder = ProcessInfo.processInfo.environment["HOUSE_SNAPSHOT_DIR"] {
            let directory = URL(fileURLWithPath: folder, isDirectory: true)
            let delay = Double(ProcessInfo.processInfo.environment["HOUSE_SNAPSHOT_DELAY"] ?? "") ?? 6
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.hosts[.primary]?.snapshot(to: directory.appendingPathComponent("panel.png"))
                self?.island?.snapshot(to: directory.appendingPathComponent("island.png"))
                self?.mainWindow?.snapshot(to: directory.appendingPathComponent("main.png"), page: self?.homeSlot)
            }
        }
        // House Control lives in the menu bar; its window opens by itself only the very first
        // time, so it is found (and with HOUSE_OPEN_WINDOW=1, for scripted runs).
        // A run with its own data folder (HOUSE_DATA_DIR, for tests) leaves the real first launch alone.
        let firstLaunch = ProcessInfo.processInfo.environment["HOUSE_DATA_DIR"] == nil
            && !UserDefaults.standard.bool(forKey: "mainWindowSeen")
        if (firstLaunch && !launchedAtLogin) || ProcessInfo.processInfo.environment["HOUSE_OPEN_WINDOW"] != nil {
            router.show(.home)
        }
        if ProcessInfo.processInfo.environment["HOUSE_OPEN_PAIRING"] != nil {
            router.show(.pairing)
        }
        // HOUSE_OPEN_EDITOR=1 for Edit Home, connections|smartlife|homeassistant|hue|homekit for Connections (on that platform).
        if let open = ProcessInfo.processInfo.environment["HOUSE_OPEN_EDITOR"] {
            if open == "connections" {
                router.show(.connections(service: nil))
            } else if ConnectionsModel.Service(rawValue: open) != nil {
                router.show(.connections(service: open))
            } else {
                router.show(.editor)
            }
        }
        if let open = ProcessInfo.processInfo.environment["HOUSE_OPEN_AGENT"] {
            router.show(.agent) { [weak self] in
                if open == "start" { self?.agent.start() }
            }
        }
        if ProcessInfo.processInfo.environment["HOUSE_OPEN_SETTINGS"] != nil {
            router.show(.settings)
        }
        if ProcessInfo.processInfo.environment["HOUSE_OPEN_ON_LAUNCH"] != nil {
            router.show(.panel)
        }
    }

    /// `housecontrol://open[?device=…]`: a click on a widget opens the panel (on that lamp, AC or room).
    func open(urls: [URL]) {
        guard let url = urls.first, url.scheme == SyncPairing.scheme, url.host == "open" else { return }
        show(device: URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "device" })?.value)
    }

    /// The panel (the window, when the island stands in for the menu bar icon), on a device's
    /// sheet or a room (`HomeModel.open(device:)`).
    func show(device: String?) {
        router.whenReady { [weak self] in
            guard let self else { return }
            if !self.panel.isVisible { self.router.show(.panel) }
            if let device { self.home.open(device: device) }
        }
    }

    // MARK: - Status item

    private func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "House Control")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        image?.isTemplate = true
        return image
    }

    func updateStatus(_ summary: [String: Any]) {
        lastSummary = summary
        refreshStatusIcon()
    }

    /// The house, with sparkles beside it while an AI assistant has a live link.
    private func refreshStatusIcon() {
        guard let button = statusItem.button else { return }
        let summary = lastSummary
        let lights = summary["lightsOn"] as? Int ?? 0
        let acOn = summary["acOn"] as? Int ?? 0
        var parts: [String] = []
        if lights > 0 { parts.append("\(lights)") }
        if acOn > 0, let target = summary["acTarget"] as? Int { parts.append("\(target)°") }
        let house = lights > 0 || acOn > 0 ? "house.fill" : "house"
        button.image = agent.isLive ? pair(house, "sparkles") : symbol(house)
        button.attributedTitle = NSAttributedString(
            string: parts.isEmpty ? "" : " " + parts.joined(separator: " · "),
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)])
    }

    /// Two symbols side by side as one template image.
    private func pair(_ first: String, _ second: String) -> NSImage? {
        guard let a = symbol(first), let b = NSImage(systemSymbolName: second, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)) else { return symbol(first) }
        let size = NSSize(width: a.size.width + b.size.width + 1, height: max(a.size.height, b.size.height))
        let image = NSImage(size: size, flipped: false) { _ in
            a.draw(in: NSRect(x: 0, y: (size.height - a.size.height) / 2, width: a.size.width, height: a.size.height))
            b.draw(in: NSRect(x: a.size.width + 1, y: size.height - b.size.height, width: b.size.width, height: b.size.height))
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            dismissPanel()
            statusItem.menu = appMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        togglePanel()
    }

    /// The app's menu: on the menu bar icon (right click), or the island's gear while the island
    /// stands in for the icon.
    func appMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open House Control", action: #selector(requestHome), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Edit Home…", action: #selector(requestEditor), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Load Floor Plan…", action: #selector(loadPlan), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Reveal Plan File", action: #selector(revealPlan), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Reveal Device Log", action: #selector(revealLog), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let islandItem = menu.addItem(withTitle: "Use the Island Instead of the Menu Bar Icon", action: #selector(toggleIsland), keyEquivalent: "")
        islandItem.target = self
        islandItem.state = island?.isShown == true ? .on : .off
        loginState = LoginItem.state
        let login = loginState
        let loginItem = menu.addItem(withTitle: login == .needsApproval ? "Open at Login — Allow in Settings…" : "Open at Login",
                                     action: #selector(toggleOpenAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = login == .on ? .on : login == .needsApproval ? .mixed : .off
        menu.addItem(withTitle: "Pair iPhone…", action: #selector(requestPairing), keyEquivalent: "").target = self
        let aiItem = menu.addItem(withTitle: agent.isLive ? "AI Access — Live" : "AI Access…", action: #selector(requestAgent), keyEquivalent: "")
        aiItem.target = self
        aiItem.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        if agent.isLive {
            menu.addItem(withTitle: "Stop AI Access", action: #selector(stopAgent), keyEquivalent: "").target = self
        }
        connectedDevices = sync.connectedDevices
        for device in connectedDevices {
            let item = menu.addItem(withTitle: "\(device) is connected", action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: nil)
        }
        menu.addItem(.separator())
        menu.addItem(aboutMenuItem())
        menu.addItem(withTitle: "Settings…", action: #selector(requestSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Reload", action: #selector(reloadAll), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit House Control", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    /// The island stands in for the menu bar icon: one of the two is shown, never both.
    func updateStatusItem() {
        statusItem.isVisible = island?.isShown != true
    }

    private func togglePanel() {
        guard let button = statusItem.button else { return }
        if panel.isVisible {
            dismissPanel()
            return
        }
        openPanel(below: button) { [weak self] in
            // It can be switched off in System Settings too: the panel's menu shows what is true now.
            guard let self, self.panel.isVisible else { return }
            self.loginState = LoginItem.state
            self.hosts[.primary]?.call("openAtLogin", self.loginState.rawValue)
        }
    }

    // MARK: - Plans

    func bootPayload() -> [String: Any] {
        var boot = plans.bootPayload()
        boot["services"] = hub.servicesInfo
        boot["agentLive"] = agent.isLive
        loginState = LoginItem.state
        boot["openAtLogin"] = loginState.rawValue
        stateBoot(&boot)
        // HOUSE_OPEN_DEVICE=<id> starts the panel on that light's or AC's detail sheet.
        if let device = ProcessInfo.processInfo.environment["HOUSE_OPEN_DEVICE"] { boot["openDevice"] = device }
        return boot
    }

    func reloadLinks() {
        loadHomeStore()
        storedConnections?.plan = homePlan
        hub.setLinks(from: plans.activePlan == "custom" ? plans.customPlan() : nil)
        homeName = plans.activePlan == "custom" ? (plans.customPlanName ?? "My home") : "Demo home"
    }

    /// A platform was connected or disconnected: read the devices again and tell the phones.
    func connectionsChanged() {
        reloadLinks()
        setPolling(false) // reads at once while the panel or the island is open
        sync.broadcast()
    }

    @objc func reloadAll() {
        reloadLinks()
        widgets.isReady = false
        hosts[.primary]?.load()
        if island?.isShown == true { hosts[.island]?.load() }
        sync.broadcast()
    }

    @objc func loadPlan() {
        dismissPanel()
        NSApp.activate(ignoringOtherApps: true)
        let open = NSOpenPanel()
        open.title = "Choose a floor plan"
        open.allowedContentTypes = [.json]
        guard open.runModal() == .OK, let url = open.url else { return }
        do {
            try plans.importPlan(from: url)
            reloadAll()
            hosts[.editor]?.load()
        } catch {
            alert("Could not load this floor plan", error.localizedDescription)
        }
    }

    @objc func revealPlan() {
        let url = plans.hasCustomPlan ? plans.customPlanURL : WebHost.assetRoot.appendingPathComponent("plans/\(plans.activePlan).json")
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// "About House Control": the version, the website and where to find the developer.
    private func aboutMenuItem() -> NSMenuItem {
        let about = NSMenu()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        about.addItem(withTitle: "House Control\(version.map { " \($0)" } ?? "")", action: nil, keyEquivalent: "")
        about.addItem(.separator())
        let links: [(String, String, URL)] = [
            ("Website", "globe", About.website),
            ("Privacy Policy", "hand.raised", About.privacy),
            ("Support", "questionmark.circle", About.support),
            ("", "", About.website),
            ("\(About.developer) on X", "at", About.x),
            ("\(About.developer) on GitHub", "chevron.left.forwardslash.chevron.right", About.github),
            ("Source Code", "shippingbox", About.source),
        ]
        for (title, symbol, url) in links {
            guard !title.isEmpty else { about.addItem(.separator()); continue }
            let item = about.addItem(withTitle: title, action: #selector(openLink(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        let item = NSMenuItem(title: "About House Control", action: nil, keyEquivalent: "")
        item.submenu = about
        return item
    }

    @objc private func openLink(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) }
    }

    @objc func revealLog() {
        if !FileManager.default.fileExists(atPath: hub.log.fileURL.path) { hub.log.write("log started") }
        NSWorkspace.shared.activateFileViewerSelecting([hub.log.fileURL])
    }

    @objc private func requestHome() { router.show(.home) }
    @objc private func requestSettings() { router.show(.settings) }
    @objc private func requestEditor() { router.show(.editor) }
    @objc private func requestAgent() { router.show(.agent) }
    @objc private func requestPairing() { router.show(.pairing) }

    /// Connections in the main window, on one platform's screen when `service` names one.
    private func openConnections(_ service: String?) {
        connections.path = service.flatMap(ConnectionsModel.Service.init(rawValue:)).map { [$0] } ?? []
        showMainWindow(.connections)
    }

    func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }

    // MARK: - AI Access

    @objc private func stopAgent() { agent.stop() }

    // MARK: - Device state

    /// Real devices are read while there is something on screen to show them in.
    func setPolling(_ requested: Bool) {
        let on = requested || panel.isVisible || primaryPlace == .home || island?.isExpanded == true
        pollTimer?.invalidate()
        pollTimer = nil
        guard on, hub.canPoll else { return }
        poll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        Task { @MainActor in
            guard let update = await hub.poll() else { return }
            homeStore?.applyRemote(update)
        }
    }

    // MARK: - Island

    /// Off unless switched on in Settings or the menu (or by HOUSE_ISLAND=1 for one run).
    private var islandEnabled: Bool {
        if let forced = ProcessInfo.processInfo.environment["HOUSE_ISLAND"] { return forced != "0" }
        return UserDefaults.standard.object(forKey: "island") as? Bool ?? false
    }

    private func showIsland() {
        if island == nil {
            let host = WebHost(mode: "island", transparent: true) { [unowned self] in
                var boot = self.plans.bootPayload()
                boot["island"] = self.island?.bootInfo ?? [:]
                boot["nativeControls"] = true // the island is drawn natively around this page's model
                self.stateBoot(&boot)
                return boot
            }
            host.onMessage = { [weak self, unowned host] message in self?.handle(message, from: host) }
            let islandModel = IslandModel(home: home)
            islandModel.earChoice = islandEar
            islandModel.onBump = { [weak self] id in self?.hosts[.island]?.call("bump", id) }
            islandModel.onMenu = { [weak self] in self?.appMenu().popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil) }
            islandModel.onOpen = { [weak self] device in self?.show(device: device) }
            self.islandModel = islandModel
            let controller = IslandController(host: host, model: islandModel)
            controller.onExpandedChange = { [weak self] open in self?.setPolling(open) }
            hosts[.island] = host
            island = controller
        }
        island?.show()
        islandShown = island?.isShown == true
        updateStatusItem()
    }

    @objc private func toggleIsland() { setIsland(island?.isShown != true) }

    func setIsland(_ show: Bool) {
        // A run with its own data folder (HOUSE_DATA_DIR, for tests) leaves the real setting alone.
        if ProcessInfo.processInfo.environment["HOUSE_DATA_DIR"] == nil { UserDefaults.standard.set(show, forKey: "island") }
        if show { showIsland() } else { island?.hide() }
        islandShown = island?.isShown == true
        updateStatusItem()
    }

    /// Auto unless chosen in Settings (or by HOUSE_ISLAND_EAR=auto|ac|solar for one run).
    private static var storedIslandEar: IslandEar.Choice {
        let raw = ProcessInfo.processInfo.environment["HOUSE_ISLAND_EAR"] ?? UserDefaults.standard.string(forKey: "islandEar")
        return raw.flatMap(IslandEar.Choice.init) ?? .auto
    }

    func setIslandEar(_ choice: IslandEar.Choice) {
        // A run with its own data folder (HOUSE_DATA_DIR, for tests) leaves the real setting alone.
        if ProcessInfo.processInfo.environment["HOUSE_DATA_DIR"] == nil { UserDefaults.standard.set(choice.rawValue, forKey: "islandEar") }
        islandEar = choice
        islandModel?.earChoice = choice
    }

    // MARK: - Open at Login

    /// Waiting for approval counts as off: choosing it again takes the user to System Settings.
    @objc private func toggleOpenAtLogin() { setOpenAtLogin(LoginItem.state != .on) }

    func setOpenAtLogin(_ on: Bool) {
        if on, LoginItem.isTemporaryCopy {
            alert("Move House Control to Applications first",
                  "It is running from the disk image or from a temporary copy of the download, which is gone after a restart. "
                  + "Drag House Control into the Applications folder, open it from there, then turn on Open at Login.")
            return
        }
        do {
            try LoginItem.set(on)
        } catch {
            alert(on ? "Could not add House Control to Login Items" : "Could not remove House Control from Login Items",
                  "\(error.localizedDescription)\n\nYou can change it in System Settings → General → Login Items.")
        }
        loginState = LoginItem.state
        hosts[.primary]?.call("openAtLogin", loginState.rawValue)
        // The very first registration can take a moment to show in the status.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            self.loginState = LoginItem.state
            self.hosts[.primary]?.call("openAtLogin", self.loginState.rawValue)
        }
    }
}
