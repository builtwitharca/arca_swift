import Foundation

/// A file the app names, followed in-process, with no child process (design.md
/// "ArcaLogConsole"). A dispatch source watches the open file, and another
/// the nearest folder there is on the way to it, and at each event the file
/// open is checked against the one at the path, by identity and size
/// (`FileChange`).
///
/// **A TRUNCATED FILE IS READ AGAIN FROM THE START.** A file smaller than what
/// has been read was cut short in place, so what is held of its last line is
/// given up as a line, and reading starts again at its first byte.
///
/// **A RENAMED FILE IS DRAINED TO ITS END** before the path is opened again, so
/// the lines written before the rename still arrive, a last one with no
/// newline among them. A new file at the path is then read from its start: a
/// daemon that rotates its log renames it aside and makes a new one.
///
/// **A FILE THAT IS NOT THERE YET** is picked up by its folder's source when it
/// is made, and a folder that is not there yet is waited for on the nearest
/// folder above it that is. Each source looks again once it is registered,
/// for what changed before it could see it.
///
/// **A READ PASS IS BOUNDED.** A pass reads at most the read window, the newest
/// of what lies ahead, so a large new file, or one that replaced the last, is
/// never read whole: the pass starts at the first line that starts in the
/// window, and a marker line says how many bytes it passed over.
///
/// **A FAILURE IS SAID** as an error line, once while it lasts: a file or a
/// folder that is there but cannot be opened, read or watched. Only a file
/// that is not there yet is waited for in silence.
///
/// Everything happens on the follower's own queue, off the main actor, and
/// each event hands `deliver` at most one batch, its failures included. `stop`
/// waits for the queue, so `deliver`, which runs there, must not call it.
final class FileFollower: @unchecked Sendable {
  // @unchecked: every property below `deliver` is read and written on `queue`
  // alone, which serialises them, or in deinit, when nothing else holds the
  // follower.
  private let queue = DispatchQueue(label: "ArcaLogConsole.FileFollower")
  private let path: String
  private let source: ConsoleSource
  private let classify: ConsoleClassifier
  private let backlog: Int
  private let window: off_t
  private let deliver: @Sendable ([ConsoleLine]) -> Void

  private var file: (source: DispatchSourceFileSystemObject, descriptor: Int32, identity: FileIdentity)?
  private var folder: (source: DispatchSourceFileSystemObject, path: String, identity: FileIdentity)?
  private var offset: off_t = 0
  private var assembler = LineAssembler()
  /// The bytes a read pass has passed over, while it waits for the first
  /// line that starts after them; nil while it reads whole lines.
  private var skipping: off_t?
  private var running = false
  /// The event's lines, handed on as one batch at its end.
  private var batch: [ConsoleLine] = []
  /// The last failure said, so a failure that lasts is said once.
  private var failure: String?

  /// The most one read pass reads, and so the most a replay reads back.
  static let readWindow: off_t = 256 * 1024

  /// Follows `path`, its lines from `source` and of the kind `classify`
  /// gives, each batch handed to `deliver` on the follower's own queue.
  /// Opening replays the file's last `backlog` lines, and none for a
  /// negative one.
  init(
    path: String, source: ConsoleSource, classify: @escaping ConsoleClassifier = ConsoleClassify.standard,
    backlog: Int = 40, window: off_t = FileFollower.readWindow,
    deliver: @escaping @Sendable ([ConsoleLine]) -> Void
  ) {
    precondition(window > 0, "a read pass reads something")
    self.path = path
    self.source = source
    self.classify = classify
    self.backlog = max(0, backlog)
    self.window = window
    self.deliver = deliver
  }

  deinit {
    // A follower let go without a stop: the cancel handlers close the
    // descriptors.
    file?.source.cancel()
    folder?.source.cancel()
  }

  /// Starts following, on the follower's queue: the file's last lines, then
  /// each change.
  func start() {
    queue.async { [self] in
      guard !running else { return }
      running = true
      watchFolder()
      if open() { take(Array(readOn(saying: false).suffix(backlog))) }
      handOn()
    }
  }

  /// Stops following. It waits for the queue, so nothing is delivered once
  /// it returns.
  func stop() {
    queue.sync { [self] in
      running = false
      batch = []
      close()
      folder?.source.cancel()
      folder = nil
    }
  }

  // MARK: - The file

