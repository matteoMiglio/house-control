import Combine
import SwiftUI

/// The panel's palette and motion, as web/src/style.css has them (`:root`).
enum P {
    static let bg = Color(red: 10 / 255, green: 14 / 255, blue: 26 / 255)
    static let text = Color(red: 243 / 255, green: 245 / 255, blue: 250 / 255)
    static let muted = Color(red: 222 / 255, green: 230 / 255, blue: 247 / 255).opacity(0.58)
    static let faint = Color(red: 222 / 255, green: 230 / 255, blue: 247 / 255).opacity(0.34)
    static let glass = Color.white.opacity(0.055)
    static let glassHi = Color.white.opacity(0.1)
    static let line = Color.white.opacity(0.085)
    static let accent = Color(red: 61 / 255, green: 139 / 255, blue: 1)
    static let warm = Color(red: 1, green: 180 / 255, blue: 107 / 255)
    static let live = Color(red: 74 / 255, green: 222 / 255, blue: 128 / 255)

    /// `--spring`: cubic-bezier(0.34, 1.56, 0.64, 1), a press that overshoots a little.
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.62)
    /// `--ease`: cubic-bezier(0.22, 1, 0.36, 1).
    static func ease(_ seconds: Double) -> Animation { .timingCurve(0.22, 1, 0.36, 1, duration: seconds) }
}

extension Color {
    /// "#rrggbb".
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v)
        self.init(.sRGB, red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

/// Whether the pointer is over a view: per-view state that needs no `@State` (not available
/// with the Command Line Tools).
final class Hover: ObservableObject {
    @Published var on = false
}

/// A cursor shown while the pointer is over a view, popped again even when the view goes away
/// under the pointer (SwiftUI does not report leaving then).
final class CursorHover: ObservableObject {
    private var pushed = false

    func set(_ inside: Bool, _ cursor: NSCursor) {
        if inside, !pushed { cursor.push(); pushed = true } else if !inside, pushed { NSCursor.pop(); pushed = false }
    }

    deinit { if pushed { NSCursor.pop() } }
}

private struct HoverCursor: ViewModifier {
    let cursor: NSCursor
    @StateObject private var state = CursorHover()

    func body(content: Content) -> some View {
        content
            .onHover { state.set($0, cursor) }
            .onDisappear { state.set(false, cursor) }
    }
}

extension View {
    /// `cursor:` in CSS.
    func hoverCursor(_ cursor: NSCursor) -> some View { modifier(HoverCursor(cursor: cursor)) }
}

/// Shrinks a little while pressed, springing back (`:active { transform: scale(…) }`).
struct PressScale: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(P.spring, value: configuration.isPressed)
    }
}

/// `.round`: a circle of glass with an icon; `.power` is the bigger one that lights up blue.
struct RoundButton: View {
    let icon: String
    var size: CGFloat = 36
    var iconSize: CGFloat = 17
    var stroke: CGFloat = 1.8
    var lit = false
    /// `.round.active`: the outside view is on.
    var active = false
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { RoundFace(icon: icon, size: size, iconSize: iconSize, stroke: stroke, lit: lit, active: active) }
            .buttonStyle(PressScale(scale: 0.9))
            .help(label)
            .accessibilityLabel(label)
    }
}

private struct RoundFace: View {
    let icon: String
    let size: CGFloat
    let iconSize: CGFloat
    let stroke: CGFloat
    let lit: Bool
    let active: Bool
    @StateObject private var hover = Hover()

    var body: some View {
        Icon(icon, size: iconSize, stroke: stroke)
            .foregroundStyle(lit ? Color.white : active ? Color(hex: "#cfeeff") : hover.on ? P.text : P.muted)
            .frame(width: size, height: size)
            .background {
                Circle().fill(fill)
            }
            .overlay { Circle().strokeBorder(border) }
            .shadow(color: lit ? Color(red: 61 / 255, green: 139 / 255, blue: 1).opacity(0.75) : .clear, radius: 11, y: 8)
            .contentShape(Circle())
            .onHover { hover.on = $0 }
            .animation(.easeOut(duration: 0.2), value: hover.on)
            .animation(.easeOut(duration: 0.3), value: lit)
    }

    private var fill: AnyShapeStyle {
        if lit {
            return AnyShapeStyle(LinearGradient(colors: hover.on ? [Color(hex: "#6aacff"), Color(hex: "#3a85f8")] : [Color(hex: "#5aa2ff"), Color(hex: "#2f7bf2")],
                                                startPoint: .top, endPoint: .bottom))
        }
        if active { return AnyShapeStyle(Color(red: 127 / 255, green: 211 / 255, blue: 1).opacity(0.18)) }
        return AnyShapeStyle(hover.on ? Color.white.opacity(0.16) : P.glassHi)
    }

    private var border: Color {
        if lit { return .white.opacity(0.28) }
        if active { return Color(red: 127 / 255, green: 211 / 255, blue: 1).opacity(0.4) }
        return P.line
    }
}

/// `.pill`: All on / All off.
struct Pill: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { PillFace(title: title) }
            .buttonStyle(PressScale(scale: 0.93))
    }
}

private struct PillFace: View {
    let title: String
    @StateObject private var hover = Hover()

    var body: some View {
        Text(title)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(hover.on ? P.text : P.muted)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(Capsule().fill(hover.on ? P.glassHi : P.glass))
            .overlay(Capsule().strokeBorder(P.line))
            .contentShape(Capsule())
            .onHover { hover.on = $0 }
            .animation(.easeOut(duration: 0.2), value: hover.on)
    }
}

/// The green dot beside "lights on", grey when nothing is.
struct LiveDot: View {
    var on: Bool
    var color: Color = P.live

    var body: some View {
        Circle()
            .fill(on ? color : Color.white.opacity(0.25))
            .frame(width: 6, height: 6)
            .shadow(color: on ? color : .clear, radius: 4)
    }
}
