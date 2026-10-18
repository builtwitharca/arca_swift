import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Markdown made HTML by cmark-gfm, as GitHub renders it, for the About
/// window (design.md "The About window"): tables, strikethrough, autolinks
/// and task lists. HTML written in the Markdown passes through, so an
/// about.html and an about.md take one path. The page is the app's or its
/// user's own file, and the window runs none of its JavaScript, so GitHub's
/// tag filter stays off and a page's `<style>` is kept.
enum Markdown {
  static func html(_ markdown: String) -> String {
    _ = registered
    guard let parser = cmark_parser_new(options) else {
      fatalError("cmark-gfm made no parser")
    }
    defer { cmark_parser_free(parser) }
    for name in extensions {
      guard let syntax = cmark_find_syntax_extension(name), cmark_parser_attach_syntax_extension(parser, syntax) == 1
      else {
        fatalError("cmark-gfm could not attach its \(name) extension")
      }
    }
    cmark_parser_feed(parser, markdown, markdown.utf8.count)
    guard let document = cmark_parser_finish(parser) else {
      fatalError("cmark-gfm parsed no document")
    }
    defer { cmark_node_free(document) }
    guard let html = cmark_render_html(document, options, cmark_parser_get_syntax_extensions(parser)) else {
      fatalError("cmark-gfm rendered no HTML")
    }
    defer { free(html) }
    return String(cString: html)
  }

  /// HTML in the Markdown is kept, where cmark's default puts a comment in
  /// its place.
  private static let options = CMARK_OPT_UNSAFE
  private static let extensions = ["table", "strikethrough", "autolink", "tasklist"]
  /// cmark-gfm registers its extensions once per process.
  private static let registered: Void = cmark_gfm_core_extensions_ensure_registered()
}
