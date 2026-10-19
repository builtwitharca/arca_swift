import Testing

@testable import ArcaLogConsole

/// The ring and what the view shows of it (design.md "ArcaLogConsole"): the
/// last lines of all a console's sources in one bounded backlog, one source's
/// lines removed on their own, and a trim that counts lines, not newline runs.
/// Acceptance test AT-09.2, in ST0001's acceptance.md.
@Suite("The ring and the view's text")
struct ConsoleRingTests {
  static let site = ConsoleSource("site")
  static let doctor = ConsoleSource("doctor")

  static func lines(_ texts: [String], from source: ConsoleSource = site, kind: ConsoleLine.Kind = .log)
    -> [ConsoleLine]
  {
    texts.map { ConsoleLine(text: $0, kind: kind, source: source) }
  }

  @Test("lines within the capacity are kept, and none leave")
  func within() {
    var ring = ConsoleRing(capacity: 3)
    #expect(ring.append(Self.lines(["a", "b"])) == 0)
    #expect(ring.lines.map(\.text) == ["a", "b"])
    #expect(ConsoleRing().capacity == 5000)
  }

  @Test("past the capacity the oldest lines leave, whatever their source, and the ring says how many")
  func past() {
    var ring = ConsoleRing(capacity: 3)
    ring.append(Self.lines(["a", "b"]))
    #expect(ring.append(Self.lines(["c"], from: Self.doctor) + Self.lines(["d"])) == 1)
    #expect(ring.lines.map(\.text) == ["b", "c", "d"])
  }

  @Test("a batch longer than the capacity keeps its own last lines")
  func longBatch() {
    var ring = ConsoleRing(capacity: 2)
    ring.append(Self.lines(["a"]))
    #expect(ring.append(Self.lines(["b", "c", "d"])) == 2)
    #expect(ring.lines.map(\.text) == ["c", "d"])
  }

  @Test("one source's lines are removed with the rest kept in order, and clear empties the ring")
  func remove() {
    var ring = ConsoleRing(capacity: 10)
    ring.append(Self.lines(["a"]) + Self.lines(["x"], from: Self.doctor) + Self.lines(["b"]))
    #expect(ring.removeAll(from: Self.site) == 2)
    #expect(ring.lines.map(\.text) == ["x"])
    ring.clear()
    #expect(ring.lines.isEmpty)
  }

  @Test("the view shows a line as its text and a newline, and a hidden line takes nothing but is counted")
  func viewText() {
    var text = ConsoleText()
    let batch = Self.lines(["GET /"], kind: .quiet) + Self.lines(["héllo"])
    #expect(text.append(batch) { $0.kind != .quiet }.map(\.text) == ["héllo"])
    #expect(text.lengths == [0, 6])
    #expect(ConsoleText.rendered(batch[1]) == "héllo\n")
  }

  @Test("a line whose text holds a newline leaves the view as one line")
  func newlineInside() {
    var text = ConsoleText()
    _ = text.append(Self.lines(["one\ntwo", "three"])) { _ in true }
    #expect(text.dropFirst(1) == 8)
    #expect(text.lengths == [6])
  }

  @Test("the lines the ring drops leave the view too, hidden ones included")
  func trimFollowsRing() {
    var ring = ConsoleRing(capacity: 2)
    var text = ConsoleText()
    let first = Self.lines(["GET /a"], kind: .quiet) + Self.lines(["b"])
    _ = text.append(first) { $0.kind != .quiet }
    ring.append(first)
    let second = Self.lines(["c"])
    _ = text.append(second) { $0.kind != .quiet }
    let dropped = ring.append(second)
    #expect(dropped == 1)
    #expect(text.dropFirst(dropped) == 0, "the hidden request line took no text")
    #expect(text.lengths == [2, 2])
  }

  @Test("after the filter changes or a source is removed, the view starts again from the ring")
  func reset() {
    var text = ConsoleText()
    let ring = Self.lines(["GET /"], kind: .quiet) + Self.lines(["b"])
    _ = text.append(ring) { $0.kind != .quiet }
    #expect(text.reset(ring) { _ in true }.map(\.text) == ["GET /", "b"])
    #expect(text.lengths == [6, 2])
  }
}
