import AppKit
import SwiftUI

/// A Lucide icon, the same one the web UI draws under that name (web/src/ui/icons.js), tinted
/// by the foreground style like a symbol.
struct Icon: View {
    let name: String
    var size: CGFloat = 18
    var stroke: CGFloat = 1.8

    init(_ name: String, size: CGFloat = 18, stroke: CGFloat = 1.8) {
        self.name = name
        self.size = size
        self.stroke = stroke
    }

    var body: some View {
        Image(nsImage: Self.image(name, stroke: stroke))
            .renderingMode(.template)
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    // Drawn from SVG (macOS reads it natively), once per name and stroke width.
    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor static func image(_ name: String, stroke: CGFloat) -> NSImage {
        let key = "\(name)@\(stroke)"
        if let image = cache[key] { return image }
        let elements = LucideIcons.elements[name] ?? LucideIcons.elements["sparkles"] ?? ""
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" \
            stroke="#000" stroke-width="\(stroke)" stroke-linecap="round" stroke-linejoin="round">\(elements)</svg>
            """
        let image = NSImage(data: Data(svg.utf8)) ?? NSImage()
        image.isTemplate = true
        cache[key] = image
        return image
    }
}
