import AppKit
import ArcaLogConsole
import ArcaMasthead

/// An example menu bar app for ArcaMasthead (ST0001 WP-03) and ArcaLogConsole
/// (WP-09): the row at the top of its menu, and the About window the row
/// opens; and a console that follows a log the app writes each second, runs a
/// command, and keeps following when the log is rotated. Its bundle's
/// masthead.yaml, about.md, about.css and arca.svg are its defaults, and a
/// copy of any of them in its config folder, arca-example, is used first. An
/// executable that SwiftPM builds has no Info.plist or icon of its own, so
/// the app names its own values, and takes the Arca box as its icon in the
/// row and in the menu bar. With --about it opens the About window as it
/// starts.
@MainActor
final class Example: NSObject, NSApplicationDelegate {
  private var status: NSStatusItem?
  // Lazy, so it is made on the main actor at first use rather than in the
  // initialiser NSObject gives the class.
  private lazy var console = LogConsole(title: "arca-example console")
  private let log = FileManager.default.temporaryDirectory.appendingPathComponent(
    "arca-example.log"
  ).path
  private var ticks = 0
  private var ticking: Timer?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.applicationIconImage = Self.appIcon()
    let values = ["name": "arca-example", "version": "0.1.0", "commit": "dev", "kind": "dev"]
    let row = MastheadRow(
      app: "arca-example", bundle: .module, owned: Set(values.keys), value: { values[$0] },
      log: { print("masthead: \($0)") })
    let menu = NSMenu()
    menu.addItem(row)
    menu.addItem(.separator())
    for (title, action) in [
      ("Console…", #selector(showConsole)), ("Run a Command", #selector(runCommand)),
      ("Rotate the Log", #selector(rotateLog)),
    ] {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }
    menu.addItem(.separator())
    menu.addItem(
      NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    status.button?.image = Self.glyph()
    status.button?.setAccessibilityLabel("arca-example")
    status.menu = menu
    self.status = status
    if CommandLine.arguments.contains("--about"), let action = row.action {
      NSApp.sendAction(action, to: row.target, from: row)
    }
    startLogging()
  }

  // MARK: - The console

  /// The example's own classifier: its request lines are quiet, and the rest
  /// are read as the library reads them.
  static let classify: ConsoleClassifier = { line in
    line.contains("GET /") ? .quiet : ConsoleClassify.standard(line)
  }

  /// Starts the log afresh, follows it, and writes to it each second: a
  /// quiet request line every second, a warning every fifth and an error
  /// every seventh.
  private func startLogging() {
    guard FileManager.default.createFile(atPath: log, contents: nil) else {
      console.note("cannot make \(log), so there is no log to follow")
      return
    }
    console.follow(file: log, as: ConsoleSource("arca-example.log"), classify: Self.classify)
    console.note("following \(log)")
    ticking = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
  }

  private func tick() {
    ticks += 1
    let stamp = Date.now.formatted(.iso8601)
    var lines = ["\(stamp) tick \(ticks)", "\(stamp) GET /tick/\(ticks) 200"]
    if ticks.isMultiple(of: 5) { lines.append("\(stamp) warning: tick \(ticks) is a fifth") }
    if ticks.isMultiple(of: 7) { lines.append("\(stamp) error: tick \(ticks) is a seventh") }
    guard let handle = FileHandle(forWritingAtPath: log) else {
      console.note("cannot write \(log)")
      return
    }
    do {
      try handle.seekToEnd()
      try handle.write(contentsOf: Data(lines.map { $0 + "\n" }.joined().utf8))
      try handle.close()
    } catch {
      console.note("cannot write \(log): \(error.localizedDescription)")
    }
  }

  @objc private func showConsole() {
    console.showWindow()
  }

  /// A command with output on both streams, a warning, an error and a
  /// non-zero exit, framed in the console.
  @objc private func runCommand() {
    console.showWindow()
    let script =
      "echo checking; sleep 0.5; echo 'warning: a thing to look at'; echo 'error: a thing that failed' >&2; exit 1"
    let command = ConsoleCommand(
      label: "example check", executable: URL(fileURLWithPath: "/bin/sh"),
      arguments: ["-c", script])
    Task {
      do {
        try await console.run(command)
      } catch {
        console.note("could not run example check: \(error.localizedDescription)")
      }
    }
  }

  /// Renames the log aside and starts a new one, as a daemon rotating its
  /// log does. The console drains the old one and follows the new.
  @objc private func rotateLog() {
    do {
      if FileManager.default.fileExists(atPath: log + ".1") {
        try FileManager.default.removeItem(atPath: log + ".1")
      }
      try FileManager.default.moveItem(atPath: log, toPath: log + ".1")
      guard FileManager.default.createFile(atPath: log, contents: nil) else {
        console.note("rotated \(log) to \(log).1, but cannot make a new \(log)")
        return
      }
      console.note("rotated \(log) to \(log).1")
    } catch {
      console.note("cannot rotate \(log): \(error.localizedDescription)")
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
      guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
        let rep = NSImageRep(contentsOf: url)
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
