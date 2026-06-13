# Shared base for generated agent-instruction docs (CLAUDE.md / AGENTS.md).
# ============================================================================
# Holds the common instruction fragments consumed by BOTH the claude-code and
# opencode modules. Neither owns these — each specializes the shared base via
# `mkDoc`:
#
#   claude-code.nix:
#     mkDoc { afterRoleTone = [ "@RTK.md\n" ]; includeModelDelegation = true; }
#     → base + the upstream RTK awareness doc (via @RTK.md, after 01) + the
#       Claude model-dispatching tier (04). Deployed to ~/.claude/CLAUDE.md.
#
#   opencode.nix:
#     mkDoc { needsRtkPrompt = true; afterSimplicity = [ <profile steering> ]; }
#     → base + the rtkPrompt fragment (after 01) + per-profile data; no
#       model-delegation. Deployed to <OPENCODE_CONFIG_DIR>/AGENTS.md.
#
# Why two different RTK prompts, not one shared fragment: the integrations
# differ. Claude Code's hook rewrites commands INVISIBLY (the agent never sees
# `rtk`), so it uses upstream's `rtk-awareness.md` via @RTK.md — auto-refreshed
# and legitimately Claude-specific (e.g. `rtk discover`). OpenCode's plugin
# mutates the command in place, so the model DOES see `rtk`-prefixed commands
# and the `--- Changes ---` output; `rtkPrompt` below tells it that's expected.
# The upstream doc is neither tool-neutral nor covers the visible-rewrite case.
#
# Fragment cascade (general → specific); see the repo CLAUDE.md for rationale:
#   01 role/tone → [RTK] → 02 working-on-code → 03 simplicity →
#   [04 model-delegation] → 05 git → 06 non-negotiables. Injection points:
#   `afterRoleTone` (after 01/RTK) and `afterSimplicity` (after 03/04).
{ lib }:
let
  dir = ./agents-md;
  frag = name: builtins.readFile (dir + "/${name}");

  # RTK awareness for tools whose rewrite is VISIBLE to the model (opencode's
  # plugin). Claude Code's hook is invisible, so it uses upstream rtk-awareness
  # via @RTK.md instead — see header.
  rtkPrompt = ''
    ## RTK — token-optimized shell

    A plugin automatically routes your shell commands through `rtk`, a
    token-saving proxy — e.g. it runs `git status` as `rtk git status` (60-90%
    fewer tokens on dev commands). You WILL see this: `rtk` prepended to your
    commands, and compact results under a `--- Changes ---` header, are
    EXPECTED and correct. Do not strip `rtk`, treat it as an error, or re-run
    the raw command to bypass it.

    Run these directly (not auto-rewritten):
    - `rtk gain` — token-savings stats
    - `rtk proxy <cmd>` — run a command raw, without rewriting (for debugging)
  '';
in
{
  inherit rtkPrompt;

  mkDoc =
    {
      afterRoleTone ? [ ],
      afterSimplicity ? [ ],
      includeModelDelegation ? false,
      needsRtkPrompt ? false,
    }:
    lib.concatStringsSep "\n" (
      [ (frag "01-role-tone.md") ]
      ++ lib.optional needsRtkPrompt rtkPrompt
      ++ afterRoleTone
      ++ [
        (frag "02-working-on-code.md")
        (frag "03-simplicity.md")
      ]
      ++ lib.optional includeModelDelegation (frag "04-model-delegation.md")
      ++ afterSimplicity
      ++ [
        (frag "05-git.md")
        (frag "06-non-negotiables.md")
      ]
    );
}
