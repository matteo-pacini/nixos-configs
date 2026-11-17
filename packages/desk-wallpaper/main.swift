// desk-wallpaper: one picture per named display on macOS, set through the
// public NSWorkspace API. How it is run and why: see
// modules/home-manager/darwin/desk-wallpaper/README.md.
//
//   desk-wallpaper run   ARGS   apply now, then again after every display
//                               change, wake and Space change
//   desk-wallpaper apply ARGS   apply once and exit
//   desk-wallpaper list         print each screen as macOS reports it
//
// ARGS: --external NAME VENDOR MODEL IMAGE (repeatable)
//       --builtin IMAGE --builtin-docked IMAGE (each optional)
//
// A screen whose name starts with NAME, or whose EDID vendor and model
// numbers (hex, as system_profiler prints them) equal VENDOR and MODEL,
// gets IMAGE. The built-in panel gets the --builtin-docked image while any
// --external display is present, else the --builtin image. Any other screen
// is left alone. One line is written to stderr per picture changed.

import AppKit

struct External {
  let name: String
  let vendor: UInt32
  let model: UInt32
  let image: URL
}

struct Config {
  var externals: [External] = []
  var builtin: URL?
  var builtinDocked: URL?
}

func log(_ message: String) {
  let stamp = ISO8601DateFormatter().string(from: Date())
  FileHandle.standardError.write(Data("\(stamp) \(message)\n".utf8))
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(
    Data("desk-wallpaper: \(message)\nusage: desk-wallpaper run|apply|list (see main.swift)\n".utf8))
  exit(2)
}

func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
  let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
  return number?.uint32Value ?? 0
}

func isBuiltin(_ screen: NSScreen) -> Bool {
  CGDisplayIsBuiltin(displayID(screen)) != 0
}

// Prefix, not equality: macOS appends " (1)" and the like to duplicate names.
func matches(_ external: External, _ screen: NSScreen) -> Bool {
  let id = displayID(screen)
  return screen.localizedName.hasPrefix(external.name)
    || (CGDisplayVendorNumber(id) == external.vendor
      && CGDisplayModelNumber(id) == external.model)
}

func picture(for screen: NSScreen, among screens: [NSScreen], _ config: Config) -> URL? {
  if isBuiltin(screen) {
    let docked = screens.contains { other in
      config.externals.contains { matches($0, other) }
    }
    return docked ? config.builtinDocked : config.builtin
  }
  return config.externals.first { matches($0, screen) }?.image
}

// Changes only the current Space of each screen: macOS has no API for the
// others, so the run loop calls this again on every Space change.
func applyOnce(_ config: Config) {
  let workspace = NSWorkspace.shared
  let screens = NSScreen.screens
  for screen in screens {
    guard let want = picture(for: screen, among: screens, config) else { continue }
    if workspace.desktopImageURL(for: screen)?.path == want.path { continue }
    do {
      // Empty options mean "Fill Screen"; a fill colour would be ignored
      // since macOS 14, hence a solid PNG for the plain background.
      try workspace.setDesktopImageURL(want, for: screen, options: [:])
      log("\(screen.localizedName): \(want.path)")
    } catch {
      log("\(screen.localizedName): cannot set \(want.path): \(error.localizedDescription)")
    }
  }
}

func list() {
  for screen in NSScreen.screens {
    let id = displayID(screen)
    let vendor = String(CGDisplayVendorNumber(id), radix: 16)
    let model = String(CGDisplayModelNumber(id), radix: 16)
    let current = NSWorkspace.shared.desktopImageURL(for: screen)?.path ?? "-"
    print(
      "\(screen.localizedName)\tbuiltin=\(isBuiltin(screen))\tvendor=\(vendor)\tmodel=\(model)\t\(current)"
    )
  }
}

func parse(_ args: ArraySlice<String>) -> Config {
  var config = Config()
  var rest = args
  func hex(_ text: String) -> UInt32 {
    guard let value = UInt32(text, radix: 16) else { fail("not a hex number: \(text)") }
    return value
  }
  func image() -> URL {
    guard let path = rest.popFirst() else { fail("missing IMAGE") }
    return URL(fileURLWithPath: path)
  }
  while let flag = rest.popFirst() {
    switch flag {
    case "--external":
      guard rest.count >= 3 else { fail("--external takes NAME VENDOR MODEL IMAGE") }
      let name = rest.removeFirst()
      let vendor = hex(rest.removeFirst())
      let model = hex(rest.removeFirst())
      config.externals.append(External(name: name, vendor: vendor, model: model, image: image()))
    case "--builtin": config.builtin = image()
    case "--builtin-docked": config.builtinDocked = image()
    default: fail("unknown argument: \(flag)")
    }
  }
  return config
}

var pendingApply: DispatchWorkItem?

// A KVM switch moves both displays and a wake can report each display
// twice, so events within 1.5 s collapse into one pass. Main thread only.
func scheduleApply() {
  pendingApply?.cancel()
  let work = DispatchWorkItem { applyOnce(config) }
  pendingApply = work
  DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
}

let args = CommandLine.arguments.dropFirst()
guard let command = args.first else { fail("missing command") }
switch command {
case "list":
  list()
  exit(0)
case "apply", "run":
  break
default:
  fail("unknown command: \(command)")
}

let config = parse(args.dropFirst())
if command == "apply" {
  applyOnce(config)
  exit(0)
}

// An application object, never shown, keeps NSScreen in step with the
// window server while the run loop waits.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
CGDisplayRegisterReconfigurationCallback(
  { _, flags, _ in
    // Called once before a change (begin flag) and once per display after.
    if !flags.contains(.beginConfigurationFlag) {
      DispatchQueue.main.async { scheduleApply() }
    }
  }, nil)
for name in [NSWorkspace.didWakeNotification, NSWorkspace.activeSpaceDidChangeNotification] {
  NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) {
    _ in scheduleApply()
  }
}
applyOnce(config)
app.run()
