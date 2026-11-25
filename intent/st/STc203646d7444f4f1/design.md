# arca_swift carries the menu bar apps' copies (its issue 0003), and menuz uses them (Utilz issue 0114)

ic's design, 25 Nov 2026, for vc's read before any code. hv's word, relayed by vc: 0114 is "Fix now, in 2.15.0". Facts are in `~/Devel/scratch/utilz-ic/arca0003/facts.md` (read at arca_swift c005f28 and Utilz fa4ce418). Sizes: 0003 S, 0114 S to M.

## What it is for

menuz stops carrying its own copies of three fixes and gains a single-instance guard. arca_swift carries them once, for every menu bar app that pins it. A second menuz launch says that menuz already runs, and quits.

## arca_swift 0.3.0 (its issue 0003)

### 1. The row asks for its image (ArcaMasthead)

- MastheadRow's designated init sets `preferredImageVisibility` to `.visible` (raw value 1) by key, when the item responds to `setPreferredImageVisibility:`. This is menuz's `drawsImage(_:)`, moved. Every row gets it, and no adopter call is needed.
- By key, because the property is new in the macOS 27 SDK, and a named reference does not compile against an older SDK.
- Test: a made row reads back 1, where the selector exists.

### 2. The row's icon can come from the bundle's icon file (ArcaMasthead)

- The public init gains `appIcon: MastheadRow.AppIcon = .application`.
  - `.application` is the behaviour today: `NSApp.applicationIconImage`.
  - `.bundleFile` reads the file that the bundle's `CFBundleIconFile` names, by URL, never by name. This is menuz's `setAppIcon(bundle:)`, moved.
  - With `.bundleFile`, a missing key or a file that is not an image falls back to `.application`. The row's RefusalLog says why, once.
- The row's icon closure reads the file. `NSApp.applicationIconImage` is not changed. arca_swift's About window takes its icon through that same closure, so it is fixed too.
- Why opt in: Gtools sets its icon by name, and the example sets its icon from `Bundle.module`. A default of `.bundleFile` could change their rows when they move to 0.3.0.
- Tests: menuz's `iconNote` and `iconKept` cases move here. They use Scratch's fake bundle: a key and a file, no key, a missing file, and a file that is not an image.

### 3. ArcaLaunch, a new product: the test-host check and the instance lock

The adopter's `applicationDidFinishLaunching` makes one call first:

```swift
guard ArcaLaunch.begin(app: "Menuz", log: { Log.write($0) }) else { return }
```

`applicationWillTerminate` starts with `guard ArcaLaunch.launched else { return }`.

`begin` makes one decision. It is Conflab's `LaunchDecision`, moved, with Conflab's tests:

