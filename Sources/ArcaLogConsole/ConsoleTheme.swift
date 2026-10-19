import AppKit

/// A console window's font and colours: the app's, or the library's own
/// (design.md "ArcaLogConsole").
public struct ConsoleTheme {
  public var font: NSFont
  public var background: NSColor
  public var log: NSColor
  public var error: NSColor
  public var warning: NSColor
  public var marker: NSColor
  public var quiet: NSColor

  public init(
    font: NSFont, background: NSColor, log: NSColor, error: NSColor, warning: NSColor,
    marker: NSColor, quiet: NSColor
  ) {
    self.font = font
    self.background = background
    self.log = log
    self.error = error
    self.warning = warning
    self.marker = marker
    self.quiet = quiet
  }

  /// The library's own: the system's monospaced font at 12 points; the text
  /// colour for a log line, red for an error, orange for a warning, blue for
  /// a marker, and a dim grey for a quiet line. They are AppKit's system
  /// colours, so they follow light and dark mode. A marker's blue is fixed
  /// rather than the user's accent colour, which can be red or orange, so a
  /// marker never takes an error's or a warning's colour.
  @MainActor public static var standard: ConsoleTheme {
    ConsoleTheme(
      font: .monospacedSystemFont(ofSize: 12, weight: .regular), background: .textBackgroundColor,
      log: .textColor, error: .systemRed, warning: .systemOrange, marker: .systemBlue,
      quiet: .tertiaryLabelColor)
  }

  /// The colour of a line of `kind`.
  func colour(for kind: ConsoleLine.Kind) -> NSColor {
    switch kind {
    case .log: log
    case .error: error
    case .warning: warning
    case .marker: marker
    case .quiet: quiet
    }
  }
}
