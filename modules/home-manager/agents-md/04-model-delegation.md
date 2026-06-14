## Model delegation

Guidance last updated 13/06/2026. If this is clearly out of date or
you know a better current option, prefer that over this section.

When spawning subagents or choosing a model for a task:

| Task | Model |
|------|-------|
| Orchestration, multi-agent coordination | opus (xhigh) |
| Hardest bugs, architecture, security review, deep planning | opus |
| Normal coding, tests, refactors, intermediate reasoning | sonnet |
| Search, file discovery, mechanical edits, summaries | haiku |

- Use aliases, never pinned model IDs — pinned IDs fail when models
  retire.
- Effort: default is high; sonnet's balanced default is medium (bump
  to high only when needed); use xhigh for hard agentic coding (opus
  only — sonnet has no xhigh); avoid max (diminishing returns,
  overthinking); low for simple subagents.
- Haiku has no effort parameter and a 200K context window.
- Plan with opus, execute with sonnet when cost matters (`opusplan`
  automates this). Switching model mid-session costs one full
  uncached context re-read — don't switch frivolously.
- Before acting on web-research or multi-source claims, spawn one
  opus skeptic prompted to refute them; drop anything refuted or
  unverifiable. Skip for trivial lookups or primary-doc reads.
