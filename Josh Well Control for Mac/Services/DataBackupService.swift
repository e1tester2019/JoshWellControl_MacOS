//
//  DataBackupService.swift
//  Josh Well Control for Mac
//
//  Exports WorkDays, Expenses, and MileageLogs to portable CSV files
//  with receipt images and GPS route data for backup purposes.
//

import Foundation
import SwiftData
#if os(macOS)
import AppKit
#endif

@MainActor
final class DataBackupService {

    struct BackupResult {
        var workDayCount = 0
        var expenseCount = 0
        var mileageLogCount = 0
        var routePointCount = 0
        var receiptCount = 0
        var mapSnapshotCount = 0
        var totalSizeBytes: Int64 = 0
        var folderURL: URL?

        var summary: String {
            var parts: [String] = []
            if workDayCount > 0 { parts.append("\(workDayCount) work days") }
            if expenseCount > 0 { parts.append("\(expenseCount) expenses") }
            if mileageLogCount > 0 { parts.append("\(mileageLogCount) mileage logs") }
            if routePointCount > 0 { parts.append("\(routePointCount) route points") }
            if receiptCount > 0 { parts.append("\(receiptCount) receipts") }
            if mapSnapshotCount > 0 { parts.append("\(mapSnapshotCount) map snapshots") }
            if parts.isEmpty { return "No records found to export." }
            let sizeMB = String(format: "%.1f", Double(totalSizeBytes) / 1_048_576)
            return "Exported \(parts.joined(separator: ", ")) (\(sizeMB) MB)"
        }
    }

    // MARK: - Public API

