//
//  HandoverExportService.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-09.
//

import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#else
import UIKit
#endif

class HandoverExportService {
    static let shared = HandoverExportService()

    struct ExportOptions {
        let wells: [Well]
        let startDate: Date
        let endDate: Date
        let includeTasks: Bool
        let includeNotes: Bool
        let includeCompleted: Bool
        let shiftType: ShiftType?  // nil = all shifts, .day/.night = filter by shift hours
    }

    // MARK: - HTML Generation

    func generateHTML(options: ExportOptions) -> String {
        let reportData = buildReportData(options: options)
        return HandoverHTMLGenerator.shared.generateHTML(for: reportData)
    }

    private func buildReportData(options: ExportOptions) -> HandoverReportData {
        let calendar = Calendar.current
        let startOfStartDate = calendar.startOfDay(for: options.startDate)
        let endOfEndDate = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: options.endDate) ?? options.endDate

        let settings = ShiftRotationSettings.shared

        // Build shift hour filter if needed
        let shiftFilter: ((Date) -> Bool)? = {
            guard let shiftType = options.shiftType, shiftType != .off else { return nil }

            let dayStartMinutes = settings.dayShiftStartHour * 60 + settings.dayShiftStartMinute
            let nightStartMinutes = settings.nightShiftStartHour * 60 + settings.nightShiftStartMinute

            return { date in
                let components = calendar.dateComponents([.hour, .minute], from: date)
                let minuteOfDay = (components.hour ?? 0) * 60 + (components.minute ?? 0)

                if shiftType == .day {
                    // Day shift: from dayStart to nightStart
                    return minuteOfDay >= dayStartMinutes && minuteOfDay < nightStartMinutes
                } else {
                    // Night shift: from nightStart to dayStart (next day), wraps midnight
                    return minuteOfDay >= nightStartMinutes || minuteOfDay < dayStartMinutes
                }
            }
        }()

        func filterByDate(_ date: Date) -> Bool {
            date >= startOfStartDate && date <= endOfEndDate
        }

        func filterByShift(_ date: Date) -> Bool {
            guard let filter = shiftFilter else { return true }
            return filter(date)
        }

        func filterTask(_ task: WellTask) -> Bool {
            guard filterByDate(task.createdAt) && filterByShift(task.createdAt) else { return false }
            if !options.includeCompleted && (task.status == .completed || task.status == .cancelled) {
                return false
            }
            return true
        }

        func filterNote(_ note: HandoverNote) -> Bool {
            filterByDate(note.createdAt) && filterByShift(note.createdAt)
        }

        func makeTaskItem(_ task: WellTask) -> HandoverReportData.TaskItem {
            HandoverReportData.TaskItem(
                title: task.title,
                description: task.taskDescription,
                priority: task.priority.rawValue,
                status: task.status.rawValue,
                dueDate: task.dueDate,
                createdAt: task.createdAt,
                isOverdue: task.isOverdue,
                author: task.author
            )
        }

        func makeNoteItem(_ note: HandoverNote) -> HandoverReportData.NoteItem {
            HandoverReportData.NoteItem(
                title: note.title,
                content: note.content,
                category: note.category.rawValue,
                priority: note.priority.rawValue,
                author: note.author,
                createdAt: note.createdAt,
                isPinned: note.isPinned
            )
        }

        // Group wells by pad
        let wellsByPad = Dictionary(grouping: options.wells) { $0.pad?.name ?? "Unassigned" }
        let sortedPadNames = wellsByPad.keys.sorted { a, b in
            if a == "Unassigned" { return false }
            if b == "Unassigned" { return true }
            return a < b
        }

        var padGroups: [HandoverReportData.PadGroup] = []

        for padName in sortedPadNames {
            guard let padWells = wellsByPad[padName] else { continue }
            let pad = padWells.first?.pad

            // Pad-level tasks and notes (assigned to pad but NOT to any well)
            var padTasks: [HandoverReportData.TaskItem] = []
            var padNotes: [HandoverReportData.NoteItem] = []

            if let pad = pad {
                if options.includeTasks {
                    padTasks = pad.padTasks
                        .filter { $0.well == nil && filterTask($0) }
                        .sorted { $0.priority.sortOrder < $1.priority.sortOrder }
                        .map { makeTaskItem($0) }
                }

                if options.includeNotes {
                    padNotes = pad.padNotes
                        .filter { $0.well == nil && filterNote($0) }
                        .sorted { $0.isPinned && !$1.isPinned }
                        .map { makeNoteItem($0) }
                }
            }

            // Well groups
            let wellGroups: [HandoverReportData.WellGroup] = padWells.sorted(by: { $0.name < $1.name }).map { well in
                var tasks: [HandoverReportData.TaskItem] = []
                var notes: [HandoverReportData.NoteItem] = []

                if options.includeTasks {
                    tasks = (well.tasks ?? [])
                        .filter { filterTask($0) }
                        .sorted { $0.priority.sortOrder < $1.priority.sortOrder }
                        .map { makeTaskItem($0) }
                }

                if options.includeNotes {
                    notes = (well.notes ?? [])
                        .filter { filterNote($0) }
                        .sorted { $0.isPinned && !$1.isPinned }
                        .map { makeNoteItem($0) }
                }

                return HandoverReportData.WellGroup(
                    wellName: well.name,
                    tasks: tasks,
                    notes: notes
                )
            }

            padGroups.append(HandoverReportData.PadGroup(
                padName: padName,
                padTasks: padTasks,
                padNotes: padNotes,
                wells: wellGroups
            ))
        }

