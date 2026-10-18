import ArcaCore
import Foundation

/// The About window's content (design.md "The About window"): the body as
/// HTML, the app's stylesheet, and what was refused on the way.
struct AboutContent: Equatable, Sendable {
  /// The body as HTML, or nil when no copy of it could be read.
  let body: String?
  /// The app's stylesheet, or nil when masthead.yaml names none or no copy
  /// of it could be read.
  let css: String?
  /// Each copy that was refused and each token in the body that names no
  /// value the app gives, the body's before the stylesheet's, for the page
  /// and the app's log.
  let refusals: [Refusal]

  /// The files `about` names, each found as masthead.yaml is: the copy in
  /// `folder` first, then `bundle`'s. A copy that is refused leaves the next
  /// in use, and a token in the body that names no value the app gives is
  /// refused, naming the copy used, once for each token, in order.
  static func load(
    _ about: MastheadFile.About, folder: String, bundle: Bundle, values: MastheadValues
  ) -> AboutContent {
    let body = ConfigFile.first(named: about.body, folder: folder, bundle: bundle) { file in
      file.text().map { (path: file.path, html: html($0, as: about.kind, values: values)) }
    }
    let css = about.css.map { name in
      ConfigFile.first(named: name, folder: folder, bundle: bundle) { $0.text() }
    }
    let unknown =
      body.value.map { found in
        found.html.missing.filter { !values.names.contains($0) }.map { token in
          Refusal(file: found.path, key: nil, value: nil, why: MastheadValues.unknown(token, names: values.names))
        }
      } ?? []
    return AboutContent(
      body: body.value?.html.text, css: css?.value, refusals: body.refusals + unknown + (css?.refusals ?? []))
  }

  /// `text` as HTML: Markdown through cmark-gfm, or HTML as written. Each
  /// token then takes its value, escaped for HTML, so a value is never
  /// markup in an element's text or a quoted attribute; a token with no
  /// value stays as written, and is named in the rendering's `missing`. The
  /// tokens are read in the HTML, so a token in a Markdown link's address,
  /// which cmark-gfm percent-encodes, stays as written: write that link in
  /// HTML.
  static func html(_ text: String, as kind: MastheadFile.About.Kind, values: MastheadValues) -> Rendering {
    let html =
      switch kind {
      case .markdown: Markdown.html(text)
      case .html: text
      }
    return Template(html).render(values.given.mapValues(HTML.escape))
  }
}
