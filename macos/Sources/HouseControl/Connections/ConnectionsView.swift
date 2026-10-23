import SwiftUI

/// Connections: a screen of the main window. The platforms, and one of them over the list.
struct ConnectionsView: View {
    @Bindable var model: ConnectionsModel

    var body: some View {
        NavigationStack(path: $model.path) {
            ConnectionsOverview(model: model)
                .navigationDestination(for: ConnectionsModel.Service.self) { service in
                    ServiceScreen(model: model, service: service)
                }
        }
        .foregroundStyle(Theme.text)
        .tint(Theme.accent)
        .background(Theme.background)
    }
}

/// A screen of this section: a column down the middle, like Settings, and the latest notice
/// at the bottom (inside each screen: the stack's AppKit views cover anything laid over it).
private struct Page<Content: View>: View {
    let model: ConnectionsModel
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) { content }
                .frame(maxWidth: 560)
                .padding(32)
                .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .overlay(alignment: .bottom) {
            if let notice = model.notice {
                NoticeView(notice: notice)
                    .padding(20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: model.notice)
    }
}

// MARK: - Overview

private struct ConnectionsOverview: View {
    let model: ConnectionsModel

    var body: some View {
        Page(model: model) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Connections").font(.system(size: 28, weight: .bold))
                Text("Where your real lamps and air conditioners live.").font(.callout).foregroundStyle(Theme.muted)
            }

            VStack(spacing: 10) {
                ForEach(model.offered) { service in
                    ServiceCard(model: model, service: service)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Footnote("Lamps and ACs show “Not linked” until you link them (in the demos they are simulated): pick one in Edit Home, then choose its device under “Real device”. One home can mix them all.")
                Button { model.openEditor?() } label: { Label("Edit Home", systemImage: "square.and.pencil") }
                    .buttonStyle(.bordered)
            }
        }
        .navigationTitle("Connections")
        .onAppear { if model.anyConnected, model.devices == nil, !model.loading { model.load() } }
    }
}

private struct ServiceCard: View {
    let model: ConnectionsModel
    let service: ConnectionsModel.Service
    @StateObject private var hover = Hover()

    var body: some View {
        let on = model.connected(service)
        Button { model.path = [service] } label: {
            HStack(spacing: 14) {
                ServiceTile(service: service, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(service.name).font(.system(size: 14.5, weight: .semibold))
                    Text(service.blurb).font(.system(size: 12)).foregroundStyle(Theme.faint)
                    HStack(spacing: 5) {
                        if on { Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)) }
                        Text(model.status(service)).lineLimit(1)
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(on ? Color(hex: "#6ee7a0") : Theme.muted)
                    .padding(.top, 4)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.faint)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hover.on ? Theme.surfaceHigh : Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(hover.on ? Color.white.opacity(0.16) : Theme.line))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressScale(scale: 0.985))
        .onHover { hover.on = $0 }
        .animation(.easeOut(duration: 0.16), value: hover.on)
        .accessibilityLabel("\(service.name), \(model.status(service))")
    }
}

/// The platform's coloured tile with its icon (`.svc-tile`).
struct ServiceTile: View {
    let service: ConnectionsModel.Service
    var size: CGFloat = 34

    var body: some View {
        let tint = Color(hex: service.tint)
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        Icon(service.icon, size: (size * 0.52).rounded(), stroke: 2)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                shape.fill(tint)
                shape.fill(RadialGradient(colors: [.white.opacity(0.35), .clear], center: UnitPoint(x: 0.2, y: 0.1),
                                          startRadius: 0, endRadius: size * 0.75))
            }
            .overlay(shape.strokeBorder(.white.opacity(0.18)))
            .shadow(color: tint.opacity(0.55), radius: 8, y: 5)
            .accessibilityHidden(true)
    }
}

// MARK: - One platform

private struct ServiceScreen: View {
    let model: ConnectionsModel
    let service: ConnectionsModel.Service

