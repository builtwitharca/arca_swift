import AppKit
import ArcaTestSupport
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import ArcaMasthead

/// The row's image on macOS 27 and the icon it draws (issue 0003): the row
/// asks for its image to be drawn, and an app can have it take its icon from
/// the bundle's icon file. Each row here is made as an app makes one,
/// through the public init. The app's icon is set to a blue square for each
/// test, and put back after it, so that a row which shows it can be told
/// from one which shows the bundle's red file.
/// AT-e69447a3.1 and AT-e69447a3.2 (STc203646d7444f4f1 acceptance.md) cite
/// this file.
@MainActor
@Suite("Masthead row's image and icon")
struct MastheadRowIconTests {
  /// How far one colour component must stand above the others for a pixel
  /// to read as that colour, whatever colour space it was drawn through.
  static let margin: CGFloat = 0.5
  /// The side of each square icon, in pixels, a size an .icns holds.
  static let iconSide = 128

  /// A square of `color`, as a bitmap.
  static func square(_ color: NSColor) throws -> NSBitmapImageRep {
    let side = iconSide
    let bitmap = try #require(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    color.setFill()
    NSRect(x: 0, y: 0, width: side, height: side).fill()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
  }

  /// An icon file's bytes: a square of `color`, as ImageIO writes an .icns.
  static func icns(_ color: NSColor) throws -> Data {
    let image = try #require(try square(color).cgImage)
    let data = NSMutableData()
    let destination = try #require(
      CGImageDestinationCreateWithData(data as CFMutableData, UTType.icns.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    try #require(CGImageDestinationFinalize(destination))
    return data as Data
  }

  /// The colour at the centre of `image`, drawn at the row's size.
  static func centre(of image: NSImage) throws -> NSColor {
    let side = Int(MastheadRowTests.rowSize.width)
    let bitmap = try #require(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    return try #require(bitmap.colorAt(x: side / 2, y: side / 2)?.usingColorSpace(.deviceRGB))
  }

  /// Whether `color` reads as red, or as blue.
  static func isRed(_ color: NSColor) -> Bool {
    color.redComponent > color.greenComponent + margin && color.redComponent > color.blueComponent + margin
  }

  static func isBlue(_ color: NSColor) -> Bool {
    color.blueComponent > color.redComponent + margin && color.blueComponent > color.greenComponent + margin
  }

  /// Runs `body` with the app's icon a blue square, then puts the icon back.
  static func withBlueAppIcon(_ body: () throws -> Void) throws {
    let app = NSApplication.shared
    let before = app.applicationIconImage
    let blue = NSImage(size: NSSize(width: iconSide, height: iconSide))
    blue.addRepresentation(try square(.blue))
    app.applicationIconImage = blue
    defer { app.applicationIconImage = before }
    try body()
  }

  /// A row made through the public init over an app in `scratch`: its
  /// Info.plist is Menuz's, with `iconFile` as its CFBundleIconFile when
  /// there is one, and its Resources hold `icon` as AppIcon.icns when there
  /// is one. With no `appIcon`, the init is called without one.
  static func appRow(
    _ scratch: String, iconFile: String?, icon: Data?, appIcon: MastheadRow.AppIcon?,
    log: @escaping @MainActor (String) -> Void
  ) throws -> MastheadRow {
    let app = try Scratch.app(in: scratch)
    _ = try Scratch.write(MastheadRowTests.bundled, to: "masthead.yaml", in: app.resources)
    _ = try Scratch.write("# {name}\n", to: "about.md", in: app.resources)
    var info = Menuz.info
    if let iconFile { info["CFBundleIconFile"] = iconFile }
    let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try plist.write(to: URL(fileURLWithPath: "\(app.bundle)/Contents/Info.plist"))
    if let icon { try icon.write(to: URL(fileURLWithPath: "\(app.resources)/AppIcon.icns")) }
    let bundle = try #require(Bundle(path: app.bundle))
    let environment = ["XDG_CONFIG_HOME": "\(scratch)/config"]
    guard let appIcon else { return MastheadRow(app: "menuz", environment: environment, bundle: bundle, log: log) }
    return MastheadRow(app: "menuz", environment: environment, bundle: bundle, appIcon: appIcon, log: log)
  }

  /// The lines `log` was told that are about the row's icon.
  static func iconLines(_ lines: [String]) -> [String] {
    lines.filter { $0.hasSuffix(", so the row shows the app's icon") }
  }

  /// macOS 27 draws a menu item's image only where the item asks for it. An
  /// older macOS has no such setting and draws the image anyway, so there is
  /// nothing to ask there. Moved from Menuz's drawsImage test (Utilz
  /// MenuzTests/IdentityRowTests.swift).
  @Test("the row asks macOS to draw its image, where its items have the setter, as macOS 27's do")
  func asksForImage() throws {
    try Scratch.folder { scratch in
      let (row, _, _) = try MastheadRowTests.row(scratch)
      guard row.responds(to: NSSelectorFromString("setPreferredImageVisibility:")) else { return }
      let visibility = row.value(forKey: "preferredImageVisibility") as? Int
      #expect(
        visibility == 1,
        "the row's preferredImageVisibility is \(visibility.map(String.init) ?? "unreadable"), not 1 (visible)")
    }
  }

