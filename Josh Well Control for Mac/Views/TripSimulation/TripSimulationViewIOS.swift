//  TripSimulationView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-07.
// (assistant) Connected and ready – 2025-11-07
//

#if os(iOS)
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

// MARK: - ViewModel Cache (iOS)

/// Cache to persist TripSimulationViewIOS.ViewModel across view switches
enum TripSimViewModelCacheIOS {
    @MainActor
    private static var cache: [UUID: TripSimulationViewIOS.ViewModel] = [:]

    @MainActor
    static func get(for projectID: UUID) -> TripSimulationViewIOS.ViewModel {
        if let existing = cache[projectID] {
            return existing
        }
        let newVM = TripSimulationViewIOS.ViewModel()
        cache[projectID] = newVM
        return newVM
    }
}

/// A compact SwiftUI front‑end over the NumericalTripModel.
/// Shows inputs, a steps table, an interactive detail (accordion), and a simple 2‑column mud visualization.
struct TripSimulationViewIOS: View {
    // MARK: - Environment
    @Environment(\.modelContext) private var modelContext

    // You typically have a selected project bound in higher views. If not, you can inject a specific instance here.
    @Bindable var project: ProjectState

    @State private var viewmodel: ViewModel
    @State private var showingExportErrorAlert = false
    @State private var exportErrorMessage = ""

    init(project: ProjectState) {
        self.project = project
        _viewmodel = State(initialValue: TripSimViewModelCacheIOS.get(for: project.id))
    }

    // MARK: - Body
    var body: some View {
        GeometryReader { geo in
            let isPortrait = geo.size.height > geo.size.width
            let isNarrow = geo.size.width < 700
            
            if isPortrait || isNarrow {
                // PORTRAIT or NARROW: Stack everything vertically
                portraitLayout(geo: geo)
            } else {
                // LANDSCAPE: Side-by-side layout with visualization on right
                landscapeLayout(geo: geo)
            }
        }
        .onAppear {
            // Only bootstrap if viewmodel is fresh (no steps and no loaded state)
            if viewmodel.steps.isEmpty && viewmodel.startBitMD_m == 0 {
                if !viewmodel.loadSavedInputs(project: project) {
                    viewmodel.bootstrap(from: project)
                }
            }
        }
        .onChange(of: viewmodel.selectedIndex) { _, newVal in
            viewmodel.stepSlider = Double(newVal ?? 0)
        }
        .alert("Export Error", isPresented: $showingExportErrorAlert, actions: { Button("OK", role: .cancel) {} }) {
            Text(exportErrorMessage)
        }
    }
    
    // MARK: - Portrait Layout
    private func portraitLayout(geo: GeometryProxy) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header inputs - compact for portrait
                VStack(alignment: .leading, spacing: 12) {
                    compactHeaderInputs
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                
                Divider()
                
                // Visualization section
                VStack(spacing: 12) {
                    if !viewmodel.steps.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Bit Depth")
                                .font(.headline)
                                .padding(.horizontal, 16)
                            
                            HStack(spacing: 8) {
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
                                Text(String(format: "%.2f m", viewmodel.steps[min(max(viewmodel.selectedIndex ?? 0, 0), max(viewmodel.steps.count - 1, 0))].bitMD_m))
                                    .frame(width: 80, alignment: .trailing)
                                    .monospacedDigit()
                                    .font(.system(.body, design: .monospaced))
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.vertical, 8)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(8)
                        .padding(.horizontal, 16)
                    }
                    
                    visualization
                        .frame(height: 400)
                        .padding(.horizontal, 16)
                    
                    if !esdAtControlText.isEmpty {
                        Text(esdAtControlText)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .cornerRadius(8)
                            .padding(.horizontal, 16)
                    }
                }
                
                Divider()
                
                // Steps table
                VStack(alignment: .leading, spacing: 8) {
                    Text("Trip Steps")
                        .font(.headline)
                        .padding(.horizontal, 16)
                    
                    stepsTable
                        .frame(height: 300)
                        .padding(.horizontal, 16)
                }
                
