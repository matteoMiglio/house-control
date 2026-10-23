import Combine
import HouseCore
import SwiftUI

/// A lamp's, an AC's, a camera's or the solar detail sheet, in place of the device list.
struct DeviceSheet: View {
    let model: HomeModel
    let sheet: HomeModel.Sheet

    var body: some View {
        switch sheet {
        case .light(let id): if let cfg = model.config.light(id) { LightSheet(model: model, cfg: cfg) }
        case .ac(let id): if let cfg = model.config.ac(id) { ACSheet(model: model, cfg: cfg) }
        case .camera(let camera): CameraSheet(model: model, camera: camera)
        case .energy: if let cfg = model.config.energy { EnergySheet(model: model, cfg: cfg) }
        }
    }
}

private struct SheetHead<Sub: View>: View {
    let model: HomeModel
    let name: String
    var power: (on: Bool, action: () -> Void)?
    @ViewBuilder var sub: Sub

    var body: some View {
        HStack(spacing: 10) {
            RoundButton(icon: "back", iconSize: 19, stroke: 2.2, label: "Back") { model.closeSheet() }
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 15, weight: .semibold)).foregroundStyle(P.text).lineLimit(1)
                HStack(spacing: 6) { sub }
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(P.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let power {
                RoundButton(icon: "power", size: 46, iconSize: 21, stroke: 2.2, lit: power.on, label: "Power", action: power.action)
            }
        }
    }
}

/// `.big`: the readout, ticking up or down as it changes.
private struct BigNumber: View {
    let text: String
    let value: Double
    let unit: String
    let off: Bool

    init(value: Int, unit: String, off: Bool) {
        self.init(text: "\(value)", value: Double(value), unit: unit, off: off)
    }

    /// `text`: the number as written ("3.2"), `value` what it ticks by.
    init(text: String, value: Double, unit: String, off: Bool) {
        self.text = text
        self.value = value
        self.unit = unit
        self.off = off
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(text)
                .font(.system(size: 68, weight: .light))
                .kerning(-2.4)
                .monospacedDigit()
                .contentTransition(.numericText(value: value))
                .animation(P.ease(0.26), value: value)
            Text(unit).font(.system(size: 19, weight: .semibold)).foregroundStyle(P.accent)
        }
        .foregroundStyle(P.text)
        .opacity(off ? 0.38 : 1)
        .animation(.easeOut(duration: 0.26), value: off)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FieldLabel: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(P.muted)
        .padding(.horizontal, 4)
    }
}

/// `.sheet-note`: a quiet hint at the bottom of a sheet.
private struct SheetNote: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Icon(icon, size: 20)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
        .lineSpacing(2)
        .foregroundStyle(P.muted)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(P.glass))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(P.line))
    }
}

// MARK: - Lamp

private struct LightSheet: View {
    let model: HomeModel
    let cfg: HomeConfig.Light

