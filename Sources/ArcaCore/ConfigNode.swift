import Foundation
import Yams

/// A YAML document as a config reader walks it (design.md "The file").
/// Every scalar is the text it was written as: YAML's core schema would read
/// `true` as a Bool, `0.10` as 0.1 and `~` as null, where a config file
/// means the text. An alias is the node its anchor names, and a merge key
/// (`<<`) is a key like any other, since composing applies no merge.
package enum ConfigNode: Equatable, Sendable {
  case text(String)
  case list([ConfigNode])
  /// A mapping's entries, in the file's order.
  case map([ConfigEntry])
}

/// One key of a mapping and its value. A key is text: a key given twice, or
/// one that is a list or a mapping, is refused when the file is read.
package struct ConfigEntry: Equatable, Sendable {
  package let key: String
  package let value: ConfigNode

  package init(key: String, value: ConfigNode) {
    self.key = key
    self.value = value
  }
}

/// Reads a config file's text as YAML. Yams composes it once, and the walk
/// carries its node into `ConfigNode`, so neither library walks Yams' own
/// types.
package enum ConfigDocument {
  /// The file's top-level entries, or why the text was refused: not YAML,
  /// not a mapping of keys, or a key given twice or that is not text. A file
  /// with nothing in it, only comments, or a document that is null (`---`
  /// alone, `~` or `null`, unquoted) has no entries.
  package static func entries(_ yaml: String, file: String) -> Result<[ConfigEntry], Refusal> {
    let root: Node?
    do {
      root = try Yams.compose(yaml: yaml)
    } catch {
      return .failure(Refusal(file: file, key: nil, value: nil, why: why(error)))
    }
    guard let root, root.null == nil else { return .success([]) }
    guard case .mapping(let mapping) = root else {
      return .failure(Refusal(file: file, key: nil, value: nil, why: "the file is not a mapping of keys"))
    }
    do throws(Refusal) {
      return .success(try Walk(file: file).entries(mapping, at: nil))
    } catch {
      return .failure(error)
    }
  }

  /// One line saying what Yams found wrong, and where. Yams' own description
  /// puts the problem on its second line and a copy of the text after it, so
  /// the line is built from the error's fields.
  private static func why(_ error: any Error) -> String {
    guard let error = error as? YamlError else { return "not YAML: \(firstLine(error))" }
    switch error {
    case .scanner(let context, let problem, let mark, _), .parser(let context, let problem, let mark, _),
      .composer(let context, let problem, let mark, _):
      let reading = context.map { ", \($0.text) in line \($0.mark.line), column \($0.mark.column)" } ?? ""
      return "not YAML: line \(mark.line), column \(mark.column): \(problem)\(reading)"
    case .duplicatedKeysInMapping(let duplicates, let context):
      return Walk.givenTwice(duplicates, first: context.mark)
    default:
      return "not YAML: \(firstLine(error))"
    }
  }

  private static func firstLine(_ error: any Error) -> String {
    String(describing: error).split(separator: "\n").first.map(String.init) ?? ""
  }
}

/// The walk from Yams' node to `ConfigNode`. It stops at the first key it
/// cannot carry, naming the path of the mapping that holds it.
private struct Walk {
  let file: String

  /// Why a mapping was refused for keys it gives more than once, and where
  /// the first of them is.
  static func givenTwice(_ names: [String], first: Mark?) -> String {
    let quoted = names.sorted().map { "'\($0)'" }.joined(separator: ", ")
    let what =
      names.count == 1
      ? "the key \(quoted) is given more than once" : "the keys \(quoted) are each given more than once"
    guard let first else { return what }
    return "\(what), first in line \(first.line), column \(first.column)"
  }

  func entries(_ mapping: Node.Mapping, at path: String?) throws(Refusal) -> [ConfigEntry] {
    var entries: [ConfigEntry] = []
    var seen: [String: Node] = [:]
    for (keyNode, valueNode) in mapping {
      guard case .scalar(let key) = keyNode else {
        throw Refusal(file: file, key: path, value: nil, why: "a key is a list or a mapping, not text")
      }
      // Yams refuses a key given twice only when its tag matches too, so
      // `on` (a Bool to YAML) and `'on'` (a string) both reach here.
      if let first = seen[key.string] {
        throw Refusal(file: file, key: path, value: nil, why: Self.givenTwice([key.string], first: first.mark))
      }
      seen[key.string] = keyNode
      let at = path.map { "\($0).\(key.string)" } ?? key.string
      let value = try node(valueNode, at: at)
      entries.append(ConfigEntry(key: key.string, value: value))
    }
    return entries
  }

  func node(_ node: Node, at path: String) throws(Refusal) -> ConfigNode {
    switch node {
    case .scalar(let scalar):
      return .text(scalar.string)
    case .sequence(let sequence):
      var items: [ConfigNode] = []
      for (index, item) in sequence.enumerated() {
        let value = try self.node(item, at: "\(path)[\(index)]")
        items.append(value)
      }
      return .list(items)
    case .mapping(let mapping):
      let entries = try self.entries(mapping, at: path)
      return .map(entries)
    case .alias:
      // compose gives each alias as its anchor's node (Yams' loadAlias), so
      // none reaches here; should a later Yams change that, the file is
      // refused rather than read wrongly.
      throw Refusal(file: file, key: path, value: nil, why: "an alias Yams left unresolved")
    }
  }
}
