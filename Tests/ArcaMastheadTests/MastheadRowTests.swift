import AppKit
import ArcaCore
import ArcaTestSupport
import Foundation
import Testing

@testable import ArcaMasthead

/// The row at the top of the app's menu (design.md "The row"): when it reads
/// masthead.yaml again, and what choosing it shows.
/// Acceptance test AT-03.1, in ST0001's acceptance.md.
@MainActor
@Suite("Masthead row")
struct MastheadRowTests {
  static let masthead = Masthead(
    heading: "menuz 0.3.0", subheading: "56e0c90 · dev", icon: .app, about: Menuz.about, refusals: [])
  static let bundled = "heading: \"{name} {version}\"\nsubheading: \"{commit} · {kind}\"\nabout:\n  body: about.md\n"
  static let refusedIcon = "heading: menuz\nicon: logo\nabout:\n  body: about.md\n"
  /// The size the row draws the app's icon at.
  static let rowSize = NSSize(width: 32, height: 32)

  /// A large image standing in for the app's icon.
  static func icon() -> NSImage {
    NSImage(size: NSSize(width: 512, height: 512))
  }

  /// A row over an app in `scratch`, in a menu of its own. The bundle ships
  /// the bundled default and an about.md, and the config folder holds `user`
  /// as its masthead.yaml when there is one.
  static func row(
    _ scratch: String, user: String? = nil, log: @escaping @MainActor (String) -> Void = { _ in },
    value: @escaping @MainActor (String) -> String? = { _ in nil }, owned: Set<String> = []
  ) throws -> (row: MastheadRow, menu: NSMenu, folder: String) {
    let app = try Scratch.app(in: scratch)
    _ = try Scratch.write(Self.bundled, to: "masthead.yaml", in: app.resources)
    _ = try Scratch.write("# {name}\n", to: "about.md", in: app.resources)
    if let user { _ = try Scratch.write(user, to: "masthead.yaml", in: app.folder) }
    let bundle = try #require(Bundle(path: app.bundle))
    let row = MastheadRow(
      folder: app.folder, bundle: bundle, info: Menuz.info, owned: owned, value: value, log: log, icon: { Self.icon() })
    let menu = NSMenu()
    menu.addItem(row)
    return (row, menu, app.folder)
  }

