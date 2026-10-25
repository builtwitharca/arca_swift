import ArcaTestSupport
import Foundation
import Testing

@testable import ArcaLogConsole

/// What a console follows, named in its window's footer (WP-11): a file by its
/// path, with the home folder written ~, and a command by the last name its own
/// lines gave through the app's namer, or by its label until one does; in the
/// order the console began following each, then the command running. A source
/// stopped, or a followed command that ended, leaves the footer.
/// Acceptance test AT-11.2, in ST0001's acceptance.md.
@MainActor
@Suite("What a console follows, named")
struct FollowedNameTests {
  static let site = ConsoleSource("site")
  static let cms = ConsoleSource("cms")
  static let logs = ConsoleCommand(label: "gtools cms logs", executable: URL(fileURLWithPath: "/usr/bin/true"))

  /// The name a `tailing <path>  (...)` line gives, the way Gtools.app's
  /// `gtools cms logs` says which file it follows.
  static let tailing: ConsoleNamer = { line in
    guard line.hasPrefix("tailing ") else { return nil }
    return line.dropFirst("tailing ".count).components(separatedBy: "  ").first
  }

  /// A launcher whose command gives what the test yields, until the test
  /// finishes it.
  static func held() -> (launcher: CommandLauncher, events: AsyncStream<CommandEvent>.Continuation) {
    let (events, continuation) = AsyncStream<CommandEvent>.makeStream()
    return ({ _ in LaunchedCommand(events: events, stop: {}) }, continuation)
  }

  @Test("a file is named by its path, with the home folder written ~")
  func fileName() {
    let home = "/Users/someone"
    #expect(LogConsole.name(ofFile: "/Users/someone/Library/Logs/menuz.log", home: home) == "~/Library/Logs/menuz.log")
    #expect(LogConsole.name(ofFile: "/Users/someone", home: home) == "~")
    #expect(LogConsole.name(ofFile: "/Users/someoneelse/a.log", home: home) == "/Users/someoneelse/a.log")
    #expect(LogConsole.name(ofFile: "/var/log/system.log", home: home) == "/var/log/system.log")
  }

  @Test("followed files are named in the order the console began following them, and a stopped one leaves")
  func files() throws {
    try Scratch.folder { folder in
      let console = LogConsole(title: "Console")
      console.follow(file: folder + "/a.log", as: ConsoleSource("a"))
      console.follow(file: folder + "/b.log", as: ConsoleSource("b"))
      #expect(console.footer == "following \(folder)/a.log, \(folder)/b.log")
      console.stopFollowing(ConsoleSource("a"))
      #expect(console.footer == "following \(folder)/b.log")
      console.stopFollowing(ConsoleSource("b"))
      #expect(console.footer == "")
    }
  }

  @Test("a command is named by its label until its own lines give a name, then by the last name they gave")
  func command() async throws {
    let (launcher, events) = Self.held()
    let console = LogConsole(title: "Console", launcher: launcher)
    try console.follow(command: Self.logs, as: Self.cms, naming: Self.tailing)
    #expect(console.footer == "following gtools cms logs")
    events.yield(.lines(["tailing /var/log/cms-4360.log  (lifecycle only)", "12:00:00 started"]))
    try await until { console.lines.count >= 3 }
    #expect(console.footer == "following /var/log/cms-4360.log")
    events.yield(.lines(["tailing /var/log/cms-4361.log  (lifecycle only)"]))
    try await until { console.lines.count >= 4 }
    #expect(console.footer == "following /var/log/cms-4361.log")
    events.yield(.exited(0))
    events.finish()
    try await until { console.footer.isEmpty }
    #expect(console.footer == "", "a command that ended is no longer followed")
  }

  @Test("a command followed with no namer keeps its label")
  func noNamer() async throws {
    let (launcher, events) = Self.held()
    let console = LogConsole(title: "Console", launcher: launcher)
    try console.follow(command: Self.logs, as: Self.cms)
    events.yield(.lines(["tailing /var/log/cms-4360.log  (lifecycle only)"]))
    try await until { console.lines.count >= 2 }
    #expect(console.footer == "following gtools cms logs")
    console.stopFollowing(Self.cms)
    #expect(console.footer == "")
    events.finish()
  }

  @Test("the command running is named after what is followed, while it runs")
  func running() async throws {
    try await Scratch.folder { folder in
      let (launcher, events) = Self.held()
      let console = LogConsole(title: "Console", launcher: launcher)
      console.follow(file: folder + "/site.log", as: Self.site)
      let run = Task { try await console.run(CommandRunTests.doctor) }
      try await until { console.running != nil }
      #expect(console.footer == "following \(folder)/site.log · running gtools doctor")
      events.yield(.exited(0))
      events.finish()
      #expect(try await run.value == 0)
      #expect(console.footer == "following \(folder)/site.log")
      console.stopFollowing(Self.site)
    }
  }

  @Test("the footer says what is followed, then the command running, and nothing for neither")
  func text() {
    #expect(
      LogConsole.footer(following: ["a.log", "b.log"], running: "gtools doctor")
        == "following a.log, b.log · running gtools doctor")
    #expect(LogConsole.footer(following: ["a.log"], running: nil) == "following a.log")
    #expect(LogConsole.footer(following: [], running: "gtools doctor") == "running gtools doctor")
    #expect(LogConsole.footer(following: [], running: nil) == "")
  }
}
