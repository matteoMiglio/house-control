import SwiftUI
import HouseCore

/// Settings: a screen of the main window (⌘, or Settings… in the menus).
struct MacSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Open at Login", isOn: Binding(get: { model.loginState == .on }, set: { model.setOpenAtLogin($0) }))
                if model.loginState == .needsApproval {
                    Text("Waiting for your approval in System Settings → General → Login Items.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Toggle("Show the island around the notch", isOn: Binding(get: { model.islandShown }, set: { model.setIsland($0) }))
            }
            Section("Floor Plan") {
                LabeledContent("Home", value: model.homeName)
                HStack {
                    Button("Load Floor Plan…") { model.loadPlan() }
                    Button("Reveal Plan File") { model.revealPlan() }
                    Button("Reveal Device Log") { model.revealLog() }
                }
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                HStack(spacing: 14) {
                    Link("Website", destination: About.website)
                    Link("Privacy Policy", destination: About.privacy)
                    Link("Support", destination: About.support)
                    Link("Source Code", destination: About.source)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        // One colour behind the form and beside it (not the window's dark blue).
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Settings")
    }
}
