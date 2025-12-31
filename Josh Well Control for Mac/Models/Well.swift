//
//  Well.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-07.
//

import Foundation
import SwiftData

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

@Model
final class Well {
    var id: UUID = UUID()
    var name: String = "New Well"
    var uwi: String? = nil
    var afeNumber: String? = nil
    var requisitioner: String? = nil
    var rigName: String? = nil
    var costCode: String? = nil
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    // Filtering & organization
    var isFavorite: Bool = false
    var isArchived: Bool = false
    var isLocked: Bool = false
    var lastAccessedAt: Date?

    // Survey reference elevations
    var kbElevation_m: Double?      // Kelly Bushing elevation above sea level (m)
    var groundElevation_m: Double?  // Ground level elevation above sea level (m)

    @Relationship var pad: Pad?

    @Relationship(deleteRule: .nullify, inverse: \ProjectState.well) var projects: [ProjectState]?
    @Relationship(deleteRule: .nullify, inverse: \MaterialTransfer.well) var transfers: [MaterialTransfer]?
    @Relationship(deleteRule: .nullify, inverse: \RentalItem.well) var rentals: [RentalItem]?
    @Relationship(deleteRule: .nullify, inverse: \WorkDay.well) var workDays: [WorkDay]?
    @Relationship(deleteRule: .nullify, inverse: \InvoiceLineItem.well) var invoiceLineItems: [InvoiceLineItem]?
    @Relationship(deleteRule: .nullify, inverse: \Expense.well) var expenses: [Expense]?
    @Relationship(deleteRule: .nullify, inverse: \MileageLog.well) var mileageLogs: [MileageLog]?
    @Relationship(deleteRule: .cascade, inverse: \WellTask.well) var tasks: [WellTask]?
    @Relationship(deleteRule: .cascade, inverse: \HandoverNote.well) var notes: [HandoverNote]?

    // Look Ahead Scheduler
    @Relationship(deleteRule: .nullify, inverse: \LookAheadTask.well) var lookAheadTasks: [LookAheadTask]?
    @Relationship(deleteRule: .nullify, inverse: \LookAheadSchedule.well) var lookAheadSchedules: [LookAheadSchedule]?

    // Directional Planning
    @Relationship(deleteRule: .cascade, inverse: \DirectionalPlan.well) var directionalPlans: [DirectionalPlan]?

    init(name: String = "New Well", uwi: String? = nil, afeNumber: String? = nil, requisitioner: String? = nil) {
        self.name = name
        self.uwi = uwi
        self.afeNumber = afeNumber
        self.requisitioner = requisitioner
    }
}

extension Well {
    // MARK: - Task helpers

    var pendingTasks: [WellTask] {
        (tasks ?? []).filter { $0.isPending }.sorted { $0.priority.sortOrder < $1.priority.sortOrder }
    }

    var overdueTasks: [WellTask] {
        (tasks ?? []).filter { $0.isOverdue }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var completedTasks: [WellTask] {
        (tasks ?? []).filter { $0.status == .completed }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    func createTask(title: String, description: String = "", priority: TaskPriority = .medium, dueDate: Date? = nil, author: String = "", context: ModelContext) -> WellTask {
        let task = WellTask(title: title, description: description, priority: priority, dueDate: dueDate, author: author)
        task.well = self
        if tasks == nil { tasks = [] }
        tasks?.append(task)
        context.insert(task)
        return task
    }

    // MARK: - Note helpers

    var pinnedNotes: [HandoverNote] {
        (notes ?? []).filter { $0.isPinned }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var recentNotes: [HandoverNote] {
        (notes ?? []).sorted { $0.updatedAt > $1.updatedAt }
    }

    func createNote(title: String, content: String = "", category: NoteCategory = .general, author: String = "", isPinned: Bool = false, context: ModelContext) -> HandoverNote {
        let note = HandoverNote(title: title, content: content, category: category, author: author, isPinned: isPinned)
        note.well = self
        if notes == nil { notes = [] }
        notes?.append(note)
        context.insert(note)
        return note
    }

    // MARK: - Transfer helpers

    func createTransfer(number: Int? = nil, context: ModelContext) -> MaterialTransfer {
        let transferNumber = number ?? (((transfers ?? []).map { $0.number }.max() ?? 0) + 1)
        let transfer = MaterialTransfer(number: transferNumber)
        transfer.well = self
        if transfers == nil { transfers = [] }
        transfers?.append(transfer)
        context.insert(transfer)
        return transfer
    }

    /// Generate PDF for a material transfer using the cross-platform PDF generator
    func generateTransferPDF(_ transfer: MaterialTransfer, pageSize: CGSize = CGSize(width: 612, height: 792)) -> Data? {
        return MaterialTransferPDFGenerator.shared.generatePDF(for: transfer, well: self, pageSize: pageSize)
    }
}

