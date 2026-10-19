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
                    HStack {
                        Text("AI Access")
                        Spacer()
                        if model.agentLive { LiveBadge() }
                    }
                } icon: { Image(systemName: "sparkles") }
                    .tag(MainSection.agent)
                Label {
                    HStack {
                        Text("Pair iPhone")
                        Spacer()
                        if !model.connectedDevices.isEmpty {
                            Text("\(model.connectedDevices.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                } icon: { Image(systemName: "iphone") }
                    .tag(MainSection.pairing)
                }

                Section {
                    SidebarButton("Settings…", systemImage: "gearshape") { model.router.show(.settings) }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            switch model.section {
            case .home: HomeView(model: model)
            case .editor, .connections: EditorView(model: model, showing: model.section)
            case .agent: AgentView(model: model)
            case .pairing: PairingView(model: model)
            }
        }
    }
}

/// Edit Home and Connections: the editor's page, its own list and inspector, the full width.
private struct EditorView: View {
    let model: AppModel
    let showing: MainSection

    var body: some View {
        WebSlot { slot, present in model.editorSlot(slot, present: present, showing: showing) }
            .id(showing) // a slot of its own for each, so moving between them lends the page again
            .navigationTitle(showing == .connections ? "Connections" : "Edit Home")
    }
}

/// The 3D home and its controls: the same page as the menu bar panel, lent to this window.
private struct HomeView: View {
    let model: AppModel

    var body: some View {
        // Up under the window's transparent title bar, but beside the sidebar, never under it.
        WebSlot { slot, present in model.homeSlot(slot, present: present) }
            .ignoresSafeArea(.container, edges: .top)
            .navigationTitle(model.homeName)
            .modifier(NoToolbarTitle())
    }
}

/// The page shows the home's name itself, so the toolbar does not repeat it (macOS 15 and later).
private struct NoToolbarTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) { content.toolbar(removing: .title) } else { content }
    }
}

/// AI Access: its page, made for a narrow window, in a column down the middle.
private struct AgentView: View {
    let model: AppModel

    var body: some View {
        WebSlot { slot, present in model.agentSlot(slot, present: present) }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .background(Color(red: 0.035, green: 0.043, blue: 0.08))
            .navigationTitle("AI Access")
    }
}

/// Shown beside AI Access while an assistant has a live link.
private struct LiveBadge: View {
    var body: some View {
        Text("Live")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.green.opacity(0.22), in: Capsule())
            .foregroundStyle(.green)
    }
}

/// A sidebar row that does something (opens another window) instead of selecting a screen.
private struct SidebarButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
