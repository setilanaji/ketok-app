# Android / Kotlin Skill

## Architecture
- MVVM with unidirectional data flow.
- ViewModel exposes `StateFlow<UiState>`; UI is a function of state.
- Repositories abstract data sources; no Android types in domain layer.

## DI
- Hilt for DI. Scope wisely (`@Singleton`, `@ViewModelScoped`).
- No `Context` leaks; never hold Activity references in ViewModels.

## Compose
- Stateless, hoisted composables. Pass state down, events up.
- Use `remember` / `rememberSaveable` correctly.
- Stable parameters; avoid lambdas recreated each recomposition (use `remember { }`).
- `LazyColumn` keys for stable identity.

## Coroutines
- Structured concurrency: tie scopes to lifecycle.
- Use `Dispatchers.IO` for I/O, `Default` for CPU work.
- Cancel on lifecycle stop; avoid `GlobalScope`.

## ProGuard / R8
- Keep rules for reflection-based libs (Gson, Moshi, Retrofit models).
- Verify release builds run without crashes.
