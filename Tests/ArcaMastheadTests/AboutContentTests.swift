import ArcaCore
import ArcaTestSupport
import Foundation
import Testing

@testable import ArcaMasthead

/// The About window's body and stylesheet (design.md "The About window").
/// Acceptance test AT-02.5, in ST0001's acceptance.md.
@Suite("About content")
struct AboutContentTests {
  /// What the app has: a user whose name needs escaping. It names a status
  /// too, which it has not got yet.
  static let app = ["user": "Tom <tj> & \"co\" 'x'"]
  static let values = MastheadValues(
    bundle: ["CFBundleName": "menuz", "CFBundleShortVersionString": "0.3.0"], owned: ["user", "status"],
    value: { Self.app[$0] })
  /// The user's value, escaped for HTML.
  static let user = "Tom &lt;tj&gt; &amp; &quot;co&quot; &#39;x&#39;"

  @Test("an about.md goes through cmark-gfm, and its tokens then take their values")
  func markdown() {
    #expect(
      AboutContent.html("# {name} {version}\n\nIt's *here*.\n", as: .markdown, values: Self.values)
        == "<h1>menuz 0.3.0</h1>\n<p>It's <em>here</em>.</p>\n")
  }

  @Test("an about.html is used as written, where cmark-gfm would change it, its tokens taking their values")
  func html() {
    let text = "<b>{name}</b> *as written*\n"
    #expect(AboutContent.html(text, as: .html, values: Self.values) == "<b>menuz</b> *as written*\n")
    #expect(AboutContent.html(text, as: .markdown, values: Self.values) == "<p><b>menuz</b> <em>as written</em></p>\n")
  }

  @Test("each value is escaped for HTML, in text and in a quoted attribute, so it is never markup there")
  func escaped() {
    #expect(AboutContent.html("By {user}.\n", as: .markdown, values: Self.values) == "<p>By \(Self.user).</p>\n")
    #expect(
      AboutContent.html("<a title=\"{user}\" href='x'>{user}</a>", as: .html, values: Self.values)
        == "<a title=\"\(Self.user)\" href='x'>\(Self.user)</a>")
  }

  @Test("a value goes in once the Markdown is HTML, so the value's own Markdown is text")
  func valueNotMarkdown() {
    let values = MastheadValues(bundle: [:], owned: ["user"]) { _ in "*Ada*" }
    #expect(AboutContent.html("By {user}.\n", as: .markdown, values: values) == "<p>By *Ada*.</p>\n")
  }

  @Test("a token with no value stays as written")
  func missing() {
    #expect(
      AboutContent.html("{status} and {nothing}\n", as: .markdown, values: Self.values)
        == "<p>{status} and {nothing}</p>\n")
  }

  @Test("a Markdown link's address keeps its token, which cmark-gfm encodes, and an HTML link's takes the value")
  func linkAddress() {
    #expect(
      AboutContent.html("[notes](https://example.com/{version})\n", as: .markdown, values: Self.values)
        == "<p><a href=\"https://example.com/%7Bversion%7D\">notes</a></p>\n")
    #expect(
      AboutContent.html("<a href=\"https://example.com/{version}\">notes</a>\n", as: .markdown, values: Self.values)
        == "<p><a href=\"https://example.com/0.3.0\">notes</a></p>\n")
  }

  @Test("the body and the stylesheet are found as masthead.yaml is, the config folder's copy first")
  func found() throws {
    try Scratch.folder { scratch in
      let app = try Scratch.app(in: scratch)
      _ = try Scratch.write("# {name}\n", to: "About.MD", in: app.folder)
      _ = try Scratch.write("p { color: blue }\n", to: "about.css", in: app.folder)
      _ = try Scratch.write("# bundled\n", to: "About.MD", in: app.resources)
      _ = try Scratch.write("p { color: red }\n", to: "about.css", in: app.resources)
      let bundle = try #require(Bundle(path: app.bundle))
      let about = MastheadFile.About(body: "About.MD", kind: .markdown, css: "about.css")
      #expect(
        AboutContent.load(about, folder: app.folder, bundle: bundle, values: Self.values)
          == AboutContent(body: "<h1>menuz</h1>\n", css: "p { color: blue }\n", refusals: []))
    }
  }

  @Test("a copy that is refused leaves the next in use, for the body and for the stylesheet")
  func refusedCopies() throws {
    try Scratch.folder { scratch in
      let app = try Scratch.app(in: scratch)
      let html = "\(app.folder)/about.html"
      let css = "\(app.folder)/about.css"
      try Data([0x3C, 0x62, 0x3E, 0xFC, 0x0A]).write(to: URL(fileURLWithPath: html))
      try Data([0x70, 0x20, 0xFC, 0x0A]).write(to: URL(fileURLWithPath: css))
      _ = try Scratch.write("<b>{name}</b> *as written*\n", to: "about.html", in: app.resources)
      _ = try Scratch.write("p { color: red }\n", to: "about.css", in: app.resources)
      let bundle = try #require(Bundle(path: app.bundle))
      let about = MastheadFile.About(body: "about.html", kind: .html, css: "about.css")
      let refusals = [
        Refusal(file: html, key: nil, value: nil, why: "not UTF-8 text"),
        Refusal(file: css, key: nil, value: nil, why: "not UTF-8 text"),
      ]
      #expect(
        AboutContent.load(about, folder: app.folder, bundle: bundle, values: Self.values)
          == AboutContent(body: "<b>menuz</b> *as written*\n", css: "p { color: red }\n", refusals: refusals))
    }
  }

  @Test("a body in neither place leaves no body")
  func noBody() throws {
    try Scratch.folder { scratch in
      let app = try Scratch.app(in: scratch)
      let bundle = try #require(Bundle(path: app.bundle))
      let refusal = Refusal(
        file: "\(app.folder)/about.md", key: nil, value: nil, why: "is not there, and the app's bundle has none")
      let about = MastheadFile.About(body: "about.md", kind: .markdown, css: nil)
      #expect(
        AboutContent.load(about, folder: app.folder, bundle: bundle, values: Self.values)
          == AboutContent(body: nil, css: nil, refusals: [refusal]))
    }
  }
}

/// Text made safe to put in HTML.
@Suite("HTML")
struct HTMLTests {
  @Test("&, <, >, \" and ' become entities, and every other character is kept")
  func escape() {
    #expect(HTML.escape("a & b < c > d \" e ' f ü ✓ {x}") == "a &amp; b &lt; c &gt; d &quot; e &#39; f ü ✓ {x}")
  }

  @Test("a quote or a bracket that a combining mark follows is escaped too")
  func combining() {
    #expect(HTML.escape("\"\u{301}<\u{301}") == "&quot;\u{301}&lt;\u{301}")
  }
}
