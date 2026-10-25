import AppKit

/// A console: the buffer of its sources' lines, the commands it runs, the app's
/// notes, and its window (design.md "ArcaLogConsole"). An app makes one for
/// each log it shows, follows a file or a command in it, runs its one-off
/// commands there, and shows its window from a menu item.
@MainActor
public final class LogConsole {
  /// The lines a console keeps by default.
  public static let defaultCapacity = ConsoleBuffer.defaultCapacity

  public let title: String
  /// The window's colours and font.
  public var theme: ConsoleTheme {
    didSet { window?.restyle(theme, shown: buffer.shown) }
  }

  /// Told when the console's window closes, so that the app can stop a
  /// command it follows only while the window shows (WP-11). Following it
  /// again when the window shows again is the app's to do.
  public var onWindowClose: (@MainActor () -> Void)?

  private var buffer: ConsoleBuffer
  private let launcher: CommandLauncher
  private let now: @Sendable () -> ContinuousClock.Instant
  /// The key the quiet lines' toggle is remembered under, if any.
  private let quietLinesKey: String?
  private let defaults: UserDefaults
  private var followed: [ConsoleSource: Followed] = [:]
  private var tokens = 0
  private var window: ConsoleWindowController?

  /// The label of the command running now, or nil.
  public private(set) var running: String? {
    didSet { window?.showFooter(footer) }
  }

  /// The lines the console keeps, oldest first.
  var lines: [ConsoleLine] { buffer.lines }

  /// The lines the window shows, oldest first.
  var shownLines: [ConsoleLine] { buffer.shown }

  /// Whether the quiet lines show. The window's toggle sets it, and so may
  /// the app, whose setting the toggle then shows. A console made with a key
  /// writes each change under it.
  public var showsQuietLines: Bool {
    get { buffer.showsQuiet }
    set {
      let shown = buffer.showQuiet(newValue)
      if let quietLinesKey { defaults.set(newValue, forKey: quietLinesKey) }
      window?.showQuiet(newValue, shown: shown)
    }
  }

  /// The text the window shows, which is what its Copy All takes.
  var copyText: String { buffer.shownText }

  /// What the window's footer says: what the console follows, each by its
  /// name, in the order it began following them, then the command running.
  var footer: String {
    Self.footer(following: followed.values.sorted { $0.token < $1.token }.map(\.name), running: running)
  }

  /// `following` and `names`, then `running` and the command's label, or
  /// nothing when there is neither.
  static func footer(following names: [String], running: String?) -> String {
    var parts: [String] = []
    if !names.isEmpty { parts.append("following " + names.joined(separator: ", ")) }
    if let running { parts.append("running " + running) }
    return parts.joined(separator: " · ")
  }

  /// A followed file's name in the footer: its path, with `home` written ~.
  static func name(ofFile path: String, home: String = NSHomeDirectory()) -> String {
    if path == home { return "~" }
    let folder = home.hasSuffix("/") ? home : home + "/"
    return path.hasPrefix(folder) ? "~/" + path.dropFirst(folder.count) : path
  }

