// swift-tools-version: 6.2
// arca_swift: the shared Swift libraries for the menu bar apps (ST0001).
// 6.2 is the first tools version that names macOS 26, the floor WebKit's
// SwiftUI web view sets (design.md "The package"). ArcaCore is internal: the
// libraries share it, and an app imports only the libraries it uses.
// ArcaLogConsole's product joins with its code (WP-09). ArcaTestSupport holds
// what the test targets share, and no product has it. ArcaMastheadExample is
// an app that shows the row and the About window, built here and by CI, and
// in no product.
//
// A warning fails the build of the package's own targets only when
// ARCA_SWIFT_STRICT is set, to any value. CI's test job and the README's build
// and test commands set it, and an app that builds the package as a dependency
// does not. The setting, the compiler's -warnings-as-errors, must not reach an
// app's build: Xcode 26.6's Swift 6.3.3 passes it beside the
// -suppress-warnings it gives a dependency, and the compiler refuses the pair
// (issue 0002). Xcode 27's Swift 6.4 drops the setting for a dependency, as
// SE-0480 specifies.
import PackageDescription

let strict = Context.environment["ARCA_SWIFT_STRICT"] != nil
let settings: [SwiftSetting] = strict ? [.treatAllWarnings(as: .error)] : []

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
    .executableTarget(
      name: "ArcaMastheadExample", dependencies: ["ArcaMasthead"], resources: [.process("Resources")],
      swiftSettings: settings
    ),
    .target(name: "ArcaTestSupport", path: "Tests/ArcaTestSupport", swiftSettings: settings),
    .testTarget(name: "ArcaCoreTests", dependencies: ["ArcaCore", "ArcaTestSupport"], swiftSettings: settings),
    .testTarget(
      name: "ArcaMastheadTests", dependencies: ["ArcaMasthead", "ArcaCore", "ArcaTestSupport"], swiftSettings: settings
    ),
  ]
)
