import Foundation
import Testing

@testable import ArcaLaunch

/// What a launch does before any side effect (issue 0003), walked without
/// launching anything: the decision over an injected lock, and the instance
/// lock on temporary files. Moved from Conflab's LaunchDecisionTests
/// (ConflabTests/LaunchDecisionTests.swift, 08b94be5), with its names made
/// arca_swift's: LaunchDecision is ArcaLaunch, and InstanceLock.appFile is
/// InstanceLock.file(app:). Its delegate's hand-over test is
/// CarryOutTests.theHandOverSaysSo here.
/// AT-e69447a3.3 and AT-e69447a3.4 (STc203646d7444f4f1 acceptance.md) cite
/// this file.
@Suite("Launch decision")
struct LaunchDecisionTests {
  private static let host = ["XCTestConfigurationFilePath": "/tmp/Conflab.xctestconfiguration"]
  private static let person = ["HOME": "/Users/someone", "PATH": "/usr/bin:/bin"]

  /// A lock file in a folder of the test's own, which the lock makes.
  private static func freshLock() -> (folder: URL, file: URL) {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("arca-lock-tests-\(UUID().uuidString)", isDirectory: true)
    return (folder, folder.appendingPathComponent("instance.lock"))
  }

  /// Remove what a test made, and say so if it cannot.
  private static func remove(_ url: URL) {
    #expect(throws: Never.self) { try FileManager.default.removeItem(at: url) }
  }

  /// Holds `file` as another copy would, with `pid` recorded in it, or nothing
  /// recorded when it is nil. The caller closes the descriptor.
  private static func holdAsAnotherCopy(_ file: URL, recording pid: String?) throws -> Int32 {
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    let fd = open(file.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
    try #require(fd >= 0)
    do {
      if let pid {
        let text = Array("\(pid)\n".utf8)
        try #require(pwrite(fd, text, text.count, 0) == text.count)
      }
      try #require(flock(fd, LOCK_EX | LOCK_NB) == 0)
    } catch {
      close(fd)
      throw error
    }
    return fd
  }

  // MARK: - The decision

  @Test("XCTest's host never asks for the lock, so it never hands over and no copy hands over to it")
  func aHostTakesNoLock() {
    var asked = false
    let decision = ArcaLaunch.decide(
      environment: Self.host,
      acquire: {
        asked = true
        return .held(by: 777)
      })
    #expect(decision == .testHost)
    #expect(!asked)
  }

  @Test("a copy that takes the lock runs the launch path")
  func takesTheLock() {
    #expect(ArcaLaunch.decide(environment: Self.person, acquire: { .acquired }) == .launch)
  }

  @Test("a copy that finds the lock held hands over, naming the holder when it recorded its pid")
  func findsTheLockHeld() {
    #expect(ArcaLaunch.decide(environment: Self.person, acquire: { .held(by: 777) }) == .handOver(holder: 777))
    #expect(ArcaLaunch.decide(environment: Self.person, acquire: { .held(by: nil) }) == .handOver(holder: nil))
  }

  @Test("a lock that cannot be taken runs the launch path anyway, and says why")
  func cannotTakeTheLock() {
    #expect(
      ArcaLaunch.decide(environment: Self.person, acquire: { .failed("disk full") })
        == .launchUnlocked(reason: "disk full"))
  }

  // MARK: - The instance lock

