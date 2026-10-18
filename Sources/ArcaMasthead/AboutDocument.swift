import ArcaCore
import Foundation

/// The About window's page (design.md "The About window"): one HTML document
/// holding its policy, the window's stylesheet and the app's, the refusals
/// and the body, in that order.
enum AboutDocument {
  /// The scheme of the page's own address, at which the app serves the
  /// images its body names (AboutImages).
  static let scheme = "arca-about"
  /// The page's own address, against which a file name in the body is read.
  static let base = URL(string: "\(scheme)://page/")!

  /// The page's Content-Security-Policy: no source but its own styles, data:
  /// images and the images the app serves. A form and a base element are
  /// refused too, though the window cancels a form's navigation anyway.
  static let policy =
    "default-src 'none'; img-src data: \(scheme):; style-src 'unsafe-inline'; form-action 'none'; base-uri 'none'"

  /// The window's own stylesheet, which follows light and dark mode, and
  /// over which the app's is laid.
  static let stylesheet = """
    :root {
      color-scheme: light dark;
    }
    body {
      font: -apple-system-body;
      line-height: 1.5;
      margin: 20px 24px;
    }
    a {
      color: LinkText;
    }
    img {
      max-width: 100%;
    }
    code, pre {
      font-family: ui-monospace, monospace;
    }
    pre {
      overflow-x: auto;
    }
    table {
      border-collapse: collapse;
    }
    th, td {
      border: 1px solid color-mix(in srgb, CanvasText 20%, transparent);
      padding: 4px 8px;
    }
    .refusals {
      color: light-dark(#b3261e, #ff8a80);
    }

    """

  /// A page to show: the window's title and the document.
  struct Page: Equatable, Sendable {
    let title: String
    let html: String
  }

  /// The page for `masthead` and the About files it names, `content`, or
  /// for masthead.yaml's refusals alone when no copy of it could be used. The
  /// heading is its title, and masthead.yaml's refusals come before the
  /// About files'.
  static func page(masthead: Masthead, content: AboutContent?) -> Page {
    let refusals = masthead.refusals + (content?.refusals ?? [])
    return Page(
      title: masthead.heading,
      html: Self.html(title: masthead.heading, body: content?.body, css: content?.css, refusals: refusals))
  }

  /// The page for `title`, the heading: the policy before anything it
  /// governs, then the stylesheets, then each refusal escaped for HTML, then
  /// `body`, which is HTML already. The app's stylesheet cannot end its
  /// style element.
  static func html(title: String, body: String?, css: String?, refusals: [Refusal]) -> String {
    var html = "<!doctype html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n"
    html += "<meta http-equiv=\"Content-Security-Policy\" content=\"\(policy)\">\n"
    html += "<title>\(HTML.escape(title))</title>\n"
    html += "<style>\n\(stylesheet)</style>\n"
    if let css { html += "<style>\n\(contained(css))</style>\n" }
    html += "</head>\n<body>\n"
    if !refusals.isEmpty {
      html += "<ul class=\"refusals\">\n"
      for refusal in refusals { html += "<li>\(HTML.escape(refusal.description))</li>\n" }
      html += "</ul>\n"
    }
    html += body ?? ""
    return html + "</body>\n</html>\n"
  }

  /// `css` with each `</` written `<\/`, which CSS reads the same, so that
  /// nothing in it ends its style element, in any case.
  private static func contained(_ css: String) -> String {
    css.replacingOccurrences(of: "</", with: "<\\/")
  }
}