        let shiftLabel = options.shiftType.map { $0.displayName }

        return HandoverReportData(
            reportTitle: "Handover Report",
            startDate: options.startDate,
            endDate: options.endDate,
            generatedDate: Date(),
            shiftTypeFilter: shiftLabel,
            padGroups: padGroups
        )
    }

    // MARK: - Export

    #if os(macOS)
    func exportHTML(options: ExportOptions, modelContext: ModelContext? = nil) {
        let htmlContent = generateHTML(options: options)

        let dateStr = Date().formatted(date: .abbreviated, time: .omitted)
            .replacingOccurrences(of: " ", with: "_")
        let baseName = "Handover_Report_\(dateStr)"

        Task { @MainActor in
            let success = await HTMLZipExporter.shared.exportZipped(
                htmlContent: htmlContent,
                htmlFileName: "\(baseName).html",
                zipFileName: "\(baseName).zip"
            )

            if success, let context = modelContext {
                self.createArchive(options: options, htmlContent: htmlContent, modelContext: context)
            }
        }
    }
    #endif

    #if os(iOS)
    @MainActor
    func exportHTML(options: ExportOptions, modelContext: ModelContext? = nil) {
        let htmlContent = generateHTML(options: options)

        let dateStr = Date().formatted(date: .abbreviated, time: .omitted)
        let filename = "Handover_Report_\(dateStr).html"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try htmlContent.data(using: .utf8)?.write(to: tempURL)

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

                if let context = modelContext {
                    self.createArchive(options: options, htmlContent: htmlContent, modelContext: context)
                }
            }
        } catch {
            print("Error exporting HTML: \(error)")
        }
    }
    #endif

    // MARK: - Archive Creation

    /// Creates an archive of the handover report for future reference
    func createArchive(options: ExportOptions, htmlContent: String? = nil, modelContext: ModelContext) {
        let calendar = Calendar.current
        let startOfStartDate = calendar.startOfDay(for: options.startDate)
        let endOfEndDate = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: options.endDate) ?? options.endDate

        // Build the archive
        let wellNames = options.wells.map { $0.name }
        let padNames = Array(Set(options.wells.compactMap { $0.pad?.name }))

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy"
        let reportTitle = "Handover \(dateFormatter.string(from: options.startDate)) - \(dateFormatter.string(from: options.endDate))"

        let archive = HandoverReportArchive(
            reportTitle: reportTitle,
            startDate: options.startDate,
            endDate: options.endDate,
            wellNames: wellNames,
            padNames: padNames
        )

        // Store HTML content
        archive.htmlData = htmlContent?.data(using: .utf8)

        // Collect and archive tasks
        var archivedTasks: [ArchivedTask] = []
        var archivedNotes: [ArchivedNote] = []

        // Get pads from wells
        let pads = Set(options.wells.compactMap { $0.pad })

        // Archive pad-level tasks and notes
        for pad in pads {
            if options.includeTasks {
                var padTasks = pad.padTasks.filter { task in
                    task.createdAt >= startOfStartDate && task.createdAt <= endOfEndDate
                }
                if !options.includeCompleted {
                    padTasks = padTasks.filter { $0.status != .completed && $0.status != .cancelled }
                }
                for task in padTasks {
                    archivedTasks.append(HandoverReportArchive.archiveTask(task))
                }
            }

            if options.includeNotes {
                let padNotes = pad.padNotes.filter { note in
                    note.createdAt >= startOfStartDate && note.createdAt <= endOfEndDate
                }
                for note in padNotes {
                    archivedNotes.append(HandoverReportArchive.archiveNote(note))
                }
            }
        }

        // Archive well-level tasks and notes
        for well in options.wells {
            if options.includeTasks {
                var tasks = (well.tasks ?? []).filter { task in
                    task.createdAt >= startOfStartDate && task.createdAt <= endOfEndDate
                }
                if !options.includeCompleted {
                    tasks = tasks.filter { $0.status != .completed && $0.status != .cancelled }
                }
                for task in tasks {
                    archivedTasks.append(HandoverReportArchive.archiveTask(task))
                }
            }

            if options.includeNotes {
                let notes = (well.notes ?? []).filter { note in
                    note.createdAt >= startOfStartDate && note.createdAt <= endOfEndDate
                }
                for note in notes {
                    archivedNotes.append(HandoverReportArchive.archiveNote(note))
                }
            }
        }

        archive.archivedTasks = archivedTasks
        archive.archivedNotes = archivedNotes

        modelContext.insert(archive)
        try? modelContext.save()
    }
}
