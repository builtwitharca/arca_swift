import AppKit
import ArcaCore
import ArcaTestSupport
import Foundation
import Synchronization
import Testing
import WebKit

@testable import ArcaMasthead

/// Answers each request for a probe: address with an empty reply, and keeps
/// each address asked for.
final class Probe: URLSchemeHandler, Sendable {
  private let asked = Mutex<[URL]>([])
  /// Each address, as it is asked for.
  let requests: AsyncStream<URL>
  private let continuation: AsyncStream<URL>.Continuation

  init() {
    let stream = AsyncStream.makeStream(of: URL.self)
    requests = stream.stream
    continuation = stream.continuation
  }

  /// Each address asked for so far.
  var addresses: [URL] {
    asked.withLock { $0 }
  }

  func reply(for request: URLRequest) -> AsyncThrowingStream<URLSchemeTaskResult, any Error> {
    let url = request.url ?? URL(fileURLWithPath: "/")
    asked.withLock { $0.append(url) }
    continuation.yield(url)
    let response = URLResponse(url: url, mimeType: "text/plain", expectedContentLength: 0, textEncodingName: nil)
    return AsyncThrowingStream { stream in
      stream.yield(.response(response))
      stream.finish()
    }
  }
}

/// What a page's navigator decided, and what it sent to the browser.
enum Decided: Sendable, Equatable {
  case asked(URL?, WKNavigationType, WKNavigationActionPolicy)
  case browsed(URL)
}

/// WebKit's own navigation rules, which follow every navigation.
struct Defaults: WebPage.NavigationDeciding {}

/// A navigator, keeping what it decided.
struct Recording<Navigator: WebPage.NavigationDeciding>: WebPage.NavigationDeciding {
  var navigator: Navigator
  let decisions: Recorder<Decided>

  @MainActor
  mutating func decidePolicy(
    for action: WebPage.NavigationAction, preferences: inout WebPage.NavigationPreferences
  ) async -> WKNavigationActionPolicy {
    let policy = await navigator.decidePolicy(for: action, preferences: &preferences)
    decisions.record(.asked(action.request.url, action.navigationType, policy))
    return policy
  }
}

/// The page's own load ended before WebKit finished it.
struct Unfinished: Error {}

/// The About page in WebKit itself (design.md "The About window"): under the
/// window's own settings, the page is held to its policy and its navigation
/// rules. Each rule's control loads the same page under WebKit's own
/// settings and sees the request made or the script run, so the probe is
/// seen to work.
/// Acceptance test AT-03.5, in ST0001's acceptance.md.
@MainActor
@Suite("About page in WebKit", .serialized, .timeLimit(.minutes(1)))
struct AboutPageTests {
  /// An image, a stylesheet and a frame, each at a probe: address.
  static let loads =
    "<img src=\"probe://x/a.png\"><link rel=\"stylesheet\" href=\"probe://x/b.css\">"
    + "<iframe src=\"probe://x/c.html\"></iframe>"
  static let loaded = ["probe://x/a.png", "probe://x/b.css", "probe://x/c.html"]
  static let refresh = "<meta http-equiv=\"refresh\" content=\"0;url=probe://x/refresh\"><p id=\"marker\">here</p>"
  static let marker = "<p id=\"marker\">here</p>"
  static let mail = "mailto:ada@example.com"
  /// The images of an app with none.
  static let noImages = AboutImages(folder: "/home/ada/.config/menuz", bundle: .main)

  /// A page under WebKit's own settings, keeping nothing on disk, with the
  /// probe, for the controls.
  static func plain(_ probe: Probe, decisions: Recorder<Decided> = Recorder()) throws -> WebPage {
    let scheme = try #require(URLScheme("probe"))
    var configuration = WebPage.Configuration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.urlSchemeHandlers[scheme] = probe
    return WebPage(
      configuration: configuration, navigationDecider: Recording(navigator: Defaults(), decisions: decisions))
  }

