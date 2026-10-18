import Testing

@testable import ArcaCore

/// Where an app keeps its config files: `${XDG_CONFIG_HOME:-$HOME/.config}/<app>`.
@Suite("Config folder")
struct ConfigFolderTests {
  @Test("XDG_CONFIG_HOME, when it is set, holds the app's folder")
  func xdg() {
    let environment = ["XDG_CONFIG_HOME": "/home/ada/xdg", "HOME": "/home/ada"]
    #expect(ConfigFolder.path(app: "menuz", environment: environment, home: "/home/other") == "/home/ada/xdg/menuz")
  }

  @Test("without it the folder is under HOME's .config, and an empty variable counts as unset")
  func home() {
    let unset = ["HOME": "/home/ada"]
    let empty = ["XDG_CONFIG_HOME": "", "HOME": "/home/ada"]
    #expect(ConfigFolder.path(app: "menuz", environment: unset, home: "/home/other") == "/home/ada/.config/menuz")
    #expect(ConfigFolder.path(app: "menuz", environment: empty, home: "/home/other") == "/home/ada/.config/menuz")
  }

  @Test("a relative XDG_CONFIG_HOME is ignored, as the XDG spec says, and a trailing slash adds no empty step")
  func relative() {
    for xdg in [".config", "~/.config"] {
      let environment = ["XDG_CONFIG_HOME": xdg, "HOME": "/home/ada"]
      #expect(
        ConfigFolder.path(app: "menuz", environment: environment, home: "/home/other") == "/home/ada/.config/menuz")
    }
    let slash = ["XDG_CONFIG_HOME": "/home/ada/xdg/", "HOME": "/home/ada"]
    #expect(ConfigFolder.path(app: "menuz", environment: slash, home: "/home/other") == "/home/ada/xdg/menuz")
  }

  @Test("with no HOME either, the home the app gives is used")
  func fallback() {
    #expect(
      ConfigFolder.path(app: "conflab", environment: ["HOME": ""], home: "/home/ada") == "/home/ada/.config/conflab")
    #expect(ConfigFolder.path(app: "conflab", environment: [:], home: "/home/ada") == "/home/ada/.config/conflab")
  }
}
