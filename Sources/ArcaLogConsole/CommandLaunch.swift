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
/// output, then how it ended, last.
public enum CommandEvent: Sendable, Equatable {
  case lines([String])
  /// It exited, with this status.
  case exited(Int32)
  /// This signal ended it.
  case signalled(Int32)
}

/// A command started: its events, how to stop it, and how many of its lines
/// were dropped.
public struct LaunchedCommand: Sendable {
  public let events: AsyncStream<CommandEvent>
  /// Closes the child's stdin, which ends a child that reads it, and
  /// terminates the child if it is still running a moment later.
  public let stop: @Sendable () -> Void
  /// How many of the command's lines were dropped, the oldest first, because
  /// its console fell behind its output. It is final once `events` has ended.
  public let droppedLines: @Sendable () -> Int

  public init(
    events: AsyncStream<CommandEvent>, stop: @escaping @Sendable () -> Void,
    droppedLines: @escaping @Sendable () -> Int = { 0 }
  ) {
    self.events = events
    self.stop = stop
    self.droppedLines = droppedLines
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
  /// command is stopped, or when its console stops reading it.
  ///
  /// **A CONSOLE THAT FALLS BEHIND LOSES THE OLDEST OUTPUT, AND IS TOLD.** At
  /// most `heldBatches` reads wait for the console. Past them the oldest are
  /// dropped and counted, and the console says how many lines it lost.
  ///
  /// **A RUN ALWAYS ENDS.** A process the child started can hold the output
  /// open after the child has ended. Two seconds after the end, the output is
  /// no longer read, a line says so, and the events end.
  public static let process: CommandLauncher = CommandLaunch.launcher(drain: .seconds(2))

  /// The most reads of a command's output that wait for its console.
  static let heldBatches = 1024

  /// The line that says a command's output is no longer read.
  static let cutLine =
    "warning: the output was still open after the command ended, held by a process it started, so it is no longer read"

  /// `process`, with the output read for `drain` after the child ends.
  static func launcher(drain: DispatchTimeInterval) -> CommandLauncher {
    { command in
      let child = Process()
      child.executableURL = command.executable
      child.arguments = command.arguments
      if let environment = command.environment { child.environment = environment }
      let output = Pipe()
      let input = Pipe()
      child.standardOutput = output
      child.standardError = output
      child.standardInput = input
      let (events, continuation) = AsyncStream.makeStream(
        of: CommandEvent.self, bufferingPolicy: .bufferingNewest(heldBatches))
      let reading = CommandOutput(continuation, from: output.fileHandleForReading, drain: drain)
      output.fileHandleForReading.readabilityHandler = { handle in
        let chunk = handle.availableData
        guard !chunk.isEmpty else {
          handle.readabilityHandler = nil
          reading.closed()
          return
        }
        reading.received(chunk)
      }
      child.terminationHandler = { child in
        let status = child.terminationStatus
        reading.ended(child.terminationReason == .uncaughtSignal ? .signalled(status) : .exited(status))
      }
      do {
        try child.run()
      } catch {
        output.fileHandleForReading.readabilityHandler = nil
        throw error
      }
      let running = Running(child, input: input.fileHandleForWriting)
      // A console that stops reading, as a cancelled run does, stops the child.
      continuation.onTermination = { termination in
        if case .cancelled = termination { running.stop() }
      }
      return LaunchedCommand(events: events, stop: running.stop, droppedLines: { reading.droppedLines })
    }
  }
}

/// A child's output, assembled into lines and handed to its events, as
/// Intent's StreamState does. The readability handler, the termination handler
/// and the drain run on queues of their own, and everything here happens under
/// one lock, so the events keep the order the bytes arrived in, and the end
/// comes last.
private final class CommandOutput: Sendable {
  private struct Progress {
    var assembler = LineAssembler()
    var closed = false
    var end: CommandEvent?
    var finished = false
    var dropped = 0
  }

  private let progress = Mutex(Progress())
  private let continuation: AsyncStream<CommandEvent>.Continuation
  private let output: FileHandle
  private let drain: DispatchTimeInterval

  init(
    _ continuation: AsyncStream<CommandEvent>.Continuation, from output: FileHandle, drain: DispatchTimeInterval
  ) {
    self.continuation = continuation
    self.output = output
    self.drain = drain
  }

  /// The lines dropped so far.
  var droppedLines: Int {
    progress.withLock { $0.dropped }
  }

  func received(_ chunk: Data) {
    progress.withLock { progress in
      guard !progress.finished else { return }
      let lines = progress.assembler.lines(chunk)
      send(lines, &progress)
    }
  }

  /// The end of the output: a last fragment with no newline is a line too.
  func closed() {
    progress.withLock { progress in
      guard !progress.finished else { return }
      let last = progress.assembler.flush().map { [$0] } ?? []
      send(last, &progress)
      progress.closed = true
      finishIfDone(&progress)
    }
  }

  /// The child's end, `.exited` or `.signalled`. The events end once the
  /// output has closed too, or `drain` after the end, whichever comes first.
  func ended(_ end: CommandEvent) {
    let draining = progress.withLock { progress in
      progress.end = end
      finishIfDone(&progress)
      return !progress.finished
    }
    guard draining else { return }
    DispatchQueue.global().asyncAfter(deadline: .now() + drain) { [self] in drained() }
  }

  /// The output still open `drain` after the child ended, held by a process
  /// it started: the fragment held is given up, a line says the output is no
  /// longer read, the events end, and the reading stops.
  private func drained() {
    let cut = progress.withLock { progress in
      guard !progress.finished else { return false }
      let last = progress.assembler.flush().map { [$0] } ?? []
      send(last + [CommandLaunch.cutLine], &progress)
      progress.closed = true
      finishIfDone(&progress)
      return true
    }
    if cut { output.readabilityHandler = nil }
  }

  /// Hands `lines` to the events, when there are any.
  private func send(_ lines: [String], _ progress: inout Progress) {
    guard !lines.isEmpty else { return }
    count(continuation.yield(.lines(lines)), &progress)
  }

  /// **THE EVENTS END WHEN BOTH ENDS HAVE BEEN SEEN.** Output can outlive the
  /// exit by a moment, and ending at the exit alone would lose what the child
  /// wrote last.
  private func finishIfDone(_ progress: inout Progress) {
    guard progress.closed, let end = progress.end, !progress.finished else { return }
    progress.finished = true
    count(continuation.yield(end), &progress)
    continuation.finish()
  }

  /// Counts the lines of a batch the stream dropped to make room for a yield.
  private func count(_ result: AsyncStream<CommandEvent>.Continuation.YieldResult, _ progress: inout Progress) {
    if case .dropped(.lines(let lost)) = result { progress.dropped += lost.count }
  }
}

/// A running child and the write end of its stdin, which the app holds.
private final class Running: Sendable {
  private let child: Process
  private let input: FileHandle
  private let stopped = Mutex(false)

  /// How long a stopped child has to end on its own before it is terminated.
  private static let grace: DispatchTimeInterval = .seconds(1)

  init(_ child: Process, input: FileHandle) {
    self.child = child
    self.input = input
  }

  /// Closes the child's stdin, then terminates it if it is still running
  /// after the grace. A second stop does nothing.
  @Sendable func stop() {
    let first = stopped.withLock { stopped in
      defer { stopped = true }
      return !stopped
    }
    guard first else { return }
    do {
      try input.close()
    } catch {
      // The child then sees no EOF, and the terminate after the grace ends it.
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + Self.grace) { [self] in
      if child.isRunning { child.terminate() }
    }
  }
}
