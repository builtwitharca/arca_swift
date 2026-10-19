import Foundation

/// A file the app names, followed in-process, with no child process (design.md
/// "ArcaLogConsole"). A dispatch source watches the open file and another its
/// folder, and at each event the file open is checked against the one at the
/// path, by identity and size.
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
/// **A FILE THAT IS NOT THERE YET** is picked up by the folder's source when it
/// is made, and a folder that is not there yet is waited for on the nearest
/// folder above it that is.
///
/// Everything happens on the follower's own queue, off the main actor, and
/// each event hands `deliver` at most one batch.
public final class FileFollower: @unchecked Sendable {
  // @unchecked: every property below `deliver` is read and written on `queue`
  // alone, which serialises them.
  private let queue = DispatchQueue(label: "ArcaLogConsole.FileFollower")
  private let path: String
  private let source: ConsoleSource
  private let classify: ConsoleClassifier
  private let backlog: Int
  private let deliver: @Sendable ([ConsoleLine]) -> Void

  private var file: (source: DispatchSourceFileSystemObject, descriptor: Int32, identity: Identity)?
  private var folder: DispatchSourceFileSystemObject?
  private var offset: off_t = 0
  private var assembler = LineAssembler()
  private var running = false
  /// The last failure said, so a failure that lasts is said once.
  private var failure: String?

  private typealias Identity = (device: dev_t, inode: ino_t)

  /// The most a replay reads back from the end of the file for its lines.
  static let replayWindow: off_t = 256 * 1024

  /// Follows `path`, its lines from `source` and of the kind `classify`
  /// gives, each batch handed to `deliver` on the follower's own queue.
  /// Opening replays the file's last `backlog` lines.
  public init(
    path: String, source: ConsoleSource,
    classify: @escaping ConsoleClassifier = ConsoleClassify.standard,
    backlog: Int = 40, deliver: @escaping @Sendable ([ConsoleLine]) -> Void
  ) {
    self.path = path
    self.source = source
    self.classify = classify
    self.backlog = backlog
    self.deliver = deliver
  }

  /// Starts following: the file's last lines, then each change.
  public func start() {
    queue.sync { [self] in
      guard !running else { return }
      running = true
      watchFolder()
      if open() { hand(replay()) }
    }
  }

  /// Stops following. Nothing is delivered once it returns.
  public func stop() {
    queue.sync { [self] in
      running = false
      close()
      folder?.cancel()
      folder = nil
    }
  }

  // MARK: - The file

