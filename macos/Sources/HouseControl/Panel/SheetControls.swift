import Combine
import SwiftUI

// The controls of the detail sheets, drawn as web/src/style.css draws them (.slider, .pad,
// .swatch, .toggle-chip, .big, .option, .menu).

enum Gradients {
    static func stops(_ list: [(String, Double)]) -> Gradient {
        Gradient(stops: list.map { Gradient.Stop(color: Color(hex: $0.0), location: $0.1) })
    }
    /// An AC's set-point, cold to warm.
    static let temperature = stops([("#2f7df6", 0), ("#58b4f5", 0.34), ("#f3e2c0", 0.62), ("#f6a54a", 0.82), ("#f0762c", 1)])
    static let dim = stops([("#4a4f5e", 0), ("#b9a98c", 0.45), ("#ffe2b0", 1)])
    static let kelvin = stops([("#ff9438", 0), ("#ffbd7a", 0.3), ("#ffe2c2", 0.62), ("#dfe9ff", 1)])
}

/// The value shown while a slider is dragged, ahead of the state that follows it.
final class SliderDrag: ObservableObject {
    @Published var value: Double?
}

/// `.slider`: a gradient track with a square white thumb, dragged or clicked anywhere.
struct GradientSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let gradient: Gradient
    var compact = false
    var labels: (String, String)?
    let onChange: (Double) -> Void
    @StateObject private var drag = SliderDrag()

    var body: some View {
        let size: CGFloat = compact ? 38 : 46
        let shown = drag.value ?? value
        let p = CGFloat(min(1, max(0, (shown - range.lowerBound) / (range.upperBound - range.lowerBound))))
        VStack(spacing: 7) {
            GeometryReader { geo in
                let w = geo.size.width
                let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
                ZStack(alignment: .leading) {
                    shape.fill(Color.black.opacity(0.36))
                    Ticks().stroke(Color.white.opacity(0.13), lineWidth: 1).frame(height: 9)
                    // The fill shows as much of the full-width gradient as the thumb has passed.
                    LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing)
                        .frame(width: w)
                        .mask(alignment: .leading) { shape.frame(width: p * (w - size) + size) }
                    shape.strokeBorder(Color.white.opacity(0.05))
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(.white)
                        .overlay(RoundedRectangle(cornerRadius: 2).fill(P.bg.opacity(0.18)).frame(width: 4, height: size - 30))
                        .frame(width: size, height: size)
                        .shadow(color: .black.opacity(drag.value == nil ? 0.4 : 0.45), radius: drag.value == nil ? 7 : 9, y: 4)
                        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(Color(red: 90 / 255, green: 160 / 255, blue: 1).opacity(drag.value == nil ? 0 : 0.75), lineWidth: 3)
                            .padding(-3))
                        .scaleEffect(drag.value == nil ? 1 : 1.06)
                        .offset(x: p * (w - size))
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let q = min(1, max(0, (g.location.x - size / 2) / max(1, w - size)))
                        let raw = range.lowerBound + Double(q) * (range.upperBound - range.lowerBound)
                        let next = min(range.upperBound, max(range.lowerBound, (raw / step).rounded() * step))
                        if next != drag.value { drag.value = next; onChange(next) }
                    }
                    .onEnded { _ in drag.value = nil })
                .hoverCursor(.openHand)
                .animation(drag.value == nil ? P.ease(0.32) : nil, value: p)
                .animation(P.spring, value: drag.value == nil)
            }
            .frame(height: size)
            if let labels {
                HStack {
                    Text(labels.0)
                    Spacer()
                    Text(labels.1)
                }
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(P.muted)
                .padding(.horizontal, 4)
            }
        }
        .accessibilityElement()
        .accessibilityValue("\(Int(shown))")
        .accessibilityAdjustableAction { direction in
            let next = direction == .increment ? value + step : value - step
            onChange(min(range.upperBound, max(range.lowerBound, next)))
        }
    }
}

/// The faint marks along a slider's track, fourteen to its length.
private struct Ticks: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for i in 1..<14 {
            let x = rect.width * CGFloat(i) / 14 - 0.5
            p.move(to: CGPoint(x: x, y: rect.minY))
            p.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        return p
    }
}

/// Where the pointer is on the colour pad while it is dragged.
final class PadDrag: ObservableObject {
    @Published var spot: CGPoint?
}

/// `.pad`: hue left to right, paler towards the bottom; brightness belongs to its own slider.
struct ColorPad: View {
    let color: String?
    let onChange: (String) -> Void
    @StateObject private var drag = PadDrag()

    static let minSaturation = 0.12

    var body: some View {
        GeometryReader { geo in
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            let spot = drag.spot ?? color.flatMap(Self.position)
            ZStack(alignment: .topLeading) {
                shape.fill(LinearGradient(colors: [0, 60, 120, 180, 240, 300, 360].map { Color(hue: Double($0) / 360, saturation: 1, brightness: 1) },
                                          startPoint: .leading, endPoint: .trailing))
                shape.fill(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.88)], startPoint: .top, endPoint: .bottom))
                shape.strokeBorder(Color.white.opacity(0.1))
                if let spot {
                    Circle()
                        .fill(Color(hex: Self.hex(hue: spot.x * 360, saturation: 1 - spot.y * (1 - Self.minSaturation))))
                        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                        .frame(width: 24, height: 24)
                        .shadow(color: .black.opacity(0.5), radius: 5, y: 3)
                        .scaleEffect(drag.spot == nil ? 1 : 1.25)
                        .position(x: spot.x * geo.size.width, y: spot.y * geo.size.height)
                        .animation(drag.spot == nil ? P.ease(0.26) : nil, value: spot)
                }
            }
            .contentShape(shape)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let x = min(1, max(0, g.location.x / geo.size.width)), y = min(1, max(0, g.location.y / geo.size.height))
                    drag.spot = CGPoint(x: x, y: y)
                    onChange(Self.hex(hue: min(359.9, x * 360), saturation: 1 - y * (1 - Self.minSaturation)))
                }
                .onEnded { _ in drag.spot = nil })
            .hoverCursor(.crosshair)
        }
        .frame(minHeight: 64, maxHeight: 120)
        .accessibilityLabel("Colour")
    }

    /// Where a colour sits on the pad (nil: not a colour).
    static func position(_ hex: String) -> CGPoint? {
        var v: UInt64 = 0
        guard Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v) else { return nil }
        let r = Double((v >> 16) & 255) / 255, g = Double((v >> 8) & 255) / 255, b = Double(v & 255) / 255
        let mx = max(r, g, b), d = mx - min(r, g, b)
        var hue = 0.0
        if d > 0 {
            if mx == r { hue = ((g - b) / d).truncatingRemainder(dividingBy: 6) } else if mx == g { hue = (b - r) / d + 2 } else { hue = (r - g) / d + 4 }
            hue = (hue * 60 + 360).truncatingRemainder(dividingBy: 360)
        }
        let s = mx == 0 ? 0 : d / mx
        return CGPoint(x: hue / 360, y: min(1, max(0, (1 - s) / (1 - minSaturation))))
    }

    /// hsvToHex() in dom.js, at full value.
    static func hex(hue: Double, saturation s: Double) -> String {
        func f(_ k: Double) -> String {
            let x = (k + hue / 60).truncatingRemainder(dividingBy: 6)
            let c = Int(((1 - s * max(0, min(x, 4 - x, 1))) * 255).rounded())
            return String(format: "%02x", c)
        }
        return "#\(f(5))\(f(3))\(f(1))"
    }
}
