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
        // The app's window is an AppKit window hosting SwiftUI (see MainWindowController) and its
        // menu bar icon an AppKit status item. An App still needs a scene: this one is never put in
        // the menu bar, so it makes no window (an empty Settings scene opened one at launch), and
        // it gives the app menu its Settings… item, which opens the window on Settings.
        MenuBarExtra("House Control", systemImage: "house", isInserted: .constant(false)) { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { delegate.model.router.show(.settings) }.keyboardShortcut(",")
                }
            }
    }
}
