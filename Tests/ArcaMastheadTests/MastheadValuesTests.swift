import Testing

@testable import ArcaMasthead

/// The values a masthead's tokens take (design.md "The file"): the bundle's,
/// then those the app names and has.
/// Acceptance test AT-02.2, in ST0001's acceptance.md.
@Suite("Masthead values")
struct MastheadValuesTests {
  static var info: [String: Any] {
    [
      "CFBundleName": "menuz", "CFBundleShortVersionString": "0.3.0", "CFBundleVersion": "1242",
      "ArcaCommit": "56e0c90", "ArcaKind": "release",
    ]
  }

  /// What the app has, whether or not it names it.
  static let app = ["version": "0.4.0", "status": "serving"]

  @Test("the bundle gives name, version, commit and kind, from the keys of its Info.plist")
  func bundle() {
    let values = MastheadValues(bundle: Self.info)
    #expect(values.given == ["name": "menuz", "version": "0.3.0", "commit": "56e0c90", "kind": "release"])
    #expect(values.names == ["name", "version", "commit", "kind"])
  }

  @Test("a stamp that is absent, empty or not text gives no value, and its token is still the bundle's")
  func absentStamps() {
    let values = MastheadValues(bundle: ["CFBundleName": "menuz", "ArcaCommit": "", "ArcaKind": 1])
    #expect(values.given == ["name": "menuz"])
    #expect(values.names == ["name", "version", "commit", "kind"])
  }

  @Test("a value the app names is added to the bundle's, or takes the bundle's place")
  func owned() {
    let values = MastheadValues(bundle: Self.info, owned: ["version", "status"]) { Self.app[$0] }
    let given = ["name": "menuz", "version": "0.4.0", "commit": "56e0c90", "kind": "release", "status": "serving"]
    #expect(values.given == given)
    #expect(values.names == ["name", "version", "commit", "kind", "status"])
  }

  @Test("the app is asked for the values it names, and for nothing else")
  func askedOwned() {
    var asked: [String] = []
    let values = MastheadValues(bundle: Self.info, owned: ["status"]) { name in
      asked.append(name)
      return Self.app[name]
    }
    #expect(asked == ["status"])
    #expect(values.given["version"] == "0.3.0")
  }

  @Test("a value the app names but has not got yet is missing, whatever the bundle gives")
  func notYet() {
    let values = MastheadValues(bundle: Self.info, owned: ["version", "commit", "user"])
    #expect(values.given == ["name": "menuz", "kind": "release"])
    #expect(values.names == ["name", "version", "commit", "kind", "user"])
  }

  @Test("an empty value from the app is a value")
  func emptyValue() {
    let values = MastheadValues(bundle: Self.info, owned: ["status"]) { _ in "" }
    #expect(values.given["status"] == "")
  }
}
