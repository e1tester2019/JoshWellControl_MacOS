//
//  WellsDashboardView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-09.
//

import SwiftUI
import SwiftData

#if os(iOS)
import UIKit
#endif

// Wrapper for new task/note target to use with sheet(item:)
enum NewItemTarget: Identifiable {
    case well(Well)
    case pad(Pad)

    var id: UUID {
        switch self {
        case .well(let well): return well.id
        case .pad(let pad): return pad.id
        }
    }
}

struct WellsDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Well.name) private var wells: [Well]
    @Query(sort: \Pad.name) private var pads: [Pad]

    // Navigation callback
    var onSelectProject: ((ProjectState) -> Void)?

    // Persisted state
    @AppStorage("wellsDashboard.selectedWellIDs") private var selectedWellIDsData: Data = Data()
    @AppStorage("wellsDashboard.showCompletedTasks") private var showCompletedTasks = true

    @State private var selectedWellIDs: Set<UUID> = []
    @State private var newTaskTarget: NewItemTarget?
    @State private var newNoteTarget: NewItemTarget?
    @State private var editingTask: WellTask?
    @State private var editingNote: HandoverNote?
    @State private var filterPriority: TaskPriority?
    @State private var searchText = ""

    // Export state
    @State private var showingExportSheet = false
    @State private var showingArchiveView = false
    @State private var exportStartDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var exportEndDate = Date()
    @State private var exportIncludeTasks = true
    @State private var exportIncludeNotes = true
    @State private var exportIncludeCompleted = true
    @State private var exportShiftType: ShiftType? = nil

    // Pad management
    @State private var editingPad: Pad?
    @State private var showingNewPadEditor = false
    @State private var showingAssignPad = false
    @State private var wellToAssignPad: Well?

    var body: some View {
        mainContent
        .sheet(item: $newTaskTarget) { target in
            switch target {
            case .well(let well):
                TaskEditorView(well: well, task: nil)
            case .pad(let pad):
                TaskEditorView(pad: pad, task: nil)
            }
        }
        .sheet(item: $editingTask) { task in
            Group {
                if let well = task.well {
                    TaskEditorView(well: well, task: task)
                } else if let pad = task.pad {
                    TaskEditorView(pad: pad, task: task)
                }
            }
            .frame(minWidth: 450, minHeight: 500)
        }
        .sheet(item: $newNoteTarget) { target in
            switch target {
            case .well(let well):
                NoteEditorView(well: well, note: nil)
            case .pad(let pad):
                NoteEditorView(pad: pad, note: nil)
            }
        }
        .sheet(item: $editingNote) { note in
            Group {
                if let well = note.well {
                    NoteEditorView(well: well, note: note)
                } else if let pad = note.pad {
                    NoteEditorView(pad: pad, note: note)
                }
            }
            .frame(minWidth: 500, minHeight: 450)
        }
        .sheet(isPresented: $showingExportSheet) {
            exportSheet
        }
        .sheet(isPresented: $showingArchiveView) {
            HandoverArchiveView()
        }
        .sheet(item: $editingPad) { pad in
            PadEditorView(pad: pad)
        }
        .sheet(isPresented: $showingNewPadEditor) {
            PadEditorView(pad: nil)
        }
        .sheet(isPresented: $showingAssignPad) {
            if let well = wellToAssignPad {
                AssignPadSheet(well: well, pads: pads)
            }
        }
        .onAppear {
            loadSelectedWellIDs()
        }
        .onChange(of: selectedWellIDs) { _, newValue in
            saveSelectedWellIDs(newValue)
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        #if os(macOS)
        HSplitView {
            // Left: Well selection grouped by pad
            wellSelectionList
                .frame(minWidth: 220, idealWidth: 280, maxWidth: 350)

            // Right: Tasks and Notes
            VStack(spacing: 0) {
                filterBar
                Divider()
                HSplitView {
                    tasksSection
                    notesSection
                }
            }
        }
        #else
        // iOS fallback
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    tasksSection
                    notesSection
                }
                .padding()
            }
            .navigationTitle("Handover")
        }
        #endif
    }

    // MARK: - Persistence

    private func loadSelectedWellIDs() {
        if selectedWellIDsData.isEmpty {
            // First time: select all wells
            selectedWellIDs = Set(wells.map { $0.id })
        } else if let uuidStrings = try? JSONDecoder().decode([String].self, from: selectedWellIDsData) {
            let savedIDs = Set(uuidStrings.compactMap { UUID(uuidString: $0) })
            // Only include IDs that still exist
            let validIDs = savedIDs.intersection(Set(wells.map { $0.id }))
            selectedWellIDs = validIDs.isEmpty ? Set(wells.map { $0.id }) : validIDs
        }
    }

    private func saveSelectedWellIDs(_ ids: Set<UUID>) {
        let uuidStrings = ids.map { $0.uuidString }
        if let data = try? JSONEncoder().encode(uuidStrings) {
            selectedWellIDsData = data
        }
    }

    // MARK: - Well Selection (Grouped by Pad)

    private var wellsByPad: [(padName: String, pad: Pad?, wells: [Well])] {
        var groups: [(String, Pad?, [Well])] = []

        // Add pad groups first
        for pad in pads.sorted(by: { $0.name < $1.name }) {
            let padWells = wells.filter { $0.pad?.id == pad.id }
            if !padWells.isEmpty {
                groups.append((pad.name, pad, padWells.sorted { $0.name < $1.name }))
            }
        }

        // Add unassigned wells
        let unassigned = wells.filter { $0.pad == nil }
        if !unassigned.isEmpty {
            groups.append(("Unassigned", nil, unassigned.sorted { $0.name < $1.name }))
        }

        return groups
    }

    private var wellSelectionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Wells by Pad")
                    .font(.headline)
                Spacer()
                Menu {
                    Button("Select All") {
                        selectedWellIDs = Set(wells.map { $0.id })
                    }
                    Button("Select None") {
                        selectedWellIDs = []
                    }
                    Divider()
                    Button("New Pad...") {
                        showingNewPadEditor = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Pad groups
            List {
                ForEach(wellsByPad, id: \.padName) { group in
                    Section {
                        ForEach(group.wells, id: \.id) { well in
                            WellRowView(well: well, isSelected: selectedWellIDs.contains(well.id))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if selectedWellIDs.contains(well.id) {
                                        selectedWellIDs.remove(well.id)
                                    } else {
                                        selectedWellIDs.insert(well.id)
                                    }
                                }
                                .contextMenu {
                                    wellContextMenu(for: well)
                                }
                        }
                    } header: {
                        HStack {
                            Text(group.padName)
                                .font(.subheadline.bold())
                            if let pad = group.pad, !pad.surfaceLocation.isEmpty {
                                Text("(\(pad.surfaceLocation))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            // Show pad-level task/note counts
                            if let pad = group.pad {
                                if !pad.pendingPadTasks.isEmpty {
                                    Label("\(pad.pendingPadTasks.count)", systemImage: "checklist")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                                if !pad.overduePadTasks.isEmpty {
                                    Label("\(pad.overduePadTasks.count)", systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                }
                                if !pad.padNotes.isEmpty {
                                    Label("\(pad.padNotes.count)", systemImage: "note.text")
                                        .font(.caption2)
                                        .foregroundStyle(.blue)
                                }
                            }
                            Spacer()
                            if let pad = group.pad {
                                Button {
                                    editingPad = pad
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            TextField("Search tasks & notes...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)

            Picker("Priority", selection: $filterPriority) {
                Text("All Priorities").tag(nil as TaskPriority?)
                ForEach(TaskPriority.allCases, id: \.self) { p in
                    Text(p.rawValue).tag(p as TaskPriority?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)

            Toggle("Show Completed", isOn: $showCompletedTasks)

            Spacer()

            // Archive button
            Button {
                showingArchiveView = true
            } label: {
                Label("Archives", systemImage: "archivebox")
            }

            // Export button
            Button {
                showingExportSheet = true
            } label: {
                Label("Export Report", systemImage: "square.and.arrow.up")
            }
            .disabled(selectedWells.isEmpty)

            Menu {
                if !selectedPads.isEmpty {
                    Section("Pads") {
                        ForEach(selectedPads, id: \.id) { pad in
                            Button("Add Task to \(pad.name) (Pad)") {
                                newTaskTarget = .pad(pad)
                            }
                        }
                    }
                }
                if !selectedWells.isEmpty {
                    Section("Wells") {
                        ForEach(selectedWells, id: \.id) { well in
                            Button("Add Task to \(well.name)") {
                                newTaskTarget = .well(well)
                            }
                        }
                    }
                }
            } label: {
                Label("New Task", systemImage: "plus.circle")
            }
            .disabled(selectedWells.isEmpty && selectedPads.isEmpty)

            Menu {
                if !selectedPads.isEmpty {
                    Section("Pads") {
                        ForEach(selectedPads, id: \.id) { pad in
                            Button("Add Note to \(pad.name) (Pad)") {
                                newNoteTarget = .pad(pad)
                            }
                        }
                    }
                }
                if !selectedWells.isEmpty {
                    Section("Wells") {
                        ForEach(selectedWells, id: \.id) { well in
                            Button("Add Note to \(well.name)") {
                                newNoteTarget = .well(well)
                            }
                        }
                    }
                }
            } label: {
                Label("New Note", systemImage: "note.text.badge.plus")
            }
            .disabled(selectedWells.isEmpty && selectedPads.isEmpty)
        }
        .padding(12)
    }

    // MARK: - Export Sheet

    private var exportSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Export Handover Report")
                    .font(.headline)
                Spacer()
                Button("Cancel") { showingExportSheet = false }
            }
            .padding()

            Divider()

            Form {
                Section("Date Range") {
                    DatePicker("From", selection: $exportStartDate, displayedComponents: .date)
                    DatePicker("To", selection: $exportEndDate, displayedComponents: .date)
                }

                Section("Include") {
                    Toggle("Tasks", isOn: $exportIncludeTasks)
                    Toggle("Handover Notes", isOn: $exportIncludeNotes)
                    Toggle("Completed/Cancelled Tasks", isOn: $exportIncludeCompleted)
                }

                Section("Shift Filter") {
                    Picker("Shift Type", selection: $exportShiftType) {
                        Text("All Shifts").tag(nil as ShiftType?)
                        Text("Day Shift").tag(ShiftType.day as ShiftType?)
                        Text("Night Shift").tag(ShiftType.night as ShiftType?)
                    }
                    .pickerStyle(.segmented)

                    if let shiftType = exportShiftType {
                        let settings = ShiftRotationSettings.shared
                        Text("Filters to items created during \(shiftType.displayName.lowercased()) shift hours (\(formatShiftHours(settings, shiftType)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Selected Wells (\(selectedWells.count))") {
                    ForEach(wellsByPad, id: \.padName) { group in
                        let groupWells = group.wells.filter { selectedWellIDs.contains($0.id) }
                        if !groupWells.isEmpty {
                            Text("\(group.padName): \(groupWells.map { $0.name }.joined(separator: ", "))")
                                .font(.caption)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Export HTML") {
                    performExport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!exportIncludeTasks && !exportIncludeNotes)
            }
            .padding()
        }
        .frame(width: 500, height: 450)
    }

    private func performExport() {
        let options = HandoverExportService.ExportOptions(
            wells: selectedWells,
            startDate: exportStartDate,
            endDate: exportEndDate,
            includeTasks: exportIncludeTasks,
            includeNotes: exportIncludeNotes,
            includeCompleted: exportIncludeCompleted,
            shiftType: exportShiftType
        )
        HandoverExportService.shared.exportHTML(options: options, modelContext: modelContext)
        showingExportSheet = false
    }

    private func formatShiftHours(_ settings: ShiftRotationSettings, _ type: ShiftType) -> String {
        if type == .day {
            return String(format: "%02d:%02d – %02d:%02d", settings.dayShiftStartHour, settings.dayShiftStartMinute, settings.nightShiftStartHour, settings.nightShiftStartMinute)
        } else {
            return String(format: "%02d:%02d – %02d:%02d", settings.nightShiftStartHour, settings.nightShiftStartMinute, settings.dayShiftStartHour, settings.dayShiftStartMinute)
        }
    }

    // MARK: - Tasks Section

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tasks")
                    .font(.headline)
                Spacer()
                Text("\(filteredTasks.count) items")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if filteredTasks.isEmpty {
                ContentUnavailableView("No Tasks", systemImage: "checkmark.circle", description: Text("Create a new task to get started"))
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredTasks, id: \.id) { task in
                        TaskRowView(task: task) {
                            editingTask = task
                        }
                        .contextMenu {
                            Button("Edit") { editingTask = task }
                            Button(task.status == .completed ? "Mark Pending" : "Mark Complete") {
                                task.status = task.status == .completed ? .pending : .completed
                                try? modelContext.save()
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                deleteTask(task)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 300)
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Handover Notes")
                    .font(.headline)
                Spacer()
                Text("\(filteredNotes.count) items")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if filteredNotes.isEmpty {
                ContentUnavailableView("No Notes", systemImage: "note.text", description: Text("Create a handover note to get started"))
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredNotes, id: \.id) { note in
                        NoteRowView(note: note) {
                            editingNote = note
                        }
                        .contextMenu {
                            Button("Edit") { editingNote = note }
                            Button(note.isPinned ? "Unpin" : "Pin") {
                                note.isPinned.toggle()
                                try? modelContext.save()
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                deleteNote(note)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 300)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func wellContextMenu(for well: Well) -> some View {
        // Project links
        if let projects = well.projects, !projects.isEmpty {
            let sortedProjects = projects.sorted(by: { $0.name < $1.name })
            Section("Projects") {
                ForEach(sortedProjects) { project in
                    Button {
                        onSelectProject?(project)
                    } label: {
                        Label(project.name, systemImage: "gauge.with.dots.needle.67percent")
                    }
                }
            }
        }

        Section {
            Button("Assign to Pad...") {
                wellToAssignPad = well
                showingAssignPad = true
            }
            if well.pad != nil {
                Button("Remove from Pad") {
                    well.pad = nil
                    try? modelContext.save()
                }
            }
        }
    }

    private var selectedWells: [Well] {
        wells.filter { selectedWellIDs.contains($0.id) }
    }

    private var selectedPads: [Pad] {
        // A pad is "selected" if any of its wells are selected
        let selectedWellPadIDs = Set(selectedWells.compactMap { $0.pad?.id })
        return pads.filter { selectedWellPadIDs.contains($0.id) }
    }

    private var allTasks: [WellTask] {
        // Include tasks from selected wells and their pads, deduplicated
        let wellTasks = selectedWells.flatMap { $0.tasks ?? [] }
        let padTasks = selectedPads.flatMap { $0.padTasks }

        // Deduplicate by ID (a task assigned to both a well and pad would appear twice otherwise)
        var seenIDs = Set<UUID>()
        var uniqueTasks: [WellTask] = []
        for task in wellTasks + padTasks {
            if seenIDs.insert(task.id).inserted {
                uniqueTasks.append(task)
            }
        }
        return uniqueTasks
    }

    private var filteredTasks: [WellTask] {
        var tasks = allTasks

        if !showCompletedTasks {
            tasks = tasks.filter { $0.status != .completed && $0.status != .cancelled }
        }

        if let priority = filterPriority {
            tasks = tasks.filter { $0.priority == priority }
        }

        if !searchText.isEmpty {
            tasks = tasks.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.taskDescription.localizedCaseInsensitiveContains(searchText)
            }
        }

        return tasks.sorted { a, b in
            if a.isOverdue != b.isOverdue { return a.isOverdue }
            if a.priority.sortOrder != b.priority.sortOrder { return a.priority.sortOrder < b.priority.sortOrder }
            let dateA = a.dueDate ?? .distantFuture
            let dateB = b.dueDate ?? .distantFuture
            return dateA < dateB
        }
    }

    private var allNotes: [HandoverNote] {
        // Include notes from selected wells and their pads, deduplicated
        let wellNotes = selectedWells.flatMap { $0.notes ?? [] }
        let padNotes = selectedPads.flatMap { $0.padNotes }

        // Deduplicate by ID (a note assigned to both a well and pad would appear twice otherwise)
        var seenIDs = Set<UUID>()
        var uniqueNotes: [HandoverNote] = []
        for note in wellNotes + padNotes {
            if seenIDs.insert(note.id).inserted {
                uniqueNotes.append(note)
            }
        }
        return uniqueNotes
    }

    private var filteredNotes: [HandoverNote] {
        var notes = allNotes

        if !searchText.isEmpty {
            notes = notes.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.content.localizedCaseInsensitiveContains(searchText)
            }
        }

        return notes.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.updatedAt > b.updatedAt
        }
    }

    private func deleteTask(_ task: WellTask) {
        if let well = task.well {
            well.tasks?.removeAll { $0.id == task.id }
        }
        if let pad = task.pad {
            pad.tasks?.removeAll { $0.id == task.id }
        }
        modelContext.delete(task)
        try? modelContext.save()
    }

    private func deleteNote(_ note: HandoverNote) {
        if let well = note.well {
            well.notes?.removeAll { $0.id == note.id }
        }
        if let pad = note.pad {
            pad.notes?.removeAll { $0.id == note.id }
        }
        modelContext.delete(note)
        try? modelContext.save()
    }
}

// MARK: - Supporting Views

struct WellRowView: View {
    let well: Well
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(well.name)
                    .font(.body)
                HStack(spacing: 8) {
                    if let projects = well.projects, !projects.isEmpty {
                        Label("\(projects.count)", systemImage: "gauge.with.dots.needle.67percent")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    if !well.pendingTasks.isEmpty {
                        Label("\(well.pendingTasks.count)", systemImage: "checklist")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if !well.overdueTasks.isEmpty {
                        Label("\(well.overdueTasks.count)", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                    if !(well.notes ?? []).isEmpty {
                        Label("\((well.notes ?? []).count)", systemImage: "note.text")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct TaskRowView: View {
    let task: WellTask
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(priorityColor)
                    .frame(width: 10, height: 10)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(task.title)
                            .font(.headline)
                            .strikethrough(task.status == .completed)
                            .foregroundStyle(task.status == .completed ? .secondary : .primary)

                        if task.isOverdue {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }

                        Spacer()

                        Text(task.status.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(statusColor.opacity(0.2))
                            .foregroundStyle(statusColor)
                            .clipShape(Capsule())
                    }

                    if !task.taskDescription.isEmpty {
                        Text(task.taskDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 12) {
                        if let well = task.well {
                            Label(well.name, systemImage: "drop.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else if let pad = task.pad {
                            Label("\(pad.name) (Pad)", systemImage: "square.grid.2x2")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }

                        if let due = task.dueDate {
                            Label(due.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                                .font(.caption2)
                                .foregroundStyle(task.isOverdue ? .red : .secondary)
                        }

                        Text(task.priority.rawValue)
                            .font(.caption2)
                            .foregroundStyle(priorityColor)
                    }
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var priorityColor: Color {
        switch task.priority {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .green
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .pending: return .secondary
        case .inProgress: return .blue
        case .completed: return .green
        case .cancelled: return .gray
        }
    }
}

struct NoteRowView: View {
    let note: HandoverNote
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Circle()
                        .fill(notePriorityColor)
                        .frame(width: 8, height: 8)

                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Text(note.title)
                        .font(.headline)

                    Spacer()

                    Text(note.category.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(categoryColor.opacity(0.2))
                        .foregroundStyle(categoryColor)
                        .clipShape(Capsule())
                }

                if !note.content.isEmpty {
                    MarkdownListView(content: note.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                HStack(spacing: 12) {
                    if let well = note.well {
                        Label(well.name, systemImage: "drop.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if let pad = note.pad {
                        Label("\(pad.name) (Pad)", systemImage: "square.grid.2x2")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }

                    if !note.author.isEmpty {
                        Label(note.author, systemImage: "person")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var categoryColor: Color {
        switch note.category {
        case .safety: return .red
        case .operations: return .blue
        case .equipment: return .orange
        case .personnel: return .purple
        case .handover: return .green
        case .general: return .secondary
        }
    }

    private var notePriorityColor: Color {
        switch note.priority {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .green
        }
    }
}

// MARK: - Pad Editor

struct PadEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let pad: Pad?

    @State private var name: String = ""
    @State private var surfaceLocation: String = ""
    @State private var latitude: String = ""
    @State private var longitude: String = ""

    private var isEditing: Bool { pad != nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isEditing ? "Edit Pad" : "New Pad")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()

            Divider()

            Form {
                Section("Pad Details") {
                    TextField("Name", text: $name)
                    TextField("Surface Location (LSD)", text: $surfaceLocation)
                }

                Section("Coordinates (Optional)") {
                    TextField("Latitude", text: $latitude)
                    TextField("Longitude", text: $longitude)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                if isEditing {
                    Button("Delete", role: .destructive) {
                        deletePad()
                    }
                }
                Spacer()
                Button("Save") {
                    savePad()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 350)
        .onAppear {
            if let pad = pad {
                name = pad.name
                surfaceLocation = pad.surfaceLocation
                if let lat = pad.latitude { latitude = String(lat) }
                if let lon = pad.longitude { longitude = String(lon) }
            }
        }
    }

    private func savePad() {
        let lat = Double(latitude)
        let lon = Double(longitude)

        if let pad = pad {
            pad.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            pad.surfaceLocation = surfaceLocation
            pad.latitude = lat
            pad.longitude = lon
            pad.updatedAt = Date()
        } else {
            let newPad = Pad(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                surfaceLocation: surfaceLocation,
                latitude: lat,
                longitude: lon
            )
            modelContext.insert(newPad)
        }

        try? modelContext.save()
        dismiss()
    }

    private func deletePad() {
        if let pad = pad {
            // Unassign wells from this pad
            for well in (pad.wells ?? []) {
                well.pad = nil
            }
            modelContext.delete(pad)
            try? modelContext.save()
        }
        dismiss()
    }
}

// MARK: - Assign Pad Sheet

struct AssignPadSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let well: Well
    let pads: [Pad]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Assign \(well.name) to Pad")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()

            Divider()

            List {
                Button("No Pad (Unassigned)") {
                    well.pad = nil
                    try? modelContext.save()
                    dismiss()
                }
                .foregroundStyle(well.pad == nil ? Color.accentColor : .primary)

                ForEach(pads) { pad in
                    Button {
                        well.pad = pad
                        try? modelContext.save()
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(pad.name)
                                if !pad.surfaceLocation.isEmpty {
                                    Text(pad.surfaceLocation)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if well.pad?.id == pad.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .foregroundStyle(well.pad?.id == pad.id ? Color.accentColor : .primary)
                }
            }
        }
        .frame(width: 350, height: 300)
    }
}