                // Details accordion
                if viewmodel.showDetails {
                    VStack(alignment: .leading, spacing: 8) {
                        detailAccordion
                            .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }
    
    // MARK: - Landscape Layout
    private func landscapeLayout(geo: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            // LEFT SIDE: Controls and table (65% width)
            ScrollView {
                VStack(spacing: 16) {
                    headerInputs
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        stepsTable
                            .frame(height: viewmodel.showDetails ? 300 : 450)
                        
                        if viewmodel.showDetails {
                            detailAccordion
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 16)
            }
            .frame(width: geo.size.width * 0.65)
            
            Divider()
            
            // RIGHT SIDE: Visualization (35% width, full height)
            VStack(spacing: 12) {
                if !viewmodel.steps.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bit Depth")
                            .font(.headline)
                        
                        HStack(spacing: 8) {
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
                            Text(String(format: "%.2f m", viewmodel.steps[min(max(viewmodel.selectedIndex ?? 0, 0), max(viewmodel.steps.count - 1, 0))].bitMD_m))
                                .frame(width: 80, alignment: .trailing)
                                .monospacedDigit()
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(8)
                }
                
                visualization
                    .frame(maxHeight: .infinity)
                
                if !esdAtControlText.isEmpty {
                    Text(esdAtControlText)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(width: geo.size.width * 0.35)
        }
    }

    // MARK: - Sections
    
    // MARK: - Compact Header Inputs (for portrait)
    private var compactHeaderInputs: some View {
        VStack(alignment: .leading, spacing: 12) {
            // All inputs in a single group box using LazyVGrid
            GroupBox("Inputs") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 500), spacing: 16)], spacing: 16) {
                    // Bit/Range section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bit / Range")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        VStack(spacing: 6) {
                            startMDField
                            endMDField
                            controlMDField
                            numberField("Step (m)", value: $viewmodel.step_m)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Fluids section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Fluids")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        VStack(spacing: 6) {
                            mudPicker(
                                label: "Base mud",
                                selection: Binding(
                                    get: { project.activeMud?.id },
                                    set: { _ in }
                                ),
                                onSelect: { newID in
                                    if let id = newID, let m = (project.muds ?? []).first(where: { $0.id == id }) {
                                        // Set all muds inactive first
                                        (project.muds ?? []).forEach { $0.isActive = false }
                                        // Set the selected mud as active
                                        m.isActive = true
                                        viewmodel.baseMudDensity_kgpm3 = m.density_kgm3
                                    }
                                }
                            )
                            
                            mudPicker(
                                label: "Backfill mud",
                                selection: $viewmodel.backfillMudID,
                                onSelect: { newID in
                                    let muds = (project.muds ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                                    if let id = newID, let m = muds.first(where: { $0.id == id }) {
                                        viewmodel.backfillDensity_kgpm3 = m.density_kgm3
                                    } else {
                                        viewmodel.backfillDensity_kgpm3 = project.activeMud?.density_kgm3 ?? viewmodel.backfillDensity_kgpm3
                                    }
                                }
                            )
                            
                            numberField("Target ESD@TD", value: $viewmodel.targetESDAtTD_kgpm3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Choke/Float section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choke / Float")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        VStack(spacing: 6) {
                            numberField("Crack Float (kPa)", value: $viewmodel.crackFloat_kPa)
                            numberField("Initial SABP (kPa)", value: $viewmodel.initialSABP_kPa)
                            Toggle("Hold SABP open (0 kPa)", isOn: $viewmodel.holdSABPOpen)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Options & Trip speed
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Options")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        VStack(spacing: 6) {
                            Toggle("Composition colors", isOn: $viewmodel.colorByComposition)

                            Divider()

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Trip speed (m/min)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    TextField("Trip speed", value: tripSpeedBinding_mpm, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                    Text(tripSpeedDirectionText)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Initial Slug Calibration
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Slug Calibration")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        VStack(spacing: 6) {
                            if viewmodel.calculatedInitialPitGain_m3 > 0 {
                                HStack {
                                    Text("Calculated:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(String(format: "%.3f m³", viewmodel.calculatedInitialPitGain_m3))
                                        .monospacedDigit()
                                    Button {
                                        viewmodel.observedInitialPitGain_m3 = viewmodel.calculatedInitialPitGain_m3
                                    } label: {
                                        Image(systemName: "arrow.right.circle")
                                    }
                                }
                            }
                            Toggle("Use observed", isOn: $viewmodel.useObservedPitGain)
                            HStack {
                                TextField("Observed", value: $viewmodel.observedInitialPitGain_m3, format: .number.precision(.fractionLength(3)))
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(!viewmodel.useObservedPitGain)
                                Text("m³")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Action buttons below the group box
            HStack(spacing: 12) {
                Toggle("Show details", isOn: $viewmodel.showDetails)
                    .toggleStyle(.switch)

                Spacer()

                if viewmodel.isRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewmodel.progressMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            ProgressView(value: viewmodel.progressValue)
                                .frame(width: 120)
                        }
                    }
                } else {
                    Button("Run Simulation") {
                        viewmodel.runSimulation(project: project)
                    }
                    .buttonStyle(.borderedProminent)
                }

                // Save inputs button
                Button {
                    viewmodel.saveInputs(project: project, context: modelContext)
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)

                Menu {
                    Button("Export PDF Report") {
                        exportPDFReport()
                    }
                    Button("Export HTML Report") {
                        exportHTMLReport()
                    }
                    Divider()
                    Button("Export Project JSON") {
                        exportProjectJSON()
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var headerInputs: some View {
        VStack(alignment: .leading, spacing: 12) {
            // All inputs in a single group box using LazyVGrid
            GroupBox("Inputs") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16, alignment: .top)], spacing: 16) {
                    // Bit / Range
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bit / Range")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        VStack(spacing: 6) {
                            startMDField
                            endMDField
                            controlMDField
                            numberField("Step (m)", value: $viewmodel.step_m)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Fluids
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Fluids")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        VStack(spacing: 6) {
                            mudPicker(
                                label: "Base mud",
                                selection: Binding(
                                    get: { project.activeMud?.id },
                                    set: { _ in }
                                ),
                                onSelect: { newID in
                                    if let id = newID, let m = (project.muds ?? []).first(where: { $0.id == id }) {
                                        // Set all muds inactive first
                                        (project.muds ?? []).forEach { $0.isActive = false }
                                        // Set the selected mud as active
                                        m.isActive = true
                                        viewmodel.baseMudDensity_kgpm3 = m.density_kgm3
                                    }
                                }
                            )
                            
                            mudPicker(
                                label: "Backfill mud",
                                selection: $viewmodel.backfillMudID,
                                onSelect: { newID in
                                    let muds = (project.muds ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                                    if let id = newID, let m = muds.first(where: { $0.id == id }) {
                                        viewmodel.backfillDensity_kgpm3 = m.density_kgm3
                                    } else {
                                        viewmodel.backfillDensity_kgpm3 = project.activeMud?.density_kgm3 ?? viewmodel.backfillDensity_kgpm3
                                    }
                                }
                            )
                            
                            numberField("Target ESD@TD", value: $viewmodel.targetESDAtTD_kgpm3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Choke / Float
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choke / Float")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        VStack(spacing: 6) {
                            numberField("Crack Float (kPa)", value: $viewmodel.crackFloat_kPa)
                            numberField("Initial SABP (kPa)", value: $viewmodel.initialSABP_kPa)
                            Toggle("Hold SABP open (0 kPa)", isOn: $viewmodel.holdSABPOpen)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Options & Trip speed combined
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Options")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        VStack(spacing: 6) {
                            Toggle("Composition colors", isOn: $viewmodel.colorByComposition)

                            Divider()

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Trip speed (m/min)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    TextField("Trip speed", value: tripSpeedBinding_mpm, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: 120)
                                    Text(tripSpeedDirectionText)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help("Signed trip speed in m/min. Positive values pull out of hole; negative values run in.")

                    // Initial Slug Calibration
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Slug Calibration")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        VStack(spacing: 6) {
                            if viewmodel.calculatedInitialPitGain_m3 > 0 {
                                HStack {
                                    Text("Calculated:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(String(format: "%.3f m³", viewmodel.calculatedInitialPitGain_m3))
                                        .monospacedDigit()
                                    Button {
                                        viewmodel.observedInitialPitGain_m3 = viewmodel.calculatedInitialPitGain_m3
                                    } label: {
                                        Image(systemName: "arrow.right.circle")
                                    }
                                }
                            }
                            Toggle("Use observed", isOn: $viewmodel.useObservedPitGain)
                            HStack {
                                TextField("Observed", value: $viewmodel.observedInitialPitGain_m3, format: .number.precision(.fractionLength(3)))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 80)
                                    .disabled(!viewmodel.useObservedPitGain)
                                Text("m³")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Action buttons below the group box
            HStack(spacing: 12) {
                Toggle("Show details", isOn: $viewmodel.showDetails)
                    .toggleStyle(.switch)

                Spacer()

                if viewmodel.isRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewmodel.progressMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            ProgressView(value: viewmodel.progressValue)
                                .frame(width: 120)
                        }
                    }
                } else {
                    Button("Run Simulation") {
                        viewmodel.runSimulation(project: project)
                    }
                    .buttonStyle(.borderedProminent)
                }

                // Save inputs button
                Button {
                    viewmodel.saveInputs(project: project, context: modelContext)
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)

                Menu {
                    Button("Export PDF Report") {
                        exportPDFReport()
                    }
                    Button("Export HTML Report") {
                        exportHTMLReport()
                    }
                    Divider()
                    Button("Export Project JSON") {
                        exportProjectJSON()
                    }
                } label: {
                    Text("Export")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Export PDF Report
    private func exportPDFReport() {
        guard !viewmodel.steps.isEmpty else {
            exportErrorMessage = "Run simulation first before exporting."
            showingExportErrorAlert = true
            return
        }

        // Get actual backfill density from selected mud (matches simulation logic)
        let backfillMud = viewmodel.backfillMudID.flatMap { id in (project.muds ?? []).first(where: { $0.id == id }) }
        let actualBackfillDensity = backfillMud?.density_kgm3 ?? viewmodel.backfillDensity_kgpm3

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
            baseMudDensity: viewmodel.baseMudDensity_kgpm3,
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

        // Get actual backfill density from selected mud (matches simulation logic)
        let backfillMud2 = viewmodel.backfillMudID.flatMap { id in (project.muds ?? []).first(where: { $0.id == id }) }
        let actualBackfillDensity2 = backfillMud2?.density_kgm3 ?? viewmodel.backfillDensity_kgpm3

        // Get actual initial SABP from first simulation step (not the input value)
        let actualInitialSABP2 = viewmodel.steps.first?.SABP_kPa ?? viewmodel.initialSABP_kPa

        // Build geometry data (same as PDF)
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

        // Helper to find pipe OD from drill string at a given depth
        let drillStringSorted2 = (project.drillString ?? []).sorted { $0.topDepth_m < $1.topDepth_m }
        func pipeODAtDepth2(_ md: Double) -> Double {
            for ds in drillStringSorted2 {
                if ds.topDepth_m <= md && md <= ds.bottomDepth_m {
                    return ds.outerDiameter_m
                }
            }
            return 0.0
        }

        let annulusSections: [PDFSectionData] = (project.annulus ?? []).sorted { $0.topDepth_m < $1.topDepth_m }.map { ann in
            let holeID = ann.innerDiameter_m
            let midDepth = (ann.topDepth_m + ann.bottomDepth_m) / 2.0
            let pipeOD = pipeODAtDepth2(midDepth)
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

        var reportData = TripSimulationReportData(
            wellName: project.well?.name ?? "Unknown Well",
            projectName: project.name,
            generatedDate: Date(),
            startMD: viewmodel.startBitMD_m,
            endMD: viewmodel.endMD_m,
            controlMD: viewmodel.shoeMD_m,
            stepSize: viewmodel.step_m,
            baseMudDensity: viewmodel.baseMudDensity_kgpm3,
            backfillDensity: actualBackfillDensity2,
            targetESD: viewmodel.targetESDAtTD_kgpm3,
            crackFloat: viewmodel.crackFloat_kPa,
            initialSABP: actualInitialSABP2,
            holdSABPOpen: viewmodel.holdSABPOpen,
            tripSpeed: project.settings.tripSpeed_m_per_s * 60,
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
        .contextMenu { Button("Re-run") { viewmodel.runSimulation(project: project) } }
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
                                let tvd = project.tvd(of: md)
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
        let controlTVD = project.tvd(of: clampedControlMD)
        let bitTVD = s.bitTVD_m
        var pressure_kPa: Double = s.SABP_kPa

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
        if viewmodel.colorByComposition {
            if let c = explicit { return Color(red: c.r, green: c.g, blue: c.b, opacity: c.a) }
            if let c = compositionColor(at: mdMid, isAnnulus: isAnnulus) { return c }
        }
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
                    DisclosureGroup("ESD@control debug") {
                        let rows = esdDebugRows(project: project, step: s)
                        debugTable(rows)
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
                .frame(minWidth: 100, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            TextField(title, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 70, maxWidth: 140)
        }
    }
    
    private func mudPicker(label: String, selection: Binding<UUID?>, onSelect: @escaping (UUID?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Picker("", selection: Binding(
                get: { selection.wrappedValue },
                set: { newID in
                    selection.wrappedValue = newID
                    onSelect(newID)
                }
            )) {
                ForEach((project.muds ?? []).sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }), id: \.id) { m in
                    Text("\(m.name): \(format0(m.density_kgm3)) kg/m³").tag(m.id as UUID?)
                }
            }
            .pickerStyle(.menu)
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
        let controlTVD = project.tvd(of: controlMD)
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

    /// TVD at the control depth
    private var controlTVD: Double {
        let controlMD = min(max(0, viewmodel.shoeMD_m), controlMDLimit)
        return project.tvd(of: controlMD)
    }

    /// Start MD field with TVD display
    private var startMDField: some View {
        HStack(spacing: 4) {
            Text("Start MD")
                .frame(minWidth: 100, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            TextField("Start MD", value: $viewmodel.startBitMD_m, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 70, maxWidth: 140)

            Text("(\(Int(startTVD)) TVD)")
                .font(.caption)
                .foregroundStyle(.blue)
        }
    }

    /// End MD field with TVD display
    private var endMDField: some View {
        HStack(spacing: 4) {
            Text("End MD")
                .frame(minWidth: 100, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            TextField("End MD", value: $viewmodel.endMD_m, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 70, maxWidth: 140)

            Text("(\(Int(endTVD)) TVD)")
                .font(.caption)
                .foregroundStyle(.blue)
        }
    }

    /// Control MD field with TVD display
    private var controlMDField: some View {
        HStack(spacing: 4) {
            Text("Control MD")
                .frame(minWidth: 100, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            TextField("Control MD", value: controlMDBinding, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 70, maxWidth: 140)

            Text("(\(Int(controlTVD)) TVD)")
                .font(.caption)
                .foregroundStyle(.blue)
        }
    }

    /// TVD at the start depth
    private var startTVD: Double {
        project.tvd(of: viewmodel.startBitMD_m)
    }

    /// TVD at the end depth
    private var endTVD: Double {
        project.tvd(of: viewmodel.endMD_m)
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
private struct TripSimulationViewIOSPreview: View {
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
    NavigationStack { TripSimulationViewIOS(project: project) }
      .modelContainer(container)
  }
}

#Preview("iPad Landscape", traits: .landscapeLeft) {
    TripSimulationViewIOSPreview()
        .frame(width: 1194, height: 834)
}

#Preview("iPad Portrait", traits: .portrait) {
    TripSimulationViewIOSPreview()
        .frame(width: 834, height: 1194)
}
#endif

#endif
