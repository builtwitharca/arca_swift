/// Text made safe to put in HTML, in an element or a quoted attribute
/// (design.md "The About window"). It is the one place a value is escaped.
enum HTML {
  /// `&`, `<`, `>`, `"` and `'` as entities, and every other character as it
  /// is. It goes by Unicode scalar, so a quote that a combining mark follows
  /// is escaped too.
  static func escape(_ text: String) -> String {
    var escaped = ""
    for scalar in text.unicodeScalars {
      switch scalar {
      case "&": escaped += "&amp;"
      case "<": escaped += "&lt;"
      case ">": escaped += "&gt;"
      case "\"": escaped += "&quot;"
      case "'": escaped += "&#39;"
      default: escaped.unicodeScalars.append(scalar)
      }
    }
    return escaped
  }
}
