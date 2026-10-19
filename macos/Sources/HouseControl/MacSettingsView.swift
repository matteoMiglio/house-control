import AppKit
import SwiftUI
import HouseCore

/// Settings: a screen of the main window (⌘, or Settings… in the menus).
struct MacSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings").font(.system(size: 28, weight: .bold))

                VStack(spacing: 10) {
                    SectionTitle("On this Mac")
                    Card {
                        SettingsRow(symbol: "power", title: "Open at Login",
                                    detail: model.loginState == .needsApproval
                                        ? "Approve in System Settings → General → Login Items."
                                        : "Start House Control when you sign in to your Mac.") {
                            Toggle("Open at Login", isOn: Binding(get: { model.loginState == .on }, set: { model.setOpenAtLogin($0) }))
                                .labelsHidden()
                        }
                        Divider().overlay(Theme.line).padding(.leading, 68).padding(.trailing, 18)
                        SettingsRow(symbol: "macbook", title: "Show the island around the notch",
                                    detail: "Keep your home's controls at the top of the screen.") {
                            Toggle("Show the island around the notch", isOn: Binding(get: { model.islandShown }, set: { model.setIsland($0) }))
                                .labelsHidden()
                        }
                    }
                }

                VStack(spacing: 10) {
                    SectionTitle("Floor plan")
                    Card {
                        SettingsRow(symbol: "house", title: model.homeName,
                                    detail: "The floor plan and device layout for your home.") { EmptyView() }
                        // One row of actions, under the text they belong to.
                        HStack(spacing: 8) {
                            Button("Load Floor Plan…") { model.loadPlan() }
                            Button("Reveal Plan File") { model.revealPlan() }
                            Button("Reveal Device Log") { model.revealLog() }
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 68).padding(.trailing, 18).padding(.bottom, 18).padding(.top, -6)
                    }
                }

                VStack(spacing: 10) {
                    SectionTitle("About")
                    Card(padding: 18) {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack(spacing: 14) {
                                Image(nsImage: NSApp.applicationIconImage)
                                    .resizable().scaledToFit().frame(width: 52, height: 52)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("House Control").font(.headline)
                                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")")
                                        .font(.callout).foregroundStyle(Theme.muted)
                                }
                            }
                            HStack(spacing: 16) {
                                Link("Website", destination: About.website)
                                Link("Privacy Policy", destination: About.privacy)
                                Link("Support", destination: About.support)
                                Link("Source Code", destination: About.source)
                            }
                            .font(.callout)
                            .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
            .frame(maxWidth: 560)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(Theme.text)
        .toggleStyle(.switch)
        .tint(Theme.accent)
        .background(Theme.background)
        .navigationTitle("Settings")
    }
}

/// A setting's symbol and explanation, with its control at the trailing edge.
private struct SettingsRow<Control: View>: View {
    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.caption).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(18)
    }
}
