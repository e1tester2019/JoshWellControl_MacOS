//
//  ProjectDashboardView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//

// ProjectDashboardView.swift
import SwiftUI
import SwiftData
#if DEBUG
import CoreData
#endif
#if os(macOS)
import AppKit
#endif

struct ProjectDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Well.name) private var allWells: [Well]
    @Bindable var project: ProjectState
    @State private var viewmodel: ViewModel
    @State private var newTransferToEdit: MaterialTransfer?
    @State private var showingAddNote = false
    @State private var showingAddTask = false
    @State private var showingRenameProject = false
    @State private var showingDeleteConfirmation = false
    @State private var renameText = ""


    // Optional navigation controls for iOS
    var wells: [Well]?
    @Binding var selectedWell: Well?
    @Binding var selectedProject: ProjectState?
    var onNewWell: (() -> Void)?
    var onNewProject: (() -> Void)?
    var onRenameWell: ((Well) -> Void)?
    var onRenameProject: ((ProjectState) -> Void)?
    var onDuplicateWell: ((Well) -> Void)?
    var onDuplicateProject: ((ProjectState) -> Void)?
    var onDeleteWell: (() -> Void)?
    var onDeleteProject: (() -> Void)?

    init(
        project: ProjectState,
        wells: [Well]? = nil,
        selectedWell: Binding<Well?>? = nil,
        selectedProject: Binding<ProjectState?>? = nil,
        onNewWell: (() -> Void)? = nil,
        onNewProject: (() -> Void)? = nil,
        onRenameWell: ((Well) -> Void)? = nil,
        onRenameProject: ((ProjectState) -> Void)? = nil,
        onDuplicateWell: ((Well) -> Void)? = nil,
        onDuplicateProject: ((ProjectState) -> Void)? = nil,
        onDeleteWell: (() -> Void)? = nil,
        onDeleteProject: (() -> Void)? = nil
    ) {
        self._project = Bindable(wrappedValue: project)
        _viewmodel = State(initialValue: ViewModel(project: project))
        self.wells = wells
        self._selectedWell = selectedWell ?? .constant(nil)
        self._selectedProject = selectedProject ?? .constant(nil)
        self.onNewWell = onNewWell
        self.onNewProject = onNewProject
        self.onRenameWell = onRenameWell
        self.onRenameProject = onRenameProject
        self.onDuplicateWell = onDuplicateWell
        self.onDuplicateProject = onDuplicateProject
        self.onDeleteWell = onDeleteWell
        self.onDeleteProject = onDeleteProject
    }

    private var pageBackgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .underPageBackgroundColor)
        #else
        Color(.systemGroupedBackground)
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Navigation controls (iOS only) - Fixed at top
            #if os(iOS)
            if let wells = wells {
                VStack(spacing: 12) {
                    // Well and Project pickers
                    HStack(spacing: 12) {
                        Menu {
                            ForEach(wells, id: \.id) { w in
                                Button {
                                    selectedWell = w
                                    selectedProject = (w.projects ?? []).first
                                } label: {
                                    if selectedWell?.id == w.id {
                                        Label(w.name, systemImage: "checkmark")
                                    } else {
                                        Text(w.name)
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "square.grid.2x2")
                                Text(selectedWell?.name ?? "Select Well")
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.accentColor, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)

                        if let well = selectedWell {
                            let projects = well.projects ?? []
                            Menu {
                                ForEach(projects.sorted(by: { $0.createdAt < $1.createdAt }), id: \.id) { p in
                                    Button {
                                        selectedProject = p
                                    } label: {
                                        if selectedProject?.id == p.id {
                                            Label(p.name, systemImage: "checkmark")
                                        } else {
                                            Text(p.name)
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "folder")
                                    Text(selectedProject?.name ?? "Select Project")
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .font(.caption)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.accentColor.opacity(0.15))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.accentColor, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Action buttons
                    HStack(spacing: 12) {
                        Menu {
                            Button("New Well", systemImage: "plus") {
                                onNewWell?()
                            }
                            Button("New Project State", systemImage: "doc.badge.plus") {
                                onNewProject?()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.green, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)

                        Menu {
                            if let well = selectedWell {
                                Section("Well") {
                                    Button("Rename Well", systemImage: "pencil") {
                                        onRenameWell?(well)
                                    }
                                    Button("Duplicate Well", systemImage: "doc.on.doc") {
                                        onDuplicateWell?(well)
                                    }
                                    Button("Delete Well", systemImage: "trash", role: .destructive) {
                                        onDeleteWell?()
                                    }
                                }
                            }
                            if let project = selectedProject {
                                Section("Project State") {
                                    Button("Rename Project", systemImage: "pencil") {
                                        onRenameProject?(project)
                                    }
                                    Button("Duplicate Project", systemImage: "doc.on.doc") {
                                        onDuplicateProject?(project)
                                    }
                                    Button("Delete Project", systemImage: "trash", role: .destructive) {
                                        onDeleteProject?()
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "ellipsis.circle.fill")
                                Text("Actions")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.blue, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .background(Color(uiColor: .secondarySystemBackground))
            }
            #endif

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.name)
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            Text("Curate project inputs, system defaults, and a snapshot of the work already captured.")
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        #if os(macOS)
                        // Action buttons
                        HStack(spacing: 8) {
                            Button(action: { renameText = project.name; showingRenameProject = true }) {
                                Label("Rename", systemImage: "pencil")
                            }
                            .buttonStyle(.borderless)

                            Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                                Label("Delete", systemImage: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        #endif

                        // Lock toggle button
                        Button {
                            project.isDashboardLocked.toggle()
                            try? modelContext.save()
                        } label: {
                            Label(
                                project.isDashboardLocked ? "Unlock" : "Lock",
                                systemImage: project.isDashboardLocked ? "lock.fill" : "lock.open"
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(project.isDashboardLocked ? Color.orange.opacity(0.2) : Color.green.opacity(0.2))
                            .foregroundStyle(project.isDashboardLocked ? .orange : .green)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .help(project.isDashboardLocked ? "Unlock dashboard for editing" : "Lock dashboard to prevent accidental edits")
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)], spacing: 16) {
                    WellSection(title: "Project", icon: "target", subtitle: "Name, well assignment, and pressure window safety margins.") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                            GridRow {
                                Text("Name")
                                    .gridColumnAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                                TextField("Project name", text: $project.name)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                            }
                            GridRow {
                                Text("Well")
                                    .gridColumnAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                                Picker("Well", selection: Binding(
                                    get: { project.well },
                                    set: { newWell in
                                        // Remove from old well
                                        if let oldWell = project.well {
                                            oldWell.projects?.removeAll { $0.id == project.id }
                                        }
                                        // Assign to new well
                                        project.well = newWell
                                        if let newWell = newWell {
                                            if newWell.projects == nil { newWell.projects = [] }
                                            if !newWell.projects!.contains(where: { $0.id == project.id }) {
                                                newWell.projects?.append(project)
                                            }
                                        }
                                        try? modelContext.save()
                                    }
                                )) {
                                    Text("No Well").tag(nil as Well?)
                                    ForEach(allWells) { well in
                                        Text(well.name).tag(well as Well?)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            GridRow {
                                Text("Pore safety (kPa)")
                                    .gridColumnAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $project.window.poreSafety_kPa, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                                    .monospacedDigit()
                            }
                            GridRow {
                                Text("Frac safety (kPa)")
                                    .gridColumnAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $project.window.fracSafety_kPa, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                                    .monospacedDigit()
                            }
                        }
                    }

                    WellSection(title: "Active System", icon: "drop.fill", subtitle: "Current active pit & surface volumes.") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                            GridRow {
                                Text("Active mud weight (kg/m³)")
                                    .gridColumnAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $project.activeMudDensity_kgm3, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                                    .monospacedDigit()
                            }
                            GridRow {
                                Text("Active mud volume (m³)")
                                    .gridColumnAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $project.activeMudVolume_m3, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                                    .monospacedDigit()
                            }
                            GridRow {
                                Text("Surface line volume (m³)")
                                    .gridColumnAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $project.surfaceLineVolume_m3, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                                    .monospacedDigit()
                            }
                        }
                    }

                    WellSection(title: "Defaults", icon: "slider.horizontal.3", subtitle: "Column densities and control depth seeds.") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                            GridRow {
                                Text("Base annulus density (kg/m³)")
                                    .gridColumnAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $project.baseAnnulusDensity_kgm3, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                                    .monospacedDigit()
                            }
                            GridRow {
                                Text("Base string density (kg/m³)")
                                    .gridColumnAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $project.baseStringDensity_kgm3, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                                    .monospacedDigit()
                            }
                            GridRow {
                                Text("Control measured depth (m)")
                                    .gridColumnAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $project.pressureDepth_m, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                .allowsHitTesting(!project.isDashboardLocked)

                // Well section - full width
                WellSection(title: "Well", icon: "oilcan", subtitle: "Identity and accounting") {
                    #if os(macOS)
                    HStack(alignment: .top, spacing: 24) {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                            GridRow {
                                Text("Well Name")
                                    .gridColumnAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                                TextField(
                                    "Well Name",
                                    text: Binding(
                                        get: { project.well?.name ?? "" },
                                        set: { newValue in
                                            if let well = project.well {
                                                well.name = newValue
                                            }
                                        }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: .infinity)
                            }
                            GridRow {
                                Text("UWI")
                                    .gridColumnAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                                TextField(
                                    "UWI",
                                    text: Binding(
                                        get: { project.well?.uwi ?? "" },
                                        set: { newValue in
                                            if let well = project.well {
                                                well.uwi = newValue
                                            }
                                        }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: .infinity)
                            }
                        }

                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                            GridRow {
                                Text("AFE #")
                                    .gridColumnAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                                TextField(
                                    "AFE #",
                                    text: Binding(
                                        get: { project.well?.afeNumber ?? "" },
                                        set: { newValue in
                                            if let well = project.well {
                                                well.afeNumber = newValue
                                            }
                                        }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: .infinity)
                            }
                            GridRow {
                                Text("Requisitioner")
                                    .gridColumnAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                                TextField(
                                    "Requisitioner",
                                    text: Binding(
                                        get: { project.well?.requisitioner ?? "" },
                                        set: { newValue in
                                            if let well = project.well {
                                                well.requisitioner = newValue
                                            }
                                        }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: .infinity)
                            }
                        }

                        Button {
                            copyProjectInfoToClipboard()
                        } label: {
                            Label("Copy Info", systemImage: "doc.on.doc")
                        }
                    }
                    #else
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow {
                            Text("Well Name")
                                .gridColumnAlignment(.trailing)
                                .foregroundStyle(.secondary)
                            TextField(
                                "Well Name",
                                text: Binding(
                                    get: { project.well?.name ?? "" },
                                    set: { newValue in
                                        if let well = project.well {
                                            well.name = newValue
                                        }
                                    }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                        }
                        GridRow {
                            Text("UWI")
                                .gridColumnAlignment(.trailing)
                                .foregroundStyle(.secondary)
                            TextField(
                                "UWI",
                                text: Binding(
                                    get: { project.well?.uwi ?? "" },
                                    set: { newValue in
                                        if let well = project.well {
                                            well.uwi = newValue
                                        }
                                    }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                        }
                        GridRow {
                            Text("AFE #")
                                .gridColumnAlignment(.trailing)
                                .foregroundStyle(.secondary)
                            TextField(
                                "AFE #",
                                text: Binding(
                                    get: { project.well?.afeNumber ?? "" },
                                    set: { newValue in
                                        if let well = project.well {
                                            well.afeNumber = newValue
                                        }
                                    }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                        }
                        GridRow {
                            Text("Requisitioner")
                                .gridColumnAlignment(.trailing)
                                .foregroundStyle(.secondary)
                            TextField(
                                "Requisitioner",
                                text: Binding(
                                    get: { project.well?.requisitioner ?? "" },
                                    set: { newValue in
                                        if let well = project.well {
                                            well.requisitioner = newValue
                                        }
                                    }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                        }
                        GridRow {
                            Button {
                                copyProjectInfoToClipboard()
                            } label: {
                                Label("Copy Info", systemImage: "doc.on.doc")
                            }
                        }
                    }
                    #endif
                }
                .allowsHitTesting(!project.isDashboardLocked)

                WellSection(title: "Overview", icon: "rectangle.grid.2x2", subtitle: "At-a-glance counters across each workspace.") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        MetricCard(title: "Drill string sections", value: "\(viewmodel.drillStringCount)", caption: "Configured", icon: "cable.connector.horizontal")
                        MetricCard(title: "Annulus sections", value: "\(viewmodel.annulusCount)", caption: "Configured", icon: "circle.grid.hex")
                        MetricCard(title: "Pressure points", value: "\(viewmodel.pressurePointCount)", caption: "Pore/Frac window", icon: "waveform.path.ecg")
                        MetricCard(title: "Survey stations", value: "\(viewmodel.surveysCount)", caption: "Imported/entered", icon: "ruler")
                        MetricCard(title: "Mud checks", value: "\(viewmodel.mudChecksCount)", caption: "Lab results", icon: "testtube.2")
                    }
                }

                // Notes and Tasks sections
                #if os(macOS)
                HStack(alignment: .top, spacing: 16) {
                    projectNotesSection
                    projectTasksSection
                }
                #else
                projectNotesSection
                projectTasksSection
                #endif
            }
            .padding(24)
        }
        .sheet(item: $newTransferToEdit, content: { transfer in
            if let well = project.well {
                MaterialTransferEditorView(well: well, transfer: transfer)
                    .frame(minWidth: 700, minHeight: 500)
            } else {
                Text("No well available")
                    .padding()
            }
        })
        .sheet(isPresented: $showingAddNote) {
            ProjectAddNoteSheet(project: project)
        }
        .sheet(isPresented: $showingAddTask) {
            ProjectAddTaskSheet(project: project)
        }
        .sheet(isPresented: $showingRenameProject) {
            RenameProjectSheet(project: project, renameText: $renameText)
        }
        .alert("Delete Project?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                modelContext.delete(project)
                try? modelContext.save()
            }
        } message: {
            Text("Are you sure you want to delete \"\(project.name)\"? This will delete all drill string sections, annulus sections, surveys, muds, and other data associated with this project.")
        }
        .background(pageBackgroundColor)
        .navigationTitle("Project Dashboard")
    }

    // MARK: - Project Notes Section

    private var projectNotes: [HandoverNote] {
        (project.notes ?? []).sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    private var projectNotesSection: some View {
        WellSection(title: "Project Notes", icon: "note.text", subtitle: "\(projectNotes.count) note(s)") {
            VStack(alignment: .leading, spacing: 8) {
                if !projectNotes.isEmpty {
                    ForEach(projectNotes.prefix(5)) { note in
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
                        }
                        .padding(.vertical, 4)
                    }

                    if projectNotes.count > 5 {
                        Text("+ \(projectNotes.count - 5) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No notes for this project")
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

    // MARK: - Project Tasks Section

    private var projectPendingTasks: [WellTask] {
        (project.tasks ?? []).filter { $0.isPending }.sorted { $0.priority.sortOrder < $1.priority.sortOrder }
    }

    private var projectTasksSection: some View {
        WellSection(title: "Project Tasks", icon: "checkmark.circle", subtitle: "\(projectPendingTasks.count) pending") {
            VStack(alignment: .leading, spacing: 8) {
                if !projectPendingTasks.isEmpty {
                    ForEach(projectPendingTasks.prefix(5)) { task in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(task.status == .completed ? .green : taskPriorityColor(task.priority))

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
                                .background(taskPriorityColor(task.priority).opacity(0.1))
                                .foregroundStyle(taskPriorityColor(task.priority))
                                .cornerRadius(4)
                        }
                        .padding(.vertical, 4)
                    }

                    if projectPendingTasks.count > 5 {
                        Text("+ \(projectPendingTasks.count - 5) more")
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

    private func taskPriorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .low: return .green
        case .medium: return .blue
        case .high: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Project Add Note Sheet

private struct ProjectAddNoteSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let project: ProjectState

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
            .navigationTitle("Add Project Note")
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
                        note.project = project
                        note.well = project.well
                        note.pad = project.well?.pad
                        if project.notes == nil { project.notes = [] }
                        project.notes?.append(note)
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

// MARK: - Project Add Task Sheet

private struct ProjectAddTaskSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let project: ProjectState

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
            .navigationTitle("Add Project Task")
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
                        task.project = project
                        task.well = project.well
                        task.pad = project.well?.pad
                        if project.tasks == nil { project.tasks = [] }
                        project.tasks?.append(task)
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

#if DEBUG
private struct ProjectDashboardPreview: View {
    let container: ModelContainer
    let project: ProjectState

    init() {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.container = try! ModelContainer(
            for: ProjectState.self,
                 DrillStringSection.self,
                 AnnulusSection.self,
                 PressureWindow.self,
                 PressureWindowPoint.self,
            configurations: config
        )
        let ctx = container.mainContext
        let p = ProjectState()
        p.baseAnnulusDensity_kgm3 = 1100
        p.baseStringDensity_kgm3 = 1100
        p.pressureDepth_m = 2500
        ctx.insert(p)

        // Seed a couple of string and annulus sections
        let ds1 = DrillStringSection(name: "DP 5\"", topDepth_m: 0, length_m: 1500, outerDiameter_m: 0.127, innerDiameter_m: 0.0953)
        let ds2 = DrillStringSection(name: "DP 5\" HW", topDepth_m: 1500, length_m: 800, outerDiameter_m: 0.127, innerDiameter_m: 0.0953)
        if p.drillString == nil { p.drillString = [] }
        [ds1, ds2].forEach { s in p.drillString?.append(s); ctx.insert(s) }

        let a1 = AnnulusSection(name: "Surface", topDepth_m: 0,    length_m: 600, innerDiameter_m: 0.340, outerDiameter_m: 0.244)
        let a2 = AnnulusSection(name: "Intermediate", topDepth_m: 600, length_m: 900, innerDiameter_m: 0.244, outerDiameter_m: 0.1778)
        if p.annulus == nil { p.annulus = [] }
        [a1, a2].forEach { s in s.project = p; p.annulus?.append(s); ctx.insert(s) }

        // Seed a few pressure window points
        let w = p.window
        let pw1 = PressureWindowPoint(depth_m: 500,  pore_kPa: 6000,  frac_kPa: 11000, window: w)
        let pw2 = PressureWindowPoint(depth_m: 1500, pore_kPa: 15000, frac_kPa: 24000, window: w)
        let pw3 = PressureWindowPoint(depth_m: 2500, pore_kPa: 22000, frac_kPa: 33000, window: w)
        [pw1, pw2, pw3].forEach { ctx.insert($0) }

        try? ctx.save()
        self.project = p
    }

    var body: some View {
        NavigationStack { ProjectDashboardView(project: project) }
            .modelContainer(container)
            .frame(width: 2000, height: 600)
    }
}

#Preview("Project Dashboard – Sample Data") {
    ProjectDashboardPreview()
}
#endif

private struct InputNumberBox: View {
    let title: String
    @Binding var value: Double
    let caption: String
    let min: Double
    let max: Double
    let step: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Stepper(value: $value, in: min...max, step: step) {
                Text("\(value)")
                    .monospacedDigit()
            }
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))
    }
}






extension ProjectDashboardView {
    /// Builds the multiline string representing key project and well info.
    fileprivate func makeProjectInfoString() -> String {
        let well = project.well
        return """
        Well Name: \(well?.name ?? "-")
        UWI: \(well?.uwi ?? "-")
        AFE: \(well?.afeNumber ?? "-")
        Requisitioner: \(well?.requisitioner ?? "-")
        """
    }

    /// Copies the project info string to the clipboard.
    fileprivate func copyProjectInfoToClipboard() {
        ClipboardService.shared.copyToClipboard(makeProjectInfoString())
    }
}

extension ProjectDashboardView {
    @Observable
    class ViewModel {
        var project: ProjectState
        init(project: ProjectState) { self.project = project }

        var drillStringCount: Int { (project.drillString ?? []).count }
        var annulusCount: Int { (project.annulus ?? []).count }
        var pressurePointCount: Int { (project.window.points ?? []).count }
        var surveysCount: Int { (project.surveys ?? []).count }
        var mudChecksCount: Int { (project.muds ?? []).count }
    }
}

// MARK: - Rename Project Sheet

private struct RenameProjectSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let project: ProjectState
    @Binding var renameText: String

    var body: some View {
        NavigationStack {
            Form {
                TextField("Project Name", text: $renameText)
            }
            .navigationTitle("Rename Project")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        project.name = renameText
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(renameText.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 300, minHeight: 120)
        #endif
    }
}

