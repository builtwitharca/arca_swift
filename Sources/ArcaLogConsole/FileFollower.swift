import Foundation

/// A file the app names, followed in-process (design.md "ArcaLogConsole").
public final class FileFollower: @unchecked Sendable {
  private let path: String
  private let source: ConsoleSource
  private let classify: ConsoleClassifier
  private let backlog: Int
  private let deliver: @Sendable ([ConsoleLine]) -> Void

  /// Follows `path`, its lines from `source` and of the kind `classify`
  /// gives, each batch handed to `deliver` on the follower's own queue.
  /// Opening replays the file's last `backlog` lines.
  public init(
    path: String, source: ConsoleSource,
    classify: @escaping ConsoleClassifier = ConsoleClassify.standard,
    backlog: Int = 40, deliver: @escaping @Sendable ([ConsoleLine]) -> Void
  ) {
    self.path = path
    self.source = source
    self.classify = classify
    self.backlog = backlog
    self.deliver = deliver
  }

  public func start() {}

  public func stop() {}
}
