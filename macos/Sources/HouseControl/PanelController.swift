import AppKit
import WebKit

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The borderless popover under the menu bar icon. The web content draws the card
/// (rounded corners, notch, shadow) itself on a fully transparent window.
///
/// The page is shared with the main window: the panel takes it back each time it opens, and
/// gives it up (see `onHidden`) once it has faded out.
final class PanelController: NSObject, NSWindowDelegate {
    private static let card = NSSize(width: 440, height: 800)
    // Transparent margin around the card, matching `html.native #app` padding in style.css.
    private static let padTop: CGFloat = 13, padSide: CGFloat = 24, padBottom: CGFloat = 34

    let host: WebHost
    private let window: FloatingPanel
    private var outsideClickMonitor: Any?
    private(set) var isVisible = false
    private var lastHide = Date.distantPast
    var onVisibilityChange: ((Bool) -> Void)?
    /// After the panel has faded out and told the page it is hidden: the page is free to go elsewhere.
    var onHidden: (() -> Void)?
    /// Keeps the panel open when it loses focus (HOUSE_PIN=1, for UI automation and screenshots).
    private let pinned = ProcessInfo.processInfo.environment["HOUSE_PIN"] != nil

    init(host: WebHost) {
        self.host = host
        let size = NSSize(width: Self.card.width + Self.padSide * 2, height: Self.card.height + Self.padTop + Self.padBottom)
        window = FloatingPanel(contentRect: NSRect(origin: .zero, size: size),
                               styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                               backing: .buffered, defer: false)
        super.init()
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        window.isMovable = false
        window.hidesOnDeactivate = false
        window.animationBehavior = .none
        window.delegate = self
        window.contentView = host.webView
        window.alphaValue = 0
    }

    func toggle(below button: NSStatusBarButton) {
        if isVisible { hide(); return }
        // The click that dismissed the panel (resign key) must not immediately reopen it.
        if Date().timeIntervalSince(lastHide) < 0.25 { return }
        show(below: button)
    }

    func show(below button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var size = window.frame.size
        size.height = min(Self.card.height + Self.padTop + Self.padBottom, visible.height - 4)
        var x = anchor.midX - size.width / 2
        x = max(visible.minX + 4 - Self.padSide, min(x, visible.maxX - size.width - 4 + Self.padSide))
        let y = anchor.minY - size.height + 3
        window.setFrame(NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height), display: true)

        // The page may have been lent to the main window since the panel last showed it.
        if window.contentView !== host.webView {
            host.webView.removeFromSuperview()
            window.contentView = host.webView
        }
        host.call("setChrome", "menubar")
        host.call("setNotch", Double(anchor.midX - x - Self.padSide))
        host.call("shown")

        isVisible = true
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            window.animator().alphaValue = 1
        }
        if !pinned {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.hide()
            }
        }
        onVisibilityChange?(true)
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        lastHide = Date()
        if let monitor = outsideClickMonitor { NSEvent.removeMonitor(monitor) }
        outsideClickMonitor = nil
        // The fade's completion does not come while the display sleeps (nothing animates then),
        // so a timer finishes the job too: whichever comes first, once.
        let finish = { [weak self] in
            guard let self, !self.isVisible, self.window.isVisible else { return }
            self.window.orderOut(nil)
            self.host.call("hidden")
            self.onHidden?()
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            window.animator().alphaValue = 0
        }, completionHandler: finish)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: finish)
        onVisibilityChange?(false)
    }

    func windowDidResignKey(_ notification: Notification) {
        if !pinned { hide() }
    }
}
