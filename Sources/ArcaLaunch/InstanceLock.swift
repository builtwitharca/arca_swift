import Foundation
import OSLog

/// The lock that the copy of an app that launches holds for as long as it
/// runs: an exclusive `flock` on a file, which the kernel drops when its
/// holder exits, however it exits, so it is never stale. The holder records
/// its pid in the file, for the line that a copy which finds the lock held
/// prints. The file's path, the lock and the pid's bytes keep Conflab's
/// contract (its ST0125 design, decision 7): a reader outside the app opens
/// the file read-only and close-on-exec, never creates it, and probes with a
/// shared lock. Moved from Conflab's InstanceLock (08b94be5).
final class InstanceLock {
  /// What taking the lock found.
  enum Outcome: Equatable, Sendable {
    case acquired
    case held(by: pid_t?)
    case failed(String)
  }

  private static let logger = Logger(subsystem: "com.builtwitharca.arca_swift", category: "InstanceLock")
  private let file: URL
  private var descriptor: Int32?

  /// The lock file of the app named `app`, in the app's own folder in the
  /// user's Application Support. Debug and Release builds share it, so only
  /// one of them runs at a time.
  static func file(app: String) -> URL {
    URL.applicationSupportDirectory
      .appending(path: app, directoryHint: .isDirectory)
      .appending(path: "instance.lock", directoryHint: .notDirectory)
  }

  init(file: URL) {
    self.file = file
  }

  deinit {
    if let descriptor { close(descriptor) }
  }

  var isHeld: Bool { descriptor != nil }

  /// Takes the lock without waiting. Asked again once held, it answers
  /// `.acquired` and changes nothing.
  func acquire() -> Outcome {
    guard descriptor == nil else { return .acquired }
    let folder = file.deletingLastPathComponent()
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    } catch {
      return .failed("could not make \(folder.path): \(error.localizedDescription)")
    }
    // Closed on exec, so no command the app runs keeps the lock after the app exits.
    let fd = open(file.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
    guard fd >= 0 else {
      let error = errno
      return .failed("could not open \(file.path): \(Self.describe(error))")
    }
    guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
      let error = errno
      defer { close(fd) }
      guard error == EWOULDBLOCK else { return .failed("could not lock \(file.path): \(Self.describe(error))") }
      return .held(by: holder(fd))
    }
    descriptor = fd
    record(ProcessInfo.processInfo.processIdentifier, in: fd)
    return .acquired
  }

  /// Records this process's pid, in the bytes that Conflab's contract fixes,
  /// for a copy that finds the lock held and for the contract's other
  /// readers. A failure costs a reader only the pid, never the lock, so it
  /// is logged and the lock kept.
  private func record(_ pid: pid_t, in fd: Int32) {
    let text = Array("\(pid)\n".utf8)
    if ftruncate(fd, 0) != 0 || pwrite(fd, text, text.count, 0) != text.count {
      let reason = Self.describe(errno)
      Self.logger.error(
        "Holding the lock, but no pid recorded in \(self.file.path, privacy: .public): \(reason, privacy: .public)")
    }
  }

  /// The pid the holder recorded, or nil when it has recorded none yet or the
  /// one recorded no longer runs. A copy records its pid only once it holds
  /// the lock, so a copy refused in between reads the last holder's, or
  /// nothing.
  private func holder(_ fd: Int32) -> pid_t? {
    var bytes = [UInt8](repeating: 0, count: 32)
    let count = pread(fd, &bytes, bytes.count, 0)
    guard count >= 0 else {
      let reason = Self.describe(errno)
      Self.logger.error(
        "Could not read the holder's pid from \(self.file.path, privacy: .public): \(reason, privacy: .public)")
      return nil
    }
    let text = String(decoding: bytes[..<count], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let pid = pid_t(text), pid > 0, kill(pid, 0) == 0 || errno == EPERM else { return nil }
    return pid
  }

  private static func describe(_ error: Int32) -> String {
    String(cString: strerror(error))
  }
}
