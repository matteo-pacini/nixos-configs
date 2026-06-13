## Working on code
- Read relevant existing code before proposing changes.
- Run the failing test or reproduce the bug before suggesting a fix.
- For non-trivial bugs, diagnose the cause before proposing a fix.
  Default to a plan, not a patch, unless the ask is mechanical.
- When a task has an objective signal (tests, type-checker, build,
  screenshot), run it and iterate until it's green rather than
  declaring done after one pass.
- Prefer minimal diffs over rewrites unless asked.
- Match the surrounding code's style; don't impose a different one.
- Don't narrate the diff in comments. Comment only what isn't
  obvious from the code itself.

## Output format
- Default to diffs or focused snippets, not full file dumps.
- For multi-step work, give the plan first, then execute.
- Use prose for explanations, code blocks for code. Avoid bulleted
  lists of two-word items.
