import ArcaCore
import ArcaTestSupport
import Foundation
import Testing

@testable import ArcaMasthead

/// The images an About body names by file name (design.md "The About
/// window"): found as masthead.yaml is, and refused when the name has a
/// folder in it or is not an image's.
/// Acceptance test AT-03.4, in ST0001's acceptance.md.
@Suite("About images")
struct AboutImagesTests {
  /// A PNG's signature with a byte after it, enough to tell two copies apart.
  static let user = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01])
  static let bundled = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x02])

  /// The address a page asks for when its body names `name`.
  static func url(_ name: String) throws -> URL {
    try #require(URL(string: name, relativeTo: AboutDocument.base)).absoluteURL
  }

  /// An app in `scratch`, and its images.
  static func images(_ scratch: String) throws -> (images: AboutImages, folder: String, resources: String) {
    let app = try Scratch.app(in: scratch)
    let bundle = try #require(Bundle(path: app.bundle))
    return (AboutImages(folder: app.folder, bundle: bundle), app.folder, app.resources)
  }

  @Test("an image named by file name is the config folder's copy, or else the bundle's, served as its type")
  func found() throws {
    try Scratch.folder { scratch in
      let (images, folder, resources) = try Self.images(scratch)
      try Self.bundled.write(to: URL(fileURLWithPath: "\(resources)/logo.png"))
      let user = "\(folder)/logo.png"
      try Self.user.write(to: URL(fileURLWithPath: user))
      let url = try Self.url("logo.png")
      let found = images.image(url)
      #expect(found.value == AboutImages.Image(data: Self.user, type: "image/png"))
      #expect(found.refusals.isEmpty)
      try FileManager.default.removeItem(atPath: user)
      #expect(images.image(url).value == AboutImages.Image(data: Self.bundled, type: "image/png"))
    }
  }

  @Test(
    "each image type is served as its own, its extension in any case",
    arguments: [
      ("logo.png", "image/png"), ("photo.JPG", "image/jpeg"), ("photo.jpeg", "image/jpeg"), ("moving.gif", "image/gif"),
      ("still.webp", "image/webp"), ("mark.SVG", "image/svg+xml"),
    ])
  func types(name: String, type: String) throws {
    try Scratch.folder { scratch in
      let (images, folder, _) = try Self.images(scratch)
      try Self.user.write(to: URL(fileURLWithPath: "\(folder)/\(name)"))
      let url = try Self.url(name)
      #expect(images.image(url).value == AboutImages.Image(data: Self.user, type: type))
    }
  }

  @Test("the name is the address's path, decoded, without its query or its fragment")
  func name() throws {
    try Scratch.folder { scratch in
      let (images, folder, _) = try Self.images(scratch)
      try Self.user.write(to: URL(fileURLWithPath: "\(folder)/my logo.png"))
      let url = try Self.url("my%20logo.png?size=2#top")
      #expect(images.image(url).value == AboutImages.Image(data: Self.user, type: "image/png"))
    }
  }

  @Test(
    "a name with a folder in it is refused, since an image is found beside masthead.yaml",
    arguments: ["docs/logo.png", "a/b/logo.png"])
  func path(name: String) throws {
    try Scratch.folder { scratch in
      let (images, folder, _) = try Self.images(scratch)
      let found = images.image(try Self.url(name))
      #expect(found.value == nil)
      #expect(found.refusals == [Refusal(file: folder, key: nil, value: name, why: "is a path, not a file name")])
    }
  }

  @Test(
    "one rule refuses a file name with a folder or a control character in it, for images and the About files alike",
    arguments: [
      ("docs/logo.png", "is a path, not a file name"), ("logo\u{0}.png", "has a control character in it"),
      ("logo\n.png", "has a control character in it"), ("logo\u{7F}.png", "has a control character in it"),
    ])
  func fileNameRule(name: String, why: String) {
    #expect(MastheadFile.fileNameRefusal(name) == why)
    #expect(MastheadFile.fileNameRefusal("logo.png") == nil)
  }

  @Test(
    "a name that is not an image's is refused",
    arguments: ["about.md", "masthead.yaml", "logo", "logo.png.txt", "logo.tiff"])
  func notAnImage(name: String) throws {
    try Scratch.folder { scratch in
      let (images, folder, _) = try Self.images(scratch)
      _ = try Scratch.write("# here\n", to: name, in: folder)
      let found = images.image(try Self.url(name))
      #expect(found.value == nil)
      let why = "is not a .png, .jpg, .jpeg, .gif, .webp or .svg file"
      #expect(found.refusals == [Refusal(file: folder, key: nil, value: name, why: why)])
    }
  }

  @Test("an image in neither place is refused, naming where the user's would be")
  func absent() throws {
    try Scratch.folder { scratch in
      let (images, folder, _) = try Self.images(scratch)
      let found = images.image(try Self.url("logo.png"))
      #expect(found.value == nil)
      let why = "is not there, and the app's bundle has none"
      #expect(found.refusals == [Refusal(file: "\(folder)/logo.png", key: nil, value: nil, why: why)])
    }
  }

  @Test("a copy that cannot be read is refused in the system's words, and the bundle's is used")
  func unreadable() throws {
    try Scratch.folder { scratch in
      let (images, folder, resources) = try Self.images(scratch)
      try Self.bundled.write(to: URL(fileURLWithPath: "\(resources)/logo.png"))
      let link = "\(folder)/logo.png"
      try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "\(scratch)/gone.png")
      let found = images.image(try Self.url("logo.png"))
      #expect(found.value == AboutImages.Image(data: Self.bundled, type: "image/png"))
      let why = "cannot be read: No such file or directory"
      #expect(found.refusals == [Refusal(file: link, key: nil, value: nil, why: why)])
    }
  }
}
