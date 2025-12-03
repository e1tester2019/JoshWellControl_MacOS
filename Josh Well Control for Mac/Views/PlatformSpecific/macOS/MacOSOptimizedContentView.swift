//
//  MacOSOptimizedContentView.swift
//  Josh Well Control for Mac
//
//  macOS-optimized interface with native toolbar, keyboard shortcuts, and window management
//

import SwiftUI
import SwiftData

#if os(macOS)
import AppKit

struct MacOSOptimizedContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Well.updatedAt, order: .reverse) private var wells: [Well]

    @State private var selectedWell: Well?
    @State private var selectedProject: ProjectState?
    @State private var selectedView: ViewSelection = .dashboard
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showRenameWell = false
    @State private var showRenameProject = false
    @State private var searchText = ""
    @State private var showCommandPalette = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar - Feature Navigation
            MacOSSidebarView(
                selectedView: $selectedView,
                selectedProject: selectedProject,
                searchText: $searchText
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 300)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: toggleSidebar) {
                        Label("Toggle Sidebar", systemImage: "sidebar.left")
                    }
                    .help("Toggle Sidebar (⌘⌥S)")
                }
            }
        } detail: {
            // Main Content Area
            MacOSDetailView(
                selectedView: selectedView,
                selectedProject: selectedProject,
                selectedWell: selectedWell,
                selectedWellBinding: $selectedWell,
                selectedProjectBinding: $selectedProject,
                showRenameWell: $showRenameWell,
                showRenameProject: $showRenameProject
            )
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(id: "main-toolbar") {
            // Well Selector
            ToolbarItem(id: "well-selector", placement: .navigation) {
                MacOSWellPicker(
                    wells: wells,
                    selectedWell: $selectedWell,
                    selectedProject: $selectedProject,
                    showRenameWell: $showRenameWell,
                    modelContext: modelContext
                )
                .frame(minWidth: 200)
            }

            // Project Selector
            ToolbarItem(id: "project-selector", placement: .navigation) {
                MacOSProjectPicker(
                    selectedWell: selectedWell,
                    selectedProject: $selectedProject,
                    showRenameProject: $showRenameProject,
                    modelContext: modelContext
                )
                .frame(minWidth: 200)
            }

            // Spacer
            ToolbarItem(id: "spacer", placement: .principal) {
                Spacer()
            }

            // Quick Actions
            ToolbarItem(id: "command-palette", placement: .automatic) {
                Button(action: { showCommandPalette.toggle() }) {
                    Label("Command Palette", systemImage: "command")
                }
                .help("Command Palette (⌘K)")
                .keyboardShortcut("k", modifiers: .command)
            }

            ToolbarItem(id: "search", placement: .automatic) {
                Button(action: {}) {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .help("Search (⌘F)")
                .keyboardShortcut("f", modifiers: .command)
            }
        }
        .sheet(isPresented: $showCommandPalette) {
            MacOSCommandPalette(
                wells: wells,
                selectedWell: $selectedWell,
                selectedProject: $selectedProject,
                selectedView: $selectedView,
                isPresented: $showCommandPalette,
                modelContext: modelContext
            )
        }
        .onAppear {
            setupInitialSelection()
            setupKeyboardShortcuts()
        }
    }

    private func setupInitialSelection() {
        if selectedWell == nil, let first = wells.first {
            selectedWell = first
            selectedProject = first.projects?.first
        }
    }

    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }

    private func setupKeyboardShortcuts() {
        // Additional keyboard shortcut setup if needed
    }

    @CommandsBuilder
    private func macOSMenuCommands() -> some Commands {
        CommandGroup(after: .newItem) {
            Button("New Well...") {
                createNewWell()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("New Project...") {
                createNewProject()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(selectedWell == nil)

            Divider()
        }

        CommandGroup(replacing: .sidebar) {
            Button("Toggle Sidebar") {
                toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
        }

        CommandMenu("View") {
            ForEach(ViewSelection.allCases) { view in
                Button(view.title) {
                    selectedView = view
                }
                .optionalKeyboardShortcut(view.keyboardShortcut)
            }
        }

        CommandMenu("Navigate") {
            Button("Command Palette...") {
                showCommandPalette = true
            }
            .keyboardShortcut("k", modifiers: .command)

            Divider()

            Button("Next Project") {
                selectNextProject()
            }
            .keyboardShortcut("]", modifiers: [.command, .option])

            Button("Previous Project") {
                selectPreviousProject()
            }
            .keyboardShortcut("[", modifiers: [.command, .option])
        }
    }

    private func createNewWell() {
        let well = Well(name: "New Well")
        modelContext.insert(well)
        let project = ProjectState()
        project.well = well
        well.projects = [project]
        modelContext.insert(project)
        try? modelContext.save()
        selectedWell = well
        selectedProject = project
    }

    private func createNewProject() {
        guard let well = selectedWell else { return }
        let project = ProjectState()
        project.well = well
        if well.projects == nil {
            well.projects = []
        }
        well.projects?.append(project)
        modelContext.insert(project)
        try? modelContext.save()
        selectedProject = project
    }

    private func selectNextProject() {
        guard let well = selectedWell,
              let projects = well.projects,
              let current = selectedProject,
              let index = projects.firstIndex(where: { $0.id == current.id }) else { return }

        let nextIndex = (index + 1) % projects.count
        selectedProject = projects[nextIndex]
    }

    private func selectPreviousProject() {
        guard let well = selectedWell,
              let projects = well.projects,
              let current = selectedProject,
              let index = projects.firstIndex(where: { $0.id == current.id }) else { return }

        let prevIndex = (index - 1 + projects.count) % projects.count
        selectedProject = projects[prevIndex]
    }
}

// MARK: - macOS Sidebar

struct MacOSSidebarView: View {
    @Binding var selectedView: ViewSelection
    let selectedProject: ProjectState?
    @Binding var searchText: String

    private let geometryViews: [ViewSelection] = [.drillString, .annulus, .volumeSummary, .surveys]
    private let fluidViews: [ViewSelection] = [.mudCheck, .mixingCalc, .mudPlacement]
    private let analysisViews: [ViewSelection] = [.pressureWindow, .pumpSchedule, .swabbing, .tripSimulation]
    private let operationsViews: [ViewSelection] = [.rentals, .transfers]

    var body: some View {
        List(selection: $selectedView) {
            // Dashboard
            Section {
                NavigationLink(value: ViewSelection.dashboard) {
                    Label(ViewSelection.dashboard.title, systemImage: ViewSelection.dashboard.icon)
                }
            }

            // Well Geometry
            Section("Well Geometry") {
                ForEach(geometryViews, id: \.self) { view in
                    NavigationLink(value: view) {
                        Label(view.title, systemImage: view.icon)
                    }
                }
            }

            // Fluids & Mud
            Section("Fluids & Mud") {
                ForEach(fluidViews, id: \.self) { view in
                    NavigationLink(value: view) {
                        Label(view.title, systemImage: view.icon)
                    }
                }
            }

            // Analysis & Simulation
            Section("Analysis & Simulation") {
                ForEach(analysisViews, id: \.self) { view in
                    NavigationLink(value: view) {
                        Label(view.title, systemImage: view.icon)
                    }
                }
            }

            // Operations
            Section("Operations") {
                ForEach(operationsViews, id: \.self) { view in
                    NavigationLink(value: view) {
                        Label(view.title, systemImage: view.icon)
                    }
                }
            }

            // Quick Stats at bottom
            if let project = selectedProject {
                Section("Quick Stats") {
                    MacOSQuickStatRow(label: "Surveys", value: "\((project.surveys ?? []).count)")
                    MacOSQuickStatRow(label: "Drill String", value: "\((project.drillString ?? []).count)")
                    MacOSQuickStatRow(label: "Annulus", value: "\((project.annulus ?? []).count)")
                    MacOSQuickStatRow(label: "Muds", value: "\((project.muds ?? []).count)")
                }
                .font(.caption)
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, prompt: "Search features...")
        .navigationTitle("Features")
    }
}

struct MacOSQuickStatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

// MARK: - macOS Detail View

struct MacOSDetailView: View {
    let selectedView: ViewSelection
    let selectedProject: ProjectState?
    let selectedWell: Well?
    @Binding var selectedWellBinding: Well?
    @Binding var selectedProjectBinding: ProjectState?
    @Binding var showRenameWell: Bool
    @Binding var showRenameProject: Bool

    var body: some View {
        Group {
            if let project = selectedProject {
                switch selectedView {
                case .dashboard:
                    ProjectDashboardView(project: project)
                case .drillString:
                    DrillStringListView(project: project)
                case .annulus:
                    AnnulusListView(project: project)
                case .volumeSummary:
                    VolumeSummaryView(project: project)
                case .surveys:
                    SurveyListView(project: project)
                case .mudCheck:
                    MudCheckView(project: project)
                case .mixingCalc:
                    MixingCalculatorView(project: project)
                case .pressureWindow:
                    PressureWindowView(project: project)
                case .mudPlacement:
                    MudPlacementView(project: project)
                case .pumpSchedule:
                    PumpScheduleView(project: project)
                case .swabbing:
                    SwabbingView(project: project)
                case .tripSimulation:
                    TripSimulationView(project: project)
                case .rentals:
                    if let well = selectedWell {
                        RentalItemsView(well: well)
                    }
                case .transfers:
                    if let well = selectedWell {
                        MaterialTransferListView(well: well)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No Project Selected", systemImage: "folder.badge.questionmark")
                } description: {
                    Text("Select or create a project to get started")
                } actions: {
                    Button("Create New Well") {
                        // Create well action
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - macOS Well Picker

struct MacOSWellPicker: View {
    let wells: [Well]
    @Binding var selectedWell: Well?
    @Binding var selectedProject: ProjectState?
    @Binding var showRenameWell: Bool
    let modelContext: ModelContext

    var body: some View {
        Menu {
            ForEach(wells) { well in
                Button(action: {
                    selectedWell = well
                    selectedProject = well.projects?.first
                }) {
                    HStack {
                        Text(well.name)
                        if selectedWell?.id == well.id {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button(action: createNewWell) {
                Label("New Well", systemImage: "plus")
            }
            Button(action: { showRenameWell = true }) {
                Label("Rename Well", systemImage: "pencil")
            }
            .disabled(selectedWell == nil)
            Button(role: .destructive, action: deleteCurrentWell) {
                Label("Delete Well", systemImage: "trash")
            }
            .disabled(selectedWell == nil)
        } label: {
            HStack {
                Image(systemName: "building.2")
                    .foregroundStyle(.secondary)
                Text(selectedWell?.name ?? "Select Well")
                    .fontWeight(.medium)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.5))
            .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
        .help("Select Well (⌘⌥W)")
    }

    private func createNewWell() {
        let well = Well(name: "New Well")
        modelContext.insert(well)
        let project = ProjectState()
        project.well = well
        well.projects = [project]
        modelContext.insert(project)
        try? modelContext.save()
        selectedWell = well
        selectedProject = project
    }

    private func deleteCurrentWell() {
        guard let well = selectedWell else { return }
        modelContext.delete(well)
        try? modelContext.save()
        selectedWell = wells.first
        selectedProject = selectedWell?.projects?.first
    }
}

// MARK: - macOS Project Picker

struct MacOSProjectPicker: View {
    let selectedWell: Well?
    @Binding var selectedProject: ProjectState?
    @Binding var showRenameProject: Bool
    let modelContext: ModelContext

    var body: some View {
        Menu {
            if let well = selectedWell {
                ForEach(well.projects ?? []) { project in
                    Button(action: {
                        selectedProject = project
                    }) {
                        HStack {
                            Text(project.name)
                            if selectedProject?.id == project.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Button(action: createNewProject) {
                    Label("New Project", systemImage: "plus")
                }
                Button(action: { showRenameProject = true }) {
                    Label("Rename Project", systemImage: "pencil")
                }
                .disabled(selectedProject == nil)
                Button(role: .destructive, action: deleteCurrentProject) {
                    Label("Delete Project", systemImage: "trash")
                }
                .disabled(selectedProject == nil)
            } else {
                Text("No Well Selected")
                    .foregroundStyle(.secondary)
            }
        } label: {
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(selectedProject?.name ?? "Select Project")
                    .fontWeight(.medium)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.5))
            .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
        .help("Select Project (⌘⌥P)")
        .disabled(selectedWell == nil)
    }

    private func createNewProject() {
        guard let well = selectedWell else { return }
        let project = ProjectState()
        project.well = well
        if well.projects == nil {
            well.projects = []
        }
        well.projects?.append(project)
        modelContext.insert(project)
        try? modelContext.save()
        selectedProject = project
    }

    private func deleteCurrentProject() {
        guard let project = selectedProject else { return }
        modelContext.delete(project)
        try? modelContext.save()
        selectedProject = selectedWell?.projects?.first
    }
}

// MARK: - macOS Command Palette

struct MacOSCommandPalette: View {
    let wells: [Well]
    @Binding var selectedWell: Well?
    @Binding var selectedProject: ProjectState?
    @Binding var selectedView: ViewSelection
    @Binding var isPresented: Bool
    let modelContext: ModelContext

    @State private var searchText = ""
    @State private var selectedCommand: CommandPaletteItem?

    enum CommandPaletteItem: Identifiable {
        case view(ViewSelection)
        case well(Well)
        case project(ProjectState)
        case action(String, () -> Void)

        var id: String {
            switch self {
            case .view(let view): return "view-\(view.rawValue)"
            case .well(let well): return "well-\(well.id)"
            case .project(let project): return "project-\(project.id)"
            case .action(let name, _): return "action-\(name)"
            }
        }

        var title: String {
            switch self {
            case .view(let view): return view.title
            case .well(let well): return well.name
            case .project(let project): return project.name
            case .action(let name, _): return name
            }
        }

        var subtitle: String {
            switch self {
            case .view: return "View"
            case .well: return "Well"
            case .project: return "Project"
            case .action: return "Action"
            }
        }

        var icon: String {
            switch self {
            case .view(let view): return view.icon
            case .well: return "building.2"
            case .project: return "folder"
            case .action: return "bolt"
            }
        }
    }

    private var filteredCommands: [CommandPaletteItem] {
        var commands: [CommandPaletteItem] = []

        // Views
        commands.append(contentsOf: ViewSelection.allCases.map { .view($0) })

        // Wells
        commands.append(contentsOf: wells.map { .well($0) })

        // Projects
        if let well = selectedWell {
            commands.append(contentsOf: (well.projects ?? []).map { .project($0) })
        }

        // Actions
        commands.append(.action("New Well", createNewWell))
        commands.append(.action("New Project", createNewProject))

        // Filter by search
        if searchText.isEmpty {
            return commands
        } else {
            return commands.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Type a command or search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
            }
            .padding()
            .background(.quaternary.opacity(0.3))

            Divider()

            // Commands list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredCommands) { command in
                        MacOSCommandPaletteRow(
                            command: command,
                            isSelected: selectedCommand?.id == command.id
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            executeCommand(command)
                        }
                    }
                }
            }
        }
        .frame(width: 600, height: 400)
        .background(.ultraThickMaterial)
    }

    private func executeCommand(_ command: CommandPaletteItem) {
        switch command {
        case .view(let view):
            selectedView = view
        case .well(let well):
            selectedWell = well
            selectedProject = well.projects?.first
        case .project(let project):
            selectedProject = project
        case .action(_, let action):
            action()
        }
        isPresented = false
    }

    private func createNewWell() {
        let well = Well(name: "New Well")
        modelContext.insert(well)
        let project = ProjectState()
        project.well = well
        well.projects = [project]
        modelContext.insert(project)
        try? modelContext.save()
        selectedWell = well
        selectedProject = project
    }

    private func createNewProject() {
        guard let well = selectedWell else { return }
        let project = ProjectState()
        project.well = well
        if well.projects == nil {
            well.projects = []
        }
        well.projects?.append(project)
        modelContext.insert(project)
        try? modelContext.save()
        selectedProject = project
    }
}

struct MacOSCommandPaletteRow: View {
    let command: MacOSCommandPalette.CommandPaletteItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: command.icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .fontWeight(.medium)
                Text(command.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
    }
}

private extension View {
    @ViewBuilder
    func optionalKeyboardShortcut(_ key: KeyEquivalent?) -> some View {
        if let key {
            self.keyboardShortcut(key)
        } else {
            self
        }
    }
}

#endif

