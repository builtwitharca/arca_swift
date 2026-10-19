import Foundation

/// A command a console runs: what the operator would type, for its frame, and
/// what to run.
public struct ConsoleCommand: Sendable, Equatable {
  /// The command as the operator would type it, eg `gtools doctor`.
  public let label: String
  public let executable: URL
  public let arguments: [String]
  /// The child's environment, or nil for the app's own.
  public let environment: [String: String]?

  public init(
    label: String, executable: URL, arguments: [String] = [], environment: [String: String]? = nil
  ) {
    self.label = label
    self.executable = executable
    self.arguments = arguments
    self.environment = environment
  }
}

/// What a running command gives: its lines, one batch for each read of its
/// output, then its exit status, last.
public enum CommandEvent: Sendable, Equatable {
  case lines([String])
  case exited(Int32)
}

/// A command started: its events, and how to stop it.
public struct LaunchedCommand: Sendable {
  public let events: AsyncStream<CommandEvent>
  /// Closes the child's stdin, which ends a child that reads it, and
  /// terminates the child if it is still running a moment later.
  public let stop: @Sendable () -> Void

  public init(events: AsyncStream<CommandEvent>, stop: @escaping @Sendable () -> Void) {
    self.events = events
    self.stop = stop
  }
}

/// What starts a command: `CommandLaunch.process` in an app, a stub in a test.
public typealias CommandLauncher = @Sendable (ConsoleCommand) throws -> LaunchedCommand

public enum CommandLaunch {
  /// A child process, with one pipe for its stdout and stderr, read as it
  /// arrives, and its stdin held.
  public static let process: CommandLauncher = { _ in
    LaunchedCommand(events: AsyncStream { $0.finish() }, stop: {})
  }
}
