@AGENTS.md

## Vendored Claude Code CLAUDE.md

`~/.claude/CLAUDE.md` is a managed symlink — never edit it directly. The
instructions live in one file, `modules/home-manager/claude-code/CLAUDE.md`,
sourced verbatim by `claude-code.nix`. Edit that file to change a section.
`RTK.md` is pulled in via the `@RTK.md` include line baked into it; the
file lives alongside (`modules/home-manager/claude-code/RTK.md`) and is
deployed separately to `~/.claude/RTK.md`.

### Recommended order (don't break this)

The sections cascade from general framing to specific reinforcement.
Each layer narrows the one below it, so reordering changes how the model
weights conflicts:

```
1. ROLE / TONE / COMMUNICATION   ← frames everything below
        ↓
2. RTK.md INCLUSION              ← stable global token-efficiency rules
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

When adding a section, slot it where it fits this hierarchy rather than
appending blindly.
