//
//  FileService.swift
//  Josh Well Control
//
//  Platform-agnostic file operations service
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Service for handling file operations in a platform-agnostic way
@MainActor
class FileService {
    static let shared = FileService()

    private init() {}

    /// Save data to a file with a save dialog
    /// - Parameters:
    ///   - data: The data to save
    ///   - defaultName: Default file name
    ///   - allowedFileTypes: File extensions allowed (e.g., ["csv", "pdf"])
    /// - Returns: True if saved successfully
    func saveFile(data: Data, defaultName: String, allowedFileTypes: [String]) async -> Bool {
        #if os(macOS)
        return await saveMacOS(data: data, defaultName: defaultName, allowedFileTypes: allowedFileTypes)
        #elseif os(iOS)
        return await saveIOS(data: data, defaultName: defaultName)
        #else
        return false
        #endif
    }

    /// Save text to a file
    func saveTextFile(text: String, defaultName: String, allowedFileTypes: [String] = ["txt"]) async -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        return await saveFile(data: data, defaultName: defaultName, allowedFileTypes: allowedFileTypes)
    }

    #if os(macOS)
    private func saveMacOS(data: Data, defaultName: String, allowedFileTypes: [String]) async -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = allowedFileTypes.compactMap { UTType(filenameExtension: $0) }
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let response = await panel.begin()

        guard response == .OK, let url = panel.url else {
            return false
        }

        do {
            try data.write(to: url)
            return true
        } catch {
            print("Error saving file: \(error)")
            return false
        }
    }
    #endif

    #if os(iOS)
    private func saveIOS(data: Data, defaultName: String) async -> Bool {
        // On iOS, we'll use UIDocumentPickerViewController or share sheet
        // For now, save to temporary directory and return the URL for sharing
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(defaultName)

        do {
            try data.write(to: tempURL)

            // Present share sheet
            await MainActor.run {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first,
                   let rootViewController = window.rootViewController {

                    let activityVC = UIActivityViewController(
                        activityItems: [tempURL],
                        applicationActivities: nil
                    )

                    if let popover = activityVC.popoverPresentationController {
                        popover.sourceView = window
                        popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                        popover.permittedArrowDirections = []
                    }

                    rootViewController.present(activityVC, animated: true)
                }
            }

            return true
        } catch {
            print("Error saving file: \(error)")
            return false
        }
    }
    #endif
}