  /// A page under the window's own settings and navigator, with the probe
  /// beside the app's images.
  static func window(
    _ probe: Probe, images: AboutImages = AboutPageTests.noImages, decisions: Recorder<Decided> = Recorder(),
    report: @escaping @MainActor ([Refusal]) -> Void = { _ in }
  ) throws -> WebPage {
    let scheme = try #require(URLScheme("probe"))
    var configuration = AboutPage.configuration(images: images, report: report)
    configuration.urlSchemeHandlers[scheme] = probe
    let navigator = AboutNavigator(browse: { decisions.record(.browsed($0)) })
    return WebPage(
      configuration: configuration, navigationDecider: Recording(navigator: navigator, decisions: decisions))
  }

  /// The page for `body` under the window's own document.
  static func document(_ body: String) -> String {
    AboutDocument.html(title: "menuz", body: body, css: nil, refusals: [])
  }

  /// Loads `html` at the page's own address, and returns once WebKit has
  /// finished it; a load that ends before it finishes throws.
  static func load(_ html: String, in page: WebPage) async throws {
    for try await event in page.load(html: html, baseURL: AboutDocument.base) where event == .finished {
      return
    }
    throw Unfinished()
  }

  /// What `script` returns, read by the test's own script world, which the
  /// page's policy and its JavaScript setting do not cover.
  static func value(_ script: String, in page: WebPage) async throws -> Any? {
    try await page.callJavaScript(script, contentWorld: .defaultClient)
  }

  /// The text of the element `id` names, or nil when the page has none.
  static func text(of id: String, in page: WebPage) async throws -> String? {
    try await value("return document.getElementById('\(id)')?.textContent ?? null", in: page) as? String
  }

  /// The first of `events` that `wanted` takes, or nil when none comes within
  /// `limit`, so a page that never does the thing fails its test.
  static func first<Event: Sendable, Value: Sendable>(
    _ events: AsyncStream<Event>, within limit: Duration = .seconds(20),
    _ wanted: @escaping @Sendable (Event) -> Value?
  ) async -> Value? {
    await withTaskGroup(of: Value?.self) { group in
      group.addTask {
        for await event in events {
          if let value = wanted(event) { return value }
        }
        return nil
      }
      group.addTask {
        try? await Task.sleep(for: limit)
        return nil
      }
      let value = await group.next() ?? nil
      group.cancelAll()
      return value
    }
  }

  /// The policy decided for `address`, as the navigator decides it.
  static func policy(
    for address: String, in decisions: Recorder<Decided>, kind: WKNavigationType? = nil
  ) async -> WKNavigationActionPolicy? {
    await first(decisions.stream) { decided -> WKNavigationActionPolicy? in
      guard case .asked(let url, let asked, let policy) = decided, url?.absoluteString == address else { return nil }
      if let kind, kind != asked { return nil }
      return policy
    }
  }

  /// A one-pixel PNG.
  static func png() throws -> Data {
    let image = try #require(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    return try #require(image.representation(using: .png, properties: [:]))
  }

  @Test("the control: under WebKit's own settings, an image, a stylesheet and a frame are each asked of the probe")
  func controlLoads() async throws {
    let probe = Probe()
    let page = try Self.plain(probe)
    try await Self.load(Self.loads, in: page)
    #expect(Set(probe.addresses.map(\.absoluteString)) == Set(Self.loaded))
  }

  @Test("the control: under WebKit's own settings, the page's script runs")
  func controlScript() async throws {
    let page = try Self.plain(Probe())
    try await Self.load("<title>here</title><script>document.title = 'ran'</script>", in: page)
    #expect(page.title == "ran")
  }

  @Test("the control: under WebKit's own settings, a refresh to another address is made")
  func controlRefresh() async throws {
    let probe = Probe()
    let page = try Self.plain(probe)
    try await Self.load(Self.refresh, in: page)
    let made = await Self.first(probe.requests) { $0.absoluteString == "probe://x/refresh" ? true : nil }
    #expect(made == true)
  }

