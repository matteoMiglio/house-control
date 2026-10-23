import SwiftUI

/// Floor Plans: your own home and the demos, which one is shown, and what can be done with each.
/// The menus switch quickly; this is where a home is started, replaced, exported or removed.
struct HomesView: View {
    let model: AppModel

    var body: some View {
        let active = model.activeHome
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Floor Plans").font(.system(size: 28, weight: .bold))
                    Text("The home shown is the one the menu bar, the island and the widgets control.")
                        .font(.callout).foregroundStyle(Theme.muted)
                }

                VStack(spacing: 10) {
                    SectionTitle("Your home")
                    Card {
                        if let own = model.ownHome {
                            HomeRow(entry: own, symbol: "house.fill", tint: Theme.warm, shown: active == own.id,
                                    detail: "\(rooms(own.rooms)) · \(AppModel.linkedLine(own.linked))") {
                                model.choosePlan(own.id)
                            }
                            Actions {
                                Button("Edit Home") { model.router.show(.editor) }
                                Button("Export…") { model.exportOwnHome() }
                                Button("Replace from File…") { model.loadPlan() }
                                Spacer(minLength: 0)
                                Button("Remove…", role: .destructive) { model.removeOwnHome() }
                            }
                        } else {
                            HStack(spacing: 12) {
                                IconBadge(symbol: "house", tint: Theme.warm)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("No home of your own yet").font(.system(size: 13, weight: .semibold))
                                    Text("Draw it in Edit Home, import a plan file, or start from one of the demos below.")
                                        .font(.caption).foregroundStyle(Theme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(18)
                            Actions {
                                Button("Draw My Home") { model.router.show(.editor) }
                                Button("Import Plan File…") { model.loadPlan() }
                            }
                        }
                    }
                }

                VStack(spacing: 10) {
                    SectionTitle("Demos")
                    Card {
                        let demos = model.demoHomes
                        ForEach(Array(demos.enumerated()), id: \.element.id) { i, demo in
                            if i > 0 { Divider().overlay(Theme.line).padding(.leading, 68).padding(.trailing, 18) }
                            HomeRow(entry: demo, symbol: demo.id == "studio" ? "square.split.bottomrightquarter" : "building.2",
                                    tint: Theme.accent, shown: active == demo.id, detail: "\(rooms(demo.rooms)) · everything simulated") {
                                model.choosePlan(demo.id)
                            } more: {
                                Menu {
                                    Button(model.ownHome == nil ? "Make It My Home" : "Make It My Home…") { model.startFromDemo(demo.id) }
                                } label: {
                                    Image(systemName: "ellipsis").frame(width: 22, height: 22)
                                }
                                .menuStyle(.borderlessButton)
                                .menuIndicator(.hidden)
                                .fixedSize()
                                .help("More for this demo")
                            }
                        }
                    }
                    Text("Demos are for trying House Control: everything in them is simulated and never reaches your devices. “Make It My Home” copies one as your own, to change in Edit Home.")
                        .font(.caption).foregroundStyle(Theme.faint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 560)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(Theme.text)
        .tint(Theme.accent)
        .background(Theme.background)
        .navigationTitle("Floor Plans")
    }

    private func rooms(_ n: Int) -> String { n == 1 ? "1 room" : "\(n) rooms" }
}

/// A home: its symbol, name and what it is, and Show (or Shown, for the one on screen).
private struct HomeRow<More: View>: View {
    let entry: HomeEntry
    let symbol: String
    let tint: Color
    let shown: Bool
    let detail: String
    let show: () -> Void
    @ViewBuilder var more: More

    init(entry: HomeEntry, symbol: String, tint: Color, shown: Bool, detail: String,
         show: @escaping () -> Void, @ViewBuilder more: () -> More = { EmptyView() }) {
        self.entry = entry
        self.symbol = symbol
        self.tint = tint
        self.shown = shown
        self.detail = detail
        self.show = show
        self.more = more()
    }

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if shown {
                Label("Shown", systemImage: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.green)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Theme.green.opacity(0.14), in: Capsule())
                    .accessibilityLabel("Shown now")
            } else {
                Button("Show", action: show).buttonStyle(.bordered).controlSize(.small)
            }
            more
        }
        .padding(18)
        .accessibilityElement(children: .contain)
    }
}

/// A row of actions under the home they act on, lined up with its text.
private struct Actions<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) { content }
            .buttonStyle(.bordered).controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 68).padding(.trailing, 18).padding(.bottom, 18).padding(.top, -6)
    }
}