  /// Opens the file at the path, if there is one, and watches it.
  private func open() -> Bool {
    let descriptor = Darwin.open(path, O_RDONLY | O_CLOEXEC)
    guard descriptor >= 0 else {
      if errno != ENOENT { fail("could not open \(path): \(String(cString: strerror(errno)))") }
      return false
    }
    var info = stat()
    guard fstat(descriptor, &info) == 0 else {
      fail("could not read \(path): \(String(cString: strerror(errno)))")
      Darwin.close(descriptor)
      return false
    }
    let watch = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor, eventMask: .all, queue: queue)
    watch.setEventHandler { [weak self] in self?.changed() }
    watch.setCancelHandler { Darwin.close(descriptor) }
    watch.resume()
    file = (watch, descriptor, (device: info.st_dev, inode: info.st_ino))
    failure = nil
    offset = 0
    assembler = LineAssembler()
    return true
  }

  /// Stops watching the open file. Its source's cancel handler closes it.
  private func close() {
    file?.source.cancel()
    file = nil
  }

  /// The file's last `backlog` complete lines, read back from its end. What
  /// follows the last newline is held, as at any read.
  private func replay() -> [String] {
    guard let file else { return [] }
    var info = stat()
    guard fstat(file.descriptor, &info) == 0 else {
      fail("could not read \(path): \(String(cString: strerror(errno)))")
      return []
    }
    let start = max(0, info.st_size - Self.replayWindow)
    offset = start
    var lines = assembler.lines(readToEnd())
    // A window that starts inside the file starts inside a line.
    if start > 0, !lines.isEmpty { lines.removeFirst() }
    return Array(lines.suffix(backlog))
  }

  /// The bytes from `offset` to the file's end, `offset` moved past them.
  private func readToEnd() -> [UInt8] {
    guard let file else { return [] }
    var bytes: [UInt8] = []
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
      let count = buffer.withUnsafeMutableBytes {
        pread(file.descriptor, $0.baseAddress, $0.count, offset)
      }
      if count < 0 {
        fail("could not read \(path): \(String(cString: strerror(errno)))")
        break
      }
      guard count > 0 else { break }
      bytes.append(contentsOf: buffer[0..<count])
      offset += off_t(count)
    }
    return bytes
  }

  /// One event, on the file or its folder: what has changed is found from the
  /// file open and the one at the path, and its lines handed on as one batch.
  private func changed() {
    guard running else { return }
    var lines: [String] = []
    if let file {
      var info = stat()
      let atPath: Identity? =
        stat(path, &info) == 0 ? (device: info.st_dev, inode: info.st_ino) : nil
      if let atPath, atPath == file.identity {
        guard fstat(file.descriptor, &info) == 0 else {
          fail("could not read \(path): \(String(cString: strerror(errno)))")
          return
        }
        if info.st_size < offset {
          lines += assembler.flush().map { [$0] } ?? []
          offset = 0
        }
        lines += assembler.lines(readToEnd())
      } else {
        lines += assembler.lines(readToEnd())
        lines += assembler.flush().map { [$0] } ?? []
        close()
        if atPath != nil, open() { lines += assembler.lines(readToEnd()) }
      }
    } else if open() {
      lines += assembler.lines(readToEnd())
    }
    hand(lines)
  }

  // MARK: - The folder

  /// Watches the file's folder, which sees the file made, renamed or
  /// removed; or, while the folder is not there, the nearest folder above it
  /// that is.
  private func watchFolder() {
    folder?.cancel()
    folder = nil
    let directory = (path as NSString).deletingLastPathComponent
    if let watch = watch(directory, onEvent: { [weak self] mask in self?.folderChanged(mask) }) {
      folder = watch
      return
    }
    guard let ancestor = Self.nearestAncestor(of: directory) else {
      fail("cannot watch \(directory): no folder above it can be opened")
      return
    }
    folder = watch(ancestor) { [weak self] _ in self?.ancestorChanged() }
  }

  private func folderChanged(_ mask: DispatchSource.FileSystemEvent) {
    guard running else { return }
    // The folder itself went: wait for it above, as at a start.
    if !mask.isDisjoint(with: [.delete, .rename]) { watchFolder() }
    changed()
  }

  private func ancestorChanged() {
    guard running else { return }
    watchFolder()
    changed()
  }

  private func watch(
    _ directory: String, onEvent: @escaping @Sendable (DispatchSource.FileSystemEvent) -> Void
  ) -> DispatchSourceFileSystemObject? {
    let descriptor = Darwin.open(directory, O_EVTONLY | O_CLOEXEC)
    guard descriptor >= 0 else { return nil }
    let watch = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: queue)
    watch.setEventHandler { [weak watch] in onEvent(watch?.data ?? []) }
    watch.setCancelHandler { Darwin.close(descriptor) }
    watch.resume()
    return watch
  }

  /// The nearest folder above `directory` that is there, or nil.
  static func nearestAncestor(of directory: String) -> String? {
    var url = URL(fileURLWithPath: directory).standardizedFileURL
    while url.path != "/" {
      url.deleteLastPathComponent()
      var isFolder: ObjCBool = false
      if FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder),
        isFolder.boolValue
      {
        return url.path
      }
    }
    return nil
  }

  // MARK: - Delivery

  private func hand(_ texts: [String]) {
    guard running, !texts.isEmpty else { return }
    deliver(texts.map { ConsoleLine(text: $0, kind: classify($0), source: source) })
  }

  /// Says a failure as an error line, once while it lasts.
  private func fail(_ text: String) {
    guard running, text != failure else { return }
    failure = text
    deliver([ConsoleLine(text: text, kind: .error, source: source)])
  }
}
