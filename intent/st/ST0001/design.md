# ST0001 design: shared Swift libraries for the menu bar apps

As agreed with hv, 18 Oct 2026.

## The package

- **One Swift package,** `arca_swift`, for macOS 26 and later, in the Swift 6 language mode, built with the current toolchain.
- **Library products, each imported on its own:**
  - `ArcaMasthead`: the top line and the About window.
  - `ArcaLogConsole`: the log console.

  Module names carry the `Arca` prefix because a module name must be unique across an app's dependencies.
- **One internal target, `ArcaCore`,** holds what both libraries read:
  - a config file found in the app's config folder or, failing that, in its bundle;
  - YAML, read through Yams;
  - `{token}` templates.

  So neither library grows its own reader.
- **Dependencies:** Yams, and Apple's swift-cmark (cmark-gfm) for Markdown.
- **A pure core, tested with Swift Testing, and a thin AppKit and SwiftUI layer** that parses, calls and renders.
- **CI on GitHub Actions' macOS runners,** which are free for a public repo, builds and tests every push. A release is a tag, and the apps pin it.

## ArcaMasthead

### The row

- **One menu item at the top of the app's menu:** the heading as its title in bold, the subheading as its subtitle, and the app's icon as its image. macOS draws it, so highlighting, clicks and the keyboard work as for any other item. A subtitle under an attributed title shows from macOS 15.
- **It is enabled,** and choosing it opens the About window.

### The file

- **`masthead.yaml` lives in the app's config folder** (eg `~/.config/<app>/`). Without one, the default the app ships in its bundle is used. Nothing in the bundle is edited, because that breaks the app's signature.
- **A sketch of the file:**

  ```yaml
  heading: "{name} {version}"
  subheading: "{commit} · {kind}"
  icon: app
  about:
    body: about.md # or about.html
    css: about.css # optional
  ```

- **Values:**
  - The bundle gives `{name}`, `{version}`, `{commit}` and `{kind}`.
  - The app names its own once, eg `{status}` or `{user}`, and is asked for their values at each menu open. Naming one of the bundle's takes its place.
  - A value the app cannot give yet leaves the heading as the app's name alone, and hides a subheading that names it. Each line stands on its own.
- **The file is read again** each time the menu or the About window opens, so nothing watches it.
- **A file that fails keeps the bundled default,** and the subheading says what is wrong. The app's log hook gets the same line.

### The About window

- **A window holding WebKit's SwiftUI web view** (`WebPage`), which needs macOS 26.
- **Markdown becomes HTML through cmark-gfm,** and HTML inside it passes through. An `about.html` is used as written.
- **The page's JavaScript is off.** A link opens in the browser, the default stylesheet follows light and dark mode, and `{tokens}` expand in the body.
- **The page loads nothing from outside.** Its Content-Security-Policy allows only its own styles, `data:` images and the images the body names by file name, which the app serves from the config folder or the bundle. Any navigation other than a link opened in the browser is cancelled.
- **An app with no Dock icon is brought forward** to show the window.

### The four apps

| App         | Heading             | Subheading                             | Stays the app's own rows                                     |
| ----------- | ------------------- | -------------------------------------- | ------------------------------------------------------------ |
| menuz       | `menuz <version>`   | `<commit> · <kind>`                    | none                                                         |
| Gtools.app  | `gtools <version>`  | `<commit> · <kind>`                    | its CMS status row, which opens the site; its estate flyout  |
| Intent.app  | `intent <version>`  | `<commit> · <kind>`                    | its intentd status row, which opens the web face             |
| Conflab.app | `conflab <version>` | the signed-in user, or `not signed in` | its conflabd status row, coloured by state, in Gtools' shape |

- **Gtools.app's and Intent.app's version and commit come from their CLI** (`gtools version`, `intent version`), as today. Until the CLI answers, the heading is the app's name.
- **The build word is always named:** `release` or `dev`.
- **Conflab.app's About tab** in its Settings window becomes its `about.md`.

## ArcaLogConsole

It is reviewed before any code (WP-08), as Masthead was. The review measures how Gtools.app's and Intent.app's consoles differ, and covers:

- the CLI runs whose only output is the console, eg Run Doctor and Rebuild Search Index;
- a daemon's log, tailed while the window is open;
- menuz's run log, which must keep being followed when it is truncated or rotated under the tail.

## The work

- **ic builds the package:** WP-01 to WP-03, then WP-08 and WP-09.
- **The roll-out is selective, app by app** (WP-04 to WP-07, and WP-10). Each app's adoption is done by its own project's IC, from ic's brief, in its own repo and under its own gates. ic reviews each adoption against its brief.
- **Masthead comes first, then LogConsole.**
