import Foundation
import Testing
import WebKit

@testable import ArcaMasthead

/// Which of the About page's navigations the window follows (design.md "The
/// About window"), as each is decided before WebKit makes it.
/// Acceptance test AT-03.3, in ST0001's acceptance.md.
@Suite("About navigation")
struct AboutNavigationTests {
  /// A navigation, as the decision sees it.
  struct Case: Sendable, CustomTestStringConvertible {
    let what: String
    let url: String?
    let kind: WKNavigationType
    var mainFrame = true
    var loading = false

    var testDescription: String { what }

    func decision() -> AboutNavigation.Decision {
      AboutNavigation.decide(url.flatMap(URL.init(string:)), kind: kind, mainFrame: mainFrame, loading: loading)
    }
  }

  @Test("the page's own load, in the main frame at the page's own address, is the window's")
  func load() {
    let navigation = Case(what: "the page's own load", url: "arca-about://page/", kind: .other, loading: true)
    #expect(navigation.decision() == .load)
  }

  @Test("a link to a place in the page is followed")
  func followed() {
    let navigation = Case(what: "a link to a place in the page", url: "arca-about://page/#notes", kind: .linkActivated)
    #expect(navigation.decision() == .follow)
  }

  @Test(
    "a link the user follows to an http, https or mailto address opens in the browser, not in the window",
    arguments: [
      Case(what: "an https link", url: "https://example.com/notes", kind: .linkActivated),
      Case(what: "an http link", url: "http://example.com/", kind: .linkActivated),
      Case(what: "a mailto link", url: "mailto:ada@example.com", kind: .linkActivated),
      Case(what: "a link whose scheme is in capitals", url: "HTTPS://example.com/", kind: .linkActivated),
      Case(what: "a link to a place in another page", url: "https://example.com/#notes", kind: .linkActivated),
    ])
  func browsed(navigation: Case) throws {
    let url = try #require(navigation.url.flatMap(URL.init(string:)))
    #expect(navigation.decision() == .browse(url))
  }

  @Test(
    "every other navigation is cancelled",
    arguments: [
      Case(what: "a second load of the page", url: "arca-about://page/", kind: .other),
      Case(
        what: "a load in a frame while the page loads", url: "arca-about://page/", kind: .other, mainFrame: false,
        loading: true),
      Case(what: "an https address while the page loads", url: "https://example.com/", kind: .other, loading: true),
      Case(what: "a reload", url: "arca-about://page/", kind: .reload),
      Case(what: "a reload of a place in the page", url: "arca-about://page/#notes", kind: .reload),
      Case(what: "back or forward to a place in the page", url: "arca-about://page/#notes", kind: .backForward),
      Case(what: "a refresh to a place in the page", url: "arca-about://page/#notes", kind: .other),
      Case(
        what: "a frame's link to a place in the page", url: "arca-about://page/#notes", kind: .linkActivated,
        mainFrame: false),
      Case(what: "a form", url: "https://example.com/form", kind: .formSubmitted),
      Case(what: "a form sent again", url: "https://example.com/form", kind: .formResubmitted),
      Case(what: "back or forward", url: "https://example.com/", kind: .backForward),
      Case(what: "a refresh", url: "https://example.com/", kind: .other),
      Case(what: "a frame", url: "https://example.com/", kind: .other, mainFrame: false),
      Case(what: "a link in a frame", url: "https://example.com/", kind: .linkActivated, mainFrame: false),
      Case(what: "a link to a file", url: "file:///etc/hosts", kind: .linkActivated),
      Case(
        what: "a link to another of the page's addresses", url: "arca-about://page/notes.html", kind: .linkActivated),
      Case(what: "a javascript: link", url: "javascript:void(0)", kind: .linkActivated),
      Case(what: "a data: link", url: "data:text/html,here", kind: .linkActivated),
      Case(what: "a link to another scheme", url: "ftp://example.com/", kind: .linkActivated),
      Case(what: "a navigation with no address", url: nil, kind: .other),
    ])
  func cancelled(navigation: Case) {
    #expect(navigation.decision() == .cancel)
  }
}