  /// A console titled `title`, which keeps `capacity` lines, and as many quiet
  /// ones apart. Made with `quietLinesKey`, it remembers under that key in
  /// `defaults` whether its quiet lines show, and starts as they were left.
  public init(
    title: String, capacity: Int = LogConsole.defaultCapacity, theme: ConsoleTheme = .standard,
    quietLinesKey: String? = nil, defaults: UserDefaults = .standard,
    launcher: @escaping CommandLauncher = CommandLaunch.process,
    now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }
  ) {
    self.title = title
    self.theme = theme
    self.quietLinesKey = quietLinesKey
    self.defaults = defaults
    self.buffer = ConsoleBuffer(
      capacity: capacity, showsQuiet: quietLinesKey.map { defaults.bool(forKey: $0) } ?? false)
    self.launcher = launcher
    self.now = now
  }

  deinit {
    // A console let go while it follows stops what it follows, or a
    // command's child would run on.
    for entry in followed.values { entry.follow.end() }
  }

  // MARK: - Commands

  /// Runs `command`, its lines from `source`, or from the command's own source
  /// when none is named, framed by `» ` and its label and by `» exit N · 1.2s`
  /// (`CommandFrame`), and gives its exit status, or, for a child a signal
  /// ended, 128 and the signal, as a shell gives it.
  ///
  /// **A NON-ZERO EXIT IS NOT THROWN:** the command's own lines say what went
  /// wrong. **ONE AT A TIME, REFUSED RATHER THAN QUEUED:** a second run while
  /// one goes throws `busy`, naming the first, before it writes anything. A
  /// command that cannot launch, or whose output ends with no exit status,
  /// throws too, after its reason and a `» failed` marker. **A CANCELLED RUN
  /// STOPS ITS CHILD,** then writes `» cancelled` and throws
  /// CancellationError.
  @discardableResult
  public func run(
    _ command: ConsoleCommand, as source: ConsoleSource? = nil,
    classify: @escaping ConsoleClassifier = ConsoleClassify.standard
  ) async throws -> Int32 {
    if let running { throw ConsoleError.busy(running) }
    running = command.label
    defer { running = nil }
    var frame = CommandFrame(
      label: command.label, source: source ?? ConsoleSource(command.label), classify: classify, started: now())
    append([frame.opening])
    let launched: LaunchedCommand
    do {
      launched = try launcher(command)
    } catch {
      append(frame.failed(error))
      throw error
    }
    var status: Int32?
    await withTaskCancellationHandler {
      for await event in launched.events {
        let taken = frame.take(event, dropped: launched.droppedLines(), now: now)
        append(taken.lines)
        status = taken.status ?? status
      }
    } onCancel: {
      launched.stop()
    }
    if let status { return status }
    if Task.isCancelled {
      append(frame.cancelled(dropped: launched.droppedLines()))
      throw CancellationError()
    }
    let error = ConsoleError.noExitStatus(command.label)
    append(frame.failed(error, dropped: launched.droppedLines()))
    throw error
  }

  /// The app's note, as a marker line from the app.
  public func note(_ text: String) {
    append([.marker(text)])
  }

  /// A command the app ran without the console, eg one whose output it reads
  /// itself, shown as a run is (WP-11), in the run's own frame: `» ` and
  /// `label`, then `lines`, each of the kind `classify` gives it, then `» exit`
  /// and `status`, untimed, all from the command's own source.
  public func note(
    command label: String, lines: [String], status: Int32,
    classify: @escaping ConsoleClassifier = ConsoleClassify.standard
  ) {
    let frame = CommandFrame(label: label, source: ConsoleSource(label), classify: classify, started: now())
    append(frame.noted(lines, exited: status))
  }

  // MARK: - Following

  /// Follows the file at `path` as `source`: its last `backlog` lines, then
  /// each line written to it, across a truncation and a rename. The source's
  /// earlier lines are dropped first, so a source followed again does not show
  /// its backlog twice.
  public func follow(
    file path: String, as source: ConsoleSource,
    classify: @escaping ConsoleClassifier = ConsoleClassify.standard,
    backlog: Int = 40
  ) {
    let token = restart(source)
    let follower = FileFollower(path: path, source: source, classify: classify, backlog: backlog) {
      [weak self] batch in
      // The main queue rather than a Task: it keeps the batches in the order
      // the follower sent them.
      DispatchQueue.main.async {
        MainActor.assumeIsolated { self?.received(batch, from: source, token: token) }
      }
    }
    followed[source] = Followed(follow: .file(follower), token: token, name: Self.name(ofFile: path))
    follower.start()
    window?.showFooter(footer)
  }

  /// Follows a command's output as `source`, eg `intent daemon logs --follow`
  /// for a log only its CLI can render: its lines as they come, framed as a
  /// run's are, until it ends or `stopFollowing` stops it. The source's
  /// earlier lines are dropped once it has launched. The window's footer
  /// names it by its label, or by the last name `naming` found in its lines.
  public func follow(
    command: ConsoleCommand, as source: ConsoleSource,
    classify: @escaping ConsoleClassifier = ConsoleClassify.standard,
    naming: ConsoleNamer? = nil
  ) throws {
    stopFollowing(source)
    let launched = try launcher(command)
    let token = restart(source)
    let opened = CommandFrame(label: command.label, source: source, classify: classify, started: now())
    append([opened.opening])
    let clock = now
    let reader = Task { [weak self] in
      var frame = opened
      for await event in launched.events {
        guard let self, !Task.isCancelled else { return }
        if let naming, case .lines(let texts) = event, let name = texts.compactMap(naming).last {
          self.named(source, name, token: token)
        }
        let taken = frame.take(event, dropped: launched.droppedLines(), now: clock)
        self.received(taken.lines, from: source, token: token)
        if taken.status != nil {
          self.ended(source, token: token)
          return
        }
      }
      guard let self, !Task.isCancelled else { return }
      let failure = frame.failed(ConsoleError.noExitStatus(command.label), dropped: launched.droppedLines())
      self.received(failure, from: source, token: token)
      self.ended(source, token: token)
    }
    followed[source] = Followed(follow: .command(launched, reader), token: token, name: command.label)
    window?.showFooter(footer)
  }

  /// Stops following `source`. Its lines stay.
  public func stopFollowing(_ source: ConsoleSource) {
    followed.removeValue(forKey: source)?.follow.end()
    window?.showFooter(footer)
  }

  /// Whether the console follows `source` now: from `follow` until it is
  /// stopped or, for a command, until the command ends (WP-11). An app that
  /// follows a command only while the window shows asks it before following
  /// again, so a tail that runs is kept and one that ended starts afresh.
  public func isFollowing(_ source: ConsoleSource) -> Bool {
    followed[source] != nil
  }

  /// Stops what `source` was following, drops its lines, and gives the token
  /// its new batches carry.
  private func restart(_ source: ConsoleSource) -> Int {
    stopFollowing(source)
    let before = buffer.lines.count
    let shown = buffer.removeAll(from: source)
    if buffer.lines.count != before { window?.reload(shown) }
    tokens += 1
    return tokens
  }

  /// A batch from a source still followed under `token`; a late one from a
  /// source stopped or followed again is dropped.
  private func received(_ batch: [ConsoleLine], from source: ConsoleSource, token: Int) {
    guard followed[source]?.token == token else { return }
    append(batch)
  }

  /// A name a followed command's line gave what it follows, for a source still
  /// followed under `token`.
  private func named(_ source: ConsoleSource, _ name: String, token: Int) {
    guard followed[source]?.token == token else { return }
    followed[source]?.name = name
    window?.showFooter(footer)
  }

  /// A followed command ended: its source is no longer followed, unless it
  /// has been followed again since.
  private func ended(_ source: ConsoleSource, token: Int) {
    if followed[source]?.token == token { followed[source] = nil }
    window?.showFooter(footer)
  }

  // MARK: - The buffer and the window

  /// Empties the console.
  public func clear() {
    buffer.clear()
    window?.reload([])
  }

  /// Shows the window, made on first use, and brings it forward.
  public func showWindow() {
    let window = self.window ?? ConsoleWindowController(console: self)
    self.window = window
    window.show()
  }

  /// The window closed: the app is told.
  func windowDidClose() {
    onWindowClose?()
  }

  /// Puts the text the window shows on `pasteboard`, for the window's Copy
  /// All, or says in a note that it could not.
  func copyAll(to pasteboard: NSPasteboard = .general) {
    pasteboard.clearContents()
    if !pasteboard.setString(copyText, forType: .string) {
      note("could not copy the console's lines")
    }
  }

  private func append(_ batch: [ConsoleLine]) {
    guard !batch.isEmpty else { return }
    let edit = buffer.append(batch)
    window?.apply(edit)
  }
}

/// One source a console follows: how, the token its batches carry, and its
/// name in the window's footer.
private struct Followed: Sendable {
  let follow: Follow
  let token: Int
  var name: String
}

/// What a console follows for one of its sources. It is outside the console,
/// so that the console's deinit, which is not on the main actor, can stop it.
private enum Follow: Sendable {
  case file(FileFollower)
  case command(LaunchedCommand, Task<Void, Never>)

  /// Stops it: the follower, or the command's reader and its child.
  func end() {
    switch self {
    case .file(let follower): follower.stop()
    case .command(let launched, let reader):
      reader.cancel()
      launched.stop()
    }
  }
}
