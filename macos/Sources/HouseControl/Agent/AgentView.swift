import AppKit
import SwiftUI

/// AI Access: start and stop the private link, hand it to an assistant, choose what the
/// assistant may do, and watch what it does. Reads everything from `AgentController`; the look
/// is the one web/src/agent/console.css had.
struct AgentView: View {
    let agent: AgentController

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Hero(agent: agent)
                if agent.screenState == .live { LinkCard(agent: agent).transition(.cardIn) }
                ConnectCard(agent: agent)
                PermissionsCard(agent: agent)
                ActivityCard(agent: agent)
                PrivacyNote()
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 22)
            .padding(.top, 46)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity)
            .animation(AI.ease(0.5), value: agent.screenState)
        }
        .background(alignment: .top) { Aurora(bright: agent.screenState == .live) }
        .background(AI.background)
        .foregroundStyle(Theme.text)
        .navigationTitle("AI Access")
    }
}

/// The screen's palette and shapes (console.css).
enum AI {
    static let background = Color(hex: "#07090f")
    static let violet = Color(hex: "#8b6cff")
    static let blue = Color(hex: "#3d8bff")
    static let lilac = Color(hex: "#b9a6ff")
    static let card = Color.white.opacity(0.045)
    static let cardLine = Color.white.opacity(0.08)
    static let live = Color(hex: "#34c759")
    static let red = Color(hex: "#ff5a4f")
    static let mono = Font.system(size: 12.5, weight: .medium, design: .monospaced)
    static let gradient = LinearGradient(colors: [Color(hex: "#7c5cff"), Color(hex: "#4f7dff"), Color(hex: "#3d8bff")],
                                         startPoint: .leading, endPoint: .trailing)

    /// `--ease`: cubic-bezier(0.22, 1, 0.36, 1).
    static func ease(_ seconds: Double) -> Animation { .timingCurve(0.22, 1, 0.36, 1, duration: seconds) }

    /// What assistants wear in the feed.
    static func color(of client: String) -> Color {
        let colors = ["ChatGPT": "#19c37d", "Claude": "#e08a5f", "Claude Code": "#e08a5f", "Cursor": "#e6e9f2", "Gemini": "#6ea8ff",
                      "Perplexity": "#3fc1c9", "Copilot": "#8ab4ff", "House Control": "#8a94ab"]
        return Color(hex: colors[client] ?? "#b9a6ff")
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func open(_ link: String?) {
        guard let link, let url = URL(string: link), ["http", "https"].contains(url.scheme ?? "") else { return }
        NSWorkspace.shared.open(url)
    }
}

extension AgentController {
    /// What the screen shows: the phase, with a missing tunnel program as a state of its own.
    enum ScreenState: Equatable { case off, starting, live, error, setup }

    var screenState: ScreenState {
        switch phase {
        case .off: .off
        case .starting: .starting
        case .live: .live
        case .failed(let message): message == "needs-cloudflared" ? .setup : .error
        }
    }

    var failure: String? {
        if case .failed(let message) = phase, message != "needs-cloudflared" { return message.isEmpty ? "Something went wrong." : message }
        return nil
    }
}

extension AnyTransition {
    /// `card-in`: up a little and in.
    static var cardIn: AnyTransition { .opacity.combined(with: .offset(y: 8)) }
}

// MARK: - Hero

private struct Hero: View {
    let agent: AgentController

    var body: some View {
        let state = agent.screenState
        VStack(spacing: 0) {
            Orb(state: state).padding(.top, 6)
            Text("AI Access")
                .font(.system(size: 30, weight: .bold))
                .kerning(-0.6)
                .foregroundStyle(LinearGradient(colors: [.white, .white, Color(hex: "#c9cfe6")], startPoint: .top, endPoint: .bottom))
                .padding(.top, 18).padding(.bottom, 6)
            Text("Let ChatGPT, Claude or any AI assistant see and run your home — through a private link that lives only as long as you want it to.")
                .font(.system(size: 13.5)).lineSpacing(3)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                StatusPill(agent: agent, now: context.date)
            }
            .padding(.bottom, 16)
            PrimaryButton(state: state) {
                if state == .live || state == .starting { agent.stop() } else { agent.start() }
            }
            Segmented(options: [(AgentController.Reach.internet, "globe", "Over the internet"), (.local, "laptop", "This Mac only")],
                      selection: agent.reach, locked: state == .live || state == .starting) { agent.setReach($0) }
                .padding(.top, 12)
            if state == .setup { SetupCallout(agent: agent).padding(.top, 16).transition(.cardIn) }
            if let failure = agent.failure { ErrorCallout(message: failure).padding(.top, 16).transition(.cardIn) }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
    }
}

/// The orb: a glow, a ring of colours that seem to flow (three still gradients whose opacities
/// drift), grey while off and red after an error, and a dark core with sparkles.
private struct Orb: View {
    let state: AgentController.ScreenState

