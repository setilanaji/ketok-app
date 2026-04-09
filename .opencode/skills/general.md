# General Skill

## Git
- Conventional commits: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`.
- Small, focused PRs. One concern per PR.
- Squash merge to main.

## Code Style
- Format with the project's standard formatter.
- Prefer immutability and pure functions.
- Avoid deep inheritance; prefer composition.

## API Design
- RESTful resources, plural nouns, no verbs in paths.
- Versioned endpoints: `/v1/...`.
- Consistent error envelope: `{ "error": { "code", "message", "details" } }`.
- Idempotent PUT/DELETE.
- Pagination via `limit` + `cursor` (or `page`+`size`).