  /// What macOS posts as `menu` opens.
  static func open(_ menu: NSMenu) {
    NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: menu)
  }

  /// Chooses `row` as its menu does: its action, sent to its target.
  static func choose(_ row: MastheadRow) throws {
    let action = try #require(row.action)
    let target = try #require(row.target as? NSObject)
    _ = target.perform(action, with: row)
  }

  @Test("the heading is the item's title, all of it in bold, and the subheading is its subtitle")
  func lines() throws {
    let item = NSMenuItem()
    MastheadRow.apply(Self.masthead, to: item, icon: Self.icon())
    #expect(item.title == "menuz 0.3.0")
    let title = try #require(item.attributedTitle)
    #expect(title.string == "menuz 0.3.0")
    var range = NSRange()
    let whole = NSRange(location: 0, length: title.length)
    let attribute = title.attribute(.font, at: 0, longestEffectiveRange: &range, in: whole)
    let font = try #require(attribute as? NSFont)
    #expect(font.fontDescriptor.symbolicTraits.contains(.bold))
    #expect(range == whole)
    #expect(item.subtitle == "56e0c90 · dev")
  }

  @Test("a hidden subheading leaves the item no subtitle")
  func noSubtitle() {
    let item = NSMenuItem()
    item.subtitle = "56e0c90 · dev"
    let masthead = Masthead(heading: "menuz", subheading: nil, icon: .app, about: Menuz.about, refusals: [])
    MastheadRow.apply(masthead, to: item, icon: Self.icon())
    #expect(item.title == "menuz")
    #expect(item.subtitle == nil)
  }

  @Test("the image is the app's icon at 32 points, the icon itself left as it is, and icon none shows none")
  func image() throws {
    let icon = Self.icon()
    let item = NSMenuItem()
    MastheadRow.apply(Self.masthead, to: item, icon: icon)
    let image = try #require(item.image)
    #expect(image.size == Self.rowSize)
    #expect(image !== icon)
    #expect(icon.size == NSSize(width: 512, height: 512))
    let omitted = Masthead(heading: "menuz", subheading: nil, icon: .omitted, about: Menuz.about, refusals: [])
    MastheadRow.apply(omitted, to: item, icon: icon)
    #expect(item.image == nil)
  }

  @Test("the row is a menu item made from masthead.yaml, enabled, with itself as its target")
  func made() throws {
    try Scratch.folder { scratch in
      let (row, _, _) = try Self.row(scratch)
      #expect(row.title == "menuz 0.3.0")
      #expect(row.subtitle == "56e0c90 · dev")
      #expect(row.image?.size == Self.rowSize)
      #expect(row.isEnabled)
      #expect(row.target === row)
    }
  }

  @Test("the row's config folder is found from the environment, and its values from the bundle's Info.plist")
  func appsOwn() throws {
    try Scratch.folder { scratch in
      let app = try Scratch.app(in: scratch)
      _ = try Scratch.write(Self.bundled, to: "masthead.yaml", in: app.resources)
      let info = try PropertyListSerialization.data(fromPropertyList: Menuz.info, format: .xml, options: 0)
      try info.write(to: URL(fileURLWithPath: "\(app.bundle)/Contents/Info.plist"))
      let user = "heading: \"{name} at {commit}\"\nabout:\n  body: about.md\n"
      _ = try Scratch.write(user, to: "masthead.yaml", in: app.folder)
      let bundle = try #require(Bundle(path: app.bundle))
      let row = MastheadRow(
        app: "menuz", environment: ["XDG_CONFIG_HOME": "\(scratch)/config"], bundle: bundle, owned: [],
        value: { _ in nil }, log: { _ in }, icon: { Self.icon() })
      #expect(row.title == "menuz at 56e0c90")
    }
  }

  @Test("the menu that holds the row keeps it, so with no other hold on it the row still reads again")
  func kept() throws {
    try Scratch.folder { scratch in
      let (_, menu, folder) = try Self.row(scratch)
      _ = try Scratch.write("heading: changed\nabout:\n  body: about.md\n", to: "masthead.yaml", in: folder)
      Self.open(menu)
      let row = try #require(menu.items.first as? MastheadRow)
      #expect(row.title == "changed")
    }
  }

  @Test("masthead.yaml is read again when the row's menu opens, and not when another menu does")
  func readOnOpen() throws {
    try Scratch.folder { scratch in
      let (row, menu, folder) = try Self.row(scratch)
      _ = try Scratch.write("heading: changed\nabout:\n  body: about.md\n", to: "masthead.yaml", in: folder)
      Self.open(NSMenu())
      #expect(row.title == "menuz 0.3.0")
      Self.open(menu)
      #expect(row.title == "changed")
      #expect(row.subtitle == nil)
    }
  }

  @Test("the app is asked for the values it names each time the menu opens")
  func askedOnOpen() throws {
    try Scratch.folder { scratch in
      let asked = Recorder<String>()
      let value: @MainActor (String) -> String? = { name in
        asked.record(name)
        return "0.4.0"
      }
      let (row, menu, _) = try Self.row(scratch, value: value, owned: ["version"])
      #expect(asked.all == ["version"])
      #expect(row.title == "menuz 0.4.0")
      Self.open(menu)
      #expect(asked.all == ["version", "version"])
    }
  }

  @Test("a refusal goes to the log once, when it first appears, and again after it has gone and come back")
  func loggedOnce() throws {
    try Scratch.folder { scratch in
      let logged = Recorder<String>()
      let (row, menu, folder) = try Self.row(scratch, user: Self.refusedIcon, log: { logged.record($0) })
      let user = "\(folder)/masthead.yaml"
      let refusal = Refusal(file: user, key: "icon", value: "logo", why: "is not app or none").description
      #expect(logged.all == [refusal])
      #expect(row.subtitle == refusal)
      Self.open(menu)
      #expect(logged.all == [refusal])
      try FileManager.default.removeItem(atPath: user)
      Self.open(menu)
      #expect(logged.all == [refusal])
      _ = try Scratch.write(Self.refusedIcon, to: "masthead.yaml", in: folder)
      Self.open(menu)
      #expect(logged.all == [refusal, refusal])
    }
  }

  @Test("choosing the row shows its page, read again with the app's values each time, each refusal logged once")
  func chosen() throws {
    try Scratch.folder { scratch in
      let logged = Recorder<String>()
      let asked = Recorder<String>()
      let shown = Recorder<AboutDocument.Page>()
      let value: @MainActor (String) -> String? = { name in
        asked.record(name)
        return "0.4.0"
      }
      let (row, _, folder) = try Self.row(scratch, log: { logged.record($0) }, value: value, owned: ["version"])
      row.present = { shown.record($0) }
      let body = try Scratch.write("# {name} {version}\n\n{nothing}\n", to: "about.md", in: folder)
      let masthead = Masthead(
        heading: "menuz 0.4.0", subheading: "56e0c90 · dev", icon: .app, about: Menuz.about, refusals: [])
      let why = "has {nothing}, which is not a value the app gives: those are {commit}, {kind}, {name} and {version}"
      let token = Refusal(file: body, key: nil, value: nil, why: why)
      let first = AboutContent(body: "<h1>menuz 0.4.0</h1>\n<p>{nothing}</p>\n", css: nil, refusals: [token])
      try Self.choose(row)
      #expect(shown.all == [AboutDocument.page(masthead: masthead, content: first)])
      #expect(logged.all == [token.description])
      _ = try Scratch.write("# changed\n", to: "about.md", in: folder)
      try Self.choose(row)
      let changed = AboutContent(body: "<h1>changed</h1>\n", css: nil, refusals: [])
      #expect(shown.all.last == AboutDocument.page(masthead: masthead, content: changed))
      #expect(logged.all == [token.description])
      _ = try Scratch.write("# {name} {version}\n\n{nothing}\n", to: "about.md", in: folder)
      try Self.choose(row)
      #expect(shown.all.count == 3)
      #expect(logged.all == [token.description, token.description])
      #expect(asked.all == ["version", "version", "version", "version"])
    }
  }

  @Test("an image the page cannot have goes to the log once for each open of the window")
  func imageLogged() throws {
    try Scratch.folder { scratch in
      let logged = Recorder<String>()
      let (row, _, folder) = try Self.row(scratch, log: { logged.record($0) })
      row.present = { _ in }
      let gone = Refusal(
        file: "\(folder)/gone.png", key: nil, value: nil, why: "is not there, and the app's bundle has none")
      try Self.choose(row)
      row.logged([gone])
      row.logged([gone])
      #expect(logged.all == [gone.description])
      try Self.choose(row)
      row.logged([gone])
      #expect(logged.all == [gone.description])
    }
  }
}

