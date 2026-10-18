import Testing

@testable import ArcaMasthead

/// The About body's Markdown (design.md "The About window"): cmark-gfm with
/// GitHub's extensions, and HTML passed through.
@Suite("Markdown")
struct MarkdownTests {
  @Test("a paragraph becomes HTML")
  func paragraph() {
    #expect(Markdown.html("Hello *world*") == "<p>Hello <em>world</em></p>\n")
  }

  @Test("HTML in the Markdown passes through, a page's style included")
  func html() {
    #expect(Markdown.html("<div class=\"note\">kept</div>\n") == "<div class=\"note\">kept</div>\n")
    #expect(Markdown.html("<style>p { color: red }</style>\n") == "<style>p { color: red }</style>\n")
  }

  @Test("GitHub's tables, strikethrough, autolinks and task lists")
  func extensions() {
    let table =
      "<table>\n<thead>\n<tr>\n<th>a</th>\n<th>b</th>\n</tr>\n</thead>\n"
      + "<tbody>\n<tr>\n<td>1</td>\n<td>2</td>\n</tr>\n</tbody>\n</table>\n"
    #expect(Markdown.html("| a | b |\n|---|---|\n| 1 | 2 |\n") == table)
    #expect(Markdown.html("~~old~~") == "<p><del>old</del></p>\n")
    #expect(
      Markdown.html("see https://example.com")
        == "<p>see <a href=\"https://example.com\">https://example.com</a></p>\n")
    #expect(
      Markdown.html("- [x] done\n")
        == "<ul>\n<li><input type=\"checkbox\" checked=\"\" disabled=\"\" /> done</li>\n</ul>\n")
  }

  @Test("a line break in a paragraph, quotes and dashes stay as written, as GitHub shows a .md file")
  func asWritten() {
    #expect(Markdown.html("it's -- a\nb") == "<p>it's -- a\nb</p>\n")
  }
}
