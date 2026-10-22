import Combine
import HouseCore
import SwiftUI

/// Scenes, room tabs and the device tiles: the panel below (or beside) the 3D model.
struct DeviceList: View {
    let model: HomeModel

    var body: some View {
        VStack(spacing: 0) {
            if !model.config.scenes.isEmpty { SceneStrip(model: model) }
            RoomTabs(model: model).padding(.top, 12)
            ListHead(model: model).padding(.top, 12).padding(.bottom, 8).padding(.horizontal, 4)
            DeviceGrid(model: model)
        }
    }
}

// MARK: - Scenes

private struct SceneStrip: View {
    let model: HomeModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(model.config.scenes) { scene in
                Button { model.applyScene(scene.id) } label: {
                    SceneFace(scene: scene, active: model.scene == scene.id)
                }
                .buttonStyle(PressScale(scale: 0.94))
                .accessibilityLabel(scene.name)
                .accessibilityAddTraits(model.scene == scene.id ? .isSelected : [])
            }
        }
    }
}

private struct SceneFace: View {
    let scene: HomeConfig.Scene
    let active: Bool
    @StateObject private var hover = Hover()

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(spacing: 6) {
            Icon(scene.icon, size: 19).foregroundStyle(active ? Color(hex: "#a9cbff") : hover.on ? P.text : P.muted)
            Text(scene.name).font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(active ? .white : hover.on ? P.text : P.muted)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 62)
        .background {
            if active {
                shape.fill(LinearGradient(colors: [Color(red: 88 / 255, green: 150 / 255, blue: 1).opacity(0.34),
                                                   Color(red: 61 / 255, green: 139 / 255, blue: 1).opacity(0.14)],
                                          startPoint: .top, endPoint: .bottom))
            } else {
                shape.fill(hover.on ? P.glassHi : P.glass)
            }
        }
        .overlay(shape.strokeBorder(active ? Color(red: 120 / 255, green: 175 / 255, blue: 1).opacity(0.55) : P.line))
        .shadow(color: active ? P.accent.opacity(0.8) : .clear, radius: 12, y: 10)
        .contentShape(shape)
        .onHover { hover.on = $0 }
        .animation(.easeOut(duration: 0.22), value: active)
        .animation(.easeOut(duration: 0.22), value: hover.on)
    }
}

// MARK: - Rooms

private struct RoomTabs: View {
    let model: HomeModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    tab(id: "all", name: "All")
                    ForEach(model.config.groups) { tab(id: $0.id, name: $0.name) }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)
            .onChange(of: model.room) { _, room in
                withAnimation(P.ease(0.4)) { proxy.scrollTo(room, anchor: .center) }
            }
        }
    }

    private func tab(id: String, name: String) -> some View {
        Button { model.selectRoom(id) } label: {
            RoomFace(name: name, count: id == "all" ? 0 : model.onCount(in: id), active: model.room == id)
        }
        .buttonStyle(PressScale(scale: 0.95))
        .id(id)
        .accessibilityAddTraits(model.room == id ? .isSelected : [])
    }
}

private struct RoomFace: View {
    let name: String
    let count: Int
    let active: Bool
    @StateObject private var hover = Hover()

    var body: some View {
        HStack(spacing: 7) {
            Text(name).font(.system(size: 12.5, weight: .semibold))
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color(red: 42 / 255, green: 26 / 255, blue: 5 / 255))
                    .padding(.horizontal, 5)
                    .frame(minWidth: 17, minHeight: 17)
                    .background(Capsule().fill(P.warm))
                    .shadow(color: P.warm, radius: 5)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .foregroundStyle(active || hover.on ? P.text : P.muted)
        .padding(.horizontal, 13)
        .frame(height: 32)
        .background(Capsule().fill(active ? P.glassHi : hover.on ? P.glass : .clear))
        .overlay(Capsule().strokeBorder(active ? P.line : .clear))
        .contentShape(Capsule())
        .onHover { hover.on = $0 }
        .animation(P.spring, value: count)
        .animation(.easeOut(duration: 0.22), value: active)
    }
}

// MARK: - List head

private struct ListHead: View {
    let model: HomeModel

