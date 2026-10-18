import ArcaCore
import Testing

@testable import ArcaMasthead

/// masthead.yaml checked against its schema (design.md "The file"), each
/// refusal naming the file, the key and the value.
/// Acceptance test AT-02.1, in ST0001's acceptance.md.
@Suite("Masthead file")
struct MastheadFileTests {
  /// The values every app's bundle gives.
  static let bundleNames: Set<String> = ["name", "version", "commit", "kind"]

  static func check(_ yaml: String, names: Set<String> = bundleNames) -> Result<MastheadFile, Refusal> {
    ConfigDocument.entries(yaml, file: "masthead.yaml").flatMap {
      MastheadFile.check($0, file: "masthead.yaml", names: names)
    }
  }

  static func refused(_ key: String, _ value: String?, _ why: String) -> Result<MastheadFile, Refusal> {
    .failure(Refusal(file: "masthead.yaml", key: key, value: value, why: why))
  }

  /// A file whose heading passes, with `lines` as its about's.
  static func about(_ lines: String) -> Result<MastheadFile, Refusal> {
    check("heading: menuz\nabout:\n\(lines)")
  }

  @Test("a file with every key")
  func full() {
    let yaml =
      "heading: \"{name} {version}\"\nsubheading: \"{commit} · {kind}\"\nicon: none\n"
      + "about:\n  body: about.md\n  css: about.css\n"
    #expect(
      Self.check(yaml)
        == .success(
          MastheadFile(
            heading: Template("{name} {version}"), subheading: Template("{commit} · {kind}"), icon: .omitted,
            about: MastheadFile.About(body: "about.md", kind: .markdown, css: "about.css"))))
  }

  @Test("only the heading and the About body are required, and with no icon the row shows the app's")
  func least() {
    #expect(
      Self.check("heading: menuz\nabout:\n  body: about.html\n")
        == .success(
          MastheadFile(
            heading: Template("menuz"), subheading: nil, icon: .app,
            about: MastheadFile.About(body: "about.html", kind: .html, css: nil))))
    #expect(Self.check("heading: menuz\nicon: app\nabout:\n  body: about.md\n").map(\.icon) == .success(.app))
  }

  @Test("a required key that is missing is refused, an empty file's heading first")
  func required() {
    #expect(Self.check("") == Self.refused("heading", nil, "is required"))
    #expect(Self.check("about:\n  body: about.md\n") == Self.refused("heading", nil, "is required"))
    #expect(Self.check("heading: menuz\n") == Self.refused("about", nil, "is required"))
    #expect(Self.about("  css: about.css\n") == Self.refused("about.body", nil, "is required"))
  }

  @Test("a key the file does not have is refused, naming the keys it does")
  func unknownKey() {
    let keys = "is not one of the keys heading, subheading, icon and about"
    #expect(Self.check("heading: menuz\nhedaing: x\nabout:\n  body: about.md\n") == Self.refused("hedaing", "x", keys))
    #expect(Self.check("heading: menuz\nrows:\n  - a\nabout:\n  body: about.md\n") == Self.refused("rows", nil, keys))
    #expect(
      Self.about("  body: about.md\n  style: about.css\n")
        == Self.refused("about.style", "about.css", "is not one of the keys body and css"))
  }

  @Test("a value of the wrong kind is refused, saying what it is and what it should be")
  func wrongKind() {
    #expect(
      Self.check("heading:\n  - menuz\nabout:\n  body: about.md\n")
        == Self.refused("heading", nil, "is a list, not text"))
    #expect(
      Self.check("heading: menuz\nsubheading:\n  a: b\nabout:\n  body: about.md\n")
        == Self.refused("subheading", nil, "is a mapping, not text"))
    #expect(
      Self.check("heading: menuz\nabout: about.md\n") == Self.refused("about", "about.md", "is text, not a mapping"))
    #expect(
      Self.check("heading: menuz\nabout:\n  - about.md\n") == Self.refused("about", nil, "is a list, not a mapping"))
    #expect(Self.about("  body:\n    - about.md\n") == Self.refused("about.body", nil, "is a list, not text"))
    #expect(
      Self.check("heading: menuz\nicon:\n  - app\nabout:\n  body: about.md\n")
        == Self.refused("icon", nil, "is a list, not text"))
    #expect(
      Self.about("  body: about.md\n  css:\n    a: b\n") == Self.refused("about.css", nil, "is a mapping, not text"))
  }

  @Test("a heading with no text in it is refused")
  func blankHeading() {
    #expect(Self.check("heading: ''\nabout:\n  body: about.md\n") == Self.refused("heading", "", "is blank"))
    #expect(Self.check("heading:\nabout:\n  body: about.md\n") == Self.refused("heading", "", "is blank"))
    #expect(Self.check("heading: \" \\t\"\nabout:\n  body: about.md\n") == Self.refused("heading", " \t", "is blank"))
  }

  @Test("a subheading may be blank, which hides it")
  func blankSubheading() {
    #expect(
      Self.check("heading: menuz\nsubheading: ''\nabout:\n  body: about.md\n").map(\.subheading)
        == .success(Template("")))
  }

  @Test("the icon is app or none, as written", arguments: ["logo.png", "App", "none."])
  func icon(icon: String) {
    #expect(
      Self.check("heading: menuz\nicon: \(icon)\nabout:\n  body: about.md\n")
        == Self.refused("icon", icon, "is not app or none"))
  }

  @Test("a .md body is Markdown and a .html one HTML, the stylesheet a .css file, the extension in any case")
  func fileNames() {
    #expect(
      Self.about("  body: About.MD\n  css: Site.CSS\n").map(\.about)
        == .success(MastheadFile.About(body: "About.MD", kind: .markdown, css: "Site.CSS")))
    #expect(
      Self.about("  body: about.HTML\n").map(\.about)
        == .success(MastheadFile.About(body: "about.HTML", kind: .html, css: nil)))
    #expect(Self.about("  body: about.txt\n") == Self.refused("about.body", "about.txt", "is not a .md or .html file"))
    #expect(Self.about("  body: about\n") == Self.refused("about.body", "about", "is not a .md or .html file"))
    #expect(
      Self.about("  body: about.md\n  css: about.scss\n")
        == Self.refused("about.css", "about.scss", "is not a .css file"))
  }

  @Test(
    "a body with a folder in its name is refused, since it is found beside masthead.yaml",
    arguments: ["docs/about.md", "../about.md", "/etc/about.md"])
  func bodyPath(body: String) {
    #expect(Self.about("  body: \(body)\n") == Self.refused("about.body", body, "is a path, not a file name"))
  }

  @Test("a stylesheet with a folder in its name is refused too")
  func cssPath() {
    #expect(
      Self.about("  body: about.md\n  css: css/about.css\n")
        == Self.refused("about.css", "css/about.css", "is a path, not a file name"))
  }

  @Test("the first refusal in the file's order is the one given")
  func firstRefusal() {
    #expect(Self.check("icon: logo\nhedaing: x\n") == Self.refused("icon", "logo", "is not app or none"))
    #expect(
      Self.check("about:\n  body: about.txt\nheading: ''\n")
        == Self.refused("about.body", "about.txt", "is not a .md or .html file"))
  }
}
