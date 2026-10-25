import Foundation
import Testing

@testable import ArcaLogConsole

/// A stopped child's grace (WP-11): a launcher made with no grace terminates a
/// stopped command's child at once, for a command that does not end when its
/// stdin closes, as a log follower running a pipeline of its own may not; the
/// default launcher still gives such a child a moment to end first.
/// Acceptance test AT-11.6, in ST0001's acceptance.md.
@MainActor
@Suite("A stopped child's grace")
struct GraceTests {
  /// A `sleep`, which does not read its stdin, so closing it ends nothing.
  static func sleeper(_ seconds: String) -> ConsoleCommand {
    ConsoleCommand(label: "sleep", executable: URL(fileURLWithPath: "/bin/sleep"), arguments: [seconds])
  }

  @Test("with no grace, a stopped child that does not end when its stdin closes is terminated at once")
  func atOnce() async throws {
    let seconds = WindowCloseTests.sleepLength()
    let launched = try CommandLaunch.launcher(grace: nil)(Self.sleeper(seconds))
    try await until { WindowCloseTests.sleeping(seconds) }
    launched.stop()
    // Well inside the default grace, which would leave it running.
    try await Task.sleep(for: .milliseconds(300))
    #expect(!WindowCloseTests.sleeping(seconds), "terminated at once")
  }

  @Test("with the default grace, such a child is still running a moment after its stop, then terminated")
  func afterTheGrace() async throws {
    let seconds = WindowCloseTests.sleepLength()
    let launched = try CommandLaunch.process(Self.sleeper(seconds))
    try await until { WindowCloseTests.sleeping(seconds) }
    launched.stop()
    try await Task.sleep(for: .milliseconds(300))
    #expect(WindowCloseTests.sleeping(seconds), "still within its grace")
    try await until { !WindowCloseTests.sleeping(seconds) }
    #expect(!WindowCloseTests.sleeping(seconds), "terminated once the grace ran out")
  }
}
