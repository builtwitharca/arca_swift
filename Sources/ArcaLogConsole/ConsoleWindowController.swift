import AppKit

/// A console's window (design.md "ArcaLogConsole"), AppKit and made in code: a
/// read-only text view of the console's lines, over a footer that holds a
/// toggle for its quiet ones, what it follows, and Copy All (WP-11). It tells
/// the console when it closes.
///
/// **THE VIEW FOLLOWS THE END** as lines arrive, stops following while the
/// reader has scrolled up, and follows again once they are back at the
/// bottom.
///
/// **EACH BATCH IS ONE EDIT:** the batch's shown lines are added and what the
/// ring dropped is cut from the top, inside one text-storage edit, and the cut
/// counts lines, not newline runs (`ConsoleBuffer`).
@MainActor
final class ConsoleWindowController: NSWindowController, NSWindowDelegate {
  private weak var console: LogConsole?
  private let scrollView: NSScrollView
  private let textView: NSTextView
  private let quietToggle = NSButton(
    checkboxWithTitle: "Show quiet lines", target: nil, action: nil)
  /// What the console follows and the command running (WP-11).
  private let followingLabel = NSTextField(labelWithString: "")
  private let copyButton = NSButton(title: "Copy All", target: nil, action: nil)
  private var theme: ConsoleTheme
  private var following = true

  /// How near the bottom, in points, still counts as at it.
  private static let bottomSlack: CGFloat = 8

  init(console: LogConsole) {
    self.console = console
    self.theme = console.theme
    let window = ConsoleWindow(
      contentRect: NSRect(x: 0, y: 0, width: 920, height: 520),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    window.title = console.title
    window.isReleasedWhenClosed = false
    // The window opens where it was last left, under a name its title gives,
    // and in the middle of the screen the first time (WP-11).
    window.setFrameAutosaveName("ArcaLogConsole \(console.title)")
    if !window.setFrameUsingName(window.frameAutosaveName) {
      window.center()
    }
    let scrollView = NSScrollView()
    self.scrollView = scrollView
    textView = NSTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
    super.init(window: window)
    window.console = console
    window.textView = textView
    window.delegate = self
    layOut(in: window)
    quietToggle.state = console.showsQuietLines ? .on : .off
    showFooter(console.footer)
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
    window?.appearance = theme.appearance.flatMap { NSAppearance(named: $0) }
    textView.backgroundColor = theme.background
    // Below a short log the scroll view shows its own background.
    scrollView.backgroundColor = theme.background
    reload(shown)
  }

  /// Shows the quiet lines or hides them: the toggle follows, whoever set
  /// it, and `shown` is shown.
  func showQuiet(_ visible: Bool, shown: [ConsoleLine]) {
    quietToggle.state = visible ? .on : .off
    reload(shown)
  }

  /// Shows `text` in the footer, and whole in its tooltip, since a long path
  /// is cut in the middle.
  func showFooter(_ text: String) {
    followingLabel.stringValue = text
    followingLabel.toolTip = text.isEmpty ? nil : text
  }

  /// Tells the console, which tells the app.
  func windowWillClose(_ notification: Notification) {
    console?.windowDidClose()
  }

  /// One batch's edit, made inside one text-storage edit: the removals in
  /// the buffer's order, last first, so each range is still where the buffer
  /// counted it, then the additions at the end.
  func apply(_ edit: ConsoleBuffer.Edit) {
    guard let storage = textView.textStorage else { return }
    storage.beginEditing()
    for range in edit.removed { storage.deleteCharacters(in: NSRange(range)) }
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
    followingLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    followingLabel.textColor = .secondaryLabelColor
    followingLabel.lineBreakMode = .byTruncatingMiddle
    // The label gives way first, so that the toggle and the button keep
    // their size in a narrow window, and fills the space between them.
    followingLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    followingLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    copyButton.target = self
    copyButton.action = #selector(copyAll(_:))
    copyButton.toolTip = "Copy every line the console shows"

    let footer = NSStackView(views: [quietToggle, followingLabel, copyButton])
    footer.orientation = .horizontal
    footer.alignment = .centerY
    footer.spacing = 12
    footer.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

    let content = NSView()
    for view in [scrollView, footer] as [NSView] {
      view.translatesAutoresizingMaskIntoConstraints = false
      content.addSubview(view)
    }
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: content.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      footer.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
      footer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      footer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      footer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
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

  @objc private func copyAll(_ sender: NSButton) {
    console?.copyAll()
  }
}

/// The console's window, which handles the console's keys itself, since a
/// library cannot count on its app's main menu: ⌘F and ⌘G (⇧⌘G back) for
/// Find, ⌘K to clear the console, and ⌘W to close.
private final class ConsoleWindow: NSWindow {
  weak var console: LogConsole?
  weak var textView: NSTextView?

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    // The modifiers alone, so Caps Lock or a function key changes nothing.
    let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
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
