import AppKit
import HouseCore
import SwiftUI
import WebKit

/// The island, drawn natively: the black shape that hangs from the notch and springs open, its
/// ears at rest, its peeks, and when open its header, scenes and devices around the 3D model
/// (the island page, in a web view the size of the model's place). Laid out as island.css.
struct IslandSurface: View {
    let model: IslandModel
    let page: NSView
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The window it is drawn in (IslandController), and the open island's size below the notch.
    static let canvas = CGSize(width: 820, height: 470)
    static let open = CGSize(width: 664, height: 292)
    /// The model's place in the open island (`.isle-main` padding 2 14 14 8, its first column 286).
    static func stage(notch: CGFloat) -> CGRect {
        CGRect(x: (canvas.width - open.width) / 2 + 8, y: notch + 2, width: 286, height: open.height - 2 - 14)
    }

    var body: some View {
        let notch = model.notchHeight
        let expanded = model.phase == .expanded
        let stage = Self.stage(notch: notch)
        ZStack(alignment: .top) {
            Glow(model: model, expanded: expanded, reduceMotion: reduceMotion, spring: spring(opening: true))
            IslandShape(model: model, reduceMotion: reduceMotion)
                .animation(spring(opening: model.phase != .collapsed), value: model.phase)
                .animation(spring(opening: true), value: model.news)
            // The model is a web view, which SwiftUI cannot clip to the growing shape: it lies on
            // top (nothing else is in its place) and only shows once the shape has grown around it
            // (IslandModel.revealSeconds).
            PageView(page: page, shown: model.revealed)
                .frame(width: stage.width, height: stage.height)
                .offset(x: stage.midX - Self.canvas.width / 2, y: stage.minY)
        }
        .frame(width: Self.canvas.width, height: Self.canvas.height, alignment: .top)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    /// Opening (or peeking) overshoots a little, closing does not: SwiftUI's own springs, which
    /// island.css samples. With Reduce Motion, no bounce.
    private func spring(opening: Bool) -> Animation {
        if reduceMotion { return .timingCurve(0.32, 0.72, 0.2, 1, duration: opening ? 0.36 : 0.28) }
        return opening ? .spring(response: 0.5, dampingFraction: 0.74) : .spring(response: 0.34, dampingFraction: 1)
    }
}

// MARK: - The shape and its ears

private struct IslandShape: View {
    let model: IslandModel
    let reduceMotion: Bool

    var body: some View {
        let home = model.home
        let lightsOn = home.lightsOn
        let ac = home.firstACOn
        let quiet = lightsOn == 0 && ac == nil
        let size: CGSize
        let radius: CGFloat
        let ear: CGFloat
        switch model.phase {
        case .expanded:
            size = CGSize(width: IslandSurface.open.width, height: model.notchHeight + IslandSurface.open.height)
            radius = 34
            ear = 64
        case .peek:
            ear = 132
            size = CGSize(width: model.notchWidth + ear * 2, height: model.notchHeight)
            radius = 16
        case .collapsed:
            // Everything off on a display without a notch: nothing to show, so nothing in the menu bar
            // (the sun alone does not bring it out there).
            ear = quiet && !model.realNotch ? 0 : model.restingEar
            size = ear == 0 ? .zero : CGSize(width: model.notchWidth + ear * 2, height: model.notchHeight)
            radius = 13
        }
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
        return shape
            .fill(.black)
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .top) {
                HStack(spacing: 0) {
                    Ear(content: left(lightsOn: lightsOn, ac: ac, quiet: quiet), mood: model.mood, leading: true)
                        .frame(width: ear, alignment: .leading)
                    Spacer(minLength: 0)
                    Ear(content: right(ac: ac, quiet: quiet), mood: model.mood, leading: false)
                        .frame(width: ear, alignment: .trailing)
                }
                .frame(width: size.width, height: model.notchHeight)
                // Only the fade has its own timing; the ears' widths follow the shape's spring.
                .animation(model.phase == .expanded ? .easeOut(duration: 0.09) : .easeOut(duration: 0.26).delay(0.2)) {
                    $0.opacity(model.phase == .expanded ? 0 : 1)
                }
            }
            // The open island's content lies inside the shape and grows out of the notch with it.
            .overlay(alignment: .top) {
                if model.phase == .expanded {
                    OpenIsland(model: model, reduceMotion: reduceMotion)
                        .frame(width: IslandSurface.open.width, height: model.notchHeight + IslandSurface.open.height, alignment: .topLeading)
                        .transition(.opacity.animation(.easeOut(duration: 0.11)))
                }
            }
            .clipShape(shape)
    }

