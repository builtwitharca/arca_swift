import Foundation
import Testing

@testable import ArcaLogConsole

/// A command the console runs (design.md "ArcaLogConsole"): framed by
/// `» cmd` and `» exit N · 1.2s`, one at a time, against a stub launcher and
/// an injected clock, with its dropped lines said, and a cancelled run
/// stopped; a followed command framed as a run is; and the process launcher,
/// with real children: one pipe for stdout and stderr, bad bytes as U+FFFD,
/// stdin held, a signal said as one, and output a started process holds open
/// cut after the drain.
/// Acceptance test AT-09.5, in ST0001's acceptance.md.
@MainActor
@Suite("Running a command")
struct CommandRunTests {
  static let doctor = ConsoleCommand(
    label: "gtools doctor", executable: URL(fileURLWithPath: "/usr/bin/false"))
  static let source = ConsoleSource("doctor")

  /// A launcher whose every command gives `events`, then ends, and says
  /// `dropped` lines were dropped.
  static func stub(_ events: [CommandEvent], dropped: Int = 0) -> CommandLauncher {
    { _ in
      LaunchedCommand(
        events: AsyncStream { continuation in
          for event in events { continuation.yield(event) }
          continuation.finish()
        },
        stop: {}, droppedLines: { dropped })
    }
  }

  /// A clock that reads `seconds` after one start, in turn, and the last of
  /// them from then on.
  static func clock(_ seconds: [Double]) -> @Sendable () -> ContinuousClock.Instant {
    let start = ContinuousClock.now
    let readings = Readings(seconds)
    return { start + .milliseconds(Int(readings.next() * 1000)) }
  }

