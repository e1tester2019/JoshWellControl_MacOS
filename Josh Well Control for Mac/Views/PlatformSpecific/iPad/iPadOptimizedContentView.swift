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
    @Query(sort: \Pad.name) private var pads: [Pad]

    @State private var selectedWell: Well?
    @State private var selectedProject: ProjectState?
    @State private var selectedPad: Pad?
    @State private var selectedView: ViewSelection = .wellDashboard
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showWellPicker = false
    @State private var showProjectPicker = false
    @State private var showRenameWell = false
    @State private var showRenameProject = false
    @State private var quickNoteManager = QuickNoteManager.shared
    @State private var taskCountDebounce: Task<Void, Never>?

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
                selectedPad: selectedPad,
                pads: pads,
                selectedWellBinding: $selectedWell,
                selectedProjectBinding: $selectedProject,
                selectedPadBinding: $selectedPad,
                selectedViewBinding: $selectedView,
                showRenameWell: $showRenameWell,
                showRenameProject: $showRenameProject
            )
        }
        .navigationSplitViewStyle(.balanced)
        .quickAddSheet(manager: quickNoteManager)
        .onAppear {
            if selectedWell == nil, let first = wells.first {
                selectedWell = first
                selectedProject = first.projects?.first
                selectedPad = first.pad ?? pads.first
            } else {
                selectedPad = selectedWell?.pad ?? pads.first
            }
            // Initialize quick note context
            quickNoteManager.updateContext(well: selectedWell, project: selectedProject)
            quickNoteManager.updateTaskCounts(from: wells)
        }
        .onChange(of: selectedWell) { _, newWell in
            quickNoteManager.updateContext(well: newWell, project: selectedProject)
            // Sync pad selection
            if let well = newWell, well.pad != selectedPad {
                selectedPad = well.pad
            }
        }
        .onChange(of: selectedProject) { _, newProject in
            quickNoteManager.updateContext(well: selectedWell, project: newProject)
        }
        .onChange(of: wells) { _, newWells in
            taskCountDebounce?.cancel()
            taskCountDebounce = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                quickNoteManager.updateTaskCounts(from: newWells)
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

    // Technical sections (same as macOS)
    private let dashboardViews: [ViewSelection] = [.handover, .padDashboard, .wellDashboard, .dashboard]
    private let geometryViews: [ViewSelection] = [.drillString, .annulus, .volumeSummary, .surveys]
    private let fluidViews: [ViewSelection] = [.mudCheck, .mixingCalc, .mudPlacement]
    private let analysisViews: [ViewSelection] = [.pressureWindow, .pumpSchedule, .cementJob, .swabbing, .surgeSwab]
    private let simulationViews: [ViewSelection] = [.tripSimulation, .tripInSimulation, .mpdTracking]
    private let directionalViews: [ViewSelection] = [.directionalPlanning]
    private let operationsViews: [ViewSelection] = [.rentals, .transfers, .equipmentRegistry]
    private let lookAheadViews: [ViewSelection] = [.lookAheadScheduler, .vendors, .jobCodes]

    // Business sections
    private let incomeViews: [ViewSelection] = [.workDays, .invoices, .clients]
    private let expenseViews: [ViewSelection] = [.expenses, .mileage]
    private let payrollViews: [ViewSelection] = [.payroll, .employees]
    private let dividendViews: [ViewSelection] = [.dividends, .shareholders]
    private let reportViews: [ViewSelection] = [.companyStatement, .expenseReport, .payrollReport]

    @State private var showingDataSettings = false

    var body: some View {
        List {
            // Dashboards
            Section("Dashboards") {
                ForEach(dashboardViews, id: \.self) { view in
                    sidebarRow(for: view)
                }
            }

            // Well Geometry
            Section("Well Geometry") {
                ForEach(geometryViews, id: \.self) { view in
                    sidebarRow(for: view)
                }
            }

            // Fluids
            Section("Fluids") {
                ForEach(fluidViews, id: \.self) { view in
                    sidebarRow(for: view)
                }
            }

            // Analysis
            Section("Analysis") {
                ForEach(analysisViews, id: \.self) { view in
                    sidebarRow(for: view)
                }
            }

            // Simulation
            Section("Simulation") {
                ForEach(simulationViews, id: \.self) { view in
                    sidebarRow(for: view)
                }
            }

            // Directional
            Section("Directional") {
                ForEach(directionalViews, id: \.self) { view in
                    sidebarRow(for: view)
                }
            }

            // Operations
            Section("Operations") {
                ForEach(operationsViews, id: \.self) { view in
                    sidebarRow(for: view)
                }
            }

            // Look Ahead
            Section("Look Ahead") {
                ForEach(lookAheadViews, id: \.self) { view in
                    sidebarRow(for: view)
                }
            }

            // Business - Income
            Section("Income") {
                ForEach(incomeViews, id: \.self) { view in
                    sidebarRow(for: view)
                }
            }

            // Business - Expenses
            Section("Expenses") {
                ForEach(expenseViews, id: \.self) { view in
                    sidebarRow(for: view)
                }
            }

            // Business - Payroll
            Section("Payroll") {
                ForEach(payrollViews, id: \.self) { view in
                    sidebarRow(for: view)
                }
            }

            // Business - Dividends
            Section("Dividends") {
                ForEach(dividendViews, id: \.self) { view in
                    sidebarRow(for: view)
                }
            }

            // Business - Reports
            Section("Reports") {
                ForEach(reportViews, id: \.self) { view in
                    sidebarRow(for: view)
                }
            }

            // Settings
            Section("Settings") {
                Button {
                    showingDataSettings = true
                } label: {
                    Label("Data & Sync", systemImage: "arrow.clockwise.icloud")
                }
            }
        }
        .navigationTitle("Features")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.sidebar)
        .sheet(isPresented: $showingDataSettings) {
            NavigationStack {
                DataSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                showingDataSettings = false
                            }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func sidebarRow(for view: ViewSelection) -> some View {
        Button {
            selectedView = view
        } label: {
            HStack {
                Label(view.title, systemImage: view.icon)
                Spacer()
                if selectedView == view {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .font(.caption)
                }
            }
        }
        .listRowBackground(selectedView == view ? Color.accentColor.opacity(0.15) : Color.clear)
    }
}

// MARK: - iPad Detail View

struct iPadDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Well.updatedAt, order: .reverse) private var wells: [Well]

    let selectedView: ViewSelection
    let selectedProject: ProjectState?
    let selectedWell: Well?
    let selectedPad: Pad?
    let pads: [Pad]
    @Binding var selectedWellBinding: Well?
    @Binding var selectedProjectBinding: ProjectState?
    @Binding var selectedPadBinding: Pad?
    @Binding var selectedViewBinding: ViewSelection
    @Binding var showRenameWell: Bool
    @Binding var showRenameProject: Bool

    private var quickNoteManager: QuickNoteManager { QuickNoteManager.shared }

    var body: some View {
        NavigationStack {
            Group {
                if let project = selectedProject {
                    detailContent(for: project)
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
            // Pad picker
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    padMenuContent
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "map")
                        Text(selectedPad?.name ?? "Select Pad")
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                }
            }

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
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
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
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                    }
                    .disabled(selectedWell == nil)
                }
            }

            // Quick add button
            ToolbarItem(placement: .topBarTrailing) {
                QuickAddButton(manager: quickNoteManager)
            }
        }
        }
    }

    @ViewBuilder
    private func detailContent(for project: ProjectState) -> some View {
        switch selectedView {
        case .handover:
            WellsDashboardView()
                case .padDashboard:
                    if let pad = selectedPad {
                        PadDashboardView(pad: pad, onSelectWell: { well in
                            selectedWellBinding = well
                            selectedViewBinding = .wellDashboard
                        })
                    } else if let pad = selectedWell?.pad {
                        PadDashboardView(pad: pad, onSelectWell: { well in
                            selectedWellBinding = well
                            selectedViewBinding = .wellDashboard
                        })
                    } else {
                        ContentUnavailableView("No Pad Selected", systemImage: "map", description: Text("Select a pad or assign a pad to the current well"))
                    }
                case .wellDashboard:
                    if let well = selectedWell {
                        WellDashboardView(well: well, onSelectProject: { project in
                            selectedProjectBinding = project
                            selectedViewBinding = .dashboard
                        })
                    } else {
                        ContentUnavailableView("No Well Selected", systemImage: "building.2", description: Text("Select a well to view its dashboard"))
                    }
                case .dashboard:
                    ProjectDashboardView(project: project)
                case .drillString:
                    DrillStringListView(project: project)
                case .annulus:
                    AnnulusListView(project: project)
                case .volumeSummary:
                    VolumeSummaryViewIOS(project: project)
                case .surveys:
                    SurveysPadView(project: project)
                case .mudCheck:
                    MudCheckView(project: project)
                case .mixingCalc:
                    MixingCalculatorView(project: project)
                case .pressureWindow:
                    PressureWindowView(project: project)
                case .mudPlacement:
                    iPadMudPlacementView(project: project)
                case .pumpSchedule:
                    PumpScheduleViewIOS(project: project)
                case .cementJob:
                    CementJobView(project: project)
                case .swabbing:
                    SwabbingView(project: project)
                case .surgeSwab:
                    SurgeSwabView(project: project)
                case .tripSimulation:
                    TripSimulationViewIOS(project: project)
                case .tripInSimulation:
                    TripInSimulationViewIOS(project: project)
                case .mpdTracking:
                    MPDTrackingView(project: project)
                case .directionalPlanning:
                    DirectionalDashboardView(project: project)
                case .lookAheadScheduler:
                    LookAheadListView()
                case .vendors:
                    VendorListView()
                case .jobCodes:
                    JobCodeListView()
                case .rentals:
                    if let well = selectedWell {
                        RentalItemsView(well: well)
                    } else {
                        ContentUnavailableView("No Well Selected", systemImage: "bag.fill", description: Text("Select a well to view rentals"))
                    }
                case .transfers:
                    AllMaterialTransfersViewIOS()
                case .equipmentRegistry:
                    RentalEquipmentListViewIOS()
                case .shiftCalendar:
                    ShiftCalendarViewIOS()
                case .workDays:
                    WorkTrackingContainerViewIOS()

                // Business - Income
                case .invoices:
                    InvoiceListView()
                case .clients:
                    ClientListView()

                // Business - Expenses
                case .expenses:
                    ExpenseListViewIOS()
                case .mileage:
                    MileageLogViewIOS()

                // Business - Payroll
                case .payroll:
                    PayrollListViewIOS()
                case .employees:
                    EmployeeListView()

                // Business - Dividends
                case .dividends:
                    DividendListViewIOS()
                case .shareholders:
                    ShareholderListView()

                // Business - Reports
                case .companyStatement:
                    CompanyStatementView()
                case .expenseReport:
                    ExpenseReportView()
                case .payrollReport:
                    PayrollReportView()
        }
    }

    @ViewBuilder
    private var padMenuContent: some View {
        ForEach(pads) { pad in
            Button(action: {
                selectedPadBinding = pad
            }) {
                Label(pad.name, systemImage: selectedPad?.id == pad.id ? "checkmark" : "map")
            }
        }
        Divider()
        Button(action: { createNewPad() }) {
            Label("New Pad", systemImage: "plus")
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

    private func createNewPad() {
        let pad = Pad(name: "New Pad")
        modelContext.insert(pad)
        try? modelContext.save()
        selectedPadBinding = pad
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

