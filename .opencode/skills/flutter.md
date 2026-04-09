# Flutter Skill

## State Management
- BLoC or Riverpod (project standard). No mixing without justification.
- Keep widgets stateless when possible; lift state to providers.

## Widgets
- Extract widgets when build methods exceed ~60 lines.
- Use `const` constructors aggressively.
- Provide stable `Key`s in lists.

## Null Safety
- No `!` force-unwrap unless justified by a comment.
- Prefer `??`, `?.`, and pattern matching.

## Performance
- Avoid rebuilding large subtrees; use `Selector`/`select`.
- Use `ListView.builder` for long lists.
- Cache decoded images; size them to display dimensions.
