import ArcaTestSupport
import Foundation
import Testing

@testable import ArcaLogConsole

/// A file the app names, followed in-process (design.md "ArcaLogConsole"),
/// against temporary files: an append; a truncation, with the fragment held
/// given up, a short append after one, and one while a pass skips ahead; a
/// rename, with the new file a moment later or already there; a log missing
/// at open, and its folders missing too; a character split across two reads;
/// a last line with no newline; a replay and a read pass bounded by the read
/// window; a failure said once; the change each event decides; and a console
/// following a file again.
/// Acceptance test AT-09.4, in ST0001's acceptance.md.
@Suite("Following a file")
struct FileFollowerTests {
  static let source = ConsoleSource("site.log")

  static func write(_ bytes: [UInt8], to path: String, appending: Bool = true) throws {
    if appending, let handle = FileHandle(forWritingAtPath: path) {
      try handle.seekToEnd()
      try handle.write(contentsOf: Data(bytes))
      try handle.close()
    } else {
      try Data(bytes).write(to: URL(fileURLWithPath: path))
    }
  }

  static func write(_ text: String, to path: String, appending: Bool = true) throws {
    try write(Array(text.utf8), to: path, appending: appending)
  }

  static func follow(
    _ path: String, backlog: Int = 40, window: off_t = FileFollower.readWindow, into delivered: Delivered
  ) -> FileFollower {
    let follower = FileFollower(path: path, source: source, backlog: backlog, window: window) { delivered.add($0) }
    follower.start()
    return follower
  }

  /// Four lines of seven bytes each: `line 1` to `line 4`.
  static let fourLines = (1...4).map { "line \($0)\n" }.joined()

  @Test("opening replays the log's last lines, and an append arrives, once")
  func append() async throws {
    try await Scratch.folder { folder in
      let path = folder + "/site.log"
      try Self.write((1...50).map { "line \($0)\n" }.joined(), to: path, appending: false)
      let delivered = Delivered()
      let follower = Self.follow(path, into: delivered)
      defer { follower.stop() }
      #expect(try await delivered.texts(atLeast: 40) == (11...50).map { "line \($0)" })
      try Self.write("line 51\n", to: path)
      _ = try await delivered.texts(atLeast: 41)
      #expect(try await delivered.texts(after: .milliseconds(200)) == (11...51).map { "line \($0)" })
    }
  }

  @Test("each line carries the source's id and the kind the classifier gives it")
  func classified() async throws {
    try await Scratch.folder { folder in
      let path = folder + "/site.log"
      try Self.write("2026-10-19T09:04:28Z error: x\nstarted\n", to: path, appending: false)
      let delivered = Delivered()
      let follower = Self.follow(path, into: delivered)
      defer { follower.stop() }
      _ = try await delivered.texts(atLeast: 2)
      #expect(delivered.lines.map(\.kind) == [.error, .log])
      #expect(delivered.lines.allSatisfy { $0.source == Self.source })
    }
  }

  @Test("a truncated file is read again from the start")
  func truncation() async throws {
    try await Scratch.folder { folder in
      let path = folder + "/site.log"
      try Self.write("a\nb\n", to: path, appending: false)
      let delivered = Delivered()
      let follower = Self.follow(path, into: delivered)
      defer { follower.stop() }
      #expect(try await delivered.texts(atLeast: 2) == ["a", "b"])
      try Self.write("", to: path, appending: false)
      _ = try await delivered.texts(after: .milliseconds(200))
      try Self.write("c\n", to: path)
      #expect(try await delivered.texts(atLeast: 3) == ["a", "b", "c"])
    }
  }

  @Test("a truncated file gives up the fragment it held as a line before it is read again")
  func truncatedFragment() async throws {
    try await Scratch.folder { folder in
      let path = folder + "/site.log"
      try Self.write("a\npart", to: path, appending: false)
      let delivered = Delivered()
      let follower = Self.follow(path, into: delivered)
      defer { follower.stop() }
      #expect(try await delivered.texts(atLeast: 1) == ["a"])
      try Self.write("b\n", to: path, appending: false)
      #expect(try await delivered.texts(atLeast: 3) == ["a", "part", "b"])
    }
  }

  @Test("a truncation with a short append after it is read from the start")
  func truncationThenShortAppend() async throws {
    try await Scratch.folder { folder in
      let path = folder + "/site.log"
      try Self.write("the first line\nthe second line\n", to: path, appending: false)
      let delivered = Delivered()
      let follower = Self.follow(path, into: delivered)
      defer { follower.stop() }
      _ = try await delivered.texts(atLeast: 2)
      try Self.write("x\n", to: path, appending: false)
      #expect(try await delivered.texts(atLeast: 3) == ["the first line", "the second line", "x"])
    }
  }

