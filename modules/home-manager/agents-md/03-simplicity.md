## Simplicity first

These rules bias toward caution over speed; for trivial tasks, use
judgment.

- Write the minimum code that solves the problem; nothing speculative.
- No abstractions for single-use code, no configurability that wasn't
  asked for, no error handling for impossible scenarios.
- If 200 lines could be 50, rewrite it. If a senior engineer would
  call it overcomplicated, simplify.

## Surgical changes
- Touch only what the request requires; don't refactor or reformat
  adjacent code that isn't broken.
- Remove imports, variables, and functions that your change made
  unused — but don't delete pre-existing dead code; mention it instead.
- Every changed line should trace directly to the request.
