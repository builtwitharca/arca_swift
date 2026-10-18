import ArcaCore
import Testing

@testable import ArcaMasthead

/// The heading and the subheading as text (design.md "The file"): their
/// templates with the values in, each line on its own, and a token that
/// names no value refused.
/// Acceptance test AT-02.3, in ST0001's acceptance.md.
@Suite("Masthead lines")
struct MastheadLinesTests {
  /// The lines a file with `heading` and `subheading` makes, the app naming
  /// `owned` and having `provided`.
  static func masthead(
    _ heading: String, _ subheading: String?, info: [String: Any] = Menuz.info, owned: Set<String> = [],
    provided: [String: String] = [:]
  ) -> Masthead {
    let file = MastheadFile(
      heading: Template(heading), subheading: subheading.map { Template($0) }, icon: .app, about: Menuz.about)
    return file.masthead(MastheadValues(bundle: info, owned: owned) { provided[$0] })
  }

  @Test("the heading and the subheading take their values")
  func values() {
    #expect(
      Self.masthead("{name} {version}", "{commit} · {kind}")
        == Masthead(heading: "menuz 0.3.0", subheading: "56e0c90 · dev", icon: .app, about: Menuz.about, refusals: []))
  }

  @Test("a value missing from the heading leaves it as the app's name alone")
  func headingFallsBack() {
    #expect(Self.masthead("{name} {version}", nil, owned: ["version"]).heading == "menuz")
    #expect(Self.masthead("gtools {version} ({status})", nil, owned: ["status"]).heading == "menuz")
  }

  @Test("each line stands on its own: a value missing from one leaves the other as it is")
  func eachLine() {
    #expect(
      Self.masthead("{name} {version}", "{commit} · {kind}", owned: ["version"])
        == Masthead(heading: "menuz", subheading: "56e0c90 · dev", icon: .app, about: Menuz.about, refusals: []))
    #expect(
      Self.masthead("{name} {version}", "{commit} · {kind}", owned: ["commit"])
        == Masthead(heading: "menuz 0.3.0", subheading: nil, icon: .app, about: Menuz.about, refusals: []))
  }

  @Test("a heading that comes out blank is the app's name alone too")
  func blankHeading() {
    #expect(Self.masthead("{status}", nil, owned: ["status"], provided: ["status": ""]).heading == "menuz")
    #expect(Self.masthead("{status}", nil, owned: ["status"], provided: ["status": " \t"]).heading == "menuz")
  }

  @Test("with no name, the app's name alone is nothing, never the heading as written")
  func noName() {
    #expect(Self.masthead("{name} {version}", nil, info: ["CFBundleShortVersionString": "0.3.0"]).heading == "")
    #expect(Self.masthead("{name} {version}", nil, owned: ["name"]).heading == "")
  }

  @Test("a subheading with a value missing is hidden, as is one that comes out blank")
  func subheadingHidden() {
    #expect(Self.masthead("{name}", "{kind}").subheading == "dev")
    #expect(Self.masthead("{name}", "{commit} · {kind}", owned: ["commit"]).subheading == nil)
    #expect(Self.masthead("{name}", "").subheading == nil)
    #expect(Self.masthead("{name}", " ").subheading == nil)
    #expect(Self.masthead("{name}", "{status}", owned: ["status"], provided: ["status": ""]).subheading == nil)
    #expect(Self.masthead("{name}", nil).subheading == nil)
  }

  @Test("a value goes in as it is, braces and markup included, and is not read for tokens")
  func asGiven() {
    let masthead = Self.masthead("{name} {status}", nil, owned: ["status"], provided: ["status": "{version} <b>"])
    #expect(masthead.heading == "menuz {version} <b>")
  }

  @Test("a token that names no value the app gives is refused, naming it and the values there are")
  func unknownToken() {
    let those = "which is not a value the app gives: those are {commit}, {kind}, {name} and {version}"
    #expect(
      MastheadFileTests.check("heading: \"{name} {verison}\"\nabout:\n  body: about.md\n")
        == MastheadFileTests.refused("heading", "{name} {verison}", "has {verison}, \(those)"))
    #expect(
      MastheadFileTests.check("heading: \"{name}\"\nsubheading: \"{user}\"\nabout:\n  body: about.md\n")
        == MastheadFileTests.refused("subheading", "{user}", "has {user}, \(those)"))
  }

  @Test("a value the app names is one a token may take, though it has none yet")
  func appNames() {
    let names = MastheadValues(bundle: Menuz.info, owned: ["user"]).names
    #expect(
      MastheadFileTests.check("heading: \"{name}\"\nsubheading: \"{user}\"\nabout:\n  body: about.md\n", names: names)
        .map(\.subheading) == .success(Template("{user}")))
  }
}