    var body: some View {
        let s = model.light(cfg.id)
        let set = { (patch: [String: Any]) in model.setLight(cfg.id, patch) }
        VStack(spacing: 0) {
            SheetHead(model: model, name: cfg.name, power: (s.on, { model.toggleLight(cfg.id) })) {
                Text(model.groupName(cfg.room))
                Text("·")
                Text(s.on ? "On" : "Off").foregroundStyle(P.text).fontWeight(.semibold)
            }
            BigNumber(value: cfg.dimmable ? Int((s.brightness * 100).rounded()) : s.on ? 100 : 0, unit: "%", off: !s.on)
                .padding(.top, 18)
            if cfg.dimmable {
                HStack(spacing: 10) {
                    RoundButton(icon: "dim", size: 40, iconSize: 18, label: "Dimmer") { set(["on": true, "brightness": s.brightness - 0.1]) }
                    GradientSlider(value: (s.brightness * 100).rounded(), range: 5...100, gradient: Gradients.dim) { set(["on": true, "brightness": $0 / 100]) }
                    RoundButton(icon: "bright", size: 40, iconSize: 18, label: "Brighter") { set(["on": true, "brightness": s.brightness + 0.1]) }
                }
                .padding(.top, 18)
            }
            if cfg.capabilities.contains("temp") {
                FieldLabel(title: "Colour temperature", value: s.color == nil ? "\(Int(s.temp)) K" : "—").padding(.top, 14)
                GradientSlider(value: s.temp, range: 2200...6500, step: 100, gradient: Gradients.kelvin, compact: true) { set(["on": true, "temp": $0]) }
                    .padding(.top, 8)
            }
            if cfg.capabilities.contains("color") {
                FieldLabel(title: "Colour", value: s.color?.uppercased() ?? "White").padding(.top, 14)
                ColorPad(color: s.color) { set(["on": true, "color": $0]) }.padding(.top, 8)
                HStack(spacing: 9) {
                    ForEach(PanelColors.swatches, id: \.self) { hex in
                        Swatch(hex: hex, selected: s.color?.lowercased() == hex) { set(["on": true, "color": hex]) }
                    }
                }
                .padding(.top, 10).padding(.horizontal, 2)
            } else {
                Spacer(minLength: 16)
                SheetNote(icon: cfg.icon, text: "\(model.groupName(cfg.room)) · drag across a light tile to dim it, or click the lamp in the 3D view to toggle.")
            }
        }
    }
}

private struct Swatch: View {
    let hex: String
    let selected: Bool
    let action: () -> Void
    @StateObject private var hover = Hover()

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: hex))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? .white : Color.white.opacity(0.1), lineWidth: selected ? 2 : 1))
                .frame(height: 28)
                .shadow(color: selected ? Color(hex: hex) : .clear, radius: 9, y: 6)
                .offset(y: hover.on ? -2 : 0)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
        .animation(P.spring, value: hover.on)
        .animation(.easeOut(duration: 0.2), value: selected)
        .accessibilityLabel("Colour \(hex)")
    }
}

// MARK: - AC

private struct ACSheet: View {
    let model: HomeModel
    let cfg: HomeConfig.AC

    var body: some View {
        let s = model.ac(cfg.id)
        let f = model.features(cfg.id)
        let set = { (patch: [String: Any]) in model.setAC(cfg.id, patch) }
        let modeColor = PanelColors.mode(s.mode).color
        VStack(spacing: 0) {
            SheetHead(model: model, name: cfg.name, power: (s.on, { set(["on": !s.on]) })) {
                Icon("thermo", size: 14)
                Text("Room ") + Text(verbatim: String(format: "%.1f°C", s.roomTemp)).foregroundColor(P.text).fontWeight(.semibold)
                LiveDot(on: s.on && !s.idle, color: modeColor)
            }
            HStack(alignment: .bottom, spacing: 12) {
                BigNumber(value: Int(s.target), unit: "°C", off: !s.on)
                if f.eco { EcoChip(on: s.eco) { set(["eco": !s.eco]) } }
            }
            .padding(.top, 18)
            HStack(spacing: 10) {
                RoundButton(icon: "minus", size: 40, iconSize: 18, stroke: 2.2, label: "Cooler") { set(["on": true, "target": s.target - 1]) }
                GradientSlider(value: s.target, range: cfg.min...cfg.max, gradient: Gradients.temperature,
                               labels: ("\(Int(cfg.min))°", "\(Int(cfg.max))°")) { set(["on": true, "target": $0]) }
                RoundButton(icon: "plus", size: 40, iconSize: 18, stroke: 2.2, label: "Warmer") { set(["on": true, "target": s.target + 1]) }
            }
            .padding(.top, 18)
            Spacer(minLength: 16)
            HStack(spacing: 8) {
                if !f.modes.isEmpty {
                    OptionCard(key: "mode", label: "Mode", value: PanelColors.modeLabel[s.mode] ?? s.mode, icon: s.mode, menu: model,
                               items: f.modes.map { ($0, PanelColors.modeLabel[$0] ?? $0) }, selected: s.mode, first: true) { set(["on": true, "mode": $0]) }
                }
                if !f.fans.isEmpty {
                    OptionCard(key: "fan", label: "Fan speed", value: PanelColors.fanLabel[s.fan] ?? s.fan, icon: "fan", menu: model,
                               items: f.fans.map { ($0, PanelColors.fanLabel[$0] ?? $0) }, selected: s.fan, first: f.modes.isEmpty) { set(["fan": $0]) }
                }
                if f.sleep {
                    SleepCard(on: s.sleep) { set(["sleep": !s.sleep]) }
                }
                if f.swing {
                    OptionCard(key: "swing", label: "Airflow", value: PanelColors.swingLabel[s.swing] ?? s.swing, icon: "wind", menu: model,
                               items: PanelColors.swings.map { ($0, PanelColors.swingLabel[$0] ?? $0) }, selected: s.swing) { set(["swing": $0]) }
                }
            }
        }
    }
}