    private func left(lightsOn: Int, ac: ACState?, quiet: Bool) -> EarContent? {
        if model.phase == .peek, let news = model.news {
            return EarContent(icon: news.icon, color: news.color, text: news.title, dimIcon: quiet, key: "news-\(news.id)")
        }
        if lightsOn > 0 { return EarContent(icon: "home", color: "#ffb46b", text: "\(lightsOn)", key: "on-\(lightsOn)") }
        if ac != nil { return EarContent(icon: "home", color: "#8fa3c7", text: nil, key: "ac") }
        if quiet, model.realNotch { return EarContent(icon: "home", color: "#8b93a7", text: nil, quiet: true, key: "off") }
        return nil
    }

    private func right(ac: ACState?, quiet: Bool) -> EarContent? {
        if model.phase == .peek, let news = model.news {
            return EarContent(icon: nil, color: "#ffffff", text: news.detail, strong: true, key: "news-\(news.id)")
        }
        switch model.rightEar {
        case .ac?:
            if let ac { return EarContent(icon: ac.mode, color: PanelColors.modes[ac.mode] ?? "#5db2ff", text: "\(Int(ac.target))°", key: "ac-\(ac.mode)-\(ac.target)") }
        case .solar(let production)?:
            // One key: a new reading changes the text, it does not pop in again.
            if !quiet || model.realNotch { return EarContent(icon: "sun", color: PanelColors.solar, text: production, key: "solar") }
        case nil:
            break
        }
        if quiet, model.realNotch { return EarContent(icon: nil, color: "#ffffff", text: "Off", quiet: true, key: "off") }
        return nil
    }
}

private struct EarContent: Equatable {
    var icon: String?
    var color: String
    var text: String?
    /// The peek's right ear: tinted by what is lit at home.
    var strong = false
    /// Everything off: dimmer, no glow.
    var quiet = false
    /// Everything off, while peeking: the icon quieter, the text as usual.
    var dimIcon = false
    let key: String
}

/// `.ear`: an icon and a short text beside the notch.
private struct Ear: View {
    let content: EarContent?
    let mood: RGB
    let leading: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let content {
                if let icon = content.icon {
                    Icon(icon, size: 14, stroke: 2.2)
                        .foregroundStyle(Color(hex: content.color))
                        .opacity(content.quiet || content.dimIcon ? 0.8 : 1)
                        .shadow(color: content.quiet || content.dimIcon ? .clear : Color(hex: content.color).opacity(0.7), radius: 2.5)
                }
                if let text = content.text {
                    Text(text)
                        .font(.system(size: 12, weight: content.quiet ? .medium : .semibold).monospacedDigit())
                        .foregroundStyle(content.quiet ? Color(red: 243 / 255, green: 245 / 255, blue: 250 / 255).opacity(0.55)
                                         : content.strong ? mood.withWhite(0.65) : Color(red: 243 / 255, green: 245 / 255, blue: 250 / 255))
                        .lineLimit(1)
                }
            }
        }
        .id(content?.key)
        .transition(.scale(scale: 0.6).combined(with: .opacity).animation(P.ease(0.36)))
        .padding(.leading, leading ? 12 : 10)
        .padding(.trailing, leading ? 10 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: leading ? .leading : .trailing)
    }
}

/// The light that spills out under the open island, tinted by what is on at home.
private struct Glow: View {
    let model: IslandModel
    let expanded: Bool
    let reduceMotion: Bool
    let spring: Animation

