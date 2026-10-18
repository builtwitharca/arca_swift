import AppKit
import ArcaMasthead

/// An example menu bar app for ArcaMasthead (ST0001 WP-03): the row at the
/// top of its menu, and the About window the row opens. Its bundle's
/// masthead.yaml, about.md, about.css and arca.svg are its defaults, and a
/// copy of any of them in its config folder, arca-example, is used first. An
/// executable that SwiftPM builds has no Info.plist of its own, so the app
/// names its own values. With --about it opens the About window as it
/// starts.
@MainActor
final class Example: NSObject, NSApplicationDelegate {
  private var status: NSStatusItem?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let values = ["name": "arca-example", "version": "0.1.0", "commit": "dev", "kind": "dev"]
    let row = MastheadRow(
      app: "arca-example", bundle: .module, owned: Set(values.keys), value: { values[$0] },
      log: { print("masthead: \($0)") })
    let menu = NSMenu()
    menu.addItem(row)
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    status.button?.title = "Arca"
    status.menu = menu
    self.status = status
    if CommandLine.arguments.contains("--about"), let action = row.action {
      NSApp.sendAction(action, to: row.target, from: row)
    }
  }
}

let example = Example()
NSApplication.shared.delegate = example
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
