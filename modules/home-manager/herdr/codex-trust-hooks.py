"""Marks herdr's own Codex hooks as trusted, so Codex runs them without its
"Hooks need review" screen after every change to hooks.json.

Usage: codex-trust-hooks.py HOOKS_JSON CONFIG_TOML COMMAND...

For each hook in HOOKS_JSON whose command is one of COMMAND, writes the
`trusted_hash` Codex itself records when you trust a hook (/hooks) into
CONFIG_TOML's `[hooks.state]`, leaving every other key and hook as it is.
The hash mirrors codex-rs (rust-v0.164.0): `hook_hash` in
hooks/src/engine/discovery.rs serialises the event label and the hook's
matcher group, reduced to that one handler, and `version_for_toml` in
config/src/fingerprint.rs takes the SHA-256 of it as compact JSON with
sorted keys. If a Codex release changes that, the entries stop matching and
Codex asks again; nothing else breaks.
"""

import hashlib
import json
import re
import sys
from pathlib import Path

import tomlkit

hooks_path, config_path, *ours = sys.argv[1:]
hooks = json.loads(Path(hooks_path).read_text()).get("hooks", {})
config_file = Path(config_path)
config = tomlkit.parse(config_file.read_text()) if config_file.exists() else tomlkit.document()

# PermissionRequest -> permission_request, as codex-rs `hook_event_key_label`.
label = lambda event: re.sub(r"(?<!^)(?=[A-Z])", "_", event).lower()

if "hooks" not in config:
    config["hooks"] = tomlkit.table()
if "state" not in config["hooks"]:
    config["hooks"]["state"] = tomlkit.table()
state = config["hooks"]["state"]

for event, groups in hooks.items():
    for g, group in enumerate(groups):
        for h, handler in enumerate(group.get("hooks", [])):
            if handler.get("type") != "command" or handler.get("command") not in ours:
                continue
            # The handler as Codex re-serialises it: unset options drop out
            # (TOML has no null), `async` is always present.
            normalized = {"type": "command", "command": handler["command"], "async": handler.get("async", False)}
            for src, dst in (("commandWindows", "commandWindows"), ("command_windows", "commandWindows"),
                             ("timeout", "timeout"), ("statusMessage", "statusMessage"),
                             ("additionalContextLimit", "additionalContextLimit")):
                if handler.get(src) is not None:
                    normalized[dst] = handler[src]
            identity = {"event_name": label(event), "hooks": [normalized]}
            if group.get("matcher") is not None:
                identity["matcher"] = group["matcher"]
            digest = hashlib.sha256(
                json.dumps(identity, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
            ).hexdigest()
            key = f"{hooks_path}:{label(event)}:{g}:{h}"
            if key not in state:
                state[key] = tomlkit.table()
            state[key]["trusted_hash"] = f"sha256:{digest}"

config_file.write_text(tomlkit.dumps(config))
