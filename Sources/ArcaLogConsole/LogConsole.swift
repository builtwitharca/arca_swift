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

  private var buffer: ConsoleBuffer
  private let launcher: CommandLauncher
  private let now: @Sendable () -> ContinuousClock.Instant
  private var followed: [ConsoleSource: (follow: Follow, token: Int)] = [:]
  private var tokens = 0
  private var window: ConsoleWindowController?

  private enum Follow {
    case file(FileFollower)
    case command(LaunchedCommand, Task<Void, Never>)
  }

  /// The label of the command running now, or nil.
  public private(set) var running: String?

  /// The lines the console keeps, oldest first.
  public var lines: [ConsoleLine] { buffer.lines }

  /// The lines the window shows, oldest first.
  var shownLines: [ConsoleLine] { buffer.shown }

  /// Whether the quiet lines show. The window's toggle sets it, and so may
  /// the app.
  public var showsQuietLines: Bool {
    get { buffer.showsQuiet }
    set {
      let shown = buffer.showQuiet(newValue)
      window?.reload(shown)
    }
  }

  public init(
    title: String, capacity: Int = LogConsole.defaultCapacity, theme: ConsoleTheme = .standard,
    launcher: @escaping CommandLauncher = CommandLaunch.process,
    now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }
  ) {
    self.title = title
    self.theme = theme
    self.buffer = ConsoleBuffer(capacity: capacity)
    self.launcher = launcher
    self.now = now
  }

  // MARK: - Commands

  /// Runs `command`, its lines from `source`, or from the command's own source
  /// when none is named, framed by `» ` and its label and by
  /// `» exit N · 1.2s`, and gives its exit status.
  ///
  /// **A NON-ZERO EXIT IS NOT THROWN:** the command's own lines say what went
  /// wrong. **ONE AT A TIME, REFUSED RATHER THAN QUEUED:** a second run while
  /// one goes throws `busy`, naming the first, before it writes anything. A
  /// command that cannot launch, or whose output ends with no exit status,
  /// throws too, after its reason and a `» failed` marker.
  @discardableResult
  public func run(
    _ command: ConsoleCommand, as source: ConsoleSource? = nil,
    classify: @escaping ConsoleClassifier = ConsoleClassify.standard
  ) async throws -> Int32 {
    let source = source ?? ConsoleSource(command.label)
    if let running { throw ConsoleError.busy(running) }
    running = command.label
    defer { running = nil }
    append([.marker(command.label, source: source)])
    let started = now()
    let launched: LaunchedCommand
    do {
      launched = try launcher(command)
    } catch {
      append([
        ConsoleLine(text: error.localizedDescription, kind: .error, source: source),
        .marker("failed", source: source),
      ])
      throw error
    }
    var status: Int32?
    for await event in launched.events {
      switch event {
      case .lines(let texts):
        append(texts.map { ConsoleLine(text: $0, kind: classify($0), source: source) })
      case .exited(let code): status = code
      }
    }
    guard let status else {
      let error = ConsoleError.noExitStatus(command.label)
      append([
        ConsoleLine(text: error.localizedDescription, kind: .error, source: source),
        .marker("failed", source: source),
      ])
      throw error
    }
    append([.marker(Self.exitMarker(status, after: now() - started), source: source)])
    return status
  }

  /// `exit 0 · 1.2s`.
  nonisolated static func exitMarker(_ status: Int32, after elapsed: Duration) -> String {
    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    return "exit \(status) · \(String(format: "%.1f", seconds))s"
  }

  /// The app's note, as a marker line from the app.
  public func note(_ text: String) {
    append([.marker(text)])
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
      DispatchQueue.main.async {
        MainActor.assumeIsolated { self?.received(batch, from: source, token: token) }
      }
    }
    followed[source] = (.file(follower), token)
    follower.start()
  }

  /// Follows a command's output as `source`, eg `intent daemon logs --follow`
  /// for a log only its CLI can render: its lines as they come, until it
  /// exits or `stopFollowing` stops it. The source's earlier lines are
  /// dropped once it has launched.
  public func follow(
    command: ConsoleCommand, as source: ConsoleSource,
    classify: @escaping ConsoleClassifier = ConsoleClassify.standard
  ) throws {
    stopFollowing(source)
    let launched = try launcher(command)
    let token = restart(source)
    let reader = Task { [weak self] in
      for await event in launched.events {
        guard let self, !Task.isCancelled else { return }
        switch event {
        case .lines(let texts):
          self.received(
            texts.map { ConsoleLine(text: $0, kind: classify($0), source: source) }, from: source,
            token: token)
        case .exited(let status):
          self.received(
            [.marker("\(command.label) exited \(status)", source: source)], from: source,
            token: token)
          self.followed[source] = nil
        }
      }
    }
    followed[source] = (.command(launched, reader), token)
  }

  /// Stops following `source`. Its lines stay.
  public func stopFollowing(_ source: ConsoleSource) {
    switch followed.removeValue(forKey: source)?.follow {
    case .file(let follower): follower.stop()
    case .command(let launched, let reader):
      reader.cancel()
      launched.stop()
    case nil: break
    }
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

  private func append(_ batch: [ConsoleLine]) {
    guard !batch.isEmpty else { return }
    let edit = buffer.append(batch)
    window?.apply(edit)
  }
}