    var body: some View {
        Page(model: model) {
            // The window has no title bar to hold the stack's own back button.
            Button { model.path = [] } label: {
                Label("Connections", systemImage: "chevron.left").font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color(hex: "#7fb2ff"))
            .keyboardShortcut("[", modifiers: .command)
            .padding(.bottom, -10)
            HStack(spacing: 14) {
                ServiceTile(service: service, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(service.name).font(.system(size: 26, weight: .bold))
                    Text(service.blurb).font(.callout).foregroundStyle(Theme.muted)
                }
            }
            switch service {
            case .smartLife: SmartLifeScreen(model: model)
            case .homeAssistant: HomeAssistantScreen(model: model)
            case .hue: HueScreen(model: model)
            case .homeKit: HomeKitScreen(model: model)
            }
        }
        .navigationTitle(service.name)
        .onAppear { model.appeared(service) }
        .onDisappear { model.left(service) }
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: model.connected(service))
    }
}

// MARK: - Shared pieces

/// A titled group: a section title over a card.
struct ConnectionSection<Content: View>: View {
    let title: String
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    init(_ title: String, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.title = title
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 10) {
            SectionTitle(title)
            Card(padding: padding) {
                VStack(alignment: .leading, spacing: 14) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// A server, bridge, account or device: a dot (green while online), a name and a line under it.
struct DeviceRow<Accessory: View>: View {
    let name: String
    let line: String
    var online = true
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(online ? Theme.green : Color.white.opacity(0.22))
                .frame(width: 8, height: 8)
                .shadow(color: online ? Theme.green.opacity(0.7) : .clear, radius: 4)
                .help(online ? "Online" : "Offline")
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13.5, weight: .semibold))
                Text(line).font(.system(size: 12)).foregroundStyle(Theme.faint).lineLimit(2)
            }
            Spacer(minLength: 8)
            accessory
        }
    }
}

extension DeviceRow where Accessory == EmptyView {
    init(name: String, line: String, online: Bool = true) {
        self.init(name: name, line: line, online: online) { EmptyView() }
    }
}

/// The plan item that uses a device.
struct UsedPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(hex: "#6ee7a0"))
            .lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Theme.green.opacity(0.14), in: Capsule())
    }
}

/// A small grey paragraph.
struct Footnote: View {
    let text: String
    var bad = false

    init(_ text: String, bad: Bool = false) {
        self.text = text
        self.bad = bad
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(bad ? Theme.red : Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A spinner and what it is waiting for.
struct Busy: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text).font(.system(size: 13)).foregroundStyle(Theme.muted)
        }
    }
}

/// Numbered instructions.
struct Steps: View {
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, text in
                NumberedStep(number: index + 1, text: text)
            }
        }
    }
}

/// A label over a field.
struct Field<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
            content.textFieldStyle(.roundedBorder).controlSize(.large)
        }
    }
}

/// "Look again": discovery once more.
struct LookAgain: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) { Label("Look again", systemImage: "dot.radiowaves.left.and.right") }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.accent)
            .font(.system(size: 12.5, weight: .semibold))
    }
}

/// The devices a connected platform reported, by kind, with the plan items that use them.
struct ServiceDevices: View {
    let model: ConnectionsModel
    let service: ConnectionsModel.Service

    private static let kinds = [("light", "Lights and plugs"), ("ac", "Air conditioners"), ("sensor", "Temperature sensors"),
                                ("power", "Power sensors"), ("battery", "Battery levels")]

    var body: some View {
        if model.loading {
            Busy(text: "Asking for the devices…")
        } else if let error = model.errors[service.rawValue] ?? model.errors["all"] {
            Footnote(error, bad: true)
        } else if model.devices != nil {
            let list = model.devices(of: service)
            if list.isEmpty {
                Footnote("Connected, but no lamps, air conditioners or sensors were found.")
            } else {
                ForEach(Self.kinds, id: \.0) { kind, title in
                    let items = list.filter { $0.kind == kind }
                    if !items.isEmpty {
                        DeviceGroup(title: "\(title) · \(items.count)", devices: items, used: model.used)
                    }
                }
            }
        }
    }
}

struct DeviceGroup: View {
    let title: String
    let devices: [ConnectionsModel.Device]
    let used: [String: String]

    var body: some View {
        ConnectionSection(title) {
            ForEach(Array(devices.enumerated()), id: \.offset) { index, device in
                if index > 0 { Divider().overlay(Theme.line) }
                DeviceRow(name: device.name, line: device.line, online: device.online) {
                    if let item = used[device.key] { UsedPill(text: item) }
                }
            }
        }
    }
}

private struct NoticeView: View {
    let notice: ConnectionsModel.Notice

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: notice.bad ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(notice.bad ? Theme.red : Theme.green)
            Text(notice.text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        .accessibilityAddTraits(.isStaticText)
    }
}
