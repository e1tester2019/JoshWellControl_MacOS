//
//  TripTrackerViewIOS.swift
//  Josh Well Control for Mac
//
//  Process-based trip tracking view for iOS - manual step-by-step tracking.
//

#if os(iOS)
import SwiftUI
import SwiftData

struct TripTrackerViewIOS: View {
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
    @State private var showingStartSheet = false
    @State private var showingSimulationPicker = false
    @State private var showingTrackPicker = false
    @State private var selectedSimulation: TripSimulation?
    @State private var selectedSimulationStep: Int = 0
    @State private var showingStepHistory = false

    // MARK: - Body
    var body: some View {
        GeometryReader { geo in
            let isPortrait = geo.size.height > geo.size.width
            let isNarrow = geo.size.width < 700

            if viewModel.tripTrack == nil {
                startOptionsView
            } else if isPortrait || isNarrow {
                portraitLayout(geo: geo)
            } else {
                landscapeLayout(geo: geo)
            }
        }
        .navigationTitle(viewModel.tripTrack?.name ?? "Trip Tracker")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.tripTrack != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New Session") {
                            viewModel.tripTrack = nil
                        }
                        Button("Step History") {
                            showingStepHistory = true
                        }
                        .disabled(viewModel.sortedSteps.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showingStartSheet) {
            startOptionsSheet
        }
        .sheet(isPresented: $showingSimulationPicker) {
            simulationPickerSheet
        }
        .sheet(isPresented: $showingTrackPicker) {
            trackPickerSheet
        }
        .sheet(isPresented: $showingStepHistory) {
            stepHistorySheet
        }
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
                .padding(.horizontal)