    var body: some View {
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: 34, bottomTrailingRadius: 34, style: .continuous)
        // Only what spills out (a box-shadow): the inside is cut away, so the shape is seen growing.
        ZStack {
            // `0 40px 110px -30px` in the mood: a blurred, smaller copy below.
            shape.fill(model.mood.color.opacity(0.85))
                .padding(.horizontal, 30).padding(.bottom, 30)
                .blur(radius: 50)
                .offset(y: 40)
            shape.fill(.black)
                .shadow(color: .black.opacity(0.75), radius: 30, y: 26)
            shape.fill(.black).blendMode(.destinationOut)
            shape.strokeBorder(Color.white.opacity(0.06))
        }
        .compositingGroup()
        .frame(width: IslandSurface.open.width, height: model.notchHeight + IslandSurface.open.height)
        .animation(expanded ? spring : .easeOut(duration: 0.14)) { $0.scaleEffect(expanded || reduceMotion ? 1 : 0.94, anchor: .top) }
        .animation(expanded ? .easeOut(duration: 0.52).delay(0.12) : .easeOut(duration: 0.14)) { $0.opacity(expanded ? 1 : 0) }
        .allowsHitTesting(false)
    }
}

// MARK: - The 3D model

/// The island page's web view, shown once the island has opened around it.
private struct PageView: NSViewRepresentable {
    let page: NSView
    let shown: Bool

    func makeNSView(context: Context) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.alphaValue = 0
        page.frame = box.bounds
        page.autoresizingMask = [.width, .height]
        box.addSubview(page)
        return box
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        /// Counts reveals, so a fade scheduled for one that was cancelled does not happen.
        var generation = 0
    }

    func updateNSView(_ box: NSView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.generation % 2 == 0 ? shown : !shown else { return }
        coordinator.generation += 1
        let generation = coordinator.generation
        if shown {
            // A few frames for the page to draw the start of its intro, not its last picture.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                guard coordinator.generation == generation else { return }
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    box.animator().alphaValue = 1
                }
            }
        } else {
            // At once: the shape closes over it, and it cannot be clipped to the shape.
            box.layer?.removeAllAnimations()
            box.alphaValue = 0
        }
    }
}

// MARK: - Open

/// The open island's header and side column, laid out in its 664-wide box (`.isle-body`).
private struct OpenIsland: View {
    let model: IslandModel
    let reduceMotion: Bool

    var body: some View {
        // `.isle-main`: padding 2 14 14 8; the model's column 286, then a 6 pt gap.
        let sideX: CGFloat = 8 + 286 + 6
        ZStack(alignment: .topLeading) {
            Head(model: model)
                .frame(width: IslandSurface.open.width, height: model.notchHeight)
                .reveal(delay: 0.06, reduceMotion: reduceMotion)
            VStack(spacing: 9) {
                if !model.home.config.scenes.isEmpty { Scenes(model: model, reduceMotion: reduceMotion) }
                Chips(model: model, reduceMotion: reduceMotion)
            }
            .frame(width: IslandSurface.open.width - 14 - sideX, height: IslandSurface.open.height - 2 - 14, alignment: .top)
            .offset(x: sideX, y: model.notchHeight + 2)
        }
    }
}

private struct Reveal: ViewModifier {
    let delay: Double
    var dy: CGFloat = -10
    var scale: CGFloat = 1
    let reduceMotion: Bool
    @StateObject private var shown = Hover()

    func body(content: Content) -> some View {
        // Opacity eases in over 320 ms; position and size come on the opening spring.
        let move: Animation = reduceMotion ? .easeOut(duration: 0.32) : .spring(response: 0.5, dampingFraction: 0.74)
        content
            .animation(.easeOut(duration: 0.32).delay(delay)) { $0.opacity(shown.on ? 1 : 0) }
            .animation(move.delay(delay)) {
                $0.offset(y: shown.on || reduceMotion ? 0 : dy).scaleEffect(shown.on || reduceMotion ? 1 : scale)
            }
            .onAppear { shown.on = true }
    }
}

private extension View {
    /// `.reveal`: each part of the open island arrives on its own, top to bottom.
    func reveal(delay: Double, dy: CGFloat = -10, scale: CGFloat = 1, reduceMotion: Bool) -> some View {
        modifier(Reveal(delay: delay, dy: dy, scale: scale, reduceMotion: reduceMotion))
    }
}

/// `.isle-head`: the home and its power on the left and right of the notch.
private struct Head: View {
    let model: IslandModel

