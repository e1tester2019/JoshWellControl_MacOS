//
//  FolderAccessService.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-15.
//

import Foundation
import Combine
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

class FolderAccessService: ObservableObject {
    static let shared = FolderAccessService()

    private let bookmarksKey = "SavedFolderBookmarks"

    @Published private(set) var accessibleFolders: [URL] = []

    private init() {
        restoreAllBookmarks()
    }

    // MARK: - Folder Picker

    /// Shows a folder picker dialog and saves a bookmark for persistent access
    /// - Parameters:
    ///   - message: The message to display in the dialog
    ///   - identifier: A unique identifier for this folder access (e.g., "exports", "imports")
    /// - Returns: The selected folder URL, or nil if cancelled
    @MainActor
    func requestFolderAccess(message: String = "Select a folder", identifier: String) async -> URL? {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.message = message
        panel.prompt = "Select"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        let response = await panel.beginSheetModal(for: NSApp.keyWindow ?? NSWindow())

        guard response == .OK, let url = panel.url else {
            return nil
        }

        // Save bookmark for persistent access
        do {
            try saveBookmark(for: url, identifier: identifier)
            if !accessibleFolders.contains(url) {
                accessibleFolders.append(url)
            }
            return url
        } catch {
            print("Failed to save bookmark: \(error)")
            return url // Return URL anyway, it will work for this session
        }
        #else
        return nil
        #endif
    }

    /// Shows a folder picker and returns the URL without saving a bookmark
    @MainActor
    func pickFolderOnce(message: String = "Select a folder") async -> URL? {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.message = message
        panel.prompt = "Select"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        let response = await panel.beginSheetModal(for: NSApp.keyWindow ?? NSWindow())

        guard response == .OK else {
            return nil
        }

        return panel.url
        #else
        return nil
        #endif
    }

    // MARK: - File Picker

    /// Shows a file picker dialog
    /// - Parameters:
    ///   - message: The message to display in the dialog
    ///   - allowedTypes: Array of allowed file extensions (e.g., ["pdf", "csv"])
    /// - Returns: The selected file URL, or nil if cancelled
    @MainActor
    func pickFile(message: String = "Select a file", allowedTypes: [String]? = nil) async -> URL? {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.message = message
        panel.prompt = "Select"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if let types = allowedTypes {
            panel.allowedContentTypes = types.compactMap { ext in
                UTType(filenameExtension: ext)
            }
        }

        let response = await panel.beginSheetModal(for: NSApp.keyWindow ?? NSWindow())

        guard response == .OK else {
            return nil
        }

        return panel.url
        #else
        return nil
        #endif
    }

    /// Shows a file picker for multiple files
    @MainActor
    func pickFiles(message: String = "Select files", allowedTypes: [String]? = nil) async -> [URL] {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.message = message
        panel.prompt = "Select"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true

        if let types = allowedTypes {
            panel.allowedContentTypes = types.compactMap { ext in
                UTType(filenameExtension: ext)
            }
        }

        let response = await panel.beginSheetModal(for: NSApp.keyWindow ?? NSWindow())

        guard response == .OK else {
            return []
        }

        return panel.urls
        #else
        return []
        #endif
    }

    // MARK: - Save Panel

    /// Shows a save panel dialog
    /// - Parameters:
    ///   - suggestedName: The suggested file name
    ///   - allowedTypes: Array of allowed file extensions
    /// - Returns: The selected save URL, or nil if cancelled
    @MainActor
    func pickSaveLocation(suggestedName: String, allowedTypes: [String]? = nil) async -> URL? {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true

        if let types = allowedTypes {
            panel.allowedContentTypes = types.compactMap { ext in
                UTType(filenameExtension: ext)
            }
        }

        let response = await panel.beginSheetModal(for: NSApp.keyWindow ?? NSWindow())

        guard response == .OK else {
            return nil
        }

        return panel.url
        #else
        return nil
        #endif
    }

    // MARK: - Bookmark Management

