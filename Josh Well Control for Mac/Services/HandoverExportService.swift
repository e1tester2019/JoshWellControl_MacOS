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
    }

    func generatePDF(options: ExportOptions) -> Data? {
        let pageWidth: CGFloat = 612  // Letter size
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50
        let contentWidth = pageWidth - 2 * margin

        var yPosition: CGFloat = pageHeight - margin

        let pdfData = NSMutableData()

        #if os(macOS)
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return nil
        }
        #else
        UIGraphicsBeginPDFContextToData(pdfData, CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight), nil)
        guard let pdfContext = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndPDFContext()
            return nil
        }
        #endif

        func startNewPage() {
            #if os(macOS)
            pdfContext.beginPDFPage(nil)
            #else
            UIGraphicsBeginPDFPage()
            #endif
            yPosition = pageHeight - margin
        }

        func endPage() {
            #if os(macOS)
            pdfContext.endPDFPage()
            #endif
        }

        func checkPageBreak(needed: CGFloat) {
            if yPosition - needed < margin {
                endPage()
                startNewPage()
            }
        }

        func drawText(_ text: String, at point: CGPoint, font: CTFont, color: CGColor = CGColor(gray: 0, alpha: 1)) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]
            let attrString = NSAttributedString(string: text, attributes: attributes)
            let line = CTLineCreateWithAttributedString(attrString)

            pdfContext.saveGState()
            pdfContext.textMatrix = .identity
            pdfContext.translateBy(x: point.x, y: point.y)
            pdfContext.scaleBy(x: 1, y: 1)
            CTLineDraw(line, pdfContext)
            pdfContext.restoreGState()
        }

        func drawWrappedText(_ text: String, at x: CGFloat, width: CGFloat, font: CTFont, color: CGColor = CGColor(gray: 0, alpha: 1), lineHeight: CGFloat = 14) -> CGFloat {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]
            let attrString = NSAttributedString(string: text, attributes: attributes)

            let frameSetter = CTFramesetterCreateWithAttributedString(attrString)
            let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
                frameSetter,
                CFRange(location: 0, length: attrString.length),
                nil,
                CGSize(width: width, height: .greatestFiniteMagnitude),
                nil
            )

            let requiredHeight = suggestedSize.height + 4
            checkPageBreak(needed: requiredHeight)

            let framePath = CGPath(rect: CGRect(x: x, y: yPosition - requiredHeight, width: width, height: requiredHeight), transform: nil)
            let frame = CTFramesetterCreateFrame(frameSetter, CFRange(location: 0, length: attrString.length), framePath, nil)

            pdfContext.saveGState()
            CTFrameDraw(frame, pdfContext)
            pdfContext.restoreGState()

            return requiredHeight
        }

        // Start first page
        startNewPage()

        // Fonts
        let titleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 24, nil)
        let headingFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 16, nil)
        let subheadingFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 12, nil)
        let bodyFont = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
        let smallFont = CTFontCreateWithName("Helvetica" as CFString, 9, nil)

        // Title
        drawText("Handover Report", at: CGPoint(x: margin, y: yPosition), font: titleFont)
        yPosition -= 30

        // Date range
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        let rangeText = "\(dateFormatter.string(from: options.startDate)) - \(dateFormatter.string(from: options.endDate))"
        drawText(rangeText, at: CGPoint(x: margin, y: yPosition), font: bodyFont)
        yPosition -= 20

        // Generated date
        let generatedText = "Generated: \(dateFormatter.string(from: Date()))"
        drawText(generatedText, at: CGPoint(x: margin, y: yPosition), font: smallFont, color: CGColor(gray: 0.5, alpha: 1))
        yPosition -= 30

        // Adjust dates to include full days
        let calendar = Calendar.current
        let startOfStartDate = calendar.startOfDay(for: options.startDate)
        let endOfEndDate = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: options.endDate) ?? options.endDate

        // Group wells by pad
        let wellsByPad = Dictionary(grouping: options.wells) { $0.pad?.name ?? "Unassigned" }
        let sortedPadNames = wellsByPad.keys.sorted { a, b in
            if a == "Unassigned" { return false }
            if b == "Unassigned" { return true }
            return a < b
        }

        for padName in sortedPadNames {
            guard let padWells = wellsByPad[padName] else { continue }

            checkPageBreak(needed: 40)

            // Get the actual pad object if this isn't the "Unassigned" group
            let pad = padWells.first?.pad

            // Pad header
            pdfContext.saveGState()
            pdfContext.setFillColor(CGColor(red: 0.9, green: 0.9, blue: 0.95, alpha: 1))
            pdfContext.fill(CGRect(x: margin - 5, y: yPosition - 5, width: contentWidth + 10, height: 22))
            pdfContext.restoreGState()

            drawText("Pad: \(padName)", at: CGPoint(x: margin, y: yPosition), font: headingFont)
            yPosition -= 30

            // Render pad-only tasks and notes (items assigned to pad but NOT to any well)
            if let pad = pad {
                // Filter pad tasks: only those assigned to pad but not to a well
                if options.includeTasks {
                    var padTasks = pad.padTasks.filter { task in
                        task.createdAt >= startOfStartDate && task.createdAt <= endOfEndDate &&
                        task.well == nil  // Only show if not assigned to a specific well
                    }
                    if !options.includeCompleted {
                        padTasks = padTasks.filter { $0.status != .completed && $0.status != .cancelled }
                    }
                    padTasks.sort { $0.priority.sortOrder < $1.priority.sortOrder }

                    if !padTasks.isEmpty {
                        checkPageBreak(needed: 20)
                        drawText("Pad Tasks (\(padTasks.count))", at: CGPoint(x: margin + 10, y: yPosition), font: subheadingFont, color: CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
                        yPosition -= 16

                        for task in padTasks {
                            checkPageBreak(needed: 40)

                            // Priority indicator
                            let priorityColor: CGColor
                            switch task.priority {
                            case .critical: priorityColor = CGColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1)
                            case .high: priorityColor = CGColor(red: 0.9, green: 0.5, blue: 0.2, alpha: 1)
                            case .medium: priorityColor = CGColor(red: 0.8, green: 0.7, blue: 0.2, alpha: 1)
                            case .low: priorityColor = CGColor(red: 0.3, green: 0.7, blue: 0.3, alpha: 1)
                            }

                            pdfContext.saveGState()
                            pdfContext.setFillColor(priorityColor)
                            pdfContext.fillEllipse(in: CGRect(x: margin + 15, y: yPosition - 3, width: 6, height: 6))
                            pdfContext.restoreGState()

                            // Task title, date, and status
                            let taskDateText = dateFormatter.string(from: task.createdAt)
                            let statusText = task.status == .completed ? " [DONE]" : (task.isOverdue ? " [OVERDUE]" : "")
                            drawText("\(task.title) - \(taskDateText)\(statusText)", at: CGPoint(x: margin + 25, y: yPosition), font: bodyFont)
                            yPosition -= 14

                            // Task details
                            if !task.taskDescription.isEmpty {
                                let height = drawWrappedText(task.taskDescription, at: margin + 25, width: contentWidth - 35, font: smallFont, color: CGColor(gray: 0.4, alpha: 1))
                                yPosition -= height
                            }

                            // Due date
                            if let due = task.dueDate {
                                let dueText = "Due: \(dateFormatter.string(from: due))"
                                drawText(dueText, at: CGPoint(x: margin + 25, y: yPosition), font: smallFont, color: task.isOverdue ? CGColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1) : CGColor(gray: 0.5, alpha: 1))
                                yPosition -= 12
                            }

                            yPosition -= 10  // Spacing between tasks
                        }
                    }
                }

                // Filter pad notes: only those assigned to pad but not to a well
                if options.includeNotes {
                    let padNotes = pad.padNotes.filter { note in
                        note.createdAt >= startOfStartDate && note.createdAt <= endOfEndDate &&
                        note.well == nil  // Only show if not assigned to a specific well
                    }.sorted { $0.isPinned && !$1.isPinned }

                    if !padNotes.isEmpty {
                        checkPageBreak(needed: 20)
                        drawText("Pad Notes (\(padNotes.count))", at: CGPoint(x: margin + 10, y: yPosition), font: subheadingFont, color: CGColor(red: 0.2, green: 0.6, blue: 0.4, alpha: 1))
                        yPosition -= 16

                        for note in padNotes {
                            checkPageBreak(needed: 50)

                            // Category badge
                            let categoryColor: CGColor
                            switch note.category {
                            case .safety: categoryColor = CGColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1)
                            case .operations: categoryColor = CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
                            case .equipment: categoryColor = CGColor(red: 0.9, green: 0.5, blue: 0.2, alpha: 1)
                            case .personnel: categoryColor = CGColor(red: 0.6, green: 0.3, blue: 0.7, alpha: 1)
                            case .handover: categoryColor = CGColor(red: 0.3, green: 0.7, blue: 0.3, alpha: 1)
                            case .general: categoryColor = CGColor(gray: 0.5, alpha: 1)
                            }

                            // Note title with date
                            let pinPrefix = note.isPinned ? "📌 " : ""
                            let noteDateText = dateFormatter.string(from: note.createdAt)
                            drawText("\(pinPrefix)\(note.title) - \(noteDateText) [\(note.category.rawValue)]", at: CGPoint(x: margin + 15, y: yPosition), font: bodyFont, color: categoryColor)
                            yPosition -= 14

                            // Note content
                            if !note.content.isEmpty {
                                let height = drawWrappedText(note.content, at: margin + 15, width: contentWidth - 25, font: smallFont, color: CGColor(gray: 0.3, alpha: 1))
                                yPosition -= height
                            }

                            // Author
                            if !note.author.isEmpty {
                                drawText("By: \(note.author)", at: CGPoint(x: margin + 15, y: yPosition), font: smallFont, color: CGColor(gray: 0.5, alpha: 1))
                                yPosition -= 12
                            }

                            yPosition -= 10  // Spacing between notes
                        }
                    }
                }

                yPosition -= 10
            }

            for well in padWells.sorted(by: { $0.name < $1.name }) {
                checkPageBreak(needed: 30)

                // Well header
                drawText(well.name, at: CGPoint(x: margin + 10, y: yPosition), font: subheadingFont)
                yPosition -= 18

                // Filter tasks by date (all tasks assigned to this well)
                if options.includeTasks {
                    var tasks = (well.tasks ?? []).filter { task in
                        task.createdAt >= startOfStartDate && task.createdAt <= endOfEndDate
                    }
                    if !options.includeCompleted {
                        tasks = tasks.filter { $0.status != .completed && $0.status != .cancelled }
                    }
                    tasks.sort { $0.priority.sortOrder < $1.priority.sortOrder }

                    if !tasks.isEmpty {
                        checkPageBreak(needed: 20)
                        drawText("Tasks (\(tasks.count))", at: CGPoint(x: margin + 20, y: yPosition), font: subheadingFont, color: CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
                        yPosition -= 16

                        for task in tasks {
                            checkPageBreak(needed: 40)

                            // Priority indicator
                            let priorityColor: CGColor
                            switch task.priority {
                            case .critical: priorityColor = CGColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1)
                            case .high: priorityColor = CGColor(red: 0.9, green: 0.5, blue: 0.2, alpha: 1)
                            case .medium: priorityColor = CGColor(red: 0.8, green: 0.7, blue: 0.2, alpha: 1)
                            case .low: priorityColor = CGColor(red: 0.3, green: 0.7, blue: 0.3, alpha: 1)
                            }

                            pdfContext.saveGState()
                            pdfContext.setFillColor(priorityColor)
                            pdfContext.fillEllipse(in: CGRect(x: margin + 25, y: yPosition - 3, width: 6, height: 6))
                            pdfContext.restoreGState()

                            // Task title, date, and status
                            let taskDateText = dateFormatter.string(from: task.createdAt)
                            let statusText = task.status == .completed ? " [DONE]" : (task.isOverdue ? " [OVERDUE]" : "")
                            drawText("\(task.title) - \(taskDateText)\(statusText)", at: CGPoint(x: margin + 35, y: yPosition), font: bodyFont)
                            yPosition -= 14

                            // Task details
                            if !task.taskDescription.isEmpty {
                                let height = drawWrappedText(task.taskDescription, at: margin + 35, width: contentWidth - 45, font: smallFont, color: CGColor(gray: 0.4, alpha: 1))
                                yPosition -= height
                            }

                            // Due date
                            if let due = task.dueDate {
                                let dueText = "Due: \(dateFormatter.string(from: due))"
                                drawText(dueText, at: CGPoint(x: margin + 35, y: yPosition), font: smallFont, color: task.isOverdue ? CGColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1) : CGColor(gray: 0.5, alpha: 1))
                                yPosition -= 12
                            }

                            yPosition -= 10  // Spacing between tasks
                        }
                    }
                }

                // Filter notes by date (all notes assigned to this well)
                if options.includeNotes {
                    let notes = (well.notes ?? []).filter { note in
                        note.createdAt >= startOfStartDate && note.createdAt <= endOfEndDate
                    }.sorted { $0.isPinned && !$1.isPinned }

                    if !notes.isEmpty {
                        checkPageBreak(needed: 20)
                        drawText("Notes (\(notes.count))", at: CGPoint(x: margin + 20, y: yPosition), font: subheadingFont, color: CGColor(red: 0.2, green: 0.6, blue: 0.4, alpha: 1))
                        yPosition -= 16

                        for note in notes {
                            checkPageBreak(needed: 50)

                            // Category badge
                            let categoryColor: CGColor
                            switch note.category {
                            case .safety: categoryColor = CGColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1)
                            case .operations: categoryColor = CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
                            case .equipment: categoryColor = CGColor(red: 0.9, green: 0.5, blue: 0.2, alpha: 1)
                            case .personnel: categoryColor = CGColor(red: 0.6, green: 0.3, blue: 0.7, alpha: 1)
                            case .handover: categoryColor = CGColor(red: 0.3, green: 0.7, blue: 0.3, alpha: 1)
                            case .general: categoryColor = CGColor(gray: 0.5, alpha: 1)
                            }

                            // Note title with date
                            let pinPrefix = note.isPinned ? "📌 " : ""
                            let noteDateText = dateFormatter.string(from: note.createdAt)
                            drawText("\(pinPrefix)\(note.title) - \(noteDateText) [\(note.category.rawValue)]", at: CGPoint(x: margin + 25, y: yPosition), font: bodyFont, color: categoryColor)
                            yPosition -= 14

                            // Note content
                            if !note.content.isEmpty {
                                let height = drawWrappedText(note.content, at: margin + 25, width: contentWidth - 35, font: smallFont, color: CGColor(gray: 0.3, alpha: 1))
                                yPosition -= height
                            }

                            // Author
                            if !note.author.isEmpty {
                                drawText("By: \(note.author)", at: CGPoint(x: margin + 25, y: yPosition), font: smallFont, color: CGColor(gray: 0.5, alpha: 1))
                                yPosition -= 12
                            }

                            yPosition -= 10  // Spacing between notes
                        }
                    }
                }

                yPosition -= 10
            }

            yPosition -= 10
        }

        // End last page
        endPage()

        #if os(macOS)
        pdfContext.closePDF()
        #else
        UIGraphicsEndPDFContext()
        #endif

        return pdfData as Data
    }

    #if os(macOS)
    func exportPDF(options: ExportOptions, modelContext: ModelContext? = nil) {
        guard let pdfData = generatePDF(options: options) else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "Handover Report \(Date().formatted(date: .abbreviated, time: .omitted)).pdf"

        savePanel.begin { [weak self] response in
            if response == .OK, let url = savePanel.url {
                try? pdfData.write(to: url)
                NSWorkspace.shared.open(url)

                // Save archive if we have a model context
                if let context = modelContext {
                    self?.createArchive(options: options, pdfData: pdfData, modelContext: context)
                }
            }
        }
    }
    #endif

    #if os(iOS)
    @MainActor
    func exportPDF(options: ExportOptions, modelContext: ModelContext? = nil) {
        guard let pdfData = generatePDF(options: options) else { return }

        // Save to temp file
        let filename = "Handover Report \(Date().formatted(date: .abbreviated, time: .omitted)).pdf"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try pdfData.write(to: tempURL)

            // Present share sheet
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

                // Save archive if we have a model context
                if let context = modelContext {
                    self.createArchive(options: options, pdfData: pdfData, modelContext: context)
                }
            }
        } catch {
            print("Error exporting PDF: \(error)")
        }
    }
    #endif

    // MARK: - Archive Creation

    /// Creates an archive of the handover report for future reference
    func createArchive(options: ExportOptions, pdfData: Data? = nil, modelContext: ModelContext) {
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

        // Store PDF data (optional - can be large)
        archive.pdfData = pdfData

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

