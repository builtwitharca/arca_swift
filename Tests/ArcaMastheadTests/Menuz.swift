@testable import ArcaMasthead

/// The app the masthead tests stand in for: menuz 0.3.0 at 56e0c90, a dev
/// build, whose About page is an about.md with no stylesheet.
enum Menuz {
  static var info: [String: Any] {
    ["CFBundleName": "menuz", "CFBundleShortVersionString": "0.3.0", "ArcaCommit": "56e0c90", "ArcaKind": "dev"]
  }

  static let about = MastheadFile.About(body: "about.md", kind: .markdown, css: nil)
  static let values = MastheadValues(bundle: info)
}
