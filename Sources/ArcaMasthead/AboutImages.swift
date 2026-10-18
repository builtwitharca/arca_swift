import ArcaCore
import Foundation

/// The images an About body names by file name (design.md "The About
/// window"), found as masthead.yaml is: the copy in the app's config folder
/// first, then its bundle's.
struct AboutImages: Sendable {
  /// An image's bytes, and the type it is served as.
  struct Image: Equatable, Sendable {
    let data: Data
    let type: String
  }

  /// The extensions an image may have, in lower case and in the order a
  /// refusal names them, and the type each is served as.
  private static let types: [(suffix: String, type: String)] = [
    ("png", "image/png"), ("jpg", "image/jpeg"), ("jpeg", "image/jpeg"), ("gif", "image/gif"),
    ("webp", "image/webp"), ("svg", "image/svg+xml"),
  ]

  let folder: String
  let bundle: Bundle

  /// The image whose file name is `url`'s path, or nil, with the refusals of
  /// the copies before the one used. A name that `named` refuses is not
  /// looked for.
  func image(_ url: URL) -> (value: Image?, refusals: [Refusal]) {
    switch named(url) {
    case .failure(let refusal):
      return (nil, [refusal])
    case .success(let file):
      let found = ConfigFile.first(named: file.name, folder: folder, bundle: bundle) { $0.data() }
      return (found.value.map { Image(data: $0, type: file.type) }, found.refusals)
    }
  }

  /// The file name `url`'s path gives, decoded, and the type it is served
  /// as, or why not: a name with a folder or a control character in it, or
  /// that is not a .png, .jpg, .jpeg, .gif, .webp or .svg file, is refused.
  func named(_ url: URL) -> Result<(name: String, type: String), Refusal> {
    let name = String(url.path(percentEncoded: false).drop { $0 == "/" })
    if let why = MastheadFile.fileNameRefusal(name) { return .failure(refusal(name, why)) }
    let suffix = MastheadFile.suffix(name)
    guard let type = Self.types.first(where: { $0.suffix == suffix })?.type else {
      let kinds = MastheadFile.list(Self.types.map { ".\($0.suffix)" }, "or")
      return .failure(refusal(name, "is not a \(kinds) file"))
    }
    return .success((name, type))
  }

  /// A refusal of `name`, as the body names it, before it is looked for.
  private func refusal(_ name: String, _ why: String) -> Refusal {
    Refusal(file: folder, key: nil, value: name, why: why)
  }
}
