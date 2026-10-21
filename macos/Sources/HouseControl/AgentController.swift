import AppKit
import Observation
import WebKit
import HouseCore

/// AI Access: a private link that lets an AI assistant (ChatGPT, Claude, an MCP client…)
/// see and run the home, served from this Mac.
///
///     AI ─HTTPS─▶ Cloudflare quick tunnel ─▶ cloudflared on this Mac ─▶ 127.0.0.1 gateway ─▶ the panel's store
///
/// Off until the user starts it. Every start makes a new secret link; Stop (or the auto-stop
/// timer) closes the gateway and the tunnel, and the old address stops existing.
///
/// The AI Access screen (Agent/AgentView.swift) reads what it shows from here.
@MainActor
@Observable
final class AgentController: NSObject, AgentBackend {
    enum Reach: String { case internet, local }
    enum Phase: Equatable { case off, starting, live, failed(String) }

    @ObservationIgnored let gateway = AgentGateway()
    @ObservationIgnored private lazy var server = LoopbackHTTPServer { [unowned self] request in await self.gateway.handle(request) }
    @ObservationIgnored private let tunnel: CloudflareTunnel
    @ObservationIgnored private let plans: PlanStore
    /// The panel runs every request: it holds the state of each device.
    @ObservationIgnored private let panel: () -> WebHost
    /// Reloads every view after the plan changed (and tells paired iPhones).
    @ObservationIgnored private let reloadAll: () -> Void
    @ObservationIgnored var onLiveChange: ((Bool) -> Void)?

    private(set) var phase: Phase = .off
    /// What assistants read and did, oldest first (the last 200).
    private(set) var activity: [AgentActivity] = []
    /// What the plan was before each change an AI made, newest last.
    @ObservationIgnored private var history: [(data: Data?, active: String)] = []
    /// An AI's change to the plan can be undone.
    private(set) var canUndo = false
    private(set) var startedAt: Date?
    private(set) var stopsAt: Date?
    @ObservationIgnored private var stopTimer: Timer?
    /// While live: the private link, and the same for MCP clients.
    private(set) var link: String?
    private(set) var mcp: String?
    /// Cloudflare's tunnel program: being downloaded, or what went wrong getting it.
    private(set) var tunnelDownloading = false
    private(set) var tunnelError = ""

    @ObservationIgnored private let defaults = UserDefaults.standard
    /// Over the internet (through Cloudflare) or for apps on this Mac only.
    private(set) var reach: Reach {
        didSet { defaults.set(reach.rawValue, forKey: "agent.reach") }
    }
    /// "1h", "8h" or "never".
    private(set) var autoStop: String {
        didSet { defaults.set(autoStop, forKey: "agent.autoStop") }
    }
    private(set) var permissions: AgentPermissions {
        didSet {
            defaults.set(permissions.control, forKey: "agent.control")
            defaults.set(permissions.edit, forKey: "agent.edit")
            gateway.permissions = permissions
        }
    }

    init(plans: PlanStore, panel: @escaping () -> WebHost, reloadAll: @escaping () -> Void) {
        self.plans = plans
        self.panel = panel
        self.reloadAll = reloadAll
        tunnel = CloudflareTunnel(directory: plans.directory)
        // HOUSE_AGENT_REACH=local|internet overrides the saved choice for one run (tests).
        reach = Reach(rawValue: ProcessInfo.processInfo.environment["HOUSE_AGENT_REACH"] ?? defaults.string(forKey: "agent.reach") ?? "") ?? .internet
        autoStop = defaults.string(forKey: "agent.autoStop") ?? "8h"
        permissions = AgentPermissions(control: defaults.object(forKey: "agent.control") as? Bool ?? true,
                                       edit: defaults.object(forKey: "agent.edit") as? Bool ?? true)
        super.init()
        gateway.backend = self
        gateway.permissions = permissions
        gateway.onActivity = { [weak self] entry in self?.log(entry) }
        tunnel.onChange = { [weak self] state in self?.tunnelChanged(state) }
        push()
    }

    var isLive: Bool { phase == .live }

    // MARK: - Start and stop

    /// Starts the link, over `reach` when given (the screen's switch, or "Use this Mac only").
    func start(reach new: Reach? = nil) {
        if let new, phase != .live, phase != .starting { reach = new }
        switch phase {
        case .starting, .live: return
        default: break
        }
        if reach == .internet, tunnel.binary == nil {
            phase = .failed("needs-cloudflared")
            push()
            return
        }
        gateway.rotateToken()
        gateway.permissions = permissions
        phase = .starting
        tunnelError = ""
        push()
        server.start(preferredPort: 7419) { [weak self] result in
            guard let self, self.phase == .starting else { return }
            switch result {
            case .success(let port):
                if self.reach == .local {
                    self.gateway.publicBase = "http://127.0.0.1:\(port)"
                    self.goLive()
                } else {
                    self.tunnel.start(port: port)
                }
            case .failure(let error):
                self.fail("The local server could not start: \(error.localizedDescription)")
            }
        }
    }

    private func tunnelChanged(_ state: CloudflareTunnel.State) {
        switch state {
        case .live(let url):
            guard phase == .starting else { return }
            gateway.publicBase = url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            goLive()
        case .failed(let message):
            guard phase == .starting || phase == .live else { return }
            fail(message)
        case .starting, .stopped:
            break
        }
    }

