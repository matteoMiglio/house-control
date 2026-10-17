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
        Settings { EmptyView() }
    }
}