    var body: some View {
        let home = model.home
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Icon("home", size: 14).foregroundStyle(model.mood.withWhite(0.6))
                Text(home.config.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(P.text).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: model.notchWidth)
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    LiveDot(on: home.anyOn).padding(.trailing, 2)
                    (Text(home.lightsOn > 0 ? "\(home.lightsOn) of \(home.config.lights.count)" : "No").foregroundColor(P.text).fontWeight(.semibold)
                        + Text(" lights on") + Text(home.houseTemp.map { " · " + AppModel.degrees($0) } ?? ""))
                        .lineLimit(1)
                }
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(P.muted)
                Button { model.onMenu?() } label: {
                    Icon("settings", size: 14, stroke: 2)
                        .foregroundStyle(P.muted)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                        .contentShape(Circle())
                }
                .buttonStyle(PressScale(scale: 0.88))
                .help("House Control menu")
                .accessibilityLabel("House Control menu")
                Button { home.toggleEverything() } label: {
                    Icon("power", size: 15, stroke: 2.4)
                        .foregroundStyle(home.anyOn ? .white : P.muted)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(home.anyOn
                            ? AnyShapeStyle(LinearGradient(colors: [Color(hex: "#5aa2ff"), Color(hex: "#2f7bf2")], startPoint: .top, endPoint: .bottom))
                            : AnyShapeStyle(Color.white.opacity(0.1))))
                        .shadow(color: home.anyOn ? P.accent.opacity(0.8) : .clear, radius: 7, y: 4)
                        .contentShape(Circle())
                }
                .buttonStyle(PressScale(scale: 0.88))
                .accessibilityLabel("Everything on / off")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.leading, 16).padding(.trailing, 14)
    }
}

/// `.isle-scenes`: up to five.
private struct Scenes: View {
    let model: IslandModel
    let reduceMotion: Bool

    var body: some View {
        let scenes = Array(model.home.config.scenes.prefix(5))
        HStack(spacing: 6) {
            ForEach(Array(scenes.enumerated()), id: \.element.id) { i, scene in
                Button { model.home.applyScene(scene.id) } label: {
                    SceneFace(scene: scene, active: model.home.scene == scene.id)
                }
                .buttonStyle(PressScale(scale: 0.93))
                .accessibilityLabel(scene.name)
                .reveal(delay: 0.13 + Double(i) * 0.03, dy: -12, scale: 0.9, reduceMotion: reduceMotion)
            }
        }
        .frame(height: 50)
    }
}

private struct SceneFace: View {
    let scene: HomeConfig.Scene
    let active: Bool
    @StateObject private var hover = Hover()

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        VStack(spacing: 4) {
            Icon(scene.icon, size: 17).foregroundStyle(active ? Color(hex: "#a9cbff") : hover.on ? P.text : P.muted)
            Text(scene.name).font(.system(size: 10.5, weight: .semibold)).lineLimit(1).padding(.horizontal, 4)
                .foregroundStyle(active ? .white : hover.on ? P.text : P.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if active {
                shape.fill(LinearGradient(colors: [Color(red: 88 / 255, green: 150 / 255, blue: 1).opacity(0.4),
                                                   Color(red: 61 / 255, green: 139 / 255, blue: 1).opacity(0.16)], startPoint: .top, endPoint: .bottom))
            } else {
                shape.fill(Color.white.opacity(hover.on ? 0.12 : 0.07))
            }
        }
        .overlay(shape.strokeBorder(active ? Color(red: 120 / 255, green: 175 / 255, blue: 1).opacity(0.55) : Color.white.opacity(0.06)))
        .shadow(color: active ? P.accent.opacity(0.9) : .clear, radius: 10, y: 8)
        .contentShape(shape)
        .onHover { hover.on = $0 }
        .animation(.easeOut(duration: 0.22), value: active)
    }
}

/// `.isle-list`: the Solar chip and the AC chips across, lamp chips two to a row.
private struct Chips: View {
    let model: IslandModel
    let reduceMotion: Bool