    private static func conic(_ from: Double, _ hexes: [String]) -> AngularGradient {
        // CSS measures from the top, SwiftUI from the right.
        AngularGradient(colors: hexes.map { Color(hex: $0) }, center: .center,
                        startAngle: .degrees(from - 90), endAngle: .degrees(from + 270))
    }

    var body: some View {
        let flowing = state == .live || state == .starting
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [AI.violet.opacity(0.5), AI.blue.opacity(0.22), .clear], center: .center,
                                     startRadius: 0, endRadius: 78))
                .frame(width: 156, height: 156)
                .opacity(state == .live ? 1 : state == .starting ? 0.55 : 0.2)
                .animation(.easeOut(duration: 1.2), value: state)
                .modifier(Pulse(on: state == .live, low: 0.6, seconds: 2.5))
            ZStack {
                Circle().fill(Self.conic(210, ["#8b6cff", "#3d8bff", "#42d6e8", "#3d8bff", "#ff5fc4", "#8b6cff"]))
                // The colours flow only while there is something to show: under the grey cover they stay still.
                if flowing {
                    let pace = state == .starting ? 2.4 : 9.0
                    Circle().fill(Self.conic(330, ["#ff5fc4", "#8b6cff", "#3d8bff", "#42d6e8", "#8b6cff", "#ff5fc4"]))
                        .phaseAnimator([0.0, 1, 0.15]) { ring, value in ring.opacity(value) } animation: { _ in .easeInOut(duration: pace / 3) }
                    Circle().fill(Self.conic(90, ["#42d6e8", "#8b6cff", "#ff5fc4", "#6e8bff", "#42d6e8"]))
                        .phaseAnimator([0.0, 0, 1]) { ring, value in ring.opacity(value) } animation: { _ in .easeInOut(duration: pace / 3) }
                }
                Circle()
                    .fill(state == .error ? Self.conic(210, ["#ff5a4f", "#8a2b3a", "#ff8a80", "#8a2b3a", "#ff5a4f"])
                        : Self.conic(210, ["#4a4f66", "#3a3f55", "#565b72", "#3a3f55", "#4a4f66"]))
                    .opacity(state == .live ? 0 : state == .starting ? 0.35 : state == .error ? 0.6 : 0.88)
                    .animation(.easeOut(duration: 1.2), value: state)
            }
            .id(state == .starting) // the flow restarts at its new pace
            .frame(width: 104, height: 104)
            Circle()
                .fill(RadialGradient(colors: [Color(hex: "#2a2f4a"), Color(hex: "#0d1020")], center: UnitPoint(x: 0.35, y: 0.3),
                                     startRadius: 0, endRadius: 56))
                .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                .padding(-3).background(Circle().fill(Color(hex: "#0b0d18"))).padding(3)
                .frame(width: 80, height: 80)
                .shadow(color: .black.opacity(0.8), radius: 15, y: 10)
            Icon("sparkles", size: 30, stroke: 1.8)
                .foregroundStyle(.white)
                .opacity(state == .live ? 1 : 0.55)
                .animation(.easeOut(duration: 0.8), value: state)
        }
        .frame(width: 104, height: 104)
        .accessibilityHidden(true)
    }
}

private struct StatusPill: View {
    let agent: AgentController
    let now: Date