  @Test("a truncation while a pass skips ahead reads the file again from its start")
  func truncationWhileSkipping() async throws {
    try await Scratch.folder { folder in
      let path = folder + "/site.log"
      // Forty bytes with no newline: the pass skips to a 16-byte window and
      // finds no line starting in it.
      try Self.write(String(repeating: "x", count: 40), to: path, appending: false)
      let delivered = Delivered()
      let follower = Self.follow(path, window: 16, into: delivered)
      defer { follower.stop() }
      #expect(try await delivered.texts(after: .milliseconds(200)).isEmpty)
      try Self.write("a\n", to: path, appending: false)
      #expect(try await delivered.texts(atLeast: 1) == ["a"])
      #expect(try await delivered.texts(after: .milliseconds(200)) == ["a"], "no skip is said for the new content")
    }
  }

  @Test("a renamed log is drained to its end, then the new file at the path is followed")
  func rename() async throws {
    try await Scratch.folder { folder in
      let path = folder + "/site.log"
      try Self.write("a\n", to: path, appending: false)
      let delivered = Delivered()
      let follower = Self.follow(path, into: delivered)
      defer { follower.stop() }
      #expect(try await delivered.texts(atLeast: 1) == ["a"])
      try Self.write("b\nlast, no newline", to: path)
      try FileManager.default.moveItem(atPath: path, toPath: path + ".1")
      _ = try await delivered.texts(after: .milliseconds(100))
      try Self.write("c\n", to: path, appending: false)
      #expect(try await delivered.texts(atLeast: 4) == ["a", "b", "last, no newline", "c"])
      try Self.write("not followed\n", to: path + ".1")
      #expect(try await delivered.texts(after: .milliseconds(200)).count == 4)
    }
  }

  @Test("a rename whose new file is there by the event is drained, then the new file is followed")
  func renameOntoNewFile() async throws {
    try await Scratch.folder { folder in
      let path = folder + "/site.log"
      try Self.write("a\n", to: path, appending: false)
      let delivered = Delivered()
      let follower = Self.follow(path, into: delivered)
      defer { follower.stop() }
      #expect(try await delivered.texts(atLeast: 1) == ["a"])
      try Self.write("b\n", to: path)
      try FileManager.default.moveItem(atPath: path, toPath: path + ".1")
      try Self.write("c\n", to: path, appending: false)
      #expect(try await delivered.texts(atLeast: 3) == ["a", "b", "c"])
      try Self.write("not followed\n", to: path + ".1")
      #expect(try await delivered.texts(after: .milliseconds(200)) == ["a", "b", "c"])
    }
  }

  @Test("a log missing at open is picked up when it is created")
  func missingAtOpen() async throws {
    try await Scratch.folder { folder in
      let path = folder + "/site.log"
      let delivered = Delivered()
      let follower = Self.follow(path, into: delivered)
      defer { follower.stop() }
      #expect(try await delivered.texts(after: .milliseconds(200)).isEmpty)
      try Self.write("a\nb\n", to: path, appending: false)
      #expect(try await delivered.texts(atLeast: 2) == ["a", "b"])
    }
  }

  @Test("a log whose folders are missing at open is picked up when they and it are made")
  func foldersMissingAtOpen() async throws {
    try await Scratch.folder { folder in
      let path = folder + "/logs/site/site.log"
      let delivered = Delivered()
      let follower = Self.follow(path, into: delivered)
      defer { follower.stop() }
      #expect(try await delivered.texts(after: .milliseconds(200)).isEmpty)
      _ = try Scratch.folders(folder + "/logs/site")
      try Self.write("a\n", to: path, appending: false)
      #expect(try await delivered.texts(atLeast: 1) == ["a"])
    }
  }

  @Test("a character split across two writes stays one character")
  func splitCharacter() async throws {
    try await Scratch.folder { folder in
      let path = folder + "/site.log"
      try Self.write("", to: path, appending: false)
      let delivered = Delivered()
      let follower = Self.follow(path, into: delivered)
      defer { follower.stop() }
      let accented = Array("é".utf8)
      try Self.write([UInt8(ascii: "x"), accented[0]], to: path)
      #expect(try await delivered.texts(after: .milliseconds(200)).isEmpty)
      try Self.write([accented[1], 0x0A], to: path)
      #expect(try await delivered.texts(atLeast: 1) == ["xé"])
    }
  }

