//
//  PadDashboardView.swift
//  Josh Well Control for Mac
//
//  Dashboard view for a pad showing location info, wells list, and notes/tasks
//

import SwiftUI
import SwiftData
import CoreLocation
import Combine

struct PadDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<LookAheadSchedule> { $0.isActive }, sort: \LookAheadSchedule.updatedAt, order: .reverse) private var activeSchedules: [LookAheadSchedule]
    @Bindable var pad: Pad

    // Optional navigation callback for wells (to navigate in main view, not sheet)
    // If not provided, wells will open in a sheet instead
    var onSelectWell: ((Well) -> Void)?

    @State private var showingAddNote = false
    @State private var showingAddTask = false
    @State private var showingAddWell = false
    @State private var showingNewPad = false
    @State private var showingDeleteConfirmation = false

    // GPS capture state
    @StateObject private var locationHelper = PadLocationHelper()

    // Navigation states for items that open in sheets
    @State private var selectedWellForSheet: Well?  // Fallback when onSelectWell is nil
    @State private var selectedRental: RentalItem?
    @State private var selectedTransfer: MaterialTransfer?
    @State private var selectedNote: HandoverNote?
    @State private var selectedTask: WellTask?
    @State private var selectedLookAheadTask: LookAheadTask?
    @State private var showingAddLookAheadTask = false
    @State private var showingOnLocationReport = false

    private var pageBackgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .underPageBackgroundColor)
        #else
        Color(.systemGroupedBackground)
        #endif
    }

    // Aggregated stats across all wells in this pad
    private var totalRentals: Int {
        (pad.wells ?? []).reduce(0) { $0 + ($1.rentals?.count ?? 0) }
    }

    private var totalTransfers: Int {
        (pad.wells ?? []).reduce(0) { $0 + ($1.transfers?.count ?? 0) }
    }

    private var totalProjects: Int {
        (pad.wells ?? []).reduce(0) { $0 + ($1.projects?.count ?? 0) }
    }

    // Aggregation helpers — computed once per section body via local lets (see each section)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                header

                // Pad info section
                padInfoSection

                // Summary stats
                summarySection

                #if os(macOS)
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        wellsSection
                        rentalsSection
                        transfersSection
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 16) {
                        workDaysSection
                        lookAheadSection
                        notesSection
                        tasksSection
                    }
                    .frame(maxWidth: .infinity)
                }
                #else
                wellsSection
                workDaysSection
                rentalsSection
                transfersSection
                lookAheadSection
                notesSection
                tasksSection
                #endif
            }
            .padding(24)
        }
        .background(pageBackgroundColor)
        .navigationTitle("Pad Dashboard")
        .sheet(isPresented: $showingAddNote) {
            NoteEditorView(pad: pad, note: nil)
        }
        .sheet(isPresented: $showingAddTask) {
            TaskEditorView(pad: pad, task: nil)
        }
        .sheet(isPresented: $showingAddWell) {
            AddWellToPadSheet(pad: pad)
        }
        .sheet(isPresented: $showingNewPad) {
            NewPadSheet()
        }
        .alert("Delete Pad?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                modelContext.delete(pad)
                try? modelContext.save()
            }
        } message: {
            Text("Are you sure you want to delete \"\(pad.name)\"? Wells assigned to this pad will be unassigned but not deleted.")
        }
        // Navigation sheets — wrapper views hold @Query so queries only run when sheet opens
        .sheet(item: $selectedRental) { rental in
            RentalEditorSheetContent(rental: rental)
        }
        .sheet(item: $selectedTransfer) { transfer in
            if let well = transfer.well {
                MaterialTransferEditorView(well: well, transfer: transfer)
            }
        }
        .sheet(item: $selectedNote) { note in
            NoteEditorView(pad: pad, note: note)
        }
        .sheet(item: $selectedTask) { task in
            TaskEditorView(pad: pad, task: task)
        }
        .sheet(item: $selectedWellForSheet) { well in
            WellDashboardView(well: well)
        }
        .sheet(item: $selectedLookAheadTask) { task in
            LookAheadEditorSheetContent(schedule: task.schedule, task: task)
        }
        .sheet(isPresented: $showingAddLookAheadTask) {
            LookAheadEditorSheetContent(schedule: activeSchedule, task: nil)
        }
        #if os(macOS)
        .sheet(isPresented: $showingOnLocationReport) {
            OnLocationReportSheetContent(pad: pad)
        }
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(pad.name)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Overview including wells and handover items.")
                    .foregroundStyle(.secondary)
            }
            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                Button(action: { showingNewPad = true }) {
                    Label("New Pad", systemImage: "plus")
                }
                .buttonStyle(.borderless)

                Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.borderless)

                // Lock toggle button
                Button {
                    pad.isLocked.toggle()
                    try? modelContext.save()
                } label: {
                    Label(
                        pad.isLocked ? "Unlock" : "Lock",
                        systemImage: pad.isLocked ? "lock.fill" : "lock.open"
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(pad.isLocked ? Color.orange.opacity(0.2) : Color.green.opacity(0.2))
                    .foregroundStyle(pad.isLocked ? .orange : .green)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help(pad.isLocked ? "Unlock pad for editing" : "Lock pad to prevent accidental edits")
            }
        }
    }

    // MARK: - Pad Info Section

    private var padInfoSection: some View {
        WellSection(title: "Pad Information", icon: "map", subtitle: "Location and identifiers") {
            VStack(alignment: .leading, spacing: 12) {
                #if os(macOS)
                HStack(alignment: .top, spacing: 32) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Name").foregroundStyle(.secondary)
                            TextField("Pad name", text: $pad.name)
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Surface Location").foregroundStyle(.secondary)
                            TextField("Surface location", text: $pad.surfaceLocation)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                            GridRow {
                                Text("Latitude").foregroundStyle(.secondary)
                                TextField("Latitude", value: $pad.latitude, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .monospacedDigit()
                            }
                            GridRow {
                                Text("Longitude").foregroundStyle(.secondary)
                                TextField("Longitude", value: $pad.longitude, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .monospacedDigit()
                            }
                        }

                        // GPS capture button
                        Button {
                            captureCurrentLocation()
                        } label: {
                            HStack(spacing: 4) {
                                if locationHelper.isCapturing {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                } else {
                                    Image(systemName: "location.fill")
                                }
                                Text("Get Current Location")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(locationHelper.isCapturing || pad.isLocked)

                        if let error = locationHelper.error {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Wells").foregroundStyle(.secondary)
                            Text("\(pad.wells?.count ?? 0)")
                                .fontWeight(.medium)
                        }
                        GridRow {
                            Text("Created").foregroundStyle(.secondary)
                            Text(pad.createdAt.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                    Spacer()
                }
                .allowsHitTesting(!pad.isLocked)
                #else
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Name").foregroundStyle(.secondary)
                        TextField("Pad name", text: $pad.name)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Surface Location").foregroundStyle(.secondary)
                        TextField("Surface location", text: $pad.surfaceLocation)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Latitude").foregroundStyle(.secondary)
                        TextField("Latitude", value: $pad.latitude, format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Longitude").foregroundStyle(.secondary)
                        TextField("Longitude", value: $pad.longitude, format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Wells").foregroundStyle(.secondary)
                        Text("\(pad.wells?.count ?? 0)")
                    }
                }
                .allowsHitTesting(!pad.isLocked)

                // GPS capture button (iOS)
                Button {
                    captureCurrentLocation()
                } label: {
                    HStack(spacing: 4) {
                        if locationHelper.isCapturing {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "location.fill")
                        }
                        Text("Get Current Location")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(locationHelper.isCapturing || pad.isLocked)
                .padding(.top, 8)

                if let error = locationHelper.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                #endif

                // Directions - multi-line
                VStack(alignment: .leading, spacing: 4) {
                    Text("Directions")
                        .foregroundStyle(.secondary)
                    TextEditor(text: $pad.directions)
                        .font(.body)
                        .frame(minHeight: 60)
                        .padding(4)
                        .background(Color(white: 0.5, opacity: 0.1))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .allowsHitTesting(!pad.isLocked)
                    if pad.directions.isEmpty && !pad.isLocked {
                        Text("Add driving directions to the pad location")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        WellSection(title: "Summary", icon: "chart.bar", subtitle: "Aggregated totals across all wells") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                PadSummaryCard(title: "Wells", value: "\(pad.wells?.count ?? 0)", icon: "building.2", color: .blue)
                PadSummaryCard(title: "Projects", value: "\(totalProjects)", icon: "folder", color: .purple)
                PadSummaryCard(title: "Rentals", value: "\(totalRentals)", icon: "bag", color: .orange)
                PadSummaryCard(title: "Transfers", value: "\(totalTransfers)", icon: "arrow.left.arrow.right.circle", color: .green)
                PadSummaryCard(title: "Notes", value: "\(pad.notes?.count ?? 0)", icon: "note.text", color: .yellow)
                PadSummaryCard(title: "Tasks", value: "\(padPendingTasks.count)", icon: "checkmark.circle", color: .red)
            }
        }
    }

    // MARK: - Wells Section

    private var sortedWells: [Well] {
        (pad.wells ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var wellsSection: some View {
        WellSection(title: "Wells", icon: "building.2", subtitle: "\(pad.wells?.count ?? 0) well(s) on this pad") {
            VStack(alignment: .leading, spacing: 8) {
                if !sortedWells.isEmpty {
                    PaginatedList(items: sortedWells, pageSize: 5) { well in
                        Button {
                            if let callback = onSelectWell {
                                callback(well)
                            } else {
                                selectedWellForSheet = well
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(well.name)
                                            .fontWeight(.medium)
                                        if well.isFavorite {
                                            Image(systemName: "star.fill")
                                                .foregroundStyle(.yellow)
                                                .font(.caption)
                                        }
                                    }
                                    if let uwi = well.uwi, !uwi.isEmpty {
                                        Text(uwi)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                HStack(spacing: 16) {
                                    Label("\(well.projects?.count ?? 0)", systemImage: "folder")
                                    Label("\(well.rentals?.count ?? 0)", systemImage: "bag")
                                    Label("\(well.transfers?.count ?? 0)", systemImage: "arrow.left.arrow.right")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    StandardEmptyState(icon: "building.2", title: "No Wells", description: "Add wells to this pad to get started")
                }

                Button(action: { showingAddWell = true }) {
                    Label("Add Well", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Rentals Section

    private var rentalsSection: some View {
        let allRentals = (pad.wells ?? []).flatMap { $0.rentals ?? [] }
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
        let onLocation = allRentals.filter { $0.onLocation && !$0.invoiced }
        let totalCost = allRentals.reduce(0) { $0 + $1.totalCost }
        let uninvoicedCost = allRentals.filter { !$0.invoiced }.reduce(0) { $0 + $1.totalCost }

        return WellSection(
            title: "Rentals",
            icon: "bag",
            subtitle: "\(onLocation.count) on location • \(allRentals.count) total"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // Summary stats
                if !allRentals.isEmpty {
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Total Cost")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(totalCost, format: .currency(code: "CAD"))
                                .font(.headline)
                                .fontWeight(.bold)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Uninvoiced")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(uninvoicedCost, format: .currency(code: "CAD"))
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundStyle(uninvoicedCost > 0 ? .orange : .green)
                        }

                        Spacer()

                        #if os(macOS)
                        Button("On Location Report", systemImage: "doc.text") {
                            showingOnLocationReport = true
                        }
                        .buttonStyle(.borderless)
                        .disabled(onLocation.isEmpty)
                        #endif
                    }
                    .padding(.bottom, 8)

                    Divider()

                    PaginatedList(items: allRentals, pageSize: 5) { rental in
                        Button {
                            selectedRental = rental
                        } label: {
                            PadRentalRow(rental: rental)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    StandardEmptyState(icon: "bag", title: "No Rentals", description: "No rental items for wells on this pad")
                }
            }
        }
    }

    // MARK: - Transfers Section

    private var transfersSection: some View {
        let allTransfers = (pad.wells ?? []).flatMap { $0.transfers ?? [] }
            .sorted { $0.date > $1.date }
        let pending = allTransfers.filter { !$0.isShippedBack }
        let totalItems = allTransfers.reduce(0) { $0 + ($1.items?.count ?? 0) }

        return WellSection(
            title: "Material Transfers",
            icon: "arrow.left.arrow.right.circle",
            subtitle: "\(pending.count) pending • \(totalItems) items"
        ) {
            if !allTransfers.isEmpty {
                PaginatedList(items: allTransfers, pageSize: 5) { transfer in
                    Button {
                        selectedTransfer = transfer
                    } label: {
                        PadTransferRow(transfer: transfer)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                StandardEmptyState(icon: "arrow.left.arrow.right.circle", title: "No Transfers", description: "No material transfers for wells on this pad")
            }
        }
    }

    // MARK: - Work Days Section

    private var workDaysSection: some View {
        let allWorkDays = (pad.wells ?? []).flatMap { $0.workDays ?? [] }
            .sorted { $0.startDate > $1.startDate }
        let totalDays = allWorkDays.reduce(0) { $0 + $1.dayCount }
        let totalEarnings = allWorkDays.reduce(0) { $0 + $1.totalEarnings }
        let uninvoicedEarnings = allWorkDays.filter { !$0.isInvoiced }.reduce(0) { $0 + $1.totalEarnings }

        return WellSection(
            title: "Work Days",
            icon: "calendar.badge.clock",
            subtitle: "\(totalDays) day(s) • \(totalEarnings.formatted(.currency(code: "CAD")))"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                // Summary stats
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total Days")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(totalDays)")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total Earnings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(totalEarnings.formatted(.currency(code: "CAD")))
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Uninvoiced")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(uninvoicedEarnings.formatted(.currency(code: "CAD")))
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(uninvoicedEarnings > 0 ? .orange : .green)
                    }
                }
                .padding(.bottom, 8)

                if !allWorkDays.isEmpty {
                    Divider()

                    PaginatedList(items: allWorkDays, pageSize: 5) { workDay in
                        PadWorkDayRow(workDay: workDay)
                    }
                } else {
                    Text("No work days recorded for wells on this pad")
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
        }
    }

    // MARK: - Notes Section

    private var sortedPadNotes: [HandoverNote] {
        (pad.notes ?? []).sorted { $0.updatedAt > $1.updatedAt }
    }

    private var notesSection: some View {
        WellSection(title: "Pad Notes", icon: "note.text", subtitle: "\(pad.notes?.count ?? 0) note(s)") {
            VStack(alignment: .leading, spacing: 8) {
                if !sortedPadNotes.isEmpty {
                    PaginatedList(items: sortedPadNotes, pageSize: 5) { note in
                        Button {
                            selectedNote = note
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                if note.isPinned {
                                    Image(systemName: "pin.fill")
                                        .foregroundStyle(.orange)
                                        .font(.caption)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(note.title)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                    if !note.content.isEmpty {
                                        Text(note.content)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                                Text(note.category.rawValue)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    StandardEmptyState(icon: "note.text", title: "No Notes", description: "Add pad-level notes to share across all wells")
                }

                Button(action: { showingAddNote = true }) {
                    Label("Add Note", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Tasks Section

    private var padPendingTasks: [WellTask] {
        (pad.tasks ?? []).filter { $0.isPending }.sorted { $0.priority.sortOrder < $1.priority.sortOrder }
    }

    private var tasksSection: some View {
        WellSection(title: "Pad Tasks", icon: "checkmark.circle", subtitle: "\(padPendingTasks.count) pending") {
            VStack(alignment: .leading, spacing: 8) {
                if !padPendingTasks.isEmpty {
                    PaginatedList(items: padPendingTasks, pageSize: 5) { task in
                        Button {
                            selectedTask = task
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(task.status == .completed ? .green : priorityColor(task.priority))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                        .fontWeight(.medium)
                                        .strikethrough(task.status == .completed)
                                        .lineLimit(1)
                                    if let dueDate = task.dueDate {
                                        Text("Due: \(dueDate.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption)
                                            .foregroundStyle(task.isOverdue ? .red : .secondary)
                                    }
                                }
                                Spacer()
                                Text(task.priority.rawValue)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(priorityColor(task.priority).opacity(0.1))
                                    .foregroundStyle(priorityColor(task.priority))
                                    .cornerRadius(4)

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    StandardEmptyState(icon: "checkmark.circle", title: "No Pending Tasks", description: "Add tasks to track pad-level work items")
                }

                Button(action: { showingAddTask = true }) {
                    Label("Add Task", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Look Ahead Section

    /// All Look Ahead tasks from wells on this pad, sorted by start time
    private var padLookAheadTasks: [LookAheadTask] {
        (pad.wells ?? [])
            .flatMap { $0.lookAheadTasks ?? [] }
            .filter { $0.status != .completed && $0.status != .cancelled }
            .sorted { $0.startTime < $1.startTime }
    }

    private var activeSchedule: LookAheadSchedule? {
        activeSchedules.first
    }

    private var lookAheadSection: some View {
        WellSection(
            title: "Look Ahead",
            icon: "calendar.badge.clock",
            subtitle: "\(padLookAheadTasks.count) upcoming task(s)"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if !padLookAheadTasks.isEmpty {
                    PaginatedList(items: padLookAheadTasks, pageSize: 5) { task in
                        Button {
                            selectedLookAheadTask = task
                        } label: {
                            PadLookAheadTaskRow(task: task)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Text("No scheduled look ahead tasks for wells on this pad")
                        .foregroundStyle(.secondary)
                        .italic()
                }

                if activeSchedule != nil {
                    Button(action: { showingAddLookAheadTask = true }) {
                        Label("Add Look Ahead Task", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 4)
                }
            }
        }
    }

    private func lookAheadStatusColor(_ status: LookAheadTaskStatus) -> Color {
        switch status {
        case .scheduled: return .blue
        case .inProgress: return .orange
        case .completed: return .green
        case .delayed: return .red
        case .cancelled: return .gray
        }
    }

    private func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .low: return .green
        case .medium: return .blue
        case .high: return .orange
        case .critical: return .red
        }
    }

    // MARK: - Location Capture

    private func captureCurrentLocation() {
        locationHelper.captureLocation { latitude, longitude in
            pad.latitude = latitude
            pad.longitude = longitude
            try? modelContext.save()
        }
    }
}

// MARK: - Sheet Wrapper Views (deferred @Query)

/// Wraps RentalDetailEditor so the @Query for equipment only runs when the sheet is presented.
struct RentalEditorSheetContent: View {
    @Query(sort: \RentalEquipment.name) private var allEquipment: [RentalEquipment]
    let rental: RentalItem

    var body: some View {
        RentalDetailEditor(rental: rental, allEquipment: allEquipment)
            .environment(\.locale, Locale(identifier: "en_GB"))
            #if os(macOS)
            .standardSheetSize(.large)
            #endif
    }
}

/// Wraps LookAheadTaskEditorView so @Query for jobCodes/vendors/wells only runs when the sheet is presented.
struct LookAheadEditorSheetContent: View {
    @Query(sort: \JobCode.name) private var jobCodes: [JobCode]
    @Query(sort: \Vendor.companyName) private var vendors: [Vendor]
    @Query(sort: \Well.name) private var allWells: [Well]
    let schedule: LookAheadSchedule?
    let task: LookAheadTask?
    var preselectedWell: Well? = nil

    var body: some View {
        LookAheadTaskEditorView(
            schedule: schedule,
            task: task,
            jobCodes: jobCodes,
            vendors: vendors,
            wells: allWells,
            preselectedWell: preselectedWell
        )
    }
}

/// Wraps CloseOutWellSheet so the @Query for allWells only runs when the sheet is presented.
struct CloseOutSheetContent: View {
    @Query(sort: \Well.name) private var allWells: [Well]
    let sourceWell: Well
    let equipment: [RentalEquipment]

    var body: some View {
        CloseOutWellSheet(sourceWell: sourceWell, equipment: equipment, allWells: allWells)
    }
}

#if os(macOS)
/// Wraps PadRentalsOnLocationReportPreview so the aggregation only runs when the sheet is presented.
private struct OnLocationReportSheetContent: View {
    let pad: Pad

    private var onLocationRentals: [RentalItem] {
        (pad.wells ?? []).flatMap { $0.rentals ?? [] }
            .filter { $0.onLocation && !$0.invoiced }
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }

    var body: some View {
        PadRentalsOnLocationReportPreview(pad: pad, rentals: onLocationRentals)
    }
}
#endif

// MARK: - Pad Summary Card

private struct PadSummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Add Pad Note Sheet

private struct AddPadNoteSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let pad: Pad

    @State private var title = ""
    @State private var content = ""
    @State private var category: NoteCategory = .general
    @State private var isPinned = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextEditor(text: $content)
                    .frame(minHeight: 100)
                Picker("Category", selection: $category) {
                    ForEach(NoteCategory.allCases, id: \.self) { cat in
                        Text(cat.rawValue).tag(cat)
                    }
                }
                Toggle("Pin to top", isOn: $isPinned)
            }
            .navigationTitle("Add Pad Note")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let note = HandoverNote(
                            title: title,
                            content: content,
                            category: category,
                            isPinned: isPinned
                        )
                        modelContext.insert(note)
                        note.pad = pad  // SwiftData automatically manages the inverse relationship
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
        #if os(macOS)
        .standardSheetSize(.small)
        #endif
    }
}

// MARK: - Add Pad Task Sheet

private struct AddPadTaskSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let pad: Pad

    @State private var title = ""
    @State private var description = ""
    @State private var priority: TaskPriority = .medium
    @State private var hasDueDate = false
    @State private var dueDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextEditor(text: $description)
                    .frame(minHeight: 80)
                Picker("Priority", selection: $priority) {
                    ForEach(TaskPriority.allCases, id: \.self) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                Toggle("Has due date", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("Due date", selection: $dueDate)
                }
            }
            .navigationTitle("Add Pad Task")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let task = WellTask(
                            title: title,
                            description: description,
                            priority: priority,
                            dueDate: hasDueDate ? dueDate : nil
                        )
                        modelContext.insert(task)
                        task.pad = pad  // SwiftData automatically manages the inverse relationship
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
        #if os(macOS)
        .standardSheetSize(.small)
        #endif
    }
}

// MARK: - Add Well To Pad Sheet

private struct AddWellToPadSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let pad: Pad

    @State private var name = ""
    @State private var uwi = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Well Details") {
                    TextField("Well Name", text: $name)
                    TextField("UWI (optional)", text: $uwi)
                }
            }
            .navigationTitle("Add Well")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let well = Well(name: name.isEmpty ? "New Well" : name)
                        well.uwi = uwi.isEmpty ? nil : uwi
                        well.pad = pad
                        if pad.wells == nil { pad.wells = [] }
                        pad.wells?.append(well)
                        // Create a default project for the well
                        let project = ProjectState()
                        project.well = well
                        well.projects = [project]
                        modelContext.insert(well)
                        modelContext.insert(project)
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .standardSheetSize(.small)
        #endif
    }
}

// MARK: - New Pad Sheet

private struct NewPadSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var surfaceLocation = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Pad Details") {
                    TextField("Pad Name", text: $name)
                    TextField("Surface Location (optional)", text: $surfaceLocation)
                }
            }
            .navigationTitle("New Pad")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let newPad = Pad(
                            name: name.isEmpty ? "New Pad" : name,
                            surfaceLocation: surfaceLocation
                        )
                        modelContext.insert(newPad)
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .standardSheetSize(.small)
        #endif
    }
}

// MARK: - Pad Rental Row

private struct PadRentalRow: View {
    let rental: RentalItem

    private var statusColor: Color {
        if rental.onLocation { return .green }
        if rental.invoiced { return .blue }
        return .orange
    }

    private var statusText: String {
        if rental.onLocation { return "On Location" }
        if rental.invoiced { return "Invoiced" }
        return "Pending"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(rental.name)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if let well = rental.well {
                        Text("• \(well.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 8) {
                    if rental.totalDays > 0 {
                        Text("\(rental.totalDays) days")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let start = rental.startDate {
                        Text(start.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(rental.totalCost, format: .currency(code: "CAD"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .monospacedDigit()

                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Pad Transfer Row

private struct PadTransferRow: View {
    let transfer: MaterialTransfer

    private var statusColor: Color {
        if transfer.isShippedBack { return .green }
        if transfer.isShippingOut { return .blue }
        return .orange
    }

    private var statusText: String {
        if transfer.isShippedBack { return "Complete" }
        if transfer.isShippingOut { return "Outgoing" }
        return "Incoming"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Transfer #\(transfer.number)")
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if let well = transfer.well {
                        Text("• \(well.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 8) {
                    Text(transfer.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let itemCount = transfer.items?.count, itemCount > 0 {
                        Text("\(itemCount) item\(itemCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(statusText)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(statusColor)

                if let dest = transfer.destinationName, !dest.isEmpty {
                    Text(dest)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Pad Look Ahead Task Row

private struct PadLookAheadTaskRow: View {
    let task: LookAheadTask

    private var statusColor: Color {
        switch task.status {
        case .scheduled: return .blue
        case .inProgress: return .orange
        case .completed: return .green
        case .delayed: return .red
        case .cancelled: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(task.name)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if let jc = task.jobCode {
                        Text(jc.code)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(3)
                    }

                    if let well = task.well {
                        Text("• \(well.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 8) {
                    Text(task.startTime.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("(\(task.estimatedDurationFormatted))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Vendor/call status
            if !task.assignedVendors.isEmpty {
                if task.hasConfirmedCall {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Image(systemName: "phone.badge.waveform")
                        .foregroundStyle(task.isCallOverdue ? .red : .orange)
                        .font(.caption)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Pad Work Day Row

private struct PadWorkDayRow: View {
    let workDay: WorkDay

    private var statusColor: Color {
        if workDay.isPaid { return .green }
        if workDay.isInvoiced { return .blue }
        return .orange
    }

    private var statusIcon: String {
        if workDay.isPaid { return "checkmark.circle.fill" }
        if workDay.isInvoiced { return "doc.text.fill" }
        return "circle"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(workDay.dateRangeString)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if let well = workDay.well {
                        Text("• \(well.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 8) {
                    Text("\(workDay.dayCount) day\(workDay.dayCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let client = workDay.client {
                        Text("• \(client.companyName)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Text(workDay.totalEarnings.formatted(.currency(code: "CAD")))
                .font(.subheadline)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Pad Location Helper

/// Helper class for capturing GPS location for pads (works on both macOS and iOS)
@MainActor
class PadLocationHelper: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isCapturing = false
    @Published var error: String?

    private let locationManager = CLLocationManager()
    private var completion: ((Double, Double) -> Void)?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func captureLocation(completion: @escaping (Double, Double) -> Void) {
        self.completion = completion
        self.error = nil
        self.isCapturing = true

        // Check authorization
        let status = locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            #if os(iOS)
            locationManager.requestWhenInUseAuthorization()
            #else
            // macOS uses requestAlwaysAuthorization for location services
            // But for one-time capture, we can just request location
            locationManager.requestLocation()
            #endif
        case .restricted, .denied:
            self.isCapturing = false
            self.error = "Location access denied. Enable in System Settings."
        #if os(iOS)
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        #else
        case .authorizedAlways:
            locationManager.requestLocation()
        #endif
        @unknown default:
            self.isCapturing = false
            self.error = "Unknown authorization status"
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            self.isCapturing = false
            self.completion?(location.coordinate.latitude, location.coordinate.longitude)
            self.completion = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.isCapturing = false
            self.error = error.localizedDescription
            self.completion = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            #if os(iOS)
            let isAuthorized = status == .authorizedWhenInUse || status == .authorizedAlways
            #else
            let isAuthorized = status == .authorizedAlways
            #endif

            if isAuthorized {
                if self.isCapturing {
                    manager.requestLocation()
                }
            } else if status == .denied || status == .restricted {
                self.isCapturing = false
                self.error = "Location access denied"
            }
        }
    }
}
