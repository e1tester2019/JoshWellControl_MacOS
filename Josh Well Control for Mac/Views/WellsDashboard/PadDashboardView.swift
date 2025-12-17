//
//  PadDashboardView.swift
//  Josh Well Control for Mac
//
//  Dashboard view for a pad showing location info, wells list, and notes/tasks
//

import SwiftUI
import SwiftData

struct PadDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Pad.name) private var allPads: [Pad]
    @Bindable var pad: Pad

    // Optional navigation callback for wells (to navigate in main view, not sheet)
    // If not provided, wells will open in a sheet instead
    var onSelectWell: ((Well) -> Void)?

    @State private var showingAddNote = false
    @State private var showingAddTask = false
    @State private var showingAddWell = false
    @State private var showingNewPad = false
    @State private var showingDeleteConfirmation = false

    // Navigation states for items that open in sheets
    @State private var selectedWellForSheet: Well?  // Fallback when onSelectWell is nil
    @State private var selectedRental: RentalItem?
    @State private var selectedTransfer: MaterialTransfer?
    @State private var selectedNote: HandoverNote?
    @State private var selectedTask: WellTask?

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

    // All rentals from wells on this pad
    private var allPadRentals: [RentalItem] {
        (pad.wells ?? []).flatMap { $0.rentals ?? [] }
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }

    private var onLocationRentals: [RentalItem] {
        allPadRentals.filter { $0.onLocation }
    }

    private var totalRentalCost: Double {
        allPadRentals.reduce(0) { $0 + $1.totalCost }
    }

    private var uninvoicedRentalCost: Double {
        allPadRentals.filter { !$0.invoiced }.reduce(0) { $0 + $1.totalCost }
    }

    // All material transfers from wells on this pad
    private var allPadTransfers: [MaterialTransfer] {
        (pad.wells ?? []).flatMap { $0.transfers ?? [] }
            .sorted { $0.date > $1.date }
    }

    private var pendingTransfers: [MaterialTransfer] {
        allPadTransfers.filter { !$0.isShippedBack }
    }

    private var totalTransferItems: Int {
        allPadTransfers.reduce(0) { $0 + ($1.items?.count ?? 0) }
    }

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
                        notesSection
                        tasksSection
                    }
                    .frame(maxWidth: .infinity)
                }
                #else
                wellsSection
                rentalsSection
                transfersSection
                notesSection
                tasksSection
                #endif
            }
            .padding(24)
        }
        .background(pageBackgroundColor)
        .navigationTitle("Pad Dashboard")
        .sheet(isPresented: $showingAddNote) {
            AddPadNoteSheet(pad: pad)
        }
        .sheet(isPresented: $showingAddTask) {
            AddPadTaskSheet(pad: pad)
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
        // Navigation sheets
        .sheet(item: $selectedRental) { rental in
            RentalDetailEditor(rental: rental)
                .environment(\.locale, Locale(identifier: "en_GB"))
                #if os(macOS)
                .frame(minWidth: 720, minHeight: 520)
                #endif
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
                #endif

                // Directions - multi-line
                VStack(alignment: .leading, spacing: 4) {
                    Text("Directions")
                        .foregroundStyle(.secondary)
                    TextEditor(text: $pad.directions)
                        .font(.body)
                        .frame(minHeight: 60, maxHeight: 120)
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

    private var wellsSection: some View {
        WellSection(title: "Wells", icon: "building.2", subtitle: "\(pad.wells?.count ?? 0) well(s) on this pad") {
            VStack(alignment: .leading, spacing: 8) {
                if let wells = pad.wells, !wells.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(wells.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })) { well in
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

                            if well.id != wells.last?.id {
                                Divider()
                            }
                        }
                    }
                } else {
                    Text("No wells on this pad")
                        .foregroundStyle(.secondary)
                        .italic()
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
        WellSection(
            title: "Rentals",
            icon: "bag",
            subtitle: "\(onLocationRentals.count) on location • \(allPadRentals.count) total"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // Summary stats
                if !allPadRentals.isEmpty {
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Total Cost")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(totalRentalCost, format: .currency(code: "CAD"))
                                .font(.headline)
                                .fontWeight(.bold)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Uninvoiced")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(uninvoicedRentalCost, format: .currency(code: "CAD"))
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundStyle(uninvoicedRentalCost > 0 ? .orange : .green)
                        }

                        Spacer()
                    }
                    .padding(.bottom, 8)

                    Divider()
                }

                // On-location rentals (most important)
                if !onLocationRentals.isEmpty {
                    Text("On Location")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    ForEach(onLocationRentals.prefix(5)) { rental in
                        Button {
                            selectedRental = rental
                        } label: {
                            PadRentalRow(rental: rental)
                        }
                        .buttonStyle(.plain)
                    }

                    if onLocationRentals.count > 5 {
                        Text("+ \(onLocationRentals.count - 5) more on location")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Recent rentals (not on location)
                let recentOffLocation = allPadRentals.filter { !$0.onLocation }.prefix(3)
                if !recentOffLocation.isEmpty {
                    if !onLocationRentals.isEmpty {
                        Divider()
                            .padding(.vertical, 4)
                    }

                    Text("Recent")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    ForEach(Array(recentOffLocation)) { rental in
                        Button {
                            selectedRental = rental
                        } label: {
                            PadRentalRow(rental: rental)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if allPadRentals.isEmpty {
                    Text("No rentals for wells on this pad")
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
        }
    }

    // MARK: - Transfers Section

    private var transfersSection: some View {
        WellSection(
            title: "Material Transfers",
            icon: "arrow.left.arrow.right.circle",
            subtitle: "\(pendingTransfers.count) pending • \(totalTransferItems) items"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if !allPadTransfers.isEmpty {
                    // Pending transfers first
                    if !pendingTransfers.isEmpty {
                        Text("Pending")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        ForEach(pendingTransfers.prefix(5)) { transfer in
                            Button {
                                selectedTransfer = transfer
                            } label: {
                                PadTransferRow(transfer: transfer)
                            }
                            .buttonStyle(.plain)
                        }

                        if pendingTransfers.count > 5 {
                            Text("+ \(pendingTransfers.count - 5) more pending")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Completed transfers
                    let completedTransfers = allPadTransfers.filter { $0.isShippedBack }
                    if !completedTransfers.isEmpty {
                        if !pendingTransfers.isEmpty {
                            Divider()
                                .padding(.vertical, 4)
                        }

                        Text("Completed")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        ForEach(completedTransfers.prefix(3)) { transfer in
                            Button {
                                selectedTransfer = transfer
                            } label: {
                                PadTransferRow(transfer: transfer)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Text("No material transfers for wells on this pad")
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        WellSection(title: "Pad Notes", icon: "note.text", subtitle: "\(pad.notes?.count ?? 0) note(s)") {
            VStack(alignment: .leading, spacing: 8) {
                if let notes = pad.notes, !notes.isEmpty {
                    ForEach(notes.sorted(by: { $0.updatedAt > $1.updatedAt }).prefix(5)) { note in
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

                    if (pad.notes?.count ?? 0) > 5 {
                        Text("+ \((pad.notes?.count ?? 0) - 5) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No notes for this pad")
                        .foregroundStyle(.secondary)
                        .italic()
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
                    ForEach(padPendingTasks.prefix(5)) { task in
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

                    if padPendingTasks.count > 5 {
                        Text("+ \(padPendingTasks.count - 5) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No pending tasks")
                        .foregroundStyle(.secondary)
                        .italic()
                }

                Button(action: { showingAddTask = true }) {
                    Label("Add Task", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }
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
}

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
                        note.pad = pad
                        if pad.notes == nil { pad.notes = [] }
                        pad.notes?.append(note)
                        modelContext.insert(note)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
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
                        task.pad = pad
                        if pad.tasks == nil { pad.tasks = [] }
                        pad.tasks?.append(task)
                        modelContext.insert(task)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
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
        .frame(minWidth: 350, minHeight: 180)
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
        .frame(minWidth: 350, minHeight: 180)
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
