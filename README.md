<p align="center"><img src="design/icons/arca_swift-icon.svg" width="128" height="128" alt="The arca_swift icon: a white swift rising from a chest, on an orange tile"></p>

# arca_swift

Shared Swift libraries for macOS menu bar apps. Each app imports only the libraries it uses, and what they show comes from files the user can change without a rebuild.

## Libraries

| Library          | What it gives an app                              | State       |
| ---------------- | ------------------------------------------------- | ----------- |
| `ArcaMasthead`   | The menu's top line and the About window it opens | In progress |
| `ArcaLogConsole` | A log console window                              | Planned     |

`ArcaMasthead`'s top line is the app's name and version over a smaller subheading. Choosing it opens an About window that shows Markdown or HTML. Both are set in a `masthead.yaml` in the app's config folder, with a default in the app's bundle.

`ArcaCore` holds what the libraries share: finding an app's config file in its config folder or its bundle, reading it as YAML, and expanding `{token}` templates. It is internal to the package.

## Requirements

- macOS 26 or later.
- Swift 6.2 or later, which comes with Xcode 26 or later.

## Adding it to an app

```swift
.package(url: "https://github.com/matthewsinclair/arca_swift", from: "0.1.0"),
```

Then depend on the library the app uses, eg `.product(name: "ArcaMasthead", package: "arca_swift")`. No release is tagged yet.

## Building and testing

```sh
swift build
swift test
swift format lint --strict --recursive Package.swift Sources Tests
```

A warning in the package's own code fails the build. CI runs the same three steps on every push and pull request, on GitHub's macOS 26 runners.

## Design

The design and its work packages are steel thread ST0001, kept with [Intent](https://github.com/matthewsinclair/intent) under `intent/`. Run `intent st show ST0001` to read it.

## Licence

MIT: see [LICENSE](LICENSE).
