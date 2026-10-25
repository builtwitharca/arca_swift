import AppKit
import Foundation
import Testing

@testable import ArcaLogConsole

/// The window's close, told to the app (WP-11), so that an app can follow a
/// command only while the window shows: an app that stops following a command
/// when told has that command's child gone.
/// Acceptance test AT-11.4, in ST0001's acceptance.md.
@MainActor
@Suite("The window's close, told to the app")
struct WindowCloseTests {
  @Test("the app is told when the console's window closes")
  func told() {
    _ = NSApplication.shared
    let console = LogConsole(title: "Console")
    let closed = Readings([])
    console.onWindowClose = { closed.mark() }
    // A window made and closed, never shown. The window holds its controller,
    // its delegate, weakly, so the controller is kept until the close is done.
    let controller = ConsoleWindowController(console: console)
    withExtendedLifetime(controller) { controller.window?.close() }
    #expect(closed.marked)
  }

  @Test("an app that stops following a command when told has the command's child gone")
  func childGone() async throws {
    let seconds = Self.sleepLength()
    let source = ConsoleSource("sleep")
    let console = LogConsole(title: "Console")
    try console.follow(
      command: ConsoleCommand(label: "sleep", executable: URL(fileURLWithPath: "/bin/sleep"), arguments: [seconds]),
      as: source)
    console.onWindowClose = { [weak console] in console?.stopFollowing(source) }
    try await until { Self.sleeping(seconds) }
    #expect(Self.sleeping(seconds), "the child runs while the console follows it")
    console.windowDidClose()
    try await until { !Self.sleeping(seconds) }
    #expect(!Self.sleeping(seconds), "the child is gone once the app has stopped following it")
  }

  /// A length for a test's `sleep` that no other sleep on the machine has, so
  /// that pgrep finds that child alone: 30 s and a random fraction, so that a
  /// child a dead test left behind ends on its own half a minute later.
  static func sleepLength() -> String {
    "30.\(Int.random(in: 100_000...999_999))"
  }

  /// Whether a `sleep` of `seconds` runs, as pgrep finds it.
  static func sleeping(_ seconds: String) -> Bool {
    let pgrep = Process()
    pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    pgrep.arguments = ["-f", "^/bin/sleep \(seconds)$"]
    pgrep.standardOutput = FileHandle.nullDevice
    do {
      try pgrep.run()
    } catch {
      Issue.record(error, "pgrep could not run")
      return false
    }
    pgrep.waitUntilExit()
    return pgrep.terminationStatus == 0
  }
}
