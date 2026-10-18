/// The values a masthead's tokens take (design.md "The file"). The bundle
/// gives `{name}`, `{version}`, `{commit}` and `{kind}`, from its Info.plist's
/// CFBundleName, CFBundleShortVersionString, ArcaCommit and ArcaKind. The
/// app names the values it gives, once, each adding a value or taking the
/// bundle's place, and is asked for them at every menu open. A value it names
/// but has not got yet is missing, whatever the bundle gives, so an app whose
/// version comes from its CLI shows none until the CLI answers.
struct MastheadValues: Equatable, Sendable {
  /// Each value a token may name, whether or not there is one yet.
  let names: Set<String>
  /// The values there are.
  let given: [String: String]

  /// Each value the bundle gives, and the Info.plist key it is read from.
  private static let stamps = [
    "name": "CFBundleName", "version": "CFBundleShortVersionString", "commit": "ArcaCommit", "kind": "ArcaKind",
  ]

  /// `owned` names the values the app gives, and `ask` is asked for each of
  /// them and for nothing else: nil means the app has not got it yet. A stamp
  /// that is absent, empty or not text gives no value.
  init(bundle info: [String: Any], owned: Set<String> = [], value ask: (String) -> String? = { _ in nil }) {
    var given: [String: String] = [:]
    for (name, stamp) in Self.stamps where !owned.contains(name) {
      if let text = info[stamp] as? String, !text.isEmpty { given[name] = text }
    }
    for name in owned {
      if let text = ask(name) { given[name] = text }
    }
    self.names = Set(Self.stamps.keys).union(owned)
    self.given = given
  }

  /// The app's name alone, for a heading that cannot be shown: the `{name}`
  /// value, or nothing when there is none.
  var appName: String {
    given["name"] ?? ""
  }

  /// Why `token` is refused, in a line or in the About body: it names no
  /// value the app gives, and `names` are those it does.
  static func unknown(_ token: String, names: Set<String>) -> String {
    let those = MastheadFile.list(names.sorted().map { "{\($0)}" })
    return "has {\(token)}, which is not a value the app gives: those are \(those)"
  }
}
