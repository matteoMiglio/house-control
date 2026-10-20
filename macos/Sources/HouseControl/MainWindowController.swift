import AppKit
import Observation
import SwiftUI
import WebKit

/// The app's main window: the SwiftUI `MainView` in a window of its own. It is an AppKit window
/// rather than a SwiftUI scene so that the menu bar icon, links and the Dock can all open it
/// directly, and so that it never reopens by itself when the Mac starts the app at login.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private(set) var window: NSWindow
    /// The window came on screen (true) or left it: closed or minimised (false).
    var onVisibilityChange: ((Bool) -> Void)?
    /// The window opened (true) or closed (false); minimised it is still open.
    var onOpenChange: ((Bool) -> Void)?

    init(model: AppModel) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        let hosting = NSHostingController(rootView: MainView(model: model))
        // No toolbar (it had nothing in it): just the title bar's traffic lights, above the content.
        hosting.sceneBridgingOptions = []
        window.contentViewController = hosting
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        observeHomeName(model)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(calibratedRed: 0.04, green: 0.055, blue: 0.1, alpha: 1)
        window.minSize = NSSize(width: 1000, height: 600) // the editor's plan, list and inspector side by side
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.delegate = self
        window.setContentSize(NSSize(width: 1280, height: 820))
        window.center()
        window.setFrameAutosaveName("HouseControlMain")
    }

    /// Keep the window's title with the home, whichever screen is selected.
    private func observeHomeName(_ model: AppModel) {
        withObservationTracking {
            window.title = model.homeName
        } onChange: { [weak self, weak model] in
            Task { @MainActor in
                guard let self, let model else { return }
                self.observeHomeName(model)
            }
        }
    }

    var isVisible: Bool { window.isVisible && !window.isMiniaturized }

    func show() {
        onOpenChange?(true)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        onVisibilityChange?(true)
    }

    /// Writes a PNG of the window (HOUSE_SNAPSHOT_DIR): its SwiftUI views as they draw, with
    /// the web page inside them taken by WebKit, which draws it on the GPU.
    func snapshot(to url: URL, page: WebSlotView?) {
        guard window.isVisible, let content = window.contentView,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: rep)
        let write: (NSImage?) -> Void = { pageImage in
            let image = NSImage(size: content.bounds.size)
            image.lockFocus()
            rep.draw(in: content.bounds)
            if let pageImage, let page { pageImage.draw(in: page.convert(page.bounds, to: content)) }
            image.unlockFocus()
            guard let tiff = image.tiffRepresentation, let out = NSBitmapImageRep(data: tiff) else { return }
            try? out.representation(using: .png, properties: [:])?.write(to: url)
        }
        guard let web = page?.subviews.compactMap({ $0 as? WKWebView }).first else { write(nil); return }
        web.takeSnapshot(with: nil) { image, _ in write(image) }
    }

    func windowWillClose(_ notification: Notification) {
        onVisibilityChange?(false)
        onOpenChange?(false)
    }
    func windowDidMiniaturize(_ notification: Notification) { onVisibilityChange?(false) }
    func windowDidDeminiaturize(_ notification: Notification) { onVisibilityChange?(true) }
}
