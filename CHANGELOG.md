# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- A console window's footer names what the console follows, then the command running. A file is named by its path, and a command by its label or by a name its own output gives through the app's `naming:` function.
- The footer's Copy All copies the lines the window shows.
- `LogConsole(quietLinesKey:)` remembers in the app's defaults whether the quiet lines show, and starts as they were left.
- `onWindowClose` tells the app when the console's window closes, so that it can follow a command only while the window shows.
- `isFollowing(_:)` says whether the console still follows a source.
- `note(command:lines:status:)` shows a command the app ran without the console, framed as a run is.
- A console's window opens where it was last left.
- `CommandLaunch.launcher(grace:)` makes a launcher whose stopped child is given a `Duration` to end on its own; with `nil` it is terminated at once, for a command that does not end when its stdin closes.
- A `ConsoleTheme` can set the window's appearance, eg dark whatever the system's mode.
- The example app's console remembers its quiet lines, and notes when its window closes.

### Changed

- CI builds and tests with Xcode 27.1 on GitHub's `xcode-27` image (macOS 27), the test job and the adopter alike. The adopter no longer builds with Xcode 26.6, so CI no longer checks the Xcode 26 dependency build that 0.1.1 fixed. The package still supports macOS 26 and Swift 6.2 or later.

## [0.2.0] - 2026-10-22

### Added

- `ArcaLogConsole`, a console for an app's logs and the commands it runs. A `LogConsole` follows a file in-process, across a truncation or a rotation, or a command's output; runs one command at a time, framed by `» cmd` and `» exit N · 1.2s`; and takes the app's notes. A cancelled run stops its command, and a run always ends, even when a process it started holds its output open. Its window follows the end, finds with ⌘F, clears with ⌘K and closes with ⌘W. Lines are classified by the app, with the library's start-of-line tokens and timestamp skip to build on, and quiet lines are hidden until shown. A console keeps 5000 lines and 5000 quiet ones apart.
- The example app has a console: it follows a log the app writes, runs a command and rotates the log.

## [0.1.1] - 2026-10-19

### Fixed

- An app that depends on the package builds on Xcode 26. 0.1.0's manifest made every target's warnings errors, which Xcode 26.6's Swift 6.3.3 passes as `-warnings-as-errors` beside the `-suppress-warnings` it gives a dependency, and the compiler refused the pair. The setting now applies only when `ARCA_SWIFT_STRICT` is set, as the package's own CI and the README's commands set it.

### Added

- CI builds an adopter: a package that names arca_swift by URL and revision, built with xcodebuild and Xcode 26.6 on GitHub's macOS 26 runners, as the apps build it.

## [0.1.0] - 2026-10-18

### Added

- The package, for macOS 26 and Swift 6.2 or later. It has one library, `ArcaMasthead`, and the internal target `ArcaCore`, and it depends on Yams for YAML and on swift-cmark for cmark-gfm. A warning in the package's own code fails its build.
- `ArcaCore` finds an app's config file in the app's config folder, `${XDG_CONFIG_HOME:-$HOME/.config}/<app>`, and then in its bundle. A user's copy that is there but cannot be read, such as a broken link, is refused rather than passed over for the bundle's. It reads the file as YAML, keeping every value as written. Each refusal is one line naming the file, the key and the value, or, for text that is not YAML, the problem and its line and column. It also expands `{token}` templates, and names each token that has no value.
- `ArcaMasthead` turns Markdown into HTML with GitHub's tables, strikethrough, autolinks and task lists. HTML in the Markdown passes through.
- `ArcaMasthead` reads `masthead.yaml`: the user's copy in the app's config folder when it passes its checks, and otherwise the default in the app's bundle, with the subheading saying what was wrong. Each refusal is one line naming the file, the key and the value. Its `{token}`s take the bundle's name, version, commit and kind, read from Info.plist's `CFBundleName`, `CFBundleShortVersionString`, `ArcaCommit` and `ArcaKind`, and the app's own values. Each line waits for its own values: until they are there, the heading is the app's name alone and the subheading is hidden. The About page's body is made HTML, each value in it escaped, and its stylesheet is read beside it.
- `MastheadRow`, the row at the top of an app's menu: the heading in bold, the subheading under it and the app's icon, read from `masthead.yaml` each time the menu opens, with each refusal sent to the app's log once. Choosing it opens the About window.
- The About window shows the page in WebKit's web view. The window's stylesheet follows light and dark mode, the app's is laid over it, and every refusal is listed above the body. The page runs no JavaScript. Its Content-Security-Policy allows only its own styles, `data:` images and the images the app serves by file name, found as the About files are. A link to an `http`, `https` or `mailto` address opens in the browser, and every other navigation is cancelled. A token in the body that names no value is refused.
- `ArcaMastheadExample`, an app that shows the row and the About window.
- CI checks the formatting, builds the package and runs its tests on every push and pull request, on GitHub's macOS 26 runners.
- The MIT licence.
