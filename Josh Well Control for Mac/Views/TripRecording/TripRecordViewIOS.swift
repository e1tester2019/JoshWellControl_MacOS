//
//  TripRecordViewIOS.swift
//  Josh Well Control for Mac
//
//  iOS view for recording actual trip observations against simulation predictions.
//

import SwiftUI
import SwiftData

#if os(iOS)
struct TripRecordViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState

    @Query private var allSimulations: [TripSimulation]
    @Query private var allRecords: [TripRecord]

    private var savedSimulations: [TripSimulation] {
        allSimulations.filter { $0.project?.id == project.id }.sorted { $0.createdAt > $1.createdAt }
    }

    private var savedRecords: [TripRecord] {
        allRecords.filter { $0.project?.id == project.id }.sorted { $0.createdAt > $1.createdAt }
    }

    @State private var viewModel = TripRecordViewModel()
    @State private var showingSimulationPicker = false
    @State private var selectedSimulation: TripSimulation?
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.tripRecord == nil {
                // No record loaded - show start options
                noRecordView
            } else {
                // Record loaded - show tabs
                Picker("View", selection: $selectedTab) {
                    Text("Steps").tag(0)
                    Text("Summary").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                TabView(selection: $selectedTab) {
                    stepsView
                        .tag(0)

                    summaryView
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .navigationTitle("Trip Recording")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.tripRecord != nil {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if viewModel.tripRecord?.status == .inProgress {
                            Button("Mark Complete", systemImage: "checkmark.circle") {
                                viewModel.markComplete()
                            }
                            Button("Cancel Record", systemImage: "xmark.circle", role: .destructive) {
                                viewModel.markCancelled()
                            }
                        }
                        if viewModel.tripRecord?.status == .completed {
                            Button("Unmark Complete", systemImage: "arrow.uturn.backward") {
                                viewModel.unmarkComplete()
                            }
                        }
                        Divider()
                        Button("Close Record", systemImage: "xmark") {
                            viewModel.clear()
                        }
                        Button("Delete Record", systemImage: "trash", role: .destructive) {
                            viewModel.deleteRecord(context: modelContext)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showingSimulationPicker) {
            simulationPickerSheet
        }
    }

    // MARK: - No Record View

    private var noRecordView: some View {
        VStack(spacing: 20) {
            // Start new record
            ContentUnavailableView {
                Label("No Record Loaded", systemImage: "list.bullet.clipboard")
            } description: {
                Text("Start a new trip record from a saved simulation, or select a saved record below.")
            } actions: {
                Button("Start from Simulation") {
                    showingSimulationPicker = true
                }
                .buttonStyle(.borderedProminent)
            }

            // Saved records list
            if !savedRecords.isEmpty {
                Divider()
                    .padding(.horizontal)

                Text("Saved Records")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                List {
                    ForEach(savedRecords) { record in
                        Button {
                            viewModel.load(record)
                        } label: {
                            HStack {
                                Image(systemName: record.status.icon)
                                    .foregroundStyle(statusColor(record.status))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.name)
                                        .foregroundStyle(.primary)
                                    HStack(spacing: 8) {
                                        Text("\(record.stepsRecorded)/\(record.stepCount) recorded")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(record.createdAt, style: .date)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                modelContext.delete(record)
                                try? modelContext.save()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func statusColor(_ status: TripRecord.RecordStatus) -> Color {
        switch status {
        case .inProgress: return .orange
        case .completed: return .green
        case .cancelled: return .red
        }
    }

    // MARK: - Steps View

    private var stepsView: some View {
        List {
            // Header info
            Section {
                if let record = viewModel.tripRecord {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.name)
                                .font(.headline)
                            HStack(spacing: 4) {
                                Image(systemName: record.status.icon)
                                    .foregroundStyle(statusColor(record.status))
                                Text(record.status.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(record.stepsRecorded)/\(record.stepCount)")
                                .font(.headline)
                                .monospacedDigit()
                            ProgressView(value: viewModel.progressPercent, total: 100)
                                .frame(width: 80)
                        }
                    }
                }
            }

            // Steps
            Section("Steps") {
                ForEach(Array(viewModel.steps.enumerated()), id: \.element.id) { index, step in
                    StepRowIOS(
                        step: step,
                        index: index,
                        isEditing: viewModel.tripRecord?.status == .inProgress,
                        viewModel: viewModel
                    )
                }
            }
        }
    }

    // MARK: - Summary View

    private var summaryView: some View {
        List {
            if let record = viewModel.tripRecord {
                // Status section
                Section("Status") {
                    LabeledContent("Record Name", value: record.name)
                    LabeledContent("Status", value: record.status.label)
                    LabeledContent("Progress", value: "\(record.stepsRecorded)/\(record.stepCount) steps")
                    LabeledContent("Skipped", value: "\(record.stepsSkipped) steps")
                }

                // Variance section
                Section("Variance Analysis") {
                    LabeledContent("Avg SABP Variance") {
                        Text(viewModel.avgSABPVarianceText)
                            .monospacedDigit()
                            .foregroundStyle(varianceColor(record.avgSABPVariance_kPa, threshold: 50))
                    }

                    LabeledContent("Avg Backfill Variance") {
                        Text(viewModel.avgBackfillVarianceText)
                            .monospacedDigit()
                            .foregroundStyle(varianceColor(record.avgBackfillVariance_m3 * 100, threshold: 5))
                    }

                    LabeledContent("Max SABP Variance") {
                        Text(String(format: "%+.0f kPa", record.maxSABPVariance_kPa))
                            .monospacedDigit()
                    }

                    LabeledContent("Max Backfill Variance") {
                        Text(String(format: "%+.3f m³", record.maxBackfillVariance_m3))
                            .monospacedDigit()
                    }
                }

                // Simulation info
                Section("Source Simulation") {
                    LabeledContent("Simulation", value: record.sourceSimulationName)
                    LabeledContent("Start MD", value: "\(Int(record.startBitMD_m))m")
                    LabeledContent("End MD", value: "\(Int(record.endMD_m))m")
                    LabeledContent("Shoe MD", value: "\(Int(record.shoeMD_m))m")
                }

                // Dates
                Section("Dates") {
                    LabeledContent("Created", value: record.createdAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Updated", value: record.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
    }

    private func varianceColor(_ value: Double, threshold: Double) -> Color {
        let absV = abs(value)
        if absV <= threshold / 2 { return .green }
        if absV <= threshold { return .orange }
        return .red
    }

    // MARK: - Simulation Picker Sheet

    private var simulationPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if savedSimulations.isEmpty {
                    ContentUnavailableView {
                        Label("No Saved Simulations", systemImage: "chart.line.uptrend.xyaxis")
                    } description: {
                        Text("Save a trip simulation first, then create a record from it.")
                    }
                } else {
                    List(savedSimulations) { sim in
                        Button {
                            selectedSimulation = sim
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(sim.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    HStack(spacing: 12) {
                                        Text("\(Int(sim.startBitMD_m))m → \(Int(sim.endMD_m))m")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("\(sim.stepCount) steps")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if selectedSimulation?.id == sim.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Simulation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        selectedSimulation = nil
                        showingSimulationPicker = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create Record") {
                        if let sim = selectedSimulation {
                            viewModel.createFromSimulation(sim, project: project, context: modelContext)
                        }
                        selectedSimulation = nil
                        showingSimulationPicker = false
                    }
                    .disabled(selectedSimulation == nil)
                }
            }
        }
    }
}

// MARK: - Step Row

private struct StepRowIOS: View {
    @Bindable var step: TripRecordStep
    let index: Int
    let isEditing: Bool
    let viewModel: TripRecordViewModel

    @State private var showingEditSheet = false

    var body: some View {
        Button {
            if isEditing {
                showingEditSheet = true
            }
        } label: {
            HStack(spacing: 12) {
                // Status icon
                Image(systemName: step.status.icon)
                    .foregroundStyle(statusColor)
                    .frame(width: 24)

                // Depth info
                VStack(alignment: .leading, spacing: 2) {
                    Text("MD: \(Int(step.bitMD_m))m")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("TVD: \(Int(step.bitTVD_m))m")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Values
                if step.hasActualData {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let sabp = step.actualSABP_kPa {
                            HStack(spacing: 4) {
                                Text("SABP:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.0f", sabp))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)
                            }
                        }
                        if let bf = step.actualBackfill_m3 {
                            HStack(spacing: 4) {
                                Text("BF:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.3f", bf))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                } else if step.skipped {
                    Text("Skipped")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("Pending")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isEditing {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
        .disabled(!isEditing)
        .sheet(isPresented: $showingEditSheet) {
            StepEditSheetIOS(step: step, viewModel: viewModel)
        }
    }

    private var statusColor: Color {
        switch step.status {
        case .pending: return .secondary
        case .recorded: return .green
        case .skipped: return .orange
        }
    }
}

// MARK: - Step Edit Sheet

private struct StepEditSheetIOS: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var step: TripRecordStep
    let viewModel: TripRecordViewModel

    @State private var sabpText = ""
    @State private var backfillText = ""
    @State private var dynamicSABPText = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                // Depth info
                Section("Depth") {
                    LabeledContent("Bit MD", value: "\(Int(step.bitMD_m))m")
                    LabeledContent("Bit TVD", value: "\(Int(step.bitTVD_m))m")
                }

                // Simulated values
                Section("Simulated Values") {
                    LabeledContent("SABP", value: String(format: "%.0f kPa", step.simSABP_kPa))
                    LabeledContent("Dynamic SABP", value: String(format: "%.0f kPa", step.simSABP_Dynamic_kPa))
                    LabeledContent("Backfill", value: String(format: "%.3f m³", step.simBackfill_m3))
                }

                // Actual values
                Section("Actual Values") {
                    HStack {
                        Text("SABP (kPa)")
                        Spacer()
                        TextField("--", text: $sabpText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }

                    HStack {
                        Text("Dynamic SABP (kPa)")
                        Spacer()
                        TextField("--", text: $dynamicSABPText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }

                    HStack {
                        Text("Backfill (m³)")
                        Spacer()
                        TextField("--", text: $backfillText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                }

                // Notes
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }

                // Skip option
                if !step.hasActualData {
                    Section {
                        Button("Skip This Step", role: .destructive) {
                            step.markSkipped()
                            viewModel.tripRecord?.updateVarianceSummary()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Record Step \(Int(step.bitMD_m))m")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveValues()
                        dismiss()
                    }
                }
            }
            .onAppear {
                sabpText = step.actualSABP_kPa.map { String(format: "%.0f", $0) } ?? ""
                dynamicSABPText = step.actualSABP_Dynamic_kPa.map { String(format: "%.0f", $0) } ?? ""
                backfillText = step.actualBackfill_m3.map { String(format: "%.3f", $0) } ?? ""
                notes = step.notes
            }
        }
    }

    private func saveValues() {
        step.actualSABP_kPa = Double(sabpText)
        step.actualSABP_Dynamic_kPa = Double(dynamicSABPText)
        step.actualBackfill_m3 = Double(backfillText)
        step.notes = notes
        step.calculateVariance()
        viewModel.tripRecord?.updateVarianceSummary()
    }
}
#endif // os(iOS)

#if os(iOS)
#Preview {
    NavigationStack {
        Text("Trip Record iOS Preview")
    }
}
#endif
