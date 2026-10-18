// swift-tools-version: 6.2
// arca_swift: the shared Swift libraries for the menu bar apps (ST0001).
// 6.2 is the first tools version that names macOS 26, the floor WebKit's
// SwiftUI web view sets (design.md "The package"). ArcaCore is internal: the
// libraries share it, and an app imports only the libraries it uses.
// ArcaLogConsole's product joins with its code (WP-09). A warning fails the
// build of this package's own targets; SwiftPM drops the setting when an app
// builds the package as a dependency (SE-0480).
import PackageDescription

let settings: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
  name: "arca_swift",
  platforms: [.macOS(.v26)],
  products: [
    .library(name: "ArcaMasthead", targets: ["ArcaMasthead"])
  ],
  dependencies: [
    .package(url: "https://github.com/jpsim/Yams", from: "6.0.1"),
    .package(url: "https://github.com/swiftlang/swift-cmark", from: "0.9.0"),
  ],
  targets: [
    .target(name: "ArcaCore", dependencies: ["Yams"], swiftSettings: settings),
    .target(
      name: "ArcaMasthead",
      dependencies: [
        "ArcaCore",
        .product(name: "cmark-gfm", package: "swift-cmark"),
        .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
      ],
      swiftSettings: settings
    ),
    .testTarget(name: "ArcaCoreTests", dependencies: ["ArcaCore"], swiftSettings: settings),
    .testTarget(name: "ArcaMastheadTests", dependencies: ["ArcaMasthead"], swiftSettings: settings),
  ]
)