    var body: some View {
        let scoped = model.config.lights.filter { model.inScope($0.room) }
        let on = scoped.filter { model.light($0.id).on }.count
        HStack(spacing: 8) {
            (Text(model.room == "all" ? "Whole home" : model.groupName(model.room)).foregroundColor(P.text).fontWeight(.semibold)
                + Text(" · \(on) of \(scoped.count) on"))
                .font(.system(size: 12))
                .foregroundStyle(P.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            Pill(title: "All on") { model.bulk(true) }
            Pill(title: "All off") { model.bulk(false) }
        }
    }
}

// MARK: - Tiles

private struct DeviceGrid: View {
    let model: HomeModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                let shown = model.config.groups.filter { model.room == "all" || $0.id == model.room }
                let any = shown.contains { g in model.config.lights.contains { $0.room == g.id } || model.config.acs.contains { $0.room == g.id } }
                if !any, !model.energyShown { GroupLabel(text: "No devices in this room yet") }
                // In the whole home, first under its own heading; in a room, in the one the battery stands in.
                if model.energyShown, let energy = model.config.energy {
                    if model.room == "all" { GroupLabel(text: "Energy") }
                    EnergyTile(model: model, cfg: energy)
                }
                ForEach(shown) { group in
                    let acs = model.config.acs.filter { $0.room == group.id }
                    let lights = model.config.lights.filter { $0.room == group.id }
                    if !acs.isEmpty || !lights.isEmpty {
                        if model.room == "all" {
                            GroupLabel(text: group.name).padding(.top, group.id == shown.first?.id && !model.energyShown ? 0 : 8)
                        }
                        ForEach(acs) { ACTile(model: model, cfg: $0) }
                        TilePairs(model: model, lights: lights)
                    }
                }
            }
            .padding(.top, 2)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .id(model.room) // a new list for each room, which plays the tiles' entrance again
            .transition(.opacity.combined(with: .offset(y: 10)))
        }
        .padding(.horizontal, -16)
        .mask {
            // The list fades out at its top and bottom edges as it scrolls.
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 10)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 22)
            }
        }
        .animation(P.ease(0.48), value: model.room)
    }
}

private struct GroupLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .bold))
            .kerning(0.95)
            .foregroundStyle(P.faint)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Lamps two to a row.
private struct TilePairs: View {
    let model: HomeModel
    let lights: [HomeConfig.Light]

    var body: some View {
        let rows = stride(from: 0, to: lights.count, by: 2).map { Array(lights[$0..<min($0 + 2, lights.count)]) }
        ForEach(rows, id: \.first!.id) { row in
            HStack(spacing: 8) {
                ForEach(row) { LightTile(model: model, cfg: $0) }
                if row.count == 1 { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
            }
        }
    }
}

/// Where a drag across a lamp tile started, and whether it became a dim (vs. a click).
final class TileDrag: ObservableObject {
    @Published var pressed = false
    @Published var dragging = false
    var start = 0.0
    var step = -1
}

struct LightTile: View {
    let model: HomeModel
    let cfg: HomeConfig.Light
    @StateObject private var hover = Hover()
    @StateObject private var drag = TileDrag()

    private var dimmable: Bool { cfg.dimmable }

