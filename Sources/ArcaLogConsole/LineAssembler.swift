/// Bytes into lines, for a followed file and a command's output alike
/// (design.md "ArcaLogConsole", one line assembler for both).
///
/// **A FRAGMENT IS HELD UNTIL ITS NEWLINE ARRIVES.** The bytes are split on
/// 0x0A, and only a complete line is decoded, so a character split across two
/// reads stays one character.
///
/// **A LINE THAT IS NOT VALID UTF-8 STILL ARRIVES**, its bad bytes shown as
/// U+FFFD: dropping it would lose a log line with nothing to say so.
///
/// **NO LINE IS LONGER THAN THE LIMIT.** A longer run of bytes with no
/// newline, held or not, is given up in pieces of the limit, each ending on a
/// character's boundary, so a stream with no newline cannot grow what is held
/// without bound. Each read scans only its own bytes, since what is held has
/// no newline.
struct LineAssembler: Sendable {
  /// The longest line given, in bytes.
  static let lineLimit = 256 * 1024

  private let limit: Int
  private var pending: [UInt8] = []

  init(limit: Int = LineAssembler.lineLimit) {
    precondition(limit >= 4, "a piece holds at least one whole character")
    self.limit = limit
  }

  /// The complete lines that `bytes` finishes, oldest first. What follows
  /// the last newline is held for the next read.
  mutating func lines(_ bytes: some Sequence<UInt8>) -> [String] {
    var scanned = pending.count
    pending.append(contentsOf: bytes)
    var lines: [String] = []
    var start = 0
    while let newline = pending[scanned...].firstIndex(of: 0x0A) {
      start = pieces(from: start, to: newline, into: &lines)
      lines.append(String(decoding: pending[start..<newline], as: UTF8.self))
      start = newline + 1
      scanned = start
    }
    start = pieces(from: start, to: pending.count, into: &lines)
    pending.removeFirst(start)
    return lines
  }

  /// The fragment held, given up as a line, or nil when none is held. It is
  /// asked for at a stream's end, and when a followed file is truncated or
  /// replaced, since nothing more will finish the line then.
  mutating func flush() -> String? {
    guard !pending.isEmpty else { return nil }
    defer { pending.removeAll() }
    return String(decoding: pending, as: UTF8.self)
  }

  /// Gives up the bytes from `start` to `end` in pieces of the limit while
  /// more than the limit of them is left, and gives where the rest starts. A
  /// piece never ends before a UTF-8 continuation byte, unless the bytes
  /// there are not UTF-8.
  private func pieces(from start: Int, to end: Int, into lines: inout [String]) -> Int {
    var start = start
    while end - start > limit {
      var cut = start + limit
      while cut > start + limit - 3, pending[cut] & 0xC0 == 0x80 { cut -= 1 }
      lines.append(String(decoding: pending[start..<cut], as: UTF8.self))
      start = cut
    }
    return start
  }
}
