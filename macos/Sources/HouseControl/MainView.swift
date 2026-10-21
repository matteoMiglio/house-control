import SwiftUI

/// The app's main window: the home in 3D with its controls, and in the sidebar what else the
/// app does — editing the home and its connections, AI Access, pairing an iPhone.
struct MainView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView(columnVisibility: $model.sidebar) {
            List(selection: $model.section) {
                Label("Home", systemImage: "house").tag(MainSection.home)
                Label("Edit Home", systemImage: "square.and.pencil").tag(MainSection.editor)
                Label("Connections", systemImage: "link").tag(MainSection.connections)

                Section("Access") {
                    Label {
                        HStack(spacing: 8) {
                            Text("AI Access")
                            Spacer(minLength: 0)
                            if model.agentLive { LiveBadge() }
                        }
                    } icon: { Image(systemName: "sparkles") }
                        .tag(MainSection.agent)
                    Label {
                        HStack(spacing: 8) {
                            Text("Pair iPhone")
                            Spacer(minLength: 0)
                            if !model.connectedDevices.isEmpty {
                                Text("\(model.connectedDevices.count)")
                                    .font(.caption2.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(Theme.muted)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Theme.surfaceHigh, in: Capsule())
                                    .accessibilityLabel("\(model.connectedDevices.count) connected iPhones")
                            }
                        }
                    } icon: { Image(systemName: "iphone") }
                        .tag(MainSection.pairing)
                }

                Section {
                    Label("Settings", systemImage: "gearshape").tag(MainSection.settings)
                }
            }
            .listStyle(.sidebar)
            .tint(Theme.accent)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SidebarStatus(model: model)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            switch model.section {
            case .home: HomeView(model: model)
            case .editor: EditorView(model: model)
            case .connections: ConnectionsView(model: model.connections)
            case .agent: AgentView(agent: model.agent)
            case .pairing: PairingView(model: model)
            case .settings: MacSettingsView(model: model)
            }
        }
    }
}

/// Edit Home: the editor's page, its own list and inspector, the full width.
private struct EditorView: View {
    let model: AppModel

    var body: some View {
        // Up under the title bar too: the editor's top bar grows by as much (editor.css), so its
        // colour fills it while its buttons stay below it.
        WebSlot { slot, present in model.editorSlot(slot, present: present) }
            .ignoresSafeArea(.container, edges: .top)
            .navigationTitle("Edit Home")
    }
}

/// The 3D home and its controls: the same page as the menu bar panel, lent to this window, with
/// the same native controls over it.
private struct HomeView: View {
    let model: AppModel

    var body: some View {
        // Up under the title bar, so the page's own colours fill it; the page's header lies level
        // with the sidebar's first row.
        HomeSurface(model: model.home, chrome: .window) { slot, present in model.homeSlot(slot, present: present) }
            .ignoresSafeArea(.container, edges: .top)
    }
}

/// Shown beside AI Access while an assistant has a live link.
private struct LiveBadge: View {
    var body: some View {
        Text("Live")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Theme.green.opacity(0.14), in: Capsule())
            .foregroundStyle(Theme.green)
    }
}

/// The home's name and a quiet summary, always visible below navigation.
private struct SidebarStatus: View {
    let model: AppModel

    private var summary: String {
        let lights = model.lastSummary["lightsOn"] as? Int ?? 0
        let ac = model.lastSummary["acOn"] as? Int ?? 0
        var parts: [String] = []
        if lights > 0 { parts.append("\(lights) \(lights == 1 ? "light" : "lights") on") }
        if ac > 0 {
            if let target = model.lastSummary["acTarget"] as? Int {
                parts.append("AC \(target)°")
            } else {
                parts.append("AC on")
            }
        }
        return parts.isEmpty ? "Everything off" : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(model.homeName).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text).lineLimit(1)
            Text(summary).font(.system(size: 11)).foregroundStyle(Theme.muted)
                .lineLimit(1).minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}
