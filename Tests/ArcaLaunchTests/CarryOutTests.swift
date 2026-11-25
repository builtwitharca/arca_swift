import Foundation
import Testing

@testable import ArcaLaunch

/// How `begin` carries a decision out (issue 0003), with the app's log and
/// its quit injected: what each decision says, whether the launch path runs,
/// and that only a hand-over quits. `begin` itself is not called here: it
/// takes the app's real lock and would quit the test's process on a
/// hand-over.
/// AT-e69447a3.5 (STc203646d7444f4f1 acceptance.md) cites this file.
@MainActor
@Suite("Carrying a launch out")
struct CarryOutTests {
  /// What `log` was told, and whether `terminate` was called, for one
  /// decision carried out for the app "Menuz".
  private static func carried(_ decision: ArcaLaunch.Decision) -> (goesOn: Bool, logged: [String], quit: Bool) {
    var logged: [String] = []
    var quit = false
    let goesOn = ArcaLaunch.carryOut(decision, app: "Menuz", log: { logged.append($0) }, terminate: { quit = true })
    return (goesOn, logged, quit)
  }

  @Test("a hand-over names the running copy's pid, or that a copy runs, then says how to run this one, and quits")
  func theHandOverSaysSo() {
    let named = Self.carried(.handOver(holder: 777))
    #expect(
      named.logged == ["Menuz already runs as pid 777, so this copy quits. To run this one, quit that copy first."])
    #expect(named.quit)
    #expect(!named.goesOn)
    let unnamed = Self.carried(.handOver(holder: nil))
    #expect(unnamed.logged == ["Menuz already runs, so this copy quits. To run this one, quit that copy first."])
  }

  @Test("XCTest's host goes no further than saying so, and quits nothing")
  func aHostGoesNoFurther() {
    let host = Self.carried(.testHost)
    #expect(!host.goesOn)
    #expect(!host.quit)
    #expect(host.logged == ["XCTest hosts this process, so the launch path is skipped"])
  }

  @Test("a launch goes on, and a launch without the lock says why, and neither quits")
  func aLaunchGoesOn() {
    let locked = Self.carried(.launch)
    #expect(locked.goesOn)
    #expect(!locked.quit)
    #expect(locked.logged.isEmpty)
    let unlocked = Self.carried(.launchUnlocked(reason: "could not make /nowhere: disk full"))
    #expect(unlocked.goesOn)
    #expect(!unlocked.quit)
    #expect(
      unlocked.logged == [
        "No instance lock, so another copy may run beside this one: could not make /nowhere: disk full"
      ])
  }
}
