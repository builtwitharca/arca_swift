import Foundation

/// A command's frame in a console (design.md "ArcaLogConsole"), one for a run
/// and a followed command alike: `» ` and its label before its lines, a line
/// for any lines its launcher dropped, and how it ended after them, as
/// `» exit 0 · 1.2s` or `» killed by signal 15 · 1.2s`.
struct CommandFrame: Sendable {
  let label: String
  let source: ConsoleSource
  let classify: ConsoleClassifier
  let started: ContinuousClock.Instant
  /// How many dropped lines have been said.
  private var said = 0

  init(
    label: String, source: ConsoleSource, classify: @escaping ConsoleClassifier, started: ContinuousClock.Instant
  ) {
    self.label = label
    self.source = source
    self.classify = classify
    self.started = started
  }

  /// The line that opens the frame.
  var opening: ConsoleLine { .marker(label, source: source) }

  /// The lines `event` adds, after a line for any dropped since the last was
  /// said; and, for the command's end, the status `run` gives for it: its exit
  /// status, or 128 and the signal, as a shell gives it. The end's time is
  /// read off `now`.
  mutating func take(
    _ event: CommandEvent, dropped: Int, now: () -> ContinuousClock.Instant
  ) -> (lines: [ConsoleLine], status: Int32?) {
    let before = droppedSince(dropped)
    switch event {
    case .lines(let texts):
      return (before + ConsoleLine.lines(texts, source: source, classify: classify), nil)
    case .exited(let status):
      return (before + [ending("exit \(status)", at: now())], status)
    case .signalled(let signal):
      return (before + [ending("killed by signal \(signal)", at: now())], 128 + signal)
    }
  }

  /// The lines a command that failed adds: a line for any lines dropped,
  /// then its reason and `» failed`.
  mutating func failed(_ error: any Error, dropped: Int = 0) -> [ConsoleLine] {
    droppedSince(dropped) + [
      ConsoleLine(text: error.localizedDescription, kind: .error, source: source),
      .marker("failed", source: source),
    ]
  }

  /// The lines a cancelled run adds: a line for any lines dropped, then
  /// `» cancelled`.
  mutating func cancelled(dropped: Int) -> [ConsoleLine] {
    droppedSince(dropped) + [.marker("cancelled", source: source)]
  }

  /// `how · 1.2s`, the time since the command started.
  private func ending(_ how: String, at now: ContinuousClock.Instant) -> ConsoleLine {
    let elapsed = now - started
    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    return .marker("\(how) · \(String(format: "%.1f", seconds))s", source: source)
  }

  /// A line saying how many lines were dropped since the last such line, if
  /// any were.
  private mutating func droppedSince(_ dropped: Int) -> [ConsoleLine] {
    guard dropped > said else { return [] }
    defer { said = dropped }
    let count = dropped - said
    return [.marker("\(count) \(count == 1 ? "line" : "lines") dropped", source: source)]
  }
}