  @Test("every copy, of either build, locks the same file, in the app's own Application Support folder")
  func theAppLocksOneFile() {
    #expect(
      InstanceLock.file(app: "Menuz").path == NSHomeDirectory() + "/Library/Application Support/Menuz/instance.lock")
  }

  @Test("the first copy takes the lock, and a second is refused and told the holder's pid")
  func aSecondIsRefused() {
    let (folder, file) = Self.freshLock()
    defer { Self.remove(folder) }
    let first = InstanceLock(file: file)
    #expect(first.acquire() == .acquired)
    #expect(first.isHeld)
    withExtendedLifetime(first) {
      let second = InstanceLock(file: file)
      #expect(second.acquire() == .held(by: ProcessInfo.processInfo.processIdentifier))
      #expect(!second.isHeld)
    }
  }

  @Test("a lock its holder released can be taken again")
  func aReleasedLockIsTakenAgain() {
    let (folder, file) = Self.freshLock()
    defer { Self.remove(folder) }
    do {
      let first = InstanceLock(file: file)
      #expect(first.acquire() == .acquired)
    }
    #expect(InstanceLock(file: file).acquire() == .acquired)
  }

  /// A flock belongs to the open file, so a child that inherited the descriptor
  /// would keep the lock held after the app let it go, and the next launch would
  /// hand over to no copy. The holder is kept alive across the spawn, so the
  /// child starts while the lock is held.
  @Test("a command started while the lock is held does not keep it once its holder lets go")
  func aChildDoesNotKeepTheLock() throws {
    let (folder, file) = Self.freshLock()
    defer { Self.remove(folder) }
    let args: [String] = ["/bin/sleep", "30"]
    let argv = args.map { strdup($0) } + [nil]
    defer {
      for arg in argv { free(arg) }
    }
    let envp: [UnsafeMutablePointer<CChar>?] = [nil]
    var child: pid_t = 0
    do {
      let holder = InstanceLock(file: file)
      try #require(holder.acquire() == .acquired)
      try withExtendedLifetime(holder) {
        try #require(posix_spawn(&child, "/bin/sleep", nil, nil, argv, envp) == 0)
      }
    }
    defer {
      if child > 0 {
        kill(child, SIGKILL)
        waitpid(child, nil, 0)
      }
    }
    // The child must still run, or a lock it had kept would be gone with it.
    #expect(kill(child, 0) == 0)
    #expect(InstanceLock(file: file).acquire() == .acquired)
  }

  /// Conflab's contract (its ST0125 design, decision 7) promises these bytes
  /// to the lock's readers outside the app, so they are read here raw:
  /// InstanceLock's own reader trims whitespace, so it would pass bytes the
  /// contract forbids. The app never removes the file, so each holder writes
  /// over the last one's line: the file starts out longer than this pid's
  /// line, so a tail left untruncated shows.
  @Test("the holder records its pid as decimal digits and one newline, and nothing else")
  func theHolderRecordsItsPid() throws {
    let (folder, file) = Self.freshLock()
    defer { Self.remove(folder) }
    let line = Array("\(ProcessInfo.processInfo.processIdentifier)\n".utf8)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(line + line).write(to: file)
    let holder = InstanceLock(file: file)
    try #require(holder.acquire() == .acquired)
    let bytes = try withExtendedLifetime(holder) { try Data(contentsOf: file) }
    #expect([UInt8](bytes) == line)
  }

  /// A holder takes the lock before it records its pid, so a copy can find it
  /// held with the file still empty.
  @Test("a lock held with no pid recorded yet is reported held by an unknown copy")
  func aHolderWithNoPidYet() throws {
    let (folder, file) = Self.freshLock()
    defer { Self.remove(folder) }
    let fd = try Self.holdAsAnotherCopy(file, recording: nil)
    defer { close(fd) }
    #expect(InstanceLock(file: file).acquire() == .held(by: nil))
  }

  /// The same window can leave the last holder's pid in the file. XNU's pids
  /// stop below 100000, so this one never runs.
  @Test("a recorded pid that no longer runs is not named")
  func aStalePidIsNotNamed() throws {
    let (folder, file) = Self.freshLock()
    defer { Self.remove(folder) }
    let fd = try Self.holdAsAnotherCopy(file, recording: "999999")
    defer { close(fd) }
    #expect(InstanceLock(file: file).acquire() == .held(by: nil))
  }

  @Test("a path that cannot hold a lock fails, naming where it could not")
  func aPathThatCannotHoldALock() throws {
    let (folder, _) = Self.freshLock()
    defer { Self.remove(folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    let blocker = folder.appendingPathComponent("blocker")
    try Data().write(to: blocker)
    let lock = InstanceLock(file: blocker.appendingPathComponent("instance.lock"))
    let outcome = lock.acquire()
    #expect(!lock.isHeld)
    guard case .failed(let reason) = outcome else {
      Issue.record("a lock under a file answered \(outcome)")
      return
    }
    #expect(reason.contains(blocker.path))
  }
}
