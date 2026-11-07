# Merges the herdr hooks into Codex's ~/.codex/hooks.json (stdin to stdout).
# Each hook ends up exactly once per event, last; every other hook is kept, so
# running it again changes nothing.
.hooks //= {}
| reduce (
    { command: "herdr-codex-labels", timeout: 10, events: ["SessionStart", "Stop", "PostToolUse"] },
    # Codex fires Interrupt when a prompt is denied, PreModelRequest
    # when the model is asked again after one. 3 s: Codex clamps an
    # Interrupt hook to that, and trusts the clamped definition.
    { command: "herdr-agent-ask", timeout: 3, events: ["PermissionRequest", "PostToolUse", "UserPromptSubmit", "Interrupt", "PreModelRequest", "Stop"] }
  ) as $hook (.;
    reduce $hook.events[] as $event (.;
      .hooks[$event] = (
        (.hooks[$event] // [])
        | map(.hooks |= map(select(.command != $hook.command)) | select(.hooks != []))
      ) + [{ hooks: [{ type: "command", command: $hook.command, timeout: $hook.timeout }] }]))
