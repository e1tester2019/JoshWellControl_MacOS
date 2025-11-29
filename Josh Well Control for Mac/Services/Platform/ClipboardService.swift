//
//  ClipboardService.swift
//  Josh Well Control
//
//  Platform-agnostic clipboard operations service
//

import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Service for handling clipboard operations in a platform-agnostic way
class ClipboardService {
    static let shared = ClipboardService()

    private init() {}

    /// Copy text to clipboard
    /// - Parameter text: The text to copy
    func copyToClipboard(_ text: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = text
        #endif
    }

    /// Get text from clipboard
    /// - Returns: The text from clipboard, if any
    func getFromClipboard() -> String? {
        #if os(macOS)
        return NSPasteboard.general.string(forType: .string)
        #elseif os(iOS)
        return UIPasteboard.general.string
        #else
        return nil
        #endif
    }

    /// Check if clipboard has text
    var hasText: Bool {
        #if os(macOS)
        return NSPasteboard.general.string(forType: .string) != nil
        #elseif os(iOS)
        return UIPasteboard.general.hasStrings
        #else
        return false
        #endif
    }
}
