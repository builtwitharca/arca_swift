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

| App         | Heading             | Subheading                             | Stays the app's own rows                               |
| ----------- | ------------------- | -------------------------------------- | ------------------------------------------------------ |
| menuz       | `menuz <version>`   | `<commit> · <kind>`                    | none                                                   |
| Gtools.app  | `gtools <version>`  | `<commit> · <kind>`                    | its site row, with the estates as its flyout           |
| Intent.app  | `intent <version>`  | `<commit> · <kind>`                    | its intentd status row; opening the web face is a verb |
| Conflab.app | `conflab <version>` | the signed-in user, or `not signed in` | its conflabd status row, coloured by state             |

- **Gtools.app's and Intent.app's version and commit come from their CLI** (`gtools version`, `intent version`), as today. Until the CLI answers, the heading is the app's name.
- **The build word is always named:** `release` or `dev`.
- **Conflab.app's About tab** in its Settings window becomes its `about.md`.

## The Arca menu

The shape of an Arca app's menu below the masthead row. It is the layout hv chose for Gtools.app from mockups on 18 Oct 2026 and checked by eye on the installed app the same day, and hv made it the rule that menuz, Intent.app and Conflab.app take in their adoptions.

- **The masthead row is first,** with nothing above it.
- **The app's status row comes next, if it has one,** with no divider between it and the masthead.
  - Its title names what it reports on, and its second line gives that thing's state, in the masthead's style: a title over a smaller line.
  - A choice among like things hangs off it as a flyout, with the current one ticked, as Gtools.app's estates do.
  - The row is not itself an action. What opens the thing it names is a verb in the first group.
- **Then a divider, and groups,** one kind of thing to a group, with one divider between each and never two together:
  - first, the verbs on the thing the status row names, eg Open Site, then Restart Site and Stop Site, or Start Site;
  - then a group for each other kind of thing, eg search, or the tools such as Console… and Run Doctor;
  - in an app whose menu the user writes, as menuz's is, the user's entries are a section of their own, as the user's file writes them.
- **The app's own group is last:** Settings… (⌘,), Help, and Quit with the app's name (⌘Q). An app leaves out what it does not have, and keeps its own items here, eg menuz's Edit…, Log and Reload.
- **Titles:**
  - A title is a verb or a name, a single word where one will do, and similar things are grouped (hv, 18 Oct 2026).
  - A title ends in … when its item opens a window or asks for more.
  - A state is a row's second line and never part of a title. The one exception is the caption that stands in for a verb while it runs, eg Restarting…. No label such as "CMS" or "Estate:" goes into a title.
  - A notice, such as a refusal or a status that has not answered yet, is a disabled row of its own.
- **Images:** no row of the menu below the masthead has one. A flyout's rows may carry the mark that names each, as Gtools.app's estates do.
- **The adoptions:** Gtools.app has it. menuz, Intent.app and Conflab.app take it in WP-04, WP-06 and WP-07, from ic's briefs, and ic reviews each against this section.

## ArcaLogConsole

It was reviewed before any code (WP-08), as Masthead was. The review read Gtools.app's and Intent.app's consoles, which began as one copy and have drifted, and what menuz needs. hv agreed the shape below on 18 Oct 2026, with the review's conditions.

- **The line model:** `ConsoleLine(text, kind, source)`.
  - The kinds are log, error, warning, marker and quiet. Quiet lines are dimmed, and hidden when the app asks.
  - A line's source is an id the app gives, one for each file or command it follows, so a window can show several sources and replace one source's lines.
- **The classifier is the app's,** `(String) -> Kind`, since each daemon's log has its own tokens. The library gives two pieces: a start-of-line matcher for `error:`, `caused by:`, `warning:` and `remedy:`, and a skip of one leading RFC 3339 timestamp.
- **The ring:** bounded, 5000 lines by default, with clear() and the removal of one source's lines. WP-09 was to decide whether the capacity is per source or shared, since a shared ring lets a busy source evict a quiet one's lines: it keeps one buffer, with the quiet lines and the rest each bounded apart (see "As built"). The view counts lines, not newline runs.
- **The sources:**
  - **A file the app names, followed in-process.** A dispatch source watches the file and its directory, as menuz's config watcher does, and the file's identity and size are checked at each event.
    - A truncated file is read again from the start.
    - A renamed one is drained to its end, then the path is reopened when the new file appears, so lines written before the rename still arrive.
    - A log that does not exist yet is picked up when it does.
    - A bounded backlog, eg the last 40 lines, is replayed when the window opens.
    - There is no child process.
  - **A command's output,** for Run Doctor and Rebuild Search Index, and for a log only a CLI can render, eg `intent daemon logs --follow`, which merges two logs.
    - One pipe takes stdout and stderr, read through an AsyncStream.
    - stdin is held, so the child dies with the app.
    - The run is framed by `» cmd` and `» exit N · 1.2s`, and a second run is refused while one goes.
    - The launcher and the clock are injectable.
  - **The app's own notes,** as marker lines.
  - **One line assembler serves both.** Bytes are split on 0x0A, each complete line is decoded with bad bytes as U+FFFD, and a fragment is held until its newline arrives, so a character split across two reads stays one character.
  - **Reads happen off the main actor,** and the view gets one batch per event: one text-storage edit and one trim.
