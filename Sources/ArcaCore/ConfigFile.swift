import Foundation

/// A config file an app reads, and where it was found (design.md "The
/// file"): the user's copy in the app's config folder, or the default the
/// app ships in its bundle. Nothing in a bundle is written, since that would
/// break the app's signature.
package struct ConfigFile: Equatable, Sendable {
  package enum Origin: Equatable, Sendable {
    case user
    case bundled
  }

  package let path: String
  package let origin: Origin

  package init(path: String, origin: Origin) {
    self.path = path
    self.origin = origin
  }

  /// The files to read, in order: the user's copy when the folder holds one,
  /// then the bundle's when the app ships one. A reader takes the first, and
  /// falls back to the bundle's when the user's is refused. `exists` is the
  /// file system's answer for a path.
  package static func candidates(
    name: String, folder: String, bundled: String?, exists: (String) -> Bool
  ) -> [ConfigFile] {
    let user = (folder as NSString).appendingPathComponent(name)
    var files: [ConfigFile] = []
    if exists(user) { files.append(ConfigFile(path: user, origin: .user)) }
    if let bundled { files.append(ConfigFile(path: bundled, origin: .bundled)) }
    return files
  }

  /// The same, asking the file system and `bundle`'s resources. The user's
  /// copy counts as there unless the system says there is no such file, so a
  /// broken link, or a folder the app may not search, is refused in the
  /// system's words rather than passed over for the bundle's default.
  package static func candidates(name: String, folder: String, bundle: Bundle) -> [ConfigFile] {
    candidates(
      name: name, folder: folder, bundled: bundle.path(forResource: name, ofType: nil), exists: isPresent)
  }

  /// Whether `path` names something, a link included, or cannot be looked at
  /// for a reason other than its absence.
  private static func isPresent(_ path: String) -> Bool {
    var info = stat()
    return lstat(path, &info) == 0 || errno != ENOENT
  }

  /// The file's text, or why it could not be read.
  package func text() -> Result<String, Refusal> {
    let data: Data
    do {
      data = try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
      return .failure(refusal("cannot be read: \(Self.reason(error))"))
    }
    guard let text = String(data: data, encoding: .utf8) else {
      return .failure(refusal("not UTF-8 text"))
    }
    return .success(text)
  }

  /// The file's top-level entries: its text, read as YAML.
  package func entries() -> Result<[ConfigEntry], Refusal> {
    text().flatMap { ConfigDocument.entries($0, file: path) }
  }

  private func refusal(_ why: String) -> Refusal {
    Refusal(file: path, key: nil, value: nil, why: why)
  }

  /// The system's own words for a failed read (eg "No such file or
  /// directory"), or Foundation's when it gives no POSIX error.
  private static func reason(_ error: any Error) -> String {
    let error = error as NSError
    if let posix = error.userInfo[NSUnderlyingErrorKey] as? NSError, posix.domain == NSPOSIXErrorDomain {
      return String(cString: strerror(Int32(posix.code)))
    }
    return error.localizedDescription
  }
}
