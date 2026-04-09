# iOS / Swift Skill

## Concurrency
- Prefer `async`/`await` over completion handlers and Combine where possible.
- Use `Task { }` correctly; avoid detached tasks unless required.
- Mark UI-touching code `@MainActor`.

## SwiftUI
- Small views; extract subviews instead of giant body blocks.
- `@State` for local, `@StateObject` for owned, `@ObservedObject` for injected.
- Stable `id` on `ForEach`.

## Memory
- Avoid retain cycles in closures: `[weak self]` where appropriate.
- Cancel Combine subscriptions; store in `Set<AnyCancellable>`.

## Patterns
- Protocol-oriented; depend on abstractions.
- No singletons for mutable state.
- Localizable strings via string catalogs.