    var body: some View {
        let state = agent.screenState
        let local = agent.reach == .local
        let label = switch state {
        case .off: "Off"
        case .starting: local ? "Starting…" : "Opening a private tunnel…"
        case .live: agent.stopsAt.map { "Live · \(Self.left($0, now: now))" } ?? "Live"
        case .error: "Stopped"
        case .setup: "One-time setup"
        }
        let (text, line, fill, dot): (Color, Color, Color, Color) = switch state {
        case .live: (Color(hex: "#d9ffe9"), AI.live.opacity(0.35), AI.live.opacity(0.1), AI.live)
        case .error: (Color(hex: "#ffd2cc"), AI.red.opacity(0.35), AI.red.opacity(0.1), AI.red)
        case .starting: (Theme.muted, AI.cardLine, .white.opacity(0.06), AI.violet)
        default: (Theme.muted, AI.cardLine, .white.opacity(0.06), .white.opacity(0.3))
        }
        HStack(spacing: 8) {
            Circle().fill(dot).frame(width: 7, height: 7)
                .background { if state == .live { Ping() } }
                .modifier(Pulse(on: state == .starting, low: 0.3, seconds: 0.9))
            Text(label)
            if state == .live {
                Text(local ? "This Mac" : "Internet")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.white.opacity(0.08), in: Capsule())
            }
        }
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(text)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(fill, in: Capsule())
        .overlay(Capsule().strokeBorder(line))
        .animation(.easeOut(duration: 0.3), value: state)
    }

    static func left(_ end: Date, now: Date) -> String {
        let m = max(0, Int((end.timeIntervalSince(now) / 60).rounded()))
        return m >= 60 ? "\(m / 60) h \(m % 60) min left" : "\(m) min left"
    }
}

/// Fades between full and `low` opacity and back, again and again, while `on`.
private struct Pulse: ViewModifier {
    let on: Bool
    let low: Double
    let seconds: Double

    func body(content: Content) -> some View {
        if on {
            content.phaseAnimator([1, low]) { view, value in view.opacity(value) } animation: { _ in .easeInOut(duration: seconds) }
        } else {
            content
        }
    }
}

/// The live dot's ring, growing out of it and fading, every 1.8 s (`live-dot`).
private struct Ping: View {
    var body: some View {
        Circle().stroke(AI.live.opacity(0.6), lineWidth: 1.5)
            .phaseAnimator([false, true]) { ring, out in
                ring.scaleEffect(out ? 3 : 1).opacity(out ? 0 : 1)
            } animation: { out in out ? .easeOut(duration: 1.3) : .linear(duration: 0.01).delay(0.5) }
    }
}

/// Start, Cancel while starting, Stop while live.
private struct PrimaryButton: View {
    let state: AgentController.ScreenState
    let action: () -> Void

    var body: some View {
        let stop = state == .live || state == .starting
        Button(action: action) {
            HStack(spacing: 9) {
                switch state {
                case .live: Icon("stop", size: 15, stroke: 2.4); Text("Stop AI Access")
                case .starting: ProgressView().controlSize(.small).tint(Color(hex: "#ff8a80")); Text("Cancel")
                default: Icon("sparkles", size: 17, stroke: 2); Text("Start AI Access")
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(stop ? Color(hex: "#ff8a80") : .white)
            .frame(maxWidth: 300).frame(height: 50)
            .background {
                let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
                if stop { shape.fill(.white.opacity(0.06)) } else { shape.fill(AI.gradient) }
            }
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(stop ? Color(red: 1, green: 110 / 255, blue: 100 / 255).opacity(0.4) : .white.opacity(0.16)))
            .shadow(color: stop ? .clear : Color(red: 110 / 255, green: 90 / 255, blue: 1).opacity(0.85), radius: 15, y: 12)
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(PressScale(scale: 0.97))
        .animation(.easeOut(duration: 0.3), value: state)
    }
}

/// `.seg`: a row of choices; `locked` greys out all but the one chosen.
struct Segmented<Value: Hashable>: View {
    let options: [(Value, String?, String)]
    let selection: Value
    var locked = false
    let choose: (Value) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let (value, icon, label) = option
                let on = value == selection
                Button { if !locked { choose(value) } } label: {
                    HStack(spacing: 6) {
                        if let icon { Icon(icon, size: 13) }
                        Text(label)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(on ? Theme.text : Theme.muted)
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.12))
                                .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
                        }
                    }
                    .opacity(locked && !on ? 0.35 : 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(AI.cardLine))
        .animation(.easeOut(duration: 0.2), value: selection)
    }
}

