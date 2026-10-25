import AppKit
import Foundation
import Testing

@testable import ArcaLogConsole

/// Copy All (WP-11): what the window's Copy All puts on the pasteboard is the
/// text the window shows, each line it shows as its text and a newline, oldest
/// first, so that a quiet line goes only while the quiet lines show.
/// Acceptance test AT-11.1, in ST0001's acceptance.md.
@MainActor
@Suite("Copy All")
struct CopyAllTests {
  /// A console that ran a command whose lines are a log line, a quiet request
  /// line and an error.
  static func console() async throws -> LogConsole {
    let console = LogConsole(
      title: "Console",
      launcher: CommandRunTests.stub([.lines(["started", "GET / 200", "error: gone"]), .exited(1)]),
      now: CommandRunTests.clock([0, 1.5]))
    try await console.run(
      CommandRunTests.doctor, as: CommandRunTests.source,
      classify: { $0.hasPrefix("GET") ? .quiet : ConsoleClassify.standard($0) })
    return console
  }

  @Test("Copy All takes the lines the window shows, oldest first, each as its text and a newline")
  func shown() async throws {
    let console = try await Self.console()
    #expect(console.copyText == "» gtools doctor\nstarted\nerror: gone\n» exit 1 · 1.5s\n")
  }

  @Test("a quiet line goes only while the quiet lines show")
  func quiet() async throws {
    let console = try await Self.console()
    console.showsQuietLines = true
    #expect(console.copyText == "» gtools doctor\nstarted\nGET / 200\nerror: gone\n» exit 1 · 1.5s\n")
    console.showsQuietLines = false
    #expect(console.copyText == "» gtools doctor\nstarted\nerror: gone\n» exit 1 · 1.5s\n")
  }

  @Test("Copy All puts that text on the pasteboard, as its string, in place of what was there")
  func pasteboard() async throws {
    let console = try await Self.console()
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.clearContents()
    pasteboard.setString("copied before", forType: .string)
    console.copyAll(to: pasteboard)
    #expect(pasteboard.string(forType: .string) == "» gtools doctor\nstarted\nerror: gone\n» exit 1 · 1.5s\n")
  }

  @Test("an empty console, or a cleared one, copies nothing")
  func empty() async throws {
    #expect(LogConsole(title: "Console").copyText == "")
    let console = try await Self.console()
    console.clear()
    #expect(console.copyText == "")
  }
}
