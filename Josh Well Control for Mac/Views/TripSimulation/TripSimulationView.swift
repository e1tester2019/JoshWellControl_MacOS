//  TripSimulationView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-07.
// (assistant) Connected and ready – 2025-11-07
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

typealias TripStep = NumericalTripModel.TripStep
typealias LayerRow = NumericalTripModel.LayerRow

struct KVRow: Identifiable {
    let id = UUID()
    let key: String
    let value: String
}

// MARK: - ViewModel Cache

/// Cache to persist TripSimulationView.ViewModel across view switches
enum TripSimViewModelCache {
    @MainActor
    private static var cache: [UUID: TripSimulationView.ViewModel] = [:]

    @MainActor
    static func get(for projectID: UUID) -> TripSimulationView.ViewModel {
        if let existing = cache[projectID] {
            return existing
        }
        let newVM = TripSimulationView.ViewModel()
        cache[projectID] = newVM
        return newVM
    }
}

/// A compact SwiftUI front‑end over the NumericalTripModel.
/// Shows inputs, a steps table, an interactive detail (accordion), and a simple 2‑column mud visualization.
struct TripSimulationView: View {
    // MARK: - Environment
    @Environment(\.modelContext) private var modelContext

    // You typically have a selected project bound in higher views. If not, you can inject a specific instance here.
    @Bindable var project: ProjectState

    /// Optional closure to navigate to another view (e.g., Trip In). Provided by parent content view.
    var navigateToView: ((ViewSelection) -> Void)?

    @State private var viewmodel: ViewModel
    @State private var showingExportErrorAlert = false
    @State private var exportErrorMessage = ""

    // Consolidated sheet state
    private enum SheetType: Identifiable {
        case optimizer
        case pumpSchedule
        case circulation

        var id: String {
            switch self {
            case .optimizer: return "optimizer"
            case .pumpSchedule: return "pumpSchedule"
            case .circulation: return "circulation"
            }
        }
    }
    @State private var activeSheet: SheetType?

    // Pump Schedule sheet state
    @State private var pumpScheduleVM = PumpScheduleViewModel()

    // Trip Optimizer state
    @State private var optimizerSurfaceSlugVolume: Double = 2.0
    @State private var optimizerSurfaceSlugDensity: Double = 2100
    @State private var optimizerSecondSlugDensity: Double? = nil  // nil = use calculated
    @State private var optimizerManualHeelMD: Double? = nil
    @State private var optimizerObservedSlugDrop: Double? = nil
    @State private var optimizerResult: TripOptimizerResult? = nil

