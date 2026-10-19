/// What a console's view shows of its ring, kept as one entry for each line in
/// the ring: the length the line takes in the view's text, in UTF-16 units,
/// and nothing when the view hides it (design.md "ArcaLogConsole").
///
/// **THE VIEW COUNTS LINES, NOT NEWLINE RUNS.** When the ring drops its oldest
/// lines, the view drops what those lines took, so a line whose text holds a
/// newline still leaves the view as one line, and a hidden line, which took
/// nothing, is still counted.
struct ConsoleText: Sendable {
  /// Each ring line's length in the view's text, oldest first.
  private(set) var lengths: [Int] = []

  /// The text a shown line takes: its own, then a newline.
  static func rendered(_ line: ConsoleLine) -> String {
    line.text + "\n"
  }

  /// Records `batch`, and returns the lines of it that the view shows, in
  /// order, each to be added as `rendered(_:)`.
  mutating func append(_ batch: [ConsoleLine], showing shows: (ConsoleLine) -> Bool) -> [ConsoleLine] {
    []
  }

  /// The length of the text the first `count` lines took, which the view
  /// removes from its front, and forgets those lines.
  mutating func dropFirst(_ count: Int) -> Int {
    0
  }

  /// Starts again from `lines`, the whole ring, and returns the lines the view
  /// shows: after the filter changes, or a source's lines are removed.
  mutating func reset(_ lines: [ConsoleLine], showing shows: (ConsoleLine) -> Bool) -> [ConsoleLine] {
    []
  }
}
