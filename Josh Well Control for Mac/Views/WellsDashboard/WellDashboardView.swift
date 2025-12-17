//
//  WellDashboardView.swift
//  Josh Well Control for Mac
//
//  Dashboard view for a single well showing identity, projects, rentals, transfers, and notes/tasks
//

import SwiftUI
import SwiftData

struct WellDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Pad.name) private var allPads: [Pad]
    @Bindable var well: Well

    // Optional navigation callback for projects (to navigate in main view, not sheet)
    // If not provided, projects will open in a sheet instead
    var onSelectProject: ((ProjectState) -> Void)?

    @State private var showingAddNote = false
    @State private var showingAddTask = false
    @State private var showingAddProject = false
    @State private var showingAddRental = false
    @State private var showingAddTransfer = false
    @State private var showingDeleteConfirmation = false

    // Navigation states for items that open in sheets
    @State private var selectedProjectForSheet: ProjectState?  // Fallback when onSelectProject is nil
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                header

                // Identity section - full width
                identitySection

                #if os(macOS)
                // Two-column layout for macOS
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        projectsSection
                        rentalsSection
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 16) {
                        transfersSection
                        notesSection
                        tasksSection
                    }
                    .frame(maxWidth: .infinity)
                }
                #else
                // Stacked layout for iOS
                projectsSection
                rentalsSection
                transfersSection
                notesSection
                tasksSection
                #endif
            }
            .padding(24)
        }
        .background(pageBackgroundColor)
        .navigationTitle("Well Dashboard")
        .sheet(isPresented: $showingAddNote) {
            AddNoteSheet(well: well, project: nil, pad: well.pad)
        }
        .sheet(isPresented: $showingAddTask) {
            AddTaskSheet(well: well, project: nil, pad: well.pad)
        }
        .sheet(isPresented: $showingAddProject) {
            AddProjectSheet(well: well)
        }
        .sheet(isPresented: $showingAddRental) {
            AddRentalSheet(well: well)
        }
        .sheet(isPresented: $showingAddTransfer) {
            AddTransferSheet(well: well)
        }
        .alert("Delete Well?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                modelContext.delete(well)
                try? modelContext.save()
            }
        } message: {
            Text("Are you sure you want to delete \"\(well.name)\"? This will also delete all projects, rentals, transfers, notes, and tasks associated with this well.")
        }
        // Navigation sheets for clickable list items
        .sheet(item: $selectedRental) { rental in
            RentalDetailEditor(rental: rental)
                .environment(\.locale, Locale(identifier: "en_GB"))
                #if os(macOS)
                .frame(minWidth: 720, minHeight: 520)
                #endif
        }
        .sheet(item: $selectedTransfer) { transfer in
            MaterialTransferEditorView(well: well, transfer: transfer)
        }
        .sheet(item: $selectedNote) { note in
            NoteEditorView(well: well, note: note)
        }
        .sheet(item: $selectedTask) { task in
            TaskEditorView(well: well, task: task)
        }
        .sheet(item: $selectedProjectForSheet) { project in
            ProjectDashboardView(project: project)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(well.name)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    if well.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                }
                Text("Overview including projects, equipment, and handover items.")
                    .foregroundStyle(.secondary)
            }
            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                Button(action: { well.isFavorite.toggle(); try? modelContext.save() }) {
                    Label("Favorite", systemImage: well.isFavorite ? "star.fill" : "star")
                }
                .buttonStyle(.borderless)

                Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.borderless)

                // Lock toggle button
                Button {
                    well.isLocked.toggle()
                    try? modelContext.save()
                } label: {
                    Label(
                        well.isLocked ? "Unlock" : "Lock",
                        systemImage: well.isLocked ? "lock.fill" : "lock.open"
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(well.isLocked ? Color.orange.opacity(0.2) : Color.green.opacity(0.2))
                    .foregroundStyle(well.isLocked ? .orange : .green)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help(well.isLocked ? "Unlock well for editing" : "Lock well to prevent accidental edits")
            }
        }
    }

    // MARK: - Identity Section

    private var identitySection: some View {
        WellSection(title: "Well", icon: "building.2", subtitle: "Identity and accounting") {
            HStack(alignment: .top) {
                #if os(macOS)
                HStack(alignment: .top, spacing: 32) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Well Name").foregroundStyle(.secondary)
                            TextField("Well name", text: $well.name)
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("UWI").foregroundStyle(.secondary)
                            TextField("UWI", text: Binding(
                                get: { well.uwi ?? "" },
                                set: { well.uwi = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("AFE #").foregroundStyle(.secondary)
                            TextField("AFE number", text: Binding(
                                get: { well.afeNumber ?? "" },
                                set: { well.afeNumber = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Requisitioner").foregroundStyle(.secondary)
                            TextField("Requisitioner", text: Binding(
                                get: { well.requisitioner ?? "" },
                                set: { well.requisitioner = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Rig").foregroundStyle(.secondary)
                            TextField("Rig name", text: Binding(
                                get: { well.rigName ?? "" },
                                set: { well.rigName = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Pad").foregroundStyle(.secondary)
                            Picker("Pad", selection: Binding(
                                get: { well.pad },
                                set: { newPad in
                                    if let oldPad = well.pad {
                                        oldPad.wells?.removeAll { $0.id == well.id }
                                    }
                                    well.pad = newPad
                                    if let newPad = newPad {
                                        if newPad.wells == nil { newPad.wells = [] }
                                        if !newPad.wells!.contains(where: { $0.id == well.id }) {
                                            newPad.wells?.append(well)
                                        }
                                    }
                                    try? modelContext.save()
                                }
                            )) {
                                Text("No Pad").tag(nil as Pad?)
                                ForEach(allPads) { pad in
                                    Text(pad.name).tag(pad as Pad?)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                }
                .allowsHitTesting(!well.isLocked)
                #else
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Well Name").foregroundStyle(.secondary)
                        TextField("Well name", text: $well.name)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("UWI").foregroundStyle(.secondary)
                        TextField("UWI", text: Binding(
                            get: { well.uwi ?? "" },
                            set: { well.uwi = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("AFE #").foregroundStyle(.secondary)
                        TextField("AFE number", text: Binding(
                            get: { well.afeNumber ?? "" },
                            set: { well.afeNumber = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Requisitioner").foregroundStyle(.secondary)
                        TextField("Requisitioner", text: Binding(
                            get: { well.requisitioner ?? "" },
                            set: { well.requisitioner = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Rig").foregroundStyle(.secondary)
                        TextField("Rig name", text: Binding(
                            get: { well.rigName ?? "" },
                            set: { well.rigName = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Pad").foregroundStyle(.secondary)
                        Picker("Pad", selection: Binding(
                            get: { well.pad },
                            set: { newPad in
                                if let oldPad = well.pad {
                                    oldPad.wells?.removeAll { $0.id == well.id }
                                }
                                well.pad = newPad
                                if let newPad = newPad {
                                    if newPad.wells == nil { newPad.wells = [] }
                                    if !newPad.wells!.contains(where: { $0.id == well.id }) {
                                        newPad.wells?.append(well)
                                    }
                                }
                                try? modelContext.save()
                            }
                        )) {
                            Text("No Pad").tag(nil as Pad?)
                            ForEach(allPads) { pad in
                                Text(pad.name).tag(pad as Pad?)
                            }
                        }
                        .labelsHidden()
                    }
                }
                .allowsHitTesting(!well.isLocked)
                #endif

                Spacer()

                // Copy Info button - always accessible regardless of lock
                Button {
                    copyWellInfoToClipboard()
                } label: {
                    Label("Copy Info", systemImage: "doc.on.doc")
                }
            }
        }
    }

    // MARK: - Copy Info

    private func makeWellInfoString() -> String {
        """
        Well Name: \(well.name)
        UWI: \(well.uwi ?? "-")
        AFE: \(well.afeNumber ?? "-")
        Requisitioner: \(well.requisitioner ?? "-")
        """
    }

    private func copyWellInfoToClipboard() {
        ClipboardService.shared.copyToClipboard(makeWellInfoString())
    }

    // MARK: - Projects Section

    private var projectsSection: some View {
        WellSection(title: "Projects", icon: "folder", subtitle: "\(well.projects?.count ?? 0) project(s)") {
            VStack(alignment: .leading, spacing: 8) {
                if let projects = well.projects, !projects.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(projects.sorted(by: { $0.updatedAt > $1.updatedAt })) { project in
                            Button {
                                if let callback = onSelectProject {
                                    callback(project)
                                } else {
                                    selectedProjectForSheet = project
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(project.name)
                                            .fontWeight(.medium)
                                        Text("Updated \(project.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    HStack(spacing: 12) {
                                        Label("\(project.drillString?.count ?? 0)", systemImage: "cylinder.split.1x2")
                                        Label("\(project.annulus?.count ?? 0)", systemImage: "circle.hexagonpath")
                                        Label("\(project.surveys?.count ?? 0)", systemImage: "location.north.circle")
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

                            if project.id != projects.last?.id {
                                Divider()
                            }
                        }
                    }
                } else {
                    Text("No projects")
                        .foregroundStyle(.secondary)
                        .italic()
                }

                Button(action: { showingAddProject = true }) {
                    Label("Add Project", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Rentals Section

    private var rentalsSection: some View {
        WellSection(title: "Rentals", icon: "bag", subtitle: "\(well.rentals?.count ?? 0) item(s)") {
            VStack(alignment: .leading, spacing: 8) {
                if let rentals = well.rentals, !rentals.isEmpty {
                    VStack(spacing: 0) {
                        // Header row
                        HStack {
                            Text("Item").fontWeight(.medium).frame(maxWidth: .infinity, alignment: .leading)
                            Text("Serial").fontWeight(.medium).frame(width: 80, alignment: .leading)
                            Text("Days").fontWeight(.medium).frame(width: 50, alignment: .trailing)
                            Text("Status").fontWeight(.medium).frame(width: 70, alignment: .center)
                            Spacer().frame(width: 20)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)

                        Divider()

                        ForEach(rentals.sorted(by: { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) })) { rental in
                            Button {
                                selectedRental = rental
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(rental.name)
                                        if let detail = rental.detail, !detail.isEmpty {
                                            Text(detail)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    Text(rental.serialNumber ?? "—")
                                        .font(.caption)
                                        .frame(width: 80, alignment: .leading)

                                    Text("\(rental.totalDays)")
                                        .monospacedDigit()
                                        .frame(width: 50, alignment: .trailing)

                                    HStack(spacing: 4) {
                                        if rental.onLocation {
                                            Image(systemName: "mappin.circle.fill")
                                                .foregroundStyle(.green)
                                        }
                                        if rental.invoiced {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                    .frame(width: 70, alignment: .center)

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .font(.callout)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if rental.id != rentals.last?.id {
                                Divider()
                            }
                        }
                    }
                } else {
                    Text("No rental items")
                        .foregroundStyle(.secondary)
                        .italic()
                }

                Button(action: { showingAddRental = true }) {
                    Label("Add Rental", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Transfers Section

    private var transfersSection: some View {
        WellSection(title: "Material Transfers", icon: "arrow.left.arrow.right.circle", subtitle: "\(well.transfers?.count ?? 0) transfer(s)") {
            VStack(alignment: .leading, spacing: 8) {
                if let transfers = well.transfers, !transfers.isEmpty {
                    VStack(spacing: 0) {
                        // Header row
                        HStack {
                            Text("M.T.#").fontWeight(.medium).frame(width: 50, alignment: .leading)
                            Text("Date").fontWeight(.medium).frame(width: 80, alignment: .leading)
                            Text("Destination").fontWeight(.medium).frame(maxWidth: .infinity, alignment: .leading)
                            Text("Items").fontWeight(.medium).frame(width: 50, alignment: .trailing)
                            Spacer().frame(width: 20)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)

                        Divider()

                        ForEach(transfers.sorted(by: { $0.date > $1.date })) { transfer in
                            Button {
                                selectedTransfer = transfer
                            } label: {
                                HStack {
                                    Text("\(transfer.number)")
                                        .fontWeight(.medium)
                                        .frame(width: 50, alignment: .leading)

                                    Text(transfer.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .frame(width: 80, alignment: .leading)

                                    Text(transfer.destinationName ?? "—")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .lineLimit(1)

                                    Text("\(transfer.items?.count ?? 0)")
                                        .monospacedDigit()
                                        .frame(width: 50, alignment: .trailing)

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .font(.callout)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if transfer.id != transfers.last?.id {
                                Divider()
                            }
                        }
                    }
                } else {
                    Text("No material transfers")
                        .foregroundStyle(.secondary)
                        .italic()
                }

                Button(action: { showingAddTransfer = true }) {
                    Label("Add Transfer", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        WellSection(title: "Notes", icon: "note.text", subtitle: "\(well.notes?.count ?? 0) note(s)") {
            VStack(alignment: .leading, spacing: 8) {
                if let notes = well.notes, !notes.isEmpty {
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

                    if (well.notes?.count ?? 0) > 5 {
                        Text("+ \((well.notes?.count ?? 0) - 5) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No notes")
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

    private var tasksSection: some View {
        WellSection(title: "Tasks", icon: "checkmark.circle", subtitle: "\(well.pendingTasks.count) pending") {
            VStack(alignment: .leading, spacing: 8) {
                if !well.pendingTasks.isEmpty {
                    ForEach(well.pendingTasks.prefix(5)) { task in
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

                    if well.pendingTasks.count > 5 {
                        Text("+ \(well.pendingTasks.count - 5) more")
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

// MARK: - Add Note Sheet

private struct AddNoteSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let well: Well
    let project: ProjectState?
    let pad: Pad?

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
            .navigationTitle("Add Note")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let note = well.createNote(
                            title: title,
                            content: content,
                            category: category,
                            isPinned: isPinned,
                            context: modelContext
                        )
                        note.project = project
                        note.pad = pad
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

// MARK: - Add Task Sheet

private struct AddTaskSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let well: Well
    let project: ProjectState?
    let pad: Pad?

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
            .navigationTitle("Add Task")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let task = well.createTask(
                            title: title,
                            description: description,
                            priority: priority,
                            dueDate: hasDueDate ? dueDate : nil,
                            context: modelContext
                        )
                        task.project = project
                        task.pad = pad
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

// MARK: - Add Project Sheet

private struct AddProjectSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let well: Well

    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Project Name", text: $name)
            }
            .navigationTitle("Add Project")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let project = ProjectState()
                        project.name = name.isEmpty ? "New Project" : name
                        project.well = well
                        if well.projects == nil { well.projects = [] }
                        well.projects?.append(project)
                        modelContext.insert(project)
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 350, minHeight: 150)
        #endif
    }
}

// MARK: - Add Rental Sheet

private struct AddRentalSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let well: Well

    @State private var name = ""
    @State private var detail = ""
    @State private var serialNumber = ""
    @State private var costPerDay: Double = 0
    @State private var startDate = Date()
    @State private var onLocation = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Name", text: $name)
                    TextField("Detail", text: $detail)
                    TextField("Serial Number", text: $serialNumber)
                }

                Section("Rental Info") {
                    HStack {
                        Text("Cost per Day")
                        Spacer()
                        TextField("0.00", value: $costPerDay, format: .currency(code: "CAD"))
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .frame(width: 120)
                    }
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    Toggle("On Location", isOn: $onLocation)
                }
            }
            .navigationTitle("Add Rental")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let rental = RentalItem(
                            name: name.isEmpty ? "Rental Item" : name,
                            detail: detail.isEmpty ? nil : detail,
                            serialNumber: serialNumber.isEmpty ? nil : serialNumber,
                            startDate: startDate,
                            onLocation: onLocation,
                            costPerDay: costPerDay,
                            well: well
                        )
                        if well.rentals == nil { well.rentals = [] }
                        well.rentals?.append(rental)
                        modelContext.insert(rental)
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 350)
        #endif
    }
}

// MARK: - Add Transfer Sheet

private struct AddTransferSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let well: Well

    @State private var destinationName = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Destination", text: $destinationName)
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }
            .navigationTitle("Add Transfer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let transfer = well.createTransfer(context: modelContext)
                        transfer.destinationName = destinationName.isEmpty ? nil : destinationName
                        transfer.date = date
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

