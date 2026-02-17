//
//  HTMLZipExporter.swift
//  Josh Well Control for Mac
//
//  Utility to export HTML reports as compressed ZIP files for easier sharing.
//

import Foundation

@MainActor
class HTMLZipExporter {
    static let shared = HTMLZipExporter()
    private init() {}

    /// Exports an HTML string as a compressed ZIP file via save dialog.
    func exportZipped(htmlContent: String, htmlFileName: String, zipFileName: String) async -> Bool {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let htmlPath = tempDir.appendingPathComponent(htmlFileName)
            let zipPath = tempDir.appendingPathComponent(zipFileName)

            try htmlContent.data(using: .utf8)?.write(to: htmlPath)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.arguments = ["-j", zipPath.path, htmlPath.path]
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                try? FileManager.default.removeItem(at: tempDir)
                return false
            }

            let zipData = try Data(contentsOf: zipPath)
            let success = await FileService.shared.saveFile(
                data: zipData,
                defaultName: zipFileName,
                allowedFileTypes: ["zip"]
            )

            try? FileManager.default.removeItem(at: tempDir)
            return success
        } catch {
            print("Zip export error: \(error)")
            try? FileManager.default.removeItem(at: tempDir)
            return false
        }
    }
}
