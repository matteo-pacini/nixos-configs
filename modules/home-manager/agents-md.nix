# Shared base for generated agent-instruction docs (CLAUDE.md / AGENTS.md).
# ============================================================================
# Holds the common instruction fragments consumed by BOTH the claude-code and
# opencode modules. Neither owns these — each specializes the shared base via
# `mkDoc`:
#
#   claude-code.nix:
#     mkDoc { afterRoleTone = [ "@RTK.md\n" ]; includeModelDelegation = true; }
#     → refines the base with the RTK include + the Claude model-dispatching
#       tier (04). Deployed to ~/.claude/CLAUDE.md.
#
#   opencode.nix:
#     mkDoc { afterSimplicity = [ <profile-specific steering> ]; }
#     → augments the base with per-profile data; no RTK (the rtk.ts plugin
#       rewrites bash transparently — the awareness prose is Claude-specific)
#       and no model-delegation (Claude model tiers, irrelevant to OpenRouter).
#       Deployed to <OPENCODE_CONFIG_DIR>/AGENTS.md.
#
# Fragment cascade (general → specific); see the repo CLAUDE.md for rationale:
#   01 role/tone → 02 working-on-code → 03 simplicity → [04 model-delegation]
#   → 05 git → 06 non-negotiables. Injection points: `afterRoleTone` (after 01)
#   and `afterSimplicity` (after 03/04).
{ lib }:
let
  dir = ./agents-md;
  frag = name: builtins.readFile (dir + "/${name}");
in
{
  mkDoc =
    {
      afterRoleTone ? [ ],
      afterSimplicity ? [ ],
      includeModelDelegation ? false,
    }:
    lib.concatStringsSep "\n" (
      [ (frag "01-role-tone.md") ]
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
