import ArcaCore
import Foundation
import WebKit

/// The About window's page in WebKit (design.md "The About window"): its
/// JavaScript off, nothing kept between opens, and the app's images served
/// at the page's own address.
@MainActor
enum AboutPage {
  /// The settings the window's page has. `report` gets the refusals of each
  /// image the page asks for and cannot have.
  static func configuration(
    images: AboutImages, report: @escaping @MainActor ([Refusal]) -> Void
  ) -> WebPage.Configuration {
    guard let scheme = URLScheme(AboutDocument.scheme) else {
      fatalError("WebKit takes \(AboutDocument.scheme): for its own")
    }
    var configuration = WebPage.Configuration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultNavigationPreferences.allowsContentJavaScript = false
    configuration.urlSchemeHandlers[scheme] = AboutImageHandler(images: images, report: report)
    return configuration
  }

  /// Loads `html` into `page` at the page's own address, and watches the
  /// load, since WebKit's own report of it is the sequence it returns.
  static func load(_ html: String, in page: WebPage, log: @escaping @MainActor (String) -> Void) {
    Task { @MainActor in
      await watch(page.load(html: html, baseURL: AboutDocument.base), log: log)
    }
  }

  /// Tells `log` when `events`, a page's own load, fails or stops before it
  /// finishes. A load that a navigator cancels sends neither: WebKit leaves
  /// its sequence open (measured in WP-03's green, slot 33), and the
  /// window's navigator never cancels the page's own load.
  static func watch<Events: AsyncSequence>(
    _ events: Events, log: @MainActor (String) -> Void
  ) async where Events.Element == WebPage.NavigationEvent {
    do {
      for try await event in events where event == .finished {
        return
      }
      log("The About page stopped before it finished loading")
    } catch {
      log("The About page did not load: \(error)")
    }
  }
}

/// The About window's navigation rules (AboutNavigation), applied to
/// WebKit's navigations.
struct AboutNavigator: WebPage.NavigationDeciding {
  /// Opens an address in the browser.
  private let browse: @MainActor (URL) -> Void
  /// Whether the page's own load is yet to come.
  private var loading = true

  init(browse: @escaping @MainActor (URL) -> Void) {
    self.browse = browse
  }

  @MainActor
  mutating func decidePolicy(
    for action: WebPage.NavigationAction, preferences: inout WebPage.NavigationPreferences
  ) async -> WKNavigationActionPolicy {
    // A navigation with no target frame opens a window, which counts as the
    // main frame's.
    let decision = AboutNavigation.decide(
      action.request.url, kind: action.navigationType, mainFrame: action.target?.isMainFrame ?? true,
      loading: loading)
    switch decision {
    case .load:
      loading = false
      return .allow
    case .follow:
      return .allow
    case .browse(let url):
      browse(url)
      return .cancel
    case .cancel:
      return .cancel
    }
  }
}

/// Serves the images an About body names (AboutImages) at the page's own
/// address, and reports each refusal. The file is read off the thread WebKit
/// asks on.
struct AboutImageHandler: URLSchemeHandler {
  let images: AboutImages
  let report: @MainActor ([Refusal]) -> Void

  func reply(for request: URLRequest) -> AsyncThrowingStream<URLSchemeTaskResult, any Error> {
    guard let url = request.url else {
      return AsyncThrowingStream { $0.finish(throwing: URLError(.badURL)) }
    }
    let images = self.images
    let report = self.report
    return AsyncThrowingStream { stream in
      let reading = Task {
        let found = images.image(url)
        if !found.refusals.isEmpty { await report(found.refusals) }
        guard let image = found.value else {
          stream.finish(throwing: URLError(.fileDoesNotExist))
          return
        }
        let response = URLResponse(
          url: url, mimeType: image.type, expectedContentLength: image.data.count, textEncodingName: nil)
        stream.yield(.response(response))
        stream.yield(.data(image.data))
        stream.finish()
      }
      stream.onTermination = { _ in reading.cancel() }
    }
  }
}
