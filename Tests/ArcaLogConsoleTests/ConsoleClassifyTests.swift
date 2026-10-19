import Testing

@testable import ArcaLogConsole

/// A line and its kind (design.md "ArcaLogConsole"): the app's classifier, and
/// the two pieces the library gives it, a start-of-line token and the skip of
/// one leading timestamp. A marker line is the app's own.
/// Acceptance test AT-09.1, in ST0001's acceptance.md.
@Suite("Console lines and their kinds")
struct ConsoleClassifyTests {
  @Test("error: and caused by: are errors, and warning: and remedy: warnings, after any indent")
  func tokens() {
    #expect(ConsoleClassify.token("error: the estate has no config") == .error)
    #expect(ConsoleClassify.token("  caused by: no such file") == .error)
    #expect(ConsoleClassify.token("warning: the log is over 1 MB") == .warning)
    #expect(ConsoleClassify.token("  remedy: run gtools doctor") == .warning)
  }

  @Test("a marker opens with » , and the app makes one with that prefix")
  func markers() {
    #expect(ConsoleClassify.token("» intent doctor") == .marker)
    #expect(ConsoleLine.marker("exit 0 · 1.2s") == ConsoleLine(text: "» exit 0 · 1.2s", kind: .marker, source: .app))
    #expect(ConsoleLine.marker("x", source: ConsoleSource("doctor")).source == ConsoleSource("doctor"))
  }

  @Test("a token anywhere but the start names nothing, and the standard classifier makes it a log line")
  func notAtStart() {
    #expect(ConsoleClassify.token("the run said error: none") == nil)
    #expect(ConsoleClassify.token("errors: 0") == nil)
    #expect(ConsoleClassify.standard("the run said error: none") == .log)
    #expect(ConsoleClassify.standard("") == .log)
  }

  @Test("a stamped line is read as the line under its stamp, in UTC, with fractional seconds or with an offset")
  func stamped() {
    #expect(ConsoleClassify.unstamped("2026-10-19T09:04:28Z error: x") == "error: x")
    #expect(ConsoleClassify.token("2026-10-19T09:04:28.123Z error: x") == .error)
    #expect(ConsoleClassify.token("2026-10-19T10:04:28+01:00   remedy: y") == .warning)
    #expect(ConsoleClassify.token("2026-10-19T09:04:28Z » note") == .marker)
    #expect(ConsoleClassify.standard("2026-10-19T09:04:28Z started") == .log)
  }

  @Test("only one stamp is skipped, and a token with the shape but a field out of range is not a stamp")
  func notStamps() {
    let twice = "2026-10-19T09:04:28Z 2026-10-19T09:04:29Z error: x"
    #expect(ConsoleClassify.unstamped(twice) == "2026-10-19T09:04:29Z error: x")
    #expect(ConsoleClassify.token(twice) == nil)
    for line in [
      "2026-13-19T09:04:28Z error: x",
      "2026-10-32T09:04:28Z error: x",
      "2026-10-19T24:04:28Z error: x",
      "2026-10-19T09:04:28 error: x",
      "2026-10-19T09:04:28.Z error: x",
      "2026-10-19T09:04:28+1:00 error: x",
      "2026-10-19 09:04:28Z error: x",
    ] {
      #expect(ConsoleClassify.unstamped(line) == line[...], "\(line)")
      #expect(ConsoleClassify.token(line) == nil, "\(line)")
    }
  }

  @Test("a line keeps its text, kind and source")
  func line() {
    let line = ConsoleLine(text: "GET /", kind: .quiet, source: ConsoleSource("site 4360"))
    #expect(line.text == "GET /")
    #expect(line.kind == .quiet)
    #expect(line.source.id == "site 4360")
    #expect(ConsoleSource.app.description == "app")
    #expect(ConsoleLine.Kind.allCases == [.log, .error, .warning, .marker, .quiet])
  }
}
