//
//  SuperSimulationViewIOS.swift
//  Josh Well Control for Mac
//
//  iOS/iPadOS optimized view for Super Simulation
//  Supports iPhone (tabbed) and iPad (split view) layouts
//

import SwiftUI
import SwiftData

#if os(iOS)
import UIKit

/// Cache to persist SuperSimViewModel across view switches
enum SuperSimViewModelCacheIOS {
    @MainActor
    private static var cache: [UUID: SuperSimViewModel] = [:]

    @MainActor
    static func get(for projectID: UUID) -> SuperSimViewModel {
        if let existing = cache[projectID] {
            return existing
        }
        let newVM = SuperSimViewModel()
        cache[projectID] = newVM
        return newVM
    }
}

struct SuperSimulationViewIOS: View {
    @Bindable var project: ProjectState
    @State private var viewModel: SuperSimViewModel
    @State private var selectedTab = 0
    @State private var showAddOperation = false
    @State private var showSavePreset = false
    @State private var showLoadPreset = false
    @State private var presetName: String = ""
    @State private var showExportOptions = false
    
    @Environment(\.horizontalSizeClass) var sizeClass
    @Environment(\.verticalSizeClass) var vSizeClass
    
    init(project: ProjectState) {
        self.project = project
        _viewModel = State(initialValue: SuperSimViewModelCacheIOS.get(for: project.id))
    }
    
    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .phone {
                // iPhone: Tab-based navigation
                phoneLayout
            } else {
                // iPad: Adaptive layout based on orientation
                if sizeClass == .regular && vSizeClass == .regular {
                    iPadLandscapeLayout
                } else {
                    iPadPortraitLayout
                }
            }
        }
        .loadingOverlay(
            isShowing: viewModel.isRunning,
            message: viewModel.progressMessage,
            progress: viewModel.operationProgress > 0 ? viewModel.operationProgress : nil
        )
        .navigationTitle("Super Simulation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("Run All", systemImage: "play.fill") {
                        viewModel.runAll(project: project)
                    }
                    .disabled(viewModel.operations.isEmpty || viewModel.isRunning)
                    
                    Divider()
                    
                    Button("Save Preset", systemImage: "square.and.arrow.down") {
                        showSavePreset = true
                    }
                    .disabled(viewModel.operations.isEmpty)
                    
                    Button("Load Preset", systemImage: "square.and.arrow.up") {
                        viewModel.loadPresetList()
                        showLoadPreset = true
                    }
                    
                    Divider()
                    
                    Button("Export Report", systemImage: "doc.richtext") {
                        showExportOptions = true
                    }
                    .disabled(viewModel.totalGlobalSteps == 0)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showAddOperation) {
            addOperationSheet
        }
        .sheet(isPresented: $showSavePreset) {
            savePresetSheet
        }
        .sheet(isPresented: $showLoadPreset) {
            loadPresetSheet
        }
        .confirmationDialog("Export Report", isPresented: $showExportOptions) {
            Button("Export HTML") {
                viewModel.exportHTMLReport(project: project)
            }
            Button("Export Zipped HTML") {
                viewModel.exportZippedHTMLReport(project: project)
            }
        }
        .onAppear {
            if viewModel.initialState == nil {
                viewModel.bootstrap(from: project)
            }
        }
    }
    
    // MARK: - iPhone Layout (Tabbed)
    
    private var phoneLayout: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Operations Timeline
            operationsListView
                .tabItem {
                    Label("Operations", systemImage: "list.bullet")
                }
                .tag(0)
            
            // Tab 2: Detail/Config
            operationDetailView
                .tabItem {
                    Label("Detail", systemImage: "slider.horizontal.3")
                }
                .tag(1)
            
            // Tab 3: Wellbore Visualization
            wellboreVisualizationView
                .tabItem {
                    Label("Wellbore", systemImage: "cylinder.split.1x2")
                }
                .tag(2)
            
            // Tab 4: Timeline Chart
            if viewModel.totalGlobalSteps > 0 {
                SuperSimTimelineChartIOS(viewModel: viewModel)
                    .tabItem {
                        Label("Chart", systemImage: "chart.xyaxis.line")
                    }
                    .tag(3)
            }
        }
        .safeAreaPadding(.bottom, 49)
    }
    
    // MARK: - iPad Portrait Layout (Stacked)
    
    private var iPadPortraitLayout: some View {
        VStack(spacing: 0) {
            // Segmented control for view switching
            Picker("View", selection: $selectedTab) {
                Text("Operations").tag(0)
                Text("Detail").tag(1)
                Text("Wellbore").tag(2)
                if viewModel.totalGlobalSteps > 0 {
                    Text("Chart").tag(3)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content area
            Group {
                switch selectedTab {
                case 0:
                    operationsListView
                case 1:
                    operationDetailView
                case 2:
                    wellboreVisualizationView
                case 3:
                    SuperSimTimelineChartIOS(viewModel: viewModel)
                default:
                    operationsListView
                }
            }
        }
    }
    
    // MARK: - iPad Landscape Layout (Split View)
    
    private var iPadLandscapeLayout: some View {
        HStack(spacing: 0) {
            // Left: Operations timeline (narrow sidebar)
            operationsListView
                .frame(width: 320)
            
            Divider()
            
            // Center: Detail or Chart with tab selector
            VStack(spacing: 0) {
                // Tab selector for center panel
                if viewModel.selectedOperationIndex != nil || viewModel.totalGlobalSteps > 0 {
                    Picker("View", selection: $selectedTab) {
                        if viewModel.selectedOperationIndex != nil {
                            Text("Detail").tag(1)
                        }
                        if viewModel.totalGlobalSteps > 0 {
                            Text("Chart").tag(3)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    Divider()
                }
                
                Group {
                    if selectedTab == 3 && viewModel.totalGlobalSteps > 0 {
                        SuperSimTimelineChartIOS(viewModel: viewModel)
                            .padding()
                    } else if let idx = viewModel.selectedOperationIndex,
                              idx >= 0, idx < viewModel.operations.count {
                        OperationDetailViewIOSWithCollapsibleSections(
                            operation: $viewModel.operations[idx],
                            viewModel: viewModel,
                            project: project
                        )
                    } else {
                        emptyStateView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            Divider()
            
            // Right: Wellbore visualization
            if viewModel.totalGlobalSteps > 0 {
                SuperSimWellboreView(viewModel: viewModel)
                    .frame(width: 280)
            }
        }
    }
    
    // MARK: - Operations List View
    
    private var operationsListView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Operations")
                    .font(.headline)
                Spacer()
                Button {
                    showAddOperation = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .imageScale(.large)
                }
            }
            .padding()
            
            Divider()
            
            if viewModel.operations.isEmpty {
                emptyOperationsView
            } else {
                List(selection: $viewModel.selectedOperationIndex) {
                    ForEach(Array(viewModel.operations.enumerated()), id: \.element.id) { index, op in
                        OperationRowViewIOS(
                            operation: op,
                            index: index,
                            operationProgress: viewModel.currentRunningIndex == index ? viewModel.operationProgress : 0
                        )
                        .tag(index)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                viewModel.removeOperation(at: index)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                viewModel.runFrom(operationIndex: index, project: project)
                            } label: {
                                Label("Run From Here", systemImage: "play.fill")
                            }
                            .tint(.blue)
                            .disabled(viewModel.isRunning)
                        }
                    }
                    .onMove { source, destination in
                        if let first = source.first {
                            viewModel.moveOperation(from: first, to: destination)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .onChange(of: viewModel.selectedOperationIndex) {
                    if let idx = viewModel.selectedOperationIndex {
                        viewModel.selectOperation(idx)
                    }
                }
            }
            
            // Run controls
            if !viewModel.operations.isEmpty {
                VStack(spacing: 8) {
                    if viewModel.isRunning {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: viewModel.operationProgress)
                                .tint(.blue)
                            Text(viewModel.progressMessage)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                        .padding(.horizontal)
                    }
                    
                    Button {
                        viewModel.runAll(project: project)
                    } label: {
                        Label("Run All Operations", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.operations.isEmpty || viewModel.isRunning)
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                .background(Color(uiColor: .systemGroupedBackground))
            }
        }
    }
    
    // MARK: - Empty States
    
    private var emptyOperationsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "timeline.selection")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            Text("No Operations")
                .font(.title2.bold())
            
            Text("Add trip and circulation operations to build a simulation timeline.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                showAddOperation = true
            } label: {
                Label("Add Operation", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            Text("Super Simulation")
                .font(.title2.bold())
            
            Text("Select an operation from the timeline, or add new operations to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
    
    // MARK: - Operation Detail View
    
    private var operationDetailView: some View {
        Group {
            if let idx = viewModel.selectedOperationIndex,
               idx >= 0, idx < viewModel.operations.count {
                ScrollView {
                    OperationDetailViewIOS(
                        operation: $viewModel.operations[idx],
                        viewModel: viewModel,
                        project: project
                    )
                }
                #if os(iOS)
                .scrollDismissesKeyboard(.interactively)
                #endif
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Select an operation")
                        .font(.headline)
                    Text("Choose an operation from the list to view and edit its configuration.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Wellbore Visualization
    
    private var wellboreVisualizationView: some View {
        Group {
            if viewModel.totalGlobalSteps > 0 {
                SuperSimWellboreView(viewModel: viewModel)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "cylinder.split.1x2")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No Results Yet")
                        .font(.headline)
                    Text("Run the simulation to see wellbore visualization.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Sheets
    
    private var addOperationSheet: some View {
        NavigationView {
            List {
                ForEach(OperationType.allCases, id: \.self) { type in
                    Button {
                        viewModel.addOperation(type)
                        showAddOperation = false
                    } label: {
                        HStack {
                            Image(systemName: type.icon)
                                .frame(width: 30)
                            Text(type.rawValue)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Add Operation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showAddOperation = false
                    }
                }
            }
        }
    }
    
    private var savePresetSheet: some View {
        NavigationView {
            Form {
                Section("Preset Name") {
                    TextField("Enter name", text: $presetName)
                }
            }
            .navigationTitle("Save Preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showSavePreset = false
                        presetName = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if !presetName.isEmpty {
                            viewModel.savePreset(name: presetName, muds: project.muds ?? [])
                            presetName = ""
                            showSavePreset = false
                        }
                    }
                    .disabled(presetName.isEmpty)
                }
            }
        }
    }
    
    private var loadPresetSheet: some View {
        NavigationView {
            List {
                if viewModel.savedPresets.isEmpty {
                    Text("No saved presets")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.savedPresets) { preset in
                        Button {
                            viewModel.loadPreset(preset, muds: project.muds ?? [])
                            showLoadPreset = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(preset.name)
                                        .font(.headline)
                                    Text("\(preset.operationConfigs.count) operations")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                viewModel.deletePreset(preset)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Load Preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showLoadPreset = false
                    }
                }
            }
        }
    }
}

// MARK: - Operation Row (iOS)

struct OperationRowViewIOS: View {
    let operation: SuperSimOperation
    let index: Int
    var operationProgress: Double = 0

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            statusIcon
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(index + 1).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(operation.type.rawValue)
                        .font(.subheadline.weight(.medium))
                    if case .running = operation.status, operationProgress > 0 {
                        Text("\(Int(operationProgress * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.blue)
                    }
                }
                Text(operation.depthLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch operation.status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .running:
            if operationProgress > 0 {
                ZStack {
                    Circle()
                        .stroke(.secondary.opacity(0.3), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: operationProgress)
                        .stroke(.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 20, height: 20)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Operation Detail View (iOS)

struct OperationDetailViewIOS: View {
    @Binding var operation: SuperSimOperation
    @Bindable var viewModel: SuperSimViewModel
    var project: ProjectState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: operation.type.icon)
                        .font(.title2)
                    Text(operation.type.rawValue)
                        .font(.title2.bold())
                    Spacer()
                    statusBadge
                }
                
                Text(operation.depthLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(12)
            
            // Config
            OperationConfigView(operation: $operation, project: project)
            
            // Results
            if operation.status == .complete {
                Divider()
                OperationResultView(
                    operation: operation,
                    viewModel: viewModel
                )
            }
            
            // State summary
            if let output = operation.outputState {
                Divider()
                stateSummaryView(output)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch operation.status {
        case .pending:
            Text("Pending")
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.secondary.opacity(0.2))
                .clipShape(Capsule())
        case .running:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(viewModel.progressMessage.isEmpty ? "Running" : viewModel.progressMessage)
                    .font(.caption.bold())
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.blue.opacity(0.2))
            .clipShape(Capsule())
        case .complete:
            Text("Complete")
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.green.opacity(0.2))
                .clipShape(Capsule())
        case .error(let msg):
            Text("Error")
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.red.opacity(0.2))
                .clipShape(Capsule())
        }
    }

    private func stateSummaryView(_ state: WellboreStateSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Output State")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Bit MD:")
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.1f", state.bitMD_m)) m")
                        .font(.body.monospacedDigit())
                }
                GridRow {
                    Text("Bit TVD:")
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.1f", state.bitTVD_m)) m")
                        .font(.body.monospacedDigit())
                }
                GridRow {
                    Text("ESD:")
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.1f", state.ESDAtControl_kgpm3)) kg/m³")
                        .font(.body.monospacedDigit())
                }
                GridRow {
                    Text("SABP:")
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.0f", state.SABP_kPa)) kPa")
                        .font(.body.monospacedDigit())
                }
            }
            .font(.subheadline)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - iPad Detail View with Collapsible Sections

struct OperationDetailViewIOSWithCollapsibleSections: View {
    @Binding var operation: SuperSimOperation
    @Bindable var viewModel: SuperSimViewModel
    var project: ProjectState
    
    @State private var configExpanded: Bool = true
    @State private var resultsExpanded: Bool = true
    @State private var stateExpanded: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Compact header
                HStack {
                    Image(systemName: operation.type.icon)
                    Text(operation.type.rawValue)
                        .font(.headline)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(operation.depthLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    statusBadge
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(8)
                
                // Collapsible Config
                DisclosureGroup(isExpanded: $configExpanded) {
                    OperationConfigView(operation: $operation, project: project)
                        .padding(.top, 8)
                } label: {
                    Label("Configuration", systemImage: "slider.horizontal.3")
                        .font(.subheadline.bold())
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(8)
                
                // Collapsible Results
                if operation.status == .complete {
                    DisclosureGroup(isExpanded: $resultsExpanded) {
                        OperationResultView(
                            operation: operation,
                            viewModel: viewModel
                        )
                        .padding(.top, 8)
                    } label: {
                        Label("Results", systemImage: "tablecells")
                            .font(.subheadline.bold())
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(8)
                }
                
                // Collapsible State Summary
                if let output = operation.outputState {
                    DisclosureGroup(isExpanded: $stateExpanded) {
                        stateSummaryGrid(output)
                            .padding(.top, 8)
                    } label: {
                        Label("Output State", systemImage: "info.circle")
                            .font(.subheadline.bold())
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(8)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch operation.status {
        case .pending:
            Text("Pending")
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.secondary.opacity(0.2))
                .clipShape(Capsule())
        case .running:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Running")
                    .font(.caption.bold())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.blue.opacity(0.2))
            .clipShape(Capsule())
        case .complete:
            Text("Complete")
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.green.opacity(0.2))
                .clipShape(Capsule())
        case .error:
            Text("Error")
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.red.opacity(0.2))
                .clipShape(Capsule())
        }
    }
    
    private func stateSummaryGrid(_ state: WellboreStateSnapshot) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                Text("Bit MD:")
                    .foregroundStyle(.secondary)
                Text("\(String(format: "%.1f", state.bitMD_m)) m")
                    .font(.body.monospacedDigit())
            }
            GridRow {
                Text("Bit TVD:")
                    .foregroundStyle(.secondary)
                Text("\(String(format: "%.1f", state.bitTVD_m)) m")
                    .font(.body.monospacedDigit())
            }
            GridRow {
                Text("ESD:")
                    .foregroundStyle(.secondary)
                Text("\(String(format: "%.1f", state.ESDAtControl_kgpm3)) kg/m³")
                    .font(.body.monospacedDigit())
            }
            GridRow {
                Text("SABP:")
                    .foregroundStyle(.secondary)
                Text("\(String(format: "%.0f", state.SABP_kPa)) kPa")
                    .font(.body.monospacedDigit())
            }
        }
        .font(.caption)
    }
}

#endif
