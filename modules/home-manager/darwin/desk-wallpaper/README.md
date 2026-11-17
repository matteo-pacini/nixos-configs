# desk-wallpaper (NightSprings, WorkLaptop)

The two Macs share the desk's monitors with BrightFalls through a KVM and
show the same pictures on them: the ASUS (left) gets `assets/wallpapers/left.png`,
the Dell (right) gets `assets/wallpapers/right.png`. Enabled per user with
`custom.deskWallpaper.enable = true;`. Pictures, display names and ids are
fixed in `default.nix`, since both Macs sit at the same desk.

## How it works

`desk-wallpaper` (`packages/desk-wallpaper/main.swift`, built with nixpkgs'
`swiftc`) runs as a Home Manager launchd agent in the GUI session
(`LimitLoadToSessionType = Aqua`, `RunAtLoad`, `KeepAlive`). It sets pictures
with `NSWorkspace.setDesktopImageURL` only: no `osascript`, no edits to the
wallpaper store, so no permission prompt.

- **Which screen gets what.** A screen whose name starts with
  `ROG PG278QR` gets `left.png`; one starting with `DELL U2719D` gets
  `right.png`. If a name ever differs, the EDID vendor and model numbers
  (ASUS `6b3`/`27b1`, Dell `10ac`/`415a`) match instead. The built-in panel
  gets `left.png` (scaled to fill) when neither monitor is connected, and
  the solid `#282a36` `background.png` when at least one is. Any other
  display is left alone, and does not count as docked.
- **When.** Once at start, then after every display reconfiguration (a KVM
  switch, plugging, the lid), after wake, and after a change of the active
  Space. Events within 1.5 s collapse into one pass, and a screen already
  showing the right file is skipped.
- **Spaces.** macOS has no API to set every Space at once: each call sets
  the current Space of each screen. Another Space shows its old picture
  until its first visit, then the agent fixes it. "Show on all Spaces" in
  System Settings reads off after the agent has set a picture.
- **Log.** One line per picture changed, and any error, in
  `~/Library/Logs/desk-wallpaper.log`.
- **Updates.** The picture paths are store paths in the agent's arguments,
  so a new picture or a new helper changes the plist, and the switch
  restarts the agent. Nothing runs at activation.

## On the Mac

```bash
# What macOS calls each screen, its EDID ids and current picture
desk-wallpaper list
# Agent state (running, last exit)
launchctl print gui/$UID/org.nix-community.home.desk-wallpaper
tail -f ~/Library/Logs/desk-wallpaper.log
```

To turn it off on one Mac, set `custom.deskWallpaper.enable = false;` for
that user and switch: Home Manager unloads the agent. The pictures it set
stay until changed by hand.

## Changing things

- **A picture:** replace the PNG in `assets/wallpapers/` (2560×1440 like the
  monitors, or the crop changes). BrightFalls uses the same files.
- **The plain background:** `assets/wallpapers/background.png` is a 16×16
  PNG of `#282a36`, made with
  `magick -size 16x16 'xc:#282a36' -strip png24:background.png`. A picture,
  not a fill colour, because `setDesktopImageURL` ignores the fill colour
  since macOS 14.
- **Polling instead of watching:** `desk-wallpaper apply` takes the same
  arguments, applies once and exits. Swap `run` for `apply` and
  `KeepAlive` for `StartInterval` in `default.nix`.

## Caveats

- The built-in panel's picture is best effort: "Fill Screen" crops
  `left.png` at the sides and puts its top under the menu bar.
- WorkLaptop is managed: a profile that locks the wallpaper would win over
  the agent. Check System Settings › Privacy & Security › Profiles.
- macOS lists the agent under Login Items › Allow in the Background, and
  shows a "Background Items Added" notice the first time. Home Manager
  starts it through `/bin/sh -c "/bin/wait4path /nix/store && exec …"`, so
  the entry may read `sh` rather than `desk-wallpaper`, like the other
  agents here.
