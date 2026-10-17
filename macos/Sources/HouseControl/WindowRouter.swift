import Foundation

/// Keeps window requests until the existing controllers and primary page are ready.
@MainActor
final class WindowRouter {
    enum Destination {
        case home, editor(section: String?), agent, pairing, settings
    }

    /// Step 3 supplies SwiftUI's openWindow action here.
    var openWindow: ((String) -> Void)?
    private(set) var ready = false
    private var pending: [() -> Void] = []
    private let perform: (Destination) -> Void

    init(perform: @escaping (Destination) -> Void) {
        self.perform = perform
    }

    func show(_ destination: Destination, then completion: (() -> Void)? = nil) {
        whenReady { [weak self] in
            self?.perform(destination)
            completion?()
        }
    }

    /// Deep links also wait before addressing a device in the primary page.
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
