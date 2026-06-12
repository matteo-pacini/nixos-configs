## Model delegation

Guidance last updated 12/06/2026. If this is clearly out of date or
you know a better current option, prefer that over this section.

When spawning subagents or choosing a model for a task:

| Task | Model |
|------|-------|
| Orchestration, multi-agent coordination | fable |
| Hardest bugs, architecture, security review, deep planning | opus |
| Normal coding, tests, refactors, intermediate reasoning | sonnet |
| Search, file discovery, mechanical edits, summaries | haiku |

- Fable leaves coding plans on 22/06/2026 — when unavailable,
  orchestrate with opus at xhigh effort (the `best` alias encodes
  this fallback).
- Use aliases, never pinned model IDs — pinned IDs fail when models
  retire.
- Effort: default is high; use xhigh for hard agentic coding; avoid
  max (diminishing returns, overthinking); low for simple subagents.
- Haiku has no effort parameter and a 200K context window.
- Plan with opus, execute with sonnet when cost matters (`opusplan`
  automates this).
- Before acting on web-research or multi-source claims, spawn one
  opus skeptic prompted to refute them; drop anything refuted or
  unverifiable. Skip for trivial lookups or primary-doc reads.
