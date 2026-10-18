import ArcaCore
import Foundation
import Testing

@testable import ArcaMasthead

/// The About window's page (design.md "The About window"): its policy, the
/// window's stylesheet and the app's, the refusals and the body, in that
/// order.
/// Acceptance test AT-03.2, in ST0001's acceptance.md.
@Suite("About document")
struct AboutDocumentTests {
  static let refusal = Refusal(file: "/home/ada/.config/menuz/about.css", key: nil, value: nil, why: "not UTF-8 text")

  /// Where `text` first is in `html`, or nil.
  static func offset(of text: String, in html: String) -> Int? {
    html.range(of: text).map { html.distance(from: html.startIndex, to: $0.lowerBound) }
  }

  @Test("the page is the policy, the window's stylesheet, the app's, the refusals and the body, in that order")
  func whole() {
    let html = AboutDocument.html(
      title: "menuz 0.3.0", body: "<h1>menuz</h1>\n", css: "p { color: blue }\n", refusals: [Self.refusal])
    let page = [
      "<!doctype html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n",
      "<meta http-equiv=\"Content-Security-Policy\" content=\"\(AboutDocument.policy)\">\n",
      "<title>menuz 0.3.0</title>\n",
      "<style>\n\(AboutDocument.stylesheet)</style>\n",
      "<style>\np { color: blue }\n</style>\n",
      "</head>\n<body>\n",
      "<ul class=\"refusals\">\n",
      "<li>/home/ada/.config/menuz/about.css: not UTF-8 text</li>\n",
      "</ul>\n",
      "<h1>menuz</h1>\n</body>\n</html>\n",
    ]
    #expect(html == page.joined())
  }

  @Test("the policy allows no source but the page's own styles, data: images and the images the app serves")
  func policy() {
    #expect(
      AboutDocument.policy
        == "default-src 'none'; img-src data: arca-about:; style-src 'unsafe-inline'; form-action 'none'; "
        + "base-uri 'none'")
  }

  @Test("the policy comes before anything it governs")
  func policyFirst() throws {
    let html = AboutDocument.html(title: "menuz", body: "<p>here</p>\n", css: "p { color: blue }\n", refusals: [])
    let policy = try #require(Self.offset(of: "<meta http-equiv=\"Content-Security-Policy\"", in: html))
    for later in ["<title>", "<style>", "<body>", "<p>here</p>"] {
      let offset = try #require(Self.offset(of: later, in: html))
      #expect(policy < offset, "\(later) comes before the policy")
    }
  }

  @Test("the window's stylesheet follows light and dark mode, and the app's is laid over it")
  func stylesheets() throws {
    #expect(AboutDocument.stylesheet.contains("color-scheme: light dark"))
    let html = AboutDocument.html(title: "menuz", body: nil, css: "p { color: blue }\n", refusals: [])
    let window = try #require(Self.offset(of: AboutDocument.stylesheet, in: html))
    let app = try #require(Self.offset(of: "p { color: blue }", in: html))
    #expect(window < app)
  }

  @Test("each refusal, and the title, is escaped for HTML")
  func escaped() {
    let refusal = Refusal(
      file: "/home/ada/.config/menuz/masthead.yaml", key: "icon", value: "<img src=x>", why: "is not app or none")
    let html = AboutDocument.html(title: "Tom & <co>", body: nil, css: nil, refusals: [refusal])
    #expect(html.contains("<title>Tom &amp; &lt;co&gt;</title>"))
    #expect(
      html.contains(
        "<li>/home/ada/.config/menuz/masthead.yaml: icon = &#39;&lt;img src=x&gt;&#39;: is not app or none</li>"))
    #expect(!html.contains("<img src=x>"))
  }

  @Test("the app's stylesheet cannot end its style element, in any case")
  func contained() {
    let html = AboutDocument.html(
      title: "menuz", body: nil, css: "p { color: blue }</style><p id=\"x\">\n</STYLE >\n", refusals: [])
    #expect(html.contains("p { color: blue }<\\/style><p id=\"x\">\n<\\/STYLE >\n</style>\n"))
    #expect(html.components(separatedBy: "</style>").count == 3)
  }

  @Test("with no refusals the page has no list of them, and with no body it has the refusals alone")
  func parts() {
    let body = AboutDocument.html(title: "menuz", body: "<p>here</p>\n", css: nil, refusals: [])
    #expect(!body.contains("<ul class=\"refusals\">"))
    #expect(body.hasSuffix("<body>\n<p>here</p>\n</body>\n</html>\n"))
    #expect(body.components(separatedBy: "<style>").count == 2)
    let refused = AboutDocument.html(title: "menuz", body: nil, css: nil, refusals: [Self.refusal])
    #expect(
      refused.hasSuffix(
        "<body>\n<ul class=\"refusals\">\n<li>/home/ada/.config/menuz/about.css: not UTF-8 text</li>\n</ul>\n"
          + "</body>\n</html>\n"))
  }

  @Test("a page's title is the heading, and masthead.yaml's refusals come before the About files'")
  func page() {
    let icon = Refusal(
      file: "/home/ada/.config/menuz/masthead.yaml", key: "icon", value: "logo", why: "is not app or none")
    let masthead = Masthead(
      heading: "menuz 0.3.0", subheading: icon.description, icon: .app, about: Menuz.about, refusals: [icon])
    let content = AboutContent(body: "<h1>menuz</h1>\n", css: "p { color: blue }\n", refusals: [Self.refusal])
    let html = AboutDocument.html(
      title: "menuz 0.3.0", body: "<h1>menuz</h1>\n", css: "p { color: blue }\n", refusals: [icon, Self.refusal])
    let page = AboutDocument.Page(title: "menuz 0.3.0", html: html)
    #expect(AboutDocument.page(masthead: masthead, content: content) == page)
  }

  @Test("with no masthead.yaml to use, the page is its refusals alone, under the app's name")
  func pageAlone() {
    let why = "is not there, and the app's bundle has none"
    let absent = Refusal(file: "/home/ada/.config/menuz/masthead.yaml", key: nil, value: nil, why: why)
    let masthead = Masthead(
      heading: "menuz", subheading: absent.description, icon: .app, about: nil, refusals: [absent])
    let html = AboutDocument.html(title: "menuz", body: nil, css: nil, refusals: [absent])
    #expect(AboutDocument.page(masthead: masthead, content: nil) == AboutDocument.Page(title: "menuz", html: html))
  }
}
