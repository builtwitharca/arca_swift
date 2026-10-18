import Foundation

/// The folder an app keeps its config files in, found from an environment
/// as the XDG spec has it: `${XDG_CONFIG_HOME:-$HOME/.config}/<app>`. An
/// empty variable counts as unset, as `:-` reads it, and a relative one is
/// ignored, as the spec says. launchd gives a GUI app none of the user's
/// variables, so an app that captures its login shell's environment passes
/// that capture.
package enum ConfigFolder {
  /// `home` is used when the environment has no HOME.
  package static func path(app: String, environment: [String: String], home: String) -> String {
    func value(_ name: String) -> String? {
      guard let value = environment[name], !value.isEmpty else { return nil }
      return value
    }
    let xdg = value("XDG_CONFIG_HOME").flatMap { $0.hasPrefix("/") ? $0 : nil }
    let base = xdg ?? ((value("HOME") ?? home) as NSString).appendingPathComponent(".config")
    return (base as NSString).appendingPathComponent(app)
  }
}
