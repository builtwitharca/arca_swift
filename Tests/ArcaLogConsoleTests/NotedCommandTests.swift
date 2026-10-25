import Testing

@testable import ArcaLogConsole

/// A command the app ran without the console, shown as a run is (WP-11): `» `
/// and its label, its lines as the app's classifier reads them, then `» exit`
/// and its status, all from the command's own source.
/// Acceptance test AT-11.5, in ST0001's acceptance.md.
@MainActor
@Suite("A command the app ran itself")
struct NotedCommandTests {
  static let label = "gtools url open gtools://x"

  @Test("it is framed by » and its label and by » exit and its status, with its lines between, from its own source")
  func framed() {
    let console = LogConsole(title: "Console")
    console.note(command: Self.label, lines: ["opened x", "error: not there"], status: 1)
    #expect(console.lines.map(\.text) == ["» gtools url open gtools://x", "opened x", "error: not there", "» exit 1"])
    #expect(console.lines.map(\.kind) == [.marker, .log, .error, .marker])
    #expect(console.lines.allSatisfy { $0.source == ConsoleSource(Self.label) })
  }

  @Test("its lines are of the kinds the app's classifier gives them")
  func classified() {
    let console = LogConsole(title: "Console")
    console.note(command: Self.label, lines: ["GET / 200"], status: 0, classify: { _ in .quiet })
    #expect(console.lines.map(\.text) == ["» gtools url open gtools://x", "GET / 200", "» exit 0"])
    #expect(console.lines.map(\.kind) == [.marker, .quiet, .marker])
  }
}
