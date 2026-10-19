import Testing

@testable import ArcaLogConsole

/// Bytes into lines (design.md "ArcaLogConsole", one line assembler for a file
/// and a command alike): split on 0x0A, a fragment held until its newline,
/// bad bytes shown as U+FFFD, and the fragment given up as a line at the end.
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
    #expect(!assembler.isHolding)
  }

  @Test("a fragment is held until its newline arrives")
  func fragment() {
    var assembler = LineAssembler()
    #expect(assembler.lines(Self.bytes("ab")).isEmpty)
    #expect(assembler.isHolding)
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
    #expect(!assembler.isHolding)
  }
}
