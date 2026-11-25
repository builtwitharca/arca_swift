import AppKit
import Foundation

/// What a menu bar app does first at launch, before any side effect (issue
/// 0003): it skips its launch path when XCTest hosts the process; runs it,
/// holding the instance lock, or without the lock when the lock cannot be
/// taken; or hands over to the copy that holds the lock. The running copy
/// wins, as a macOS app's does. So replacing an older running build is the
/// app's install step's job, never this check's: quit it, wait for it to
/// exit, then open the new build. Moved from Conflab's LaunchDecision and its
/// delegate's hand-over (Conflab ST0125/WP-07, 08b94be5).
public enum ArcaLaunch {
  /// What a launch does.
  public enum Decision: Equatable, Sendable {
    case testHost
    case launch
    case launchUnlocked(reason: String)
    case handOver(holder: pid_t?)
  }

  /// Whether `begin` let the launch path run. An app's
  /// `applicationWillTerminate` starts with `guard ArcaLaunch.launched`, so
  /// a copy that handed over, or XCTest's host, tears down nothing it never
  /// set up.
  @MainActor public private(set) static var launched = false

  /// The lock this copy holds, kept for the life of the process. The kernel
  /// drops it when the process exits, however it exits.
  @MainActor private static var held: InstanceLock?

  /// The call an app's `applicationDidFinishLaunching` makes first:
  ///
  ///     guard ArcaLaunch.begin(app: "Menuz", log: { Log.write($0) }) else { return }
  ///
  /// `app` names the app's folder in the user's Application Support, which
  /// holds the lock file. True when the app goes on with its launch path. A
  /// copy that hands over says so on stderr and to `log`, and quits.
  @MainActor
  public static func begin(app: String, log: (String) -> Void) -> Bool {
    let lock = InstanceLock(file: InstanceLock.file(app: app))
    let decision = decide(environment: ProcessInfo.processInfo.environment, acquire: lock.acquire)
    let goesOn = carryOut(decision, app: app, log: log) { NSApplication.shared.terminate(nil) }
    if goesOn {
      held = lock
      launched = true
    }
    return goesOn
  }

  /// Whether XCTest hosts this process (Gtools' gtools#0050): xcodebuild
  /// sets `XCTestConfigurationFilePath` in the host, and a launch at login
  /// or by `open` has none. Its presence counts, never its value: under
  /// Xcode 27.1 xcodebuild sets it empty (Conflab, 25 Oct 2026).
  public static func isTestHost(_ environment: [String: String]) -> Bool {
    environment["XCTestConfigurationFilePath"] != nil
  }

  /// Asks for the lock only once the test-host check has passed, so XCTest's
  /// host never takes it, and no copy ever hands over to a host.
  static func decide(environment: [String: String], acquire: () -> InstanceLock.Outcome) -> Decision {
    guard !isTestHost(environment) else { return .testHost }
    switch acquire() {
    case .acquired: return .launch
    case .held(let holder): return .handOver(holder: holder)
    case .failed(let reason): return .launchUnlocked(reason: reason)
    }
  }

  /// What a copy that hands over says, naming the running copy's pid when
  /// that copy recorded one.
  static func handOverLine(app: String, holder: pid_t?) -> String {
    let running = holder.map { "\(app) already runs as pid \($0)" } ?? "\(app) already runs"
    return "\(running), so this copy quits. To run this one, quit that copy first."
  }

  /// Carries `decision` out, and says whether the launch path runs. A copy
  /// that hands over says so to `log`, and on stderr for a launch from a
  /// shell, then calls `terminate`, which quits the app; a test passes its
  /// own.
  @MainActor
  static func carryOut(
    _ decision: Decision, app: String, log: (String) -> Void, terminate: () -> Void
  ) -> Bool {
    switch decision {
    case .testHost:
      log("XCTest hosts this process, so the launch path is skipped")
      return false
    case .handOver(let holder):
      let line = handOverLine(app: app, holder: holder)
      log(line)
      do {
        try FileHandle.standardError.write(contentsOf: Data((line + "\n").utf8))
      } catch {
        log("Could not write the hand-over to stderr: \(error.localizedDescription)")
      }
      terminate()
      return false
    case .launchUnlocked(let reason):
      log("No instance lock, so another copy may run beside this one: \(reason)")
      return true
    case .launch:
      return true
    }
  }
}