  @Test("a last line with no newline is held until its newline arrives")
  func lastLineWithNoNewline() async throws {
    try await Scratch.folder { folder in
      let path = folder + "/site.log"
      try Self.write("a\nparti", to: path, appending: false)
      let delivered = Delivered()
      let follower = Self.follow(path, into: delivered)
      defer { follower.stop() }
      #expect(try await delivered.texts(atLeast: 1) == ["a"])
      #expect(try await delivered.texts(after: .milliseconds(200)) == ["a"], "the fragment is held")
      try Self.write("al\n", to: path)
      #expect(try await delivered.texts(atLeast: 2) == ["a", "partial"])
    }
  }

  @Test("a replay that starts inside the file starts at the first whole line in its window")
  func replayInside() async throws {
    try await Scratch.folder { folder in
      let path = folder + "/site.log"
      try Self.write(Self.fourLines, to: path, appending: false)
      // A window of 16 bytes starts inside line 2, and one of 14 at line 3.
      for window: off_t in [16, 14] {
        let delivered = Delivered()
        let follower = Self.follow(path, window: window, into: delivered)
        #expect(try await delivered.texts(atLeast: 2) == ["line 3", "line 4"], "window \(window)")
        #expect(try await delivered.texts(after: .milliseconds(100)).count == 2, "window \(window)")
        follower.stop()
      }
    }
  }

  @Test("a pass with more than its window ahead reads the window alone, and says how much it passed over")
  func skipAhead() async throws {
    try await Scratch.folder { folder in
      let path = folder + "/site.log"
      try Self.write("", to: path, appending: false)
      let delivered = Delivered()
      let follower = Self.follow(path, window: 16, into: delivered)
      defer { follower.stop() }
      #expect(try await delivered.texts(after: .milliseconds(200)).isEmpty)
      try Self.write(Self.fourLines, to: path)
      #expect(try await delivered.texts(atLeast: 3) == ["» skipped 14 bytes of \(path)", "line 3", "line 4"])
      #expect(delivered.lines.first?.kind == .marker)
    }
  }

  @Test("a folder that is there but cannot be read is said as error lines, each failure once")
  func unreadable() async throws {
    try await Scratch.folder { folder in
      let locked = try Scratch.folders(folder + "/locked")
      try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked)
      let delivered = Delivered()
      let follower = Self.follow(locked + "/site.log", into: delivered)
      _ = try await delivered.texts(atLeast: 1)
      let texts = try await delivered.texts(after: .milliseconds(200))
      follower.stop()
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked)
      // At mode 0 the folder can be opened neither for its events nor on the
      // way to its file: both fail with EACCES (measured on macOS 27).
      let expected = [
        "could not watch \(locked): Permission denied", "could not open \(locked)/site.log: Permission denied",
      ]
      #expect(texts == expected, "each failure is said once")
      #expect(delivered.lines.allSatisfy { $0.kind == .error })
    }
  }

  @Test("a stopped follower delivers nothing more")
  func stopped() async throws {
    try await Scratch.folder { folder in
      let path = folder + "/site.log"
      try Self.write("a\n", to: path, appending: false)
      let delivered = Delivered()
      let follower = Self.follow(path, into: delivered)
      #expect(try await delivered.texts(atLeast: 1) == ["a"])
      follower.stop()
      try Self.write("b\n", to: path)
      #expect(try await delivered.texts(after: .milliseconds(200)) == ["a"])
    }
  }

  @Test("an event's change is decided from the file open, the file at the path, its size and the offset")
  func decide() {
    let open = FileIdentity(device: 1, inode: 2)
    let other = FileIdentity(device: 1, inode: 3)
    #expect(FileChange.decide(open: open, atPath: open, size: 10, read: 10) == .appended)
    #expect(FileChange.decide(open: open, atPath: open, size: 12, read: 10) == .appended)
    #expect(FileChange.decide(open: open, atPath: open, size: 4, read: 10) == .truncated)
    #expect(FileChange.decide(open: open, atPath: other, size: 4, read: 10) == .replaced)
    #expect(FileChange.decide(open: open, atPath: nil, size: 10, read: 10) == .removed)
  }

  @MainActor
  @Test("a console following a file shows its lines, and following it again shows its backlog once")
  func consoleFollowsAgain() async throws {
    try await Scratch.folder { folder in
      let path = folder + "/site.log"
      try Self.write("a\nb\n", to: path, appending: false)
      let console = LogConsole(title: "Console")
      console.follow(file: path, as: Self.source)
      try await until { console.lines.count >= 2 }
      console.follow(file: path, as: Self.source)
      try await until { console.lines.count >= 2 }
      try await Task.sleep(for: .milliseconds(200))
      #expect(console.lines.map(\.text) == ["a", "b"])
      console.stopFollowing(Self.source)
      try Self.write("c\n", to: path)
      try await Task.sleep(for: .milliseconds(200))
      #expect(console.lines.map(\.text) == ["a", "b"], "a source no longer followed adds nothing")
    }
  }
}