/// `.toggle-chip`: Eco Mode with its switch.
private struct EcoChip: View {
    let on: Bool
    let action: () -> Void
    @StateObject private var hover = Hover()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Icon("leaf", size: 17).foregroundStyle(on ? Color(hex: "#6ee7a0") : P.muted)
                Text("Eco Mode").font(.system(size: 13, weight: .semibold)).foregroundStyle(P.text)
                Capsule()
                    .fill(on ? Color(hex: "#34c773") : Color.white.opacity(0.16))
                    .frame(width: 38, height: 23)
                    .overlay(alignment: on ? .trailing : .leading) {
                        Circle().fill(.white).frame(width: 18, height: 18).shadow(color: .black.opacity(0.4), radius: 1.5, y: 1).padding(2.5)
                    }
            }
            .padding(.leading, 14).padding(.trailing, 10)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(hover.on ? P.glassHi : P.glass))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(P.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
        .animation(P.spring, value: on)
        .accessibilityLabel("Eco Mode")
        .accessibilityValue(on ? "On" : "Off")
    }
}

/// `.option`: a card with an icon, a label and its value; it opens a menu above it.
private struct OptionCard: View {
    let key: String
    let label: String
    let value: String
    let icon: String
    let menu: HomeModel
    let items: [(String, String)]
    let selected: String
    /// The leftmost card: its menu opens to the right.
    var first = false
    let choose: (String) -> Void

    var body: some View {
        let open = menu.openMenu == key
        Button { menu.openMenu = open ? nil : key } label: {
            OptionFace(icon: icon, label: label, value: value, highlighted: open) {
                Icon("down", size: 15, stroke: 2.2).foregroundStyle(P.muted)
                    .rotationEffect(.degrees(open ? 180 : 0))
                    .animation(P.ease(0.3), value: open)
            }
        }
        .buttonStyle(PressScale(scale: 0.95))
        // Above the card, lined up with its right edge (its left edge for the first card, so the
        // menu stays inside the panel, as dom.js `openMenu` clamps it).
        .overlay(alignment: first ? .bottomLeading : .bottomTrailing) {
            if open {
                VStack(spacing: 8) {
                    OptionMenu(items: items, selected: selected) { value in
                        menu.openMenu = nil
                        choose(value)
                    }
                    .background(MenuFrame(model: menu))
                    Color.clear.frame(height: 96)
                }
                .fixedSize()
                .transition(.scale(scale: 0.86, anchor: first ? .bottomLeading : .bottomTrailing).combined(with: .opacity))
            }
        }
        .background { if open { MenuFrame(model: menu) } }
        .zIndex(open ? 1 : 0)
        .animation(P.ease(0.26), value: open)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

private struct SleepCard: View {
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            OptionFace(icon: "moon", label: "Sleep", value: on ? "On" : "Off", highlighted: on) {
                Circle()
                    .fill(on ? Color(hex: "#6fb0ff") : Color.white.opacity(0.22))
                    .frame(width: 8, height: 8)
                    .shadow(color: on ? Color(hex: "#6fb0ff") : .clear, radius: 5)
                    .padding(3)
            }
        }
        .buttonStyle(PressScale(scale: 0.95))
        .accessibilityLabel("Sleep")
        .accessibilityValue(on ? "On" : "Off")
    }
}

