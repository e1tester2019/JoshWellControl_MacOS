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
                .navigationDestination(for: ViewSelection.self) { selection in
                    switch selection {
                    case .dashboard:
                        iPadQuickStats(project: selectedProject)
                    case .drillString:
                        iPadDrillStringList(project: selectedProject)
                    case .annulus:
                        iPadAnnulusList(project: selectedProject)
                    case .surveys:
                        iPadSurveyList(project: selectedProject)
                    case .mudCheck:
                        iPadMudList(project: selectedProject)
                    case .mixingCalc:
                        MixingCalculatorView(project: selectedProject ?? ProjectState())
                    case .pressureWindow:
                        PressureWindowView(project: selectedProject ?? ProjectState())
                    case .mudPlacement:
                        MudPlacementView(project: selectedProject ?? ProjectState())
                    case .volumeSummary:
                        VolumeSummaryView(project: selectedProject ?? ProjectState())
                    case .pumpSchedule:
                        PumpScheduleView(project: selectedProject ?? ProjectState())
                    case .swabbing:
                        SwabbingView(project: selectedProject ?? ProjectState())
                    case .tripSimulation:
                        TripSimulationView(project: selectedProject ?? ProjectState())
                    case .rentals:
                        RentalItemsView(well: selectedWell ?? Well())
                    case .transfers:
                        MaterialTransferListView(well: selectedWell ?? Well())
                    }
                }
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } content: {
            // Middle column - Context/List (for landscape)
            if horizontalSizeClass == .regular {
                iPadContextView(
                    selectedView: selectedView,
                    selectedProject: selectedProject,
                    selectedWell: selectedWell
                )
                .navigationSplitViewColumnWidth(min: 300, ideal: 350, max: 400)
            }
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
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                if horizontalSizeClass == .compact {
                    Menu {
                        wellMenuContent
                    } label: {
                        Label(selectedWell?.name ?? "Select Well", systemImage: "building.2")
                    }
                }
            }

            ToolbarItemGroup(placement: .principal) {
                if horizontalSizeClass == .regular {
                    iPadToolbarContent(
                        selectedWell: selectedWell,
                        selectedProject: selectedProject,
                        selectedWellBinding: $selectedWell,
                        selectedProjectBinding: $selectedProject,
                        showRenameWell: $showRenameWell,
                        showRenameProject: $showRenameProject
                    )
                }
            }

            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if horizontalSizeClass == .compact {
                    Menu {
                        projectMenuContent
                    } label: {
                        Label(selectedProject?.name ?? "Select Project", systemImage: "folder")
                    }
                }
            }
        }
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
            ForEach(ViewSelection.allCases, id: \.self) { view in
                NavigationLink(value: view) {
                    Label(view.title, systemImage: view.icon)
                        .font(.body)
                }
            }
        }
        .navigationTitle("Features")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.sidebar)
    }
}

// MARK: - iPad Context View (Middle Column)

struct iPadContextView: View {
    let selectedView: ViewSelection
    let selectedProject: ProjectState?
    let selectedWell: Well?

