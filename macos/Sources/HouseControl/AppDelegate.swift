import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Menu bar only: HOUSE_DOCK=1 shows a Dock icon for UI automation.
        NSApp.setActivationPolicy(ProcessInfo.processInfo.environment["HOUSE_DOCK"] != nil ? .regular : .accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        stopTunnelOnSignals()
        model.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        model.open(urls: urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        model.agent.stop(reason: "House Control quit")
    }

    /// `kill`, a logout or Ctrl-C end the app without applicationWillTerminate: the AI
    /// Access tunnel must not outlive it.
    private var signalSources: [DispatchSourceSignal] = []
    private func stopTunnelOnSignals() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.model.agent.stop(reason: "House Control quit") }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
