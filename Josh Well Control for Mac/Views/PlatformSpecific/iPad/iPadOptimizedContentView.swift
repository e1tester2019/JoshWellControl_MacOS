//
//  iPadOptimizedContentView.swift
//  Josh Well Control for Mac
//
//  iPad-optimized interface with split view, multitasking, and touch-first interactions
//

import SwiftUI
import SwiftData

#if os(iOS)
import UIKit

struct iPadOptimizedContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Well.updatedAt, order: .reverse) private var wells: [Well]

    @State private var selectedWell: Well?
    @State private var selectedProject: ProjectState?
    @State private var selectedView: ViewSelection = .dashboard
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showWellPicker = false
    @State private var showProjectPicker = false
    @State private var showRenameWell = false
    @State private var showRenameProject = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar - Feature Selection
            iPadSidebarView(selectedView: $selectedView, selectedProject: selectedProject)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } detail: {
            // Detail - Main content
            iPadDetailView(
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
        .onAppear {
            if selectedWell == nil, let first = wells.first {
                selectedWell = first
                selectedProject = first.projects?.first
            }
        }
    }

    @ViewBuilder
    private var wellMenuContent: some View {
        ForEach(wells) { well in
            Button(action: {
                selectedWell = well
                selectedProject = well.projects?.first
            }) {
                Label(well.name, systemImage: selectedWell?.id == well.id ? "checkmark" : "building.2")
            }
        }
        Divider()
        Button(action: { createNewWell() }) {
            Label("New Well", systemImage: "plus")
        }
        Button(action: { showRenameWell = true }) {
            Label("Rename Well", systemImage: "pencil")
        }
        .disabled(selectedWell == nil)
        Button(role: .destructive, action: { deleteCurrentWell() }) {
            Label("Delete Well", systemImage: "trash")
        }
        .disabled(selectedWell == nil)
    }

    @ViewBuilder
    private var projectMenuContent: some View {
        if let well = selectedWell {
            ForEach(well.projects ?? []) { project in
                Button(action: {
                    selectedProject = project
                }) {
                    Label(project.name, systemImage: selectedProject?.id == project.id ? "checkmark" : "folder")
                }
            }
            Divider()
            Button(action: { createNewProject() }) {
                Label("New Project", systemImage: "plus")
            }
            Button(action: { showRenameProject = true }) {
                Label("Rename Project", systemImage: "pencil")
            }
            .disabled(selectedProject == nil)
            Button(role: .destructive, action: { deleteCurrentProject() }) {
                Label("Delete Project", systemImage: "trash")
            }
            .disabled(selectedProject == nil)
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

    private func deleteCurrentWell() {
        guard let well = selectedWell else { return }
        modelContext.delete(well)
        try? modelContext.save()
        selectedWell = wells.first
        selectedProject = selectedWell?.projects?.first
    }

    private func deleteCurrentProject() {
        guard let project = selectedProject else { return }
        modelContext.delete(project)
        try? modelContext.save()
        selectedProject = selectedWell?.projects?.first
    }
}

// MARK: - iPad Sidebar

struct iPadSidebarView: View {
    @Binding var selectedView: ViewSelection
    let selectedProject: ProjectState?

    var body: some View {
        List {
            ForEach(ViewSelection.allCases) { view in
                Button(action: {
                    selectedView = view
                }) {
                    HStack {
                        Label(view.title, systemImage: view.icon)
                            .font(.body)
                        Spacer()
                        if selectedView == view {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .listRowBackground(selectedView == view ? Color.accentColor.opacity(0.1) : Color.clear)
            }
        }
        .navigationTitle("Features")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.sidebar)
    }
}

// MARK: - iPad Detail View

struct iPadDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Well.updatedAt, order: .reverse) private var wells: [Well]

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
                ContentUnavailableView(
                    "No Project Selected",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Select or create a project to get started")
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Well picker
            ToolbarItem(placement: .topBarLeading) {
                if wells.isEmpty {
                    Button(action: { createNewWell() }) {
                        Label("New Well", systemImage: "plus.circle.fill")
                    }
                } else {
                    Menu {
                        wellMenuContent
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "building.2")
                            Text(selectedWell?.name ?? "Select Well")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                    }
                }
            }

            // Project picker
            ToolbarItem(placement: .topBarTrailing) {
                if !wells.isEmpty {
                    Menu {
                        projectMenuContent
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                            Text(selectedProject?.name ?? "Select Project")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                    }
                    .disabled(selectedWell == nil)
                }
            }
        }
    }

    @ViewBuilder
    private var wellMenuContent: some View {
        ForEach(wells) { well in
            Button(action: {
                selectedWellBinding = well
                selectedProjectBinding = well.projects?.first
            }) {
                Label(well.name, systemImage: selectedWell?.id == well.id ? "checkmark" : "building.2")
            }
        }
        Divider()
        Button(action: { createNewWell() }) {
            Label("New Well", systemImage: "plus")
        }
        Button(action: { showRenameWell = true }) {
            Label("Rename Well", systemImage: "pencil")
        }
        .disabled(selectedWell == nil)
        Button(role: .destructive, action: { deleteCurrentWell() }) {
            Label("Delete Well", systemImage: "trash")
        }
        .disabled(selectedWell == nil)
    }

    @ViewBuilder
    private var projectMenuContent: some View {
        if let well = selectedWell {
            ForEach(well.projects ?? []) { project in
                Button(action: {
                    selectedProjectBinding = project
                }) {
                    Label(project.name, systemImage: selectedProject?.id == project.id ? "checkmark" : "folder")
                }
            }
            Divider()
            Button(action: { createNewProject() }) {
                Label("New Project", systemImage: "plus")
            }
            Button(action: { showRenameProject = true }) {
                Label("Rename Project", systemImage: "pencil")
            }
            .disabled(selectedProject == nil)
            Button(role: .destructive, action: { deleteCurrentProject() }) {
                Label("Delete Project", systemImage: "trash")
            }
            .disabled(selectedProject == nil)
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
        selectedWellBinding = well
        selectedProjectBinding = project
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
        selectedProjectBinding = project
    }

    private func deleteCurrentWell() {
        guard let well = selectedWell else { return }
        modelContext.delete(well)
        try? modelContext.save()
        selectedWellBinding = wells.first
        selectedProjectBinding = selectedWellBinding?.projects?.first
    }

    private func deleteCurrentProject() {
        guard let project = selectedProject else { return }
        modelContext.delete(project)
        try? modelContext.save()
        selectedProjectBinding = selectedWell?.projects?.first
    }
}

// MARK: - iPad Toolbar

struct iPadToolbarContent: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Well.updatedAt, order: .reverse) private var wells: [Well]
    
    let selectedWell: Well?
    let selectedProject: ProjectState?
    @Binding var selectedWellBinding: Well?
    @Binding var selectedProjectBinding: ProjectState?
    @Binding var showRenameWell: Bool
    @Binding var showRenameProject: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Well Selector
            Menu {
                ForEach(wells) { well in
                    Button(action: {
                        selectedWellBinding = well
                        selectedProjectBinding = well.projects?.first
                    }) {
                        Label(well.name, systemImage: selectedWell?.id == well.id ? "checkmark" : "building.2")
                    }
                }
                Divider()
                Button(action: { createNewWell() }) {
                    Label("New Well", systemImage: "plus")
                }
                Button(action: { showRenameWell = true }) {
                    Label("Rename Well", systemImage: "pencil")
                }
                .disabled(selectedWell == nil)
                Button(role: .destructive, action: { deleteCurrentWell() }) {
                    Label("Delete Well", systemImage: "trash")
                }
                .disabled(selectedWell == nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "building.2")
                    Text(selectedWell?.name ?? "Select Well")
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Project Selector
            Menu {
                if let well = selectedWell {
                    ForEach(well.projects ?? []) { project in
                        Button(action: {
                            selectedProjectBinding = project
                        }) {
                            Label(project.name, systemImage: selectedProject?.id == project.id ? "checkmark" : "folder")
                        }
                    }
                    Divider()
                    Button(action: { createNewProject() }) {
                        Label("New Project", systemImage: "plus")
                    }
                    Button(action: { showRenameProject = true }) {
                        Label("Rename Project", systemImage: "pencil")
                    }
                    .disabled(selectedProject == nil)
                    Button(role: .destructive, action: { deleteCurrentProject() }) {
                        Label("Delete Project", systemImage: "trash")
                    }
                    .disabled(selectedProject == nil)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                    Text(selectedProject?.name ?? "Select Project")
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
            }
            .disabled(selectedWell == nil)
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
        selectedWellBinding = well
        selectedProjectBinding = project
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
        selectedProjectBinding = project
    }

    private func deleteCurrentWell() {
        guard let well = selectedWell else { return }
        modelContext.delete(well)
        try? modelContext.save()
        selectedWellBinding = wells.first
        selectedProjectBinding = selectedWellBinding?.projects?.first
    }

    private func deleteCurrentProject() {
        guard let project = selectedProject else { return }
        modelContext.delete(project)
        try? modelContext.save()
        selectedProjectBinding = selectedWell?.projects?.first
    }
}

#endif

