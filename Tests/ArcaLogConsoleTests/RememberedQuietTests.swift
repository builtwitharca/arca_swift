import Foundation
import Testing

@testable import ArcaLogConsole

/// The quiet lines' toggle, remembered (WP-11): made with a key, a console reads
/// whether its quiet lines show from the app's defaults under that key, and
/// writes it there each time it changes, from the window's toggle or from the
/// app; made with none, its quiet lines start hidden and it writes nothing.
/// Acceptance test AT-11.3, in ST0001's acceptance.md.
@MainActor
@Suite("The quiet lines, remembered")
struct RememberedQuietTests {
  static let key = "ConsoleVerbose"

  @Test("made with a key, a console shows its quiet lines as the app's defaults remember them")
  func read() throws {
    let scratch = try ScratchDefaults()
    scratch.defaults.set(true, forKey: Self.key)
    #expect(LogConsole(title: "Console", quietLinesKey: Self.key, defaults: scratch.defaults).showsQuietLines)
  }

  @Test("each change is written under the key, and a console made after it reads the last")
  func written() throws {
    let scratch = try ScratchDefaults()
    let console = LogConsole(title: "Console", quietLinesKey: Self.key, defaults: scratch.defaults)
    #expect(!console.showsQuietLines, "nothing is remembered yet, so the quiet lines are hidden")
    console.showsQuietLines = true
    #expect(scratch.stored[Self.key] as? Bool == true)
    console.showsQuietLines = false
    #expect(scratch.stored[Self.key] as? Bool == false)
    #expect(!LogConsole(title: "Console", quietLinesKey: Self.key, defaults: scratch.defaults).showsQuietLines)
  }

  @Test("a remembered toggle shows the quiet lines from a console's first line")
  func shownFromTheStart() async throws {
    let scratch = try ScratchDefaults()
    scratch.defaults.set(true, forKey: Self.key)
    let console = LogConsole(
      title: "Console", quietLinesKey: Self.key, defaults: scratch.defaults,
      launcher: CommandRunTests.stub([.lines(["GET / 200"]), .exited(0)]), now: CommandRunTests.clock([0, 1]))
    try await console.run(CommandRunTests.doctor, classify: { $0.hasPrefix("GET") ? .quiet : .log })
    #expect(console.shownLines.map(\.text) == ["» gtools doctor", "GET / 200", "» exit 0 · 1.0s"])
  }

  @Test("made with no key, a console's quiet lines start hidden and it writes nothing")
  func noKey() throws {
    let scratch = try ScratchDefaults()
    let console = LogConsole(title: "Console", defaults: scratch.defaults)
    #expect(!console.showsQuietLines)
    console.showsQuietLines = true
    #expect(scratch.stored.isEmpty)
  }
}

/// Defaults of a test's own, under a suite name no app reads, removed when the
/// test lets them go.
final class ScratchDefaults {
  let suite: String
  let defaults: UserDefaults

  init() throws {
    let suite = "arca-swift-test-\(UUID().uuidString)"
    self.suite = suite
    defaults = try #require(UserDefaults(suiteName: suite))
  }

  deinit {
    defaults.removePersistentDomain(forName: suite)
  }

  /// What the suite holds now.
  var stored: [String: Any] {
    defaults.persistentDomain(forName: suite) ?? [:]
  }
}
