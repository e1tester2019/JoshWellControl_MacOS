//
//  iPhoneOptimizedContentView.swift
//  Josh Well Control for Mac
//
//  iPhone-optimized interface with tab-based navigation for compact screens
//

import SwiftUI
import SwiftData

#if os(iOS)
import UIKit

struct iPhoneOptimizedContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Well.updatedAt, order: .reverse) private var wells: [Well]

    @State private var selectedWell: Well?
    @State private var selectedProject: ProjectState?
    @State private var selectedTab: TabCategory = .technical
    @State private var showWellPicker = false
    @State private var showProjectPicker = false
    @State private var showRenameWell = false
    @State private var showRenameProject = false
    @State private var renameText = ""

    enum TabCategory: String, CaseIterable {
        case technical = "Technical"
        case operations = "Operations"
        case simulation = "Simulation"
        case business = "Business"
        case more = "More"

        var icon: String {
            switch self {
            case .technical: return "gauge.with.dots.needle.67percent"
            case .operations: return "drop.fill"
            case .simulation: return "play.circle.fill"
            case .business: return "dollarsign.circle.fill"
            case .more: return "ellipsis.circle.fill"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // Technical Tab
            NavigationStack {
                technicalTabContent
            }
            .tabItem {
                Label(TabCategory.technical.rawValue, systemImage: TabCategory.technical.icon)
            }
            .tag(TabCategory.technical)

            // Operations Tab
            NavigationStack {
                operationsTabContent
            }
            .tabItem {
                Label(TabCategory.operations.rawValue, systemImage: TabCategory.operations.icon)
            }
            .tag(TabCategory.operations)

            // Simulation Tab
            NavigationStack {
                simulationTabContent
            }
            .tabItem {
                Label(TabCategory.simulation.rawValue, systemImage: TabCategory.simulation.icon)
            }
            .tag(TabCategory.simulation)

            // Business Tab
            NavigationStack {
                businessTabContent
            }
            .tabItem {
                Label(TabCategory.business.rawValue, systemImage: TabCategory.business.icon)
            }
            .tag(TabCategory.business)

            // More Tab
            NavigationStack {
                moreTabContent
            }
            .tabItem {
                Label(TabCategory.more.rawValue, systemImage: TabCategory.more.icon)
            }
            .tag(TabCategory.more)
        }
        .onAppear {
            if selectedWell == nil, let first = wells.first {
                selectedWell = first
                selectedProject = first.projects?.first
            }
        }
        .sheet(isPresented: $showRenameWell) {
            renameSheet(title: "Rename Well", currentName: selectedWell?.name ?? "", onSave: { newName in
                selectedWell?.name = newName
                try? modelContext.save()
            })
        }
        .sheet(isPresented: $showRenameProject) {
            renameSheet(title: "Rename Project", currentName: selectedProject?.name ?? "", onSave: { newName in
                selectedProject?.name = newName
                try? modelContext.save()
            })
        }
    }

    // MARK: - Technical Tab Content

    private var technicalTabContent: some View {
        List {
            // Well/Project selector section
            Section {
                wellProjectSelector
            }

            // Navigation items
            Section("Well Geometry") {
                if let project = selectedProject {
                    NavigationLink {
                        DrillStringListViewIOS(project: project)
                    } label: {
                        Label(ViewSelection.drillString.title, systemImage: ViewSelection.drillString.icon)
                    }

                    NavigationLink {
                        AnnulusListViewIOS(project: project)
                    } label: {
                        Label(ViewSelection.annulus.title, systemImage: ViewSelection.annulus.icon)
                    }

                    NavigationLink {
                        VolumeSummaryViewIOS(project: project)
                    } label: {
                        Label(ViewSelection.volumeSummary.title, systemImage: ViewSelection.volumeSummary.icon)
                    }

                    NavigationLink {
                        SurveyListViewIOS(project: project)
                    } label: {
                        Label(ViewSelection.surveys.title, systemImage: ViewSelection.surveys.icon)
                    }
                } else {
                    noProjectSelectedRow
                }
            }

            Section("Dashboard") {
                if let project = selectedProject {
                    NavigationLink {
                        ProjectDashboardView(project: project)
                    } label: {
                        Label(ViewSelection.dashboard.title, systemImage: ViewSelection.dashboard.icon)
                    }
                } else {
                    noProjectSelectedRow
                }
            }
        }
        .navigationTitle("Technical")
        .listStyle(.insetGrouped)
    }

    // MARK: - Operations Tab Content

    private var operationsTabContent: some View {
        List {
            Section {
                wellProjectSelector
            }

            Section("Fluids") {
                if let project = selectedProject {
                    NavigationLink {
                        MudCheckViewIOS(project: project)
                    } label: {
                        Label(ViewSelection.mudCheck.title, systemImage: ViewSelection.mudCheck.icon)
                    }

                    NavigationLink {
                        MixingCalculatorViewIOS(project: project)
                    } label: {
                        Label(ViewSelection.mixingCalc.title, systemImage: ViewSelection.mixingCalc.icon)
                    }

                    NavigationLink {
                        iPadMudPlacementView(project: project)
                    } label: {
                        Label(ViewSelection.mudPlacement.title, systemImage: ViewSelection.mudPlacement.icon)
                    }
                } else {
                    noProjectSelectedRow
                }
            }

            Section("Pressure Management") {
                if let project = selectedProject {
                    NavigationLink {
                        PressureWindowViewIOS(project: project)
                    } label: {
                        Label(ViewSelection.pressureWindow.title, systemImage: ViewSelection.pressureWindow.icon)
                    }

                    NavigationLink {
                        SwabbingViewIOS(project: project)
                    } label: {
                        Label(ViewSelection.swabbing.title, systemImage: ViewSelection.swabbing.icon)
                    }
                } else {
                    noProjectSelectedRow
                }
            }
        }
        .navigationTitle("Operations")
        .listStyle(.insetGrouped)
    }

    // MARK: - Simulation Tab Content

    private var simulationTabContent: some View {
        List {
            Section {
                wellProjectSelector
            }

            Section("Simulations") {
                if let project = selectedProject {
                    NavigationLink {
                        PumpScheduleViewIOS(project: project)
                    } label: {
                        Label(ViewSelection.pumpSchedule.title, systemImage: ViewSelection.pumpSchedule.icon)
                    }

                    NavigationLink {
                        CementJobView(project: project)
                    } label: {
                        Label(ViewSelection.cementJob.title, systemImage: ViewSelection.cementJob.icon)
                    }

                    NavigationLink {
                        TripSimulationViewIOS(project: project)
                    } label: {
                        Label(ViewSelection.tripSimulation.title, systemImage: ViewSelection.tripSimulation.icon)
                    }
                } else {
                    noProjectSelectedRow
                }
            }
        }
        .navigationTitle("Simulation")
        .listStyle(.insetGrouped)
    }

    // MARK: - Business Tab Content

    private var businessTabContent: some View {
        List {
            Section("Work & Invoicing") {
                NavigationLink {
                    WorkTrackingContainerViewIOS()
                } label: {
                    Label(ViewSelection.workTracking.title, systemImage: ViewSelection.workTracking.icon)
                }
            }

            Section("Expenses & Mileage") {
                NavigationLink {
                    ExpenseListViewIOS()
                } label: {
                    Label("Expenses", systemImage: "creditcard.fill")
                }

                NavigationLink {
                    MileageLogViewIOS()
                } label: {
                    Label("Mileage Log", systemImage: "car.fill")
                }
            }

            Section("Equipment") {
                if let well = selectedWell {
                    NavigationLink {
                        RentalItemsViewIOS(well: well)
                    } label: {
                        Label(ViewSelection.rentals.title, systemImage: ViewSelection.rentals.icon)
                    }

                    NavigationLink {
                        MaterialTransferListViewIOS(well: well)
                    } label: {
                        Label(ViewSelection.transfers.title, systemImage: ViewSelection.transfers.icon)
                    }
                } else {
                    Text("Select a well first")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Business")
        .listStyle(.insetGrouped)
    }

    // MARK: - More Tab Content

    private var moreTabContent: some View {
        List {
            Section("Well Management") {
                wellProjectSelector
            }

            Section("Actions") {
                Button(action: createNewWell) {
                    Label("New Well", systemImage: "plus.circle")
                }

                Button(action: createNewProject) {
                    Label("New Project", systemImage: "folder.badge.plus")
                }
                .disabled(selectedWell == nil)

                Button(action: { showRenameWell = true }) {
                    Label("Rename Well", systemImage: "pencil")
                }
                .disabled(selectedWell == nil)

                Button(action: { showRenameProject = true }) {
                    Label("Rename Project", systemImage: "pencil.line")
                }
                .disabled(selectedProject == nil)

                Button(role: .destructive, action: deleteCurrentWell) {
                    Label("Delete Well", systemImage: "trash")
                }
                .disabled(selectedWell == nil)

                Button(role: .destructive, action: deleteCurrentProject) {
                    Label("Delete Project", systemImage: "trash")
                }
                .disabled(selectedProject == nil)
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("More")
        .listStyle(.insetGrouped)
    }

    // MARK: - Well/Project Selector

    private var wellProjectSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Well picker
            HStack {
                Image(systemName: "building.2")
                    .foregroundStyle(.secondary)
                Picker("Well", selection: $selectedWell) {
                    Text("Select Well").tag(nil as Well?)
                    ForEach(wells) { well in
                        Text(well.name).tag(well as Well?)
                    }
                }
                .onChange(of: selectedWell) { _, newWell in
                    selectedProject = newWell?.projects?.first
                }
            }

            // Project picker
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Picker("Project", selection: $selectedProject) {
                    Text("Select Project").tag(nil as ProjectState?)
                    if let well = selectedWell {
                        ForEach(well.projects ?? []) { project in
                            Text(project.name).tag(project as ProjectState?)
                        }
                    }
                }
                .disabled(selectedWell == nil)
            }
        }
    }

    private var noProjectSelectedRow: some View {
        Text("Select a project first")
            .foregroundStyle(.secondary)
            .italic()
    }

    // MARK: - Rename Sheet

    private func renameSheet(title: String, currentName: String, onSave: @escaping (String) -> Void) -> some View {
        NavigationStack {
            Form {
                TextField("Name", text: $renameText)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showRenameWell = false
                        showRenameProject = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(renameText)
                        showRenameWell = false
                        showRenameProject = false
                    }
                    .disabled(renameText.isEmpty)
                }
            }
            .onAppear {
                renameText = currentName
            }
        }
    }

    // MARK: - CRUD Operations

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

#endif
