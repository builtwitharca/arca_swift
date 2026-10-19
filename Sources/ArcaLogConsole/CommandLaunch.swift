import Foundation
import Synchronization

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
  ///
  /// **THE CHILD'S STDIN IS HELD, SO IT DIES WITH THE APP.** The app keeps the
  /// pipe's write end, so a child that reads its stdin, as a `--follow` verb
  /// does, sees it close when the app quits, however it quits, or when the
  /// command is stopped.
  public static let process: CommandLauncher = { command in
    let child = Process()
    child.executableURL = command.executable
    child.arguments = command.arguments
    if let environment = command.environment { child.environment = environment }
    let output = Pipe()
    let input = Pipe()
    child.standardOutput = output
    child.standardError = output
    child.standardInput = input
    let (events, continuation) = AsyncStream<CommandEvent>.makeStream()
    let reading = CommandOutput(continuation)
    output.fileHandleForReading.readabilityHandler = { handle in
      let chunk = handle.availableData
      guard !chunk.isEmpty else {
        handle.readabilityHandler = nil
        reading.closed()
        return
      }
      reading.received(chunk)
    }
    child.terminationHandler = { reading.exited($0.terminationStatus) }
    do {
      try child.run()
    } catch {
      output.fileHandleForReading.readabilityHandler = nil
      throw error
    }
    let running = Running(child, input: input.fileHandleForWriting)
    return LaunchedCommand(events: events, stop: running.stop)
  }
}

/// A child's output, assembled into lines and handed to its events, as
/// Intent's StreamState does. The readability handler and the termination
/// handler run on queues of their own, and everything here happens under one
/// lock, so the events keep the order the bytes arrived in and the exit comes
/// last.
final class CommandOutput: Sendable {
  private struct Progress {
    var assembler = LineAssembler()
    var closed = false
    var status: Int32?
    var finished = false
  }

  private let progress = Mutex(Progress())
  private let continuation: AsyncStream<CommandEvent>.Continuation

  init(_ continuation: AsyncStream<CommandEvent>.Continuation) {
    self.continuation = continuation
  }

  func received(_ chunk: Data) {
    progress.withLock { progress in
      let lines = progress.assembler.lines(chunk)
      if !lines.isEmpty { continuation.yield(.lines(lines)) }
    }
  }

  /// The end of the output: a last fragment with no newline is a line too.
  func closed() {
    progress.withLock { progress in
      if let last = progress.assembler.flush() { continuation.yield(.lines([last])) }
      progress.closed = true
      finishIfDone(&progress)
    }
  }

  func exited(_ status: Int32) {
    progress.withLock { progress in
      progress.status = status
      finishIfDone(&progress)
    }
  }

  /// **THE EVENTS END WHEN BOTH ENDS HAVE BEEN SEEN.** Output can outlive the
  /// exit by a moment, and ending at the exit alone would lose what the child
  /// wrote last.
  private func finishIfDone(_ progress: inout Progress) {
    guard progress.closed, let status = progress.status, !progress.finished else { return }
    progress.finished = true
    continuation.yield(.exited(status))
    continuation.finish()
  }
}

/// A running child and the write end of its stdin, which the app holds.
final class Running: @unchecked Sendable {
  // @unchecked: Process is not Sendable. `stop` reads the child's state and
  // calls its terminate, both of which Process allows from any thread.
  private let child: Process
  private let input: FileHandle

  /// How long a stopped child has to end on its own before it is terminated.
  static let grace: DispatchTimeInterval = .seconds(1)

  init(_ child: Process, input: FileHandle) {
    self.child = child
    self.input = input
  }

  /// Closes the child's stdin, then terminates it if it is still running
  /// after the grace.
  @Sendable func stop() {
    do {
      try input.close()
    } catch {
      // Already closed by an earlier stop: the child has its EOF.
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + Self.grace) { [self] in
      if child.isRunning { child.terminate() }
    }
  }
}
