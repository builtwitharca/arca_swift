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
  /// the text before the change, merged where they meet, and last first, so
  /// that the view removing them in turn finds each where it was counted;
  /// then the lines to add at the end, each as `rendered(_:)`.
  struct Edit: Equatable, Sendable {
    var removed: [Range<Int>] = []
    var added: [ConsoleLine] = []
  }

  static let defaultCapacity = 5000

  let capacity: Int
  private(set) var lines: [ConsoleLine] = []
  /// Whether the quiet lines show.
  private(set) var showsQuiet: Bool
  private var lengths: [Int] = []
  private var quietCount = 0

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
    lines.filter { shows($0) }
  }

  // WP-11's compiling stub, which its red run reads.
  var shownText: String { "" }

  /// Adds `batch`, drops the oldest lines of each kind past the capacity, and
  /// gives the view's edit. A batch longer than the capacity loses its own
  /// first lines, which never reach the view.
  mutating func append(_ batch: [ConsoleLine]) -> Edit {
    guard !batch.isEmpty else { return Edit() }
    let before = lines.count
    lines.append(contentsOf: batch)
    lengths.append(contentsOf: batch.map { length($0) })
    quietCount += batch.count { $0.kind == .quiet }
    let leaving = leavers()
    var edit = Edit()
    var offset = 0
    var index = 0
    for leaver in leaving where leaver < before {
      while index < leaver {
        offset += lengths[index]
        index += 1
      }
      let length = lengths[leaver]
      if length > 0 {
        if let last = edit.removed.last, last.upperBound == offset {
          edit.removed[edit.removed.count - 1] = last.lowerBound..<offset + length
        } else {
          edit.removed.append(offset..<offset + length)
        }
      }
      offset += length
      index = leaver + 1
    }
    edit.removed.reverse()
    let gone = Set(leaving)
    edit.added = (before..<lines.count).filter { !gone.contains($0) && lengths[$0] > 0 }.map {
      lines[$0]
    }
    if !gone.isEmpty { keep(lines.indices.map { !gone.contains($0) }) }
    return edit
  }

  /// Drops `source`'s lines, keeping the rest in order, and gives the lines
  /// the view shows now, for it to start again from.
  mutating func removeAll(from source: ConsoleSource) -> [ConsoleLine] {
    keep(lines.map { $0.source != source })
    return shown
  }

  /// Shows or hides the quiet lines, and gives the lines the view shows now.
  mutating func showQuiet(_ visible: Bool) -> [ConsoleLine] {
    showsQuiet = visible
    lengths = lines.map { length($0) }
    return shown
  }

  mutating func clear() {
    lines = []
    lengths = []
    quietCount = 0
  }

  /// The indices of the oldest lines past the capacity, the quiet lines and
  /// the rest counted apart, in order.
  private func leavers() -> [Int] {
    var quietOver = quietCount - capacity
    var restOver = lines.count - quietCount - capacity
    var leaving: [Int] = []
    for (index, line) in lines.enumerated() {
      guard quietOver > 0 || restOver > 0 else { break }
      if line.kind == .quiet {
        if quietOver > 0 {
          leaving.append(index)
          quietOver -= 1
        }
      } else if restOver > 0 {
        leaving.append(index)
        restOver -= 1
      }
    }
    return leaving
  }

  /// Keeps the lines `kept` marks, with their lengths.
  private mutating func keep(_ kept: [Bool]) {
    var keptLines: [ConsoleLine] = []
    var keptLengths: [Int] = []
    for index in lines.indices where kept[index] {
      keptLines.append(lines[index])
      keptLengths.append(lengths[index])
    }
    lines = keptLines
    lengths = keptLengths
    quietCount = lines.count { $0.kind == .quiet }
  }

  private func shows(_ line: ConsoleLine) -> Bool {
    showsQuiet || line.kind != .quiet
  }

  private func length(_ line: ConsoleLine) -> Int {
    shows(line) ? Self.rendered(line).utf16.count : 0
  }
}
