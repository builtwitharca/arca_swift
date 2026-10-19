import ArcaTestSupport
import Foundation
import Testing

@testable import ArcaLogConsole

/// A file the app names, followed in-process (design.md "ArcaLogConsole"),
/// against temporary files: an append; a truncation, and a short append after
/// one; a rename with the new file a moment later; a log missing at open and
/// created later; a character split across two reads; and a last line with no
/// newline.
/// Acceptance test AT-09.4, in ST0001's acceptance.md.
@Suite("Following a file")
struct FileFollowerTests {
  static let source = ConsoleSource("site.log")

  static func write(_ bytes: [UInt8], to path: String, appending: Bool = true) throws {
    if appending, let handle = FileHandle(forWritingAtPath: path) {
      defer { try? handle.close() }
      try handle.seekToEnd()
      try handle.write(contentsOf: Data(bytes))
    } else {
      try Data(bytes).write(to: URL(fileURLWithPath: path))
    }
  }

  static func write(_ text: String, to path: String, appending: Bool = true) throws {
    try write(Array(text.utf8), to: path, appending: appending)
  }

  static func follow(_ path: String, backlog: Int = 40, into delivered: Delivered) -> FileFollower {
    let follower = FileFollower(path: path, source: source, backlog: backlog) { delivered.add($0) }
    follower.start()
    return follower
  }

  @Test("opening replays the log's last lines, and an append arrives")
  func append() async throws {
    try await Scratch.folder { folder in
      let path = folder + "/site.log"
      try Self.write((1...50).map { "line \($0)\n" }.joined(), to: path, appending: false)
      let delivered = Delivered()
      let follower = Self.follow(path, into: delivered)
      defer { follower.stop() }
      #expect(await delivered.texts(atLeast: 40) == (11...50).map { "line \($0)" })
      try Self.write("line 51\n", to: path)
      #expect(await delivered.texts(atLeast: 41).last == "line 51")
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
      _ = await delivered.texts(atLeast: 2)
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
      #expect(await delivered.texts(atLeast: 2) == ["a", "b"])
      try Self.write("", to: path, appending: false)
      _ = await delivered.texts(after: .milliseconds(200))
      try Self.write("c\n", to: path)
      #expect(await delivered.texts(atLeast: 3) == ["a", "b", "c"])
    }
  }

  @Test("a truncation with a short append after it, seen as one change, is read from the start")
  func truncationThenShortAppend() async throws {
    try await Scratch.folder { folder in
      let path = folder + "/site.log"
      try Self.write("the first line\nthe second line\n", to: path, appending: false)
      let delivered = Delivered()
      let follower = Self.follow(path, into: delivered)
      defer { follower.stop() }
      _ = await delivered.texts(atLeast: 2)
      try Self.write("x\n", to: path, appending: false)
      #expect(await delivered.texts(atLeast: 3) == ["the first line", "the second line", "x"])
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
      #expect(await delivered.texts(atLeast: 1) == ["a"])
      try Self.write("b\nlast, no newline", to: path)
      try FileManager.default.moveItem(atPath: path, toPath: path + ".1")
      _ = await delivered.texts(after: .milliseconds(100))
      try Self.write("c\n", to: path, appending: false)
      #expect(await delivered.texts(atLeast: 4) == ["a", "b", "last, no newline", "c"])
      try Self.write("not followed\n", to: path + ".1")
      #expect(await delivered.texts(after: .milliseconds(200)).count == 4)
    }
  }

  @Test("a log missing at open is picked up when it is created")
  func missingAtOpen() async throws {
    try await Scratch.folder { folder in
      let path = folder + "/site.log"
      let delivered = Delivered()
      let follower = Self.follow(path, into: delivered)
      defer { follower.stop() }
      #expect(await delivered.texts(after: .milliseconds(200)).isEmpty)
      try Self.write("a\nb\n", to: path, appending: false)
      #expect(await delivered.texts(atLeast: 2) == ["a", "b"])
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
      #expect(await delivered.texts(after: .milliseconds(200)).isEmpty)
      try Self.write([accented[1], 0x0A], to: path)
      #expect(await delivered.texts(atLeast: 1) == ["xé"])
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
      #expect(await delivered.texts(after: .milliseconds(200)) == ["a"])
      try Self.write("al\n", to: path)
      #expect(await delivered.texts(atLeast: 2) == ["a", "partial"])
    }
  }

  @Test("a stopped follower delivers nothing more")
  func stopped() async throws {
    try await Scratch.folder { folder in
      let path = folder + "/site.log"
      try Self.write("a\n", to: path, appending: false)
      let delivered = Delivered()
      let follower = Self.follow(path, into: delivered)
      #expect(await delivered.texts(atLeast: 1) == ["a"])
      follower.stop()
      try Self.write("b\n", to: path)
      #expect(await delivered.texts(after: .milliseconds(200)) == ["a"])
    }
  }
}