- **The window:** AppKit, built in code, with a read-only text view that follows the end and stops following when scrolled up.
  - Find (⌘F, ⌘G), Clear (⌘K) and Close (⌘W) are handled by the window itself, since a library cannot rely on the host's main menu.
  - The app gives a theme of colours and a font, and the library owns the default.
  - It is brought forward with NSApp.activate(), as the About window is.
  - A "show quiet lines" toggle filters in the view.
- **Tests:** Swift Testing.
  - The line model, the ring and the classifier helpers.
  - The file source, against temporary files: an append; a truncation; a truncation then a short append; a rename with the new file a moment later; a log missing at open and created later; a character split across two reads; and a last line with no newline. WP-09 added: a truncation that gives up the fragment held; a rename whose new file is there by the event; a log whose folders are missing at open; a replay and a read pass bounded by the window; a failure said once while it lasts, and again when it comes back or the follower starts again, with the memory that decides it as plain values; and the change each event decides, as a pure function.
  - The runner, against a stub launcher, and the process launcher against real children. WP-09 added: a signal; output a started process holds open; a cancelled run; dropped lines; and a followed command.
  - The window, by eye in an example app.
- **Its release is 0.2.0,** since it adds a product. An app moves its pin to `.upToNextMinor(from: "0.2.0")` when it adopts it.
- **The adoptions (WP-10):**
  - Gtools.app follows each site's log as a file source, or `gtools cms logs` as a command source, with its own classifier and its Verbose as quiet lines. Its console keeps following across a `cms start` that renames a log over 1 MB.
  - Intent.app runs `intent daemon logs --follow` as a command source.
  - menuz follows menuz.log as a file source, with no runs.

### As built (WP-09)

- **The buffer:** one buffer for all of a console's sources. Its quiet lines and the rest are each kept to the capacity apart, the oldest of each leaving first, so a console holds up to twice the capacity.
  - One ring for all lines would let a busy source's hidden request lines push a command's output out of a shared console, as Gtools.app's would be. Keeping the quiet lines apart stops that, at the cost of the second capacity.
  - The buffer gives the view one edit for each batch: the ranges it removes, last first, then the lines it adds. The order of the view's changes is so the buffer's, under test, rather than left to AppKit. A quiet line that leaves while quiet lines show is cut from inside the text.
- **The classifier's pieces:** `ConsoleClassify.token` also reads `» ` as a marker, and matches `error:`, `caused by:`, `warning:` and `remedy:` after an indent of spaces or tabs. Both are ported from Intent's console, so a log line that opens with `» ` takes the marker colour. `unstamped` skips one RFC 3339 timestamp, with `Z` or an offset.
- **The file source:**
  - The folder's source watches the nearest folder there is on the way to the file, so a log whose folders are not made yet is picked up too. Each source looks again once it is registered, for what changed before it could see it.
  - Each event's change is decided by one pure function, `FileChange.decide`, from the identity of the file open, the identity of the file at the path, the open file's size, and how far it has been read.
  - Each read pass is bounded by the read window, 256 KiB, as the replay is. When more lies ahead, as in a large new file, the pass reads the window's end of it alone, from the first line that starts there, and a marker line says how many bytes it passed over. No line is longer than 256 KiB: a longer run with no newline arrives in pieces.
  - A failure other than a file not there yet, such as a folder that cannot be read, is said as an error line, once while it lasts. It lasts while each event meets it, so one that an event goes without is said again when it comes back. A value of its own, `FailureMemory`, decides which failures to say, as `FileChange.decide` decides each event's change, and a stopped follower forgets them, so one started again says those that still hold.
  - The reads, the replay included, happen on the follower's own queue, and the console takes each batch on the main queue, in order.
