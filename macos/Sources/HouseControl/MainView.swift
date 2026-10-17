import SwiftUI

/// The app's main window: the home in 3D with its controls, and in the sidebar what else the
/// app does — AI Access, pairing an iPhone, editing the home.
struct MainView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.section) {
                Label("Home", systemImage: "house").tag(MainSection.home)

                Section("Set Up") {
                    SidebarButton("Edit Home…", systemImage: "square.and.pencil") { model.router.show(.editor(section: nil)) }
                    SidebarButton("Connections…", systemImage: "link") { model.router.show(.editor(section: "connections")) }
                    SidebarButton("AI Access…", systemImage: "sparkles") { model.router.show(.agent) }
                    SidebarButton("Pair iPhone…", systemImage: "iphone") { model.router.show(.pairing) }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            HomeView(model: model)
        }
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
            .toolbar(removing: .title) // the page shows the home's name itself
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
