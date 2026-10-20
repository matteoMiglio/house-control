import AppKit
import SwiftUI
import WebKit

/// A place in a SwiftUI view where a web page can be shown. The page itself (a WKWebView)
/// belongs to the app, not to the view: it is lent to whichever slot should show it and taken
/// back when that slot goes away, so the page keeps its state, its 3D model and its scroll
/// position as it moves between the menu bar panel and the main window.
final class WebSlotView: NSView {
    /// Set by the owner of the page: the slot came on screen (true) or left it (false).
    var onPresence: ((WebSlotView, Bool) -> Void)?
    private let still = NSImageView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        still.imageScaling = .scaleAxesIndependently
        still.autoresizingMask = [.width, .height]
        still.frame = bounds
        addSubview(still)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows the page here.
    func lend(_ webView: WKWebView) {
        guard webView.superview !== self else { return }
        webView.removeFromSuperview()
        webView.frame = bounds
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)
        still.isHidden = true
    }

    /// While the page is shown somewhere else, the slot keeps a still of how it last looked.
    func showStill(_ image: NSImage?) {
        still.image = image
        still.isHidden = false
    }

    /// Arrived in a window, not yet laid out there.
    private var arriving = false

    // The page is only lent (and told it is on screen) once the slot has its real size: shown
    // any earlier, the 3D view would start its intro at the old size and be resized mid-way.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        arriving = window != nil
        if arriving {
            needsLayout = true
        } else {
            onPresence?(self, false)
        }
    }

    override func layout() {
        super.layout()
        guard arriving, !bounds.isEmpty else { return }
        arriving = false
        onPresence?(self, true)
    }
}

struct WebSlot: NSViewRepresentable {
    let onPresence: (WebSlotView, Bool) -> Void

    func makeNSView(context: Context) -> WebSlotView {
        let view = WebSlotView()
        view.onPresence = onPresence
        return view
    }

    func updateNSView(_ view: WebSlotView, context: Context) {
        view.onPresence = onPresence
    }
}
