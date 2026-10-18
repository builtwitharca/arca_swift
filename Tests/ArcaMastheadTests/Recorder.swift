/// What a test's closures were given: each value in order, and as it comes,
/// for a test that waits on one. Its stream is read once.
@MainActor
final class Recorder<Value: Sendable> {
  private(set) var all: [Value] = []
  /// Each value, as it is recorded.
  let stream: AsyncStream<Value>
  private let continuation: AsyncStream<Value>.Continuation

  init() {
    let made = AsyncStream.makeStream(of: Value.self)
    stream = made.stream
    continuation = made.continuation
  }

  func record(_ value: Value) {
    all.append(value)
    continuation.yield(value)
  }
}
