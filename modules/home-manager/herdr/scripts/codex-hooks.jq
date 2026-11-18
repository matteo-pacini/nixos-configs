# Merges the herdr hooks into Codex's ~/.codex/hooks.json (stdin to stdout).
# $labels and $ask (--arg) are the commands of herdr-codex-labels and
# herdr-agent-ask as they are to be written.
# Each hook ends up exactly once per event, last. An earlier entry of ours is
# replaced whatever its command's directory, or none: any command whose last
# path component is the hook's name. Every other hook is kept, so running it
# again changes nothing.
def base: sub("^.*/"; "");
def ours($name): .command | type == "string" and base == $name;
.hooks //= {}
| reduce (
    { command: $labels, timeout: 10, events: ["SessionStart", "Stop", "PostToolUse"] },
    # Codex fires Interrupt when a prompt is denied, PreModelRequest
    # when the model is asked again after one. 3 s: Codex clamps an
    # Interrupt hook to that, and trusts the clamped definition.
    { command: $ask, timeout: 3, events: ["PermissionRequest", "PostToolUse", "UserPromptSubmit", "Interrupt", "PreModelRequest", "Stop"] }
  ) as $hook (.;
    ($hook.command | base) as $name
    | reduce $hook.events[] as $event (.;
      .hooks[$event] = (
        (.hooks[$event] // [])
        | map(.hooks |= map(select(ours($name) | not)) | select(.hooks != []))
      ) + [{ hooks: [{ type: "command", command: $hook.command, timeout: $hook.timeout }] }]))