    private func goLive() {
        phase = .live
        startedAt = Date()
        scheduleAutoStop()
        log(AgentActivity(date: Date(), client: "House Control", title: reach == .local ? "Started on this Mac" : "Link is live", ok: true, quiet: false))
        onLiveChange?(true)
        push()
        // HOUSE_AGENT_LINK_FILE=<path> writes the live link there, for scripted tests.
        if let path = ProcessInfo.processInfo.environment["HOUSE_AGENT_LINK_FILE"] {
            try? gateway.linkURL.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    private func fail(_ message: String) {
        let wasLive = phase == .live
        tunnel.stop()
        server.stop()
        stopTimer?.invalidate()
        phase = .failed(message)
        if wasLive { onLiveChange?(false) }
        push()
    }

    func stop(reason: String = "Stopped") {
        guard phase != .off else { return }
        let wasLive = phase == .live
        tunnel.stop()
        server.stop()
        stopTimer?.invalidate()
        stopTimer = nil
        stopsAt = nil
        startedAt = nil
        phase = .off
        link = nil
        mcp = nil
        gateway.rotateToken() // the old link is dead even if the same address came back
        if wasLive {
            log(AgentActivity(date: Date(), client: "House Control", title: "\(reason) — the link no longer works", ok: true, quiet: false))
            onLiveChange?(false)
        }
        push()
    }

    private func scheduleAutoStop() {
        stopTimer?.invalidate()
        stopTimer = nil
        let hours: Double? = ["1h": 1, "8h": 8][autoStop]
        guard let hours, let startedAt else { stopsAt = nil; return }
        let when = startedAt.addingTimeInterval(hours * 3600)
        stopsAt = when
        stopTimer = Timer.scheduledTimer(withTimeInterval: max(1, when.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop(reason: "Stopped automatically") }
        }
    }

    private func log(_ entry: AgentActivity) {
        activity.append(entry)
        if activity.count > 200 { activity.removeFirst(activity.count - 200) }
        push()
    }

    // MARK: - Requests from the AI (AgentBackend)

    func agentRequest(_ request: [String: Any]) async throws -> [String: Any] {
        let host = try await readyPanel()
        let raw = try await host.webView.callAsyncJavaScript("return await window.house.agent(request)",
                                                             arguments: ["request": request], contentWorld: .page)
        guard let text = raw as? String, let data = text.data(using: .utf8),
              var result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentError("House Control did not understand the request.")
        }
        if let plan = result["savePlan"] as? [String: Any] {
            result["savePlan"] = nil
            do {
                try savePlan(plan)
            } catch {
                result = ["content": [["type": "text", "text": "Error: \(error.localizedDescription)"]], "isError": true,
                          "summary": "Floor plan not saved: \(error.localizedDescription)"]
            }
        }
        if result["undo"] as? Bool == true {
            result["undo"] = nil
            do {
                try undo()
                result["content"] = [["type": "text", "text": "Undone: the floor plan is back to how it was before the last change. The 3D model is updating."]]
            } catch {
                result = ["content": [["type": "text", "text": "Error: \(error.localizedDescription)"]], "isError": true, "summary": error.localizedDescription]
            }
        }
        return result
    }

    /// The panel page, once it has (re)loaded: a request that arrives while the plan is
    /// being swapped waits for the new one.
    private func readyPanel() async throws -> WebHost {
        for _ in 0..<150 {
            let host = panel()
            if host.isReady { return host }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw AgentError("House Control is busy loading the home. Try again in a moment.")
    }

    private func savePlan(_ plan: [String: Any]) throws {
        if plans.activePlan != "custom", plans.hasCustomPlan {
            throw AgentError("The user is looking at a demo plan, and their own home is saved separately. Ask them to switch to \"My home\" (gear menu in the panel) first.")
        }
        let previous = plans.hasCustomPlan ? try? Data(contentsOf: plans.customPlanURL) : nil
        let previousActive = plans.activePlan
        try plans.saveCustom(plan)
        history.append((previous, previousActive))
        if history.count > 30 { history.removeFirst() }
        reloadAll()
        push()
    }

    func undo() throws {
        guard let last = history.popLast() else { throw AgentError("There is no floor plan change to undo.") }
        if let data = last.data {
            try plans.saveCustom(data: data, select: true)
        } else {
            plans.removeCustom()
            plans.select(last.active)
        }
        reloadAll()
        log(AgentActivity(date: Date(), client: "House Control", title: "Undid the last floor plan change", ok: true, quiet: false))
    }

    // MARK: - The screen

    /// A new link: the current one stops working.
    func newLink() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.start() }
    }

    func setReach(_ new: Reach) {
        guard phase != .live, phase != .starting else { return }
        reach = new
    }

    func setControl(_ on: Bool) { permissions.control = on }
    func setEdit(_ on: Bool) { permissions.edit = on }

    /// "1h", "8h" or "never"; a live link's timer starts over from when it went live.
    func setAutoStop(_ value: String) {
        guard ["1h", "8h", "never"].contains(value) else { return }
        autoStop = value
        if phase == .live { scheduleAutoStop() }
    }

    /// Undo home edit: what went wrong lands in the feed.
    func undoFromScreen() {
        do { try undo() } catch {
            log(AgentActivity(date: Date(), client: "House Control", title: error.localizedDescription, ok: false, quiet: false))
        }
    }

    /// Downloads Cloudflare's tunnel program, once.
    func installTunnel() {
        guard !tunnelDownloading, !tunnel.isDownloading else { return }
        tunnelError = ""
        tunnelDownloading = true
        Task { @MainActor in
            do {
                try await tunnel.download()
                if case .failed("needs-cloudflared") = phase { phase = .off }
            } catch {
                tunnelError = error.localizedDescription
            }
            tunnelDownloading = false
            push()
        }
    }

    struct AgentError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    /// Brings what the screen shows from the tunnel and the gateway up to date.
    private func push() {
        canUndo = !history.isEmpty
        link = phase == .live ? gateway.linkURL : nil
        mcp = phase == .live ? gateway.mcpURL : nil
    }
}
