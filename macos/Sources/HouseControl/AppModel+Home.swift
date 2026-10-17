import AppKit

/// What the main window's sidebar shows.
enum MainSection: Hashable { case home, agent, pairing }

/// Where the panel page is on screen. There is one such page (its 3D model, its state, its
/// device commands), lent to whichever of the two places shows it.
enum PrimaryPlace { case none, panel, home }

extension AppModel {
    // MARK: - Main window

    func showMainWindow(_ section: MainSection? = nil) {
        if let section { self.section = section }
        if mainWindow == nil {
            let controller = MainWindowController(model: self)
            controller.onVisibilityChange = { [weak self] _ in self?.placePrimary() }
            mainWindow = controller
        }
        panel.hide()
        mainWindow?.show()
    }

    /// The Home view's slot came on screen (it is shown in the window) or left it.
    func homeSlot(_ slot: WebSlotView, present: Bool) {
        if present { homeSlot = slot } else if homeSlot === slot { homeSlot = nil }
        placePrimary()
    }

    /// Puts the panel page where it can be seen: in the panel while that is open (it takes the
    /// page itself), otherwise in the main window's Home, otherwise nowhere.
    func placePrimary() {
        guard let host = hosts[.primary], !panel.isVisible else { return }
        if let slot = homeSlot, mainWindow?.isVisible == true {
            guard primaryPlace != .home || host.webView.superview !== slot else { return }
            slot.lend(host.webView)
            host.call("setChrome", "window")
            host.call("shown")
            primaryPlace = .home
        } else if primaryPlace == .home {
            host.call("hidden")
            primaryPlace = .none
        }
        setPolling(false)
    }

    /// Opens the panel, taking its page from the main window if it is there: the window keeps a
    /// still of how the page looked until the panel gives it back.
    func openPanel(below button: NSStatusBarButton, then done: @escaping () -> Void) {
        guard primaryPlace == .home, let slot = homeSlot, let host = hosts[.primary] else {
            panel.toggle(below: button)
            panelToggled()
            done()
            return
        }
        host.webView.takeSnapshot(with: nil) { [weak self] image, _ in
            guard let self else { return }
            slot.showStill(image)
            self.panel.toggle(below: button)
            self.panelToggled()
            done()
        }
    }

    private func panelToggled() {
        if panel.isVisible { primaryPlace = .panel } else { placePrimary() }
    }
}
