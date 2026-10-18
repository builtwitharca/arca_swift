import Testing

@testable import ArcaCore

/// A config file's text read as YAML: every scalar as written, and a
/// refusal for what is not a mapping of keys (design.md "The file").
@Suite("Config document")
struct ConfigDocumentTests {
  static func read(_ yaml: String) -> Result<[ConfigEntry], Refusal> {
    ConfigDocument.entries(yaml, file: "masthead.yaml")
  }

  static func refusal(_ yaml: String) -> Refusal? {
    guard case .failure(let refusal) = read(yaml) else { return nil }
    return refusal
  }

  static func refused(_ key: String?, _ why: String) -> Result<[ConfigEntry], Refusal> {
    .failure(Refusal(file: "masthead.yaml", key: key, value: nil, why: why))
  }

  @Test("a mapping's entries come in the file's order, each scalar as the text it was written as")
  func scalars() {
    #expect(
      Self.read("kind: true\nversion: 0.10\nnone: ~\nquoted: 'it''s'\nempty:\n")
        == .success([
          ConfigEntry(key: "kind", value: .text("true")),
          ConfigEntry(key: "version", value: .text("0.10")),
          ConfigEntry(key: "none", value: .text("~")),
          ConfigEntry(key: "quoted", value: .text("it's")),
          ConfigEntry(key: "empty", value: .text("")),
        ]))
  }

  @Test("mappings and lists nest, and an alias reads as the node its anchor names")
  func nesting() {
    #expect(
      Self.read("about:\n  body: about.md\nrows: &rows\n  - one\n  - two\nagain: *rows\n")
        == .success([
          ConfigEntry(key: "about", value: .map([ConfigEntry(key: "body", value: .text("about.md"))])),
          ConfigEntry(key: "rows", value: .list([.text("one"), .text("two")])),
          ConfigEntry(key: "again", value: .list([.text("one"), .text("two")])),
        ]))
  }

  @Test("an empty file, one of comments only, or a document that is null has no entries")
  func empty() {
    #expect(Self.read("") == .success([]))
    #expect(Self.read("# nothing yet\n") == .success([]))
    #expect(Self.read("---\n") == .success([]))
    #expect(Self.read("~\n") == .success([]))
  }

  @Test("text that is not YAML is refused in one line: the problem, where it is, and what was being read")
  func notYAML() {
    let flow =
      "not YAML: line 2, column 1: did not find expected ',' or ']', "
      + "while parsing a flow sequence in line 1, column 10"
    #expect(Self.read("heading: [menuz\n") == Self.refused(nil, flow))
    #expect(
      Self.read("a: b: c\n")
        == Self.refused(nil, "not YAML: line 1, column 5: mapping values are not allowed in this context"))
  }

  @Test("a key given twice is refused, naming the key and where it first is")
  func duplicate() {
    let twice = "the key 'heading' is given more than once, first in line 1, column 1"
    #expect(Self.read("heading: a\nheading: b\n") == Self.refused(nil, twice))
    // Yams lets these through, since its keys differ in tag: on is a Bool to YAML, 'on' a string.
    #expect(
      Self.read("on: a\n'on': b\n")
        == Self.refused(nil, "the key 'on' is given more than once, first in line 1, column 1"))
    #expect(
      Self.read("about:\n  1: a\n  '1': b\n")
        == Self.refused("about", "the key '1' is given more than once, first in line 2, column 3"))
    // Yams refuses this one itself, before the walk knows the path.
    #expect(
      Self.read("about:\n  body: a\n  body: b\n")
        == Self.refused(nil, "the key 'body' is given more than once, first in line 2, column 3"))
  }

  @Test("a merge key is a key like any other, since composing applies no merge")
  func mergeKey() {
    let css = ConfigEntry(key: "css", value: .text("about.css"))
    #expect(
      Self.read("base: &base\n  css: about.css\nabout:\n  <<: *base\n  body: about.md\n")
        == .success([
          ConfigEntry(key: "base", value: .map([css])),
          ConfigEntry(
            key: "about",
            value: .map([
              ConfigEntry(key: "<<", value: .map([css])), ConfigEntry(key: "body", value: .text("about.md")),
            ])),
        ]))
  }

  @Test("a file that is not a mapping of keys is refused, a quoted empty document included")
  func notMapping() {
    #expect(Self.read("- one\n") == Self.refused(nil, "the file is not a mapping of keys"))
    #expect(Self.read("just text\n") == Self.refused(nil, "the file is not a mapping of keys"))
    #expect(Self.read("''\n") == Self.refused(nil, "the file is not a mapping of keys"))
  }

  @Test("a key that is a list or a mapping is refused at the path of the mapping that holds it")
  func complexKey() {
    let why = "a key is a list or a mapping, not text"
    #expect(Self.read("? [a, b]\n: 1\n") == Self.refused(nil, why))
    #expect(Self.read("about:\n  ? {a: 1}\n  : 2\n") == Self.refused("about", why))
    #expect(Self.read("rows:\n  - ? [a]\n    : 1\n") == Self.refused("rows[0]", why))
  }
}

/// A refusal prints as one line, as an app's log and its menu show it.
@Suite("Refusal")
struct RefusalTests {
  @Test("the file, the key's path and its value, and why")
  func keyAndValue() {
    let refusal = Refusal(file: "masthead.yaml", key: "about.body", value: "about.txt", why: "not .md or .html")
    #expect(refusal.description == "masthead.yaml: about.body = 'about.txt': not .md or .html")
  }

  @Test("a key with no value prints without one, a value with no key keeps the value, and the whole file has neither")
  func shorter() {
    #expect(
      Refusal(file: "masthead.yaml", key: "heading", value: nil, why: "is required").description
        == "masthead.yaml: heading: is required")
    #expect(
      Refusal(file: "masthead.yaml", key: nil, value: "- one", why: "the file is not a mapping of keys").description
        == "masthead.yaml: '- one': the file is not a mapping of keys")
    #expect(
      Refusal(file: "masthead.yaml", key: nil, value: nil, why: "not UTF-8 text").description
        == "masthead.yaml: not UTF-8 text")
  }

  @Test("a line break or other control character in any part prints as its escape, so a refusal stays one line")
  func oneLine() {
    let refusal = Refusal(file: "masthead.yaml", key: "a\nb", value: "x\ty\u{7}", why: "line\u{2028}two")
    #expect(refusal.description == "masthead.yaml: a\\nb = 'x\\ty\\u{7}': line\\u{2028}two")
  }
}
