import AppKit
import ArcaCore
import Foundation
import WebKit

/// The row at the top of an app's menu (design.md "The row"): a menu item
/// with the heading in bold, the subheading under it, and the app's icon,
/// read from masthead.yaml each time the menu opens. Choosing it opens the
/// About window. The app makes one and puts it at the top of its menu, which
/// keeps it, and does nothing more.
@MainActor
public final class MastheadRow: NSMenuItem {
  /// The size the app's icon is drawn at in the row.
  static let iconSize = NSSize(width: 32, height: 32)

  private let folder: String
  private let bundle: Bundle
  private let info: [String: Any]
  private let owned: Set<String>
  private let value: @MainActor (String) -> String?
  private let log: @MainActor (String) -> Void
  private let icon: @MainActor () -> NSImage?
  /// masthead.yaml's refusals, and the About page's, each logged once.
  private var rowLog = RefusalLog()
  private var pageLog = RefusalLog()
  private let window = AboutWindow()
  /// Shows a page: in the About window, unless a test looks at it instead.
  var present: @MainActor (AboutDocument.Page) -> Void = { _ in }

  /// The row for the app named `app`, whose config folder is found from
  /// `environment` as `${XDG_CONFIG_HOME:-$HOME/.config}/<app>`, and whose
  /// bundle holds its default masthead.yaml and About files. `owned` names
  /// the values the app gives, and `value` is asked for each of them at every
  /// open, nil meaning not yet. `log` gets each refusal once, when it first
  /// appears.
  public convenience init(
    app: String, environment: [String: String] = ProcessInfo.processInfo.environment, bundle: Bundle = .main,
    owned: Set<String> = [], value: @escaping @MainActor (String) -> String? = { _ in nil },
    log: @escaping @MainActor (String) -> Void
  ) {
    self.init(
      app: app, environment: environment, bundle: bundle, owned: owned, value: value, log: log,
      icon: { NSApplication.shared.applicationIconImage })
  }

  /// The same, with `icon` asked for the app's icon at each read.
  convenience init(
    app: String, environment: [String: String], bundle: Bundle, owned: Set<String>,
    value: @escaping @MainActor (String) -> String?, log: @escaping @MainActor (String) -> Void,
    icon: @escaping @MainActor () -> NSImage?
  ) {
    self.init(
      folder: ConfigFolder.path(app: app, environment: environment, home: NSHomeDirectory()), bundle: bundle,
      info: bundle.infoDictionary ?? [:], owned: owned, value: value, log: log, icon: icon)
  }

  /// The row over `folder` and `bundle`, with `info` as the bundle's
  /// Info.plist, and `icon` asked for the app's icon at each read.
  init(
    folder: String, bundle: Bundle, info: [String: Any], owned: Set<String> = [],
    value: @escaping @MainActor (String) -> String? = { _ in nil }, log: @escaping @MainActor (String) -> Void,
    icon: @escaping @MainActor () -> NSImage?
  ) {
    self.folder = folder
    self.bundle = bundle
    self.info = info
    self.owned = owned
    self.value = value
    self.log = log
    self.icon = icon
    super.init(title: "", action: nil, keyEquivalent: "")
    present = { [weak self] page in self?.show(page) }
    target = self
    action = #selector(showAbout(_:))
    NotificationCenter.default.addObserver(
      self, selector: #selector(menuOpened(_:)), name: NSMenu.didBeginTrackingNotification, object: nil)
    read()
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError("A MastheadRow is made in code, not read from a nib")
  }

  /// Sets `item` to show `masthead`: the heading as its title, in bold, the
  /// subheading as its subtitle, or none when it is hidden, and `icon` at the
  /// row's size as its image, or none when masthead.yaml's icon is none. The
  /// app's own icon is left as it is.
  static func apply(_ masthead: Masthead, to item: NSMenuItem, icon: NSImage?) {
    let font = NSFont.boldSystemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize)
    item.title = masthead.heading
    item.attributedTitle = NSAttributedString(string: masthead.heading, attributes: [.font: font])
    item.subtitle = masthead.subheading
    item.image = masthead.icon == .app ? icon.map(sized) : nil
    item.isEnabled = true
  }

  /// A copy of `image` at the row's size.
  private static func sized(_ image: NSImage) -> NSImage {
    guard let copy = image.copy() as? NSImage else {
      fatalError("NSImage made a copy that is not an NSImage")
    }
    copy.size = iconSize
    return copy
  }

  /// The masthead as masthead.yaml has it now, shown in the row, with each
  /// new refusal logged, and the values the app gave for it.
  @discardableResult
  private func read() -> (masthead: Masthead, values: MastheadValues) {
    let values = MastheadValues(bundle: info, owned: owned) { self.value($0) }
    let masthead = Masthead.load(folder: folder, bundle: bundle, values: values)
    for line in rowLog.read(masthead.refusals) { log(line) }
    Self.apply(masthead, to: self, icon: icon())
    return (masthead, values)
  }

  /// Reads masthead.yaml again as the row's own menu opens.
  @objc private func menuOpened(_ notification: Notification) {
    guard let opened = notification.object as? NSMenu, opened === menu else { return }
    read()
  }

  /// Opens the About window, reading masthead.yaml and the About files
  /// again, with each new refusal of theirs logged.
  @objc private func showAbout(_ sender: Any?) {
    let (masthead, values) = read()
    let content = masthead.about.map { AboutContent.load($0, folder: folder, bundle: bundle, values: values) }
    for line in pageLog.read(content?.refusals ?? []) { log(line) }
    present(AboutDocument.page(masthead: masthead, content: content))
  }

  /// Shows `page` in the About window, its images served from the app's
  /// folder and bundle, and a link opened in the browser.
  private func show(_ page: AboutDocument.Page) {
    let report: @MainActor ([Refusal]) -> Void = { [weak self] in self?.logged($0) }
    let browse: @MainActor (URL) -> Void = { [weak self] url in
      if !NSWorkspace.shared.open(url) { self?.log("The browser could not open \(url.absoluteString)") }
    }
    let configuration = AboutPage.configuration(images: AboutImages(folder: folder, bundle: bundle), report: report)
    let webPage = WebPage(configuration: configuration, navigationDecider: AboutNavigator(browse: browse))
    AboutPage.load(page.html, in: webPage, log: log)
    window.show(webPage, title: page.title)
  }

  /// Logs each of `refusals`, the page's images', that is new to this open.
  func logged(_ refusals: [Refusal]) {
    for line in pageLog.add(refusals) { log(line) }
  }
}
