import Foundation
import Testing

/// A folder of the test's own under the temporary directory, removed when
/// the body returns, so no test sees another's files. Its path has its
/// symlinks resolved (`/var` is `/private/var`), as a bundle reports a path.
enum Scratch {
  static func folder<T>(_ body: (String) throws -> T) throws -> T {
    let temporary = (NSTemporaryDirectory() as NSString).resolvingSymlinksInPath
    let path = (temporary as NSString).appendingPathComponent("arca-\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
    defer {
      do {
        try FileManager.default.removeItem(atPath: path)
      } catch {
        Issue.record("the scratch folder \(path) was not removed: \(error)")
      }
    }
    return try body(path)
  }

  /// Makes `path`'s folders, then returns it.
  static func folders(_ path: String) throws -> String {
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
  }

  /// Writes `contents` to `name` in `folder`, and returns the file's path.
  static func write(_ contents: String, to name: String, in folder: String) throws -> String {
    let path = (folder as NSString).appendingPathComponent(name)
    try contents.write(toFile: path, atomically: false, encoding: .utf8)
    return path
  }
}
