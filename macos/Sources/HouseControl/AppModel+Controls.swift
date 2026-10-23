import AppKit
import HouseCore

extension AppModel {
    // MARK: - The native home controls

    /// Connects the native controls to the 3D page and to the rest of the app.
    func startHomeControls() {
        home.tellPage = { [weak self] function, args in self?.hosts[.primary]?.call(function, arguments: args) }
        home.onGear = { [weak self] in self?.showPlanMenu() }
        home.onAgentBadge = { [weak self] in self?.router.show(.agent) }
        home.onBackHome = { [weak self] in self?.choosePlan("custom") }
        home.agentLive = agent.isLive
        // Escape closes an open menu, else the sheet, else the panel; it is caught before the page sees it.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else { return event }
            let inPanel = event.window === self.panel.nsWindow
            let inHome = event.window === self.mainWindow?.window && self.section == .home
            guard inPanel || inHome else { return event }
            if self.home.closeTopmost() { return nil }
            if inPanel {
                self.dismissPanel()
                return nil
            }
            return event
        }
        // A click anywhere but on an AC option menu (or the card that opened it) closes the menu,
        // and still does what it was for.
        menuMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.home.openMenu != nil, let content = event.window?.contentView else { return event }
            let p = content.convert(event.locationInWindow, from: nil)
            let point = CGPoint(x: p.x, y: content.isFlipped ? p.y : content.bounds.height - p.y)
            if !self.home.menuFrames.contains(where: { $0.contains(point) }) { self.home.openMenu = nil }
            return event
        }
    }

    /// HOUSE_OPEN_DEVICE=<id>: the first time the page is ready, that lamp's or AC's sheet (or room,
    /// or "energy" for the solar sheet).
    func openDeviceOnLaunch() {
        guard !openedLaunchDevice, let device = ProcessInfo.processInfo.environment["HOUSE_OPEN_DEVICE"] else { return }
        openedLaunchDevice = true
        home.open(device: device)
    }

    /// The header's gear: the floor plans, and the rest of the app.
    func showPlanMenu() {
        let menu = NSMenu()
        addHomeItems(to: menu)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Open House Control…") { [weak self] in self?.router.show(.home) })
        menu.addItem(ClosureMenuItem("Edit Home…") { [weak self] in self?.router.show(.editor) })
        menu.addItem(ClosureMenuItem("AI Access…") { [weak self] in self?.router.show(.agent) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Settings…") { [weak self] in self?.router.show(.settings) })
        menu.addItem(ClosureMenuItem("Quit House Control") { NSApp.terminate(nil) })
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    static let demos = [("home", "Apartment"), ("studio", "Studio")]

    /// The homes to switch to: My home first, with what it reaches; the demos apart, for trying
    /// things out; then the Floor Plans screen, where they are managed.
    func addHomeItems(to menu: NSMenu) {
        let current = plans.activePlan
        if let plan = plans.customPlan() {
            let item = ClosureMenuItem(plans.customPlanName ?? "My home", checked: current == "custom") { [weak self] in self?.choosePlan("custom") }
            if #available(macOS 14.4, *) { item.subtitle = Self.linkedLine(HomeConfig(plan: plan).linkedCount) }
            menu.addItem(item)
            menu.addItem(.separator())
        }
        menu.addItem(.sectionHeader(title: "Try a demo"))
        for (id, name) in Self.demos {
            menu.addItem(ClosureMenuItem(name, checked: current == id) { [weak self] in self?.choosePlan(id) })
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Manage Floor Plans…") { [weak self] in self?.router.show(.homes) })
    }

    /// The island's and the menu bar icon's menu: the same homes, one level down.
    func homesMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: plans.isDemo ? "Home: Demo" : "Home: \(homeName)", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        addHomeItems(to: submenu)
        item.submenu = submenu
        return item
    }

    /// "3 linked to real devices", or "Nothing linked yet".
    static func linkedLine(_ count: Int) -> String {
        count == 0 ? "Nothing linked yet" : "\(count) linked to real devices"
    }

    /// Switches home, and says where you are now: a demo is easy to mistake for your own.
    func choosePlan(_ id: String) {
        guard id != plans.activePlan else { return }
        plans.select(id)
        reloadAll()
        hosts[.editor]?.load()
        let demo = Self.demos.first { $0.0 == id }?.1
        home.showToast(demo.map { "Demo · \($0): everything here is simulated" } ?? homeName)
    }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let run: () -> Void

    init(_ title: String, checked: Bool = false, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(runAction), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func runAction() { run() }
}