            VStack(spacing: 12) {
                Button(action: startFresh) {
                    Label("Start Fresh", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: { showingSimulationPicker = true }) {
                    Label("Load from Simulation", systemImage: "play.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(savedSimulations.isEmpty)

                Button(action: { showingTrackPicker = true }) {
                    Label("Resume Previous", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(savedTracks.isEmpty)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Portrait Layout
    private func portraitLayout(geo: GeometryProxy) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Status bar
                statusBar
                    .padding(.horizontal)

                // Input form
                inputFormSection
                    .padding(.horizontal)

                // Preview section
                if viewModel.previewCalculated {
                    previewSection
                        .padding(.horizontal)
                }

                // Visualization
                visualizationSection
                    .frame(height: 350)
                    .padding(.horizontal)

                // Action buttons
                actionButtonsSection
                    .padding(.horizontal)

                // Quick step list
                if !viewModel.sortedSteps.isEmpty {
                    recentStepsSection
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    // MARK: - Landscape Layout
    private func landscapeLayout(geo: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            // LEFT: Inputs and preview
            ScrollView {
                VStack(spacing: 16) {
                    statusBar
                    inputFormSection
                    if viewModel.previewCalculated {
                        previewSection
                    }
                    actionButtonsSection
                }
                .padding()
            }
            .frame(width: geo.size.width * 0.55)

            Divider()

            // RIGHT: Visualization
            VStack(spacing: 8) {
                visualizationSection
                    .frame(maxHeight: .infinity)

                if !viewModel.sortedSteps.isEmpty {
                    compactStepInfo
                        .padding(.horizontal)
                }
            }
            .padding()
        }
    }

    // MARK: - Status Bar
    private var statusBar: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Bit Depth")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f m", viewModel.currentBitMD_m))
                    .font(.headline)
                    .monospacedDigit()
            }

            Spacer()

            VStack(alignment: .center) {
                Text("Steps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(viewModel.sortedSteps.count)")
                    .font(.headline)
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text("Backfill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.3f m³", viewModel.cumulativeBackfill_m3))
                    .font(.headline)
                    .monospacedDigit()
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Input Form Section
    private var inputFormSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step Inputs")
                .font(.headline)

            // Target bit depth
            HStack {
                Text("Target Bit MD")
                Spacer()
                TextField("", value: $viewModel.inputBitMD_m, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .frame(width: 100)
                Text("m")
                    .foregroundStyle(.secondary)
            }

            // Backfill
            HStack {
                Text("Backfill Pumped")
                Spacer()
                TextField("", value: $viewModel.inputBackfill_m3, format: .number.precision(.fractionLength(3)))
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .frame(width: 100)
                Text("m³")
                    .foregroundStyle(.secondary)
            }

            // SABP
            HStack {
                Text("Observed SABP")
                Spacer()
                TextField("", value: $viewModel.inputSABP_kPa, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .frame(width: 100)
                Text("kPa")
                    .foregroundStyle(.secondary)
            }

            // Pit change
            HStack {
                Text("Pit Change")
                Spacer()
                TextField("", value: $viewModel.inputPitChange_m3, format: .number.precision(.fractionLength(3)))
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .frame(width: 100)
                Text("m³")
                    .foregroundStyle(.secondary)
            }

            // Float override
            HStack {
                Text("Float")
                Spacer()
                Picker("", selection: floatOverrideBinding) {
                    Text("Auto").tag(0)
                    Text("Closed").tag(1)
                    Text("Open").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
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

    // MARK: - Preview Section
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                previewItem("DP Wet", value: String(format: "%.3f m³", viewModel.previewExpectedIfClosed_m3))
                previewItem("DP Dry", value: String(format: "%.3f m³", viewModel.previewExpectedIfOpen_m3))
                previewItem("Calc SABP", value: String(format: "%.0f kPa", viewModel.previewCalculatedSABP_kPa))
                previewItem("Float", value: viewModel.previewFloatState,
                           color: viewModel.previewFloatState.contains("OPEN") ? .orange : .green)
                previewItem("ESD @ TD", value: String(format: "%.0f kg/m³", viewModel.previewESDatTD_kgpm3))
                previewItem("ESD @ Bit", value: String(format: "%.0f kg/m³", viewModel.previewESDatBit_kgpm3))
            }

            // Discrepancies
            if abs(viewModel.previewBackfillDiscrepancy_m3) > 0.01 || abs(viewModel.previewSABPDiscrepancy_kPa) > 50 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Discrepancy: Backfill \(String(format: "%+.3f", viewModel.previewBackfillDiscrepancy_m3)) m³, SABP \(String(format: "%+.0f", viewModel.previewSABPDiscrepancy_kPa)) kPa")
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func previewItem(_ label: String, value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Visualization Section
    private var visualizationSection: some View {
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
                    let gap: CGFloat = 6
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

                    // Pocket - full width
                    for r in pocketLayers {
                        let yTop = yGlobal(r.topMD)
                        let yBot = yGlobal(r.bottomMD)
                        let col = fillColor(rho: r.rho_kgpm3)
                        let top = floor(min(yTop, yBot))
                        let bottom = ceil(max(yTop, yBot))
                        let sub = CGRect(x: 0, y: top, width: size.width, height: max(1, bottom - top))
                        ctx.fill(Path(sub), with: .color(col))
                    }

                    // Bit marker
                    let yBit = yGlobal(bitMD)
                    ctx.fill(Path(CGRect(x: 0, y: yBit - 1, width: size.width, height: 2)),
                             with: .color(.accentColor.opacity(0.9)))

                    // Depth labels
                    ctx.draw(Text(String(format: "%.0f m", bitMD)).font(.caption2),
                             at: CGPoint(x: size.width - 30, y: yBit - 10))
                }
            }
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
        ctx.stroke(Path(rect), with: .color(.black.opacity(0.5)), lineWidth: 1)
    }

    private func fillColor(rho: Double) -> Color {
        let t = min(max((rho - 800) / 1200, 0), 1)
        return Color(white: 0.3 + 0.6 * t)
    }

    // MARK: - Action Buttons
    private var actionButtonsSection: some View {
        HStack(spacing: 16) {
            Button(action: {
                viewModel.calculatePreview(project: project)
            }) {
                Label("Preview", systemImage: "eye")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(action: {
                if let _ = viewModel.lockStep(project: project, context: modelContext) {
                    // Step locked successfully
                }
            }) {
                Label("Lock In", systemImage: "lock.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.previewCalculated)
        }
    }

    // MARK: - Recent Steps Section
    private var recentStepsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Steps")
                    .font(.headline)
                Spacer()
                Button("View All") {
                    showingStepHistory = true
                }
                .font(.caption)
            }

            ForEach(viewModel.sortedSteps.suffix(3).reversed(), id: \.id) { step in
                HStack {
                    VStack(alignment: .leading) {
                        Text("Step \(step.stepIndex + 1)")
                            .fontWeight(.medium)
                        Text(String(format: "%.0f m", step.bitMD_m))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(String(format: "%.3f m³", step.observedBackfill_m3))
                            .monospacedDigit()
                        Text(String(format: "%.0f kPa", step.observedSABP_kPa))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Compact Step Info (Landscape)
    private var compactStepInfo: some View {
        HStack {
            Text("\(viewModel.sortedSteps.count) steps")
            Spacer()
            Text(String(format: "%.3f m³ backfill", viewModel.cumulativeBackfill_m3))
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Actions
    private func startFresh() {
        viewModel.initializeFresh(project: project)
        modelContext.insert(viewModel.tripTrack!)
        try? modelContext.save()
    }

    // MARK: - Start Options Sheet
    private var startOptionsSheet: some View {
        NavigationStack {
            List {
                Button(action: {
                    startFresh()
                    showingStartSheet = false
                }) {
                    Label("Start Fresh", systemImage: "plus.circle.fill")
                }

                Button(action: {
                    showingStartSheet = false
                    showingSimulationPicker = true
                }) {
                    Label("Load from Simulation", systemImage: "play.circle")
                }
                .disabled(savedSimulations.isEmpty)

                Button(action: {
                    showingStartSheet = false
                    showingTrackPicker = true
                }) {
                    Label("Resume Previous", systemImage: "clock.arrow.circlepath")
                }
                .disabled(savedTracks.isEmpty)
            }
            .navigationTitle("Start Trip Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingStartSheet = false }
                }
            }
        }
    }

    // MARK: - Simulation Picker Sheet
    private var simulationPickerSheet: some View {
        NavigationStack {
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
            .navigationTitle("Select Simulation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingSimulationPicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Load") {
                        if let sim = selectedSimulation {
                            viewModel.initializeFromSimulation(sim, stepIndex: 0, project: project)
                            modelContext.insert(viewModel.tripTrack!)
                            try? modelContext.save()
                            showingSimulationPicker = false
                        }
                    }
                    .disabled(selectedSimulation == nil)
                }
            }
        }
    }

    // MARK: - Track Picker Sheet
    private var trackPickerSheet: some View {
        NavigationStack {
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
                }
            }
            .navigationTitle("Resume Track")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingTrackPicker = false }
                }
            }
        }
    }

    // MARK: - Step History Sheet
    private var stepHistorySheet: some View {
        NavigationStack {
            List {
                ForEach(viewModel.sortedSteps, id: \.id) { step in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Step \(step.stepIndex + 1)")
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.0f m", step.bitMD_m))
                                .monospacedDigit()
                        }
                        HStack {
                            Text(String(format: "Backfill: %.3f m³", step.observedBackfill_m3))
                            Spacer()
                            Text(String(format: "SABP: %.0f kPa", step.observedSABP_kPa))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if step.hasBackfillDiscrepancy || step.hasSABPDiscrepancy {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("Discrepancy detected")
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Step History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showingStepHistory = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Undo Last") {
                        viewModel.undoLastStep(context: modelContext)
                    }
                    .disabled(viewModel.sortedSteps.isEmpty)
                }
            }
        }
    }
}

// MARK: - Preview
#if DEBUG
#Preview("Trip Tracker iOS") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: ProjectState.self, TripTrack.self, TripTrackStep.self, TripSimulation.self,
        configurations: config
    )
    let project = ProjectState()
    container.mainContext.insert(project)

    return NavigationStack {
        TripTrackerViewIOS(project: project)
    }
    .modelContainer(container)
}
#endif
#endif