    var body: some View {
        let config = model.home.config
        let rows = stride(from: 0, to: config.lights.count, by: 2).map { Array(config.lights[$0..<min($0 + 2, config.lights.count)]) }
        // First, as in the panel's list.
        let first = config.energy == nil ? 0 : 1
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 6) {
                if let energy = config.energy {
                    EnergyChip(model: model, cfg: energy).reveal(delay: 0.19, reduceMotion: reduceMotion)
                }
                ForEach(Array(config.acs.enumerated()), id: \.element.id) { i, ac in
                    ACChip(model: model, cfg: ac).reveal(delay: 0.19 + Double(min(first + i, 9)) * 0.024, reduceMotion: reduceMotion)
                }
                ForEach(Array(rows.enumerated()), id: \.element.first!.id) { r, row in
                    HStack(spacing: 6) {
                        ForEach(Array(row.enumerated()), id: \.element.id) { c, light in
                            let i = first + config.acs.count + r * 2 + c
                            LightChip(model: model, cfg: light).reveal(delay: 0.19 + Double(min(i, 9)) * 0.024, reduceMotion: reduceMotion)
                        }
                        if row.count == 1 { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                    }
                }
            }
            .padding(.bottom, 14)
        }
        .padding(.bottom, -14)
        .mask {
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 26)
            }
        }
    }
}

private struct ChipFace<Content: View>: View {
    let on: Bool
    let color: RGB
    @ViewBuilder var content: Content
    @StateObject private var hover = Hover()

    var body: some View {
        let c = color.color
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        content
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
            .background {
                if on {
                    shape.fill(LinearGradient(colors: [c.opacity(0.3), c.opacity(0.09)], startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    shape.fill(Color.white.opacity(hover.on ? 0.12 : 0.07))
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(on ? c.opacity(0.44) : Color.white.opacity(0.06)))
            .shadow(color: on ? c.opacity(0.45) : .clear, radius: 8, y: 10)
            .contentShape(shape)
            .onHover { hover.on = $0 }
            .animation(.easeOut(duration: 0.24), value: on)
    }
}

private struct ChipText: View {
    let name: String
    let sub: String
    let on: Bool
    let color: RGB

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name).font(.system(size: 12, weight: .semibold)).foregroundStyle(P.text).lineLimit(1)
            Text(sub).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(on ? color.withWhite(0.45) : P.muted).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Bubble: View {
    let icon: String
    let on: Bool
    let color: RGB
    let ink: Color

    var body: some View {
        Icon(icon, size: 15)
            .foregroundStyle(on ? ink : P.muted)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? color.color : Color.white.opacity(0.08)))
            .shadow(color: on ? color.color : .clear, radius: 8)
    }
}

private struct ACChip: View {
    let model: IslandModel
    let cfg: HomeConfig.AC

    var body: some View {
        let home = model.home
        let s = home.ac(cfg.id)
        let rgb = PanelColors.mode(s.mode)
        ChipFace(on: s.on, color: rgb) {
            HStack(spacing: 6) {
                Bubble(icon: s.mode, on: s.on, color: rgb, ink: Color(red: 6 / 255, green: 22 / 255, blue: 44 / 255))
                ChipText(name: cfg.name, sub: "\(s.on ? PanelColors.modeLabel[s.mode] ?? s.mode : "Off") · \(Int(s.roomTemp.rounded()))° inside", on: s.on, color: rgb)
                ChipButton(icon: "minus", label: "Cooler") { home.setAC(cfg.id, ["on": true, "target": s.target - 1]) }
                Text("\(Int(s.target))°").font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(s.on ? P.text : P.faint).frame(minWidth: 30)
                ChipButton(icon: "plus", label: "Warmer") { home.setAC(cfg.id, ["on": true, "target": s.target + 1]) }
                Button { home.setAC(cfg.id, ["on": !s.on]) } label: {
                    Icon("power", size: 13, stroke: 2.4)
                        .foregroundStyle(s.on ? Color(red: 6 / 255, green: 22 / 255, blue: 44 / 255) : P.muted)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(s.on ? rgb.color : Color.white.opacity(0.1)))
                        .shadow(color: s.on ? rgb.color : .clear, radius: 7)
                        .contentShape(Circle())
                }
                .buttonStyle(PressScale(scale: 0.86))
                .padding(.leading, 2)
                .accessibilityLabel("\(cfg.name) power")
            }
        }
    }
}

