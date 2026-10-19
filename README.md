<p align="center"><img src="design/icons/arca_swift-icon.svg" width="128" height="128" alt="The arca_swift icon: a swift rising out of the Arca box"></p>

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
.package(url: "https://github.com/builtwitharca/arca_swift", .upToNextMinor(from: "0.1.1")),
```

Then depend on the library the app uses, eg `.product(name: "ArcaMasthead", package: "arca_swift")`. Until 1.0 a minor release may change the API, so pin the minor version, as above.

## masthead.yaml

An app that uses `ArcaMasthead` ships a `masthead.yaml` in its bundle's resources. Its user can put their own in the app's config folder, `${XDG_CONFIG_HOME:-$HOME/.config}/<app>/`, with no rebuild. The user's copy is used when it passes its checks. One that does not leaves the bundle's in use, and the subheading says what is wrong.

```yaml
heading: "{name} {version}"
subheading: "{commit} · {kind}"
icon: app
about:
  body: about.md
  css: about.css
```

| Key          | What it holds                                                |
| ------------ | ------------------------------------------------------------ |
| `heading`    | The top line. Required.                                      |
| `subheading` | The smaller line under it.                                   |
| `icon`       | `app` for the app's icon, which is the default, or `none`.   |
| `about.body` | The About window's page, a `.md` or `.html` file. Required.  |
| `about.css`  | A stylesheet laid over the window's own.                     |

The About files are found as `masthead.yaml` is: the config folder's copy first, then the bundle's. So a user can replace the page and keep the rest.

Each `{token}` takes a value. The bundle gives four, from the app's Info.plist, and the app can add its own values or replace these.

| Token       | Info.plist key               |
| ----------- | ---------------------------- |
| `{name}`    | `CFBundleName`               |
| `{version}` | `CFBundleShortVersionString` |
| `{commit}`  | `ArcaCommit`                 |
| `{kind}`    | `ArcaKind`                   |

Each line stands on its own. Until the heading's values are there, it is the app's name alone, and until the subheading's are, it is hidden; a line that comes out blank is treated the same way. A token in the heading or the subheading that names no value is refused. In the About page each value is escaped for HTML, so a value never becomes markup in text or in a quoted attribute: put an attribute's value in quotes. A token in a Markdown link's address is left as written, since cmark-gfm percent-encodes its braces, so write that link in HTML.

## The row and the About window

An app makes one `MastheadRow`, a menu item, and puts it at the top of its menu, which keeps it. The row reads `masthead.yaml` again each time that menu opens, and choosing it opens the About window.

```swift
import ArcaMasthead

let row = MastheadRow(
  app: "gtools", owned: ["version", "commit"], value: { stamp[$0] }, log: { logger.warning("\($0)") })
menu.insertItem(row, at: 0)
```

- `app` names the config folder, `${XDG_CONFIG_HOME:-$HOME/.config}/<app>/`. A GUI app is given none of the user's environment, so an app that captures its login shell's passes it as `environment`.
- `bundle` holds the defaults, `masthead.yaml` and the About files. It is the app's own bundle unless the app passes another.
- `owned` names the values the app gives, and `value` is asked for each of them at every open. nil means the app has not got that value yet.
- `log` gets each refusal once, when it first appears, and again only after a read without it.

The About page is the body, under the window's own stylesheet and the app's. The window's follows light and dark mode, and the app's is laid over it. What was refused is listed above the body.

The page runs no JavaScript and loads nothing from outside. Its policy allows only its own styles, `data:` images and the images the app serves. An image the body names by a file name, as in `![logo](logo.png)`, is found as the About files are: the config folder's copy first, then the bundle's. The name must be a `.png`, `.jpg`, `.jpeg`, `.gif`, `.webp` or `.svg` file with no folder in it.

A link to an `http`, `https` or `mailto` address opens in the browser. Every other navigation is cancelled.

`ArcaMastheadExample` is an app that shows both. Run it with `swift run ArcaMastheadExample`, adding `--about` to open the window as it starts.

## Building and testing

```sh
ARCA_SWIFT_STRICT=1 swift build
ARCA_SWIFT_STRICT=1 swift test
swift format lint --strict --recursive Package.swift Sources Tests
```

With `ARCA_SWIFT_STRICT` set, to any value, a warning in the package's own code fails the build. Set it on each command, as above, rather than exporting it: the manifest reads it from the environment of whatever builds the package, and an app built from a shell that exports it could get the setting too. CI runs the same three steps with it set, on every push and pull request, on GitHub's macOS 26 runners. CI also builds an app that depends on the package without it, with xcodebuild and Xcode 26.6, as the apps build it.

## Design

The design and its work packages are steel thread ST0001, kept with [Intent](https://github.com/matthewsinclair/intent) under `intent/`. Run `intent st show ST0001` to read it.

## Licence

MIT: see [LICENSE](LICENSE).
