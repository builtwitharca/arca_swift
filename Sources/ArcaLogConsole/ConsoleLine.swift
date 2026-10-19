/// One line of a console: its text, its kind and the source it came from
/// (design.md "ArcaLogConsole"). The kind sets the line's colour. The source
/// is an id the app gives, one for each file or command it follows, so one
/// window can show several sources and replace one source's lines.
public struct ConsoleLine: Sendable, Equatable {
  public enum Kind: Sendable, Equatable, CaseIterable {
    /// Every line that is none of the kinds below.
    case log
    case error
    case warning
    /// The app's own lines: its notes, and the frame around a command it ran.
    case marker
    /// Dimmed, and hidden when the app asks, eg a request line.
    case quiet
  }

  public let text: String
  public let kind: Kind
  public let source: ConsoleSource

  public init(text: String, kind: Kind, source: ConsoleSource) {
    self.text = text
    self.kind = kind
    self.source = source
  }

  /// What a marker line opens with.
  public static let markerPrefix = "» "

  /// A marker line, `» ` then `text`: the app's note, or `» exit 0 · 1.2s`.
  public static func marker(_ text: String, source: ConsoleSource = .app) -> ConsoleLine {
    ConsoleLine(text: markerPrefix + text, kind: .marker, source: source)
  }
}

/// The id of one of a console's sources: one for each file or command the app
/// follows, and `app` for the app's own notes.
public struct ConsoleSource: Hashable, Sendable, CustomStringConvertible {
  public let id: String

  public init(_ id: String) {
    self.id = id
  }

  public var description: String { id }

  /// The app's own notes.
  public static let app = ConsoleSource("app")
}
