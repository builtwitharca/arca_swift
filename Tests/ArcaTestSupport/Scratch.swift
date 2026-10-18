import Foundation

/// A folder of the test's own under the temporary directory, removed when
/// the body returns, so no test sees another's files. Its path has its
/// symlinks resolved (`/var` is `/private/var`), as a bundle reports a path.
/// The test targets share this one copy.
package enum Scratch {
  /// A body that failed, and its folder, which could not then be removed.
  package struct Leftover: Error, CustomStringConvertible {
    package let failure: any Error
    package let removal: any Error
    package let path: String

    package var description: String {
      "\(failure); and the folder \(path) was not removed: \(removal)"
    }
  }

  /// A folder that cannot be removed fails the test too: on its own when the
  /// body returns, and as a Leftover, with the body's failure, when it
  /// throws.
  package static func folder<T>(_ body: (String) throws -> T) throws -> T {
    let temporary = (NSTemporaryDirectory() as NSString).resolvingSymlinksInPath
    let path = (temporary as NSString).appendingPathComponent("arca-\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
    let outcome = Result { try body(path) }
    let removal = Result { try FileManager.default.removeItem(atPath: path) }
    switch (outcome, removal) {
    case (.success(let value), .success): return value
    case (.failure(let error), .success), (.success, .failure(let error)): throw error
    case (.failure(let failure), .failure(let error)): throw Leftover(failure: failure, removal: error, path: path)
    }
  }

  /// An app's config folder, config/menuz, and its bundle, Example.bundle,
  /// made in `scratch`, with the folder the bundle's resources go in. A test
  /// writes the files it needs into each.
  package static func app(in scratch: String) throws -> (folder: String, bundle: String, resources: String) {
    let bundle = "\(scratch)/Example.bundle"
    let folder = try folders("\(scratch)/config/menuz")
    let resources = try folders("\(bundle)/Contents/Resources")
    return (folder, bundle, resources)
  }

  /// Makes `path`'s folders, then returns it.
  package static func folders(_ path: String) throws -> String {
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
  }

  /// Writes `contents` to `name` in `folder`, and returns the file's path.
  package static func write(_ contents: String, to name: String, in folder: String) throws -> String {
    let path = (folder as NSString).appendingPathComponent(name)
    try contents.write(toFile: path, atomically: false, encoding: .utf8)
    return path
  }
}
