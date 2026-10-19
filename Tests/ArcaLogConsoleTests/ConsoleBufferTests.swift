import Testing

@testable import ArcaLogConsole

/// A console's lines and its view's edits (design.md "ArcaLogConsole"): a
/// bounded buffer whose quiet lines and other lines are kept to the capacity
/// apart, and one edit for each batch, whose ranges count lines rather than
/// newline runs.
/// Acceptance test AT-09.2, in ST0001's acceptance.md.
@Suite("The buffer and its view's edits")
struct ConsoleBufferTests {
  static let site = ConsoleSource("site")
  static let doctor = ConsoleSource("doctor")

  static func lines(_ texts: [String], from source: ConsoleSource = site, kind: ConsoleLine.Kind = .log)
    -> [ConsoleLine]
  {
    texts.map { ConsoleLine(text: $0, kind: kind, source: source) }
  }

  @Test("lines within the capacity are kept, and each one added shows as its text and a newline")
  func within() {
    var buffer = ConsoleBuffer(capacity: 3)
    #expect(buffer.append(Self.lines(["a", "b"])) == ConsoleBuffer.Edit(removed: [], added: Self.lines(["a", "b"])))
    #expect(buffer.lines.map(\.text) == ["a", "b"])
    #expect(ConsoleBuffer().capacity == 5000)
    #expect(ConsoleBuffer.rendered(Self.lines(["héllo"])[0]) == "héllo\n")
  }

  @Test(
    "past the capacity the oldest lines leave, whatever their source, and the view cuts them from its top as one range")
  func past() {
    var buffer = ConsoleBuffer(capacity: 3)
    _ = buffer.append(Self.lines(["a", "bb", "c"]))
    let batch = Self.lines(["d"], from: Self.doctor) + Self.lines(["e"])
    #expect(buffer.append(batch) == ConsoleBuffer.Edit(removed: [0..<5], added: batch))
    #expect(buffer.lines.map(\.text) == ["c", "d", "e"])
  }

  @Test("a batch longer than the capacity keeps its own last lines, and its first ones never reach the view")
  func longBatch() {
    var buffer = ConsoleBuffer(capacity: 2)
    _ = buffer.append(Self.lines(["a"]))
    #expect(
      buffer.append(Self.lines(["b", "c", "d"])) == ConsoleBuffer.Edit(removed: [0..<2], added: Self.lines(["c", "d"])))
    #expect(buffer.lines.map(\.text) == ["c", "d"])
  }

  @Test("a quiet line never pushes out a line that shows, since each kind is kept to the capacity apart")
  func quietApart() {
    var buffer = ConsoleBuffer(capacity: 2)
    _ = buffer.append(Self.lines(["» gtools doctor", "ok"], from: Self.doctor))
    let requests = Self.lines((1...5).map { "GET /\($0)" }, kind: .quiet)
    #expect(buffer.append(requests) == ConsoleBuffer.Edit(), "hidden lines change nothing the view shows")
    #expect(buffer.lines.map(\.text) == ["» gtools doctor", "ok", "GET /4", "GET /5"])
  }

  @Test("with the quiet lines shown, a quiet line that leaves is cut from inside the text")
  func quietShownLeavesFromInside() {
    var buffer = ConsoleBuffer(capacity: 1)
    #expect(buffer.showQuiet(true).isEmpty)
    _ = buffer.append(Self.lines(["doctor"]) + Self.lines(["GET /1"], kind: .quiet))
    let next = Self.lines(["GET /2"], kind: .quiet)
    #expect(buffer.append(next) == ConsoleBuffer.Edit(removed: [7..<14], added: next))
    #expect(buffer.lines.map(\.text) == ["doctor", "GET /2"])
  }

  @Test("a line whose text holds a newline leaves the view as one line")
  func newlineInside() {
    var buffer = ConsoleBuffer(capacity: 1)
    _ = buffer.append(Self.lines(["one\ntwo"]))
    #expect(buffer.append(Self.lines(["three"])) == ConsoleBuffer.Edit(removed: [0..<8], added: Self.lines(["three"])))
  }

  @Test("one source's lines are removed with the rest kept in order, and the next cut still counts right")
  func remove() {
    var buffer = ConsoleBuffer(capacity: 2)
    _ = buffer.append(Self.lines(["a"]) + Self.lines(["x"], from: Self.doctor))
    #expect(buffer.removeAll(from: Self.site).map(\.text) == ["x"])
    _ = buffer.append(Self.lines(["b"]))
    #expect(buffer.append(Self.lines(["c"])) == ConsoleBuffer.Edit(removed: [0..<2], added: Self.lines(["c"])))
    #expect(buffer.lines.map(\.text) == ["b", "c"])
  }

  @Test("showing the quiet lines gives the whole text again, and clear empties the buffer")
  func showQuietAndClear() {
    var buffer = ConsoleBuffer(capacity: 10)
    _ = buffer.append(Self.lines(["GET /"], kind: .quiet) + Self.lines(["b"]))
    #expect(buffer.shown.map(\.text) == ["b"])
    #expect(buffer.showQuiet(true).map(\.text) == ["GET /", "b"])
    buffer.clear()
    #expect(buffer.lines.isEmpty)
    #expect(buffer.append(Self.lines(["c"])) == ConsoleBuffer.Edit(removed: [], added: Self.lines(["c"])))
  }
}