    var body: some View {
        Group {
            if selectedProject != nil {
                switch selectedView {
                case .drillString:
                    iPadDrillStringList(project: selectedProject)
                case .annulus:
                    iPadAnnulusList(project: selectedProject)
                case .surveys:
                    iPadSurveyList(project: selectedProject)
                case .mudCheck:
                    iPadMudList(project: selectedProject)
                case .rentals:
                    iPadRentalsList(well: selectedWell)
                case .transfers:
                    iPadTransfersList(well: selectedWell)
                default:
                    iPadQuickStats(project: selectedProject)
                }
            } else {
                ContentUnavailableView(
                    "No Project Selected",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Select or create a project to continue")
                )
            }
        }
        .navigationTitle(selectedView.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - iPad Quick Stats

struct iPadQuickStats: View {
    let project: ProjectState?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let project = project {
                    iPadStatsCard(
                        title: "Well Data",
                        items: [
                            ("Surveys", "\((project.surveys ?? []).count)"),
                            ("Drill String", "\((project.drillString ?? []).count) sections"),
                            ("Annulus", "\((project.annulus ?? []).count) sections")
                        ]
                    )

                    iPadStatsCard(
                        title: "Fluids",
                        items: [
                            ("Muds Defined", "\((project.muds ?? []).count)"),
                            ("Active Mud", project.activeMud?.name ?? "None"),
                            ("Density", String(format: "%.0f kg/m³", project.activeMudDensity_kgm3))
                        ]
                    )

                    iPadStatsCard(
                        title: "Last Updated",
                        items: [
                            ("Project", project.name),
                            ("Modified", project.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        ]
                    )
                }
            }
            .padding()
        }
    }
}

struct iPadStatsCard: View {
    let title: String
    let items: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.0) { item in
                    HStack {
                        Text(item.0)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(item.1)
                            .fontWeight(.medium)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

// MARK: - iPad Detail View

struct iPadDetailView: View {
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
    }
}

// MARK: - iPad Toolbar

struct iPadToolbarContent: View {
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
                // Well menu items here
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
                // Project menu items here
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
        }
    }
}

// MARK: - Supporting Views (Placeholders for list views)

struct iPadDrillStringList: View {
    let project: ProjectState?
    var body: some View {
        List {
            ForEach(project?.drillString ?? []) { section in
                VStack(alignment: .leading) {
                    Text(section.name)
                        .font(.headline)
                    Text("Top: \(Int(section.topDepth_m))m | Length: \(Int(section.length_m))m")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct iPadAnnulusList: View {
    let project: ProjectState?
    var body: some View {
        List {
            ForEach(project?.annulus ?? []) { section in
                VStack(alignment: .leading) {
                    Text(section.name)
                        .font(.headline)
                    Text("Top: \(Int(section.topDepth_m))m | Length: \(Int(section.length_m))m")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct iPadSurveyList: View {
    let project: ProjectState?
    var body: some View {
        List {
            ForEach(project?.surveys ?? []) { survey in
                VStack(alignment: .leading) {
                    Text("MD: \(Int(survey.md))m")
                        .font(.headline)
                    Text("Inc: \(String(format: "%.1f", survey.inc))° | Azi: \(String(format: "%.1f", survey.azi))°")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct iPadMudList: View {
    let project: ProjectState?
    var body: some View {
        List {
            ForEach(project?.muds ?? []) { mud in
                HStack {
                    Circle()
                        .fill(mud.color)
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading) {
                        Text(mud.name)
                            .font(.headline)
                        Text("\(Int(mud.density_kgm3)) kg/m³")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if mud.isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct iPadRentalsList: View {
    let well: Well?
    var body: some View {
        List {
            ForEach(well?.rentals ?? [], id: \.id) { rental in
                VStack(alignment: .leading) {
                    Text(rental.name)
                        .font(.headline)
                    Text(rental.detail ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct iPadTransfersList: View {
    let well: Well?

    private var transfersArray: [MaterialTransfer] {
        if let well = well, let transfers = well.transfers {
            return transfers
        } else {
            return []
        }
    }

    var body: some View {
        Group {
            if well == nil {
                ContentUnavailableView(
                    "No Well Selected",
                    systemImage: "building.2.crop.circle.badge.exclamationmark",
                    description: Text("Select a well to view its material transfers.")
                )
            } else if transfersArray.isEmpty {
                ContentUnavailableView(
                    "No Transfers",
                    systemImage: "shippingbox",
                    description: Text("There are no material transfers for this well.")
                )
            } else {
                List {
                    ForEach(transfersArray, id: \MaterialTransfer.id) { transfer in
                        VStack(alignment: .leading) {
                            Text("Transfer #\(transfer.number)")
                                .font(.headline)
                            Text(transfer.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }
}

#endif

