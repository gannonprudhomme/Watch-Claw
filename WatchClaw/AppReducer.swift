import ComposableArchitecture
import SwiftUI

@Reducer
struct AppReducer: Sendable {
    @ObservableState
    struct State {
        init() { }
    }

    enum Action {
        case task
    }

    init() { }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                return .none
            }
        }
    }
}

struct AppView: View {
    let store: StoreOf<AppReducer>

    var body: some View {
        NavigationStack {
            Text("WatchClaw")
                .task {
                    await store.send(.task).finish()
                }
        }
    }
}

#Preview {
    AppView(
        store: Store(initialState: AppReducer.State()) {
            AppReducer()
        }
    )
}
