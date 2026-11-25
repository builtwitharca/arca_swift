# arca_swift carries the menu bar apps' copies (its issue 0003), and menuz uses them (Utilz issue 0114)

ic's design, 25 Nov 2026. r1 is approved as vc decision 118. r2 rewrites Runs from dc's read of the CI leg. hv's word, relayed by vc: 0114 is "Fix now, in 2.15.0". Facts are in `~/Devel/scratch/utilz-ic/arca0003/facts.md` (read at arca_swift c005f28 and Utilz fa4ce418). Sizes: 0003 S, 0114 S to M.

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
- The tag is annotated, "ArcaLaunch 0.3.0", on the commit that lands it. The push and the tag are hv's, through devbin-vc: main first, then the tag once CI is green on that commit (Runs, step 2).

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

## Runs, in order, each with what it waits on and who reads it

r2 takes dc's read r1 of the CI leg (`~/Devel/scratch/utilz-dc/arca0003-read/r1.md`, b8d373bd) and vc's ruling on it.

1. **R1, heavy, at the Desk, in arca_swift's worktree.**
   - Waits on: vc's read of r2 and of the red-leg list.
   - The red leg: each test arm as the list sorts it. An arm is red at the base by its own assertion, green at the base with a reason, or moved unchanged, with its origin file and proving commit.
   - Then green, with `ARCA_SWIFT_STRICT=1`: `swift format lint --strict`, `swift build --build-tests` and `swift test --skip-build`.
   - Reader: vc reads R1's END, then lands arca_swift by the change's hash.
2. **arca_swift's CI, before the tag.**
   - Waits on: vc's landing. hv pushes arca_swift's main alone, through devbin-vc.
   - The push starts CI's test job and its adopter job (ci.yml:5-13). The adopter job is the first build of ArcaLaunch as an app's dependency through Xcode, which no local run makes.
   - Reader: vc reads both jobs green on that commit (`gh run list -R builtwitharca/arca_swift --commit <sha>`, then the jobs). dc reads the CI leg.
   - Then hv tags 0.3.0 on that commit and pushes the tag. A red here costs a fix on main, not 0.3.1 and a second pin. 0.2.1 went this way, and it is Utilz's own rule (tests.yml:6-9).
3. **R2, heavy, at the Desk, in a Utilz worktree at the new pin.**
   - Waits on: the pushed tag, since the resolve fetches it from GitHub.
   - The resolve writes `Package.resolved`. It names 0.3.0's commit (`git rev-parse '0.3.0^{commit}'`), not the annotated tag's own object. The commit takes the file from what the resolve wrote.
   - Every file under `native/macos/Menuz` is hashed after the resolve and again after the build and test, so the pin is the one change.
   - `bin/utilz menuz build --unsigned`, then `bin/utilz menuz test --unsigned`. menuz's bats run too, if help/menuz.md's change reaches them.
   - This Mac's one Xcode is 27.2, the Xcode the 2.15.0 asset is built with, so R2 proves the build that ships.
   - Reader: vc reads R2's END, then lands 0114 by the change's hash.
4. **CI: the menuz-app dispatch, on Utilz's pushed main.**
   - Waits on: vc's landing of 0114, and hv's push of Utilz main.
   - vc sends `gh workflow run tests.yml --ref main` on devbin-vc's go (hv decision 20). If vc's session refuses it, hv runs it.
   - It proves the floor, Xcode 27.1 (project.yml's xcodeVersion), from a clean clone, and that the 0.3.0 pin resolves there. arca_swift's adopter job pins a revision (ci.yml:83), so only R2 and this run prove the pin.
   - Reader: vc reads menuz-app's conclusion from the jobs API, with its run_attempt. Baseline: menuz-app was green on dispatch 45403210925 (24 Nov 2026, Xcode 27.1), so a red here is this change's.
5. **hv's hands, once, on the build R2 proved.**
   - Waits on: R2's END. hv runs it, and tells vc what hv saw.
   - The masthead row shows its image and menuz's icon.
   - A second copy, opened with `open -n`, says that menuz already runs, and quits.

## vc's answers (vc decision 118)

- **(a) The icon is opt in.** It changes no other adopter.
- **(b) Two runs.** R2 needs the tag. A single run would need a local-path pin of arca_swift in a scratch `project.yml`, and an Xcode build with a local package rewrites a tracked `Package.resolved` (Utilz memory, 19 Oct 2026).
- **(c) vc lands arca_swift by the change's hash.** The push and the tag are hv's, through devbin-vc.
