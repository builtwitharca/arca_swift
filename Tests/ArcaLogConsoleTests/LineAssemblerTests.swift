import Testing

@testable import ArcaLogConsole

/// Bytes into lines (design.md "ArcaLogConsole", one line assembler for a file
/// and a command alike): split on 0x0A, a fragment held until its newline,
/// bad bytes shown as U+FFFD, the fragment given up as a line at the end, and
/// no line longer than the limit.
/// Acceptance test AT-09.3, in ST0001's acceptance.md.
@Suite("The line assembler")
struct LineAssemblerTests {
  static func bytes(_ text: String) -> [UInt8] {
    Array(text.utf8)
  }

  @Test("complete lines are split on the newline, an empty line among them")
  func split() {
    var assembler = LineAssembler()
    #expect(assembler.lines(Self.bytes("a\n\nb\n")) == ["a", "", "b"])
    #expect(assembler.flush() == nil, "nothing after the last newline is held")
  }

  @Test("a fragment is held until its newline arrives")
  func fragment() {
    var assembler = LineAssembler()
    #expect(assembler.lines(Self.bytes("ab")).isEmpty)
    #expect(assembler.lines(Self.bytes("c\nd")) == ["abc"])
    #expect(assembler.lines(Self.bytes("\n")) == ["d"])
  }

  @Test("a character split across two reads stays one character")
  func splitCharacter() {
    var assembler = LineAssembler()
    let accented = Self.bytes("é")
    #expect(accented.count == 2)
    #expect(assembler.lines([UInt8(ascii: "x"), accented[0]]).isEmpty)
    #expect(assembler.lines([accented[1], 0x0A]) == ["xé"])
  }

  @Test("a line that is not valid UTF-8 still arrives, its bad bytes as U+FFFD")
  func badBytes() {
    var assembler = LineAssembler()
    #expect(assembler.lines([0x61, 0xFF, 0x62, 0x0A]) == ["a\u{FFFD}b"])
  }

  @Test("at the end the fragment held is a line, and nothing is held after it")
  func flush() {
    var assembler = LineAssembler()
    #expect(assembler.lines(Self.bytes("last line, no newline")).isEmpty)
    #expect(assembler.flush() == "last line, no newline")
    #expect(assembler.flush() == nil)
    #expect(assembler.lines(Self.bytes("next\n")) == ["next"], "the flushed fragment does not start the next line")
  }

  @Test("bytes with no newline past the limit are given up in pieces of it, so what is held stays bounded")
  func pieces() {
    var assembler = LineAssembler(limit: 4)
    #expect(assembler.lines(Self.bytes("abcdefghij")) == ["abcd", "efgh"])
    #expect(assembler.flush() == "ij", "only the rest is held")
    #expect(LineAssembler(limit: 4).lines(Self.bytes("abcdefghij\n")) == ["abcd", "efgh", "ij"], "a whole line too")
    var bytewise = LineAssembler(limit: 4)
    let lines = Self.bytes("abcdefghij\n").flatMap { bytewise.lines([$0]) }
    #expect(lines == ["abcd", "efgh", "ij"], "the same pieces, however the bytes arrive")
  }

  @Test("a piece ends on a character's boundary, so a character is never split across two lines")
  func pieceBoundary() {
    var assembler = LineAssembler(limit: 4)
    #expect(Self.bytes("abcéd").count == 6)
    #expect(assembler.lines(Self.bytes("abcéd\n")) == ["abc", "éd"])
  }
}