- **The command source:**
  - A run and a followed command share one frame: `» ` and the label, then the lines, then `» exit N · 1.2s`, or `» killed by signal N · 1.2s` for a child a signal ended, for which `run` gives 128 and the signal, as a shell does.
  - At most 1024 reads of output wait for a console that has fallen behind. Past them the oldest are dropped and counted, and the console says `» N lines dropped`.
  - A run always ends. Two seconds after the child ends, output that a process it started still holds open is no longer read, a warning line says so, and the run ends.
  - A cancelled run stops its child, writes `» cancelled` and throws CancellationError. A console that stops reading a command, or is let go, stops it too.
- **The window:** a marker is blue, a fixed system colour, since the user's accent colour can be an error's red or a warning's orange. Its keys ignore Caps Lock.
- **The public surface:** `LogConsole`; the line model, `ConsoleLine` and `ConsoleSource`; and the classifier and its pieces, `ConsoleClassifier` and `ConsoleClassify`, which every app uses. Then, so an app or a test can give its own launcher, as the tests do: `ConsoleCommand`, `CommandEvent`, `LaunchedCommand`, `CommandLauncher` and `CommandLaunch`. `ConsoleError`, for what a run throws. And `ConsoleTheme`, for the app's own theme. The buffer, the file follower, the line assembler, the frame and the window are internal.
- **The limits:**
  - A truncation followed by a write that reaches past the old offset before the event is read reads as an append, so the start of the new content is lost.
  - Lines written to a renamed file after its rename's event are not read, since the old file is drained once and closed. WP-10's Gtools adoption therefore stops the old site before `cms start` renames its log.
  - While the reader has scrolled up and the console is full, each batch cuts lines from the top of the text, so the lines in view move up.
  - A folder that cannot be watched leaves the follower only the open file's own source: none at all when the file cannot be opened, or once it is renamed or removed with no new file at its path. Each failure is said once and nothing looks again, so permissions put right later pick nothing up. Following the file again recovers it.

### As built (WP-11)

What Gtools.app's console had and the package's lacked, added so that Gtools.app loses nothing when it adopts the package (Gtools' ST0018 WP-07). All of it is additive.

- **The footer:** the quiet lines' toggle, a label, and Copy All, under the text.
  - The label names what the console follows, in the order it began following each, then the command running: `following ~/Library/Logs/menuz.log · running gtools doctor`.
  - A file is named by its path, with the home folder written `~`. A command is named by its label until a line of its output gives a name through the app's `ConsoleNamer`, eg the file a `tailing <path>` line names, and then by the last name given.
  - A source stopped, or a followed command that ended, leaves the label.
- **Copy All** copies the text the window shows: each line it shows, as its text and a newline, so the quiet lines go only while they show. A pasteboard that refuses it gets a note in the console.
- **The quiet lines remembered:** a console made with `quietLinesKey` reads whether its quiet lines show from the app's defaults, and writes each change there, from the toggle or the app. Made with none, it writes nothing.
- **The window's close:** `onWindowClose` tells the app, so that it can stop a command it follows only while the window shows, as Gtools.app does with `gtools cms logs`, whose child would otherwise run for as long as the app.
- **A command the app ran itself:** `note(command:lines:status:)` frames its lines as a run's are, `» label` to `» exit N`, with no time, since the console did not time it. Gtools.app shows its `gtools url open` clicks that way, since it reads their output itself, for its url.log and its alert.
- **The window's frame** is saved under `ArcaLogConsole` and the console's title, so the window opens where it was last left, and in the middle of the screen the first time.
- **The grace:** a stopped child is given a moment to end on its own once its stdin closes, then terminated. `CommandLaunch.launcher(grace: nil)` terminates it at once, for a command that does not end when its stdin closes: Gtools.app's `gtools cms logs` runs its tail as a port of its own and ends only on a signal, so a stop, or the app quitting before the grace ran out, would leave it running.
- **The theme's appearance:** a theme can name the window's appearance, as Gtools.app's dark console does, so the footer matches the text whatever the system's mode.
- **The public surface** gains `ConsoleNamer`, `follow(command:as:classify:naming:)`, `quietLinesKey` and `defaults` on the initialiser, `onWindowClose`, `note(command:lines:status:classify:)`, `CommandLaunch.launcher(drain:grace:)` made public, and `ConsoleTheme.appearance`.

## The work

- **ic builds the package:** WP-01 to WP-03, then WP-08 and WP-09.
- **The roll-out is selective, app by app** (WP-04 to WP-07, and WP-10). Each app's adoption is done by its own project's IC, from ic's brief, in its own repo and under its own gates. ic reviews each adoption against its brief.
- **Masthead comes first, then LogConsole.**
