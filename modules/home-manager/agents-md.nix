# Shared instruction-doc base for claude-code (CLAUDE.md) and opencode (AGENTS.md).
# Both consume mkDoc and specialize via its params:
#   claude-code: mkDoc { afterRoleTone = [ "@RTK.md\n" ]; includeModelDelegation = true; }
#   opencode:    mkDoc { needsRtkPrompt = true; afterSimplicity = profile.steering; }
# Two RTK prompts because the integrations differ: Claude Code's hook rewrites
# commands INVISIBLY (uses upstream's RTK.md via the @RTK.md include), opencode's
# plugin rewrites them VISIBLY (uses the rtkPrompt below). model-delegation (04)
# is Claude-only. Editing a fragment changes both docs — keep them tool-neutral.
{ lib }:
let
  dir = ./agents-md;
  frag = name: builtins.readFile (dir + "/${name}");

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
