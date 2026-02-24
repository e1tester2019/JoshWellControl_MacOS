//
//  TripInSimulationViewIOS.swift
//  Josh Well Control for Mac
//
//  iOS view for trip-in simulation - running pipe into a well.
//

import SwiftUI
import SwiftData

#if os(iOS)
struct TripInSimulationViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState

    @State private var viewModel: TripInSimulationViewModel
    @State private var selectedTab = 0

    init(project: ProjectState) {
        self.project = project
        _viewModel = State(initialValue: TripInViewModelCache.get(for: project.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("View", selection: $selectedTab) {
                Text("Setup").tag(0)
                Text("Results").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            TabView(selection: $selectedTab) {
                // Setup tab
                setupView
                    .tag(0)

                // Results tab
                resultsView
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationTitle("Trip In Simulation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Run Simulation", systemImage: "play.fill") {
                        runSimulation()
                    }
                    .disabled(viewModel.isRunning)

                    Button("Save Inputs", systemImage: "square.and.arrow.down") {
                        viewModel.saveInputs(project: project, context: modelContext)
                    }

                    Button("Clear Results", systemImage: "trash") {
                        viewModel.steps = []
                    }
                    .disabled(viewModel.steps.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            // Check for pending wellbore state handoff from Trip Out
            if let state = OperationHandoffService.shared.pendingTripInState {
                OperationHandoffService.shared.pendingTripInState = nil
                viewModel.importFromWellboreState(state, project: project)
            } else if viewModel.steps.isEmpty && viewModel.endBitMD_m == 0 {
                if !viewModel.loadSavedInputs(project: project) {
                    viewModel.bootstrap(from: project)
                }
            }
        }
    }

    // MARK: - Setup View

    private var setupView: some View {
        Form {
            // Depths section
            Section("Depths") {
                LabeledContent("Start MD") {
                    TextField("m", value: $viewModel.startBitMD_m, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                LabeledContent("End MD") {
                    TextField("m", value: $viewModel.endBitMD_m, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                LabeledContent("Control MD (Shoe)") {
                    TextField("m", value: $viewModel.controlMD_m, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                LabeledContent("Step Size") {
                    TextField("m", value: $viewModel.step_m, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
            }

            // String section
            Section("String Configuration") {
                TextField("String Name", text: $viewModel.stringName)

                LabeledContent("Pipe OD") {
                    TextField("m", value: $viewModel.pipeOD_m, format: .number.precision(.fractionLength(4)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                LabeledContent("Pipe ID") {
                    TextField("m", value: $viewModel.pipeID_m, format: .number.precision(.fractionLength(4)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
            }

            // Floated casing section
            Section {
                Toggle("Floated Casing", isOn: $viewModel.isFloatedCasing)

                if viewModel.isFloatedCasing {
                    LabeledContent("Float Sub MD") {
                        TextField("m", value: $viewModel.floatSubMD_m, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }

                    LabeledContent("Crack Float Pressure") {
                        TextField("kPa", value: $viewModel.crackFloat_kPa, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                }
            } header: {
                Text("Floated Casing")
            }

            // Fluids section
            Section("Fluids") {
                LabeledContent("Base Mud Density") {
                    TextField("kg/m³", value: $viewModel.baseMudDensity_kgpm3, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                LabeledContent("Target ESD") {
                    TextField("kg/m³", value: $viewModel.targetESD_kgpm3, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                Picker("Fill Mud", selection: $viewModel.fillMudID) {
                    Text("None").tag(nil as UUID?)
                    ForEach(project.muds ?? []) { mud in
                        Text("\(mud.name) (\(Int(mud.density_kgm3)) kg/m³)").tag(mud.id as UUID?)
                    }
                }
                .onChange(of: viewModel.fillMudID) { _, _ in
                    viewModel.updateFillMudDensity(from: project.muds ?? [])
                }
            }

            // Run button
            Section {
                Button {
                    runSimulation()
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isRunning {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text("Running...")
                        } else {
                            Image(systemName: "play.fill")
                                .padding(.trailing, 4)
                            Text("Run Simulation")
                        }
                        Spacer()
                    }
                }
                .disabled(viewModel.isRunning)
            }
        }
    }

    // MARK: - Results View

    private var resultsView: some View {
        Group {
            if viewModel.steps.isEmpty {
                ContentUnavailableView {
                    Label("No Results", systemImage: "chart.line.uptrend.xyaxis")
                } description: {
                    Text("Run a simulation to see results here.")
                } actions: {
                    Button("Run Simulation") {
                        runSimulation()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isRunning)
                }
            } else {
                List {
                    // Summary section
                    Section("Summary") {
                        summaryRow("Total Fill Volume", value: String(format: "%.3f m³", viewModel.totalFillVolume_m3))
                        summaryRow("Displacement Returns", value: String(format: "%.3f m³", viewModel.totalDisplacementReturns_m3))
                        summaryRow("Max Choke Pressure", value: String(format: "%.0f kPa", viewModel.maxChokePressure_kPa))
                        summaryRow("Min ESD at Control", value: String(format: "%.0f kg/m³", viewModel.minESDAtControl_kgpm3))

                        if let depthBelow = viewModel.depthBelowTarget_m {
                            summaryRow("Depth Below Target", value: String(format: "%.0f m", depthBelow), highlight: true)
                        }

                        if viewModel.isFloatedCasing {
                            summaryRow("Max Differential", value: String(format: "%.0f kPa", viewModel.maxDifferentialPressure_kPa))
                        }
                    }

                    // Step-by-step results
                    Section("Steps (\(viewModel.steps.count))") {
                        ForEach(viewModel.steps) { step in
                            stepRow(step)
                        }
                    }
                }
            }
        }
    }

    private func summaryRow(_ title: String, value: String, highlight: Bool = false) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(highlight ? .orange : .primary)
                .monospacedDigit()
        }
    }

    private func stepRow(_ step: TripInSimulationViewModel.TripInStep) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with depth
            HStack {
                Text("MD: \(Int(step.bitMD_m))m")
                    .font(.headline)
                Text("TVD: \(Int(step.bitTVD_m))m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if step.isBelowTarget {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            // Metrics grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 4) {
                metricCell("Fill Vol", value: String(format: "%.3f", step.stepFillVolume_m3), unit: "m³")
                metricCell("Cum Fill", value: String(format: "%.3f", step.cumulativeFillVolume_m3), unit: "m³")
                metricCell("ESD@Ctrl", value: String(format: "%.1f", step.ESDAtControl_kgpm3), unit: "kg/m³")
                metricCell("Choke P", value: String(format: "%.0f", step.requiredChokePressure_kPa), unit: "kPa")
            }

            if viewModel.isFloatedCasing {
                HStack {
                    Text("Float: \(step.floatState)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("ΔP: \(Int(step.differentialPressureAtBottom_kPa)) kPa")
                        .font(.caption)
                        .foregroundStyle(step.differentialPressureAtBottom_kPa > viewModel.crackFloat_kPa ? .red : .secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func metricCell(_ label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            HStack(spacing: 2) {
                Text(value)
                    .font(.caption)
                    .monospacedDigit()
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func runSimulation() {
        viewModel.runSimulation(project: project)
        selectedTab = 1 // Switch to results
    }
}
#endif // os(iOS)

#if os(iOS)
#Preview {
    NavigationStack {
        Text("Trip In Simulation iOS Preview")
    }
}
#endif
