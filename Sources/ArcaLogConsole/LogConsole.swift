import Foundation

/// A console: the ring of its sources' lines, the commands it runs, the app's
/// notes, and its window (design.md "ArcaLogConsole").
@MainActor
public final class LogConsole {
  /// The lines a console keeps by default.
  public static let defaultCapacity = ConsoleBuffer.defaultCapacity

  public let title: String
  private var buffer: ConsoleBuffer
  private let launcher: CommandLauncher
  private let now: @Sendable () -> ContinuousClock.Instant

  /// The label of the command running now, or nil.
  public private(set) var running: String?

  /// The lines the console keeps, oldest first.
  public var lines: [ConsoleLine] { buffer.lines }

  public init(
    title: String, capacity: Int = LogConsole.defaultCapacity,
    launcher: @escaping CommandLauncher = CommandLaunch.process,
    now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }
  ) {
    self.title = title
    self.buffer = ConsoleBuffer(capacity: capacity)
    self.launcher = launcher
    self.now = now
  }

  /// Runs `command`, its lines from `source`, or from the command's own source
  /// when none is named, framed by `» ` and its label and by
  /// `» exit N · 1.2s`, and gives its exit status.
  @discardableResult
  public func run(
    _ command: ConsoleCommand, as source: ConsoleSource? = nil,
    classify: @escaping ConsoleClassifier = ConsoleClassify.standard
  ) async throws -> Int32 {
    0
  }

  /// The app's note, as a marker line.
  public func note(_ text: String) {}
}