  @Test("the control: a script's click on a link is, as WebKit reports it, a link the user follows")
  func controlClick() async throws {
    let decisions = Recorder<Decided>()
    let page = try Self.plain(Probe(), decisions: decisions)
    try await Self.load("<a id=\"link\" href=\"probe://x/link\">link</a>", in: page)
    _ = try await Self.value("document.getElementById('link').click()", in: page)
    let kind = await Self.first(decisions.stream) { decided -> WKNavigationType? in
      guard case .asked(let url, let kind, _) = decided, url?.absoluteString == "probe://x/link" else { return nil }
      return kind
    }
    #expect(kind == .linkActivated)
  }

  @Test("under the window's settings with no document, an image and a stylesheet are asked, and a frame is cancelled")
  func noDocument() async throws {
    let probe = Probe()
    let decisions = Recorder<Decided>()
    let page = try Self.window(probe, decisions: decisions)
    try await Self.load(Self.loads, in: page)
    let frame = await Self.policy(for: "probe://x/c.html", in: decisions)
    #expect(frame == .cancel)
    #expect(Set(probe.addresses.map(\.absoluteString)) == ["probe://x/a.png", "probe://x/b.css"])
  }

  @Test("under the window's settings the page shows, and its image, stylesheet and frame make no request")
  func noLoads() async throws {
    let probe = Probe()
    let page = try Self.window(probe)
    try await Self.load(Self.document(Self.marker + Self.loads), in: page)
    let marker = try await Self.text(of: "marker", in: page)
    #expect(marker == "here")
    let elements = try await Self.value("return document.querySelectorAll('img, link, iframe').length", in: page)
    #expect(elements as? Int == 3)
    #expect(probe.addresses.isEmpty)
  }

  @Test("under the window's settings the window's stylesheet applies and follows light and dark mode")
  func colourScheme() async throws {
    let page = try Self.window(Probe())
    try await Self.load(Self.document(Self.marker), in: page)
    let scheme = try await Self.value("return getComputedStyle(document.documentElement).colorScheme", in: page)
    #expect(scheme as? String == "light dark")
  }

  @Test("under the window's settings the page's script does not run, with the policy or without it")
  func noScript() async throws {
    let page = try Self.window(Probe())
    try await Self.load("<title>here</title><script>document.title = 'ran'</script>", in: page)
    #expect(page.title == "here")
    let wrapped = try Self.window(Probe())
    let script = Self.marker + "<script>document.getElementById('marker').textContent = 'ran'</script>"
    try await Self.load(Self.document(script), in: wrapped)
    let marker = try await Self.text(of: "marker", in: wrapped)
    #expect(marker == "here")
  }

  @Test("under the window's settings a refresh to another address is cancelled, and the page stays")
  func noRefresh() async throws {
    let probe = Probe()
    let decisions = Recorder<Decided>()
    let page = try Self.window(probe, decisions: decisions)
    try await Self.load(Self.document(Self.refresh), in: page)
    let policy = await Self.policy(for: "probe://x/refresh", in: decisions)
    #expect(policy == .cancel)
    let marker = try await Self.text(of: "marker", in: page)
    #expect(marker == "here")
    #expect(probe.addresses.isEmpty)
  }

  @Test("under the window's settings a reload is cancelled, and the page stays")
  func noReload() async throws {
    let decisions = Recorder<Decided>()
    let page = try Self.window(Probe(), decisions: decisions)
    try await Self.load(Self.document(Self.marker), in: page)
    page.reload()
    let policy = await Self.policy(for: AboutDocument.base.absoluteString, in: decisions, kind: .reload)
    #expect(policy == .cancel)
    let marker = try await Self.text(of: "marker", in: page)
    #expect(marker == "here")
  }