/// Solar production and the battery's charge, read-only, as on the panel's Solar tile; a click
/// opens its sheet.
private struct EnergyChip: View {
    let model: IslandModel
    let cfg: HomeConfig.Energy

    var body: some View {
        let s = model.home.energy
        let on = (s.solar ?? 0) >= EnergyState.idleWatts
        let rgb = RGB(PanelColors.solar)
        ChipFace(on: on, color: rgb) {
            HStack(spacing: 6) {
                Bubble(icon: cfg.hasSolar ? "sun" : "battery", on: on, color: rgb, ink: Color(red: 36 / 255, green: 21 / 255, blue: 3 / 255))
                ChipText(name: cfg.name, sub: cfg.status(s), on: on, color: rgb)
            }
        }
        .overlay {
            // The battery's charge along the bottom edge, as on the tile, kept inside the chip's corners.
            Rectangle().fill(Color(hex: PanelColors.charge(s.charge)))
                .frame(height: 2.5)
                .scaleEffect(x: (s.charge ?? 0) / 100, anchor: .leading)
                .opacity(cfg.hasBattery && s.charge != nil ? 0.9 : 0)
                .animation(P.ease(0.26), value: s.charge)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .allowsHitTesting(false)
        }
        .onTapGesture { model.onOpen?("energy") }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cfg.name)
        .accessibilityValue(cfg.status(s))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.onOpen?("energy") }
    }
}

private struct ChipButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    @StateObject private var hover = Hover()

    var body: some View {
        Button(action: action) {
            Icon(icon, size: 13, stroke: 2.4)
                .foregroundStyle(hover.on ? P.text : P.muted)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hover.on ? Color.white.opacity(0.14) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScale(scale: 0.86))
        .onHover { hover.on = $0 }
        .accessibilityLabel(label)
    }
}

private struct LightChip: View {
    let model: IslandModel
    let cfg: HomeConfig.Light
    @StateObject private var drag = TileDrag()

    var body: some View {
        let home = model.home
        let s = home.light(cfg.id)
        let rgb = PanelColors.light(s)
        GeometryReader { geo in
            ChipFace(on: s.on, color: rgb) {
                HStack(spacing: 8) {
                    Bubble(icon: cfg.icon, on: s.on, color: rgb, ink: Color(red: 36 / 255, green: 21 / 255, blue: 3 / 255))
                    ChipText(name: cfg.name, sub: "\(s.status(cfg)) · \(home.groupName(cfg.room))", on: s.on, color: rgb)
                }
            }
            .overlay {
                Rectangle().fill(rgb.color)
                    .frame(width: geo.size.width * (s.on ? s.brightness : 0), height: 2.5)
                    .opacity(s.on && cfg.dimmable ? 0.9 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .allowsHitTesting(false)
            }
            .scaleEffect(drag.pressed && !drag.dragging ? 0.96 : 1)
            .animation(P.spring, value: drag.pressed)
            .hoverCursor(cfg.dimmable ? .resizeLeftRight : .arrow)
            // Click toggles, dragging sideways dims: the same gesture as the panel's tiles.
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !drag.pressed {
                        drag.pressed = true
                        drag.start = s.on ? s.brightness : 0
                    }
                    if !drag.dragging, cfg.dimmable, abs(value.translation.width) > 5 { drag.dragging = true }
                    guard drag.dragging, geo.size.width > 0 else { return }
                    let b = min(1, max(0, drag.start + value.translation.width / geo.size.width))
                    home.setLight(cfg.id, b < 0.04 ? ["on": false] : ["on": true, "brightness": b])
                }
                .onEnded { _ in
                    let tapped = !drag.dragging
                    drag.pressed = false
                    drag.dragging = false
                    if tapped {
                        model.onBump?(cfg.id)
                        home.toggleLight(cfg.id, bump: false) // the island's own model nods, not the panel's
                    }
                })
            .onDisappear { drag.pressed = false; drag.dragging = false }
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { home.toggleLight(cfg.id) }
    }
}

/// A hosting view that takes the first click: the island's window never becomes key.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
