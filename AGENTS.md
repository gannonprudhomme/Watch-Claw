# AGENTS.md

## Project Overview

WatchClaw is a watchOS app with an iOS companion. The primary target is the Apple Watch app.

**Tech Stack:**
- Swift 6.2, watchOS 26+, iOS 26+
- SwiftUI
- The Composable Architecture (TCA) for state management
- swift-log for logging

## Architecture

### The Composable Architecture (TCA)

Every feature follows the TCA pattern:

```swift
@Reducer
struct MyFeature: Reducer, Sendable {
    @ObservableState
    struct State { ... }
    enum Action { ... }

    @Dependency(\.someClient) var client

    var body: some ReducerOf<Self> {
        Reduce { state, action in /* handle actions, return effects */ }
    }
}
```

**Key concepts:** `@Reducer`, `@ObservableState`, `@Dependency` for DI, `Scope` for composition, `StackState`/`@Presents` for navigation, `.run`/`.task` for async effects

**Rules:**
- Use `@Dependency` for all external dependencies
- Do not reuse reducer behavior by sending actions from within the reducer body. Reuse via reducer helper functions, and only send actions from inside `Effect.run` when necessary.
- Use `reportIssue(...)` for impossible/programmer-error states rather than logger errors.

## Swift 6.2 Concurrency

Uses strict concurrency: mark all types as `Sendable`, use `@concurrent` for async closures, use `LockIsolated` for thread-safe mutable state.

## Building & Testing

The project uses **Bazel** as its build system.

- When first compiling a task or iterating on something, ALWAYS scope checks to the module you're editing.
  - If you need to both build and test, run only `test` because `bazel test` already builds the target.
  - Then run all tests once you're wrapping up the task.

Use `bazel-run.sh` for builds and tests — it wraps Bazel with minimal output optimized for LLM context windows:
- Success: single line (`BUILD SUCCEEDED` or `TESTS PASSED (N targets)`)
- Failure: shows only compile errors or test failure details

**Build the watchOS app:**

`./bazel-run.sh build //:WatchClaw`

**Build the iOS companion:**

`./bazel-run.sh build //:WatchClawPhone`

**Run all tests:**

`./bazel-run.sh test //...`

**Generate Xcode project** (for IDE support — autocomplete, previews, debugging):

`./bazel-run.sh xcodeproj`

### Formatting

The project uses `nicklockwood/SwiftFormat` with a `.swiftformat` config at the repo root.

### Deploying to Device

Use `deploy.sh` to build and install to a physical Apple Watch or iPhone:

```bash
./deploy.sh              # Debug build (watchOS)
./deploy.sh --release    # Optimized release build (-O)
./deploy.sh //:WatchClawPhone  # Deploy iOS companion
```

The device ID is read from `~/.config/watchclaw/device_id` or the `WATCHCLAW_DEVICE_ID` env var. Find your device ID with `xcrun devicectl list devices`.

## Code Style

- Use `.isNotEmpty` instead of `!collection.isEmpty` for collection non-empty checks.
- In SwiftUI, do not use padding in the same direction as a parent stack for inter-item spacing; use stack `spacing`, or nest stacks when spacing should apply to only part of the row.

## Key Files

**Start Here:**
- `WatchClaw/WatchClawApp.swift` - watchOS app entry point
- `WatchClaw/AppReducer.swift` - Root reducer
- `WatchClawPhone/WatchClawPhoneApp.swift` - iOS companion entry point

## Do's and Don'ts

### Do:
- Use `@Dependency` for all external dependencies
- Mark all types as `Sendable`
- Follow existing module patterns

### Don't:
- Create non-Sendable types
- Mix UIKit patterns (this is SwiftUI-only)

## Logging

Define logger extensions (`Logger.myFeature`) and use `logger.info()`, `logger.error()`, etc.

## Dependencies

Key packages:
- `swift-composable-architecture` - State management (TCA)
- `swift-dependencies` - Dependency injection
- `swift-log` - Logging
