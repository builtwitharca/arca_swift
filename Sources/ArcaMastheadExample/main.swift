import AppKit
import ArcaMasthead

/// An example menu bar app for ArcaMasthead (ST0001 WP-03): the row at the
/// top of its menu, and the About window the row opens. Its bundle's
/// masthead.yaml, about.md, about.css and arca.svg are its defaults, and a
/// copy of any of them in its config folder, arca-example, is used first. An
/// executable that SwiftPM builds has no Info.plist or icon of its own, so
/// the app names its own values, and takes the Arca box as its icon in the
/// row and in the menu bar. With --about it opens the About window as it
/// starts.
@MainActor
final class Example: NSObject, NSApplicationDelegate {
  private var status: NSStatusItem?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.applicationIconImage = Self.appIcon()
    let values = ["name": "arca-example", "version": "0.1.0", "commit": "dev", "kind": "dev"]
    let row = MastheadRow(
      app: "arca-example", bundle: .module, owned: Set(values.keys), value: { values[$0] },
      log: { print("masthead: \($0)") })
    let menu = NSMenu()
    menu.addItem(row)
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    status.button?.image = Self.glyph()
    status.button?.setAccessibilityLabel("arca-example")
    status.menu = menu
    self.status = status
    if CommandLine.arguments.contains("--about"), let action = row.action {
      NSApp.sendAction(action, to: row.target, from: row)
    }
  }

  /// The Arca box on Apple's rounded plate, as the app's icon.
  private static func appIcon() -> NSImage {
    guard let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
      let icon = NSImage(contentsOf: url)
    else {
      fatalError("the example's bundle has no AppIcon.icns")
    }
    return icon
  }

  /// The Arca box glyph for the menu bar, as a template image that macOS
  /// tints for a light or a dark bar: the pixel-fitted 16 px render, and
  /// the 32 px one for a Retina display.
  private static func glyph() -> NSImage {
    let size = NSSize(width: 16, height: 16)
    let glyph = NSImage(size: size)
    for name in ["arca-logo-black-16", "arca-logo-black-32"] {
      guard let url = Bundle.module.url(forResource: name, withExtension: "png"), let rep = NSImageRep(contentsOf: url)
      else {
        fatalError("the example's bundle has no \(name).png")
      }
      rep.size = size
      glyph.addRepresentation(rep)
    }
    glyph.isTemplate = true
    return glyph
  }
}

let example = Example()
NSApplication.shared.delegate = example
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