    static func exportBackup(context: ModelContext) async -> BackupResult {
        var result = BackupResult()

        let dateString = Self.folderDateFormatter.string(from: Date())
        let folderName = "JWC_Backup_\(dateString)"
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(folderName)
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // Fetch all records
            let workDays = (try? context.fetch(FetchDescriptor<WorkDay>(sortBy: [SortDescriptor(\.startDate)]))) ?? []
            let expenses = (try? context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date)]))) ?? []
            let mileageLogs = (try? context.fetch(FetchDescriptor<MileageLog>(sortBy: [SortDescriptor(\.date)]))) ?? []

            // Build CSVs
            let workDaysCSV = buildWorkDaysCSV(workDays)
            let expensesCSV = buildExpensesCSV(expenses)
            let mileageLogsCSV = buildMileageLogsCSV(mileageLogs)
            let (routePointsCSV, rpCount) = buildRoutePointsCSV(mileageLogs)

            try workDaysCSV.write(to: tempDir.appendingPathComponent("WorkDays.csv"), atomically: true, encoding: .utf8)
            try expensesCSV.write(to: tempDir.appendingPathComponent("Expenses.csv"), atomically: true, encoding: .utf8)
            try mileageLogsCSV.write(to: tempDir.appendingPathComponent("MileageLogs.csv"), atomically: true, encoding: .utf8)
            try routePointsCSV.write(to: tempDir.appendingPathComponent("RoutePoints.csv"), atomically: true, encoding: .utf8)

            result.workDayCount = workDays.count
            result.expenseCount = expenses.count
            result.mileageLogCount = mileageLogs.count
            result.routePointCount = rpCount

            // Export receipt images
            let receiptsDir = tempDir.appendingPathComponent("receipts")
            try fm.createDirectory(at: receiptsDir, withIntermediateDirectories: true)
            result.receiptCount = exportReceipts(expenses, to: receiptsDir)

            // Export map snapshots
            let mapsDir = tempDir.appendingPathComponent("map_snapshots")
            try fm.createDirectory(at: mapsDir, withIntermediateDirectories: true)
            result.mapSnapshotCount = exportMapSnapshots(mileageLogs, to: mapsDir)

            await Task.yield()

            // Calculate total size
            result.totalSizeBytes = Self.directorySize(at: tempDir)

            // Present save dialog via NSSavePanel for the folder
            let saved = await saveFolder(tempDir, defaultName: folderName)
            if saved {
                result.folderURL = tempDir
            }

            // Clean up temp directory
            try? fm.removeItem(at: tempDir.deletingLastPathComponent())

        } catch {
            print("Backup export error: \(error)")
            try? fm.removeItem(at: tempDir.deletingLastPathComponent())
        }

        return result
    }

    // MARK: - CSV Builders

    private static func buildWorkDaysCSV(_ workDays: [WorkDay]) -> String {
        var lines: [String] = []
        lines.append([
            "id", "wellName", "clientName", "startDate", "endDate", "dayCount",
            "dayRate", "dayRateOverride", "customRateReason", "totalEarnings",
            "mileageToLocation", "mileageFromLocation", "mileageInField", "mileageCommute", "totalMileage",
            "rigName", "costCode", "isInvoiced", "isPaid", "paidDate", "notes", "createdAt"
        ].joined(separator: ","))

        for wd in workDays {
            let row: [String] = [
                csvEscape(wd.id.uuidString),
                csvEscape(wd.well?.name ?? ""),
                csvEscape(wd.client?.companyName ?? ""),
                csvEscape(isoDate(wd.startDate)),
                csvEscape(isoDate(wd.endDate)),
                "\(wd.dayCount)",
                String(format: "%.2f", wd.effectiveDayRate),
                wd.dayRateOverride.map { String(format: "%.2f", $0) } ?? "",
                csvEscape(wd.customRateReason),
                String(format: "%.2f", wd.totalEarnings),
                String(format: "%.1f", wd.mileageToLocation),
                String(format: "%.1f", wd.mileageFromLocation),
                String(format: "%.1f", wd.mileageInField),
                String(format: "%.1f", wd.mileageCommute),
                String(format: "%.1f", wd.totalMileage),
                csvEscape(wd.effectiveRigName),
                csvEscape(wd.effectiveCostCode),
                wd.isInvoiced ? "true" : "false",
                wd.isPaid ? "true" : "false",
                wd.paidDate.map { isoDate($0) } ?? "",
                csvEscape(wd.notes),
                csvEscape(isoDate(wd.createdAt)),
            ]
            lines.append(row.joined(separator: ","))
        }

        return lines.joined(separator: "\n")
    }

    private static func buildExpensesCSV(_ expenses: [Expense]) -> String {
        var lines: [String] = []
        lines.append([
            "id", "wellName", "clientName", "date", "vendor", "description", "category",
            "amount", "gstAmount", "pstAmount", "totalAmount", "taxIncludedInAmount",
            "province", "paymentMethod", "isReimbursable", "isReimbursed", "reimbursedDate",
            "hasReceipt", "receiptFileName", "notes", "createdAt"
        ].joined(separator: ","))

        for exp in expenses {
            let row: [String] = [
                csvEscape(exp.id.uuidString),
                csvEscape(exp.well?.name ?? ""),
                csvEscape(exp.client?.companyName ?? ""),
                csvEscape(isoDate(exp.date)),
                csvEscape(exp.vendor),
                csvEscape(exp.expenseDescription),
                csvEscape(exp.category.rawValue),
                String(format: "%.2f", exp.amount),
                String(format: "%.2f", exp.gstAmount),
                String(format: "%.2f", exp.pstAmount),
                String(format: "%.2f", exp.totalAmount),
                exp.taxIncludedInAmount ? "true" : "false",
                csvEscape(exp.province.rawValue),
                csvEscape(exp.paymentMethod.rawValue),
                exp.isReimbursable ? "true" : "false",
                exp.isReimbursed ? "true" : "false",
                exp.reimbursedDate.map { isoDate($0) } ?? "",
                exp.hasReceipt ? "true" : "false",
                csvEscape(exp.receiptFileName ?? ""),
                csvEscape(exp.notes),
                csvEscape(isoDate(exp.createdAt)),
            ]
            lines.append(row.joined(separator: ","))
        }

        return lines.joined(separator: "\n")
    }

    private static func buildMileageLogsCSV(_ logs: [MileageLog]) -> String {
        var lines: [String] = []
        lines.append([
            "id", "wellName", "clientName", "date", "startLocation", "endLocation",
            "distance", "effectiveDistance", "isRoundTrip", "purpose", "trackingMode",
            "hasRoute", "hasMapSnapshot", "tripStartTime", "tripEndTime", "duration",
            "calculatedDistance", "expectedTravelTime", "destinationName", "notes", "createdAt"
        ].joined(separator: ","))

        for log in logs {
            let row: [String] = [
                csvEscape(log.id.uuidString),
                csvEscape(log.well?.name ?? ""),
                csvEscape(log.client?.companyName ?? ""),
                csvEscape(isoDate(log.date)),
                csvEscape(log.startLocation),
                csvEscape(log.endLocation),
                String(format: "%.1f", log.distance),
                String(format: "%.1f", log.effectiveDistance),
                log.isRoundTrip ? "true" : "false",
                csvEscape(log.purpose),
                csvEscape(log.trackingMode.rawValue),
                log.hasRoute ? "true" : "false",
                (log.mapSnapshotData != nil) ? "true" : "false",
                log.tripStartTime.map { isoDate($0) } ?? "",
                log.tripEndTime.map { isoDate($0) } ?? "",
                log.duration.map { String(format: "%.0f", $0) } ?? "",
                log.calculatedDistance.map { String(format: "%.1f", $0) } ?? "",
                log.expectedTravelTime.map { String(format: "%.0f", $0) } ?? "",
                csvEscape(log.destinationName ?? ""),
                csvEscape(log.notes),
                csvEscape(isoDate(log.createdAt)),
            ]
            lines.append(row.joined(separator: ","))
        }

        return lines.joined(separator: "\n")
    }

    private static func buildRoutePointsCSV(_ logs: [MileageLog]) -> (String, Int) {
        var lines: [String] = []
        lines.append("mileageLogID,latitude,longitude,altitude,timestamp,speed,course")

        var count = 0
        for log in logs {
            guard let points = log.routePoints, !points.isEmpty else { continue }
            let sorted = points.sorted { $0.timestamp < $1.timestamp }
            for pt in sorted {
                let row: [String] = [
                    csvEscape(log.id.uuidString),
                    String(format: "%.8f", pt.latitude),
                    String(format: "%.8f", pt.longitude),
                    pt.altitude.map { String(format: "%.1f", $0) } ?? "",
                    csvEscape(isoDate(pt.timestamp)),
                    pt.speed.map { String(format: "%.1f", $0) } ?? "",
                    pt.course.map { String(format: "%.1f", $0) } ?? "",
                ]
                lines.append(row.joined(separator: ","))
                count += 1
            }
        }

        return (lines.joined(separator: "\n"), count)
    }

    // MARK: - Binary Asset Export

    private static func exportReceipts(_ expenses: [Expense], to directory: URL) -> Int {
        var count = 0
        for exp in expenses {
            guard let data = exp.receiptImageData else { continue }
            let ext = exp.receiptIsPDF ? "pdf" : "jpg"
            let filename = "expense_\(exp.id.uuidString).\(ext)"
            let url = directory.appendingPathComponent(filename)
            do {
                try data.write(to: url)
                count += 1
            } catch {
                print("Failed to export receipt \(filename): \(error)")
            }
        }
        return count
    }

    private static func exportMapSnapshots(_ logs: [MileageLog], to directory: URL) -> Int {
        var count = 0
        for log in logs {
            guard let data = log.mapSnapshotData else { continue }
            let filename = "mileage_\(log.id.uuidString).png"
            let url = directory.appendingPathComponent(filename)
            do {
                try data.write(to: url)
                count += 1
            } catch {
                print("Failed to export map snapshot \(filename): \(error)")
            }
        }
        return count
    }

    // MARK: - Save Dialog

    private static func saveFolder(_ sourceDir: URL, defaultName: String) async -> Bool {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let response = await panel.begin()
        guard response == .OK, let destURL = panel.url else { return false }

        let fm = FileManager.default
        do {
            // Remove existing item at destination if present
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.copyItem(at: sourceDir, to: destURL)
            return true
        } catch {
            print("Error saving backup folder: \(error)")
            return false
        }
        #else
        return false
        #endif
    }

    // MARK: - Helpers

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let folderDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func isoDate(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
