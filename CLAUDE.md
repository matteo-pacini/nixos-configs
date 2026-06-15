@AGENTS.md

## Vendored Claude Code CLAUDE.md

`~/.claude/CLAUDE.md` is a managed symlink — never edit it directly. The
instruction fragments are shared: they live in
`modules/home-manager/agents-md/` and are assembled by the `mkDoc`
generator in `modules/home-manager/agents-md.nix`, which is consumed by
**both** the claude-code and opencode modules. `claude-code.nix` refines
the base with the `@RTK.md` include (after fragment 01) and the
model-delegation tier (04); `opencode.nix` opts into a *different* RTK
prompt via `needsRtkPrompt` (the integrations differ — see below) and
drops model-delegation. To change a section, edit the matching fragment in
`modules/home-manager/agents-md/`:

- `01-role-tone.md` — role, tone, confidence
- `02-working-on-code.md` — workflow, output format
- `03-simplicity.md` — simplicity & surgical-change discipline
- `04-model-delegation.md` — model/effort choice for subagents & tasks
- `05-git.md` — git/PR rules
- `06-non-negotiables.md` — short list of never-dos

### Recommended order (don't break this)

The fragments cascade from general framing to specific reinforcement.
Each layer narrows the one below it, so reordering changes how the model
weights conflicts:

```
1. ROLE / TONE / COMMUNICATION   ← frames everything below
        ↓
2. RTK AWARENESS PROMPT          ← rtk shell-rewrite awareness (opt-in)
        ↓
3. WORKING ON CODE / OUTPUT      ← specific workflow guidance
        ↓
4. SIMPLICITY / SURGICAL        ← narrows how code changes are made
        ↓
5. MODEL DELEGATION              ← which model/effort per task tier
        ↓
6. GIT GUIDANCE                  ← workflow specialization for VCS
        ↓
7. NON-NEGOTIABLES (short)       ← final reinforcement, 2–4 lines
```

When adding a new section, slot it where it fits this hierarchy rather
than appending blindly. Reuse an existing fragment if the topic overlaps;
create a new numbered fragment only for a genuinely new layer, and weave
it into the `mkDoc` cascade in `modules/home-manager/agents-md.nix`
(shared by both consumers) — or, if it's tool-specific, inject it via the
`afterRoleTone` / `afterSimplicity` hooks from `claude-code.nix` or
`opencode.nix`. The two modules use *different* RTK prompts on purpose:
Claude's hook rewrites invisibly, so claude-code `@`-includes upstream's
`RTK.md` (in `modules/home-manager/claude-code/`, deployed to
`~/.claude/RTK.md`); OpenCode's plugin rewrites visibly, so opencode opts
into the `rtkPrompt` fragment in `agents-md.nix` via `needsRtkPrompt`. The
rtk *executables* (the Claude `rtk-rewrite.sh` hook and the OpenCode
`rtk.ts` plugin) and `RTK.md` are vendored and refreshed by
`modules/home-manager/update-rtk.sh`.