private struct OptionFace<Corner: View>: View {
    let icon: String
    let label: String
    let value: String
    let highlighted: Bool
    @ViewBuilder var corner: Corner
    @StateObject private var hover = Hover()

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        VStack(alignment: .leading, spacing: 2) {
            Icon(icon, size: 24, stroke: 1.6).foregroundStyle(Color(hex: "#6fb0ff"))
            Spacer(minLength: 0)
            Text(label).font(.system(size: 12)).foregroundStyle(P.muted).lineLimit(1)
            Text(value).font(.system(size: 13, weight: .semibold)).foregroundStyle(P.text).lineLimit(1)
        }
        .padding(.horizontal, 11).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 96, alignment: .leading)
        .overlay(alignment: .topTrailing) { corner.padding(.top, 11).padding(.trailing, 10) }
        .background {
            if highlighted {
                shape.fill(LinearGradient(colors: [Color(red: 88 / 255, green: 150 / 255, blue: 1).opacity(0.26),
                                                   Color(red: 61 / 255, green: 139 / 255, blue: 1).opacity(0.1)], startPoint: .top, endPoint: .bottom))
            } else {
                shape.fill(hover.on ? P.glassHi : P.glass)
            }
        }
        .overlay(shape.strokeBorder(highlighted ? Color(red: 120 / 255, green: 175 / 255, blue: 1).opacity(0.5) : P.line))
        .contentShape(shape)
        .onHover { hover.on = $0 }
        .animation(.easeOut(duration: 0.22), value: highlighted)
    }
}

/// `.menu`: the glass list an option card opens, the current choice ticked.
private struct OptionMenu: View {
    let items: [(String, String)]
    let selected: String
    let choose: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items, id: \.0) { item in
                MenuRow(title: item.1, selected: item.0 == selected) { choose(item.0) }
            }
        }
        .padding(6)
        .frame(minWidth: 150)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(red: 15 / 255, green: 21 / 255, blue: 38 / 255).opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(P.line))
        .shadow(color: .black.opacity(0.7), radius: 25, y: 24)
    }
}

private struct MenuRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @StateObject private var hover = Hover()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(title).font(.system(size: 13, weight: selected ? .semibold : .medium))
                Spacer(minLength: 0)
                if selected { Icon("check", size: 16, stroke: 2.4).foregroundStyle(Color(hex: "#8fbcff")) }
            }
            .foregroundStyle(selected || hover.on ? (selected ? .white : P.text) : P.muted)
            .padding(.leading, 12).padding(.trailing, 10)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color(red: 70 / 255, green: 130 / 255, blue: 1).opacity(0.28) : hover.on ? Color.white.opacity(0.08) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
    }
}

// MARK: - Camera

private struct CameraSheet: View {
    let model: HomeModel
    let camera: HomeModel.Camera

