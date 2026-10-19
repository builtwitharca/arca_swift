/// A console's lines, bounded, and what its view shows of them, kept as one
/// (design.md "ArcaLogConsole"). Each change gives the one edit the view makes,
/// so the order of its removals and additions is the buffer's, under test,
/// rather than the view's.
///
/// **A QUIET LINE NEVER PUSHES OUT A LINE THAT SHOWS.** The quiet lines and the
/// rest are each kept to the capacity, the oldest of each leaving first, so a
/// busy source's hidden request lines cannot push a command's output out of
/// the console.
///
/// **THE VIEW COUNTS LINES, NOT NEWLINE RUNS.** A line takes its text and a
/// newline in the view, and nothing while it is hidden, and it leaves as one
/// line whatever its text holds.
struct ConsoleBuffer: Sendable {
  /// One change to the view's text: the ranges to remove, in UTF-16 units of
  /// the text before the change, in order and merged where they meet; then
  /// the lines to add at the end, each as `rendered(_:)`.
  struct Edit: Equatable, Sendable {
    var removed: [Range<Int>] = []
    var added: [ConsoleLine] = []
  }

  static let defaultCapacity = 5000

  let capacity: Int
  private(set) var lines: [ConsoleLine] = []
  /// Whether the quiet lines show.
  private(set) var showsQuiet: Bool

  init(capacity: Int = defaultCapacity, showsQuiet: Bool = false) {
    precondition(capacity > 0, "a console keeps at least one line")
    self.capacity = capacity
    self.showsQuiet = showsQuiet
  }

  /// The text a shown line takes: its own, then a newline.
  static func rendered(_ line: ConsoleLine) -> String {
    line.text + "\n"
  }

  /// The lines the view shows, oldest first.
  var shown: [ConsoleLine] {
    []
  }

  /// Adds `batch`, drops the oldest lines of each kind past the capacity, and
  /// gives the view's edit. A batch longer than the capacity loses its own
  /// first lines, which never reach the view.
  mutating func append(_ batch: [ConsoleLine]) -> Edit {
    Edit()
  }

  /// Drops `source`'s lines, keeping the rest in order, and gives the lines
  /// the view shows now, for it to start again from.
  mutating func removeAll(from source: ConsoleSource) -> [ConsoleLine] {
    []
  }

  /// Shows or hides the quiet lines, and gives the lines the view shows now.
  mutating func showQuiet(_ shows: Bool) -> [ConsoleLine] {
    []
  }

  mutating func clear() {}
}