// MARK: - Callouts

private struct Callout<Content: View>: View {
    var bad = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content }
            .font(.system(size: 12.5))
            .lineSpacing(2)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((bad ? AI.red.opacity(0.08) : Color(hex: "#7c5cff").opacity(0.09)),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(bad ? AI.red.opacity(0.3) : AI.violet.opacity(0.3)))
    }
}

/// Over the internet needs Cloudflare's tunnel program once.
private struct SetupCallout: View {
    let agent: AgentController

    var body: some View {
        Callout {
            Label { Text("Get Cloudflare’s tunnel once") } icon: { Icon("download", size: 15) }
                .font(.system(size: 13, weight: .semibold))
            Text("Over the internet, your Mac is reached through Cloudflare’s free quick tunnel (`cloudflared`, about 20 MB, from Cloudflare’s GitHub). No Cloudflare account is needed.")
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if !agent.tunnelError.isEmpty { Text(agent.tunnelError).foregroundStyle(Color(hex: "#ff8a80")) }
            HStack(spacing: 10) {
                Button { agent.installTunnel() } label: {
                    HStack(spacing: 8) {
                        if agent.tunnelDownloading {
                            ProgressView().controlSize(.small).tint(.white)
                            Text("Downloading…")
                        } else {
                            Icon("download", size: 14)
                            Text("Download")
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 34)
                    .background(AI.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .opacity(agent.tunnelDownloading ? 0.6 : 1)
                }
                .buttonStyle(PressScale(scale: 0.97))
                .disabled(agent.tunnelDownloading)
                GhostButton(title: "Use this Mac only") { agent.start(reach: .local) }
            }
            .padding(.top, 6)
            Text("Or in Terminal: `brew install cloudflared`").foregroundStyle(Theme.faint).padding(.top, 2)
        }
    }
}

private struct ErrorCallout: View {
    let message: String

    var body: some View {
        Callout(bad: true) {
            Label { Text("AI Access stopped") } icon: { Icon("close", size: 15) }
                .font(.system(size: 13, weight: .semibold))
            Text(message).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - The link

private struct LinkCard: View {
    let agent: AgentController

    var body: some View {
        let local = agent.reach == .local
        AgentCard(icon: "key", title: "Your private link", tint: .link) {
            GhostButton(icon: "rotate", title: "New link", help: "Make a new link; the current one stops working") { agent.newLink() }
        } content: {
            HStack(spacing: 8) {
                LinkText(link: agent.link ?? "")
                CopyButton(text: agent.link)
            }
            .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 6)
            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.08)))
            HStack(spacing: 8) {
                // Assistants in the cloud cannot reach 127.0.0.1: on this Mac only, apps on the Mac are the audience.
                if !local {
                    ActionButton(icon: "chat", title: "Copy for a chat", done: "Copied") {
                        AI.copy("You can control my home with House Control. Open this private link and follow its instructions: \(agent.link ?? "")\n\n")
                    }
                }
                ActionButton(icon: "book", title: "Open the guide") { AI.open(agent.link) }
            }
            .padding(.top, 10)
            Group {
                if local {
                    Text("Only apps on this Mac can open it: Claude Code, Cursor, VS Code, LM Studio, your own scripts. See **Code & agents** below.")
                } else {
                    Text("Paste it into any assistant with your request — ") + Text("“turn off every light except the bedroom”").foregroundColor(Theme.text) + Text(".")
                }
            }
            .font(.system(size: 12)).lineSpacing(2)
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 11).padding(.horizontal, 2)
        }
    }
}

/// The link's address and the start of its secret: enough to recognise it, not to use it.
private struct LinkText: View {
    let link: String

    var body: some View {
        let url = URL(string: link)
        let host = url.map { u in [u.host, u.port.map { ":\($0)" }].compactMap { $0 }.joined() } ?? link
        let token = url?.pathComponents.dropFirst().first ?? ""
        HStack(spacing: 0) {
            Text(host).foregroundStyle(Color(hex: "#dfe4f5")).lineLimit(1).truncationMode(.middle)
            if !token.isEmpty { Text("/\(token.prefix(5))…").foregroundStyle(AI.lilac).fixedSize() }
        }
        .font(AI.mono)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}
