import ArcaCore
import Foundation

/// masthead.yaml, checked (design.md "The file"): the top line's heading and
/// subheading, the row's icon, and the About window's files.
struct MastheadFile: Equatable, Sendable {
  /// The row's image: `app` shows the app's icon, and `none` shows none.
  enum Icon: Equatable, Sendable {
    case app
    case omitted
  }

  /// The About window's files. Each is a file name, found as masthead.yaml
  /// is: in the app's config folder, then in its bundle.
  struct About: Equatable, Sendable {
    /// How the body becomes HTML, which its extension decides.
    enum Kind: Equatable, Sendable {
      /// A .md file, through cmark-gfm.
      case markdown
      /// A .html file, as written.
      case html
    }

    /// A .md or .html file.
    let body: String
    let kind: Kind
    /// A .css file, laid over the window's own stylesheet.
    let css: String?
  }

  let heading: Template
  let subheading: Template?
  let icon: Icon
  let about: About

  /// The file's entries checked against the schema, or the first refusal in
  /// the file's order, naming the key and its value. `names` are the values
  /// the app gives, and a token in the heading or the subheading must name
  /// one of them.
  static func check(_ entries: [ConfigEntry], file: String, names: Set<String>) -> Result<MastheadFile, Refusal> {
    do throws(Refusal) {
      return .success(try Check(file: file, names: names).masthead(entries))
    } catch {
      return .failure(error)
    }
  }

  /// The top line this file makes with `values`, each line on its own. A
  /// heading with a value missing, or that comes out blank, is the app's
  /// name alone, and such a subheading is hidden.
  func masthead(_ values: MastheadValues) -> Masthead {
    Masthead(
      heading: Self.shown(heading.render(values.given)) ?? values.appName,
      subheading: subheading.flatMap { Self.shown($0.render(values.given)) }, icon: icon, about: about, refusals: [])
  }

  /// A line's text, or nil when a value is missing from it or it is blank.
  private static func shown(_ line: Rendering) -> String? {
    line.missing.isEmpty && !isBlank(line.text) ? line.text : nil
  }

  /// Whether `text` is empty or white space alone.
  fileprivate static func isBlank(_ text: String) -> Bool {
    text.allSatisfy(\.isWhitespace)
  }
}

/// The check of masthead.yaml's entries. Each key is checked where the file
/// has it, so the first refusal is the first in the file's order; a required
/// key that is missing is refused after them.
private struct Check {
  /// The file's keys, and its about's, in the order a refusal names them.
  static let keys = ["heading", "subheading", "icon", "about"]
  static let aboutKeys = ["body", "css"]
  /// The kind of body each extension makes, in lower case: the one place a
  /// body's extension is read.
  static let kinds: [String: MastheadFile.About.Kind] = ["md": .markdown, "html": .html]

  let file: String
  let names: Set<String>

  func masthead(_ entries: [ConfigEntry]) throws(Refusal) -> MastheadFile {
    var heading: Template?
    var subheading: Template?
    var icon = MastheadFile.Icon.app
    var about: MastheadFile.About?
    for entry in entries {
      switch entry.key {
      case "heading": heading = try self.heading(entry.value)
      case "subheading": subheading = try template(text(entry.value, at: "subheading"), at: "subheading")
      case "icon": icon = try self.icon(entry.value)
      case "about": about = try self.about(entry.value)
      default: throw unknown(entry, at: entry.key, keys: Self.keys)
      }
    }
    guard let heading else { throw refusal("heading", nil, "is required") }
    guard let about else { throw refusal("about", nil, "is required") }
    return MastheadFile(heading: heading, subheading: subheading, icon: icon, about: about)
  }

  func heading(_ node: ConfigNode) throws(Refusal) -> Template {
    let text = try self.text(node, at: "heading")
    guard !MastheadFile.isBlank(text) else { throw refusal("heading", text, "is blank") }
    return try template(text, at: "heading")
  }

  /// `text` as a template, each of whose tokens names a value the app gives.
  func template(_ text: String, at key: String) throws(Refusal) -> Template {
    let template = Template(text)
    if let token = template.tokens.first(where: { !names.contains($0) }) {
      let those = Self.list(names.sorted().map { "{\($0)}" })
      throw refusal(key, text, "has {\(token)}, which is not a value the app gives: those are \(those)")
    }
    return template
  }

  func icon(_ node: ConfigNode) throws(Refusal) -> MastheadFile.Icon {
    switch try text(node, at: "icon") {
    case "app": return .app
    case "none": return .omitted
    case let other: throw refusal("icon", other, "is not app or none")
    }
  }

  func about(_ node: ConfigNode) throws(Refusal) -> MastheadFile.About {
    var body: (name: String, kind: MastheadFile.About.Kind)?
    var css: String?
    for entry in try mapping(node, at: "about") {
      let key = "about.\(entry.key)"
      switch entry.key {
      case "body":
        let name = try fileName(entry.value, at: key)
        guard let kind = Self.kinds[Self.suffix(name)] else { throw refusal(key, name, "is not a .md or .html file") }
        body = (name: name, kind: kind)
      case "css":
        let name = try fileName(entry.value, at: key)
        guard Self.suffix(name) == "css" else { throw refusal(key, name, "is not a .css file") }
        css = name
      default: throw unknown(entry, at: key, keys: Self.aboutKeys)
      }
    }
    guard let body else { throw refusal("about.body", nil, "is required") }
    return MastheadFile.About(body: body.name, kind: body.kind, css: css)
  }

  /// A file name with no folder in it, since the file is found beside
  /// masthead.yaml.
  func fileName(_ node: ConfigNode, at key: String) throws(Refusal) -> String {
    let name = try text(node, at: key)
    guard !name.contains("/") else { throw refusal(key, name, "is a path, not a file name") }
    return name
  }

  func text(_ node: ConfigNode, at key: String) throws(Refusal) -> String {
    guard case .text(let text) = node else { throw mismatch(node, at: key, wanted: "text") }
    return text
  }

  func mapping(_ node: ConfigNode, at key: String) throws(Refusal) -> [ConfigEntry] {
    guard case .map(let entries) = node else { throw mismatch(node, at: key, wanted: "a mapping") }
    return entries
  }

  /// Why `node` is not what `key` takes: what it is, and what it should be.
  func mismatch(_ node: ConfigNode, at key: String, wanted: String) -> Refusal {
    let kind =
      switch node {
      case .text: "text"
      case .list: "a list"
      case .map: "a mapping"
      }
    return refusal(key, Self.text(of: node), "is \(kind), not \(wanted)")
  }

  func unknown(_ entry: ConfigEntry, at key: String, keys: [String]) -> Refusal {
    refusal(key, Self.text(of: entry.value), "is not one of the keys \(Self.list(keys))")
  }

  func refusal(_ key: String, _ value: String?, _ why: String) -> Refusal {
    Refusal(file: file, key: key, value: value, why: why)
  }

  /// A file name's extension, in lower case, so that its case does not count.
  static func suffix(_ name: String) -> String {
    (name as NSString).pathExtension.lowercased()
  }

  /// A node's text, or nil for a list or a mapping, which a refusal prints
  /// no value for.
  static func text(of node: ConfigNode) -> String? {
    guard case .text(let text) = node else { return nil }
    return text
  }

  /// `a, b and c`.
  static func list(_ items: [String]) -> String {
    guard let last = items.last, items.count > 1 else { return items.first ?? "" }
    return items.dropLast().joined(separator: ", ") + " and " + last
  }
}
