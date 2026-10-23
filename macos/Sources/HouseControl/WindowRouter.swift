import Foundation

/// One route for every way a window is asked for: the menu bar icon's menu, the web pages,
/// widget links, the Dock and the HOUSE_OPEN_* hooks. Windows open at once; what needs the
/// panel's page (the panel itself, a device to show in it) waits until that page has loaded —
/// or a few seconds, should it never say so (a page that failed still shows its error).
@MainActor
final class WindowRouter {
    enum Destination {
        /// `home` is the main window; `panel` the popover under the menu bar icon; `connections`
        /// opens one platform's screen when it names one.
        case home, panel, homes, editor, connections(service: String?), agent, pairing, settings
    }

    private(set) var ready = false
    private var pending: [() -> Void] = []
    private let perform: (Destination) -> Void

    init(perform: @escaping (Destination) -> Void) {
        self.perform = perform
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.markReady() }
    }

    func show(_ destination: Destination, then completion: (() -> Void)? = nil) {
        guard case .panel = destination else {
            perform(destination)
            completion?()
            return
        }
        whenReady { [weak self] in
            self?.perform(destination)
            completion?()
        }
    }

    /// Runs `action` once the panel's page is ready (deep links address a device in it).
    func whenReady(_ action: @escaping () -> Void) {
        guard ready else {
            pending.append(action)
            return
        }
        action()
    }

    func markReady() {
        guard !ready else { return }
        ready = true
        let requests = pending
        pending.removeAll()
        for action in requests { action() }
    }
}
