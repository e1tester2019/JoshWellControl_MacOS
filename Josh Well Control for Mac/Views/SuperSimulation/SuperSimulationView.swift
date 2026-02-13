//
//  SuperSimulationView.swift
//  Josh Well Control for Mac
//
//  Main view for the Super Simulation.
//  Timeline sidebar with operation list + detail area.
//

import SwiftUI
import SwiftData

struct SuperSimulationView: View {
    @Bindable var project: ProjectState
    @State private var viewModel = SuperSimViewModel()
    @State private var showAddOperation = false
    @State private var showSavePreset = false
    @State private var showLoadPreset = false
    @State private var presetName: String = ""

    var body: some View {
        HSplitView {
            // MARK: - Timeline Sidebar
            VStack(spacing: 0) {
                HStack {
                    Text("Operations")
                        .font(.headline)
                    Spacer()
                    Button {
                        showAddOperation = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showAddOperation) {
                        addOperationPopover
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                if viewModel.operations.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "timeline.selection")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No Operations")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Add trip and circulation operations to build a simulation timeline.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxHeight: .infinity)
                } else {
                    List(selection: $viewModel.selectedOperationIndex) {
                        ForEach(Array(viewModel.operations.enumerated()), id: \.element.id) { index, op in
                            OperationRowView(
                                operation: op,
                                index: index,
                                operationProgress: viewModel.currentRunningIndex == index ? viewModel.operationProgress : 0
                            )
                                .tag(index)
                                .contextMenu {
                                    Button("Delete") {
                                        viewModel.removeOperation(at: index)
                                    }
                                    Divider()
                                    Button("Run From Here") {
                                        viewModel.runFrom(operationIndex: index, project: project)
                                    }
                                    .disabled(viewModel.isRunning)
                                }
                        }
                        .onMove { source, destination in
                            if let first = source.first {
                                viewModel.moveOperation(from: first, to: destination)
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .onChange(of: viewModel.selectedOperationIndex) {
                        if let idx = viewModel.selectedOperationIndex {
                            viewModel.selectOperation(idx)
                        }
                    }
                }

                Divider()

                // Run + preset controls
                VStack(spacing: 4) {
                    if viewModel.isRunning {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: viewModel.operationProgress)
                                .tint(viewModel.operationProgress > 0 ? .blue : .secondary)
                            Text(viewModel.progressMessage)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    HStack {
                        Button {
                            viewModel.runAll(project: project)
                        } label: {
                            Label("Run All", systemImage: "play.fill")
                        }
                        .disabled(viewModel.operations.isEmpty || viewModel.isRunning)

                        Spacer()

                        // Save preset
                        Button {
                            showSavePreset = true
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(viewModel.operations.isEmpty)
                        .help("Save operations as preset")
                        .popover(isPresented: $showSavePreset) {
                            savePresetPopover
                        }

                        // Load preset
                        Button {
                            viewModel.loadPresetList()
                            showLoadPreset = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderless)
                        .help("Load saved preset")
                        .popover(isPresented: $showLoadPreset) {
                            loadPresetPopover
                        }

                        // Export HTML report
                        Button {
                            viewModel.exportHTMLReport(project: project)
                        } label: {
                            Image(systemName: "doc.richtext")
                        }
                        .buttonStyle(.borderless)
                        .disabled(viewModel.totalGlobalSteps == 0)
                        .help("Export HTML report")
                    }
                }
                .padding(8)
            }
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

            // MARK: - Detail + Wellbore Area
            if viewModel.totalGlobalSteps > 0 {
                HSplitView {
                    // Left: detail content or chart
                    if let idx = viewModel.selectedOperationIndex,
                       idx >= 0, idx < viewModel.operations.count {
                        OperationDetailView(
                            operation: $viewModel.operations[idx],
                            viewModel: viewModel,
                            project: project
                        )
                    } else {
                        SuperSimTimelineChart(viewModel: viewModel)
                            .padding()
                    }

                    // Right: wellbore (full height)
                    SuperSimWellboreView(viewModel: viewModel)
                        .frame(minWidth: 180, idealWidth: 280, maxWidth: 400)
                }
            } else if let idx = viewModel.selectedOperationIndex,
                      idx >= 0, idx < viewModel.operations.count {
                OperationDetailView(
                    operation: $viewModel.operations[idx],
                    viewModel: viewModel,
                    project: project
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "bolt.circle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.blue.opacity(0.5))
                    Text("Super Simulation")
                        .font(.title2)
                    Text("Select an operation from the timeline, or add new operations to get started.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if viewModel.initialState == nil {
                viewModel.bootstrap(from: project)
            }
        }
    }

    // MARK: - Add Operation Popover

    private var addOperationPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Operation")
                .font(.headline)
                .padding(.bottom, 4)

            ForEach(OperationType.allCases, id: \.self) { type in
                Button {
                    viewModel.addOperation(type)
                    showAddOperation = false
                } label: {
                    Label(type.rawValue, systemImage: type.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding()
        .frame(width: 200)
    }

    // MARK: - Save Preset Popover

    private var savePresetPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Save Preset")
                .font(.headline)
            TextField("Preset Name", text: $presetName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            HStack {
                Spacer()
                Button("Cancel") { showSavePreset = false }
                Button("Save") {
                    if !presetName.isEmpty {
                        viewModel.savePreset(name: presetName, muds: project.muds ?? [])
                        presetName = ""
                        showSavePreset = false
                    }
                }
                .disabled(presetName.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    // MARK: - Load Preset Popover

    private var loadPresetPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Load Preset")
                .font(.headline)

            if viewModel.savedPresets.isEmpty {
                Text("No saved presets")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(viewModel.savedPresets) { preset in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(preset.name)
                                .font(.subheadline)
                            Text("\(preset.operationConfigs.count) operations")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Load") {
                            viewModel.loadPreset(preset, muds: project.muds ?? [])
                            showLoadPreset = false
                        }
                        .buttonStyle(.borderless)
                        Button {
                            viewModel.deletePreset(preset)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 250)
    }
}

// MARK: - Operation Row

struct OperationRowView: View {
    let operation: SuperSimOperation
    let index: Int
    var operationProgress: Double = 0

    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            statusIcon

            VStack(alignment: .leading, spacing: 2) {
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
        .padding(.vertical, 2)
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
                .frame(width: 16, height: 16)
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

// MARK: - Operation Detail

struct OperationDetailView: View {
    @Binding var operation: SuperSimOperation
    @Bindable var viewModel: SuperSimViewModel
    var project: ProjectState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: operation.type.icon)
                        .font(.title2)
                    Text(operation.type.rawValue)
                        .font(.title2.bold())
                    Spacer()
                    statusBadge
                }
                .padding(.horizontal)

                Divider()

                // Config
                OperationConfigView(operation: $operation, project: project)
                    .padding(.horizontal)

                // Results
                if operation.status == .complete {
                    Divider()
                    OperationResultView(
                        operation: operation,
                        viewModel: viewModel
                    )
                    .padding(.horizontal)
                }

                // State summary
                if let output = operation.outputState {
                    Divider()
                    stateSummary(output)
                        .padding(.horizontal)
                }

                // Timeline chart (wellbore is full-height on the right side)
                if viewModel.totalGlobalSteps > 0 {
                    Divider()
                    SuperSimTimelineChart(viewModel: viewModel)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch operation.status {
        case .pending:
            Text("Pending")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.2))
                .clipShape(Capsule())
        case .running:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text(viewModel.progressMessage.isEmpty ? "Running" : viewModel.progressMessage)
                    .font(.caption)
                    .lineLimit(1)
            }
        case .complete:
            Text("Complete")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.green.opacity(0.2))
                .clipShape(Capsule())
        case .error(let msg):
            Text("Error: \(msg)")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.red.opacity(0.2))
                .clipShape(Capsule())
        }
    }

    private func stateSummary(_ state: WellboreStateSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output State")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Bit MD:")
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.1f", state.bitMD_m)) m")
                }
                GridRow {
                    Text("Bit TVD:")
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.1f", state.bitTVD_m)) m")
                }
                GridRow {
                    Text("ESD:")
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.1f", state.ESDAtControl_kgpm3)) kg/m\u{00B3}")
                }
                GridRow {
                    Text("SABP:")
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.0f", state.SABP_kPa)) kPa")
                }
                GridRow {
                    Text("Pocket Layers:")
                        .foregroundStyle(.secondary)
                    Text("\(state.layersPocket.count)")
                }
                GridRow {
                    Text("Annulus Layers:")
                        .foregroundStyle(.secondary)
                    Text("\(state.layersAnnulus.count)")
                }
            }
            .font(.subheadline)
        }
    }
}
