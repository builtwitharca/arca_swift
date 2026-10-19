/// A console's backlog: the last `capacity` lines of all its sources together,
/// in the order they arrived (design.md "ArcaLogConsole").
///
/// **ONE CAPACITY FOR ALL OF A CONSOLE'S SOURCES.** The view trims from the top
/// alone, once for each batch, and a capacity for each source would turn that
/// into deletions anywhere in the text. A console follows one log, with the
/// commands the app runs and its notes around it. An app that follows several
/// logs, as Gtools.app does one for each site, gives each log its own console,
/// so a busy log cannot push a quiet one's lines out.
struct ConsoleRing: Sendable {
  static let defaultCapacity = 5000

  let capacity: Int
  private(set) var lines: [ConsoleLine] = []

  init(capacity: Int = defaultCapacity) {
    precondition(capacity > 0, "a console keeps at least one line")
    self.capacity = capacity
  }

  /// Appends `batch` and returns how many lines left from the front, the
  /// oldest first, to keep the ring within its capacity. When `batch` alone
  /// is longer than the capacity, its own first lines are among them.
  @discardableResult
  mutating func append(_ batch: [ConsoleLine]) -> Int {
    0
  }

  /// Drops every line from `source`, keeping the rest in order, and returns
  /// how many went.
  @discardableResult
  mutating func removeAll(from source: ConsoleSource) -> Int {
    0
  }

  mutating func clear() {}
}
