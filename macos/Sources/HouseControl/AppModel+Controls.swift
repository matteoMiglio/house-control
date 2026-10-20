import AppKit
import HouseCore

extension AppModel {
    // MARK: - The native home controls

    /// Connects the native controls to the 3D page and to the rest of the app.
    func startHomeControls() {
        home.tellPage = { [weak self] function, args in self?.hosts[.primary]?.call(function, arguments: args) }
        home.onGear = { [weak self] in self?.showPlanMenu() }
        home.onAgentBadge = { [weak self] in self?.router.show(.agent) }
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

    /// HOUSE_OPEN_DEVICE=<id>: the first time the page is ready, that lamp's or AC's sheet (or room).
    func openDeviceOnLaunch() {
        guard !openedLaunchDevice, let device = ProcessInfo.processInfo.environment["HOUSE_OPEN_DEVICE"] else { return }
        openedLaunchDevice = true
        home.open(device: device)
    }

    /// The header's gear: the floor plans, and the rest of the app.
    func showPlanMenu() {
        let menu = NSMenu()
        let current = plans.activePlan
        if plans.hasCustomPlan {
            menu.addItem(ClosureMenuItem("My home", checked: current == "custom") { [weak self] in self?.choosePlan("custom") })
        }
        for (id, name) in [("home", "Demo · Apartment"), ("studio", "Demo · Studio")] {
            menu.addItem(ClosureMenuItem(name, checked: current == id) { [weak self] in self?.choosePlan(id) })
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Open House Control…") { [weak self] in self?.router.show(.home) })
        menu.addItem(ClosureMenuItem("Edit Home…") { [weak self] in self?.router.show(.editor(section: nil)) })
        menu.addItem(ClosureMenuItem("AI Access…") { [weak self] in self?.router.show(.agent) })
        menu.addItem(ClosureMenuItem("Load Floor Plan…") { [weak self] in self?.loadPlan() })
        menu.addItem(ClosureMenuItem("Reveal Plan File") { [weak self] in self?.revealPlan() })
        menu.addItem(.separator())
        loginState = LoginItem.state
        let login = loginState
        let item = ClosureMenuItem(login == .needsApproval ? "Open at Login — Allow in Settings…" : "Open at Login") { [weak self] in
            self?.setOpenAtLogin(login != .on)
        }
        item.state = login == .on ? .on : login == .needsApproval ? .mixed : .off
        menu.addItem(item)
        menu.addItem(ClosureMenuItem("Settings…") { [weak self] in self?.router.show(.settings) })
        menu.addItem(ClosureMenuItem("Quit House Control") { NSApp.terminate(nil) })
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func choosePlan(_ id: String) {
        guard id != plans.activePlan else { return }
        plans.select(id)
        reloadAll()
        hosts[.editor]?.load()
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
