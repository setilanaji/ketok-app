# Performance Rules

## Memory
- Large allocations inside hot loops → hoist out or reuse buffers.
- Missing cleanup: unclosed streams, files, sockets, observers, listeners.
- Unbounded collections / caches without eviction.
- Retain cycles (closures capturing self, event listeners not removed).

## Network / Database
- N+1 query patterns → use joins, batch loads, or DataLoader.
- Missing pagination on list endpoints.
- Missing timeouts on HTTP / DB calls.
- Synchronous network calls on UI / request threads.
- Missing retry/backoff on idempotent calls where appropriate.

## UI / Main Thread
- Heavy computation on main/UI thread → move to background.
- Unnecessary recomposition / re-renders (missing memoization, unstable keys).
- Layout thrashing, large image decode on main thread.

## Algorithms
- Flag O(n²) or worse when O(n log n) or O(n) is feasible.
- Flag unnecessary repeated work that could be cached.
