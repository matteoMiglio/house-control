import AppKit
import SwiftUI

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
            // Told before the window is gone (windowWillClose): what it says counts, not its isVisible.
            controller.onVisibilityChange = { [weak self] shown in
                self?.mainShown = shown
                self?.placePrimary()
            }
            controller.onOpenChange = { [weak self] open in
                self?.mainOpen = open
                self?.updateDockIcon()
            }
            mainWindow = controller
        }
        dismissPanel()
        UserDefaults.standard.set(true, forKey: "mainWindowSeen")
        mainWindow?.show()
    }

    /// House Control is a menu bar app; while one of its windows is open (the main window, the
    /// editor, Settings) it also has a Dock icon and a place in ⌘-Tab, like any app with a window.
    func updateDockIcon() {
        let policy: NSApplication.ActivationPolicy = mainOpen || editor != nil || settingsOpen ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
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
        if let slot = homeSlot, mainShown {
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

    /// The AI Access screen came on screen: it shows the AI Access page, made the first time.
    func agentSlot(_ slot: WebSlotView, present: Bool) {
        guard present else { return }
        if agentPage == nil {
            let host = WebHost(mode: "agent", transparent: false) { [unowned self] in ["agent": self.agent.status()] }
            agent.attach(host)
            agentPage = host
            host.load()
        }
        if let host = agentPage { slot.lend(host.webView) }
    }

    /// House Control → Settings… (⌘,): the SwiftUI settings in a window of their own, opened
    /// directly like the main window (macOS gives AppKit no way to open the Settings scene).
    func openSettings() {
        dismissPanel()
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: MacSettingsView(model: self)))
            window.title = "House Control Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.center()
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.settingsOpen = false
                    self?.updateDockIcon()
                }
            }
            settingsWindow = window
        }
        settingsOpen = true
        updateDockIcon()
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Opens the panel, taking its page from the main window if it is there: the window keeps a
    /// still of how the page looked until the panel gives it back.
    func openPanel(below button: NSStatusBarButton, then done: @escaping () -> Void) {
        panelRequest += 1
        let request = panelRequest
        guard primaryPlace == .home, let slot = homeSlot, let host = hosts[.primary] else {
            panel.toggle(below: button)
            panelToggled()
            done()
            return
        }
        host.webView.takeSnapshot(with: nil) { [weak self] image, _ in
            // Something else (a window, a second click) came first: the panel stays closed.
            guard let self, request == self.panelRequest else { return }
            slot.showStill(image)
            self.panel.toggle(below: button)
            self.panelToggled()
            done()
        }
    }

    /// Closes the panel, and cancels an opening still waiting for its snapshot.
    func dismissPanel() {
        panelRequest += 1
        panel.hide()
    }

    /// The panel's page (re)loaded: it learns again where it is shown, and starts drawing there.
    func primaryLoaded() {
        guard let host = hosts[.primary] else { return }
        if panel.isVisible {
            host.call("setChrome", "menubar")
            host.call("shown")
        } else if primaryPlace == .home {
            host.call("setChrome", "window")
            host.call("shown")
        }
    }

    private func panelToggled() {
        if panel.isVisible { primaryPlace = .panel } else { placePrimary() }
    }
}
