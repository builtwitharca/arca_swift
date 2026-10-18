import Foundation
import Testing

@testable import ArcaCore

/// Finding a config file in the app's config folder or its bundle, and
/// reading it (design.md "The file").
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
      let folder = try Scratch.folders("\(scratch)/config/menuz")
      let resources = try Scratch.folders("\(scratch)/Example.bundle/Contents/Resources")
      let bundled = try Scratch.write("heading: bundled\n", to: "masthead.yaml", in: resources)
      let bundle = try #require(Bundle(path: "\(scratch)/Example.bundle"))
      #expect(
        ConfigFile.candidates(name: "masthead.yaml", folder: folder, bundle: bundle)
          == [ConfigFile(path: bundled, origin: .bundled)])
      let user = try Scratch.write("heading: user\n", to: "masthead.yaml", in: folder)
      #expect(
        ConfigFile.candidates(name: "masthead.yaml", folder: folder, bundle: bundle)
          == [ConfigFile(path: user, origin: .user), ConfigFile(path: bundled, origin: .bundled)])
    }
  }

  @Test("a bundle that ships no copy adds none")
  func noBundled() throws {
    try Scratch.folder { scratch in
      let folder = try Scratch.folders("\(scratch)/config/menuz")
      _ = try Scratch.folders("\(scratch)/Bare.bundle/Contents/Resources")
      let bundle = try #require(Bundle(path: "\(scratch)/Bare.bundle"))
      #expect(ConfigFile.candidates(name: "masthead.yaml", folder: folder, bundle: bundle).isEmpty)
      let user = try Scratch.write("heading: user\n", to: "masthead.yaml", in: folder)
      #expect(
        ConfigFile.candidates(name: "masthead.yaml", folder: folder, bundle: bundle)
          == [ConfigFile(path: user, origin: .user)])
    }
  }

  @Test("a broken link, or a folder the app may not search, is refused in the system's words, not passed over")
  func notPassedOver() throws {
    try Scratch.folder { scratch in
      let resources = try Scratch.folders("\(scratch)/Example.bundle/Contents/Resources")
      let bundled = try Scratch.write("heading: bundled\n", to: "masthead.yaml", in: resources)
      let bundle = try #require(Bundle(path: "\(scratch)/Example.bundle"))

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
}