  /// A real child running `script` in sh.
  static func shell(_ script: String) -> ConsoleCommand {
    ConsoleCommand(label: "sh", executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script])
  }

  /// Every event a launched command gives, in order.
  static func events(of launched: LaunchedCommand) async -> [CommandEvent] {
    var events: [CommandEvent] = []
    for await event in launched.events { events.append(event) }
    return events
  }

  @Test(
    "a run is framed by » and its label and by » exit and its time, with its lines between, and gives its status"
  )
  func framed() async throws {
    let console = LogConsole(
      title: "Console",
      launcher: Self.stub([.lines(["one", "error: two"]), .lines(["three"]), .exited(3)]),
      now: Self.clock([0, 1.2]))
    #expect(try await console.run(Self.doctor, as: Self.source) == 3)
    #expect(
      console.lines.map(\.text) == [
        "» gtools doctor", "one", "error: two", "three", "» exit 3 · 1.2s",
      ])
    #expect(console.lines.map(\.kind) == [.marker, .log, .error, .log, .marker])
    #expect(console.lines.allSatisfy { $0.source == Self.source })
  }

  @Test("a run a signal ends is framed with the signal, and gives 128 and the signal, as a shell does")
  func framedSignal() async throws {
    let console = LogConsole(
      title: "Console", launcher: Self.stub([.lines(["one"]), .signalled(15)]), now: Self.clock([0, 0.5]))
    #expect(try await console.run(Self.doctor, as: Self.source) == 143)
    #expect(console.lines.map(\.text) == ["» gtools doctor", "one", "» killed by signal 15 · 0.5s"])
  }

  @Test("lines the launcher dropped are said, as how many, before what follows them")
  func droppedLines() async throws {
    let console = LogConsole(
      title: "Console", launcher: Self.stub([.lines(["one"]), .exited(0)], dropped: 7), now: Self.clock([0, 1.2]))
    try await console.run(Self.doctor, as: Self.source)
    #expect(console.lines.map(\.text) == ["» gtools doctor", "» 7 lines dropped", "one", "» exit 0 · 1.2s"])
  }

  @Test("a second run while one goes is refused, naming the first, and writes nothing")
  func busy() async throws {
    let (events, continuation) = AsyncStream<CommandEvent>.makeStream()
    let console = LogConsole(
      title: "Console", launcher: { _ in LaunchedCommand(events: events, stop: {}) })
    let first = Task { try await console.run(Self.doctor, as: Self.source) }
    let deadline = ContinuousClock.now + .seconds(2)
    while console.lines.isEmpty, ContinuousClock.now < deadline { await Task.yield() }
    let index = ConsoleCommand(
      label: "gtools index", executable: URL(fileURLWithPath: "/usr/bin/true"))
    await #expect(throws: ConsoleError.busy("gtools doctor")) { try await console.run(index) }
    #expect(console.lines.map(\.text) == ["» gtools doctor"])
    continuation.yield(.exited(0))
    continuation.finish()
    #expect(try await first.value == 0)
  }

  @Test("a cancelled run stops its command, says so under » cancelled, and throws CancellationError")
  func cancelled() async throws {
    let (events, continuation) = AsyncStream<CommandEvent>.makeStream()
    let stopped = Readings([])
    let console = LogConsole(
      title: "Console", launcher: { _ in LaunchedCommand(events: events, stop: { stopped.mark() }) })
    let run = Task { try await console.run(Self.doctor, as: Self.source) }
    let deadline = ContinuousClock.now + .seconds(2)
    while console.lines.isEmpty, ContinuousClock.now < deadline { await Task.yield() }
    run.cancel()
    await #expect(throws: CancellationError.self) { try await run.value }
    #expect(stopped.marked, "the command was stopped")
    #expect(console.lines.map(\.text) == ["» gtools doctor", "» cancelled"])
    #expect(console.running == nil, "the next run may start")
    continuation.finish()
  }

  @Test("a command that cannot launch says why, under » failed, and the run throws")
  func cannotLaunch() async throws {
    struct NoSuchTool: Error, LocalizedError {
      var errorDescription: String? { "no such tool" }
    }
    let console = LogConsole(title: "Console", launcher: { _ in throw NoSuchTool() })
    await #expect(throws: NoSuchTool.self) { try await console.run(Self.doctor, as: Self.source) }
    #expect(console.lines.map(\.text) == ["» gtools doctor", "no such tool", "» failed"])
    #expect(console.lines.map(\.kind) == [.marker, .error, .marker])
  }

  @Test("output that ends with no exit status says so, under » failed, and the run throws")
  func noExitStatus() async throws {
    let console = LogConsole(title: "Console", launcher: Self.stub([.lines(["one"])]))
    await #expect(throws: ConsoleError.noExitStatus("gtools doctor")) {
      try await console.run(Self.doctor, as: Self.source)
    }
    #expect(
      console.lines.map(\.text) == [
        "» gtools doctor", "one", "`gtools doctor` ended without an exit status.", "» failed",
      ])
  }

  @Test("by default a run's frame and lines carry the command's own source")
  func ownSource() async throws {
    let console = LogConsole(title: "Console", launcher: Self.stub([.lines(["one"]), .exited(0)]))
    try await console.run(Self.doctor)
    #expect(console.lines.count == 3)
    #expect(console.lines.allSatisfy { $0.source == ConsoleSource("gtools doctor") })
  }

  @Test("a followed command is framed as a run is, and following it again replaces its lines")
  func followedCommand() async throws {
    let console = LogConsole(
      title: "Console", launcher: Self.stub([.lines(["a"]), .exited(0)]), now: Self.clock([0, 1.2, 2, 3.2]))
    let tail = ConsoleCommand(label: "tail", executable: URL(fileURLWithPath: "/usr/bin/true"))
    let framed = ["» tail", "a", "» exit 0 · 1.2s"]
    try console.follow(command: tail, as: Self.source)
    try await until { console.lines.count >= 3 }
    #expect(console.lines.map(\.text) == framed)
    try console.follow(command: tail, as: Self.source)
    try await until { console.lines.count >= 3 }
    try await Task.sleep(for: .milliseconds(100))
    #expect(console.lines.map(\.text) == framed, "the first follow's lines were replaced")
  }

  @Test("the app's note is a marker line from the app")
  func note() {
    let console = LogConsole(title: "Console")
    console.note("stopped the site")
    #expect(console.lines == [ConsoleLine(text: "» stopped the site", kind: .marker, source: .app)])
  }

  @Test("a child's stdout and stderr share one pipe, bad bytes are U+FFFD, a last line needs no newline")
  func process() async throws {
    let launched = try CommandLaunch.process(
      Self.shell("printf 'a\\n'; printf 'b\\377c\\n' >&2; printf 'last'; exit 4"))
    let events = await Self.events(of: launched)
    let lines = events.flatMap { event -> [String] in
      if case .lines(let lines) = event { lines } else { [] }
    }
    #expect(lines == ["a", "b\u{FFFD}c", "last"])
    #expect(events.last == .exited(4))
  }

  @Test("a child a signal ends gives the signal, not an exit status")
  func signalled() async throws {
    let launched = try CommandLaunch.process(Self.shell("kill -TERM $$"))
    #expect(await Self.events(of: launched) == [.signalled(SIGTERM)])
  }

  @Test("output a process the child started holds open is cut after the drain, with a line saying so")
  func drained() async throws {
    // A drain of a second leaves a loaded machine time to read "started", and
    // ends well inside the 2 s that sleep holds the output open.
    let launch = CommandLaunch.launcher(drain: .seconds(1))
    let launched = try launch(Self.shell("sleep 2 & echo started"))
    #expect(
      await Self.events(of: launched) == [.lines(["started"]), .lines([CommandLaunch.cutLine]), .exited(0)])
  }

  @Test("a child's stdin is held, so a child that reads it runs until it is stopped")
  func heldStdin() async throws {
    let launched = try CommandLaunch.process(
      ConsoleCommand(label: "cat", executable: URL(fileURLWithPath: "/bin/cat")))
    let ended = Readings([])
    let reader = Task {
      var last: CommandEvent?
      for await event in launched.events { last = event }
      ended.mark()
      return last
    }
    try await Task.sleep(for: .milliseconds(300))
    #expect(!ended.marked, "cat ended with its stdin still held")
    launched.stop()
    #expect(await reader.value == .exited(0))
  }
}

/// Values read in turn under a lock, the last one kept; and a mark.
final class Readings: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [Double]
  private var isMarked = false

  init(_ values: [Double]) {
    self.values = values
  }

  func next() -> Double {
    lock.withLock { values.count > 1 ? values.removeFirst() : (values.first ?? 0) }
  }

  func mark() {
    lock.withLock { isMarked = true }
  }

  var marked: Bool {
    lock.withLock { isMarked }
  }
}
