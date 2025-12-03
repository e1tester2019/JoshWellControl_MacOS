//
//  WindowService.swift
//  Josh Well Control
//
//  Platform-agnostic window/modal presentation service
//

import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#endif

/// Service for handling window and modal presentations in a platform-agnostic way
@MainActor
class WindowService {
    static let shared = WindowService()

    private init() {}

    /// Present a view modally
    /// On macOS: Creates a new window
    /// On iOS: Should use sheet presentation (handled by the caller)
    #if os(macOS)
    func presentModal<Content: View>(
        title: String,
        size: CGSize = CGSize(width: 800, height: 600),
        @ViewBuilder content: () -> Content
    ) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.center()
        window.contentView = NSHostingView(rootView: content())
        window.makeKeyAndOrderFront(nil)

        // Keep window alive
        window.isReleasedWhenClosed = false
    }
    #endif
}

/// iOS-friendly sheet presentation
/// Use this in SwiftUI views with .sheet() modifier instead of WindowHost
struct SheetPresentation<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let sheetContent: () -> SheetContent

    func body(content: Content) -> some View {
        #if os(macOS)
        content
        #elseif os(iOS)
        content
            .sheet(isPresented: $isPresented) {
                self.sheetContent()
            }
        #else
        content
        #endif
    }
}

extension View {
    /// Present content as a sheet on iOS or window on macOS
    func crossPlatformSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        self.modifier(SheetPresentation(isPresented: isPresented, sheetContent: content))
    }
}