/// Which refusals go to the app's log (design.md "The file"): each once,
/// when it first appears, and again only after a whole read without it.
@Suite("Refusal log")
struct RefusalLogTests {
  static let icon = Refusal(
    file: "/home/ada/.config/menuz/masthead.yaml", key: "icon", value: "logo", why: "is not app or none")
  static let body = Refusal(file: "/home/ada/.config/menuz/about.md", key: nil, value: nil, why: "not UTF-8 text")

  @Test("a read's refusals are logged when the read before had none of them, each once, in order")
  func read() {
    var log = RefusalLog()
    #expect(log.read([Self.icon, Self.icon]) == [Self.icon.description])
    #expect(log.read([Self.icon]) == [])
    #expect(log.read([Self.body, Self.icon]) == [Self.body.description])
  }

  @Test("a read's new refusals keep the read's order, not the order of their lines")
  func order() {
    var log = RefusalLog()
    #expect(log.read([Self.icon, Self.body]) == [Self.icon.description, Self.body.description])
  }

  @Test("a refusal that goes for a whole read and comes back is logged again")
  func cameBack() {
    var log = RefusalLog()
    #expect(log.read([Self.icon]) == [Self.icon.description])
    #expect(log.read([]) == [])
    #expect(log.read([Self.icon]) == [Self.icon.description])
  }

  @Test("refusals added to a read are logged unless that read or the one before has had them")
  func added() {
    var log = RefusalLog()
    #expect(log.read([Self.icon]) == [Self.icon.description])
    #expect(log.add([Self.body, Self.body, Self.icon]) == [Self.body.description])
    #expect(log.add([Self.body]) == [])
    #expect(log.read([Self.icon]) == [])
    #expect(log.add([Self.body]) == [])
    #expect(log.read([]) == [])
    #expect(log.read([]) == [])
    #expect(log.add([Self.body]) == [Self.body.description])
  }
}
