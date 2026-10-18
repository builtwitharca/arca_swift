import ArcaCore

/// The refusals the app's log has been given (design.md "The file"), so that
/// each is logged once, when it first appears, and again only after a whole
/// read without it.
struct RefusalLog {
  /// The lines of the read before this one, and of this one so far.
  private var previous: Set<String> = []
  private var current: Set<String> = []

  /// The lines of `refusals`, a new read's, that the read before did not
  /// have, each once, in order.
  mutating func read(_ refusals: [Refusal]) -> [String] {
    previous = current
    current = []
    return add(refusals)
  }

  /// The lines of `refusals`, more of the same read's, that neither the read
  /// before nor this one has had, each once, in order.
  mutating func add(_ refusals: [Refusal]) -> [String] {
    var fresh: [String] = []
    for line in refusals.map(\.description) {
      if !previous.contains(line) && !current.contains(line) { fresh.append(line) }
      current.insert(line)
    }
    return fresh
  }
}
