/// Bytes into lines, for a followed file and a command's output alike
/// (design.md "ArcaLogConsole", one line assembler for both).
///
/// **A FRAGMENT IS HELD UNTIL ITS NEWLINE ARRIVES.** The bytes are split on
/// 0x0A, and only a complete line is decoded, so a character split across two
/// reads stays one character.
///
/// **A LINE THAT IS NOT VALID UTF-8 STILL ARRIVES**, its bad bytes shown as
/// U+FFFD: dropping it would lose a log line with nothing to say so.
struct LineAssembler: Sendable {
  private var pending: [UInt8] = []

  /// The complete lines that `bytes` finishes, oldest first. What follows
  /// the last newline is held for the next read.
  mutating func lines(_ bytes: some Sequence<UInt8>) -> [String] {
    []
  }

  /// The fragment held, given up as a line, or nil when none is held. It is
  /// asked for at a stream's end, and when a followed file is truncated or
  /// replaced, since nothing more will finish the line then.
  mutating func flush() -> String? {
    nil
  }

  /// Whether a fragment is held.
  var isHolding: Bool { !pending.isEmpty }
}
