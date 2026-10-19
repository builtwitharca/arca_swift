import ArcaLogConsole
import Foundation

/// The lines a source delivered, gathered for a test to wait on. A source
/// delivers on its own queue, so the lines are kept under a lock.
final class Delivered: @unchecked Sendable {
  private let lock = NSLock()
  private var batches: [[ConsoleLine]] = []

  func add(_ batch: [ConsoleLine]) {
    lock.withLock { batches.append(batch) }
  }

  var lines: [ConsoleLine] {
    lock.withLock { batches.flatMap { $0 } }
  }

  var texts: [String] {
    lines.map(\.text)
  }

  /// The texts once at least `count` lines have arrived, or what has
  /// arrived when `timeout` runs out first.
  func texts(atLeast count: Int, timeout: Duration = .seconds(5)) async throws -> [String] {
    let deadline = ContinuousClock.now + timeout
    while texts.count < count, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    return texts
  }

  /// The texts after `quiet` has passed, for a test that nothing more
  /// arrives.
  func texts(after quiet: Duration) async throws -> [String] {
    try await Task.sleep(for: quiet)
    return texts
  }
}