    var body: some View {
        VStack(spacing: 0) {
            SheetHead(model: model, name: camera.name) {
                Text("Security camera · ") + Text("View").foregroundColor(P.text).fontWeight(.semibold)
            }
            HStack(spacing: 8) {
                fact("Angle of view", "\(Self.number(camera.fov))°")
                fact("Mounted at", "\(Self.number(camera.y)) m · \(Self.number(camera.tilt))° down")
            }
            .padding(.top, 14)
            // How far out it makes out a face, a known person, what someone does, or anyone at all.
            VStack(spacing: 0) {
                ForEach(camera.levels.reversed(), id: \.name) { level in
                    HStack(spacing: 9) {
                        Circle().fill(Color(hex: level.color)).frame(width: 8, height: 8).shadow(color: Color(hex: level.color), radius: 4)
                        Text(level.name).frame(maxWidth: .infinity, alignment: .leading)
                        Text(level.reach < camera.range ? String(format: "%.1f m", level.reach) : "\(Self.number(camera.range)) m, its range")
                            .foregroundStyle(P.text).fontWeight(.semibold).monospacedDigit()
                    }
                    .font(.system(size: 12.5))
                    .foregroundStyle(P.muted)
                    .padding(.vertical, 5)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(P.glass))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(P.line))
            .padding(.top, 8)
            Spacer(minLength: 16)
            SheetNote(icon: "cctv", text: "Roughly what this camera sees: the dimmed part is outside its picture. Move or aim it in Edit Home.")
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(P.muted)
            Text(value).font(.system(size: 16, weight: .semibold).monospacedDigit()).foregroundStyle(P.text)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(P.glass))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(P.line))
    }

    /// 2.5 as "2.5", 100 as "100", as JavaScript prints numbers.
    static func number(_ v: Double) -> String {
        v == v.rounded() ? "\(Int(v))" : String(format: "%g", v)
    }
}

// MARK: - Solar and battery

/// What flows where right now, read-only: production big, then the house, the grid and the battery.
private struct EnergySheet: View {
    let model: HomeModel
    let cfg: HomeConfig.Energy

    var body: some View {
        let s = model.energy
        // Without panels the battery's charge is the big number.
        let big = cfg.hasSolar ? EnergyState.watts(s.solar) : s.charge.map { (number: "\(Int($0.rounded()))", unit: "%") }
        VStack(spacing: 0) {
            SheetHead(model: model, name: cfg.name) {
                Text(cfg.hasSolar ? "Production" : "Charge")
                Text("·")
                Text(!cfg.simulated ? "Live" : model.energyNotLinked ? "Not linked" : "Simulated").foregroundStyle(P.text).fontWeight(.semibold)
                if !cfg.simulated { LiveDot(on: true) }
            }
            BigNumber(text: big?.number ?? "—", value: cfg.hasSolar ? s.solar ?? 0 : s.charge ?? 0, unit: big?.unit ?? "",
                      off: cfg.hasSolar ? (s.solar ?? 0) < EnergyState.idleWatts : big == nil)
                .padding(.top, 18)
            VStack(spacing: 0) {
                row("House consumption", EnergyState.format(watts: cfg.consumption(s)), PanelColors.house)
                row("Grid", cfg.gridStatus(s), PanelColors.grid)
                if cfg.hasBattery {
                    row("Battery", s.batteryStatus, PanelColors.battery)
                    if cfg.hasSolar { row("Charge", EnergyState.format(charge: s.charge), PanelColors.charge(s.charge)) }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(P.glass))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(P.line))
            .padding(.top, 18)
            Spacer(minLength: 16)
            SheetNote(icon: cfg.hasSolar ? "sun" : "battery", text: model.energyNotLinked
                ? "No sensor is linked, and simulation is off in Settings. Link them in Edit Home → Solar & battery."
                : cfg.simulated
                ? "Simulated until a sensor is linked: a sunny day passes in six minutes. Link them in Edit Home → Solar & battery."
                : "Read from the sensors linked in Edit Home → Solar & battery, as they report.")
        }
    }

    /// A `.dori-row`: a dot in the colour of that power, its name, and its value.
    private func row(_ label: String, _ value: String, _ color: String) -> some View {
        HStack(spacing: 9) {
            Circle().fill(Color(hex: color)).frame(width: 8, height: 8).shadow(color: Color(hex: color), radius: 4)
            Text(label).frame(maxWidth: .infinity, alignment: .leading)
            Text(value).foregroundStyle(P.text).fontWeight(.semibold).monospacedDigit()
        }
        .font(.system(size: 12.5))
        .foregroundStyle(P.muted)
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

/// Tells the model where an open menu and the card that opened it are, so a click outside both
/// closes it (AppModel's mouse monitor).
private struct MenuFrame: View {
    let model: HomeModel

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { model.menuFrames.append(geo.frame(in: .global)) }
        }
    }
}