    /// Gets a previously saved folder URL by identifier
    func getSavedFolder(identifier: String) -> URL? {
        guard let bookmarks = UserDefaults.standard.dictionary(forKey: bookmarksKey),
              let bookmarkData = bookmarks[identifier] as? Data else {
            return nil
        }

        do {
            return try restoreBookmark(from: bookmarkData)
        } catch {
            print("Failed to restore bookmark for \(identifier): \(error)")
            // Remove invalid bookmark
            removeBookmark(identifier: identifier)
            return nil
        }
    }

    /// Checks if we have saved access to a folder with the given identifier
    func hasAccess(identifier: String) -> Bool {
        return getSavedFolder(identifier: identifier) != nil
    }

    /// Removes a saved folder bookmark
    func removeBookmark(identifier: String) {
        var bookmarks = UserDefaults.standard.dictionary(forKey: bookmarksKey) ?? [:]
        bookmarks.removeValue(forKey: identifier)
        UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)

        // Update accessible folders
        restoreAllBookmarks()
    }

    /// Removes all saved bookmarks
    func removeAllBookmarks() {
        UserDefaults.standard.removeObject(forKey: bookmarksKey)
        accessibleFolders.removeAll()
    }

    /// Lists all saved folder identifiers
    func savedFolderIdentifiers() -> [String] {
        let bookmarks = UserDefaults.standard.dictionary(forKey: bookmarksKey) ?? [:]
        return Array(bookmarks.keys)
    }

    // MARK: - Security Scoped Access

    /// Executes a closure with access to a security-scoped resource
    /// Use this when you need to access a bookmarked folder
    func withAccess<T>(to url: URL, perform action: (URL) throws -> T) rethrows -> T {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try action(url)
    }

    /// Executes an async closure with access to a security-scoped resource
    func withAccess<T>(to url: URL, perform action: (URL) async throws -> T) async rethrows -> T {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try await action(url)
    }

    // MARK: - Private Methods

    private func saveBookmark(for url: URL, identifier: String) throws {
        #if os(macOS)
        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        let bookmarkData = try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif

        var bookmarks = UserDefaults.standard.dictionary(forKey: bookmarksKey) ?? [:]
        bookmarks[identifier] = bookmarkData
        UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
    }

    private func restoreBookmark(from data: Data) throws -> URL {
        var isStale = false
        #if os(macOS)
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        #else
        let url = try URL(
            resolvingBookmarkData: data,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        #endif

        if isStale {
            // Bookmark is stale, try to recreate it
            print("Bookmark is stale, attempting to refresh...")
            // Note: We can only refresh if we still have access
        }

        #if os(macOS)
        // Start accessing the security-scoped resource
        _ = url.startAccessingSecurityScopedResource()
        #endif

        return url
    }

    private func restoreAllBookmarks() {
        accessibleFolders.removeAll()

        guard let bookmarks = UserDefaults.standard.dictionary(forKey: bookmarksKey) else {
            return
        }

        for (identifier, data) in bookmarks {
            guard let bookmarkData = data as? Data else { continue }

            do {
                let url = try restoreBookmark(from: bookmarkData)
                accessibleFolders.append(url)
            } catch {
                print("Failed to restore bookmark for \(identifier): \(error)")
            }
        }
    }
}

// MARK: - Convenience Extensions

extension FolderAccessService {
    /// Common folder identifiers
    enum CommonFolder: String {
        case exports = "exports"
        case imports = "imports"
        case backups = "backups"
        case documents = "documents"
        case reports = "reports"
    }

    /// Request access to a common folder type
    @MainActor
    func requestAccess(for folder: CommonFolder, message: String? = nil) async -> URL? {
        let defaultMessage: String
        switch folder {
        case .exports:
            defaultMessage = "Select a folder for exports"
        case .imports:
            defaultMessage = "Select a folder for imports"
        case .backups:
            defaultMessage = "Select a folder for backups"
        case .documents:
            defaultMessage = "Select a documents folder"
        case .reports:
            defaultMessage = "Select a folder for reports"
        }

        return await requestFolderAccess(
            message: message ?? defaultMessage,
            identifier: folder.rawValue
        )
    }

    /// Get a previously saved common folder
    func getFolder(_ folder: CommonFolder) -> URL? {
        return getSavedFolder(identifier: folder.rawValue)
    }
}
