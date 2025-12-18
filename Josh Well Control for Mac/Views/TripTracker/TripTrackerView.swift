//
//  TripTrackerView.swift
//  Josh Well Control for Mac
//
//  Process-based trip tracking view for macOS - manual step-by-step tracking.
//

import SwiftUI
import SwiftData

#if os(macOS)
struct TripTrackerView: View {
    // MARK: - Environment
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState

    // Query saved simulations and tracks
    @Query private var allSimulations: [TripSimulation]
    @Query private var allTracks: [TripTrack]

    private var savedSimulations: [TripSimulation] {
        allSimulations.filter { $0.project?.id == project.id }.sorted { $0.createdAt > $1.createdAt }
    }

    private var savedTracks: [TripTrack] {
        allTracks.filter { $0.project?.id == project.id }.sorted { $0.updatedAt > $1.updatedAt }
    }

    @State private var viewModel = TripTrackerViewModel()
    @State private var showingStartOptions = true
    @State private var showingSimulationPicker = false
    @State private var showingTrackPicker = false
    @State private var selectedSimulation: TripSimulation?
    @State private var selectedSimulationStep: Int = 0
    @State private var showExportMenu = false

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            headerToolbar
            Divider()

            if viewModel.tripTrack == nil {
                startOptionsView
            } else {
                trackingContentView
            }
        }
        .padding(12)
        .sheet(isPresented: $showingSimulationPicker) {
            simulationPickerSheet
        }
        .sheet(isPresented: $showingTrackPicker) {
            trackPickerSheet
        }
    }

    // MARK: - Header Toolbar
    private var headerToolbar: some View {
        HStack(spacing: 12) {
            if viewModel.tripTrack != nil {
                // Active tracking session
                HStack(spacing: 8) {
                    Image(systemName: "figure.walk.circle.fill")
                        .foregroundStyle(.green)
                    Text(viewModel.tripTrack?.name ?? "Trip Tracker")
                        .font(.headline)
                    Text("Step \(viewModel.sortedSteps.count)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .cornerRadius(4)
                }

                Spacer()

                // Session controls
                Button("New Session") {
                    viewModel.tripTrack = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Menu {
                    Button("Export JSON") { exportJSON() }
                    Button("Export HTML Report") { exportHTML() }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.sortedSteps.isEmpty)
            } else {
                Text("Trip Tracker")
                    .font(.headline)
                Spacer()
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Start Options View
    private var startOptionsView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "figure.walk.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Process-Based Trip Tracking")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Track your trip step-by-step with real-time observations")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Button(action: startFresh) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Start Fresh")
                    }
                    .frame(width: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: { showingSimulationPicker = true }) {
                    HStack {
                        Image(systemName: "play.circle")
                        Text("Load from Simulation")
                    }
                    .frame(width: 200)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(savedSimulations.isEmpty)

                Button(action: { showingTrackPicker = true }) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("Resume Previous")
                    }
                    .frame(width: 200)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(savedTracks.isEmpty)
            }

            if !savedSimulations.isEmpty || !savedTracks.isEmpty {
                HStack(spacing: 16) {
                    if !savedSimulations.isEmpty {
                        Label("\(savedSimulations.count) simulations", systemImage: "play.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !savedTracks.isEmpty {
                        Label("\(savedTracks.count) saved tracks", systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Tracking Content View
    private var trackingContentView: some View {
        GeometryReader { geo in
            HStack(spacing: 12) {
                // LEFT: Step History
                stepHistoryPanel
                    .frame(width: 180)

                Divider()

                // CENTER: Input Form + Preview
                VStack(spacing: 12) {
                    inputFormPanel
                    Divider()
                    previewPanel
                }
                .frame(maxWidth: .infinity)

                Divider()

                // RIGHT: Visualization
                visualizationPanel
                    .frame(width: max(220, geo.size.width / 3.5))
            }
        }
    }

    // MARK: - Step History Panel
    private var stepHistoryPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Step History")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !viewModel.sortedSteps.isEmpty {
                    Button(action: { viewModel.undoLastStep(context: modelContext) }) {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .help("Undo last step")
                }
            }

            if viewModel.sortedSteps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.title2)
                        .foregroundStyle(.quaternary)
                    Text("No steps yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.sortedSteps, id: \.id) { step in
                        StepHistoryRow(step: step)
                    }
                }
                .listStyle(.plain)
            }

            // Cumulative summary
            if !viewModel.sortedSteps.isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Total Backfill")
                            Spacer()
                            Text(String(format: "%.3f m³", viewModel.cumulativeBackfill_m3))
                                .monospacedDigit()
                        }
                        HStack {
                            Text("Tank Delta")
                            Spacer()
                            let delta = viewModel.cumulativeTankDelta_m3
                            Text(String(format: "%+.3f m³", delta))
                                .monospacedDigit()
                                .foregroundStyle(delta >= 0 ? .green : .red)
                        }
                        HStack {
                            Text("Trip Progress")
                            Spacer()
                            Text(String(format: "%.0f m", viewModel.tripProgress_m))
                                .monospacedDigit()
                        }
                    }
                    .font(.caption)
                }
            }
        }
    }

    // MARK: - Input Form Panel
    private var inputFormPanel: some View {
        GroupBox("Step Inputs") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Current Bit MD:")
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f m", viewModel.currentBitMD_m))
                        .monospacedDigit()
                        .fontWeight(.medium)
                    Spacer()
                    Text("Target Bit MD:")
                        .foregroundStyle(.secondary)
                    TextField("", value: $viewModel.inputBitMD_m, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("m")
                        .foregroundStyle(.secondary)
                }

                Divider()

                GridRow {
                    Text("Backfill Pumped:")
                        .foregroundStyle(.secondary)
                    TextField("", value: $viewModel.inputBackfill_m3, format: .number.precision(.fractionLength(3)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("m³")
                        .foregroundStyle(.secondary)
                    Text("Backfill Density:")
                        .foregroundStyle(.secondary)
                    TextField("", value: $viewModel.inputBackfillDensity_kgpm3, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("kg/m³")
                        .foregroundStyle(.secondary)
                }

                GridRow {
                    Text("Observed SABP:")
                        .foregroundStyle(.secondary)
                    TextField("", value: $viewModel.inputSABP_kPa, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("kPa")
                        .foregroundStyle(.secondary)
                    Text("Pit Change:")
                        .foregroundStyle(.secondary)
                    TextField("", value: $viewModel.inputPitChange_m3, format: .number.precision(.fractionLength(3)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("m³")
                        .foregroundStyle(.secondary)
                }

                GridRow {
                    Text("Float Override:")
                        .foregroundStyle(.secondary)
                    Picker("", selection: floatOverrideBinding) {
                        Text("Auto").tag(0)
                        Text("Force Closed").tag(1)
                        Text("Force Open").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    Spacer()
                    Spacer()
                    Spacer()
                    Spacer()
                }

                if !viewModel.inputNotes.isEmpty || viewModel.previewCalculated {
                    GridRow {
                        Text("Notes:")
                            .foregroundStyle(.secondary)
                        TextField("Optional notes for this step", text: $viewModel.inputNotes)
                            .textFieldStyle(.roundedBorder)
                        Spacer()
                        Spacer()
                        Spacer()
                        Spacer()
                    }
                }
            }

            HStack {
                Spacer()

                Button("Preview") {
                    viewModel.calculatePreview(project: project)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button("Lock In Step") {
                    if let step = viewModel.lockStep(project: project, context: modelContext) {
                        // Successfully locked step
                        print("Locked step \(step.stepIndex)")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(!viewModel.previewCalculated)
            }
            .padding(.top, 8)
        }
    }

    private var floatOverrideBinding: Binding<Int> {
        Binding(
            get: {
                switch viewModel.inputFloatOverride {
                case nil: return 0
                case .closed: return 1
                case .open: return 2
                }
            },
            set: { newVal in
                switch newVal {
                case 1: viewModel.inputFloatOverride = .closed
                case 2: viewModel.inputFloatOverride = .open
                default: viewModel.inputFloatOverride = nil
                }
            }
        )
    }

    // MARK: - Preview Panel
    private var previewPanel: some View {
        GroupBox("Preview") {
            if viewModel.previewCalculated {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                    GridRow {
                        VStack(alignment: .leading) {
                            Text("Expected Fill (DP Wet)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.3f m³", viewModel.previewExpectedIfClosed_m3))
                                .monospacedDigit()
                        }
                        VStack(alignment: .leading) {
                            Text("Expected Fill (DP Dry)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.3f m³", viewModel.previewExpectedIfOpen_m3))
                                .monospacedDigit()
                        }
                        VStack(alignment: .leading) {
                            Text("Calculated SABP")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.0f kPa", viewModel.previewCalculatedSABP_kPa))
                                .monospacedDigit()
                        }
                        VStack(alignment: .leading) {
                            Text("Float State")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(viewModel.previewFloatState)
                                .foregroundStyle(viewModel.previewFloatState.contains("OPEN") ? .orange : .green)
                        }
                    }

                    Divider()

                    GridRow {
                        VStack(alignment: .leading) {
                            Text("ESD @ TD")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.0f kg/m³", viewModel.previewESDatTD_kgpm3))
                                .monospacedDigit()
                        }
                        VStack(alignment: .leading) {
                            Text("ESD @ Bit")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.0f kg/m³", viewModel.previewESDatBit_kgpm3))
                                .monospacedDigit()
                        }
                        VStack(alignment: .leading) {
                            Text("Backfill Discrepancy")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            let disc = viewModel.previewBackfillDiscrepancy_m3
                            Text(String(format: "%+.3f m³", disc))
                                .monospacedDigit()
                                .foregroundStyle(abs(disc) > 0.01 ? .orange : .primary)
                        }
                        VStack(alignment: .leading) {
                            Text("SABP Discrepancy")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            let disc = viewModel.previewSABPDiscrepancy_kPa
                            Text(String(format: "%+.0f kPa", disc))
                                .monospacedDigit()
                                .foregroundStyle(abs(disc) > 50 ? .orange : .primary)
                        }
                    }

                    // Reference comparison (if from simulation)
                    if let refStep = viewModel.referenceStepAtDepth {
                        Divider()
                        GridRow {
                            VStack(alignment: .leading) {
                                Text("Ref SABP")
                                    .font(.caption)
                                    .foregroundStyle(.blue.opacity(0.7))
                                Text(String(format: "%.0f kPa", refStep.SABP_kPa))
                                    .monospacedDigit()
                                    .foregroundStyle(.blue)
                            }
                            VStack(alignment: .leading) {
                                Text("Ref ESD@TD")
                                    .font(.caption)
                                    .foregroundStyle(.blue.opacity(0.7))
                                Text(String(format: "%.0f kg/m³", refStep.ESDatTD_kgpm3))
                                    .monospacedDigit()
                                    .foregroundStyle(.blue)
                            }
                            VStack(alignment: .leading) {
                                Text("Ref Backfill")
                                    .font(.caption)
                                    .foregroundStyle(.blue.opacity(0.7))
                                Text(String(format: "%.3f m³", refStep.stepBackfill_m3))
                                    .monospacedDigit()
                                    .foregroundStyle(.blue)
                            }
                            VStack(alignment: .leading) {
                                Text("Ref Float")
                                    .font(.caption)
                                    .foregroundStyle(.blue.opacity(0.7))
                                Text(refStep.floatState)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No Preview", systemImage: "eye.slash")
                } description: {
                    Text("Enter step values and click Preview to see calculated results")
                }
                .frame(height: 100)
            }
        }
    }

    // MARK: - Visualization Panel
    private var visualizationPanel: some View {
        GroupBox("Well Snapshot") {
            GeometryReader { geo in
                Canvas { ctx, size in
                    let layers = viewModel.previewCalculated
                        ? viewModel.previewLayersAnnulus
                        : viewModel.currentLayersAnnulus
                    let stringLayers = viewModel.previewCalculated
                        ? viewModel.previewLayersString
                        : viewModel.currentLayersString
                    let pocketLayers = viewModel.previewCalculated
                        ? viewModel.previewLayersPocket
                        : viewModel.currentLayersPocket
                    let bitMD = viewModel.previewCalculated
                        ? viewModel.inputBitMD_m
                        : viewModel.currentBitMD_m

                    // Three-column layout
                    let gap: CGFloat = 8
                    let colW = (size.width - 2*gap) / 3
                    let annLeft = CGRect(x: 0, y: 0, width: colW, height: size.height)
                    let strRect = CGRect(x: colW + gap, y: 0, width: colW, height: size.height)
                    let annRight = CGRect(x: 2*(colW + gap), y: 0, width: colW, height: size.height)

                    // Unified vertical scale
                    let maxPocketMD = pocketLayers.map { $0.bottomMD }.max() ?? bitMD
                    let globalMaxMD = max(bitMD, maxPocketMD, viewModel.tdMD_m)
                    func yGlobal(_ md: Double) -> CGFloat {
                        guard globalMaxMD > 0 else { return 0 }
                        return CGFloat(md / globalMaxMD) * size.height
                    }

                    // Draw columns
                    drawColumn(&ctx, rows: layers, in: annLeft, bitMD: bitMD, yGlobal: yGlobal)
                    drawColumn(&ctx, rows: stringLayers, in: strRect, bitMD: bitMD, yGlobal: yGlobal)
                    drawColumn(&ctx, rows: layers, in: annRight, bitMD: bitMD, yGlobal: yGlobal)

                    // Pocket (below bit) - full width
                    for r in pocketLayers {
                        let yTop = yGlobal(r.topMD)
                        let yBot = yGlobal(r.bottomMD)
                        let col = fillColor(rho: r.rho_kgpm3)
                        let top = floor(min(yTop, yBot))
                        let bottom = ceil(max(yTop, yBot))
                        let sub = CGRect(x: 0, y: top, width: size.width, height: max(1, bottom - top))
                        ctx.fill(Path(sub), with: .color(col))
                    }

                    // Headers
                    ctx.draw(Text("Annulus"), at: CGPoint(x: annLeft.midX, y: 12))
                    ctx.draw(Text("String"), at: CGPoint(x: strRect.midX, y: 12))
                    ctx.draw(Text("Annulus"), at: CGPoint(x: annRight.midX, y: 12))

                    // Bit marker
                    let yBit = yGlobal(bitMD)
                    ctx.fill(Path(CGRect(x: 0, y: yBit - 1, width: size.width, height: 2)),
                             with: .color(.accentColor.opacity(0.9)))

                    // Depth ticks
                    let tickCount = 6
                    for i in 0...tickCount {
                        let md = Double(i) / Double(tickCount) * globalMaxMD
                        let yy = yGlobal(md)
                        ctx.fill(Path(CGRect(x: size.width - 8, y: yy - 0.5, width: 8, height: 1)),
                                 with: .color(.secondary))
                        ctx.draw(Text(String(format: "%.0f", md)),
                                 at: CGPoint(x: size.width - 10, y: yy - 6), anchor: .trailing)
                    }
                }
            }
            .frame(minHeight: 300)
        }
    }

    private func drawColumn(_ ctx: inout GraphicsContext,
                            rows: [NumericalTripModel.LayerRow],
                            in rect: CGRect,
                            bitMD: Double,
                            yGlobal: (Double) -> CGFloat) {
        for r in rows where r.bottomMD <= bitMD {
            let yTop = yGlobal(r.topMD)
            let yBot = yGlobal(r.bottomMD)
            let yMin = min(yTop, yBot)
            let h = max(1, abs(yBot - yTop))
            let sub = CGRect(x: rect.minX, y: yMin, width: rect.width, height: h)
            let col = fillColor(rho: r.rho_kgpm3)
            ctx.fill(Path(sub), with: .color(col))
        }
        ctx.stroke(Path(rect), with: .color(.black.opacity(0.6)), lineWidth: 1)
    }

    private func fillColor(rho: Double) -> Color {
        let t = min(max((rho - 800) / 1200, 0), 1)
        return Color(white: 0.3 + 0.6 * t)
    }

    // MARK: - Actions
    private func startFresh() {
        viewModel.initializeFresh(project: project)
        modelContext.insert(viewModel.tripTrack!)
        try? modelContext.save()
    }

    private func exportJSON() {
        guard let track = viewModel.tripTrack else { return }
        let dict = track.exportDictionary

        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
              let json = String(data: data, encoding: .utf8) else { return }

        let wellName = (project.well?.name ?? "Trip").replacingOccurrences(of: " ", with: "_")
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
            .replacingOccurrences(of: "/", with: "-")
        let defaultName = "TripTrack_\(wellName)_\(dateStr).json"

        Task {
            _ = await FileService.shared.saveTextFile(
                text: json,
                defaultName: defaultName,
                allowedFileTypes: ["json"]
            )
        }
    }

    private func exportHTML() {
        // TODO: Implement HTML export similar to TripSimulation
    }

    // MARK: - Simulation Picker Sheet
    private var simulationPickerSheet: some View {
        VStack(spacing: 16) {
            Text("Load from Simulation")
                .font(.headline)

            if savedSimulations.isEmpty {
                Text("No saved simulations")
                    .foregroundStyle(.secondary)
            } else {
                List(selection: $selectedSimulation) {
                    ForEach(savedSimulations) { sim in
                        VStack(alignment: .leading) {
                            Text(sim.name)
                            Text("Steps: \(sim.sortedSteps.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(sim)
                    }
                }
                .frame(height: 200)

                if let sim = selectedSimulation {
                    HStack {
                        Text("Start at step:")
                        Picker("", selection: $selectedSimulationStep) {
                            ForEach(0..<sim.sortedSteps.count, id: \.self) { idx in
                                let step = sim.sortedSteps[idx]
                                Text(String(format: "%.0f m", step.bitMD_m)).tag(idx)
                            }
                        }
                        .frame(width: 150)
                    }
                }
            }

            HStack {
                Button("Cancel") {
                    showingSimulationPicker = false
                }
                .buttonStyle(.bordered)

                Button("Load") {
                    if let sim = selectedSimulation {
                        viewModel.initializeFromSimulation(sim, stepIndex: selectedSimulationStep, project: project)
                        modelContext.insert(viewModel.tripTrack!)
                        try? modelContext.save()
                        showingSimulationPicker = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedSimulation == nil)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    // MARK: - Track Picker Sheet
    private var trackPickerSheet: some View {
        VStack(spacing: 16) {
            Text("Resume Previous Track")
                .font(.headline)

            if savedTracks.isEmpty {
                Text("No saved tracks")
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(savedTracks) { track in
                        Button(action: {
                            viewModel.loadTrack(track)
                            showingTrackPicker = false
                        }) {
                            VStack(alignment: .leading) {
                                Text(track.name)
                                HStack {
                                    Text("Steps: \(track.stepCount)")
                                    Text("Last: \(track.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(height: 200)
            }

            Button("Cancel") {
                showingTrackPicker = false
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(width: 400)
    }
}

// MARK: - Step History Row
private struct StepHistoryRow: View {
    let step: TripTrackStep

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Step \(step.stepIndex + 1)")
                    .fontWeight(.medium)
                Spacer()
                Text(String(format: "%.0f m", step.bitMD_m))
                    .monospacedDigit()
            }
            HStack {
                Text(String(format: "%.3f m³", step.observedBackfill_m3))
                Spacer()
                Text(String(format: "%.0f kPa", step.observedSABP_kPa))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Discrepancy indicators
            if step.hasBackfillDiscrepancy || step.hasSABPDiscrepancy {
                HStack(spacing: 4) {
                    if step.hasBackfillDiscrepancy {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    if step.hasSABPDiscrepancy {
                        Image(systemName: "waveform.badge.exclamationmark")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview
#if DEBUG
#Preview("Trip Tracker") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: ProjectState.self, TripTrack.self, TripTrackStep.self, TripSimulation.self,
        configurations: config
    )
    let project = ProjectState()
    container.mainContext.insert(project)

    return TripTrackerView(project: project)
        .modelContainer(container)
        .frame(width: 1200, height: 700)
}
#endif
#endif
