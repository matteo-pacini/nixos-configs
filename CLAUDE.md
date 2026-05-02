@AGENTS.md

## Vendored Claude Code CLAUDE.md

`~/.claude/CLAUDE.md` is a managed symlink — never edit it directly. The
deployed file is assembled in `modules/home-manager/claude-code.nix` by
concatenating fragments from
`modules/home-manager/claude-code/claude-md/` in numeric order, with
`@RTK.md` injected between fragments 01 and 02. To change a section,
edit the matching fragment:

- `01-role-tone.md` — role, tone, confidence
- `02-working-on-code.md` — workflow, output format
- `03-git.md` — git/PR rules
- `04-non-negotiables.md` — short list of never-dos

### Recommended order (don't break this)

The fragments cascade from general framing to specific reinforcement.
Each layer narrows the one below it, so reordering changes how the model
weights conflicts:

```
1. ROLE / TONE / COMMUNICATION   ← frames everything below
        ↓
2. RTK.md INCLUSION              ← stable global token-efficiency rules
        ↓
3. WORKING ON CODE / OUTPUT      ← specific workflow guidance
        ↓
4. GIT GUIDANCE                  ← workflow specialization for VCS
        ↓
5. NON-NEGOTIABLES (short)       ← final reinforcement, 2–4 lines
```

When adding a new section, slot it where it fits this hierarchy rather
than appending blindly. Reuse an existing fragment if the topic
overlaps; create a new numbered fragment only for a genuinely new
layer, and add a `builtins.readFile` line in the `concatStringsSep`
list in `modules/home-manager/claude-code.nix`. `RTK.md` lives
alongside the fragments and is deployed separately to `~/.claude/RTK.md`.
