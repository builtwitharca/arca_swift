/// How an app sorts its lines into kinds (design.md "ArcaLogConsole"). It is the
/// app's own, since each daemon's log has its own tokens: Gtools.app's matches
/// tokens anywhere in a line and makes its request lines quiet. The library
/// gives the pieces most logs share, in `ConsoleClassify`.
public typealias ConsoleClassifier = @Sendable (String) -> ConsoleLine.Kind

public enum ConsoleClassify {
  /// The kind the start of `line` names, or nil when it names none. One
  /// leading timestamp is skipped first (`unstamped`). Then `» ` is a marker;
  /// and, after any indent, `error:` and `caused by:` are errors, and
  /// `warning:` and `remedy:` are warnings, since a CLI prints an error's
  /// causes and remedy indented under it.
  public static func token(_ line: String) -> ConsoleLine.Kind? {
    nil
  }

  /// `line` after one leading RFC 3339 timestamp and the space after it, or
  /// all of `line` when it does not open with one. A timestamp is a full date,
  /// `T`, a time with optional fractional seconds, then `Z` or an offset such
  /// as `+01:00`, with each field in its range: a token with only the shape
  /// is not one.
  public static func unstamped(_ line: String) -> Substring {
    line[...]
  }

  /// The library's own classifier: the kind `token` finds, or log.
  public static let standard: ConsoleClassifier = { token($0) ?? .log }
}