    var body: some View {
        let s = model.light(cfg.id)
        let rgb = PanelColors.light(s)
        let c = rgb.color
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        GeometryReader { geo in
            HStack(spacing: 11) {
                Icon(cfg.icon, size: 19)
                    .foregroundStyle(s.on ? Color(red: 36 / 255, green: 21 / 255, blue: 3 / 255) : P.muted)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(s.on ? c : Color.white.opacity(0.07)))
                    .shadow(color: s.on ? c : .clear, radius: 11)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cfg.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(P.text).lineLimit(1)
                    Text(model.room == "all" ? "\(s.status(cfg)) · \(model.groupName(cfg.room))" : s.status(cfg))
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(s.on ? rgb.withWhite(0.45) : P.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if cfg.hasSheet {
                    MoreButton(visible: hover.on) { model.openSheet(.light(cfg.id)) }
                        .accessibilityLabel("\(cfg.name) settings")
                }
            }
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
            .background {
                if s.on {
                    shape.fill(LinearGradient(colors: [c.opacity(0.26), c.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    shape.fill(hover.on ? P.glassHi : P.glass)
                }
            }
            .overlay(alignment: .bottomLeading) {
                // How bright it is, along the bottom edge.
                Rectangle().fill(c)
                    .frame(width: geo.size.width * (s.on ? s.brightness : 0), height: drag.dragging ? 4 : 3)
                    .opacity(s.on && dimmable ? 0.9 : 0)
                    .animation(drag.dragging ? nil : P.ease(0.26), value: s.brightness)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(s.on ? c.opacity(0.42) : P.line))
            .shadow(color: s.on ? c.opacity(0.5) : .clear, radius: 10, y: 12)
            .scaleEffect(drag.pressed && !drag.dragging ? 0.96 : 1)
            .contentShape(shape)
            .onHover { hover.on = $0 }
            .hoverCursor(dimmable ? .resizeLeftRight : .arrow)
            .gesture(press(width: geo.size.width))
            .animation(P.spring, value: drag.pressed)
            .animation(.easeOut(duration: 0.26), value: s.on)
        }
        .frame(height: 68)
        .frame(maxWidth: .infinity)
        // Gone mid-press (the room changed, the panel closed): not left pressed for next time.
        .onDisappear { drag.pressed = false; drag.dragging = false }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cfg.name)
        .accessibilityValue(model.light(cfg.id).status(cfg))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.toggleLight(cfg.id) }
    }

    /// A click toggles; a sideways drag dims (HomeKit-style), a mostly vertical one is left to the list.
    private func press(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !drag.pressed {
                    drag.pressed = true
                    let s = model.light(cfg.id)
                    drag.start = s.on ? s.brightness : 0
                    drag.step = -1
                }
                let dx = value.translation.width, dy = value.translation.height
                if !drag.dragging, dimmable, abs(dx) > 6, abs(dx) > abs(dy) { drag.dragging = true }
                guard drag.dragging, width > 0 else { return }
                let b = min(1, max(0, drag.start + dx / width))
                let step = Int((b * 20).rounded())
                guard step != drag.step else { return }
                drag.step = step
                model.setLight(cfg.id, b < 0.04 ? ["on": false] : ["on": true, "brightness": b])
            }
            .onEnded { value in
                let moved = drag.dragging || hypot(value.translation.width, value.translation.height) > 8
                drag.pressed = false
                drag.dragging = false
                if !moved { model.toggleLight(cfg.id) }
            }
    }
}

/// The sliders button on a lamp tile, shown while the pointer is over it.
private struct MoreButton: View {
    let visible: Bool
    let action: () -> Void
    @StateObject private var hover = Hover()

    var body: some View {
        // Its own click, ahead of the tile's: opening the sheet must not also toggle the lamp.
        Icon("sliders", size: 15)
            .foregroundStyle(hover.on ? P.text : P.faint)
            .frame(width: 26, height: 26)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hover.on ? Color.white.opacity(0.12) : .clear))
            .contentShape(Rectangle())
            .highPriorityGesture(TapGesture().onEnded(action))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
        .padding(.trailing, -4)
        .opacity(visible ? 1 : 0)
        .onHover { hover.on = $0 }
        .animation(.easeOut(duration: 0.18), value: visible)
    }
}

struct ACTile: View {
    let model: HomeModel
    let cfg: HomeConfig.AC
    @StateObject private var hover = Hover()

