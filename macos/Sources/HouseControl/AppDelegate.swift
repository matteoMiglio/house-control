import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // Started by macOS as a login item: the app comes up in the menu bar only.
        let event = NSAppleEventManager.shared().currentAppleEvent
        model.launchedAtLogin = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    /// A click on the Dock icon (or opening the app again) brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.router.show(.home)
        return true
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
