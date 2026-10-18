import SwiftUI
import HouseSmartLife

@main
struct HouseControlApp: App {
    @NSApplicationDelegateAdaptor var delegate: AppDelegate

    init() {
        // Self-tests print their result and exit without starting the app or its delegate.
        SelfTest.runIfRequested()
        _delegate = NSApplicationDelegateAdaptor(AppDelegate.self)
    }

    var body: some Scene {
        // The app's windows are AppKit windows hosting SwiftUI (see MainWindowController); this
        // scene is only here to give the app menu its Settings… item, which opens one of them.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { delegate.model.router.show(.settings) }.keyboardShortcut(",")
                }
            }
    }
}
