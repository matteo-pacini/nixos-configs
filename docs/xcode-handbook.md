# Xcode handbook

NightSprings and WorkLaptop install Xcode from `.xip` archives kept in the attic `main` cache, so activation (including comin on NightSprings) never needs an Apple ID. Only `xcode-fetch`, run by hand once per Xcode version, talks to Apple. This is the same approach GitHub's macOS runner images use: download once, mirror privately, install from the mirror.

## How it works

```
xcode-fetch 27.0 (by hand, once)              darwin activation (root)
  xcodes download  ── Apple ID + 2FA            /Applications/Xcode-27.0.app missing?
  nix-store --add-fixed Xcode-27.0.xip            nix-store --realise <xip>  ◄── attic main
  sudo attic-push-closure main <path>  ──► attic  xip --expand, mv into /Applications
  jq: xcode-versions.json["27.0"] = hash          xcodebuild -license accept, -runFirstLaunch
                                                  nix-store --delete <xip>
                                                xcode-select --switch <active>
                                                remove unlisted /Applications/Xcode-*.app
```

- `modules/darwin/xcode-versions.json` maps each version to the `.xip`'s hash. `custom.xcode` turns each entry into a `requireFile` store path (`Xcode-<version>.xip`).
- That path is used only as a string, so the multi-GB `.xip` is **not** part of the system closure. CI doesn't download it, and hosts don't keep it in their store. Activation fetches it from attic only when that version isn't installed yet, and deletes it after extracting.
- Installs are named `/Applications/Xcode-<version>.app`. Any other `Xcode-*.app` in `/Applications` is deleted. Xcodes outside `/Applications`, or named differently (e.g. `Xcode.app`), are left alone.
- Before installing or removing anything, activation shuts down booted simulators and asks Xcode and Simulator to quit (AppleScript, as the primary user). If either is still running 60 s later, e.g. waiting on a save dialog, activation **fails** rather than force-quitting. Activations that change nothing never touch running apps.
- If the `.xip` can't be fetched, activation **fails**. On NightSprings that is a comin deploy failure, reported on Telegram (see [auto-deploy](auto-deploy-handbook.md)), and every later deploy fails the same way until the `.xip` is back in attic.
- CI (`build.yml`, `pr-build.yml`) checks that each listed `.xip` is in attic, without downloading it. A missing one fails the darwin build, so `deploy` doesn't move.

## Adding or bumping a version

On a Mac with the attic token (NightSprings or WorkLaptop), from a checkout of this repo:

```bash
nix run .#xcode-fetch -- 27.1
```

It asks for your Apple ID and 2FA code (xcodes), then your password (`sudo attic-push-closure`), and writes the hash into `xcode-versions.json`.

Then:

1. Change `custom.xcode.versions` / `active` in `hosts/<Host>/system.nix`.
2. Commit `xcode-versions.json` together with the host change.

Remove a version by dropping it from `versions`; the next activation deletes the app. Drop its entry from `xcode-versions.json` once no host lists it.

## Attic retention

Nothing references the `.xip` paths, so attic's garbage collection can delete them once the 3-month retention period passes (`default-retention-period` in `hosts/Nexus/services/attic.nix`). Installed Xcodes are unaffected. After that, a host that still needs to *install* that version (a fresh machine, or the app deleted) fails activation, and CI fails too. Rerun `xcode-fetch <version>`: it downloads the same Apple file, so the hash and store path come out the same.

## Migrating an existing install

An `Xcode-<version>.app` in `/Applications` is treated as installed, so rename an existing install of a listed version instead of letting activation download it again:

```bash
sudo mv /Applications/Xcode-27.0.0.app /Applications/Xcode-27.0.app   # Xcodes.app naming
```

Xcodes installed in `~/Applications` by the old Home Manager module are not managed. Remove them once the new version is active:

```bash
rm -rf ~/Applications/Xcode-26.3.0.app
```

## Files

| What | Where |
|---|---|
| Module (`custom.xcode`) | `modules/darwin/xcode.nix` |
| Version → hash | `modules/darwin/xcode-versions.json` |
| `xcode-fetch` | `packages/xcode-fetch.{nix,sh}`, exposed as `apps.aarch64-darwin.xcode-fetch` |
| xcodes 2.1.0 (overlay) | `overlays/shared.nix`, `packages/xcodes/generated/` |
| CI check | `.github/workflows/build.yml`, `pr-build.yml` |