    init(project: ProjectState, navigateToView: ((ViewSelection) -> Void)? = nil) {
        self.project = project
        self.navigateToView = navigateToView
        _viewmodel = State(initialValue: TripSimViewModelCache.get(for: project.id))
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 12) {
            headerInputs
            Divider()
            content
        }
        .padding(12)
        .onAppear {
            // Check for pending wellbore state handoff from Trip In
            if let state = OperationHandoffService.shared.pendingTripOutState {
                OperationHandoffService.shared.pendingTripOutState = nil
                viewmodel.importFromWellboreState(state, project: project)
            }
            // Load saved inputs if available, otherwise bootstrap from project
            else if viewmodel.steps.isEmpty && viewmodel.startBitMD_m == 0 {
                if !viewmodel.loadSavedInputs(project: project) {
                    viewmodel.bootstrap(from: project)
                }
            }
        }
        .onChange(of: viewmodel.selectedIndex) { _, newVal in
            viewmodel.stepSlider = Double(newVal ?? 0)
            // Reset ballooning actual volume to simulated value when step changes
            if let idx = newVal, viewmodel.steps.indices.contains(idx) {
                viewmodel.ballooningActualVolume_m3 = viewmodel.steps[idx].cumulativeBackfill_m3
                viewmodel.ballooningResult = nil
            }
        }
        .alert("Export Error", isPresented: $showingExportErrorAlert, actions: { Button("OK", role: .cancel) {} }) {
            Text(exportErrorMessage)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .optimizer:
                tripOptimizerSheet
            case .pumpSchedule:
                pumpScheduleSheet
            case .circulation:
                circulationSheet
            }
        }
    }

    // MARK: - Sections
    private var headerInputs: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Row 1: Main GroupBoxes
            HStack(spacing: 8) {
                GroupBox("Bit / Range") {
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                        GridRow {
                            Text("Start").foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                TextField("", value: $viewmodel.startBitMD_m, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                                Text("(\(Int(startTVD)))")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                    .help("TVD at start depth")
                            }
                            Text("End").foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                TextField("", value: $viewmodel.endMD_m, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                                Text("(\(Int(endTVD)))")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                    .help("TVD at end depth")
                            }
                        }
                        GridRow {
                            Text("Control").foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                TextField("", value: controlMDBinding, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                                Text("(\(Int(controlTVD)))")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                    .help("TVD at control depth")
                            }
                            Text("Step").foregroundStyle(.secondary)
                            TextField("", value: $viewmodel.step_m, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                        }
                    }
                }

                GroupBox("Fluids") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text("Base:")
                                .foregroundStyle(.secondary)
                            let active = project.activeMud
                            Text(active.map { "\($0.name) – \(format0($0.density_kgm3))" } ?? "None")
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                        HStack(spacing: 4) {
                            Text("Backfill:")
                                .foregroundStyle(.secondary)
                            Picker("", selection: backfillMudBinding) {
                                ForEach((project.muds ?? []).sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }), id: \.id) { m in
                                    Text("\(m.name): \(format0(m.density_kgm3))").tag(m.id as UUID?)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 180)
                            .pickerStyle(.menu)
                            .controlSize(.small)
                        }
                        Toggle("Switch to active after displacement", isOn: $viewmodel.switchToActiveAfterDisplacement)
                            .controlSize(.small)
                            .help("Pump backfill mud for the drill string displacement volume, then switch to active mud for the remaining pit gain portion")
                            .onChange(of: viewmodel.switchToActiveAfterDisplacement) { _, newValue in
                                if newValue {
                                    viewmodel.computeDisplacementVolume(project: project)
                                }
                                viewmodel.saveBackfillSettings(to: project)
                            }

                        if viewmodel.switchToActiveAfterDisplacement {
                            HStack(spacing: 4) {
                                Text("Vol:")
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.2f", viewmodel.computedDisplacementVolume_m3))
                                    .monospacedDigit()
                                    .foregroundStyle(.blue)
                                    .help("Computed steel displacement volume")
                                Toggle("Override:", isOn: $viewmodel.useOverrideDisplacementVolume)
                                    .controlSize(.small)
                                    .onChange(of: viewmodel.useOverrideDisplacementVolume) { _, _ in
                                        viewmodel.saveBackfillSettings(to: project)
                                    }
                                TextField("", value: $viewmodel.overrideDisplacementVolume_m3, format: .number.precision(.fractionLength(2)))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                                    .disabled(!viewmodel.useOverrideDisplacementVolume)
                                    .onChange(of: viewmodel.overrideDisplacementVolume_m3) { _, _ in
                                        viewmodel.saveBackfillSettings(to: project)
                                    }
                                Text("m³")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 4) {
                            Text("Target ESD:").foregroundStyle(.secondary)
                            TextField("", value: $viewmodel.targetESDAtTD_kgpm3, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                        }
                    }
                }

                GroupBox("Choke / Float") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("Crack").foregroundStyle(.secondary)
                            TextField("", value: $viewmodel.crackFloat_kPa, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                            Text("SABP").foregroundStyle(.secondary)
                            TextField("", value: $viewmodel.initialSABP_kPa, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                        }
                        Toggle("Hold SABP open", isOn: $viewmodel.holdSABPOpen)
                            .controlSize(.small)
                    }
                }

                GroupBox("Trip") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            TextField("", value: tripSpeedBinding_mpm, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                            Text("m/min").foregroundStyle(.secondary)
                        }
                        Text(tripSpeedDirectionText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            // Row 2: Slug calibration + View options + Bit Depth + Actions
            HStack(spacing: 8) {
                GroupBox("Slug Calibration") {
                    HStack(spacing: 8) {
                        if viewmodel.calculatedInitialPitGain_m3 > 0 {
                            HStack(spacing: 4) {
                                Text("Calc:")
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.3f", viewmodel.calculatedInitialPitGain_m3))
                                    .monospacedDigit()
                                Button {
                                    viewmodel.observedInitialPitGain_m3 = viewmodel.calculatedInitialPitGain_m3
                                } label: {
                                    Image(systemName: "arrow.right.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        Toggle("Observed:", isOn: $viewmodel.useObservedPitGain)
                            .controlSize(.small)
                        TextField("m³", value: $viewmodel.observedInitialPitGain_m3, format: .number.precision(.fractionLength(3)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                            .disabled(!viewmodel.useObservedPitGain)
                        Text("m³")
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Colors", isOn: $viewmodel.colorByComposition)
                    .controlSize(.small)

                // TVD Source toggle
                HStack(spacing: 4) {
                    Text("TVD:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $viewmodel.useDirectionalPlanForTVD) {
                        Text("Surveys").tag(false)
                        Text("Dir Plan").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 130)
                }
                .help("Choose whether to use actual surveys or directional plan for TVD calculations")

                if !viewmodel.steps.isEmpty {
                    HStack(spacing: 4) {
                        Text("Depth:")
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { viewmodel.stepSlider },
                                set: { newVal in
                                    viewmodel.stepSlider = newVal
                                    let idx = min(max(Int(round(newVal)), 0), max(viewmodel.steps.count - 1, 0))
                                    viewmodel.selectedIndex = idx
                                }
                            ),
                            in: 0...Double(max(viewmodel.steps.count - 1, 0)), step: 1
                        )
                        .frame(width: 120)
                        Text(String(format: "%.0fm", viewmodel.steps[min(max(viewmodel.selectedIndex ?? 0, 0), max(viewmodel.steps.count - 1, 0))].bitMD_m))
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }
                }

                Spacer()

                Toggle("Details", isOn: $viewmodel.showDetails)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                // Optimizer button
                Button {
                    activeSheet = .optimizer
                } label: {
                    Label("Optimizer", systemImage: "function")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Calculate optimal slug and backfill densities")

                if viewmodel.isRunning {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.small)
                        Text(viewmodel.progressMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: 150)
                    }
                } else {
                    Button("Run") { viewmodel.runSimulation(project: project) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }

                // Save inputs silently to project
                Button {
                    viewmodel.saveInputs(project: project, context: modelContext)
                } label: {
                    Label("Save Inputs", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Menu {
                    Button("Export PDF Report") { exportPDFReport() }
                    Button("Export HTML Report") { exportHTMLReport() }
                    Button("Export Zipped HTML Report") { exportZippedHTMLReport() }
                    Divider()
                    Button("Export Project JSON") { exportProjectJSON() }
                } label: {
                    Text("Export")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                // Operations handoff buttons
                if !viewmodel.steps.isEmpty && viewmodel.selectedIndex != nil {
                    Divider()
                        .frame(height: 16)

                    Button {
                        activeSheet = .circulation
                    } label: {
                        Label("Circulate Here", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Circulate fluids at the current bit depth")

                    Button {
                        openPumpScheduleSheet()
                    } label: {
                        Label("Pump Schedule", systemImage: "chart.bar.doc.horizontal")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Open full pump schedule simulation with current wellbore state")

                    Button {
                        handoffToTripIn()
                    } label: {
                        Label("Trip In from Here", systemImage: "arrow.down.to.line")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Start a Trip In simulation from the current depth using this wellbore state")
                }
            }
        }
    }

    // MARK: - Trip Optimizer Sheet
    private var tripOptimizerSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "function")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Trip Optimizer")
                    .font(.headline)
                Spacer()
                Button {
                    activeSheet = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }

            Text("Calculate kill mud density for annulus based on slug densities")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            // Inputs
            GroupBox("Inputs") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Target ESD:")
                            .foregroundStyle(.secondary)
                        HStack {
                            Text(String(format: "%.0f kg/m³", viewmodel.targetESDAtTD_kgpm3))
                                .monospacedDigit()
                            Text("(from simulation)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    GridRow {
                        Text("Surface Slug Vol:")
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField("", value: $optimizerSurfaceSlugVolume, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                            Text("m³")
                                .foregroundStyle(.secondary)
                        }
                    }

                    GridRow {
                        Text("Surface Slug ρ:")
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField("", value: $optimizerSurfaceSlugDensity, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                            Text("kg/m³")
                                .foregroundStyle(.secondary)
                        }
                    }

                    GridRow {
                        Text("2nd Slug ρ:")
                            .foregroundStyle(.secondary)
                        HStack {
                            if let density = optimizerSecondSlugDensity {
                                TextField("", value: Binding(
                                    get: { density },
                                    set: { optimizerSecondSlugDensity = $0 }
                                ), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                                Text("kg/m³")
                                    .foregroundStyle(.secondary)
                                Button("Auto") {
                                    optimizerSecondSlugDensity = nil
                                }
                                .buttonStyle(.borderless)
                            } else {
                                Text("Auto-calculate")
                                    .foregroundStyle(.blue)
                                Button("Manual") {
                                    optimizerSecondSlugDensity = 1920
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }

                    // Show formula when auto-calculating
                    if optimizerSecondSlugDensity == nil {
                        GridRow {
                            Text("")
                            Text("= 2×ESD - Active + Crack/TVD")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    GridRow {
                        Text("Heel Depth:")
                            .foregroundStyle(.secondary)
                        HStack {
                            if let heelMD = optimizerManualHeelMD {
                                TextField("", value: Binding(
                                    get: { heelMD },
                                    set: { optimizerManualHeelMD = $0 }
                                ), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                                Text("m MD")
                                    .foregroundStyle(.secondary)
                                Button("Auto") {
                                    optimizerManualHeelMD = nil
                                }
                                .buttonStyle(.borderless)
                            } else {
                                Text("Auto-detect (first 90°)")
                                    .foregroundStyle(.blue)
                                Button("Manual") {
                                    optimizerManualHeelMD = viewmodel.startBitMD_m * 0.5
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }

                    GridRow {
                        Text("Slug Drop:")
                            .foregroundStyle(.secondary)
                        HStack {
                            if let slugDrop = optimizerObservedSlugDrop {
                                TextField("", value: Binding(
                                    get: { slugDrop },
                                    set: { optimizerObservedSlugDrop = $0 }
                                ), format: .number.precision(.fractionLength(2)))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                                Text("m³")
                                    .foregroundStyle(.secondary)
                                Button("Estimate") {
                                    optimizerObservedSlugDrop = nil
                                }
                                .buttonStyle(.borderless)
                            } else {
                                Text("Estimated")
                                    .foregroundStyle(.orange)
                                Button("From Sim") {
                                    optimizerObservedSlugDrop = 3.29  // Default, user should update
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }

            // Calculate button
            Button {
                runOptimizer()
            } label: {
                Label("Calculate Kill Mud Density", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)

            // Results
            if let result = optimizerResult {
                Divider()

                ScrollView {
                    GroupBox("Results") {
                        VStack(alignment: .leading, spacing: 12) {
                        // All mud densities and volumes in a row
                        HStack(alignment: .top, spacing: 16) {
                            // Kill Mud
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Circle().fill(.green).frame(width: 10, height: 10)
                                    Text("Kill Mud")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(String(format: "%.0f", result.killMudDensity_kgm3))
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundStyle(result.killMudDensity_kgm3 < 1000 ? .orange : .green)
                                Text(String(format: "%.2f m³", result.killMudVolume_m3))
                                    .font(.caption)
                                    .monospacedDigit()
                            }
                            .frame(minWidth: 80)

                            // Surface Slug
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Circle().fill(.orange).frame(width: 10, height: 10)
                                    Text("Surface Slug")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(String(format: "%.0f", result.surfaceSlugDensity_kgm3))
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.orange)
                                Text(String(format: "%.2f m³", result.surfaceSlugVolume_m3))
                                    .font(.caption)
                                    .monospacedDigit()
                            }
                            .frame(minWidth: 80)

                            // Active Mud (if present)
                            if result.activeMudHeight_m > 0.1 {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 4) {
                                        Circle().fill(.cyan).frame(width: 10, height: 10)
                                        Text("Active Mud")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(String(format: "%.0f", result.baseMudDensity_kgm3))
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.cyan)
                                    Text(String(format: "%.2f m³", result.activeMudVolume_m3))
                                        .font(.caption)
                                        .monospacedDigit()
                                }
                                .frame(minWidth: 80)
                            }

                            // 2nd Slug
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Circle().fill(.blue).frame(width: 10, height: 10)
                                    Text("2nd Slug")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(String(format: "%.0f", result.secondSlugDensity_kgm3))
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.blue)
                                Text(String(format: "%.2f m³", result.secondSlugVolume_m3))
                                    .font(.caption)
                                    .monospacedDigit()
                            }
                            .frame(minWidth: 80)

                            // Original Mud
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Circle().fill(.gray).frame(width: 10, height: 10)
                                    Text("Original")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(String(format: "%.0f", result.baseMudDensity_kgm3))
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.gray)
                                Text("to control")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(minWidth: 80)

                            Spacer()
                        }

                        Divider()

                        // Annulus layers visualization with pressure
                        Text("Annulus Layers (from surface)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        let g = 0.00981  // kPa per m per kg/m³
                        let killMudPressure = result.killMudDensity_kgm3 * g * result.killMudHeight_m
                        let surfaceSlugPressure = result.surfaceSlugDensity_kgm3 * g * result.surfaceSlugHeight_m
                        let activeMudPressure = result.baseMudDensity_kgm3 * g * result.activeMudHeight_m
                        let secondSlugPressure = result.secondSlugDensity_kgm3 * g * result.secondSlugHeight_m
                        let originalMudPressure = result.baseMudDensity_kgm3 * g * result.originalMudHeight_m
                        let totalHeight = result.killMudHeight_m + result.surfaceSlugHeight_m + result.activeMudHeight_m + result.secondSlugHeight_m + result.originalMudHeight_m
                        let totalPressure = killMudPressure + surfaceSlugPressure + activeMudPressure + secondSlugPressure + originalMudPressure
                        let calculatedESD = totalPressure / (g * result.controlTVD_m)

                        Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 6) {
                            // Header
                            GridRow {
                                Text("")
                                Text("Layer").fontWeight(.medium)
                                Text("Density").fontWeight(.medium)
                                Text("Height").fontWeight(.medium)
                                Text("Pressure").fontWeight(.medium)
                            }
                            .foregroundStyle(.secondary)

                            Divider().gridCellColumns(5)

                            GridRow {
                                Circle().fill(.green).frame(width: 8, height: 8)
                                Text("Kill Mud").frame(maxWidth: .infinity, alignment: .leading)
                                Text(String(format: "%.0f", result.killMudDensity_kgm3))
                                Text(String(format: "%.1f", result.killMudHeight_m))
                                Text(String(format: "%.0f", killMudPressure))
                            }
                            GridRow {
                                Circle().fill(.orange).frame(width: 8, height: 8)
                                Text("Surface Slug").frame(maxWidth: .infinity, alignment: .leading)
                                Text(String(format: "%.0f", result.surfaceSlugDensity_kgm3))
                                Text(String(format: "%.1f", result.surfaceSlugHeight_m))
                                Text(String(format: "%.0f", surfaceSlugPressure))
                            }
                            if result.activeMudHeight_m > 0.1 {
                                GridRow {
                                    Circle().fill(.cyan).frame(width: 8, height: 8)
                                    Text("Active Mud").frame(maxWidth: .infinity, alignment: .leading)
                                    Text(String(format: "%.0f", result.baseMudDensity_kgm3))
                                    Text(String(format: "%.1f", result.activeMudHeight_m))
                                    Text(String(format: "%.0f", activeMudPressure))
                                }
                            }
                            GridRow {
                                Circle().fill(.blue).frame(width: 8, height: 8)
                                Text("2nd Slug @ Heel").frame(maxWidth: .infinity, alignment: .leading)
                                Text(String(format: "%.0f", result.secondSlugDensity_kgm3))
                                Text(String(format: "%.1f", result.secondSlugHeight_m))
                                Text(String(format: "%.0f", secondSlugPressure))
                            }
                            GridRow {
                                Circle().fill(.gray).frame(width: 8, height: 8)
                                Text("Original Mud").frame(maxWidth: .infinity, alignment: .leading)
                                Text(String(format: "%.0f", result.baseMudDensity_kgm3))
                                Text(String(format: "%.1f", result.originalMudHeight_m))
                                Text(String(format: "%.0f", originalMudPressure))
                            }

                            Divider().gridCellColumns(5)

                            // Totals row
                            GridRow {
                                Text("")
                                Text("Total").fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading)
                                Text("")
                                Text(String(format: "%.1f m", totalHeight)).fontWeight(.semibold)
                                Text(String(format: "%.0f kPa", totalPressure)).fontWeight(.semibold)
                            }

                            // ESD verification
                            GridRow {
                                Text("")
                                Text("→ ESD @ Control").frame(maxWidth: .infinity, alignment: .leading)
                                Text("")
                                Text(String(format: "%.1f m TVD", result.controlTVD_m))
                                Text(String(format: "%.0f kg/m³", calculatedESD))
                                    .foregroundStyle(abs(calculatedESD - viewmodel.targetESDAtTD_kgpm3) < 1 ? .green : .orange)
                            }
                        }
                        .font(.caption)
                        .monospacedDigit()

                        Divider()

                        // Details
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                            GridRow {
                                Text("Heel Depth (90°):")
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.0f m MD (%.0f m TVD)", result.heelMD_m, result.heelTVD_m))
                                    .monospacedDigit()
                            }
                            GridRow {
                                Text("2nd Slug Bottom (Heel):")
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.0f m TVD", result.sixtyDegTVD_m))
                                    .monospacedDigit()
                            }
                            GridRow {
                                Text("2nd Slug Density:")
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 4) {
                                    Text(String(format: "%.0f kg/m³", result.secondSlugDensity_kgm3))
                                        .monospacedDigit()
                                    if result.secondSlugDensityWasCalculated {
                                        Text("(calc)")
                                            .font(.caption2)
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            if result.secondSlugDensityWasCalculated {
                                GridRow {
                                    Text("")
                                    Text("= 2×\(Int(viewmodel.targetESDAtTD_kgpm3)) - \(Int(result.baseMudDensity_kgm3)) + \(Int(viewmodel.crackFloat_kPa))/\(Int(result.heelTVD_m))/0.00981")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            GridRow {
                                Text("2nd Slug Volume:")
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.2f m³", result.secondSlugVolume_m3))
                                    .monospacedDigit()
                            }
                            if result.activeMudHeight_m > 0.1 {
                                GridRow {
                                    Text("Active Mud Volume:")
                                        .foregroundStyle(.secondary)
                                    Text(String(format: "%.2f m³", result.activeMudVolume_m3))
                                        .monospacedDigit()
                                }
                            }
                            GridRow {
                                Text("Slug Drop:")
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 4) {
                                    Text(String(format: "%.2f m³", result.slugDropVolume_m3))
                                        .monospacedDigit()
                                    if abs(result.slugDropVolume_m3 - result.slugDropCalculated_m3) > 0.01 {
                                        Text("(calc: \(String(format: "%.2f", result.slugDropCalculated_m3)))")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                            // Slug drop calculation breakdown
                            GridRow {
                                Text("  Effective ESD:")
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.0f kg/m³ (target + crack)", result.effectiveESD_kgm3))
                                    .monospacedDigit()
                                    .font(.caption2)
                            }
                            GridRow {
                                Text("  Surface slug:")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(String(format: "MD=%.1fm, TVD=%.1fm",
                                        result.surfaceSlugMDLength_m,
                                        result.surfaceSlugTVDHeight_m))
                                    Text(String(format: "Δρ=%.0f × %.1f / %.0f = %.2fm",
                                        result.surfaceSlugDensity_kgm3 - result.effectiveESD_kgm3,
                                        result.surfaceSlugTVDHeight_m,
                                        result.effectiveESD_kgm3,
                                        result.surfaceSlugDropHeight_m))
                                }
                                .monospacedDigit()
                                .font(.caption2)
                            }
                            GridRow {
                                Text("  2nd slug:")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(String(format: "MD=%.1fm, TVD=%.1fm",
                                        result.secondSlugMDLength_m,
                                        result.secondSlugTVDHeight_m))
                                    Text(String(format: "Δρ=%.0f × %.1f / %.0f = %.2fm",
                                        result.secondSlugDensity_kgm3 - result.effectiveESD_kgm3,
                                        result.secondSlugTVDHeight_m,
                                        result.effectiveESD_kgm3,
                                        result.secondSlugDropHeight_m))
                                }
                                .monospacedDigit()
                                .font(.caption2)
                            }
                            GridRow {
                                Text("Steel Displacement:")
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.2f m³", result.totalSteelDisplacement_m3))
                                    .monospacedDigit()
                            }
                            GridRow {
                                Text("Control TVD:")
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.0f m", result.controlTVD_m))
                                    .monospacedDigit()
                            }
                            GridRow {
                                Text("Annulus Capacity:")
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.4f m³/m", result.annulusCapacity_m3_per_m))
                                    .monospacedDigit()
                            }
                        }
                        .font(.caption)

                        // Warnings
                        if !result.warnings.isEmpty {
                            Divider()
                            ForEach(result.warnings, id: \.self) { warning in
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.yellow)
                                    Text(warning)
                                }
                                .font(.caption)
                            }
                        }
                    }
                }

                // Note about manual setup
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                    Text("Use these values to set up your mud properties and simulation inputs manually.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
                }  // ScrollView
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 650, minHeight: optimizerResult != nil ? 850 : 400)
    }

    private func runOptimizer() {
        let input = TripOptimizerInput(
            targetESD_kgm3: viewmodel.targetESDAtTD_kgpm3,
            surfaceSlugVolume_m3: optimizerSurfaceSlugVolume,
            surfaceSlugDensity_kgm3: optimizerSurfaceSlugDensity,
            secondSlugDensity_kgm3: optimizerSecondSlugDensity,  // nil = auto-calculate
            baseMudDensity_kgm3: project.activeMud?.density_kgm3 ?? viewmodel.baseMudDensity_kgpm3,
            crackFloat_kPa: viewmodel.crackFloat_kPa,
            startBitMD_m: viewmodel.startBitMD_m,
            controlMD_m: viewmodel.shoeMD_m,
            manualHeelMD_m: optimizerManualHeelMD,
            observedSlugDrop_m3: optimizerObservedSlugDrop
        )

        optimizerResult = TripOptimizer.calculate(
            input: input,
            project: project,
            tvdSampler: tvdSampler
        )
    }

    private var backfillMudBinding: Binding<UUID?> {
        Binding(
            get: { viewmodel.backfillMudID },
            set: { newID in
                viewmodel.backfillMudID = newID
                let muds = (project.muds ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                if let id = newID, let m = muds.first(where: { $0.id == id }) {
                    viewmodel.backfillDensity_kgpm3 = m.density_kgm3
                } else {
                    viewmodel.backfillDensity_kgpm3 = project.activeMud?.density_kgm3 ?? viewmodel.backfillDensity_kgpm3
                }
            }
        )
    }

    // MARK: - Operations Handoff

    /// Hand off the current wellbore state to Trip In simulation
    private func handoffToTripIn() {
        guard let state = viewmodel.wellboreStateAtSelectedStep() else { return }
        OperationHandoffService.shared.pendingTripInState = state
        if let navigate = navigateToView {
            navigate(.tripInSimulation)
        }
    }

    // MARK: - Pump Schedule Sheet

    private func openPumpScheduleSheet() {
        guard let state = viewmodel.wellboreStateAtSelectedStep() else { return }
        pumpScheduleVM = PumpScheduleViewModel()
        pumpScheduleVM.bootstrapFromWellboreState(state, project: project, context: modelContext)
        activeSheet = .pumpSchedule
    }

    private var pumpScheduleSheet: some View {
        VStack(spacing: 0) {
            // Action bar
            HStack {
                Text("Pump Schedule")
                    .font(.headline)
                Spacer()
                Button("Apply & Return") {
                    applyPumpScheduleState()
                }
                .buttonStyle(.borderedProminent)
                Button("Cancel") {
                    activeSheet = nil
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            PumpScheduleView(project: project, viewModel: pumpScheduleVM)
        }
        .frame(minWidth: 1100, minHeight: 700)
    }

    private func applyPumpScheduleState() {
        guard let exported = pumpScheduleVM.exportWellboreState(project: project) else {
            activeSheet = nil
            return
        }
        guard let idx = viewmodel.selectedIndex, viewmodel.steps.indices.contains(idx) else {
            activeSheet = nil
            return
        }

        // Update the selected step's layers with the pump schedule result
        viewmodel.steps[idx].layersPocket = exported.layersPocket.map { $0.toLayerRow() }
        viewmodel.steps[idx].layersAnnulus = exported.layersAnnulus.map { $0.toLayerRow() }
        viewmodel.steps[idx].layersString = exported.layersString.map { $0.toLayerRow() }

        activeSheet = nil
    }

    // MARK: - Circulation Sheet

    private var circulationSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Circulate at \(circulationBitDepthLabel)m MD")
                    .font(.headline)
                Spacer()
                Button {
                    viewmodel.clearPumpQueue()
                    activeSheet = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }

            Text("Queue pump operations to circulate fluids at the current bit depth")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Provenance banner
            if let desc = viewmodel.importedStateDescription {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(6)
                .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            Divider()

            HStack(alignment: .top, spacing: 16) {
                // Left: Pump queue builder
                VStack(alignment: .leading, spacing: 8) {
                    GroupBox("Add to Queue") {
                        VStack(spacing: 6) {
                            // Mud picker
                            Picker("Mud", selection: $viewmodel.selectedCirculateMudID) {
                                Text("Select...").tag(UUID?.none)
                                ForEach(project.muds ?? [], id: \.id) { mud in
                                    HStack {
                                        Circle()
                                            .fill(Color(red: mud.colorR, green: mud.colorG, blue: mud.colorB))
                                            .frame(width: 10, height: 10)
                                        Text("\(mud.name) (\(Int(mud.density_kgm3)) kg/m\u{00B3})")
                                    }
                                    .tag(UUID?.some(mud.id))
                                }
                            }
                            .pickerStyle(.menu)

                            HStack {
                                Text("Volume:")
                                    .foregroundStyle(.secondary)
                                TextField("", value: $viewmodel.circulateVolume_m3, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                                Text("m\u{00B3}")
                                    .foregroundStyle(.secondary)
                            }

                            Button("Add to Queue") {
                                guard let mudID = viewmodel.selectedCirculateMudID,
                                      let mud = (project.muds ?? []).first(where: { $0.id == mudID }) else { return }
                                viewmodel.addToPumpQueue(mud: mud, volume_m3: viewmodel.circulateVolume_m3)
                                viewmodel.previewPumpQueue(project: project)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(viewmodel.selectedCirculateMudID == nil)
                        }
                    }

                    // Queue list
                    if !viewmodel.pumpQueue.isEmpty {
                        GroupBox("Pump Queue (\(String(format: "%.1f", viewmodel.totalQueueVolume_m3)) m\u{00B3})") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(viewmodel.pumpQueue.enumerated()), id: \.element.id) { index, op in
                                    HStack {
                                        Circle()
                                            .fill(Color(red: op.mudColorR, green: op.mudColorG, blue: op.mudColorB))
                                            .frame(width: 8, height: 8)
                                        Text("\(op.mudName)")
                                            .font(.caption)
                                        Spacer()
                                        Text("\(String(format: "%.1f", op.volume_m3)) m\u{00B3}")
                                            .font(.caption)
                                            .monospacedDigit()
                                        Button {
                                            viewmodel.removeFromPumpQueue(at: index)
                                            viewmodel.previewPumpQueue(project: project)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.caption2)
                                        }
                                        .buttonStyle(.borderless)
                                        .foregroundStyle(.red)
                                    }
                                }

                                Button("Clear All") {
                                    viewmodel.clearPumpQueue()
                                }
                                .font(.caption)
                                .foregroundStyle(.red)
                            }
                        }
                    }
                }
                .frame(width: 260)

                // Right: Preview and schedule
                VStack(alignment: .leading, spacing: 8) {
                    // Preview metrics
                    if viewmodel.previewESDAtControl > 0 {
                        GroupBox("Preview") {
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                                GridRow {
                                    Text("ESD at Control:").foregroundStyle(.secondary).font(.caption)
                                    Text(String(format: "%.1f kg/m\u{00B3}", viewmodel.previewESDAtControl))
                                        .font(.caption).monospacedDigit()
                                }
                                GridRow {
                                    Text("Required SABP:").foregroundStyle(.secondary).font(.caption)
                                    Text(String(format: "%.0f kPa", viewmodel.previewRequiredSABP))
                                        .font(.caption).monospacedDigit()
                                }
                            }
                        }
                    }

                    // Schedule table
                    if !viewmodel.circulateOutSchedule.isEmpty {
                        GroupBox("Pressure Schedule") {
                            Table(viewmodel.circulateOutSchedule) {
                                TableColumn("Vol m\u{00B3}") { step in
                                    Text(String(format: "%.1f", step.volumePumped_m3))
                                        .font(.caption).monospacedDigit()
                                }
                                .width(min: 50, ideal: 60)
                                TableColumn("Vol bbl") { step in
                                    Text(String(format: "%.1f", step.volumePumped_bbl))
                                        .font(.caption).monospacedDigit()
                                }
                                .width(min: 50, ideal: 60)
                                TableColumn("Strokes") { step in
                                    Text(String(format: "%.0f", step.strokesAtPumpOutput))
                                        .font(.caption).monospacedDigit()
                                }
                                .width(min: 50, ideal: 60)
                                TableColumn("ESD") { step in
                                    Text(String(format: "%.1f", step.ESDAtControl_kgpm3))
                                        .font(.caption).monospacedDigit()
                                }
                                .width(min: 50, ideal: 60)
                                TableColumn("SABP kPa") { step in
                                    Text(String(format: "%.0f", step.requiredSABP_kPa))
                                        .font(.caption).monospacedDigit()
                                }
                                .width(min: 60, ideal: 70)
                                TableColumn("Description") { step in
                                    Text(step.description)
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                                .width(min: 120, ideal: 200)
                            }
                            .frame(minHeight: 150)
                        }
                    }

                    Spacer()

                    // Action buttons
                    HStack {
                        Spacer()
                        Button("Cancel") {
                            viewmodel.clearPumpQueue()
                            activeSheet = nil
                        }
                        .keyboardShortcut(.cancelAction)

                        Button("Commit & Re-run") {
                            viewmodel.commitCirculation(project: project)
                            activeSheet = nil
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewmodel.pumpQueue.isEmpty)
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 750, minHeight: 500)
    }

    // MARK: - Export PDF Report
    private func exportPDFReport() {
        guard !viewmodel.steps.isEmpty else {
            exportErrorMessage = "Run simulation first before exporting."
            showingExportErrorAlert = true
            return
        }

        // Get actual mud densities from project (matches simulation logic)
        let backfillMud = viewmodel.backfillMudID.flatMap { id in (project.muds ?? []).first(where: { $0.id == id }) }
        let actualBackfillDensity = backfillMud?.density_kgm3 ?? viewmodel.backfillDensity_kgpm3
        let actualBaseMudDensity = project.activeMud?.density_kgm3 ?? viewmodel.baseMudDensity_kgpm3

        // Get actual initial SABP from first simulation step (not the input value)
        let actualInitialSABP = viewmodel.steps.first?.SABP_kPa ?? viewmodel.initialSABP_kPa

        // Build geometry data for PDF
        let drillStringSections: [PDFSectionData] = (project.drillString ?? []).sorted { $0.topDepth_m < $1.topDepth_m }.map { ds in
            let id = ds.innerDiameter_m
            let od = ds.outerDiameter_m
            let capacity = .pi * (id * id) / 4.0  // m³/m (pipe bore capacity)
            let displacement = .pi * (od * od - id * id) / 4.0  // m³/m (steel volume)
            return PDFSectionData(
                name: ds.name,
                topMD: ds.topDepth_m,
                bottomMD: ds.bottomDepth_m,
                length: ds.length_m,
                innerDiameter: id,
                outerDiameter: od,
                capacity_m3_per_m: capacity,
                displacement_m3_per_m: displacement,
                totalVolume: capacity * ds.length_m
            )
        }

        // Helper to find pipe OD from drill string at a given depth
        let drillStringSorted = (project.drillString ?? []).sorted { $0.topDepth_m < $1.topDepth_m }
        func pipeODAtDepth(_ md: Double) -> Double {
            for ds in drillStringSorted {
                if ds.topDepth_m <= md && md <= ds.bottomDepth_m {
                    return ds.outerDiameter_m
                }
            }
            return 0.0
        }

        let annulusSections: [PDFSectionData] = (project.annulus ?? []).sorted { $0.topDepth_m < $1.topDepth_m }.map { ann in
            let holeID = ann.innerDiameter_m
            // Get pipe OD from drill string at midpoint of annulus section
            let midDepth = (ann.topDepth_m + ann.bottomDepth_m) / 2.0
            let pipeOD = pipeODAtDepth(midDepth)
            let capacity = .pi * (holeID * holeID - pipeOD * pipeOD) / 4.0  // m³/m (annular capacity)
            return PDFSectionData(
                name: ann.name,
                topMD: ann.topDepth_m,
                bottomMD: ann.bottomDepth_m,
                length: ann.length_m,
                innerDiameter: holeID,
                outerDiameter: pipeOD,
                capacity_m3_per_m: capacity,
                displacement_m3_per_m: 0,  // Not applicable for annulus
                totalVolume: capacity * ann.length_m
            )
        }

        var reportData = TripSimulationReportData(
            wellName: project.well?.name ?? "Unknown Well",
            projectName: project.name,
            generatedDate: Date(),
            startMD: viewmodel.startBitMD_m,
            endMD: viewmodel.endMD_m,
            controlMD: viewmodel.shoeMD_m,
            stepSize: viewmodel.step_m,
            baseMudDensity: actualBaseMudDensity,
            backfillDensity: actualBackfillDensity,
            targetESD: viewmodel.targetESDAtTD_kgpm3,
            crackFloat: viewmodel.crackFloat_kPa,
            initialSABP: actualInitialSABP,
            holdSABPOpen: viewmodel.holdSABPOpen,
            tripSpeed: project.settings.tripSpeed_m_per_s * 60, // Convert to m/min
            useObservedPitGain: viewmodel.useObservedPitGain,
            observedPitGain: viewmodel.useObservedPitGain ? viewmodel.observedInitialPitGain_m3 : nil,
            drillStringSections: drillStringSections,
            annulusSections: annulusSections,
            steps: viewmodel.steps
        )

        // Add final fluid layers from Mud Placement view
        if let finalLayers = project.finalLayers {
            reportData.finalFluidLayers = finalLayers.map { layer in
                FinalFluidLayerData(
                    name: layer.name,
                    placement: layer.placement,
                    topMD: layer.topMD_m,
                    bottomMD: layer.bottomMD_m,
                    density_kgm3: layer.density_kgm3,
                    colorR: layer.colorR,
                    colorG: layer.colorG,
                    colorB: layer.colorB,
                    colorA: layer.colorA
                )
            }
        }

        let wellName = (project.well?.name ?? "Trip").replacingOccurrences(of: " ", with: "_")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStr = dateFormatter.string(from: Date())
        let defaultName = "TripSimulation_\(wellName)_\(dateStr).pdf"

        // Generate PDF asynchronously using WebKit
        TripSimulationPDFGenerator.shared.generatePDFAsync(for: reportData) { pdfData in
            guard let pdfData = pdfData else {
                self.exportErrorMessage = "Failed to generate PDF report."
                self.showingExportErrorAlert = true
                return
            }

            Task {
                let success = await FileService.shared.saveFile(
                    data: pdfData,
                    defaultName: defaultName,
                    allowedFileTypes: ["pdf"]
                )

                if !success {
                    await MainActor.run {
                        self.exportErrorMessage = "Failed to save PDF report."
                        self.showingExportErrorAlert = true
                    }
                }
            }
        }
    }

    // MARK: - Export HTML Report
    private func exportHTMLReport() {
        guard !viewmodel.steps.isEmpty else {
            exportErrorMessage = "Run simulation first before exporting."
            showingExportErrorAlert = true
            return
        }

        let reportData = buildReportData()
        let htmlContent = TripSimulationHTMLGenerator.shared.generateHTML(for: reportData)

        let wellName = (project.well?.name ?? "Trip").replacingOccurrences(of: " ", with: "_")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStr = dateFormatter.string(from: Date())
        let defaultName = "TripSimulation_\(wellName)_\(dateStr).html"

        Task {
            let success = await FileService.shared.saveTextFile(
                text: htmlContent,
                defaultName: defaultName,
                allowedFileTypes: ["html"]
            )

            if !success {
                await MainActor.run {
                    exportErrorMessage = "Failed to save HTML report."
                    showingExportErrorAlert = true
                }
            }
        }
    }

    // MARK: - Export Zipped HTML Report
    private func exportZippedHTMLReport() {
        guard !viewmodel.steps.isEmpty else {
            exportErrorMessage = "Run simulation first before exporting."
            showingExportErrorAlert = true
            return
        }

        let reportData = buildReportData()
        let htmlContent = TripSimulationHTMLGenerator.shared.generateHTML(for: reportData)

        let wellName = (project.well?.name ?? "Trip").replacingOccurrences(of: " ", with: "_")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStr = dateFormatter.string(from: Date())
        let baseName = "TripSimulation_\(wellName)_\(dateStr)"

        #if os(macOS)
        Task {
            let success = await HTMLZipExporter.shared.exportZipped(
                htmlContent: htmlContent,
                htmlFileName: "\(baseName).html",
                zipFileName: "\(baseName).zip"
            )

            if !success {
                await MainActor.run {
                    exportErrorMessage = "Failed to save zipped report."
                    showingExportErrorAlert = true
                }
            }
        }
        #endif
    }

    // MARK: - Build Report Data Helper
    private func buildReportData() -> TripSimulationReportData {
        // Get actual mud densities from project (matches simulation logic)
        let backfillMud = viewmodel.backfillMudID.flatMap { id in (project.muds ?? []).first(where: { $0.id == id }) }
        let actualBackfillDensity = backfillMud?.density_kgm3 ?? viewmodel.backfillDensity_kgpm3
        let actualBaseMudDensity = project.activeMud?.density_kgm3 ?? viewmodel.baseMudDensity_kgpm3

        // Get actual initial SABP from first simulation step (not the input value)
        let actualInitialSABP = viewmodel.steps.first?.SABP_kPa ?? viewmodel.initialSABP_kPa

        let drillStringSections: [PDFSectionData] = (project.drillString ?? []).sorted { $0.topDepth_m < $1.topDepth_m }.map { ds in
            let id = ds.innerDiameter_m
            let od = ds.outerDiameter_m
            let capacity = .pi * (id * id) / 4.0
            let displacement = .pi * (od * od - id * id) / 4.0
            return PDFSectionData(
                name: ds.name,
                topMD: ds.topDepth_m,
                bottomMD: ds.bottomDepth_m,
                length: ds.length_m,
                innerDiameter: id,
                outerDiameter: od,
                capacity_m3_per_m: capacity,
                displacement_m3_per_m: displacement,
                totalVolume: capacity * ds.length_m
            )
        }

        let drillStringSorted = (project.drillString ?? []).sorted { $0.topDepth_m < $1.topDepth_m }
        func pipeODAtDepth(_ md: Double) -> Double {
            for ds in drillStringSorted {
                if ds.topDepth_m <= md && md <= ds.bottomDepth_m {
                    return ds.outerDiameter_m
                }
            }
            return 0.0
        }

        let annulusSections: [PDFSectionData] = (project.annulus ?? []).sorted { $0.topDepth_m < $1.topDepth_m }.map { ann in
            let holeID = ann.innerDiameter_m
            let midDepth = (ann.topDepth_m + ann.bottomDepth_m) / 2.0
            let pipeOD = pipeODAtDepth(midDepth)
            let capacity = .pi * (holeID * holeID - pipeOD * pipeOD) / 4.0
            return PDFSectionData(
                name: ann.name,
                topMD: ann.topDepth_m,
                bottomMD: ann.bottomDepth_m,
                length: ann.length_m,
                innerDiameter: holeID,
                outerDiameter: pipeOD,
                capacity_m3_per_m: capacity,
                displacement_m3_per_m: 0,
                totalVolume: capacity * ann.length_m
            )
        }

        // Get mud names
        let baseMudName = project.activeMud?.name ?? "Active Mud"
        let backfillMudName = backfillMud?.name ?? baseMudName

        var reportData = TripSimulationReportData(
            wellName: project.well?.name ?? "Unknown Well",
            projectName: project.name,
            generatedDate: Date(),
            startMD: viewmodel.startBitMD_m,
            endMD: viewmodel.endMD_m,
            controlMD: viewmodel.shoeMD_m,
            stepSize: viewmodel.step_m,
            baseMudDensity: actualBaseMudDensity,
            backfillDensity: actualBackfillDensity,
            targetESD: viewmodel.targetESDAtTD_kgpm3,
            crackFloat: viewmodel.crackFloat_kPa,
            initialSABP: actualInitialSABP,
            holdSABPOpen: viewmodel.holdSABPOpen,
            tripSpeed: project.settings.tripSpeed_m_per_s * 60,
            useObservedPitGain: viewmodel.useObservedPitGain,
            observedPitGain: viewmodel.useObservedPitGain ? viewmodel.observedInitialPitGain_m3 : nil,
            drillStringSections: drillStringSections,
            annulusSections: annulusSections,
            steps: viewmodel.steps
        )

        // Add mud info
        reportData.baseMudName = baseMudName
        reportData.backfillMudName = backfillMudName
        reportData.switchToActiveAfterDisplacement = viewmodel.switchToActiveAfterDisplacement
        reportData.displacementSwitchVolume = viewmodel.effectiveDisplacementVolume_m3

        // Find slug mud - heaviest mud in string at start of trip
        if let firstStep = viewmodel.steps.first {
            let stringLayers = firstStep.layersString
            if let heaviestLayer = stringLayers.max(by: { $0.rho_kgpm3 < $1.rho_kgpm3 }),
               heaviestLayer.rho_kgpm3 > actualBaseMudDensity + 10 {  // Only if significantly heavier than base
                // Calculate volume of this layer
                let layerDepth = heaviestLayer.bottomMD - heaviestLayer.topMD
                // Find matching mud by density
                if let slugMud = (project.muds ?? []).first(where: { abs($0.density_kgm3 - heaviestLayer.rho_kgpm3) < 5 }) {
                    reportData.slugMudName = slugMud.name
                    reportData.slugMudDensity = slugMud.density_kgm3
                    // Estimate volume from string geometry
                    let avgCapacity = reportData.totalStringCapacity / max(1, viewmodel.startBitMD_m)
                    reportData.slugMudVolume = layerDepth * avgCapacity
                } else {
                    reportData.slugMudName = "Slug"
                    reportData.slugMudDensity = heaviestLayer.rho_kgpm3
                    let avgCapacity = reportData.totalStringCapacity / max(1, viewmodel.startBitMD_m)
                    reportData.slugMudVolume = layerDepth * avgCapacity
                }
            }
        }

        // Add final fluid layers from Mud Placement view
        if let finalLayers = project.finalLayers {
            reportData.finalFluidLayers = finalLayers.map { layer in
                FinalFluidLayerData(
                    name: layer.name,
                    placement: layer.placement,
                    topMD: layer.topMD_m,
                    bottomMD: layer.bottomMD_m,
                    density_kgm3: layer.density_kgm3,
                    colorR: layer.colorR,
                    colorG: layer.colorG,
                    colorB: layer.colorB,
                    colorA: layer.colorA
                )
            }
        }

        return reportData
    }

    // MARK: - Export Project JSON Feature
    private func exportProjectJSON() {
        // Obtain the JSON string from the project
        guard let jsonString = project.exportJSON() else {
            exportErrorMessage = "Failed to generate project JSON."
            showingExportErrorAlert = true
            return
        }

        Task {
            let success = await FileService.shared.saveTextFile(
                text: jsonString,
                defaultName: "ProjectExport.json",
                allowedFileTypes: ["json"]
            )

            if !success {
                await MainActor.run {
                    exportErrorMessage = "Failed to export project JSON."
                    showingExportErrorAlert = true
                }
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            // Provenance banner
            if let desc = viewmodel.importedStateDescription {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Continuing from: \(desc)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        viewmodel.importedStateDescription = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.blue.opacity(0.06))
            }

            GeometryReader { geo in
            HStack(spacing: 12) {
                // LEFT COLUMN: Steps (top) + Details (bottom when shown)
                GeometryReader { g in
                    VStack(spacing: 8) {
                        stepsTable
                            .frame(height: viewmodel.showDetails ? max(0, g.size.height * 0.5 - 4) : g.size.height)
                        if viewmodel.showDetails {
                            ScrollView {
                                detailAccordion
                            }
                            .frame(height: max(0, g.size.height * 0.5 - 4))
                        } else {
                            // Reserve 0 height when hidden
                            Color.clear.frame(height: 0)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(maxHeight: .infinity)

                Divider()

                // RIGHT COLUMN: Well image (own column) + ESD@control label
                VStack(alignment: .center, spacing: 4) {
                    visualization
                        .frame(maxHeight: .infinity)
                    if !esdAtControlText.isEmpty {
                        Text(esdAtControlText)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .padding(.top, 4)
                    }
                }
                // Give the visualization about 1/3 of the available width, but don't let it get too narrow
                .frame(width: max(220, geo.size.width / 3.8))
                .frame(maxHeight: .infinity)
            }
        }
        } // VStack (provenance banner + content)
    }

    // MARK: - Selection helpers
    private func indexOf(_ row: TripStep) -> Int? {
        // Heuristic: match by MD & TVD (good enough for selection)
        viewmodel.steps.firstIndex { $0.bitMD_m == row.bitMD_m && $0.bitTVD_m == row.bitTVD_m }
    }

    private func selectableText(_ text: String, for row: TripStep, alignment: Alignment = .leading) -> some View {
        Text(text)
            .frame(maxWidth: .infinity, alignment: alignment)
            .contentShape(Rectangle())
            .onTapGesture {
                if let i = indexOf(row) { viewmodel.selectedIndex = i }
            }
    }

    // MARK: - Steps Table
    private var stepsTable: some View {
        Table(viewmodel.steps) {
            TableColumn("Bit MD") { row in
                Text(format0(row.bitMD_m))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { if let i = indexOf(row) { viewmodel.selectedIndex = i } }
            }
            .width(min: 60, ideal: 70, max: 90)

            TableColumn("Bit TVD") { row in
                selectableText(format0(row.bitTVD_m), for: row)
            }
            .width(min: 60, ideal: 70, max: 90)

            TableColumn("Static SABP") { row in
                selectableText(format0(row.SABP_kPa), for: row)
            }
            .width(min: 70, ideal: 85, max: 100)

            TableColumn("Dynamic SABP") { row in
                selectableText(format0(row.SABP_Dynamic_kPa), for: row)
            }
            .width(min: 70, ideal: 85, max: 100)

            TableColumn("ESD@TD") { row in
                selectableText(format0(row.ESDatTD_kgpm3), for: row)
            }
            .width(min: 70, ideal: 85, max: 100)

            TableColumn("DP Wet") { row in
                selectableText(format3(row.expectedFillIfClosed_m3), for: row)
            }
            .width(min: 70, ideal: 85, max: 100)

            TableColumn("DP Dry") { row in
                selectableText(format3(row.expectedFillIfOpen_m3), for: row)
            }
            .width(min: 70, ideal: 85, max: 100)

            TableColumn("Actual") { row in
                selectableText(format3(row.stepBackfill_m3), for: row)
            }
            .width(min: 70, ideal: 85, max: 100)

            TableColumn("Tank Δ") { row in
                let delta = row.cumulativeSurfaceTankDelta_m3
                let color: Color = delta >= 0 ? .green : .red
                Text(String(format: "%+.2f", delta))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .contentShape(Rectangle())
                    .onTapGesture { if let i = indexOf(row) { viewmodel.selectedIndex = i } }
            }
            .width(min: 70, ideal: 85, max: 100)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contextMenu {
            Button("Re-run") { viewmodel.runSimulation(project: project) }

            if viewmodel.selectedIndex != nil {
                Divider()
                Button("Circulate Here") {
                    activeSheet = .circulation
                }
                Button("Pump Schedule") {
                    openPumpScheduleSheet()
                }
                Button("Trip In from Here") {
                    handoffToTripIn()
                }
            }
        }
    }

    // MARK: - Visualization
    private var visualization: some View {
        GroupBox("Well Snapshot") {
            GeometryReader { geo in
                Group {
                    if let idx = viewmodel.selectedIndex, viewmodel.steps.indices.contains(idx) {
                        let s = viewmodel.steps[idx]
                        let ann = s.layersAnnulus
                        let str = s.layersString
                        let pocket = s.layersPocket
                        let bitMD = s.bitMD_m

                        Canvas { ctx, size in
                            // Three-column layout: Annulus | String | Annulus
                            let gap: CGFloat = 8
                            let colW = (size.width - 2*gap) / 3
                            let annLeft  = CGRect(x: 0, y: 0, width: colW, height: size.height)
                            let strRect  = CGRect(x: colW + gap, y: 0, width: colW, height: size.height)
                            let annRight = CGRect(x: 2*(colW + gap), y: 0, width: colW, height: size.height)

                            // Unified vertical scale by MD (surface at top, deeper down)
                            let maxPocketMD = pocket.map { $0.bottomMD }.max() ?? bitMD
                            let globalMaxMD = max(bitMD, maxPocketMD)
                            func yGlobal(_ md: Double) -> CGFloat {
                                guard globalMaxMD > 0 else { return 0 }
                                return CGFloat(md / globalMaxMD) * size.height
                            }

                            // Draw annulus (left & right) and string (center), only above bit
                            drawColumn(&ctx, rows: ann, in: annLeft,  isAnnulus: true,  bitMD: bitMD, yGlobal: yGlobal)
                            drawColumn(&ctx, rows: str, in: strRect,  isAnnulus: false, bitMD: bitMD, yGlobal: yGlobal)
                            drawColumn(&ctx, rows: ann, in: annRight, isAnnulus: true,  bitMD: bitMD, yGlobal: yGlobal)

                            // Pocket (below bit): draw FULL WIDTH so it covers both tracks
                            if !pocket.isEmpty {
                                for r in pocket {
                                    let yTop = yGlobal(r.topMD)
                                    let yBot = yGlobal(r.bottomMD)
                                    let yMin = min(yTop, yBot)
                                    let col = fillColor(rho: r.rho_kgpm3, explicit: r.color, mdMid: 0.5 * (r.topMD + r.bottomMD), isAnnulus: false)
                                    // Snap + tiny overlap to hide hairlines
                                    let top = floor(yMin)
                                    let bottom = ceil(max(yTop, yBot))
                                    var sub = CGRect(x: 0, y: top, width: size.width, height: max(1, bottom - top))
                                    sub = sub.insetBy(dx: 0, dy: -0.25)
                                    ctx.fill(Path(sub), with: .color(col))
                                }
                            }

                            // Headers
                            ctx.draw(Text("Annulus"), at: CGPoint(x: annLeft.midX,  y: 12))
                            ctx.draw(Text("String"),  at: CGPoint(x: strRect.midX,  y: 12))
                            ctx.draw(Text("Annulus"), at: CGPoint(x: annRight.midX, y: 12))

                            // Bit marker
                            let yBit = yGlobal(bitMD)
                            ctx.fill(Path(CGRect(x: 0, y: yBit - 0.5, width: size.width, height: 1)), with: .color(.accentColor.opacity(0.9)))

                            // Depth ticks (MD right, TVD left)
                            let tickCount = 6
                            for i in 0...tickCount {
                                let md = Double(i) / Double(tickCount) * globalMaxMD
                                let yy = yGlobal(md)
                                let tvd = tvdSampler.tvd(of: md)
                                ctx.fill(Path(CGRect(x: size.width - 10, y: yy - 0.5, width: 10, height: 1)), with: .color(.secondary))
                                ctx.draw(Text(String(format: "%.0f", md)), at: CGPoint(x: size.width - 12, y: yy - 6), anchor: .trailing)
                                ctx.fill(Path(CGRect(x: 0, y: yy - 0.5, width: 10, height: 1)), with: .color(.secondary))
                                ctx.draw(Text(String(format: "%.0f", tvd)), at: CGPoint(x: 12, y: yy - 6), anchor: .leading)
                            }
                        }
                    } else {
                        ContentUnavailableView("Select a step", systemImage: "cursorarrow.click", description: Text("Choose a row on the left to see the well snapshot."))
                    }
                }
            }
            .frame(minHeight: 240)
        }
    }
    // MARK: - ESD @ Control MD (label)
    private var esdAtControlText: String {
        guard let idx = viewmodel.selectedIndex, viewmodel.steps.indices.contains(idx) else { return "" }
        let s = viewmodel.steps[idx]
        let rawControlMD = max(0.0, viewmodel.shoeMD_m)
        let clampedControlMD = min(rawControlMD, controlMDLimit)
        let controlTVD = tvdSampler.tvd(of: clampedControlMD)
        let bitTVD = s.bitTVD_m
        var pressure_kPa: Double = s.SABP_kPa

        // annMax/dsMax computed but currently unused - reserved for future geometry validation
        _ = (project.annulus ?? []).map { $0.bottomDepth_m }.max() ?? 0
        _ = (project.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0

        if controlTVD <= bitTVD + 1e-9 {
            var remaining = controlTVD
            for r in s.layersAnnulus where r.bottomTVD > r.topTVD {
                let seg = min(remaining, max(0.0, min(r.bottomTVD, controlTVD) - r.topTVD))
                if seg > 1e-9 {
                    let frac = seg / max(1e-9, r.bottomTVD - r.topTVD)
                    pressure_kPa += r.deltaHydroStatic_kPa * frac
                    remaining -= seg
                    if remaining <= 1e-9 { break }
                }
            }
        } else {
            var remainingA = bitTVD
            for r in s.layersAnnulus where r.bottomTVD > r.topTVD {
                let seg = min(remainingA, max(0.0, min(r.bottomTVD, bitTVD) - r.topTVD))
                if seg > 1e-9 {
                    let frac = seg / max(1e-9, r.bottomTVD - r.topTVD)
                    pressure_kPa += r.deltaHydroStatic_kPa * frac
                    remainingA -= seg
                    if remainingA <= 1e-9 { break }
                }
            }
            var remainingP = controlTVD - bitTVD
            for r in s.layersPocket where r.bottomTVD > r.topTVD {
                let top = max(r.topTVD, bitTVD)
                let bot = min(r.bottomTVD, controlTVD)
                let seg = max(0.0, bot - top)
                if seg > 1e-9 {
                    let frac = seg / max(1e-9, r.bottomTVD - r.topTVD)
                    pressure_kPa += r.deltaHydroStatic_kPa * frac
                    remainingP -= seg
                    if remainingP <= 1e-9 { break }
                }
            }
        }

        let esdAtControl = pressure_kPa / 0.00981 / max(1e-9, controlTVD)
        return String(format: "ESD@control: %.1f kg/m³", esdAtControl)
    }

    // MARK: - Drawing helpers
    private func hexColor(_ hex: String) -> Color? {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard (h.count == 6 || h.count == 8), let val = UInt64(h, radix: 16) else { return nil }
        let a, r, g, b: Double
        if h.count == 8 {
            a = Double((val >> 24) & 0xFF) / 255.0
            r = Double((val >> 16) & 0xFF) / 255.0
            g = Double((val >> 8)  & 0xFF) / 255.0
            b = Double(val & 0xFF) / 255.0
        } else {
            a = 1.0
            r = Double((val >> 16) & 0xFF) / 255.0
            g = Double((val >> 8)  & 0xFF) / 255.0
            b = Double(val & 0xFF) / 255.0
        }
        return Color(red: r, green: g, blue: b, opacity: a)
    }

    private func compositionColor(at md: Double, isAnnulus: Bool) -> Color? {
        let src = isAnnulus ? project.finalAnnulusLayersSorted : project.finalStringLayersSorted
        guard let lay = src.first(where: { md >= $0.topMD_m && md <= $0.bottomMD_m }) else { return nil }
        // Support either a stored hex String or a SwiftUI Color in the model
        let anyVal: Any? = lay.color
        if let hex = anyVal as? String, let c = hexColor(hex) { return c }
        if let c = anyVal as? Color { return c }
        return nil
    }

    private func fillColor(rho: Double, explicit: NumericalTripModel.ColorRGBA?, mdMid: Double, isAnnulus: Bool) -> Color {
        // Air (rho ~1.2) gets a distinct light blue color
        if rho < 10 {
            return Color(red: 0.7, green: 0.85, blue: 1.0, opacity: 0.8)
        }
        // Always use explicit color if provided (from mud definition)
        if let c = explicit { return Color(red: c.r, green: c.g, blue: c.b, opacity: c.a) }
        // If colorByComposition enabled, try to get from initial layer definitions
        if viewmodel.colorByComposition {
            if let c = compositionColor(at: mdMid, isAnnulus: isAnnulus) { return c }
        }
        // Fallback to density-based greyscale
        let t = min(max((rho - 800) / 1200, 0), 1)
        return Color(white: 0.3 + 0.6 * t)
    }

    private func drawColumn(_ ctx: inout GraphicsContext,
                            rows: [LayerRow],
                            in rect: CGRect,
                            isAnnulus: Bool,
                            bitMD: Double,
                            yGlobal: (Double)->CGFloat) {
        for r in rows where r.bottomMD <= bitMD {
            let yTop = yGlobal(r.topMD)
            let yBot = yGlobal(r.bottomMD)
            let yMin = min(yTop, yBot)
            let h = max(1, abs(yBot - yTop))
            let sub = CGRect(x: rect.minX, y: yMin, width: rect.width, height: h)
            let mdMid = 0.5 * (r.topMD + r.bottomMD)
            let col = fillColor(rho: r.rho_kgpm3, explicit: r.color, mdMid: mdMid, isAnnulus: isAnnulus)
            ctx.fill(Path(sub), with: .color(col))
        }
        ctx.stroke(Path(rect), with: .color(.black.opacity(0.8)), lineWidth: 1)
    }

    // MARK: - Detail (Accordion)
    private var detailAccordion: some View {
        GroupBox("Step details") {
            if let idx = viewmodel.selectedIndex, viewmodel.steps.indices.contains(idx) {
                let s = viewmodel.steps[idx]
                VStack(alignment: .leading, spacing: 8) {
                    DisclosureGroup("Summary") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            gridRow("Bit MD", format0(s.bitMD_m))
                            gridRow("Bit TVD", format0(s.bitTVD_m))
                            gridRow("SABP (kPa)", format0(s.SABP_kPa))
                            gridRow("SABP Dynamic (kPa)", format0(s.SABP_Dynamic_kPa))
                            gridRow("Target ESD@TD (kg/m³)", format0(viewmodel.targetESDAtTD_kgpm3))
                            gridRow("ESD@TD (kg/m³)", format0(s.ESDatTD_kgpm3))
                            gridRow("Backfill remaining (m³)", format3(s.backfillRemaining_m3))
                        }
                        .padding(.top, 4)
                    }
                    .disclosureGroupStyle(.automatic)

                    DisclosureGroup("Annulus stack (above bit)") {
                        layerTable(s.layersAnnulus)
                    }
                    DisclosureGroup("String stack (above bit)") {
                        layerTable(s.layersString)
                    }
                    DisclosureGroup("Pocket (below bit)") {
                        layerTable(s.layersPocket)
                    }
                    DisclosureGroup("Volume Tracking") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            GridRow {
                                Text("Float State").foregroundStyle(.secondary)
                                Text(s.floatState)
                                    .fontWeight(.medium)
                                    .foregroundStyle(s.floatState.contains("OPEN") ? .orange : .green)
                            }
                            Divider()
                            GridRow {
                                Text("This Step").foregroundStyle(.secondary).fontWeight(.semibold)
                                Text("")
                            }
                            gridRow("Backfill pumped", format3(s.stepBackfill_m3) + " m³")
                            gridRow("Pit gain (overflow)", format3(s.pitGain_m3) + " m³")
                            gridRow("Tank change", formatSigned3(s.surfaceTankDelta_m3) + " m³")
                            gridRow("Expected if CLOSED", format3(s.expectedFillIfClosed_m3) + " m³")
                            gridRow("Expected if OPEN", format3(s.expectedFillIfOpen_m3) + " m³")
                            Divider()
                            GridRow {
                                Text("Cumulative").foregroundStyle(.secondary).fontWeight(.semibold)
                                Text("")
                            }
                            gridRow("Total backfill", format3(s.cumulativeBackfill_m3) + " m³")
                            gridRow("Total pit gain", format3(s.cumulativePitGain_m3) + " m³")
                            GridRow {
                                Text("Net tank change").foregroundStyle(.secondary)
                                Text(formatSigned3(s.cumulativeSurfaceTankDelta_m3) + " m³")
                                    .fontWeight(.bold)
                                    .foregroundStyle(s.cumulativeSurfaceTankDelta_m3 >= 0 ? .green : .red)
                            }
                            gridRow("Slug contribution", format3(s.cumulativeSlugContribution_m3) + " m³")
                        }
                        .padding(.top, 4)
                    }
                    DisclosureGroup("Pocket Mud Inventory") {
                        VStack(alignment: .leading, spacing: 8) {
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                                GridRow {
                                    Text("Source Contributions").foregroundStyle(.secondary).fontWeight(.semibold)
                                    Text("")
                                }
                                ForEach(s.pocketSourceInventory) { entry in
                                    gridRow("\(format0(entry.density_kgpm3)) kg/m³", format3(entry.volume_m3) + " m³")
                                }
                            }
                            Divider()
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                                GridRow {
                                    Text("Pocket Hydrostatic").foregroundStyle(.secondary).fontWeight(.semibold)
                                    Text("")
                                    Text("")
                                }
                                GridRow {
                                    Text("Density").font(.caption).foregroundStyle(.secondary)
                                    Text("TVD Height").font(.caption).foregroundStyle(.secondary)
                                    Text("Hydrostatic").font(.caption).foregroundStyle(.secondary)
                                }
                                ForEach(s.pocketHydrostaticSummary) { entry in
                                    GridRow {
                                        Text("\(format0(entry.density_kgpm3)) kg/m³")
                                        Text(format1(entry.tvdHeight_m) + " m")
                                        Text(format0(entry.hydrostatic_kPa) + " kPa")
                                    }
                                }
                                Divider()
                                GridRow {
                                    Text("Total").fontWeight(.semibold)
                                    Text(format1(s.pocketHydrostaticSummary.reduce(0) { $0 + $1.tvdHeight_m }) + " m")
                                        .fontWeight(.semibold)
                                    Text(format0(s.pocketHydrostaticSummary.reduce(0) { $0 + $1.hydrostatic_kPa }) + " kPa")
                                        .fontWeight(.semibold)
                                }
                            }
                            if viewmodel.shoeMD_m > 0 {
                                let controlSummary = s.hydrostaticToControl(controlTVD: controlTVD)
                                if !controlSummary.isEmpty {
                                    Divider()
                                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                                        GridRow {
                                            Text("HP to Control (\(format0(controlTVD)) m TVD)").foregroundStyle(.secondary).fontWeight(.semibold)
                                            Text("")
                                            Text("")
                                        }
                                        GridRow {
                                            Text("Density").font(.caption).foregroundStyle(.secondary)
                                            Text("TVD Height").font(.caption).foregroundStyle(.secondary)
                                            Text("Hydrostatic").font(.caption).foregroundStyle(.secondary)
                                        }
                                        ForEach(controlSummary) { entry in
                                            GridRow {
                                                Text("\(format0(entry.density_kgpm3)) kg/m³")
                                                Text(format1(entry.tvdHeight_m) + " m")
                                                Text(format0(entry.hydrostatic_kPa) + " kPa")
                                            }
                                        }
                                        Divider()
                                        GridRow {
                                            Text("Total").fontWeight(.semibold)
                                            Text(format1(controlSummary.reduce(0) { $0 + $1.tvdHeight_m }) + " m")
                                                .fontWeight(.semibold)
                                            Text(format0(controlSummary.reduce(0) { $0 + $1.hydrostatic_kPa }) + " kPa")
                                                .fontWeight(.semibold)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    DisclosureGroup("ESD@control debug") {
                        let rows = esdDebugRows(project: project, step: s)
                        debugTable(rows)
                    }

                    DisclosureGroup("Field Adjustment (Ballooning)") {
                        VStack(alignment: .leading, spacing: 8) {
                            // Read-only context
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                                gridRow("Simulated Kill Vol", format3(s.cumulativeBackfill_m3) + " m³")
                                gridRow("Kill ρ", format0(viewmodel.backfillDensity_kgpm3) + " kg/m³")
                                gridRow("Base ρ", format0(viewmodel.baseMudDensity_kgpm3) + " kg/m³")
                            }

                            Divider()

                            // User input
                            HStack(spacing: 8) {
                                Text("Actual Kill Mud Vol:")
                                    .foregroundStyle(.secondary)
                                NumericTextField(
                                    placeholder: "m³",
                                    value: $viewmodel.ballooningActualVolume_m3,
                                    fractionDigits: 3
                                )
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                                Text("m³")
                                    .foregroundStyle(.secondary)
                            }
                            .onChange(of: viewmodel.ballooningActualVolume_m3) { _, _ in
                                viewmodel.recalculateBallooning(project: project)
                            }

                            // Results
                            if let r = viewmodel.ballooningResult, r.volumeDeficit_m3 > 0.001 {
                                Divider()
                                HStack(spacing: 12) {
                                    // Hold SABP
                                    VStack(spacing: 2) {
                                        Text("Hold SABP")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(format0(r.adjustedSABP_kPa) + " kPa")
                                            .font(.headline)
                                            .foregroundStyle(.orange)
                                            .fontWeight(.bold)
                                    }
                                    .frame(maxWidth: .infinity)

                                    // Extra SABP
                                    VStack(spacing: 2) {
                                        Text("Extra SABP")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text("+" + format0(r.deltaSABP_kPa) + " kPa")
                                            .font(.headline)
                                            .foregroundStyle(.red)
                                    }
                                    .frame(maxWidth: .infinity)

                                    // Pump to Recover
                                    VStack(spacing: 2) {
                                        Text("Pump to Recover")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(format3(r.volumeDeficit_m3) + " m³")
                                            .font(.headline)
                                            .foregroundStyle(.blue)
                                    }
                                    .frame(maxWidth: .infinity)
                                }

                                // Comparison row
                                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                                    gridRow("Plan SABP", format0(s.SABP_kPa) + " kPa")
                                    gridRow("Hold SABP", format0(r.adjustedSABP_kPa) + " kPa")
                                    gridRow("Deficit TVD Height", format1(r.deficitTVDHeight_m) + " m")
                                }
                                .padding(.top, 4)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            } else {
                Text("No step selected.").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Subviews / helpers
    private func numberField(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .frame(width: 100, alignment: .trailing)
                .lineLimit(1)
            TextField(title, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
        }
    }

    private func gridRow(_ k: String, _ v: String) -> some View {
        GridRow { Text(k).foregroundStyle(.secondary); Text(v) }
    }

    private func layerTable(_ rows: [LayerRow]) -> some View {
        Table(rows) {
            TableColumn("Top MD") { r in Text(format1(r.topMD)) }
            TableColumn("Bot MD") { r in Text(format1(r.bottomMD)) }
            TableColumn("Top TVD") { r in Text(format1(r.topTVD)) }
            TableColumn("Bot TVD") { r in Text(format1(r.bottomTVD)) }
            TableColumn("ρ kg/m³") { r in Text(format0(r.rho_kgpm3)) }
            TableColumn("ΔP kPa") { r in Text(format0(r.deltaHydroStatic_kPa)) }
            TableColumn("Vol m³") { r in Text(format3(r.volume_m3)) }
        }
        .frame(minHeight: 140)
    }

    private func debugTable(_ kvs: [KVRow]) -> some View {
        Table(kvs) {
            TableColumn("Key") { kv in Text(kv.key) }
            TableColumn("Value") { kv in Text(kv.value) }
        }
        .frame(minHeight: 120)
    }

    // Live ESD@control diagnostics
    private func esdDebugRows(project: ProjectState, step s: TripStep) -> [KVRow] {
        let controlMDRaw = max(0.0, viewmodel.shoeMD_m)
        let annMax = (project.annulus ?? []).map { $0.bottomDepth_m }.max() ?? 0
        let dsMax = (project.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0
        let candidates = [annMax, dsMax].filter { $0 > 0 }
        let limit = candidates.min() ?? 0
        let controlMD = min(controlMDRaw, limit)
        let controlTVD = tvdSampler.tvd(of: controlMD)
        let bitTVD = s.bitTVD_m
        let eps = 1e-9
        var pressure_kPa: Double = s.SABP_kPa
        var hydroAnn_kPa = 0.0
        var hydroPocket_kPa = 0.0
        var coveredAnn_m = 0.0
        var coveredPocket_m = 0.0

        if controlTVD <= bitTVD + eps {
            var remaining = controlTVD
            for r in s.layersAnnulus where r.bottomTVD > r.topTVD {
                let seg = min(remaining, max(0.0, min(r.bottomTVD, controlTVD) - r.topTVD))
                if seg > eps {
                    let denom = max(eps, r.bottomTVD - r.topTVD)
                    let frac = seg / denom
                    let dP = r.deltaHydroStatic_kPa * frac
                    hydroAnn_kPa += dP
                    pressure_kPa += dP
                    coveredAnn_m += seg
                    remaining -= seg
                    if remaining <= eps { break }
                }
            }
        } else {
            var remainingA = bitTVD
            for r in s.layersAnnulus where r.bottomTVD > r.topTVD {
                let seg = min(remainingA, max(0.0, min(r.bottomTVD, bitTVD) - r.topTVD))
                if seg > eps {
                    let denom = max(eps, r.bottomTVD - r.topTVD)
                    let frac = seg / denom
                    let dP = r.deltaHydroStatic_kPa * frac
                    hydroAnn_kPa += dP
                    pressure_kPa += dP
                    coveredAnn_m += seg
                    remainingA -= seg
                    if remainingA <= eps { break }
                }
            }
            var remainingP = controlTVD - bitTVD
            for r in s.layersPocket where r.bottomTVD > r.topTVD {
                let top = max(r.topTVD, bitTVD)
                let bot = min(r.bottomTVD, controlTVD)
                let seg = max(0.0, bot - top)
                if seg > eps {
                    let denom = max(eps, r.bottomTVD - r.topTVD)
                    let frac = seg / denom
                    let dP = r.deltaHydroStatic_kPa * frac
                    hydroPocket_kPa += dP
                    pressure_kPa += dP
                    coveredPocket_m += seg
                    remainingP -= seg
                    if remainingP <= eps { break }
                }
            }
        }

        let esdAtControl = pressure_kPa / 0.00981 / max(eps, controlTVD)
        let uniformESD = viewmodel.baseMudDensity_kgpm3 + s.SABP_kPa / (0.00981 * max(eps, controlTVD))
        let coverageMismatch = controlTVD - (coveredAnn_m + coveredPocket_m)

        var rows: [KVRow] = []
        rows.append(KVRow(key: "Control MD (m)", value: format0(controlMD)))
        rows.append(KVRow(key: "Control TVD (m)", value: format0(controlTVD)))
        rows.append(KVRow(key: "Bit TVD (m)", value: format0(bitTVD)))
        rows.append(KVRow(key: "SABP (kPa)", value: format0(s.SABP_kPa)))
        rows.append(KVRow(key: "Hydro annulus (kPa)", value: format0(hydroAnn_kPa)))
        if hydroPocket_kPa > eps {
            rows.append(KVRow(key: "Hydro pocket (kPa)", value: format0(hydroPocket_kPa)))
        }
        rows.append(KVRow(key: "Pressure at control (kPa)", value: format0(pressure_kPa)))
        rows.append(KVRow(key: "ESD@control (kg/m³)", value: format1(esdAtControl)))
        rows.append(KVRow(key: "Uniform ESD (base ρ) (kg/m³)", value: format1(uniformESD)))
        rows.append(KVRow(key: "Covered TVD annulus (m)", value: format1(coveredAnn_m)))
        if coveredPocket_m > eps {
            rows.append(KVRow(key: "Covered TVD pocket (m)", value: format1(coveredPocket_m)))
        }
        rows.append(KVRow(key: "Coverage mismatch (m)", value: format1(coverageMismatch)))
        return rows
    }

    // MARK: - Formatters
    private func format0(_ v: Double) -> String { String(format: "%.0f", v) }
    private func format1(_ v: Double) -> String { String(format: "%.1f", v) }
    private func format3(_ v: Double) -> String { String(format: "%.3f", v) }
    private func formatSigned3(_ v: Double) -> String { String(format: "%+.3f", v) }

    // Clamp Control MD to not exceed geometry
    private var controlMDLimit: Double {
        let annMax = (project.annulus ?? []).map { $0.bottomDepth_m }.max() ?? 0
        let dsMax = (project.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0
        let candidates = [annMax, dsMax].filter { $0 > 0 }
        return candidates.min() ?? 0
    }

    private var controlMDBinding: Binding<Double> {
        Binding(
            get: { min(max(0, viewmodel.shoeMD_m), controlMDLimit) },
            set: { newVal in
                let clamped = min(max(0, newVal), controlMDLimit)
                viewmodel.shoeMD_m = clamped
            }
        )
    }

    /// TvdSampler that respects the toggle selection
    private var tvdSampler: TvdSampler {
        TvdSampler(project: project, preferPlan: viewmodel.useDirectionalPlanForTVD)
    }

    /// TVD at the control depth
    private var controlTVD: Double {
        let controlMD = min(max(0, viewmodel.shoeMD_m), controlMDLimit)
        return tvdSampler.tvd(of: controlMD)
    }

    /// Bit depth label for circulation sheet header
    private var circulationBitDepthLabel: String {
        guard let idx = viewmodel.selectedIndex, viewmodel.steps.indices.contains(idx) else { return "?" }
        return String(Int(viewmodel.steps[idx].bitMD_m))
    }

    /// TVD at the start depth
    private var startTVD: Double {
        tvdSampler.tvd(of: viewmodel.startBitMD_m)
    }

    /// TVD at the end depth
    private var endTVD: Double {
        tvdSampler.tvd(of: viewmodel.endMD_m)
    }

    private var tripSpeedBinding: Binding<Double> {
        Binding(
            get: { project.settings.tripSpeed_m_per_s },
            set: { project.settings.tripSpeed_m_per_s = $0 }
        )
    }

    // Trip speed in m/min (converts to/from m/s for storage)
    private var tripSpeedBinding_mpm: Binding<Double> {
        Binding(
            get: { project.settings.tripSpeed_m_per_s * 60 },  // m/s -> m/min
            set: { project.settings.tripSpeed_m_per_s = $0 / 60 }  // m/min -> m/s
        )
    }

    private var tripSpeedDirectionText: String {
        project.settings.tripSpeed_m_per_s >= 0
            ? "Positive = Pull out of hole"
            : "Negative = Run in hole"
    }
}


#if DEBUG
private struct TripSimulationPreview: View {
  let container: ModelContainer
  let project: ProjectState

  init() {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    self.container = try! ModelContainer(
      for: ProjectState.self,
           DrillStringSection.self,
           AnnulusSection.self,
           FinalFluidLayer.self,
      configurations: config
    )
    let ctx = container.mainContext
    let p = ProjectState()
    ctx.insert(p)
    // Seed some layers so the visualization has data
    let a1 = FinalFluidLayer(project: p, name: "Annulus Mud", placement: .annulus, topMD_m: 0, bottomMD_m: 3000, density_kgm3: 1260, color: .yellow)
    let s1 = FinalFluidLayer(project: p, name: "String Mud", placement: .string, topMD_m: 0, bottomMD_m: 2000, density_kgm3: 1260, color: .yellow)
    ctx.insert(a1); ctx.insert(s1)
    try? ctx.save()
    self.project = p
  }

  var body: some View {
    NavigationStack { TripSimulationView(project: project) }
      .modelContainer(container)
      .frame(width: 1200, height: 800)
  }
}

#Preview("Trip Simulation – Sample Data") {
  TripSimulationPreview()
}
#endif

