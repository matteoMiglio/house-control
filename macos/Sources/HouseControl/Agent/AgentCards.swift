import Combine
import HouseCore
import SwiftUI

// The cards under AI Access's hero, and the small controls they share.

// MARK: - Connect an assistant

private enum ConnectTab: String, CaseIterable {
    case chat = "Any chat", claude = "Claude", chatgpt = "ChatGPT", code = "Code & agents"
}

/// The tab shown, kept while the app runs as the web page kept it (no `@State` with the Command Line Tools).
private final class TabChoice: ObservableObject {
    static let shared = TabChoice()
    @Published var tab = ConnectTab.chat
}

struct ConnectCard: View {
    let agent: AgentController
    @ObservedObject private var choice = TabChoice.shared

    var body: some View {
        AgentCard(icon: "link", title: "Connect an assistant") {
            HStack(spacing: 4) {
                ForEach(ConnectTab.allCases, id: \.self) { tab in
                    let on = choice.tab == tab
                    Button { choice.tab = tab } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(on ? Theme.text : Theme.muted)
                            .padding(.horizontal, 11).frame(height: 28)
                            .background(on ? Color.white.opacity(0.08) : .clear, in: Capsule())
                            .overlay(Capsule().strokeBorder(on ? AI.cardLine : .clear))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.bottom, 12)
            VStack(alignment: .leading, spacing: 10) { tabBody }
                .font(.system(size: 12.5))
                .lineSpacing(3)
                .foregroundStyle(Color(hex: "#cfd5e6"))
                .fixedSize(horizontal: false, vertical: true)
        }
        // Assistants in the cloud cannot reach 127.0.0.1: on this Mac only, apps on the Mac are the audience.
        .onChange(of: agent.reach, initial: true) { _, reach in
            if reach == .local, choice.tab == .chat { choice.tab = .code }
            if reach == .internet, choice.tab == .code, agent.screenState != .live { choice.tab = .chat }
        }
    }

    @ViewBuilder private var tabBody: some View {
        let mcp = agent.mcp
        switch choice.tab {
        case .chat:
            Text("Works with assistants that can open web pages: ChatGPT, Claude, Gemini, Perplexity, Grok.")
            AISteps(items: [Text("**Copy for a chat** above and paste it into a new conversation."),
                          Text("Add what you want: ") + Text("“dim the living room to 30% and cool the bedroom to 22°”").foregroundColor(Theme.text) + Text("."),
                          Text("The assistant reads the guide behind the link and opens the matching action links. Watch them land below.")])
            Text("For photos of your rooms and edits to the 3D model, connect it as a connector (Claude, ChatGPT) instead — that needs more than opening links.")
                .foregroundStyle(Theme.faint)
        case .claude:
            AISteps(items: [Text("In Claude open **Settings → Connectors → Add custom connector**."),
                          Text("Name it **House Control** and paste this address:")])
            CodeBlock(text: mcp, placeholder: "Start AI Access to get the address")
            AISteps(start: 3, items: [Text("In a chat, turn it on from the tools menu and ask away — or attach photos: ")
                                        + Text("“here is my living room, rebuild it in 3D”").foregroundColor(Theme.text) + Text(".")])
        case .chatgpt:
            AISteps(items: [Text("In ChatGPT open **Settings → Apps & Connectors → Advanced** and turn on **Developer mode**."),
                          Text("**Create** a connector named **House Control** with this MCP address and no authentication:")])
            CodeBlock(text: mcp, placeholder: "Start AI Access to get the address")
            AISteps(start: 3, items: [Text("In a chat choose Developer mode, add House Control, and talk to your home.")])
            Text("No developer mode? “Copy for a chat” works in any ChatGPT conversation that can browse.").foregroundStyle(Theme.faint)
        case .code:
            Text("**Claude Code**")
            CodeBlock(text: mcp.map { "claude mcp add --transport http house-control \($0)" }, placeholder: "Start AI Access to get the address")
            Text("**Cursor, Windsurf, VS Code and other MCP clients**")
            CodeBlock(text: mcp.map { #"{"mcpServers":{"house-control":{"url":"\#($0)"}}}"# }, placeholder: "Start AI Access to get the address")
            Text("**Any agent or script** — plain HTTP with JSON. Tools: `GET …/api/tools`, run one: `POST …/api/<tool>`, OpenAPI: `…/openapi.json`.")
            CodeBlock(text: agent.link, placeholder: "Start AI Access to get the link")
        }
    }
}

/// Numbered steps with gradient numbers, counting from `start`.
private struct AISteps: View {
    var start = 1
    let items: [Text]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text("\(start + index)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 19, height: 19)
                        .background(LinearGradient(colors: [Color(hex: "#7c5cff"), AI.blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: Circle())
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                    item.fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A command or an address to copy; before the link is live, what to do to get it.
private struct CodeBlock: View {
    let text: String?
    let placeholder: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(text ?? placeholder)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(text == nil ? Theme.faint : Color(hex: "#dfe4f5"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            CopyButton(text: text, small: true)
        }
        .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 9)
        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.white.opacity(0.07)))
    }
}

// MARK: - What it may do

struct PermissionsCard: View {
    let agent: AgentController

    var body: some View {
        AgentCard(icon: "shield", title: "What it may do") {
            PermissionRow(icon: "sun", title: "Lights, climate and scenes", detail: "Switch and dim lights, set air conditioners, run scenes",
                          on: agent.permissions.control) { agent.setControl($0) }
            Divider().overlay(.white.opacity(0.06))
            PermissionRow(icon: "box", title: "Your 3D home", detail: "Rebuild rooms from photos, move furniture, add devices — always undoable",
                          on: agent.permissions.edit) { agent.setEdit($0) }
            Divider().overlay(.white.opacity(0.06))
            VStack(alignment: .leading, spacing: 8) {
                Label { Text("Stop the link automatically") } icon: { Icon("clock", size: 15).foregroundStyle(AI.lilac) }
                    .font(.system(size: 13, weight: .semibold))
                Segmented(options: [("1h", nil, "1 hour"), ("8h", nil, "8 hours"), ("never", nil, "Never")],
                          selection: agent.autoStop) { agent.setAutoStop($0) }
            }
            .padding(.vertical, 10)
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let on: Bool
    let set: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Icon(icon, size: 16)
                .foregroundStyle(Color(hex: "#d6ccff"))
                .frame(width: 34, height: 34)
                .background(AI.violet.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            AISwitch(on: on, label: title, set: set)
        }
        .padding(.vertical, 10)
    }
}

/// `.ai-switch`: violet when on.
private struct AISwitch: View {
    let on: Bool
    let label: String
    let set: (Bool) -> Void

    var body: some View {
        Button { set(!on) } label: {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(on ? AnyShapeStyle(LinearGradient(colors: [Color(hex: "#7c5cff"), AI.blue], startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(Color.white.opacity(0.14)))
                Circle().fill(.white).frame(width: 21, height: 21).shadow(color: .black.opacity(0.4), radius: 3, y: 2).padding(2)
            }
            .frame(width: 42, height: 25)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(P.spring, value: on)
        .accessibilityLabel(label)
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

// MARK: - Activity

struct ActivityCard: View {
    let agent: AgentController

    var body: some View {
        AgentCard(icon: "activity", title: "Activity") {
            GhostButton(icon: "undo", title: "Undo home edit") { agent.undoFromScreen() }
                .disabled(!agent.canUndo)
        } content: {
            let entries = Self.visible(agent.activity)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                if entries.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Icon("sparkles", size: 16).foregroundStyle(AI.lilac)
                        Text(agent.screenState == .live
                             ? "Waiting for your assistant. What it reads and does shows up here, live."
                             : "Nothing yet. Start AI Access, give the link to an assistant, and watch it work here.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(size: 12.5)).lineSpacing(3)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 8).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(entries) { entry in
                                FeedRow(entry: entry, now: context.date)
                                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -6)), removal: .opacity))
                            }
                        }
                        .animation(AI.ease(0.7), value: entries.first?.id)
                    }
                    .frame(maxHeight: 330)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Newest first; reads ("Looked at the home") are folded into the action that follows them.
    static func visible(_ activity: [AgentActivity]) -> [AgentActivity] {
        let entries = Array(activity.reversed())
        return entries.enumerated().filter { i, e in !e.quiet || i == 0 || entries[i - 1].client != e.client }
            .map(\.element).prefix(40).map { $0 }
    }
}

private struct FeedRow: View {
    let entry: AgentActivity
    let now: Date

    var body: some View {
        let tint = AI.color(of: entry.client)
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Icon(entry.client == "House Control" ? "home" : "sparkles", size: 11, stroke: 2.2)
                Text(entry.client)
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(tint)
            .padding(.leading, 6).padding(.trailing, 8).padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .fixedSize()
            Text(entry.title)
                .font(.system(size: 12.5))
                .foregroundStyle(entry.ok ? Color(hex: "#e6e9f2") : Color(hex: "#ff9a90"))
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(entry.title)
            Text(Self.ago(entry.date, now: now))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Theme.faint)
        }
        .padding(8)
        .opacity(entry.quiet ? 0.55 : 1)
    }

    static func ago(_ date: Date, now: Date) -> String {
        let s = max(0, now.timeIntervalSince(date))
        if s < 45 { return "now" }
        if s < 3600 { return "\(Int((s / 60).rounded())) min" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Private by design

struct PrivacyNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label { Text("Private by design") } icon: { Icon("shield", size: 15).foregroundStyle(AI.live) }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.muted)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(["Runs on this Mac. No House Control server, no account, nothing stored anywhere else.",
                         "The link holds a 128-bit secret. Without it every address answers “not found”.",
                         "Stop ends it at once — the address itself stops existing. Each start makes a new one.",
                         "Device IDs and sign-ins never leave the Mac. Cloudflare only relays the encrypted connection."], id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("•")
                        Text(line).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.system(size: 11.5)).lineSpacing(2)
            .foregroundStyle(Theme.faint)
        }
        .padding(.horizontal, 6).padding(.top, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Shared pieces

/// `.card` (`.link-card` with `tint: .link`): a title with an icon, an optional button beside it, and what it holds.
struct AgentCard<Trailing: View, Content: View>: View {
    enum Tint { case plain, link }

    let icon: String
    let title: String
    var tint = Tint.plain
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    init(icon: String, title: String, tint: Tint = .plain, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.tint = tint
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label { Text(title) } icon: { Icon(icon, size: 15).foregroundStyle(AI.lilac) }
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                trailing
            }
            .padding(.bottom, 12)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if tint == .link {
                shape.fill(LinearGradient(stops: [.init(color: Color(hex: "#7c5cff").opacity(0.16), location: 0),
                                                  .init(color: AI.blue.opacity(0.07), location: 0.6),
                                                  .init(color: .white.opacity(0.03), location: 1)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
            } else {
                shape.fill(AI.card)
            }
        }
        .overlay(shape.strokeBorder(tint == .link ? AI.violet.opacity(0.35) : AI.cardLine))
    }
}

extension AgentCard where Trailing == EmptyView {
    init(icon: String, title: String, @ViewBuilder content: () -> Content) {
        self.init(icon: icon, title: title, trailing: { EmptyView() }, content: content)
    }
}

/// `.ghost`: a small quiet button.
struct GhostButton: View {
    var icon: String?
    let title: String
    var help: String?
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @StateObject private var hover = Hover()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Icon(icon, size: 13) }
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(hover.on ? Theme.text : Theme.muted)
            .padding(.horizontal, 9).frame(height: 26)
            .background(.white.opacity(hover.on ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.35)
        .onHover { hover.on = $0 && enabled }
        .animation(.easeOut(duration: 0.2), value: hover.on)
        .help(help ?? "")
    }
}

/// Says "Copied" for a moment after it was pressed.
final class Flash: ObservableObject {
    @Published var on = false
    private var timer: Timer?

    func fire() {
        on = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.on = false }
        }
    }
}

/// `.copy`: copies `text` (nothing to copy yet: disabled).
struct CopyButton: View {
    let text: String?
    var small = false
    @StateObject private var flash = Flash()

    var body: some View {
        Button {
            guard let text else { return }
            AI.copy(text)
            flash.fire()
        } label: {
            HStack(spacing: 6) {
                Icon(flash.on ? "check" : "copy", size: small ? 13 : 14)
                Text(flash.on ? "Copied" : "Copy")
            }
            .font(.system(size: small ? 11.5 : 12, weight: .semibold))
            .foregroundStyle(flash.on ? Color(hex: "#c9ffdc") : Theme.text)
            .padding(.horizontal, small ? 9 : 11).frame(height: small ? 26 : 30)
            .background(flash.on ? AI.live.opacity(0.22) : .white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale(scale: 0.95))
        .disabled(text == nil)
        .opacity(text == nil ? 0.4 : 1)
        .animation(.easeOut(duration: 0.2), value: flash.on)
    }
}

/// `.action`: a wide button under the link.
struct ActionButton: View {
    let icon: String
    let title: String
    /// Said for a moment after pressing, when given.
    var done: String?
    let action: () -> Void
    @StateObject private var flash = Flash()
    @StateObject private var hover = Hover()

    var body: some View {
        let flashing = flash.on && done != nil
        Button {
            action()
            if done != nil { flash.fire() }
        } label: {
            HStack(spacing: 8) {
                Icon(icon, size: 16)
                Text(flashing ? done ?? title : title)
            }
            .font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity).frame(height: 40)
            .background(flashing ? AI.live.opacity(0.2) : .white.opacity(hover.on ? 0.12 : 0.07),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale(scale: 0.97))
        .onHover { hover.on = $0 }
        .animation(.easeOut(duration: 0.2), value: hover.on)
        .animation(.easeOut(duration: 0.2), value: flash.on)
    }
}

/// The aurora behind the hero: brighter while the link is live.
struct Aurora: View {
    let bright: Bool

    var body: some View {
        ZStack {
            Ellipse().fill(RadialGradient(colors: [Color(hex: "#7c5cff").opacity(0.34), .clear], center: .center, startRadius: 0, endRadius: 300))
                .frame(width: 600, height: 420).offset(x: -150, y: -20)
            Ellipse().fill(RadialGradient(colors: [AI.blue.opacity(0.28), .clear], center: .center, startRadius: 0, endRadius: 280))
                .frame(width: 560, height: 400).offset(x: 160, y: -60)
            Ellipse().fill(RadialGradient(colors: [Color(hex: "#ff5fc4").opacity(0.12), .clear], center: .center, startRadius: 0, endRadius: 220))
                .frame(width: 440, height: 300).offset(x: 40, y: 120)
        }
        .blur(radius: 10)
        .frame(height: 560)
        .frame(maxWidth: .infinity)
        .opacity(bright ? 1 : 0.55)
        .animation(.easeOut(duration: 0.9), value: bright)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
