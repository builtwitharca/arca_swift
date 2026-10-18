import AppKit
import SwiftUI
import WebKit

/// The About window (design.md "The About window"): one window, shown again
/// with a new page at each open, and brought forward though the app has no
/// Dock icon. The page goes when the window closes, and its WebKit process
/// with it.
@MainActor
final class AboutWindow: NSObject, NSWindowDelegate {
  private var window: NSWindow?

  /// Shows `page` in the window, titled `title`.
  func show(_ page: WebPage, title: String) {
    let window = self.window ?? made()
    window.title = title
    window.contentView = NSHostingView(
      rootView: WebView(page).webViewLinkPreviews(.disabled).webViewBackForwardNavigationGestures(.disabled))
    self.window = window
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
  }

  func windowWillClose(_ notification: Notification) {
    window?.contentView = nil
  }

  /// The window, centred the first time and where the user left it after.
  private func made() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.center()
    window.setFrameAutosaveName("ArcaMasthead.About")
    return window
  }
}