    var body: some View {
        let s = model.ac(cfg.id)
        let rgb = PanelColors.mode(s.mode)
        let c = rgb.color
        // On but not running: outlined in the mode's colour instead of lit with it.
        let lit = s.on && !s.idle
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        let bubble = RoundedRectangle(cornerRadius: 13, style: .continuous)
        HStack(spacing: 11) {
            Icon(s.mode, size: 19)
                .foregroundStyle(lit ? Color(red: 6 / 255, green: 22 / 255, blue: 44 / 255) : s.on ? c : P.muted)
                .frame(width: 38, height: 38)
                .background(bubble.fill(lit ? c : s.on ? .clear : Color.white.opacity(0.07)))
                .overlay(bubble.strokeBorder(s.idle && s.on ? c.opacity(0.7) : .clear, lineWidth: 1.5))
                .shadow(color: lit ? c : .clear, radius: 11)
            VStack(alignment: .leading, spacing: 2) {
                Text(cfg.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(P.text).lineLimit(1)
                Text("\(PanelColors.acState(s)) · Room \(String(format: "%.1f", s.roomTemp))°")
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(s.on ? rgb.withWhite(0.45) : P.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 2) {
                StepButton(icon: "minus", label: "Cooler") { model.setAC(cfg.id, ["on": true, "target": s.target - 1]) }
                Text("\(Int(s.target))°")
                    .font(.system(size: 16, weight: .semibold).monospacedDigit())
                    .foregroundStyle(s.on ? P.text : P.faint)
                    .frame(minWidth: 38)
                    .contentTransition(.numericText(value: s.target))
                StepButton(icon: "plus", label: "Warmer") { model.setAC(cfg.id, ["on": true, "target": s.target + 1]) }
            }
            Button { model.setAC(cfg.id, ["on": !s.on]) } label: {
                Icon("power", size: 16, stroke: 2.2)
                    .foregroundStyle(lit ? Color(red: 6 / 255, green: 22 / 255, blue: 44 / 255) : s.on ? c : P.muted)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(lit ? c : s.on ? .clear : Color.white.opacity(0.08)))
                    .overlay(Circle().strokeBorder(s.idle && s.on ? c.opacity(0.7) : .clear, lineWidth: 1.5))
                    .shadow(color: lit ? c : .clear, radius: 9)
                    .contentShape(Circle())
            }
            .buttonStyle(PressScale(scale: 0.88))
            .accessibilityLabel("\(cfg.name) power")
        }
        .padding(.horizontal, 12)
        .frame(height: 68)
        .background {
            if lit {
                shape.fill(LinearGradient(colors: [c.opacity(0.26), c.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
            } else {
                shape.fill(hover.on ? P.glassHi : P.glass)
            }
        }
        .overlay(shape.strokeBorder(lit ? c.opacity(0.42) : P.line))
        .shadow(color: lit ? c.opacity(0.5) : .clear, radius: 10, y: 12)
        .contentShape(shape)
        .onTapGesture { model.openSheet(.ac(cfg.id)) }
        .onHover { hover.on = $0 }
        .animation(.easeOut(duration: 0.26), value: s.on)
        .animation(.easeOut(duration: 0.26), value: s.idle)
        .animation(.easeOut(duration: 0.26), value: s.mode)
        .animation(P.ease(0.3), value: s.target)
    }
}

/// Solar production and the battery's charge, read-only: a click opens the numbers.
struct EnergyTile: View {
    let model: HomeModel
    let cfg: HomeConfig.Energy
    @StateObject private var hover = Hover()

    var body: some View {
        let s = model.energy
        let on = (s.solar ?? 0) >= EnergyState.idleWatts
        let rgb = RGB(PanelColors.solar)
        let c = rgb.color
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        HStack(spacing: 11) {
            Icon(cfg.hasSolar ? "sun" : "battery", size: 19)
                .foregroundStyle(on ? Color(red: 36 / 255, green: 21 / 255, blue: 3 / 255) : P.muted)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(on ? c : Color.white.opacity(0.07)))
                .shadow(color: on ? c : .clear, radius: 11)
            VStack(alignment: .leading, spacing: 2) {
                Text(cfg.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(P.text).lineLimit(1)
                Text(cfg.status(s))
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(on ? rgb.withWhite(0.45) : P.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(height: 68)
        .background {
            if on {
                shape.fill(LinearGradient(colors: [c.opacity(0.26), c.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
            } else {
                shape.fill(hover.on ? P.glassHi : P.glass)
            }
        }
        .overlay(alignment: .bottomLeading) {
            // The battery's charge along the bottom edge, where a lamp tile shows its brightness.
            Rectangle().fill(Color(hex: PanelColors.charge(s.charge)))
                .frame(height: 3)
                .scaleEffect(x: (s.charge ?? 0) / 100, anchor: .leading)
                .opacity(cfg.hasBattery && s.charge != nil ? 0.9 : 0)
                .animation(P.ease(0.26), value: s.charge)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(on ? c.opacity(0.42) : P.line))
        .shadow(color: on ? c.opacity(0.5) : .clear, radius: 10, y: 12)
        .contentShape(shape)
        .onTapGesture { model.openSheet(.energy) }
        .onHover { hover.on = $0 }
        .animation(.easeOut(duration: 0.26), value: on)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cfg.name)
        .accessibilityValue(cfg.status(s))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.openSheet(.energy) }
    }
}

private struct StepButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    @StateObject private var hover = Hover()

    var body: some View {
        Button(action: action) {
            Icon(icon, size: 15, stroke: 2.2)
                .foregroundStyle(hover.on ? P.text : P.muted)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hover.on ? Color.white.opacity(0.12) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScale(scale: 0.86))
        .onHover { hover.on = $0 }
        .accessibilityLabel(label)
    }
}
