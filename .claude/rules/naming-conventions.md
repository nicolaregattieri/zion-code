# Naming Conventions

## Magic Numbers
- Extract numeric literals into named constants when they appear in logic.
- Timing values (nanoseconds, milliseconds) → `Constants.Timing.*`
- Limits (max counts, buffer sizes, truncation lengths) → `Constants.Limits.*`
- AI token budgets → `AILimits.*` (private to AIClient)
- Exception: SwiftUI layout values (`.padding(8)`, `.frame(width: 200)`) may remain inline.
- Exception: Artistic/geometric constants (Bezier control points, shape coordinates) may remain inline.

## Variables
- No single-letter variables outside trivial closures or loop counters (`i`, `j`).
- `$0` is acceptable in short single-expression closures (Swift convention).
- Boolean parameters should read as questions: `shouldHardReset`, `shouldPop`, `shouldOpenConflictResolver`.

## Shared Separators
- Use `Constants.gitFieldSeparator` / `Constants.gitFieldSeparatorString` instead of inline `0x1F` / `Character(UnicodeScalar(0x1F)!)`.

## Duplicated Literals
- If the same literal appears 3+ times, extract it into a named constant.
