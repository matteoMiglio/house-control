import Foundation
import Observation
import HouseCore

/// The island's state: at rest, peeking out to say what changed elsewhere, or open. Reads the
/// home from `HomeModel`; the counterpart of web/src/island/island.js.
@MainActor
@Observable
final class IslandModel {
    enum Phase: Equatable { case collapsed, peek, expanded }

    /// What a peek says: on the left an icon and a name, on the right what happened.
    struct News: Equatable {
        let id = UUID()
        let icon: String
        /// "#rrggbb" for the icon's tint.
        let color: String
        let title: String
        let detail: String
        /// Made by an AI assistant: it wears sparkles instead of the device's icon.
        let ai: Bool
    }

    static let peekSeconds = 2.4

    let home: HomeModel
    private(set) var phase: Phase = .collapsed
    private(set) var news: News?
    /// The notch it hangs from, in points, and whether the display really has one.
    var notchWidth: CGFloat = 190
    var notchHeight: CGFloat = 34
    var realNotch = false

    /// The 3D model shows: once the opening shape has grown around it (it would show outside).
    private(set) var revealed = false
    /// Told when the model is revealed (the page then plays its intro) or the island closes.
    @ObservationIgnored var onReveal: ((Bool) -> Void)?
    /// The gear: the app's menu (the island stands in for the menu bar icon).
    @ObservationIgnored var onMenu: (() -> Void)?
    /// A chip toggled a lamp: the lamp in the island's model nods.
    @ObservationIgnored var onBump: ((String) -> Void)?
    @ObservationIgnored private var before: Snapshot?
    @ObservationIgnored private var revealTimer: Task<Void, Never>?
    /// How long the opening spring takes to cover the model's place.
    static let revealSeconds = 0.35
    @ObservationIgnored private var peekTimer: Task<Void, Never>?

    init(home: HomeModel) {
        self.home = home
    }

    /// A new plan: the next change is compared with how it starts.
    func reset() { before = Snapshot(lights: home.lights, acs: home.acs, scene: home.scene) }

    // MARK: - Phases

    func setExpanded(_ open: Bool) {
        revealTimer?.cancel()
        if open {
            peekTimer?.cancel()
            news = nil
            phase = .expanded
            revealTimer = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.revealSeconds * 1_000_000_000))
                guard !Task.isCancelled, let self, self.phase == .expanded else { return }
                self.revealed = true
                self.onReveal?(true)
            }
        } else if phase == .expanded {
            phase = .collapsed
            if revealed {
                revealed = false
                onReveal?(false)
            }
        }
    }

    // MARK: - News

    /// What the lamps, ACs and scene were at the last look, to tell what changed.
    private struct Snapshot {
        var lights: [String: LightState]
        var acs: [String: ACState]
        var scene: String?
    }

    /// The home changed (once per turn of the run loop; `tick`: only a simulated room
    /// temperature moved). While the island is closed every change was made elsewhere, so it
    /// says what happened (`source` says who, when it was not the person at a screen).
    func homeChanged(tick: Bool, source: String?) {
        let now = Snapshot(lights: home.lights, acs: home.acs, scene: home.scene)
        defer { before = now }
        guard !tick, let before, phase != .expanded, let next = describe(before, now, source: source) else { return }
        news = next
        phase = .peek
        peekTimer?.cancel()
        peekTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.peekSeconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.news = nil
            if self.phase == .peek { self.phase = .collapsed }
        }
    }

    /// island.js `describe()`: a scene, one AC, one lamp, or several things at once.
    private func describe(_ was: Snapshot, _ now: Snapshot, source: String?) -> News? {
        let ai = source != nil
        func news(_ icon: String, _ color: String, _ title: String, _ detail: String) -> News {
            News(icon: ai ? "sparkles" : icon, color: ai ? "#c3b2ff" : color, title: title, detail: detail, ai: ai)
        }
        let config = home.config
        if let scene = now.scene, scene != was.scene, let s = config.scenes.first(where: { $0.id == scene }) {
            return news(s.icon, "#a9cbff", s.name, "Scene")
        }
        let lights = config.lights.filter { l in
            guard let a = was.lights[l.id], let b = now.lights[l.id] else { return false }
            return a.on != b.on || abs(a.brightness - b.brightness) > 0.02 || a.color != b.color
        }
        let acs = config.acs.filter { c in
            guard let a = was.acs[c.id], let b = now.acs[c.id] else { return false }
            return a.on != b.on || a.target != b.target || a.mode != b.mode
        }
        if acs.count == 1, lights.isEmpty, let cfg = acs.first, let s = now.acs[cfg.id] {
            return news(s.mode, s.on ? PanelColors.modes[s.mode] ?? "#5db2ff" : "#8fa3c7", cfg.name, s.on ? "\(Int(s.target))°" : "Off")
        }
        if lights.count == 1, acs.isEmpty, let cfg = lights.first, let s = now.lights[cfg.id] {
            return news(cfg.icon, s.on ? PanelColors.light(s).hex : "#8fa3c7", cfg.name, s.status(cfg))
        }
        if lights.count + acs.count > 1 {
            let on = now.lights.values.filter(\.on).count
            return news("home", on > 0 ? "#ffb46b" : "#8fa3c7", config.name, on > 0 ? "\(on) on" : "All off")
        }
        return nil
    }

    // MARK: - Mood

    /// The colour of what is lit at home, for the open island's glow (island.js `mood()`).
    var mood: RGB {
        let navy = RGB("#17274f")
        var sum = RGB(r: 0, g: 0, b: 0)
        var weight = 0.0
        for cfg in home.config.lights {
            let s = home.light(cfg.id)
            guard s.on else { continue }
            let w = cfg.dimmable ? s.brightness : 1
            let c = PanelColors.light(s)
            sum = RGB(r: sum.r + c.r * w, g: sum.g + c.g * w, b: sum.b + c.b * w)
            weight += w
        }
        guard weight > 0 else { return navy }
        return navy.lerp(sum.scaled(0.6 / weight), min(0.9, max(0.35, weight / 3)))
    }
}