  /// Opens the file at the path, if there is one, and watches it.
  private func open() -> Bool {
    let descriptor = Darwin.open(path, O_RDONLY | O_CLOEXEC)
    guard descriptor >= 0 else {
      let code = errno
      if code != ENOENT { failed("open", code) }
      return false
    }
    var info = stat()
    guard fstat(descriptor, &info) == 0 else {
      failed("read")
      Darwin.close(descriptor)
      return false
    }
    let watch = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor, eventMask: .all, queue: queue)
    watch.setEventHandler { [weak self] in self?.changed() }
    watch.setRegistrationHandler { [weak self] in self?.changed() }
    watch.setCancelHandler { Darwin.close(descriptor) }
    watch.resume()
    file = (watch, descriptor, FileIdentity(info))
    failure = nil
    offset = 0
    skipping = nil
    assembler = LineAssembler()
    return true
  }

  /// Stops watching the open file. Its source's cancel handler closes it.
  private func close() {
    file?.source.cancel()
    file = nil
  }

  /// One event, on the file or its folder: what has changed is decided from
  /// the file open and the one at the path, and its lines are handed on as
  /// one batch.
  private func changed() {
    guard running else { return }
    defer { handOn() }
    guard let file else {
      if open() { take(readOn()) }
      return
    }
    var info = stat()
    guard fstat(file.descriptor, &info) == 0 else {
      failed("read")
      return
    }
    let size = info.st_size
    let atPath: FileIdentity?
    if stat(path, &info) == 0 {
      atPath = FileIdentity(info)
    } else {
      let code = errno
      guard code == ENOENT || code == ENOTDIR else {
        // Whether the path still names the open file is not known: say so,
        // and read on from the file open.
        failed("check", code)
        take(readOn())
        return
      }
      atPath = nil
    }
    let change = FileChange.decide(open: file.identity, atPath: atPath, size: size, read: offset)
    switch change {
    case .appended:
      take(readOn())
    case .truncated:
      takeFragment()
      offset = 0
      take(readOn())
    case .replaced, .removed:
      take(readOn())
      takeFragment()
      close()
      if change == .replaced, open() { take(readOn()) }
    }
  }

  /// One read pass: the lines from `offset` to the file's end as it is now,
  /// and at most the read window of it. When more lies ahead, as in a large
  /// new file or one that replaced the last, the line held is given up, and
  /// the pass reads the window's end of it alone, from the first line that
  /// starts there; then, with `saying`, a marker line says how many bytes
  /// were passed over.
  private func readOn(saying: Bool = true) -> [String] {
    guard let file else { return [] }
    var info = stat()
    guard fstat(file.descriptor, &info) == 0 else {
      failed("read")
      return []
    }
    let end = info.st_size
    if end - offset > window {
      takeFragment()
      // From the byte before the window, so a line that starts with the
      // window is kept.
      skipping = (skipping ?? 0) + (end - window - 1 - offset)
      offset = end - window - 1
    }
    var bytes = read(to: end)
    if let passed = skipping {
      guard let newline = bytes.firstIndex(of: 0x0A) else {
        skipping = passed + off_t(bytes.count)
        return []
      }
      skipping = nil
      bytes.removeFirst(newline + 1)
      if saying {
        batch.append(.marker("skipped \(passed + off_t(newline) + 1) bytes of \(path)", source: source))
      }
    }
    return assembler.lines(bytes)
  }

  /// The bytes from `offset` to `end`, with `offset` moved past those read.
  private func read(to end: off_t) -> [UInt8] {
    guard let file, end > offset else { return [] }
    var bytes = [UInt8](repeating: 0, count: Int(end - offset))
    var count = 0
    while count < bytes.count {
      let got = bytes.withUnsafeMutableBytes { buffer in
        pread(file.descriptor, buffer.baseAddress! + count, buffer.count - count, offset + off_t(count))
      }
      if got < 0 {
        failed("read")
        break
      }
      // A file cut short while it is read ends the pass early, and the next
      // event finds the truncation.
      guard got > 0 else { break }
      count += got
    }
    offset += off_t(count)
    return Array(bytes[..<count])
  }

  // MARK: - The folder

  /// Watches the nearest folder there is on the way to the file: its own,
  /// which sees the file made, renamed or removed; or, while that is not
  /// there, the nearest one above it, which sees the next folder down made.
  /// A folder already watched is kept.
  private func watchFolder() {
    let directory = (path as NSString).deletingLastPathComponent
    guard let nearest = Self.nearestFolder(to: directory) else {
      folder?.source.cancel()
      folder = nil
      fail("could not watch \(directory): no folder on the way to it is there")
      return
    }
    if let folder, folder.path == nearest, folder.identity == Self.identity(at: nearest) { return }
    folder?.source.cancel()
    folder = nil
    let descriptor = Darwin.open(nearest, O_EVTONLY | O_CLOEXEC)
    guard descriptor >= 0 else {
      failed("watch", errno, nearest)
      return
    }
    var info = stat()
    guard fstat(descriptor, &info) == 0 else {
      failed("watch", errno, nearest)
      Darwin.close(descriptor)
      return
    }
    let watch = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: queue)
    watch.setEventHandler { [weak self] in self?.folderChanged() }
    watch.setRegistrationHandler { [weak self] in self?.folderChanged() }
    watch.setCancelHandler { Darwin.close(descriptor) }
    watch.resume()
    folder = (watch, nearest, FileIdentity(info))
  }

  /// A folder on the way changed, or its source was registered: the nearest
  /// folder may have moved, and the file may be there now.
  private func folderChanged() {
    guard running else { return }
    watchFolder()
    changed()
  }

  /// `directory` when it is a folder that is there, or else the nearest
  /// folder above it that is; nil when there is none.
  static func nearestFolder(to directory: String) -> String? {
    var url = URL(fileURLWithPath: directory).standardizedFileURL
    while true {
      var isFolder: ObjCBool = false
      if FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue {
        return url.path
      }
      guard url.path != "/" else { return nil }
      url.deleteLastPathComponent()
    }
  }

  /// The identity of what is at `path`, or nil when it cannot be read.
  static func identity(at path: String) -> FileIdentity? {
    var info = stat()
    return stat(path, &info) == 0 ? FileIdentity(info) : nil
  }

  // MARK: - Delivery

  /// Adds `texts` to the event's batch, as the source's lines.
  private func take(_ texts: [String]) {
    batch += ConsoleLine.lines(texts, source: source, classify: classify)
  }

  /// Gives up the line held, as a line, since nothing more will finish it.
  private func takeFragment() {
    if let fragment = assembler.flush() { take([fragment]) }
  }

  /// Hands the event's batch on, when it has lines.
  private func handOn() {
    defer { batch = [] }
    guard running, !batch.isEmpty else { return }
    deliver(batch)
  }

  /// Says a failure to `doing` `subject`, the file unless another is named,
  /// with the reason `code` gives.
  private func failed(_ doing: String, _ code: Int32 = errno, _ subject: String? = nil) {
    fail("could not \(doing) \(subject ?? path): \(String(cString: strerror(code)))")
  }

  /// Says a failure as an error line in the event's batch, once while it
  /// lasts.
  private func fail(_ text: String) {
    guard running, text != failure else { return }
    failure = text
    batch.append(ConsoleLine(text: text, kind: .error, source: source))
  }
}

/// A file's identity: its device and inode, which a rename keeps and a new
/// file at the same path does not.
struct FileIdentity: Equatable, Sendable {
  let device: dev_t
  let inode: ino_t
}

extension FileIdentity {
  init(_ info: stat) {
    self.init(device: info.st_dev, inode: info.st_ino)
  }
}

/// What one event on a followed file means (design.md "ArcaLogConsole"),
/// decided from the identity of the file open, the identity of the file at
/// the path, the open file's size, and how far it has been read.
enum FileChange: Equatable, Sendable {
  /// The path names the open file, which is no shorter than what was read:
  /// read on.
  case appended
  /// The path names the open file, which is shorter than what was read: it
  /// was cut short in place, so the line held is given up, and it is read
  /// again from its start.
  case truncated
  /// The path names another file: the open one is drained to its end, and
  /// then the path's is followed from its start.
  case replaced
  /// The path names no file: the open one is drained to its end, and the
  /// folder's source waits for the next.
  case removed

  static func decide(open: FileIdentity, atPath: FileIdentity?, size: off_t, read offset: off_t) -> FileChange {
    guard let atPath else { return .removed }
    guard atPath == open else { return .replaced }
    return size < offset ? .truncated : .appended
  }
}
