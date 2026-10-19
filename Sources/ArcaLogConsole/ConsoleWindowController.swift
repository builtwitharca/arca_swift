import AppKit

/// A console's window (design.md "ArcaLogConsole"), AppKit and made in code: a
/// read-only text view of the console's lines, and a toggle for its quiet
/// ones.
///
/// **THE VIEW FOLLOWS THE END** as lines arrive, stops following while the
/// reader has scrolled up, and follows again once they are back at the
/// bottom.
///
/// **EACH BATCH IS ONE EDIT:** the batch's shown lines are added and what the
/// ring dropped is cut from the top, inside one text-storage edit, and the cut
/// counts lines, not newline runs (`ConsoleBuffer`).
@MainActor
final class ConsoleWindowController: NSWindowController {
  private weak var console: LogConsole?
  private let scrollView: NSScrollView
  private let textView: NSTextView
  private let quietToggle = NSButton(
    checkboxWithTitle: "Show quiet lines", target: nil, action: nil)
  private var theme: ConsoleTheme
  private var following = true

  /// How near the bottom, in points, still counts as at it.
  static let bottomSlack: CGFloat = 8

  init(console: LogConsole) {
    self.console = console
    self.theme = console.theme
    let window = ConsoleWindow(
      contentRect: NSRect(x: 0, y: 0, width: 920, height: 520),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    window.title = console.title
    window.isReleasedWhenClosed = false
    window.center()
    let scrollView = NSScrollView()
    self.scrollView = scrollView
    textView = NSTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
    super.init(window: window)
    window.console = console
    window.textView = textView
    layOut(in: window)
    quietToggle.state = console.showsQuietLines ? .on : .off
    restyle(theme, shown: console.shownLines)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  /// Brings the window forward, as the About window is, though the app may
  /// have no Dock icon.
  func show() {
    NSApp.activate()
    window?.makeKeyAndOrderFront(nil)
  }

  /// Takes `theme`, and shows `shown` in it.
  func restyle(_ theme: ConsoleTheme, shown: [ConsoleLine]) {
    self.theme = theme
    textView.backgroundColor = theme.background
    reload(shown)
  }

  /// One batch's edit, made inside one text-storage edit: the removals,
  /// last first so each range is still where the buffer counted it, then the
  /// additions at the end.
  func apply(_ edit: ConsoleBuffer.Edit) {
    guard let storage = textView.textStorage else { return }
    storage.beginEditing()
    for range in edit.removed.reversed() { storage.deleteCharacters(in: NSRange(range)) }
    storage.append(attributed(edit.added))
    storage.endEditing()
    if following { textView.scrollToEndOfDocument(nil) }
  }

  /// The whole of `shown`, after the filter or the theme changes, or the
  /// buffer changes other than at its ends.
  func reload(_ shown: [ConsoleLine]) {
    textView.textStorage?.setAttributedString(attributed(shown))
    if following { textView.scrollToEndOfDocument(nil) }
  }

  private func attributed(_ lines: [ConsoleLine]) -> NSAttributedString {
    let result = NSMutableAttributedString()
    for line in lines {
      result.append(
        NSAttributedString(
          string: ConsoleBuffer.rendered(line),
          attributes: [.font: theme.font, .foregroundColor: theme.colour(for: line.kind)]))
    }
    return result
  }

  // MARK: - The views

  private func layOut(in window: NSWindow) {
    textView.isEditable = false
    textView.isSelectable = true
    textView.isRichText = false
    textView.usesFindBar = true
    textView.isIncrementalSearchingEnabled = true
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.textContainer?.widthTracksTextView = true
    textView.textContainerInset = NSSize(width: 6, height: 6)
    scrollView.documentView = textView
    scrollView.hasVerticalScroller = true
    scrollView.borderType = .noBorder
    scrollView.contentView.postsBoundsChangedNotifications = true
    NotificationCenter.default.addObserver(
      self, selector: #selector(scrolled(_:)), name: NSView.boundsDidChangeNotification,
      object: scrollView.contentView)

    quietToggle.target = self
    quietToggle.action = #selector(toggleQuiet(_:))

    let content = NSView()
    for view in [scrollView, quietToggle] as [NSView] {
      view.translatesAutoresizingMaskIntoConstraints = false
      content.addSubview(view)
    }
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: content.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      quietToggle.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8),
      quietToggle.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
      quietToggle.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
    ])
    window.contentView = content
  }

  /// Follows the end while the view is at the bottom, and not once the
  /// reader has scrolled up.
  @objc private func scrolled(_ notification: Notification) {
    let clip = scrollView.contentView
    let bottom = (scrollView.documentView?.frame.height ?? 0) - clip.bounds.height
    following = clip.bounds.origin.y >= bottom - Self.bottomSlack
  }

  @objc private func toggleQuiet(_ sender: NSButton) {
    console?.showsQuietLines = sender.state == .on
  }
}

/// The console's window, which handles the console's keys itself, since a
/// library cannot count on its app's main menu: ⌘F and ⌘G (⇧⌘G back) for
/// Find, ⌘K to clear the console, and ⌘W to close.
final class ConsoleWindow: NSWindow {
  weak var console: LogConsole?
  weak var textView: NSTextView?

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    switch (event.charactersIgnoringModifiers?.lowercased(), flags) {
    case ("f", .command): find(.showFindInterface)
    case ("g", .command): find(.nextMatch)
    case ("g", [.command, .shift]): find(.previousMatch)
    case ("k", .command): console?.clear()
    case ("w", .command): performClose(nil)
    default: return super.performKeyEquivalent(with: event)
    }
    return true
  }

  /// Asks the text view's find bar for `action`, as a Find menu item would.
  private func find(_ action: NSTextFinder.Action) {
    let sender = NSMenuItem()
    sender.tag = action.rawValue
    textView?.performTextFinderAction(sender)
  }
}
