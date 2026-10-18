/// One reason a config file was refused (design.md "The file"): the file,
/// the key and the value, and why. It prints as one line, which is how an
/// app's log and its menu show it.
package struct Refusal: Error, Equatable, Sendable, CustomStringConvertible {
  package let file: String
  /// The key's path from the top of the file (`about.body`, `rows[0]`), or
  /// nil when the refusal is about the file as a whole.
  package let key: String?
  package let value: String?
  package let why: String

  package init(file: String, key: String?, value: String?, why: String) {
    self.file = file
    self.key = key
    self.value = value
    self.why = why
  }

  /// `<file>: <key> = '<value>': <why>`; a refusal with no value prints
  /// `<file>: <key>: <why>`, a value with no key `<file>: '<value>': <why>`,
  /// and one about the whole file `<file>: <why>`. A control character or a
  /// line break in any part prints as its escape (`\n`), so it stays one line.
  package var description: String {
    let line: String
    switch (key, value) {
    case (let key?, let value?): line = "\(file): \(key) = '\(value)': \(why)"
    case (let key?, nil): line = "\(file): \(key): \(why)"
    case (nil, let value?): line = "\(file): '\(value)': \(why)"
    case (nil, nil): line = "\(file): \(why)"
    }
    return Self.oneLine(line)
  }

  private static func oneLine(_ text: String) -> String {
    var line = ""
    for scalar in text.unicodeScalars {
      switch scalar.properties.generalCategory {
      case .control, .lineSeparator, .paragraphSeparator:
        line += escape(scalar)
      default:
        line.unicodeScalars.append(scalar)
      }
    }
    return line
  }

  /// `\n`, `\r` and `\t` as Swift writes them, and any other as `\u{<hex>}`.
  private static func escape(_ scalar: Unicode.Scalar) -> String {
    switch scalar {
    case "\n": return "\\n"
    case "\r": return "\\r"
    case "\t": return "\\t"
    default: return "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
    }
  }
}
