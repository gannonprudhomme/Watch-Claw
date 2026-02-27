import ComposableArchitecture
import Logging
import SwiftUI

@main
struct WatchClawApp: App {
    static let store: StoreOf<AppReducer> = Store(initialState: AppReducer.State()) {
        AppReducer()
    }

    init() {
        LoggingSystem.bootstrap(LoggingOSLog.init)
    }

    var body: some Scene {
        WindowGroup {
            AppView(store: Self.store)
        }
    }
}
