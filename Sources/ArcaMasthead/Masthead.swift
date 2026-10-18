import ArcaCore
import Foundation

/// What the top line shows (design.md "The row" and "The file"): the heading,
/// the subheading, the icon, and the About window's files.
struct Masthead: Equatable, Sendable {
  let heading: String
  let subheading: String?
  let icon: MastheadFile.Icon
  /// The About window's files, or nil when no masthead.yaml could be used.
  let about: MastheadFile.About?
  /// Each copy of masthead.yaml that was refused, the user's first, for the
  /// app's log. The first is the subheading.
  let refusals: [Refusal]

  /// The top line from masthead.yaml: the user's copy in `folder` when it is
  /// read and checked without a refusal, and otherwise the default in
  /// `bundle`.
  static func load(folder: String, bundle: Bundle, values: MastheadValues) -> Masthead {
    let found = ConfigFile.first(named: "masthead.yaml", folder: folder, bundle: bundle) { file in
      file.entries().flatMap { MastheadFile.check($0, file: file.path, names: values.names) }
    }
    return Masthead(found: found, values: values)
  }
}

extension Masthead {
  /// The top line from the copy that was used, if one was, and the refusals
  /// of those before it. The first refusal is the subheading, saying what
  /// was wrong; with no copy used, the heading is the app's name alone.
  init(found: (value: MastheadFile?, refusals: [Refusal]), values: MastheadValues) {
    let refusal = found.refusals.first?.description
    guard let file = found.value else {
      self.init(heading: values.appName, subheading: refusal, icon: .app, about: nil, refusals: found.refusals)
      return
    }
    let lines = file.masthead(values)
    self.init(
      heading: lines.heading, subheading: refusal ?? lines.subheading, icon: lines.icon, about: lines.about,
      refusals: found.refusals)
  }
}
