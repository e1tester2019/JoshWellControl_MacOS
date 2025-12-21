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
    @Query(sort: \Pad.name) private var pads: [Pad]

    @State private var selectedWell: Well?
    @State private var selectedProject: ProjectState?
    @State private var selectedPad: Pad?
    @State private var selectedView: ViewSelection = .wellDashboard
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showRenameWell = false
    @State private var showRenameProject = false
    @State private var searchText = ""
    @State private var showCommandPalette = false
    @State private var quickNoteManager = QuickNoteManager.shared
    @State private var isBusinessUnlocked = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar - Feature Navigation
            MacOSSidebarView(
                selectedView: $selectedView,
                selectedProject: selectedProject,
                searchText: $searchText,
                isBusinessUnlocked: isBusinessUnlocked
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 300)
        } detail: {
            // Main Content Area
            MacOSDetailView(
                selectedView: selectedView,
                selectedProject: selectedProject,
                selectedWell: selectedWell,
                selectedPad: selectedPad,
                selectedWellBinding: $selectedWell,
                selectedProjectBinding: $selectedProject,
                selectedViewBinding: $selectedView,
                showRenameWell: $showRenameWell,
                showRenameProject: $showRenameProject,
                isBusinessUnlocked: $isBusinessUnlocked
            )
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            // All selectors in a group
            ToolbarItemGroup(placement: .navigation) {
                MacOSPadPicker(
                    pads: pads,
                    selectedPad: $selectedPad,
                    modelContext: modelContext
                )

                EnhancedWellPicker(
                    wells: wells,
                    selectedWell: $selectedWell,
                    selectedProject: $selectedProject,
                    modelContext: modelContext
                )

                MacOSProjectPicker(
                    selectedWell: selectedWell,
                    selectedProject: $selectedProject,
                    showRenameProject: $showRenameProject,
                    modelContext: modelContext
                )
            }

            // Spacer
            ToolbarItem(placement: .principal) {
                Spacer()
            }

            // Quick Actions
            ToolbarItemGroup(placement: .automatic) {
                QuickAddButton(manager: quickNoteManager)

                Button(action: { showCommandPalette.toggle() }) {
                    Label("Commands", systemImage: "command")
                }
                .help("Command Palette (⌘K)")
                .keyboardShortcut("k", modifiers: .command)
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
        .quickAddSheet(manager: quickNoteManager)
        .onAppear {
            setupInitialSelection()
            setupKeyboardShortcuts()
            // Initialize quick note context
            quickNoteManager.updateContext(well: selectedWell, project: selectedProject)
            quickNoteManager.updateTaskCounts(from: wells)
        }
        .onChange(of: selectedWell) { _, newWell in
            // Mark well as accessed and save state
            if let well = newWell {
                AppStateService.shared.markAccessed(well, context: modelContext)
                // Sync pad selection to the well's pad
                if well.pad != selectedPad {
                    selectedPad = well.pad
                }
            }
            AppStateService.shared.save(well: newWell, project: selectedProject, viewRaw: selectedView.rawValue)
            // Update quick note context
            quickNoteManager.updateContext(well: newWell, project: selectedProject)
        }
        .onChange(of: selectedPad) { _, newPad in
            // Update quick note context with pad
            quickNoteManager.currentPad = newPad
        }
        .onChange(of: selectedProject) { _, newProject in
            AppStateService.shared.save(well: selectedWell, project: newProject, viewRaw: selectedView.rawValue)
            // Update quick note context
            quickNoteManager.updateContext(well: selectedWell, project: newProject)
        }
        .onChange(of: selectedView) { _, newView in
            AppStateService.shared.save(well: selectedWell, project: selectedProject, viewRaw: newView.rawValue)
        }
        .onChange(of: wells) { _, newWells in
            // Update task counts when wells change
            quickNoteManager.updateTaskCounts(from: newWells)
        }
    }

    private func setupInitialSelection() {
        // Restore from saved state, or fall back to first well
        let restored = AppStateService.shared.restore(from: wells)
        if let well = restored.well {
            selectedWell = well
            selectedProject = restored.project
            selectedPad = well.pad ?? pads.first
            // Restore last selected view
            if let view = ViewSelection(rawValue: AppStateService.shared.lastSelectedViewRaw) {
                selectedView = view
            }
        } else if let first = wells.first {
            selectedWell = first
            selectedProject = first.projects?.first
            selectedPad = first.pad ?? pads.first
        } else {
            // No wells, try to select first pad
            selectedPad = pads.first
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
    let isBusinessUnlocked: Bool

    private let geometryViews: [ViewSelection] = [.drillString, .annulus, .volumeSummary, .surveys]
    private let fluidViews: [ViewSelection] = [.mudCheck, .mixingCalc, .mudPlacement]
    private let analysisViews: [ViewSelection] = [.pressureWindow, .pumpSchedule, .cementJob, .swabbing, .tripSimulation, .tripTracker, .mpdTracking]
    private let operationsViews: [ViewSelection] = [.rentals, .transfers]

    // Business sections
    private let incomeViews: [ViewSelection] = [.workDays, .invoices, .clients]
    private let expenseViews: [ViewSelection] = [.expenses, .mileage]
    private let payrollViews: [ViewSelection] = [.payroll, .employees]
    private let dividendViews: [ViewSelection] = [.dividends, .shareholders]
    private let reportViews: [ViewSelection] = [.companyStatement, .expenseReport, .payrollReport]

    var body: some View {
        List(selection: $selectedView) {
            // Dashboards
            Section("Dashboards") {
                NavigationLink(value: ViewSelection.handover) {
                    Label(ViewSelection.handover.title, systemImage: ViewSelection.handover.icon)
                }
                NavigationLink(value: ViewSelection.padDashboard) {
                    Label(ViewSelection.padDashboard.title, systemImage: ViewSelection.padDashboard.icon)
                }
                NavigationLink(value: ViewSelection.wellDashboard) {
                    Label(ViewSelection.wellDashboard.title, systemImage: ViewSelection.wellDashboard.icon)
                }
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

            // Business - Income
            Section("Income") {
                ForEach(incomeViews, id: \.self) { view in
                    businessNavLink(for: view)
                }
            }

            // Business - Expenses
            Section("Expenses") {
                ForEach(expenseViews, id: \.self) { view in
                    businessNavLink(for: view)
                }
            }

            // Business - Payroll
            Section("Payroll") {
                ForEach(payrollViews, id: \.self) { view in
                    businessNavLink(for: view)
                }
            }

            // Business - Dividends
            Section("Dividends") {
                ForEach(dividendViews, id: \.self) { view in
                    businessNavLink(for: view)
                }
            }

            // Business - Reports
            Section("Reports") {
                ForEach(reportViews, id: \.self) { view in
                    businessNavLink(for: view)
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

    @ViewBuilder
    private func businessNavLink(for view: ViewSelection) -> some View {
        NavigationLink(value: view) {
            HStack {
                Label(view.title, systemImage: view.icon)
                if !isBusinessUnlocked {
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
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
    let selectedPad: Pad?
    @Binding var selectedWellBinding: Well?
    @Binding var selectedProjectBinding: ProjectState?
    @Binding var selectedViewBinding: ViewSelection
    @Binding var showRenameWell: Bool
    @Binding var showRenameProject: Bool
    @Binding var isBusinessUnlocked: Bool

    @State private var pinEntry = ""
    @State private var showPinError = false
    @State private var isSettingPin = false
    @State private var newPin = ""
    @State private var confirmPin = ""
    @State private var showingBusinessSettings = false

    var body: some View {
        Group {
            // Check if this is a business view that needs unlock
            if selectedView.requiresBusinessUnlock && !isBusinessUnlocked {
                businessPinView
            } else {
                mainContentView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingBusinessSettings) {
            BusinessInfoSettingsView()
        }
    }

    @ViewBuilder
    private var mainContentView: some View {
        switch selectedView {
        // Views that don't require a project
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
                ContentUnavailableView("No Pad Selected", systemImage: "map", description: Text("Select a pad from the toolbar or assign a pad to the current well"))
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

        // Business views (no project required)
        case .workDays:
            WorkDayListView()
                .toolbar { businessSettingsToolbar }
        case .invoices:
            InvoiceListView()
                .toolbar { businessSettingsToolbar }
        case .clients:
            ClientListView()
                .toolbar { businessSettingsToolbar }
        case .expenses:
            ExpenseListView()
                .toolbar { businessSettingsToolbar }
        case .mileage:
            MileageLogView()
                .toolbar { businessSettingsToolbar }
        case .payroll:
            PayrollListView()
                .toolbar { businessSettingsToolbar }
        case .employees:
            EmployeeListView()
                .toolbar { businessSettingsToolbar }
        case .dividends:
            DividendListView()
                .toolbar { businessSettingsToolbar }
        case .shareholders:
            ShareholderListView()
                .toolbar { businessSettingsToolbar }
        case .companyStatement:
            CompanyStatementView()
                .toolbar { businessSettingsToolbar }
        case .expenseReport:
            ExpenseReportView()
                .toolbar { businessSettingsToolbar }
        case .payrollReport:
            PayrollReportView()
                .toolbar { businessSettingsToolbar }

        // Project-dependent views
        default:
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
                case .cementJob:
                    CementJobView(project: project)
                case .swabbing:
                    SwabbingView(project: project)
                case .tripSimulation:
                    TripSimulationView(project: project)
                case .tripTracker:
                    TripTrackerView(project: project)
                case .mpdTracking:
                    MPDTrackingView(project: project)
                case .rentals:
                    if let well = selectedWell {
                        RentalItemsView(well: well)
                    } else {
                        noWellSelectedView
                    }
                case .transfers:
                    if let well = selectedWell {
                        MaterialTransferListView(well: well)
                    } else {
                        noWellSelectedView
                    }
                default:
                    EmptyView()
                }
            } else {
                noProjectSelectedView
            }
        }
    }

    @ToolbarContentBuilder
    private var businessSettingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showingBusinessSettings = true
            } label: {
                Label("Settings", systemImage: "gear")
            }
        }
    }

    // MARK: - PIN Entry View

    private var businessPinView: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            if isSettingPin || !WorkTrackingAuth.hasPin {
                setPinView
            } else {
                enterPinView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            // Auto-prompt to set PIN if none exists
            if !WorkTrackingAuth.hasPin {
                isSettingPin = true
            }
        }
    }

    private var enterPinView: some View {
        VStack(spacing: 16) {
            Text("Enter PIN")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Access to business features is protected")
                .foregroundStyle(.secondary)
                .font(.callout)

            SecureField("PIN", text: $pinEntry)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit { verifyPin() }

            if showPinError {
                Text("Incorrect PIN")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack(spacing: 12) {
                Button("Unlock") { verifyPin() }
                    .buttonStyle(.borderedProminent)
                    .disabled(pinEntry.isEmpty)

                Button("Reset PIN") {
                    isSettingPin = true
                    pinEntry = ""
                    showPinError = false
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var setPinView: some View {
        VStack(spacing: 16) {
            Text(WorkTrackingAuth.hasPin ? "Reset PIN" : "Set Up PIN")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Protect your business data with a PIN")
                .foregroundStyle(.secondary)
                .font(.callout)

            if WorkTrackingAuth.hasPin {
                SecureField("Current PIN", text: $pinEntry)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }

            SecureField("New PIN", text: $newPin)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)

            SecureField("Confirm PIN", text: $confirmPin)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit { setNewPin() }

            if showPinError {
                Text("PINs don't match or current PIN is incorrect")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack(spacing: 12) {
                Button("Save PIN") { setNewPin() }
                    .buttonStyle(.borderedProminent)
                    .disabled(newPin.isEmpty || confirmPin.isEmpty)

                if WorkTrackingAuth.hasPin {
                    Button("Cancel") {
                        isSettingPin = false
                        newPin = ""
                        confirmPin = ""
                        pinEntry = ""
                        showPinError = false
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func verifyPin() {
        if WorkTrackingAuth.verifyPin(pinEntry) {
            isBusinessUnlocked = true
            showPinError = false
            pinEntry = ""
        } else {
            showPinError = true
            pinEntry = ""
        }
    }

    private func setNewPin() {
        // Verify current PIN if one exists
        if WorkTrackingAuth.hasPin && !WorkTrackingAuth.verifyPin(pinEntry) {
            showPinError = true
            return
        }

        // Verify new PINs match
        if newPin != confirmPin {
            showPinError = true
            return
        }

        WorkTrackingAuth.setPin(newPin)
        isBusinessUnlocked = true
        isSettingPin = false
        showPinError = false
        newPin = ""
        confirmPin = ""
        pinEntry = ""
    }

    private var noProjectSelectedView: some View {
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

    private var noWellSelectedView: some View {
        ContentUnavailableView {
            Label("No Well Selected", systemImage: "building.2.crop.circle.badge.exclamationmark")
        } description: {
            Text("Select a well to view this feature")
        }
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

// MARK: - macOS Pad Picker

struct MacOSPadPicker: View {
    let pads: [Pad]
    @Binding var selectedPad: Pad?
    let modelContext: ModelContext

    @State private var showPopover = false

    var body: some View {
        Button(action: { showPopover.toggle() }) {
            HStack(spacing: 6) {
                Image(systemName: "map")
                    .foregroundStyle(.secondary)
                Text(selectedPad?.name ?? "Select Pad")
                    .fontWeight(.medium)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.5))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                if pads.isEmpty {
                    Text("No pads")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    List {
                        ForEach(pads) { pad in
                            Button(action: {
                                selectedPad = pad
                                showPopover = false
                            }) {
                                HStack {
                                    Text(pad.name)
                                    Spacer()
                                    if selectedPad?.id == pad.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.plain)
                }

                Divider()

                HStack {
                    Button(action: createNewPad) {
                        Label("New Pad", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    if selectedPad != nil {
                        Button(role: .destructive, action: deleteCurrentPad) {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(10)
            }
            .frame(width: 220, height: 250)
        }
        .help("Select Pad")
    }

    private func createNewPad() {
        let pad = Pad(name: "New Pad")
        modelContext.insert(pad)
        try? modelContext.save()
        selectedPad = pad
        showPopover = false
    }

    private func deleteCurrentPad() {
        guard let pad = selectedPad else { return }
        let newSelection = pads.first { $0.id != pad.id }
        modelContext.delete(pad)
        try? modelContext.save()
        selectedPad = newSelection
        showPopover = false
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
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(selectedProject?.name ?? "Select Project")
                    .fontWeight(.medium)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.5))
            .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
        .help("Select Project")
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
    @State private var showingAddExpense = false
    @State private var showingAddMileage = false
    @State private var showingExport = false
    @State private var showingCompanyStatement = false

    enum CommandCategory: String {
        case navigation = "Navigation"
        case create = "Create"
        case export = "Export"
        case well = "Wells"
        case project = "Projects"
    }

    enum CommandPaletteItem: Identifiable {
        case view(ViewSelection)
        case well(Well)
        case project(ProjectState)
        case action(String, String, CommandCategory, () -> Void)

        var id: String {
            switch self {
            case .view(let view): return "view-\(view.rawValue)"
            case .well(let well): return "well-\(well.id)"
            case .project(let project): return "project-\(project.id)"
            case .action(let name, _, _, _): return "action-\(name)"
            }
        }

        var title: String {
            switch self {
            case .view(let view): return view.title
            case .well(let well): return well.name
            case .project(let project): return project.name
            case .action(let name, _, _, _): return name
            }
        }

        var subtitle: String {
            switch self {
            case .view: return "View"
            case .well(let well):
                if well.isFavorite { return "★ Favorite Well" }
                return "Well"
            case .project: return "Project"
            case .action(_, _, let category, _): return category.rawValue
            }
        }

        var icon: String {
            switch self {
            case .view(let view): return view.icon
            case .well(let well):
                if well.isFavorite { return "star.fill" }
                return "building.2"
            case .project: return "folder"
            case .action(_, let icon, _, _): return icon
            }
        }
    }

    private var filteredCommands: [CommandPaletteItem] {
        var commands: [CommandPaletteItem] = []

        // Quick Actions (most useful at top)
        commands.append(.action("Add New Expense", "creditcard.fill", .create, { showingAddExpense = true }))
        commands.append(.action("Log Mileage Trip", "car.fill", .create, { showingAddMileage = true }))
        commands.append(.action("Add Quick Note", "note.text", .create, { QuickNoteManager.shared.showAddNote() }))
        commands.append(.action("Add Task", "checkmark.circle", .create, { QuickNoteManager.shared.showAddTask() }))

        // Create Actions
        commands.append(.action("New Well", "plus.circle", .create, createNewWell))
        commands.append(.action("New Project", "folder.badge.plus", .create, createNewProject))

        // Export Actions
        commands.append(.action("Export for Accountant", "doc.richtext", .export, { showingExport = true }))
        commands.append(.action("Company Statement", "chart.bar.doc.horizontal", .export, { showingCompanyStatement = true }))

        // Views
        commands.append(contentsOf: ViewSelection.allCases.map { .view($0) })

        // Favorite Wells first
        let favoriteWells = wells.filter { $0.isFavorite }
        let regularWells = wells.filter { !$0.isFavorite }
        commands.append(contentsOf: favoriteWells.map { .well($0) })
        commands.append(contentsOf: regularWells.map { .well($0) })

        // Projects
        if let well = selectedWell {
            commands.append(contentsOf: (well.projects ?? []).map { .project($0) })
        }

        // Well Management
        if let well = selectedWell {
            let favAction = well.isFavorite ? "Remove from Favorites" : "Add to Favorites"
            let favIcon = well.isFavorite ? "star.slash" : "star"
            commands.append(.action(favAction, favIcon, .well, { toggleFavorite(well) }))

            let archiveAction = well.isArchived ? "Unarchive Well" : "Archive Well"
            let archiveIcon = well.isArchived ? "tray.and.arrow.up" : "archivebox"
            commands.append(.action(archiveAction, archiveIcon, .well, { toggleArchive(well) }))
        }

        // Filter by search
        if searchText.isEmpty {
            return commands
        } else {
            return commands.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.subtitle.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private func toggleFavorite(_ well: Well) {
        well.isFavorite.toggle()
        try? modelContext.save()
    }

    private func toggleArchive(_ well: Well) {
        well.isArchived.toggle()
        try? modelContext.save()
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
        .sheet(isPresented: $showingAddExpense) {
            ExpenseEditorView(expense: nil)
        }
        .sheet(isPresented: $showingAddMileage) {
            MileageLogEditorView(log: nil)
        }
        .sheet(isPresented: $showingCompanyStatement) {
            CompanyStatementView()
        }
    }

    private func executeCommand(_ command: CommandPaletteItem) {
        switch command {
        case .view(let view):
            selectedView = view
            isPresented = false
        case .well(let well):
            selectedWell = well
            selectedProject = well.projects?.first
            isPresented = false
        case .project(let project):
            selectedProject = project
            isPresented = false
        case .action(_, _, _, let action):
            isPresented = false
            // Delay action to allow sheet to dismiss first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                action()
            }
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

