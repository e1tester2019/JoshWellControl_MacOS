import SwiftUI
import AppKit

final class WindowHost<Content: View>: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let rootView: Content
    private let title: String
    private let minSize: NSSize

    init(title: String, minSize: NSSize = NSSize(width: 900, height: 600), @ViewBuilder content: () -> Content) {
        self.rootView = content()
        self.title = title
        self.minSize = minSize
    }

    func show() {
        if window == nil {
            let hosting = NSHostingView(rootView: rootView)
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: minSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
            w.title = title
            w.isReleasedWhenClosed = false
            w.contentView = hosting
            w.minSize = minSize
            w.center()
            w.delegate = self
            self.window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Keep the host alive if needed; set window to nil so show() can recreate if GC'd
        self.window = nil
    }
}