  @Test("under the window's settings a link the user follows to a mailto address goes to the browser instead")
  func link() async throws {
    let decisions = Recorder<Decided>()
    let page = try Self.window(Probe(), decisions: decisions)
    let body = Self.marker + "<a id=\"mail\" href=\"\(Self.mail)\">mail</a>"
    try await Self.load(Self.document(body), in: page)
    _ = try await Self.value("document.getElementById('mail').click()", in: page)
    let policy = await Self.policy(for: Self.mail, in: decisions)
    #expect(policy == .cancel)
    let mail = try #require(URL(string: Self.mail))
    #expect(decisions.all.contains(.browsed(mail)))
    let marker = try await Self.text(of: "marker", in: page)
    #expect(marker == "here")
  }

  @Test("under the window's settings a link that would open a window goes to the browser too")
  func newWindow() async throws {
    let decisions = Recorder<Decided>()
    let page = try Self.window(Probe(), decisions: decisions)
    let body = "<a id=\"mail\" target=\"_blank\" href=\"\(Self.mail)\">mail</a>"
    try await Self.load(Self.document(body), in: page)
    _ = try await Self.value("document.getElementById('mail').click()", in: page)
    let browsed = await Self.first(decisions.stream) { decided -> URL? in
      guard case .browsed(let url) = decided else { return nil }
      return url
    }
    #expect(browsed?.absoluteString == Self.mail)
  }

  @Test("the body's images are served from the config folder with their types, and one it cannot have is reported")
  func images() async throws {
    try await Scratch.folder { scratch in
      let app = try Scratch.app(in: scratch)
      try Self.png().write(to: URL(fileURLWithPath: "\(app.folder)/logo.png"))
      _ = try Scratch.write(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"3\" height=\"3\"></svg>\n", to: "mark.svg", in: app.folder)
      let bundle = try #require(Bundle(path: app.bundle))
      let reported = Recorder<Refusal>()
      let report: @MainActor ([Refusal]) -> Void = { refusals in
        for refusal in refusals { reported.record(refusal) }
      }
      let page = try Self.window(Probe(), images: AboutImages(folder: app.folder, bundle: bundle), report: report)
      let body = "<img id=\"logo\" src=\"logo.png\"><img id=\"mark\" src=\"mark.svg\"><img src=\"gone.png\">"
      try await Self.load(Self.document(body), in: page)
      let logo = try await Self.value("return document.getElementById('logo').naturalWidth", in: page)
      #expect(logo as? Int == 1)
      let mark = try await Self.value("return document.getElementById('mark').naturalWidth", in: page)
      #expect(mark as? Int == 3)
      let refusal = await Self.first(reported.stream) { $0 }
      let why = "is not there, and the app's bundle has none"
      #expect(refusal == Refusal(file: "\(app.folder)/gone.png", key: nil, value: nil, why: why))
    }
  }

  @Test("a page's own load that fails or stops early is told to the log, and one that finishes is not")
  func watched() async {
    let lines = Recorder<String>()
    let log: @MainActor (String) -> Void = { lines.record($0) }
    let finished = AsyncThrowingStream<WebPage.NavigationEvent, any Error> { events in
      events.yield(.committed)
      events.yield(.finished)
      events.finish()
    }
    await AboutPage.watch(finished, log: log)
    #expect(lines.all.isEmpty)
    let stopped = AsyncThrowingStream<WebPage.NavigationEvent, any Error> { events in
      events.yield(.committed)
      events.finish()
    }
    await AboutPage.watch(stopped, log: log)
    #expect(lines.all == ["The About page stopped before it finished loading"])
    let failed = AsyncThrowingStream<WebPage.NavigationEvent, any Error> { events in
      events.finish(throwing: URLError(.cannotDecodeContentData))
    }
    await AboutPage.watch(failed, log: log)
    #expect(lines.all.count == 2)
    #expect(lines.all.last?.hasPrefix("The About page did not load: ") == true)
  }
}
