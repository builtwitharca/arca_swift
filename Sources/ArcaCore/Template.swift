/// Text with `{token}` holes, such as a heading's `{name} {version}`
/// (design.md "The file"). A token is a name between braces: a letter, then
/// letters, digits and underscores. Every other brace is text, so CSS and
/// prose pass through as written; there is no escape.
package struct Template: Equatable, Sendable {
  enum Part: Equatable, Sendable {
    case text(String)
    case token(String)
  }

  let parts: [Part]

  package init(_ text: String) {
    var parts: [Part] = []
    var literal = ""
    var rest = text[...]
    while let open = rest.firstIndex(of: "{") {
      literal += rest[..<open]
      let name = rest.index(after: open)
      if let close = rest[name...].firstIndex(of: "}"), Self.isName(rest[name..<close]) {
        if !literal.isEmpty {
          parts.append(.text(literal))
          literal = ""
        }
        parts.append(.token(String(rest[name..<close])))
        rest = rest[rest.index(after: close)...]
      } else {
        literal += "{"
        rest = rest[name...]
      }
    }
    literal += rest
    if !literal.isEmpty { parts.append(.text(literal)) }
    self.parts = parts
  }

  /// Each token's name, once, in the order it first appears.
  package var tokens: [String] {
    var names: [String] = []
    for case .token(let name) in parts where !names.contains(name) {
      names.append(name)
    }
    return names
  }

  /// The text with each token replaced by its value. A token with no value
  /// stays as written and is named in `missing`, so the caller decides what
  /// a value it lacks means. A value is not read for tokens.
  package func render(_ values: [String: String]) -> Rendering {
    var text = ""
    var missing: [String] = []
    for part in parts {
      switch part {
      case .text(let literal):
        text += literal
      case .token(let name):
        if let value = values[name] {
          text += value
        } else {
          text += "{\(name)}"
          if !missing.contains(name) { missing.append(name) }
        }
      }
    }
    return Rendering(text: text, missing: missing)
  }

  private static func isName(_ name: Substring) -> Bool {
    guard let first = name.unicodeScalars.first, isLetter(first) else { return false }
    return name.unicodeScalars.allSatisfy { isLetter($0) || ("0"..."9").contains($0) || $0 == "_" }
  }

  private static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
    ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
  }
}

/// A template's text with its values in, and the tokens that had none.
package struct Rendering: Equatable, Sendable {
  package let text: String
  package let missing: [String]
}
