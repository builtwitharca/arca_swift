/// How an app sorts its lines into kinds (design.md "ArcaLogConsole"). It is the
/// app's own, since each daemon's log has its own tokens: Gtools.app's matches
/// tokens anywhere in a line and makes its request lines quiet. The library
/// gives the pieces most logs share, in `ConsoleClassify`.
public typealias ConsoleClassifier = @Sendable (String) -> ConsoleLine.Kind

public enum ConsoleClassify {
  /// The kind the start of `line` names, or nil when it names none. One
  /// leading timestamp is skipped first (`unstamped`). Then `» ` is a marker;
  /// and, after any indent of spaces or tabs, `error:` and `caused by:` are
  /// errors, and `warning:` and `remedy:` are warnings, since a CLI prints an
  /// error's causes and remedy indented under it.
  public static func token(_ line: String) -> ConsoleLine.Kind? {
    let rest = unstamped(line)
    if rest.hasPrefix(ConsoleLine.markerPrefix) { return .marker }
    let body = rest.drop(while: { $0 == " " || $0 == "\t" })
    if body.hasPrefix("error:") || body.hasPrefix("caused by:") { return .error }
    if body.hasPrefix("warning:") || body.hasPrefix("remedy:") { return .warning }
    return nil
  }

  /// `line` after one leading RFC 3339 timestamp and the space after it, or
  /// all of `line` when it does not open with one. A timestamp is a full date,
  /// `T`, a time with optional fractional seconds, then `Z` or an offset such
  /// as `+01:00`, with each field in its range: a token with only the shape
  /// is not one.
  public static func unstamped(_ line: String) -> Substring {
    guard let space = line.firstIndex(of: " "), isTimestamp(Array(line[..<space].utf8)) else {
      return line[...]
    }
    return line[line.index(after: space)...]
  }

  /// The library's own classifier: the kind `token` finds, or log.
  public static let standard: ConsoleClassifier = { token($0) ?? .log }

  private static func isTimestamp(_ bytes: [UInt8]) -> Bool {
    func ascii(_ character: Unicode.Scalar) -> UInt8 { UInt8(ascii: character) }
    func number(_ range: Range<Int>) -> Int? {
      guard range.upperBound <= bytes.count,
        bytes[range].allSatisfy({ (ascii("0")...ascii("9")).contains($0) })
      else { return nil }
      return bytes[range].reduce(0) { $0 * 10 + Int($1 - ascii("0")) }
    }
    guard bytes.count >= 20, bytes[4] == ascii("-"), bytes[7] == ascii("-"),
      bytes[10] == ascii("T"),
      bytes[13] == ascii(":"), bytes[16] == ascii(":"),
      number(0..<4) != nil,
      let month = number(5..<7), (1...12).contains(month),
      let day = number(8..<10), (1...31).contains(day),
      let hour = number(11..<13), hour <= 23,
      let minute = number(14..<16), minute <= 59,
      let second = number(17..<19), second <= 60
    else { return false }
    var zone = 19
    if bytes[zone] == ascii(".") {
      var end = zone + 1
      while end < bytes.count, (ascii("0")...ascii("9")).contains(bytes[end]) { end += 1 }
      guard end > zone + 1 else { return false }
      zone = end
    }
    if bytes.count == zone + 1 { return bytes[zone] == ascii("Z") }
    guard bytes.count == zone + 6, bytes[zone] == ascii("+") || bytes[zone] == ascii("-"),
      bytes[zone + 3] == ascii(":"),
      let offsetHour = number(zone + 1..<zone + 3), offsetHour <= 23,
      let offsetMinute = number(zone + 4..<zone + 6), offsetMinute <= 59
    else { return false }
    return true
  }
}
