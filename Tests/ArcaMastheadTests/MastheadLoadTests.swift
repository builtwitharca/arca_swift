import ArcaCore
import ArcaTestSupport
import Foundation
import Testing

@testable import ArcaMasthead

/// The user's masthead.yaml or the bundled default (design.md "The file"): a
/// refused copy leaves the next in use, and the subheading says what was
/// wrong.
/// Acceptance test AT-02.4, in ST0001's acceptance.md.
@Suite("Masthead load")
struct MastheadLoadTests {
  static let bundled = "heading: \"{name} {version}\"\nsubheading: \"{commit} · {kind}\"\nabout:\n  body: about.md\n"
  static let refusedIcon = "heading: menuz\nicon: logo\nabout:\n  body: about.md\n"

  /// The file the bundled default makes, and the refusal of a copy before it.
  static let file = MastheadFile(
    heading: Template("{name} {version}"), subheading: Template("{commit} · {kind}"), icon: .omitted,
    about: Menuz.about)
  static let refusal = Refusal(
    file: "/home/ada/.config/menuz/masthead.yaml", key: "icon", value: "logo", why: "is not app or none")

  /// A config folder and a bundle in `scratch`, the bundle shipping
  /// `bundled` as its masthead.yaml when there is one.
  static func place(_ scratch: String, bundled: String?) throws -> (folder: String, bundle: Bundle) {
    let app = try Scratch.app(in: scratch)
    if let bundled { _ = try Scratch.write(bundled, to: "masthead.yaml", in: app.resources) }
    return (app.folder, try #require(Bundle(path: app.bundle)))
  }

  @Test("the copy used gives its lines, and with a refusal before it, the subheading says what was wrong")
  func usedCopy() {
    #expect(
      Masthead(found: (value: Self.file, refusals: []), values: Menuz.values)
        == Masthead(
          heading: "menuz 0.3.0", subheading: "56e0c90 · dev", icon: .omitted, about: Menuz.about, refusals: []))
    #expect(
      Masthead(found: (value: Self.file, refusals: [Self.refusal]), values: Menuz.values)
        == Masthead(
          heading: "menuz 0.3.0", subheading: Self.refusal.description, icon: .omitted, about: Menuz.about,
          refusals: [Self.refusal]))
  }

  @Test("with no copy used, the heading is the app's name alone, or nothing, over the first refusal")
  func noCopyUsed() {
    let bundled = Refusal(
      file: "/Applications/Example.app/Contents/Resources/masthead.yaml", key: "about", value: nil, why: "is required")
    let both = [Self.refusal, bundled]
    #expect(
      Masthead(found: (value: nil, refusals: both), values: Menuz.values)
        == Masthead(heading: "menuz", subheading: Self.refusal.description, icon: .app, about: nil, refusals: both))
    #expect(Masthead(found: (value: nil, refusals: both), values: MastheadValues(bundle: [:])).heading == "")
  }

  @Test("with no user's copy, the bundled default is used")
  func bundledDefault() throws {
    try Scratch.folder { scratch in
      let (folder, bundle) = try Self.place(scratch, bundled: Self.bundled)
      let masthead = Masthead(
        heading: "menuz 0.3.0", subheading: "56e0c90 · dev", icon: .app, about: Menuz.about, refusals: [])
      #expect(Masthead.load(folder: folder, bundle: bundle, values: Menuz.values) == masthead)
    }
  }

  @Test("the user's copy is used when it is read and checked without a refusal")
  func usersCopy() throws {
    try Scratch.folder { scratch in
      let (folder, bundle) = try Self.place(scratch, bundled: Self.bundled)
      let yaml = "heading: \"{name}\"\nicon: none\nabout:\n  body: mine.html\n"
      _ = try Scratch.write(yaml, to: "masthead.yaml", in: folder)
      let mine = MastheadFile.About(body: "mine.html", kind: .html, css: nil)
      #expect(
        Masthead.load(folder: folder, bundle: bundle, values: Menuz.values)
          == Masthead(heading: "menuz", subheading: nil, icon: .omitted, about: mine, refusals: []))
    }
  }

  @Test("a user's copy that is refused leaves the bundled default in use, and the subheading says what was wrong")
  func refusedCopy() throws {
    try Scratch.folder { scratch in
      let (folder, bundle) = try Self.place(scratch, bundled: Self.bundled)
      let user = try Scratch.write(Self.refusedIcon, to: "masthead.yaml", in: folder)
      let refusal = Refusal(file: user, key: "icon", value: "logo", why: "is not app or none")
      let masthead = Masthead(
        heading: "menuz 0.3.0", subheading: refusal.description, icon: .app, about: Menuz.about, refusals: [refusal])
      #expect(Masthead.load(folder: folder, bundle: bundle, values: Menuz.values) == masthead)
    }
  }

  @Test("a user's copy that is not UTF-8, or not YAML, is refused the same way")
  func unreadableCopy() throws {
    try Scratch.folder { scratch in
      let (folder, bundle) = try Self.place(scratch, bundled: Self.bundled)
      let user = "\(folder)/masthead.yaml"
      func refused(_ why: String) -> Masthead {
        let refusal = Refusal(file: user, key: nil, value: nil, why: why)
        return Masthead(
          heading: "menuz 0.3.0", subheading: refusal.description, icon: .app, about: Menuz.about, refusals: [refusal])
      }
      try Data([0x68, 0x3A, 0x20, 0xFC, 0x0A]).write(to: URL(fileURLWithPath: user))
      #expect(Masthead.load(folder: folder, bundle: bundle, values: Menuz.values) == refused("not UTF-8 text"))
      _ = try Scratch.write("heading: [menuz\n", to: "masthead.yaml", in: folder)
      let flow =
        "not YAML: line 2, column 1: did not find expected ',' or ']', "
        + "while parsing a flow sequence in line 1, column 10"
      #expect(Masthead.load(folder: folder, bundle: bundle, values: Menuz.values) == refused(flow))
    }
  }

  @Test("the tokens a copy may name are the bundle's and the app's")
  func appNames() throws {
    try Scratch.folder { scratch in
      let (folder, bundle) = try Self.place(scratch, bundled: Self.bundled)
      let user = try Scratch.write(
        "heading: \"{name} {status}\"\nabout:\n  body: about.md\n", to: "masthead.yaml", in: folder)
      let why = "has {status}, which is not a value the app gives: those are {commit}, {kind}, {name} and {version}"
      #expect(
        Masthead.load(folder: folder, bundle: bundle, values: Menuz.values).refusals
          == [Refusal(file: user, key: "heading", value: "{name} {status}", why: why)])
      let serving = MastheadValues(bundle: Menuz.info, owned: ["status"]) { _ in "serving" }
      #expect(Masthead.load(folder: folder, bundle: bundle, values: serving).heading == "menuz serving")
    }
  }

  @Test("with no copy to use, the heading is the app's name, the subheading the first refusal, and both are kept")
  func noneUsable() throws {
    try Scratch.folder { scratch in
      let (folder, bundle) = try Self.place(scratch, bundled: "heading: menuz\n")
      let user = try Scratch.write(Self.refusedIcon, to: "masthead.yaml", in: folder)
      let bundled = try #require(bundle.path(forResource: "masthead.yaml", ofType: nil))
      let refusals = [
        Refusal(file: user, key: "icon", value: "logo", why: "is not app or none"),
        Refusal(file: bundled, key: "about", value: nil, why: "is required"),
      ]
      let masthead = Masthead(
        heading: "menuz", subheading: refusals[0].description, icon: .app, about: nil, refusals: refusals)
      #expect(Masthead.load(folder: folder, bundle: bundle, values: Menuz.values) == masthead)
    }
  }

  @Test("with a copy in neither the config folder nor the bundle, the refusal says where the user's would be")
  func noCopy() throws {
    try Scratch.folder { scratch in
      let (folder, bundle) = try Self.place(scratch, bundled: nil)
      let refusal = Refusal(
        file: "\(folder)/masthead.yaml", key: nil, value: nil, why: "is not there, and the app's bundle has none")
      #expect(
        Masthead.load(folder: folder, bundle: bundle, values: Menuz.values)
          == Masthead(heading: "menuz", subheading: refusal.description, icon: .app, about: nil, refusals: [refusal]))
    }
  }
}
