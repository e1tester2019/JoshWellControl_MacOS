//
//  TripInSimulationView.swift
//  Josh Well Control for Mac
//
//  View for trip-in simulation - running pipe into a well.
//  Supports floated casing and tracks ESD/choke pressure requirements.
//

import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

// MARK: - ViewModel Cache

/// Cache to persist TripInSimulationViewModel across view switches
enum TripInViewModelCache {
    @MainActor
    private static var cache: [UUID: TripInSimulationViewModel] = [:]

    @MainActor
    static func get(for projectID: UUID) -> TripInSimulationViewModel {
        if let existing = cache[projectID] {
            return existing
        }
        let newVM = TripInSimulationViewModel()
        cache[projectID] = newVM
        return newVM
    }
}

struct TripInSimulationView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState

    @Query private var allTripSimulations: [TripSimulation]
    @Query private var allTripInSimulations: [TripInSimulation]
    @Query private var allTripTracks: [TripTrack]

    private var savedTripOutSimulations: [TripSimulation] {
        allTripSimulations.filter { $0.project?.id == project.id }.sorted { $0.createdAt > $1.createdAt }
    }

    private var savedTripTracks: [TripTrack] {
        allTripTracks.filter { $0.project?.id == project.id }.sorted { $0.createdAt > $1.createdAt }
    }

    private var savedTripInSimulations: [TripInSimulation] {
        allTripInSimulations.filter { $0.project?.id == project.id }.sorted { $0.createdAt > $1.createdAt }
    }

    // Bind to cached ViewModel - initialized from cache
    @State private var viewModel: TripInSimulationViewModel

    @State private var showingSourcePicker = false
    @State private var showingSaveDialog = false
    @State private var saveError: String?
    @State private var showDetails = false

    // Rename dialog state
    @State private var showingRenameDialog = false
    @State private var simulationToRename: TripInSimulation?
    @State private var renameText = ""

    init(project: ProjectState) {
        self.project = project
        // Initialize viewModel from cache
        _viewModel = State(initialValue: TripInViewModelCache.get(for: project.id))
    }

    // TVD sampler for depth conversions
    private var tvdSampler: TvdSampler {
        TvdSampler(stations: project.surveys ?? [])
    }

    // Selected fill mud (for color in visualization)
    private var selectedFillMud: MudProperties? {
        guard let mudID = viewModel.fillMudID else { return nil }
        return (project.muds ?? []).first { $0.id == mudID }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerToolbar
            Divider()
            content
        }
        .padding(12)
        .onAppear {
            // Only bootstrap if viewModel is fresh (no loaded simulation and no steps)
            if viewModel.currentSimulation == nil && viewModel.steps.isEmpty {
                viewModel.bootstrap(from: project)
            }
        }
        .sheet(isPresented: $showingSourcePicker) {
            sourceSimulationPicker
        }
        .alert("Save Error", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "Unknown error")
        }
    }

    // MARK: - Header

    private var headerToolbar: some View {
        HStack(spacing: 16) {
            // Title
            Text("Trip-In Simulation")
                .font(.headline)

            Divider().frame(height: 24)

            // Source simulation picker
            Button {
                showingSourcePicker = true
            } label: {
                HStack {
                    Image(systemName: "arrow.up.doc")
                    Text(viewModel.sourceType == .none ? "Import Pocket State" : viewModel.sourceDisplayName)
                }
            }

            Spacer()

            // Depth slider (when results exist)
            if !viewModel.steps.isEmpty {
                depthSlider
            }

            Divider().frame(height: 24)

            // Details toggle
            if !viewModel.steps.isEmpty {
                Toggle("Details", isOn: $showDetails)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            Divider().frame(height: 24)

            // Actions
            Button("Run Simulation", systemImage: "play.fill") {
                viewModel.runSimulation(project: project)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isRunning)

            if !viewModel.steps.isEmpty {
                Button("Save", systemImage: "square.and.arrow.down") {
                    _ = viewModel.saveSimulation(to: project, context: modelContext)
                }

                Button("Export", systemImage: "doc.richtext") {
                    exportHTMLReport()
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func exportHTMLReport() {
        let wellName = project.well?.name ?? "Unknown Well"
        let projectName = project.name

        // Get fill mud name and color
        let fillMudName: String
        var fillMudColorR: Double? = nil
        var fillMudColorG: Double? = nil
        var fillMudColorB: Double? = nil
        if let mudID = viewModel.fillMudID,
           let mud = (project.muds ?? []).first(where: { $0.id == mudID }) {
            fillMudName = mud.name
            fillMudColorR = mud.colorR
            fillMudColorG = mud.colorG
            fillMudColorB = mud.colorB
        } else {
            fillMudName = "Fill Mud"
        }

        // Build annulus sections for report
        let annulusSections = (project.annulus ?? []).map { section in
            let length = section.bottomDepth_m - section.topDepth_m
            return PDFSectionData(
                name: section.name ?? "Section",
                topMD: section.topDepth_m,
                bottomMD: section.bottomDepth_m,
                length: length,
                innerDiameter: section.innerDiameter_m,
                outerDiameter: viewModel.pipeOD_m,
                capacity_m3_per_m: section.flowArea_m2,
                displacement_m3_per_m: 0,
                totalVolume: section.flowArea_m2 * length
            )
        }

        let reportData = TripInSimulationReportData(
            wellName: wellName,
            projectName: projectName,
            generatedDate: Date(),
            startMD: viewModel.startBitMD_m,
            endMD: viewModel.endBitMD_m,
            controlMD: viewModel.controlMD_m,
            stepSize: viewModel.step_m,
            targetESD: viewModel.targetESD_kgpm3,
            stringName: viewModel.stringName,
            pipeOD_m: viewModel.pipeOD_m,
            pipeID_m: viewModel.pipeID_m,
            isFloatedCasing: viewModel.isFloatedCasing,
            floatSubMD: viewModel.floatSubMD_m,
            crackFloat: viewModel.crackFloat_kPa,
            fillMudName: fillMudName,
            fillMudDensity: viewModel.activeMudDensity_kgpm3,
            baseMudDensity: viewModel.baseMudDensity_kgpm3,
            fillMudColorR: fillMudColorR,
            fillMudColorG: fillMudColorG,
            fillMudColorB: fillMudColorB,
            sourceName: viewModel.sourceSimulationName.isEmpty ? "Manual" : viewModel.sourceSimulationName,
            annulusSections: annulusSections,
            steps: viewModel.steps
        )

        let html = TripInSimulationHTMLGenerator.shared.generateHTML(for: reportData)

        // Create filename
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStr = dateFormatter.string(from: Date())
        let sanitizedWellName = wellName.replacingOccurrences(of: "/", with: "-")
        let filename = "TripInSimulation_\(sanitizedWellName)_\(dateStr).html"

        // Save via NSSavePanel
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = [.html]
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try html.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Failed to save HTML: \(error)")
            }
        }
    }

    private var depthSlider: some View {
        HStack(spacing: 8) {
            Text("Depth:")
                .foregroundStyle(.secondary)
                .font(.caption)

            if let step = viewModel.selectedStep {
                Text("\(Int(step.bitMD_m))m")
                    .monospacedDigit()
                    .frame(width: 50, alignment: .trailing)
            }

            Slider(
                value: $viewModel.stepSlider,
                in: 0...Double(max(viewModel.steps.count - 1, 0)),
                step: 1
            )
            .frame(width: 150)
            .onChange(of: viewModel.stepSlider) { _, _ in
                viewModel.updateFromSlider()
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        HSplitView {
            // Left: Input parameters + saved simulations
            VStack(spacing: 0) {
                ScrollView {
                    inputParametersPanel
                }

                Divider()

                savedSimulationsList
                    .frame(maxHeight: 160)
            }
            .frame(width: 280)

            // Center: Results table + summary (with optional details)
            VStack(spacing: 8) {
                if !viewModel.steps.isEmpty {
                    summaryCards

                    if showDetails {
                        resultsTable
                            .frame(maxHeight: .infinity)

                        ScrollView {
                            detailAccordion
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        resultsTable
                            .frame(maxHeight: .infinity)
                    }
                } else {
                    ContentUnavailableView(
                        "No Simulation Results",
                        systemImage: "arrow.down.circle",
                        description: Text("Configure parameters and run the simulation")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Right: Visualization
            if !viewModel.steps.isEmpty {
                VStack(alignment: .center, spacing: 4) {
                    visualization
                        .frame(maxHeight: .infinity)

                    if let step = viewModel.selectedStep {
                        Text(String(format: "ESD @ Control: %.1f kg/m³", step.ESDAtControl_kgpm3))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .padding(.top, 4)
                    }
                }
                .frame(minWidth: 220, maxWidth: 300)
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Input Parameters

    private var inputParametersPanel: some View {
        Form {
            Section("String Configuration") {
                TextField("Name", text: $viewModel.stringName)

                LabeledContent("Pipe OD") {
                    HStack {
                        TextField("", value: $viewModel.pipeOD_m, format: .number.precision(.fractionLength(4)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("m")
                        Text("(\(String(format: "%.2f", viewModel.pipeOD_m * 39.37))\")")
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Pipe ID") {
                    HStack {
                        TextField("", value: $viewModel.pipeID_m, format: .number.precision(.fractionLength(4)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("m")
                    }
                }
            }

            Section("Depths") {
                LabeledContent("Start MD") {
                    HStack {
                        TextField("", value: $viewModel.startBitMD_m, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("m")
                    }
                }

                LabeledContent("End MD (TD)") {
                    HStack {
                        TextField("", value: $viewModel.endBitMD_m, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("m")
                    }
                }

                LabeledContent("Control MD") {
                    HStack {
                        TextField("", value: $viewModel.controlMD_m, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("m")
                    }
                }

                LabeledContent("Step Size") {
                    HStack {
                        TextField("", value: $viewModel.step_m, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("m")
                    }
                }
            }

            Section("Floated Casing") {
                Toggle("Floated Casing", isOn: $viewModel.isFloatedCasing)

                if viewModel.isFloatedCasing {
                    LabeledContent("Float Sub MD") {
                        HStack {
                            TextField("", value: $viewModel.floatSubMD_m, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            Text("m")
                        }
                    }

                    LabeledContent("Crack Float") {
                        HStack {
                            TextField("", value: $viewModel.crackFloat_kPa, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            Text("kPa")
                        }
                    }
                }
            }

            Section("Fill-Up Fluid") {
                Picker("Mud", selection: $viewModel.fillMudID) {
                    Text("Select Mud...").tag(nil as UUID?)
                    ForEach(project.muds ?? []) { mud in
                        HStack {
                            Circle()
                                .fill(Color(red: mud.colorR, green: mud.colorG, blue: mud.colorB))
                                .frame(width: 10, height: 10)
                            Text("\(mud.name) - \(String(format: "%.0f", mud.density_kgm3)) kg/m³")
                        }
                        .tag(mud.id as UUID?)
                    }
                }
                .onChange(of: viewModel.fillMudID) { _, _ in
                    viewModel.updateFillMudDensity(from: project.muds ?? [])
                }

                if viewModel.fillMudID != nil {
                    LabeledContent("Density") {
                        Text("\(String(format: "%.0f", viewModel.activeMudDensity_kgpm3)) kg/m³")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Control") {
                LabeledContent("Target ESD") {
                    HStack {
                        TextField("", value: $viewModel.targetESD_kgpm3, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("kg/m³")
                    }
                }
            }

            Section("Initial Annulus State") {
                if viewModel.importedPocketLayers.isEmpty {
                    Text("No pocket layers imported")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("Import from Trip Simulation or Trip Tracker")
                        .foregroundStyle(.tertiary)
                        .font(.caption2)
                } else {
                    // Only show first 5 layers to avoid rendering thousands of views
                    let previewLayers = Array(viewModel.importedPocketLayers.prefix(5))
                    ForEach(Array(previewLayers.enumerated()), id: \.offset) { _, layer in
                        HStack {
                            Circle()
                                .fill(layer.rho_kgpm3 < viewModel.targetESD_kgpm3 ? Color.orange : Color.blue)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(String(format: "%.0f", layer.topMD)) - \(String(format: "%.0f", layer.bottomMD))m")
                                    .font(.caption)
                                Text("\(String(format: "%.0f", layer.rho_kgpm3)) kg/m³")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(String(format: "%.1f", layer.bottomMD - layer.topMD))m")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if viewModel.importedPocketLayers.count > 5 {
                        Text("+ \(viewModel.importedPocketLayers.count - 5) more layers...")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Divider()

                    LabeledContent("Total Layers") {
                        Text("\(viewModel.importedPocketLayers.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard(
                title: "Total Fill",
                value: String(format: "%.2f", viewModel.totalFillVolume_m3),
                unit: "m³",
                color: .blue
            )

            summaryCard(
                title: "Displacement Returns",
                value: String(format: "%.2f", viewModel.totalDisplacementReturns_m3),
                unit: "m³",
                color: .green
            )

            summaryCard(
                title: "Min ESD @ Control",
                value: String(format: "%.0f", viewModel.minESDAtControl_kgpm3),
                unit: "kg/m³",
                color: viewModel.minESDAtControl_kgpm3 < viewModel.targetESD_kgpm3 ? .red : .green
            )

            if viewModel.maxChokePressure_kPa > 0 {
                summaryCard(
                    title: "Max Choke Required",
                    value: String(format: "%.0f", viewModel.maxChokePressure_kPa),
                    unit: "kPa",
                    color: .orange
                )
            }

            if viewModel.isFloatedCasing {
                // Calculate max true ΔP at float (Ann + Choke - Str)
                let maxTrueDeltaP = viewModel.steps.map { step in
                    (step.annulusPressureAtBit_kPa + step.requiredChokePressure_kPa) - step.stringPressureAtBit_kPa
                }.max() ?? 0
                if maxTrueDeltaP > 0 {
                    summaryCard(
                        title: "Max ΔP @ Float",
                        value: String(format: "%.0f", maxTrueDeltaP),
                        unit: "kPa",
                        color: .purple
                    )
                }
            }

            if let depthBelow = viewModel.depthBelowTarget_m {
                summaryCard(
                    title: "Below Target From",
                    value: String(format: "%.0f", depthBelow),
                    unit: "m",
                    color: .red,
                    icon: "exclamationmark.triangle.fill"
                )
            }
        }
        .padding(.horizontal, 8)
    }

    private func summaryCard(title: String, value: String, unit: String, color: Color, icon: String? = nil) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(color)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Results Table

    private var tableSelection: Binding<TripInSimulationViewModel.TripInStep.ID?> {
        Binding(
            get: { viewModel.steps.indices.contains(viewModel.selectedIndex) ? viewModel.steps[viewModel.selectedIndex].id : nil },
            set: { newID in
                if let id = newID, let idx = viewModel.steps.firstIndex(where: { $0.id == id }) {
                    viewModel.selectedIndex = idx
                    viewModel.syncSliderToSelection()
                }
            }
        )
    }

    private var resultsTable: some View {
        Table(viewModel.steps, selection: tableSelection) {
            mdColumn
            tvdColumn
            esdColumn
            chokeColumn
            esdPlusChokeColumn
            hpAnnColumn
            annPlusChokeColumn
            hpStrColumn
            deltaPColumn
        }
        .tableStyle(.bordered)
    }

    private var mdColumn: some TableColumnContent<TripInSimulationViewModel.TripInStep, Never> {
        TableColumn("MD") { (step: TripInSimulationViewModel.TripInStep) in
            Text(String(format: "%.0f", step.bitMD_m)).monospacedDigit()
        }
        .width(50)
    }

    private var tvdColumn: some TableColumnContent<TripInSimulationViewModel.TripInStep, Never> {
        TableColumn("TVD") { (step: TripInSimulationViewModel.TripInStep) in
            Text(String(format: "%.0f", step.bitTVD_m)).monospacedDigit()
        }
        .width(50)
    }

    private var esdColumn: some TableColumnContent<TripInSimulationViewModel.TripInStep, Never> {
        TableColumn("ESD") { (step: TripInSimulationViewModel.TripInStep) in
            Text(String(format: "%.0f", step.ESDAtControl_kgpm3))
                .monospacedDigit()
                .foregroundColor(step.isBelowTarget ? .red : nil)
        }
        .width(55)
    }

    private var chokeColumn: some TableColumnContent<TripInSimulationViewModel.TripInStep, Never> {
        TableColumn("Choke") { (step: TripInSimulationViewModel.TripInStep) in
            Text(step.requiredChokePressure_kPa > 0 ? String(format: "%.0f", step.requiredChokePressure_kPa) : "-")
                .monospacedDigit()
                .foregroundColor(step.requiredChokePressure_kPa > 0 ? .orange : .secondary)
        }
        .width(55)
    }

    private var esdPlusChokeColumn: some TableColumnContent<TripInSimulationViewModel.TripInStep, Never> {
        TableColumn("ESD+C") { (step: TripInSimulationViewModel.TripInStep) in
            let controlTVD = tvdSampler.tvd(of: viewModel.controlMD_m)
            let chokeContrib = controlTVD > 0 ? step.requiredChokePressure_kPa / (0.00981 * controlTVD) : 0
            let effective = step.ESDAtControl_kgpm3 + chokeContrib
            Text(String(format: "%.0f", effective))
                .monospacedDigit()
                .foregroundColor(.green)
        }
        .width(55)
    }

    private var hpAnnColumn: some TableColumnContent<TripInSimulationViewModel.TripInStep, Never> {
        TableColumn("HP Ann@Bit") { (step: TripInSimulationViewModel.TripInStep) in
            Text(String(format: "%.0f", step.annulusPressureAtBit_kPa))
                .monospacedDigit()
                .foregroundColor(.blue)
        }
        .width(75)
    }

    private var annPlusChokeColumn: some TableColumnContent<TripInSimulationViewModel.TripInStep, Never> {
        TableColumn("Ann+Choke") { (step: TripInSimulationViewModel.TripInStep) in
            let effective = step.annulusPressureAtBit_kPa + step.requiredChokePressure_kPa
            Text(String(format: "%.0f", effective))
                .monospacedDigit()
                .foregroundColor(.red)
        }
        .width(75)
    }

    private var hpStrColumn: some TableColumnContent<TripInSimulationViewModel.TripInStep, Never> {
        TableColumn("HP Str@Bit") { (step: TripInSimulationViewModel.TripInStep) in
            Text(String(format: "%.0f", step.stringPressureAtBit_kPa))
                .monospacedDigit()
                .foregroundColor(.cyan)
        }
        .width(70)
    }

    private var deltaPColumn: some TableColumnContent<TripInSimulationViewModel.TripInStep, Never> {
        TableColumn("ΔP@Float") { (step: TripInSimulationViewModel.TripInStep) in
            // True ΔP at float = (Ann HP + Choke) - String HP
            let trueDeltaP = (step.annulusPressureAtBit_kPa + step.requiredChokePressure_kPa) - step.stringPressureAtBit_kPa
            Text(String(format: "%.0f", trueDeltaP))
                .monospacedDigit()
                .foregroundColor(trueDeltaP >= 0 ? nil : .red)
        }
        .width(65)
    }

    // MARK: - Saved Simulations List

    private var savedSimulationsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Saved Simulations")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            List(savedTripInSimulations, selection: Binding(
                get: { viewModel.currentSimulation?.id },
                set: { newID in
                    if let id = newID, let sim = savedTripInSimulations.first(where: { $0.id == id }) {
                        viewModel.loadSimulation(sim)
                    }
                }
            )) { simulation in
                VStack(alignment: .leading, spacing: 2) {
                    Text(simulation.name)
                        .font(.caption)
                    Text(simulation.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .tag(simulation.id)
                .contextMenu {
                    Button("Rename...", systemImage: "pencil") {
                        simulationToRename = simulation
                        renameText = simulation.name
                        showingRenameDialog = true
                    }
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        deleteSimulation(simulation)
                    }
                }
            }
            .listStyle(.plain)
        }
        .alert("Rename Simulation", isPresented: $showingRenameDialog) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {
                simulationToRename = nil
            }
            Button("Rename") {
                if let sim = simulationToRename {
                    sim.name = renameText
                    sim.updatedAt = .now
                    try? modelContext.save()
                }
                simulationToRename = nil
            }
        } message: {
            Text("Enter a new name for this simulation")
        }
    }

    private func deleteSimulation(_ simulation: TripInSimulation) {
        // If this is the currently loaded simulation, clear the view
        if viewModel.currentSimulation?.id == simulation.id {
            viewModel.currentSimulation = nil
            viewModel.steps = []
        }
        modelContext.delete(simulation)
        try? modelContext.save()
    }

    // MARK: - Source Picker

    @State private var sourcePickerTab: SourcePickerTab = .simulation

    private enum SourcePickerTab {
        case simulation
        case tracker
    }

    private var sourceSimulationPicker: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                Picker("Source Type", selection: $sourcePickerTab) {
                    Text("Trip Simulations").tag(SourcePickerTab.simulation)
                    Text("Trip Trackers").tag(SourcePickerTab.tracker)
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                // Content based on selected tab
                Group {
                    switch sourcePickerTab {
                    case .simulation:
                        simulationsList
                    case .tracker:
                        trackersList
                    }
                }
            }
            .navigationTitle("Import Pocket State")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingSourcePicker = false
                    }
                }
            }
        }
        .frame(width: 450, height: 550)
    }

    private var simulationsList: some View {
        Group {
            if savedTripOutSimulations.isEmpty {
                ContentUnavailableView(
                    "No Trip Simulations",
                    systemImage: "arrow.up.circle",
                    description: Text("Run a trip simulation first to import pocket state")
                )
            } else {
                List(savedTripOutSimulations) { simulation in
                    Button {
                        importSimulation(simulation)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(simulation.name)
                                .font(.headline)
                            HStack {
                                Text("TD: \(String(format: "%.0f", simulation.startBitMD_m))m")
                                Text("•")
                                Text("Shoe: \(String(format: "%.0f", simulation.shoeMD_m))m")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            Text(simulation.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func importSimulation(_ simulation: TripSimulation) {
        print("🖱️ Button pressed")
        let t = CFAbsoluteTimeGetCurrent()

        viewModel.importFromTripSimulation(simulation, project: project, context: modelContext)
        print("⏱️ After import: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - t))s")

        showingSourcePicker = false
        print("⏱️ After dismiss: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - t))s")
    }

    private var trackersList: some View {
        Group {
            if savedTripTracks.isEmpty {
                ContentUnavailableView(
                    "No Trip Trackers",
                    systemImage: "list.bullet.clipboard",
                    description: Text("Start a trip tracker session first to import pocket state")
                )
            } else {
                List(savedTripTracks) { tripTrack in
                    Button {
                        viewModel.importFromTripTracker(tripTrack, project: project)
                        showingSourcePicker = false
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tripTrack.name)
                                .font(.headline)
                            HStack {
                                Text("Current: \(String(format: "%.0f", tripTrack.currentBitMD_m))m")
                                Text("•")
                                Text("TD: \(String(format: "%.0f", tripTrack.tdMD_m))m")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            let pocketCount = tripTrack.layersPocket.count
                            if pocketCount > 0 {
                                Text("\(pocketCount) pocket layer(s)")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }

                            HStack {
                                Text("\(tripTrack.stepCount) steps recorded")
                                Text("•")
                                Text(tripTrack.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            }
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Visualization

    private var visualization: some View {
        GroupBox("Well Snapshot") {
            Canvas { ctx, size in
                guard let step = viewModel.selectedStep else { return }

                let pocketLayers = step.layersPocket

                // Determine depth range (TD)
                let globalMaxMD = max(viewModel.endBitMD_m, viewModel.controlMD_m, pocketLayers.map { $0.bottomMD }.max() ?? 0)
                guard globalMaxMD > 0 else { return }

                let bitMD = step.bitMD_m
                let margin: CGFloat = 24

                // Mapping function: MD -> Y coordinate
                func yGlobal(_ md: Double) -> CGFloat {
                    let usable = size.height - 2 * margin
                    return margin + CGFloat(md / globalMaxMD) * usable
                }

                // Wellbore (annulus) - centered with margins for depth labels
                let leftMargin: CGFloat = 35
                let rightMargin: CGFloat = 35
                let wellboreRect = CGRect(x: leftMargin, y: margin, width: size.width - leftMargin - rightMargin, height: size.height - 2 * margin)

                // Draw wellbore background
                ctx.fill(Path(wellboreRect), with: .color(.black.opacity(0.3)))

                // Consolidate adjacent layers with same color to eliminate rendering artifacts
                struct ConsolidatedLayer {
                    var topMD: Double
                    var bottomMD: Double
                    var r: Double, g: Double, b: Double, a: Double
                    var rho: Double
                }

                var consolidatedLayers: [ConsolidatedLayer] = []
                let sortedPocket = pocketLayers.sorted { $0.topMD < $1.topMD }

                for layer in sortedPocket {
                    let r = layer.colorR ?? 0.5
                    let g = layer.colorG ?? 0.5
                    let b = layer.colorB ?? 0.5
                    let a = layer.colorA ?? 1.0

                    // Check if we can merge with previous layer (similar color, contiguous)
                    if let last = consolidatedLayers.last,
                       abs(last.bottomMD - layer.topMD) < 1.0,  // Within 1m = contiguous
                       abs(last.r - r) < 0.01 && abs(last.g - g) < 0.01 && abs(last.b - b) < 0.01 {
                        // Extend the previous layer
                        consolidatedLayers[consolidatedLayers.count - 1].bottomMD = layer.bottomMD
                    } else {
                        consolidatedLayers.append(ConsolidatedLayer(
                            topMD: layer.topMD, bottomMD: layer.bottomMD,
                            r: r, g: g, b: b, a: a, rho: layer.rho_kgpm3
                        ))
                    }
                }

                // Draw consolidated layers
                for layer in consolidatedLayers {
                    let yTop = yGlobal(layer.topMD)
                    let yBot = yGlobal(layer.bottomMD)
                    let yMin = min(yTop, yBot)
                    let h = max(1, abs(yBot - yTop))

                    let col = Color(red: layer.r, green: layer.g, blue: layer.b, opacity: layer.a)
                    let layerRect = CGRect(x: wellboreRect.minX, y: yMin, width: wellboreRect.width, height: h)
                    ctx.fill(Path(layerRect), with: .color(col))
                }

                // Draw wellbore outline
                ctx.stroke(Path(wellboreRect), with: .color(.gray), lineWidth: 1)

                // Drill string overlay - only extends from surface to current bit depth
                let stringWidth = wellboreRect.width * 0.4  // 40% of wellbore width
                let stringX = wellboreRect.midX - stringWidth / 2

                if bitMD > 0 {
                    let yTop = yGlobal(0)
                    let yBot = yGlobal(bitMD)
                    let stringHeight = yBot - yTop

                    // Draw string outer wall (steel color)
                    let stringOuterRect = CGRect(x: stringX, y: yTop, width: stringWidth, height: stringHeight)
                    ctx.fill(Path(stringOuterRect), with: .color(Color(white: 0.35)))

                    // Draw fill mud inside string (slightly inset)
                    let inset: CGFloat = 4
                    let fillMudColor: Color
                    if let mud = selectedFillMud {
                        fillMudColor = Color(red: mud.colorR, green: mud.colorG, blue: mud.colorB, opacity: 0.9)
                    } else {
                        fillMudColor = Color.blue.opacity(0.7)
                    }
                    let fillRect = CGRect(x: stringX + inset, y: yTop, width: stringWidth - 2 * inset, height: stringHeight)
                    ctx.fill(Path(fillRect), with: .color(fillMudColor))

                    // Draw string outline
                    ctx.stroke(Path(stringOuterRect), with: .color(.black), lineWidth: 1.5)

                    // Draw bit indicator at bottom of string
                    let bitRect = CGRect(x: stringX - 2, y: yBot - 4, width: stringWidth + 4, height: 6)
                    ctx.fill(Path(bitRect), with: .color(.red.opacity(0.8)))
                }

                // Control depth marker (shoe)
                let yControl = yGlobal(viewModel.controlMD_m)
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: wellboreRect.minX, y: yControl))
                    p.addLine(to: CGPoint(x: wellboreRect.maxX, y: yControl))
                }, with: .color(.orange), style: StrokeStyle(lineWidth: 1.5, dash: [6, 3]))

                // Depth ticks
                let tickCount = 5
                for i in 0...tickCount {
                    let md = Double(i) / Double(tickCount) * globalMaxMD
                    let tvd = tvdSampler.tvd(of: md)
                    let yy = yGlobal(md)

                    // TVD on left side
                    ctx.draw(
                        Text(String(format: "%.0f", tvd)).font(.system(size: 9)).foregroundColor(.secondary),
                        at: CGPoint(x: wellboreRect.minX - 5, y: yy),
                        anchor: .trailing
                    )

                    // MD on right side
                    ctx.draw(
                        Text(String(format: "%.0f", md)).font(.system(size: 9)).foregroundColor(.secondary),
                        at: CGPoint(x: wellboreRect.maxX + 5, y: yy),
                        anchor: .leading
                    )
                }

                // Headers
                ctx.draw(Text("TVD").font(.system(size: 8)).foregroundColor(.secondary), at: CGPoint(x: wellboreRect.minX - 5, y: margin - 10), anchor: .trailing)
                ctx.draw(Text("MD").font(.system(size: 8)).foregroundColor(.secondary), at: CGPoint(x: wellboreRect.maxX + 5, y: margin - 10), anchor: .leading)
            }
        }
        .frame(minHeight: 280)
    }

    private func fillColor(rho: Double) -> Color {
        // Air (rho ~1.2) gets a distinct light blue color
        if rho < 10 {
            return Color(red: 0.7, green: 0.85, blue: 1.0, opacity: 0.8)
        }
        // Density-based coloring - lighter fluids are more orange, heavier are more blue
        let t = min(max((rho - 800) / 600, 0), 1)
        if t < 0.5 {
            // Light fluid - orange to yellow
            return Color(red: 1.0, green: 0.6 + 0.4 * (t * 2), blue: 0.2, opacity: 0.8)
        } else {
            // Heavy fluid - green to blue
            return Color(red: 0.2, green: 0.6, blue: 0.4 + 0.5 * ((t - 0.5) * 2), opacity: 0.8)
        }
    }

    // MARK: - Detail Accordion

    private var detailAccordion: some View {
        GroupBox("Step Details") {
            if let step = viewModel.selectedStep {
                VStack(alignment: .leading, spacing: 8) {
                    DisclosureGroup("Summary") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            GridRow {
                                Text("Bit MD").foregroundStyle(.secondary)
                                Text(String(format: "%.0f m", step.bitMD_m))
                            }
                            GridRow {
                                Text("Bit TVD").foregroundStyle(.secondary)
                                Text(String(format: "%.0f m", step.bitTVD_m))
                            }
                            GridRow {
                                Text("ESD @ Control").foregroundStyle(.secondary)
                                Text(String(format: "%.1f kg/m³", step.ESDAtControl_kgpm3))
                                    .foregroundStyle(step.isBelowTarget ? .red : .primary)
                            }
                            GridRow {
                                Text("Target ESD").foregroundStyle(.secondary)
                                Text(String(format: "%.0f kg/m³", viewModel.targetESD_kgpm3))
                            }
                            if step.requiredChokePressure_kPa > 0 {
                                GridRow {
                                    Text("Choke Required").foregroundStyle(.secondary)
                                    Text(String(format: "%.0f kPa", step.requiredChokePressure_kPa))
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }

                    DisclosureGroup("Volumes") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            GridRow {
                                Text("Step Fill").foregroundStyle(.secondary)
                                Text(String(format: "%.3f m³", step.stepFillVolume_m3))
                            }
                            GridRow {
                                Text("Cumulative Fill").foregroundStyle(.secondary)
                                Text(String(format: "%.3f m³", step.cumulativeFillVolume_m3))
                            }
                            GridRow {
                                Text("Step Displacement").foregroundStyle(.secondary)
                                Text(String(format: "%.3f m³", step.stepDisplacementReturns_m3))
                            }
                            GridRow {
                                Text("Cumulative Displacement").foregroundStyle(.secondary)
                                Text(String(format: "%.3f m³", step.cumulativeDisplacementReturns_m3))
                            }
                            if viewModel.isFloatedCasing {
                                Divider()
                                GridRow {
                                    Text("Float State").foregroundStyle(.secondary)
                                    Text(step.floatState)
                                        .foregroundStyle(step.floatState.contains("OPEN") ? .orange : .green)
                                }
                                GridRow {
                                    Text("HP Ann @ Bit").foregroundStyle(.secondary)
                                    Text(String(format: "%.0f kPa", step.annulusPressureAtBit_kPa))
                                        .foregroundStyle(.blue)
                                }
                                GridRow {
                                    Text("Ann + Choke").foregroundStyle(.secondary)
                                    let annPlusChoke = step.annulusPressureAtBit_kPa + step.requiredChokePressure_kPa
                                    Text(String(format: "%.0f kPa", annPlusChoke))
                                        .foregroundStyle(.red)
                                }
                                GridRow {
                                    Text("HP Str @ Bit").foregroundStyle(.secondary)
                                    Text(String(format: "%.0f kPa", step.stringPressureAtBit_kPa))
                                        .foregroundStyle(.cyan)
                                }
                                GridRow {
                                    Text("ΔP @ Float").foregroundStyle(.secondary)
                                    let trueDeltaP = (step.annulusPressureAtBit_kPa + step.requiredChokePressure_kPa) - step.stringPressureAtBit_kPa
                                    Text(String(format: "%.0f kPa", trueDeltaP))
                                }
                            }
                        }
                        .padding(.top, 4)
                    }

                    DisclosureGroup("Pocket Layers (\(step.layersPocket.count))") {
                        if step.layersPocket.isEmpty {
                            Text("No pocket layers")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } else {
                            layerTable(step.layersPocket)
                        }
                    }
                }
            } else {
                Text("No step selected")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func layerTable(_ layers: [TripLayerSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header row
            HStack {
                Text("Top MD").frame(width: 60, alignment: .leading).font(.caption2).foregroundStyle(.secondary)
                Text("Bot MD").frame(width: 60, alignment: .leading).font(.caption2).foregroundStyle(.secondary)
                Text("ρ kg/m³").frame(width: 60, alignment: .leading).font(.caption2).foregroundStyle(.secondary)
                Text("ΔP kPa").frame(width: 60, alignment: .leading).font(.caption2).foregroundStyle(.secondary)
            }
            Divider()
            // Data rows
            ForEach(Array(layers.enumerated()), id: \.offset) { _, layer in
                HStack {
                    Text(String(format: "%.1f", layer.topMD)).frame(width: 60, alignment: .leading).font(.caption)
                    Text(String(format: "%.1f", layer.bottomMD)).frame(width: 60, alignment: .leading).font(.caption)
                    Text(String(format: "%.0f", layer.rho_kgpm3)).frame(width: 60, alignment: .leading).font(.caption)
                    Text(String(format: "%.0f", layer.deltaHydroStatic_kPa)).frame(width: 60, alignment: .leading).font(.caption)
                }
            }
        }
        .padding(.top, 4)
    }
}

#Preview {
    Text("TripInSimulationView Preview")
}