- **Test host**: `XCTestConfigurationFilePath` is present, whatever its value, an empty value included (0003's measure under Xcode 27.1). `begin` returns false and takes no lock.
- **Launch**: it takes the instance lock, holds it for the life of the process, and returns true.
- **Hand over**: another copy holds the lock. `begin` writes "<app> already runs as pid N, so this copy quits. To run this one, quit that copy first." to stderr and to `log`, then calls `NSApp.terminate(nil)`, and returns false. With no live pid recorded, the words leave "as pid N" out.
- **Launch unlocked**: the lock could not be taken for another reason, eg the folder cannot be made. It logs why, launches, and returns true.

The lock keeps Conflab's contract (its ST0125 design, decision 7):

- The file is `~/Library/Application Support/<app>/instance.lock`, shared by Debug and Release.
- The holder opens it with `O_RDWR | O_CREAT | O_CLOEXEC` at 0600 and takes `flock(LOCK_EX | LOCK_NB)`.
- It writes its pid at offset 0, as decimal digits and one newline. It never removes the file.
- A reader opens it with `O_RDONLY | O_CLOEXEC`, never creates it, and probes with `LOCK_SH | LOCK_NB`.
- arca_swift ships no reader.

The code is pure, then impure:

- `decide(environment:acquire:)` and the hand-over's words are pure.
- `begin` carries out the decision.

Tests: Conflab's LaunchDecisionTests and TestHostTests, on a scratch lock file:

- the test host takes no lock;
- a second copy is refused, with the pid;
- the raw bytes;
- no pid recorded yet, and a stale pid;
- a path that cannot hold a lock;
- a child started with `posix_spawn` does not keep the lock.

### 4. Docs, CI and the release

- README:
  - Adopting gains ArcaLaunch's call and `appIcon: .bundleFile`.
  - The stale "Xcode 26.6" and "macOS 26 runners" line is corrected to Xcode 27.1.
- CHANGELOG gains `[0.3.0]`.
- CI's adopter job lists its products by hand. It gains ArcaLaunch and its import, so CI proves that an adopter app builds with it.
- 0.3.0, not 0.2.2, because it adds a product (ST0001 design.md:128).
- The tag is annotated, "ArcaLaunch 0.3.0", on the commit that lands it. The tag and the push are hv's, through vc.

## menuz (Utilz issue 0114)

1. **The pin.** In `project.yml`, arca_swift goes to `minorVersion: 0.3.0`, and the products gain ArcaLaunch. The project is made again through the shim. The tracked `Package.resolved` at the workspace path moves to 0.3.0's revision. MenuzKit's own `Package.resolved` keeps its own graph.
2. **The row.**
   - `Masthead.row(...)` makes `MastheadRow(app: "menuz", ..., appIcon: .bundleFile)`.
   - `drawsImage(_:)`, `setAppIcon(bundle:)` and their helpers go.
   - `row`'s `note:` parameter goes if nothing else uses it.
3. **The launch.**
   - `isTestHost(_:)` goes.
   - `applicationDidFinishLaunching` starts with the `ArcaLaunch.begin` guard.
   - `applicationWillTerminate` starts with `guard ArcaLaunch.launched`.
   - The CLI arms in `main()` run before NSApplication. So `menuz --render` and the other arms never take the lock, and they still run beside the app.
4. **Tests.**
   - TestHostTests keeps its `skipped` case: under the test host, the delegate makes no status item.
   - IdentityRowTests keeps `appIcon`: menuz's real row draws a 32x32 icon that is not blank. Its `drawsImage` case becomes "the row asks for its image".
   - `iconNote` and `iconKept` go to arca_swift.
5. **The guard and menuz's install.**
   - `quit_all` in `opt/menuz/menuz` (:841) already quits every running Menuz, and waits for each to exit, before it opens the new copy. A new copy therefore never hands over to the old one.
   - A Debug build opened while the installed copy runs hands over. help/menuz.md's "Which build" says so.
6. **help/menuz.md** says that a second launch quits, and why. The CHANGELOG lines go to vc for dc.

## Threads and records

- **arca_swift:** a new thread for 0003, with this design attached. It has one WP: the row's two fixes and ArcaLaunch. arca_swift's 0003 closes when hv has tagged 0.3.0 and pushed.
- **Utilz:** a new thread for 0114, with this design attached. It has one WP: the pin, the row, the launch, the tests and help. 0114 closes when the thread lands.
- ic writes both, each in a worktree of its own repo, and commits by path, ending each message with the (C) line.

## Runs (each booked at the Desk, with its driver's path)

1. **R1, heavy, arca_swift's worktree.**
   - The red leg: the new tests over the base sources. Each must fail at its own assertion.
   - Then green, with `ARCA_SWIFT_STRICT=1`: `swift format lint --strict`, `swift build --build-tests` and `swift test --skip-build`.
2. vc lands arca_swift. hv pushes main and tags 0.3.0 in one step. arca_swift's CI runs its test and adopter jobs on that push.
3. **R2, heavy, Utilz's worktree at the new pin.**
   - `bin/utilz menuz build --unsigned`, then `bin/utilz menuz test --unsigned`.
   - menuz's bats run too, if help/menuz.md's change reaches them.
4. **CI:** a menuz-app dispatch on the pushed main. It is the only proof of a pin under Xcode 27.1.
5. **hv's hands, once,** on the installed build:
   - The masthead row shows its image and menuz's icon.
   - A second copy, opened with `open -n`, says that menuz already runs, and quits.

## For vc

- **(a) The icon: opt in (recommended), or a default.** Opt in changes no other adopter. A default of `.bundleFile` saves menuz one argument, but it can change the row in Gtools and the example.
- **(b) One run for both repos, or two.** Two runs (recommended): R2 needs the tag. A single run would need a local-path pin of arca_swift in a scratch `project.yml`, and an Xcode build with a local package rewrites a tracked `Package.resolved` (Utilz memory, 19 Oct 2026).
- **(c) Who lands in arca_swift.** It has no whiteboard. ic proposes that vc lands it, as for Utilz, by the change's hash. The tag and the push are hv's.
