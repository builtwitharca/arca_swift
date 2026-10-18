import ArcaTestSupport
import Foundation
import Testing

@testable import ArcaCore

/// Finding a config file in the app's config folder or its bundle, and
/// reading it (design.md "The file").
/// Acceptance test AT-02.6, in ST0001's acceptance.md.
@Suite("Config file")
struct ConfigFileTests {
  static let bundled = "/Applications/Example.app/Contents/Resources/masthead.yaml"

  @Test("the user's copy comes first, then the bundle's")
  func both() {
    let files = ConfigFile.candidates(
      name: "masthead.yaml", folder: "/home/ada/.config/menuz", bundled: Self.bundled,
      exists: { $0 == "/home/ada/.config/menuz/masthead.yaml" })
    #expect(
      files == [
        ConfigFile(path: "/home/ada/.config/menuz/masthead.yaml", origin: .user),
        ConfigFile(path: Self.bundled, origin: .bundled),
      ])
  }

  @Test("with no user's copy the bundle's is the only one, and with neither there is none")
  func fallbacks() {
    let folder = "/home/ada/.config/menuz"
    #expect(
      ConfigFile.candidates(name: "masthead.yaml", folder: folder, bundled: Self.bundled, exists: { _ in false })
        == [ConfigFile(path: Self.bundled, origin: .bundled)])
    #expect(
      ConfigFile.candidates(name: "masthead.yaml", folder: folder, bundled: nil, exists: { _ in true })
        == [ConfigFile(path: "\(folder)/masthead.yaml", origin: .user)])
    #expect(ConfigFile.candidates(name: "masthead.yaml", folder: folder, bundled: nil, exists: { _ in false }).isEmpty)
  }

  @Test("the file system and the bundle's resources are asked for the same file")
  func onDisk() throws {
    try Scratch.folder { scratch in
      let app = try Scratch.app(in: scratch)
      let bundled = try Scratch.write("heading: bundled\n", to: "masthead.yaml", in: app.resources)
      let bundle = try #require(Bundle(path: app.bundle))
      #expect(
        ConfigFile.candidates(name: "masthead.yaml", folder: app.folder, bundle: bundle)
          == [ConfigFile(path: bundled, origin: .bundled)])
      let user = try Scratch.write("heading: user\n", to: "masthead.yaml", in: app.folder)
      #expect(
        ConfigFile.candidates(name: "masthead.yaml", folder: app.folder, bundle: bundle)
          == [ConfigFile(path: user, origin: .user), ConfigFile(path: bundled, origin: .bundled)])
    }
  }

  @Test("a bundle that ships no copy adds none")
  func noBundled() throws {
    try Scratch.folder { scratch in
      let app = try Scratch.app(in: scratch)
      let bundle = try #require(Bundle(path: app.bundle))
      #expect(ConfigFile.candidates(name: "masthead.yaml", folder: app.folder, bundle: bundle).isEmpty)
      let user = try Scratch.write("heading: user\n", to: "masthead.yaml", in: app.folder)
      #expect(
        ConfigFile.candidates(name: "masthead.yaml", folder: app.folder, bundle: bundle)
          == [ConfigFile(path: user, origin: .user)])
    }
  }

  @Test("a broken link, or a folder the app may not search, is refused in the system's words, not passed over")
  func notPassedOver() throws {
    try Scratch.folder { scratch in
      let app = try Scratch.app(in: scratch)
      let bundled = try Scratch.write("heading: bundled\n", to: "masthead.yaml", in: app.resources)
      let bundle = try #require(Bundle(path: app.bundle))

      let linked = try Scratch.folders("\(scratch)/linked")
      let link = "\(linked)/masthead.yaml"
      try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "\(scratch)/gone.yaml")
      #expect(
        ConfigFile.candidates(name: "masthead.yaml", folder: linked, bundle: bundle)
          == [ConfigFile(path: link, origin: .user), ConfigFile(path: bundled, origin: .bundled)])
      #expect(
        ConfigFile(path: link, origin: .user).text()
          == .failure(Refusal(file: link, key: nil, value: nil, why: "cannot be read: No such file or directory")))

      let shut = try Scratch.folders("\(scratch)/shut")
      try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: shut)
      defer {
        do {
          try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shut)
        } catch {
          Issue.record("the folder \(shut) was not opened again: \(error)")
        }
      }
      let hidden = "\(shut)/masthead.yaml"
      #expect(
        ConfigFile.candidates(name: "masthead.yaml", folder: shut, bundle: bundle)
          == [ConfigFile(path: hidden, origin: .user), ConfigFile(path: bundled, origin: .bundled)])
      #expect(
        ConfigFile(path: hidden, origin: .user).text()
          == .failure(Refusal(file: hidden, key: nil, value: nil, why: "cannot be read: Permission denied")))
    }
  }

  @Test("a file is read as UTF-8 text")
  func text() throws {
    try Scratch.folder { scratch in
      let path = try Scratch.write("heading: \"Über {name}\"\n", to: "masthead.yaml", in: scratch)
      #expect(ConfigFile(path: path, origin: .user).text() == .success("heading: \"Über {name}\"\n"))
    }
  }

  @Test("a file that cannot be read is refused in the system's words, and so is one that is not UTF-8")
  func unreadable() throws {
    try Scratch.folder { scratch in
      let absent = "\(scratch)/absent.yaml"
      #expect(
        ConfigFile(path: absent, origin: .user).text()
          == .failure(Refusal(file: absent, key: nil, value: nil, why: "cannot be read: No such file or directory")))
      let latin1 = "\(scratch)/latin1.yaml"
      try Data([0x68, 0x3A, 0x20, 0xFC, 0x0A]).write(to: URL(fileURLWithPath: latin1))
      #expect(
        ConfigFile(path: latin1, origin: .user).text()
          == .failure(Refusal(file: latin1, key: nil, value: nil, why: "not UTF-8 text")))
    }
  }

  @Test("a file's entries are its text read as YAML, and a refusal names the file")
  func entries() throws {
    try Scratch.folder { scratch in
      let path = try Scratch.write("heading: menuz\n", to: "masthead.yaml", in: scratch)
      #expect(
        ConfigFile(path: path, origin: .user).entries()
          == .success([ConfigEntry(key: "heading", value: .text("menuz"))]))
      let list = try Scratch.write("- menuz\n", to: "list.yaml", in: scratch)
      #expect(
        ConfigFile(path: list, origin: .user).entries()
          == .failure(Refusal(file: list, key: nil, value: nil, why: "the file is not a mapping of keys")))
    }
  }

  static let user = ConfigFile(path: "/home/ada/.config/menuz/masthead.yaml", origin: .user)
  static let shipped = ConfigFile(path: bundled, origin: .bundled)

  static func latin1(_ file: ConfigFile) -> Refusal {
    Refusal(file: file.path, key: nil, value: nil, why: "not UTF-8 text")
  }

  @Test("the first file read without a refusal is taken, after the refusals of those before it")
  func first() {
    let found = ConfigFile.first(of: [Self.user, Self.shipped]) { file -> Result<String, Refusal> in
      file.origin == .user ? .failure(Self.latin1(file)) : .success(file.path)
    }
    #expect(found.value == Self.bundled)
    #expect(found.refusals == [Self.latin1(Self.user)])
  }

  @Test("a file after the one taken is not read")
  func firstStops() {
    var read: [String] = []
    let found = ConfigFile.first(of: [Self.user, Self.shipped]) { file -> Result<String, Refusal> in
      read.append(file.path)
      return .success(file.path)
    }
    #expect(found.value == Self.user.path)
    #expect(found.refusals.isEmpty)
    #expect(read == [Self.user.path])
  }

  @Test("with every file refused, nothing is taken and each refusal is kept in order; with no file, neither")
  func noneTaken() {
    let refused = ConfigFile.first(of: [Self.user, Self.shipped]) { file -> Result<String, Refusal> in
      .failure(Self.latin1(file))
    }
    #expect(refused.value == nil)
    #expect(refused.refusals == [Self.latin1(Self.user), Self.latin1(Self.shipped)])
    let none = ConfigFile.first(of: []) { file -> Result<String, Refusal> in .success(file.path) }
    #expect(none.value == nil)
    #expect(none.refusals.isEmpty)
  }

  @Test("a name's copies are tried the user's first, and with neither the refusal names where the user's would be")
  func firstNamed() throws {
    try Scratch.folder { scratch in
      let app = try Scratch.app(in: scratch)
      _ = try Scratch.write("user\n", to: "about.md", in: app.folder)
      _ = try Scratch.write("bundled\n", to: "about.md", in: app.resources)
      let notes = "\(app.folder)/notes.md"
      try Data([0x68, 0xFC, 0x0A]).write(to: URL(fileURLWithPath: notes))
      _ = try Scratch.write("bundled notes\n", to: "notes.md", in: app.resources)
      let bundle = try #require(Bundle(path: app.bundle))

      let about = ConfigFile.first(named: "about.md", folder: app.folder, bundle: bundle) { $0.text() }
      #expect(about.value == "user\n")
      #expect(about.refusals.isEmpty)
      let refused = ConfigFile.first(named: "notes.md", folder: app.folder, bundle: bundle) { $0.text() }
      #expect(refused.value == "bundled notes\n")
      #expect(refused.refusals == [Refusal(file: notes, key: nil, value: nil, why: "not UTF-8 text")])
      let css = ConfigFile.first(named: "about.css", folder: app.folder, bundle: bundle) { $0.text() }
      #expect(css.value == nil)
      #expect(
        css.refusals == [
          Refusal(
            file: "\(app.folder)/about.css", key: nil, value: nil, why: "is not there, and the app's bundle has none")
        ])
    }
  }

  @Test("a refused user's copy with none in the bundle is the one refusal")
  func refusedAlone() throws {
    try Scratch.folder { scratch in
      let app = try Scratch.app(in: scratch)
      let guide = "\(app.folder)/guide.md"
      try Data([0x68, 0xFC, 0x0A]).write(to: URL(fileURLWithPath: guide))
      let bundle = try #require(Bundle(path: app.bundle))
      let found = ConfigFile.first(named: "guide.md", folder: app.folder, bundle: bundle) { $0.text() }
      #expect(found.refusals == [Refusal(file: guide, key: nil, value: nil, why: "not UTF-8 text")])
    }
  }
}
