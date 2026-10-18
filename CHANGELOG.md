# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The package, for macOS 26 and Swift 6.2 or later. It has one library, `ArcaMasthead`, and the internal target `ArcaCore`, and it depends on Yams for YAML and on swift-cmark for cmark-gfm. A warning in the package's own code fails its build.
- `ArcaCore` finds an app's config file in the app's config folder, `${XDG_CONFIG_HOME:-$HOME/.config}/<app>`, and then in its bundle. A user's copy that is there but cannot be read, such as a broken link, is refused rather than passed over for the bundle's. It reads the file as YAML, keeping every value as written. Each refusal is one line naming the file, the key and the value, or, for text that is not YAML, the problem and its line and column. It also expands `{token}` templates, and names each token that has no value.
- `ArcaMasthead` turns Markdown into HTML with GitHub's tables, strikethrough, autolinks and task lists. HTML in the Markdown passes through.
- CI checks the formatting, builds the package and runs its tests on every push and pull request, on GitHub's macOS 26 runners.
- The MIT licence.
