import Foundation
import HouseCore
import SwiftUI

/// A colour in linear light, the way three.js mixes them (web/src/three/lights.js, panel.js):
/// a mix made here comes out as the same pixel as on the web.
struct RGB: Equatable {
    var r, g, b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// From "#rrggbb" (sRGB).
    init(_ hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v)
        func linear(_ c: UInt64) -> Double {
            let s = Double(c) / 255
            return s < 0.04045 ? s * 0.0773993808 : pow(s * 0.9478672986 + 0.0521327014, 2.4)
        }
        r = linear((v >> 16) & 0xff)
        g = linear((v >> 8) & 0xff)
        b = linear(v & 0xff)
    }

    func lerp(_ to: RGB, _ t: Double) -> RGB {
        RGB(r: r + (to.r - r) * t, g: g + (to.g - g) * t, b: b + (to.b - b) * t)
    }

    func scaled(_ k: Double) -> RGB { RGB(r: r * k, g: g * k, b: b * k) }

    var color: Color { Color(.sRGB, red: Self.srgb(r), green: Self.srgb(g), blue: Self.srgb(b)) }

    /// "#rrggbb" (sRGB), as three.js `getHexString` gives it.
    var hex: String {
        func byte(_ c: Double) -> Int { Int((Self.srgb(c) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(r), byte(g), byte(b))
    }

    /// CSS `color-mix(in srgb, <this> (1 - t), #fff t)`: how a lit tile tints its status text.
    func withWhite(_ t: Double) -> Color {
        func mix(_ c: Double) -> Double { Self.srgb(c) * (1 - t) + t }
        return Color(.sRGB, red: mix(r), green: mix(g), blue: mix(b))
    }

    private static func srgb(_ c: Double) -> Double {
        let c = Swift.min(1, Swift.max(0, c))
        return c < 0.0031308 ? c * 12.92 : 1.055 * pow(c, 0.41666) - 0.055
    }
}

enum PanelColors {
    static let modes: [String: String] = ["cool": "#5db2ff", "heat": "#ff8c3a", "dry": "#62e0cf", "fan": "#cfdcff", "auto": "#9bd28a"]
    static let modeLabel = ["cool": "Cool", "heat": "Heat", "dry": "Dry", "fan": "Fan", "auto": "Auto"]
    static let fanLabel = ["auto": "Auto", "low": "Low", "medium": "Medium", "high": "High", "turbo": "Turbo"]
    static let swingLabel = ["swing": "Swing", "l1": "L1", "l2": "L2", "l3": "L3", "l4": "L4", "l5": "L5", "off": "Off"]
    static let swings = ["swing", "l1", "l2", "l3", "l4", "l5", "off"]
    static let swatches = ["#ff5a4f", "#ff9a3c", "#ffd84a", "#5fe08a", "#42d6e8", "#4f8dff", "#8b5cff", "#ff5fc4"]

    static func mode(_ mode: String) -> RGB { RGB(modes[mode] ?? modes["cool"]!) }

    /// The colour of power by where it comes from (three/energy.js `FLOW_COLORS`).
    static let solar = "#ffc24a"
    static let battery = "#4fe0b0"
    static let grid = "#6aa6ff"
    /// What the house uses, warm like a lamp.
    static let house = "#ffd9a0"

    /// A battery's charge as its front shows it: green, amber when low, red when nearly empty
    /// (three/energy.js `chargeColor`).
    static func charge(_ c: Double?) -> String {
        guard let c else { return battery }
        return c < 15 ? "#ff6b5a" : c < 35 ? solar : battery
    }

    /// tempToColor() in lights.js: the same stops, mixed the same way.
    static func temperature(_ kelvin: Double) -> RGB {
        let stops: [(Double, String)] = [(2200, "#ff9438"), (3000, "#ffbd7a"), (4200, "#ffe2c2"), (6500, "#dfe9ff")]
        let k = min(6500, max(2200, kelvin))
        for i in 0..<(stops.count - 1) where k <= stops[i + 1].0 {
            let (k0, c0) = stops[i], (k1, c1) = stops[i + 1]
            return RGB(c0).lerp(RGB(c1), (k - k0) / (k1 - k0))
        }
        return RGB(stops.last!.1)
    }

    /// What colour a lamp shines in: its colour, or its white.
    static func light(_ s: LightState) -> RGB { s.color.map { RGB($0) } ?? temperature(s.temp) }
}
