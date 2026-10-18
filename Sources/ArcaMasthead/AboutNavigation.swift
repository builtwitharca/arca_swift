import Foundation
import WebKit

/// Which of the About page's navigations the window follows (design.md "The
/// About window"): the page's own load, and a link to a place in the page. A
/// link the user follows to an http, https or mailto address opens in the
/// browser, and every other navigation is cancelled.
enum AboutNavigation {
  enum Decision: Equatable, Sendable {
    /// The page's own load, at its own address.
    case load
    /// A link to a place in the page, which the window follows.
    case follow
    /// The browser opens the address, and the window does not.
    case browse(URL)
    case cancel
  }

  /// The schemes a link opens in the browser, in lower case.
  private static let browsed: Set<String> = ["http", "https", "mailto"]

  /// The decision for a navigation to `url` of `kind`, in the page's main
  /// frame or another, `loading` while the page's own load is yet to come.
  static func decide(_ url: URL?, kind: WKNavigationType, mainFrame: Bool, loading: Bool) -> Decision {
    guard let url, mainFrame else { return .cancel }
    if loading { return url == AboutDocument.base ? .load : .cancel }
    guard kind == .linkActivated else { return .cancel }
    if isInPage(url) { return .follow }
    return browsed.contains(url.scheme?.lowercased() ?? "") ? .browse(url) : .cancel
  }

  /// Whether `url` is a place in the page itself: its own address, with a
  /// fragment.
  private static func isInPage(_ url: URL) -> Bool {
    guard url.fragment != nil, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return false
    }
    parts.fragment = nil
    return parts.url == AboutDocument.base
  }
}