  @Test("with appIcon .bundleFile, the row shows the icon file that the bundle's CFBundleIconFile names")
  func showsTheBundleFile() throws {
    try Self.withBlueAppIcon {
      try Scratch.folder { scratch in
        let logged = Recorder<String>()
        let row = try Self.appRow(
          scratch, iconFile: "AppIcon", icon: try Self.icns(.red), appIcon: .bundleFile, log: { logged.record($0) })
        let image = try #require(row.image, "the row has no image")
        #expect(image.size == MastheadRowTests.rowSize)
        let centre = try Self.centre(of: image)
        #expect(Self.isRed(centre), "the row's image is \(centre), not the bundle's red icon file")
        #expect(Self.iconLines(logged.all).isEmpty, "the log was told \(logged.all)")
      }
    }
  }

  @Test("a bundle naming no icon file, missing it, or holding one that is not an image: the app's icon, and why, once")
  func fallsBackAndSaysWhy() throws {
    let cases: [(name: String, iconFile: String?, icon: Data?, says: String)] = [
      ("no key", nil, nil, "The bundle names no icon file (CFBundleIconFile), so the row shows the app's icon"),
      ("no file", "AppIcon", nil, "The bundle has no AppIcon.icns, so the row shows the app's icon"),
      (
        "not an image", "AppIcon", Data("not an icon".utf8),
        "/AppIcon.icns is not an image, so the row shows the app's icon"
      ),
    ]
    try Self.withBlueAppIcon {
      for each in cases {
        try Scratch.folder { scratch in
          let logged = Recorder<String>()
          let row = try Self.appRow(
            scratch, iconFile: each.iconFile, icon: each.icon, appIcon: .bundleFile, log: { logged.record($0) })
          let menu = NSMenu()
          menu.addItem(row)
          MastheadRowTests.open(menu)
          let said = Self.iconLines(logged.all)
          #expect(said.count == 1, "\(each.name): the log was told \(logged.all)")
          #expect(said.first?.hasSuffix(each.says) == true, "\(each.name): the log was told \(logged.all)")
          let image = try #require(row.image, "\(each.name): the row has no image")
          let centre = try Self.centre(of: image)
          #expect(Self.isBlue(centre), "\(each.name): the row's image is \(centre), not the app's blue icon")
        }
      }
    }
  }

  @Test("by default the row shows the app's icon, as it did before appIcon, and says nothing of the bundle's file")
  func theDefaultIsTheAppsIcon() throws {
    try Self.withBlueAppIcon {
      try Scratch.folder { scratch in
        let logged = Recorder<String>()
        let row = try Self.appRow(
          scratch, iconFile: "AppIcon", icon: try Self.icns(.red), appIcon: nil, log: { logged.record($0) })
        let image = try #require(row.image, "the row has no image")
        let centre = try Self.centre(of: image)
        #expect(Self.isBlue(centre), "the row's image is \(centre), not the app's blue icon")
        #expect(Self.iconLines(logged.all).isEmpty, "the log was told \(logged.all)")
      }
    }
  }
}
