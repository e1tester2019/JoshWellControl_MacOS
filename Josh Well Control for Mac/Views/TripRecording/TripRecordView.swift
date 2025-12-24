//
//  TripRecordView.swift
//  Josh Well Control for Mac
//
//  Created for recording field trip observations against simulation predictions.
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

/// View for recording actual trip observations against simulation predictions.
/// Pre-populates depth points from a saved simulation and allows filling in actual values.
struct TripRecordView: View {
    // MARK: - Environment
    @Environment(\.modelContext) private var modelContext

    @Bindable var project: ProjectState

    // Query saved simulations and records
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
    @State private var exportError: String?
    @State private var showingHTMLPreview = false
    @State private var previewHTMLContent: String = ""

    // MARK: - Body
    var body: some View {
        VStack(spacing: 12) {
            headerToolbar
            Divider()
            content
        }
        .padding(12)
        .sheet(isPresented: $showingSimulationPicker) {
            simulationPickerSheet
        }
        #if os(macOS)
        .sheet(isPresented: $showingHTMLPreview) {
            htmlPreviewSheet
        }
        .alert("Export Error", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "Unknown error")
        }
        #endif
    }

    // MARK: - Export Functions

    #if os(macOS)
    private func createReportData() -> TripRecordComparisonGenerator.ComparisonReportData? {
        guard let record = viewModel.tripRecord else { return nil }
        let wellName = project.well?.name ?? "Unknown Well"
        let projectName = project.name
        return TripRecordComparisonGenerator.shared.createReportData(
            from: record,
            wellName: wellName,
            projectName: projectName
        )
    }

    private func exportHTML() {
        guard let data = createReportData() else {
            exportError = "No record loaded"
            return
        }

        let html = TripRecordComparisonGenerator.shared.generateHTML(for: data)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.html]
        panel.nameFieldStringValue = "\(data.recordName.replacingOccurrences(of: " ", with: "_")).html"
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try html.write(to: url, atomically: true, encoding: .utf8)
                NSWorkspace.shared.open(url)
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    private func exportCSV() {
        guard let data = createReportData() else {
            exportError = "No record loaded"
            return
        }

        let csv = TripRecordComparisonGenerator.shared.generateCSV(for: data)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.nameFieldStringValue = "\(data.recordName.replacingOccurrences(of: " ", with: "_")).csv"
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
                NSWorkspace.shared.open(url)
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    private func previewHTML() {
        guard let data = createReportData() else {
            exportError = "No record loaded"
            return
        }
        previewHTMLContent = TripRecordComparisonGenerator.shared.generateHTML(for: data)
        showingHTMLPreview = true
    }

    private var htmlPreviewSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Report Preview")
                    .font(.headline)
                Spacer()
                Button("Export", systemImage: "square.and.arrow.up") {
                    showingHTMLPreview = false
                    exportHTML()
                }
                Button("Done") {
                    showingHTMLPreview = false
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            Divider()

            WebViewPreview(htmlContent: previewHTMLContent)
        }
        .frame(minWidth: 900, minHeight: 700)
    }
    #endif

    // MARK: - Header Toolbar
    private var headerToolbar: some View {
        HStack(spacing: 12) {
            if viewModel.tripRecord == nil {
                // No record loaded - show start button
                Button {
                    showingSimulationPicker = true
                } label: {
                    Label("Start from Simulation", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)

                if !savedRecords.isEmpty {
                    Text("or select a saved record").foregroundStyle(.secondary)
                }
            } else {
                // Record loaded - show info and controls
                recordHeader
            }
        }
    }

    private var recordHeader: some View {
        HStack(spacing: 12) {
            // Record name
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.tripRecord?.name ?? "Trip Record")
                    .font(.headline)
                HStack(spacing: 4) {
                    Image(systemName: viewModel.tripRecord?.status.icon ?? "clock")
                        .foregroundStyle(statusColor)
                    Text(viewModel.tripRecord?.status.label ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider().frame(height: 30)

            // Summary stats
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.summaryText)
                    .font(.caption)
                ProgressView(value: viewModel.progressPercent, total: 100)
                    .frame(width: 120)
            }

            Divider().frame(height: 30)

            // Variance stats
            if viewModel.tripRecord?.stepsRecorded ?? 0 > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Avg SABP Var:").foregroundStyle(.secondary).font(.caption)
                        Text(viewModel.avgSABPVarianceText).monospacedDigit().font(.caption)
                    }
                    HStack(spacing: 8) {
                        Text("Avg BF Var:").foregroundStyle(.secondary).font(.caption)
                        Text(viewModel.avgBackfillVarianceText).monospacedDigit().font(.caption)
                    }
                }

                Divider().frame(height: 30)
            }

            Spacer()

            // Depth slider
            if !viewModel.steps.isEmpty {
                depthSlider
            }

            Divider().frame(height: 30)

            // Export button
            #if os(macOS)
            Menu {
                Button("Export HTML Report", systemImage: "doc.richtext") {
                    exportHTML()
                }
                Button("Export CSV Data", systemImage: "tablecells") {
                    exportCSV()
                }
                Button("Preview Report", systemImage: "eye") {
                    previewHTML()
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            #endif

            // Actions
            Menu {
                if viewModel.tripRecord?.status == .inProgress {
                    Button("Mark Complete") {
                        viewModel.markComplete()
                    }
                    Button("Cancel Record", role: .destructive) {
                        viewModel.markCancelled()
                    }
                }
                if viewModel.tripRecord?.status == .completed {
                    Button("Unmark Complete") {
                        viewModel.unmarkComplete()
                    }
                }
                Divider()
                #if os(macOS)
                Button("Export HTML Report", systemImage: "doc.richtext") {
                    exportHTML()
                }
                Button("Export CSV Data", systemImage: "tablecells") {
                    exportCSV()
                }
                Divider()
                #endif
                Button("Close Record") {
                    viewModel.clear()
                }
                Button("Delete Record", role: .destructive) {
                    viewModel.deleteRecord(context: modelContext)
                }
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
            }
        }
    }

    private var statusColor: Color {
        switch viewModel.tripRecord?.status {
        case .inProgress: return .orange
        case .completed: return .green
        case .cancelled: return .red
        default: return .secondary
        }
    }

    private var depthSlider: some View {
        HStack(spacing: 8) {
            Text("Depth:")
                .foregroundStyle(.secondary)

            if let step = viewModel.selectedStep {
                Text("\(Int(step.bitMD_m))m")
                    .monospacedDigit()
                    .frame(width: 60, alignment: .trailing)
            }

            Slider(
                value: $viewModel.stepSlider,
                in: 0...Double(max(viewModel.steps.count - 1, 0)),
                step: 1
            )
            .frame(width: 200)
            .onChange(of: viewModel.stepSlider) { _, _ in
                viewModel.updateFromSlider()
            }

            if let step = viewModel.selectedStep {
                Text("TVD: \(Int(step.bitTVD_m))m")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
    }

    // MARK: - Content
    private var content: some View {
        GeometryReader { geo in
            HStack(spacing: 12) {
                // LEFT: Saved records sidebar
                if !savedRecords.isEmpty && viewModel.tripRecord == nil {
                    savedRecordsList
                        .frame(width: 180)
                    Divider()
                }

                // CENTER: Comparison table
                VStack(spacing: 8) {
                    if viewModel.tripRecord != nil {
                        comparisonTable
                    } else {
                        emptyState
                    }
                }
                .frame(maxWidth: .infinity)

                // RIGHT: Well visualization + comparison
                if viewModel.tripRecord != nil && !viewModel.steps.isEmpty {
                    Divider()
                    VStack(spacing: 8) {
                        // Visualization mode picker
                        Picker("View", selection: $viewModel.visualizationMode) {
                            ForEach(TripRecordViewModel.VisualizationMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        wellVisualization
                        stepComparisonPanel
                        esdAndFloatStatus
                    }
                    .frame(width: max(280, geo.size.width / 4))
                }
            }
        }
    }

    // MARK: - Saved Records List
    private var savedRecordsList: some View {
        GroupBox("Saved Records") {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(savedRecords) { record in
                        Button {
                            viewModel.load(record)
                        } label: {
                            HStack {
                                Image(systemName: record.status.icon)
                                    .foregroundStyle(record.status == .completed ? .green : record.status == .cancelled ? .red : .orange)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(record.name)
                                        .lineLimit(1)
                                    Text(record.createdAt, style: .date)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(viewModel.tripRecord?.id == record.id ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Record Loaded", systemImage: "list.bullet.clipboard")
        } description: {
            Text("Start a new trip record from a saved simulation, or select a saved record from the sidebar.")
        } actions: {
            Button("Start from Simulation") {
                showingSimulationPicker = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Comparison Table
    private var comparisonTable: some View {
        GroupBox("Comparison: Simulated vs Actual") {
            Table(viewModel.steps, selection: Binding(
                get: { viewModel.selectedStep?.id },
                set: { newID in
                    if let id = newID, let idx = viewModel.steps.firstIndex(where: { $0.id == id }) {
                        viewModel.selectedIndex = idx
                        viewModel.updateSliderFromSelection()
                    }
                }
            )) {
                // Depth column
                TableColumn("Bit MD") { step in
                    Text(viewModel.format0(step.bitMD_m))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 55, ideal: 60)

                // SABP group: Sim | Act | Var
                TableColumn("Sim SABP") { step in
                    Text(viewModel.format0(step.simSABP_kPa))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 60, ideal: 70)

                TableColumn("Act SABP") { step in
                    ActualValueCell(
                        value: step.actualSABP_kPa,
                        placeholder: "--",
                        format: "%.0f",
                        isEditing: viewModel.tripRecord?.status == .inProgress
                    ) { newValue in
                        step.actualSABP_kPa = newValue
                        step.calculateVariance()
                        viewModel.tripRecord?.updateVarianceSummary()
                    }
                }
                .width(min: 65, ideal: 75)

                // Dynamic SABP group: Sim | Act
                TableColumn("Sim Dyn") { step in
                    Text(viewModel.format0(step.simSABP_Dynamic_kPa))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 55, ideal: 65)

                TableColumn("Act Dyn") { step in
                    ActualValueCell(
                        value: step.actualSABP_Dynamic_kPa,
                        placeholder: "--",
                        format: "%.0f",
                        isEditing: viewModel.tripRecord?.status == .inProgress
                    ) { newValue in
                        step.actualSABP_Dynamic_kPa = newValue
                        viewModel.tripRecord?.updateVarianceSummary()
                    }
                }
                .width(min: 65, ideal: 75)

                // Backfill group: Sim | Act | Var
                TableColumn("Sim BF") { step in
                    Text(viewModel.format3(step.simBackfill_m3))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 60, ideal: 70)

                TableColumn("Act BF") { step in
                    ActualValueCell(
                        value: step.actualBackfill_m3,
                        placeholder: "--",
                        format: "%.3f",
                        isEditing: viewModel.tripRecord?.status == .inProgress
                    ) { newValue in
                        step.actualBackfill_m3 = newValue
                        step.calculateVariance()
                        viewModel.tripRecord?.updateVarianceSummary()
                    }
                }
                .width(min: 65, ideal: 75)

                TableColumn("BF Var") { step in
                    VarianceCell(
                        value: step.backfillVariancePercent,
                        format: "%+.1f%%",
                        level: viewModel.backfillVarianceColor(step.backfillVariancePercent)
                    )
                }
                .width(min: 55, ideal: 65)

                // Status column
                TableColumn("Status") { step in
                    StatusCell(
                        step: step,
                        isEditing: viewModel.tripRecord?.status == .inProgress,
                        onSkip: {
                            step.markSkipped()
                            viewModel.tripRecord?.updateVarianceSummary()
                        },
                        onClear: {
                            step.clearActual()
                            viewModel.tripRecord?.updateVarianceSummary()
                        }
                    )
                }
                .width(50)
            }
        }
    }

    // MARK: - Step Comparison Panel
    private var stepComparisonPanel: some View {
        GroupBox("Sim vs Actual @ \(viewModel.format0(viewModel.selectedStep?.bitMD_m ?? 0))m") {
            if let step = viewModel.selectedStep {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow {
                        Text("").frame(width: 60)
                        Text("Sim").font(.caption).foregroundStyle(.secondary).frame(width: 50, alignment: .trailing)
                        Text("Act").font(.caption).foregroundStyle(.blue).frame(width: 50, alignment: .trailing)
                        Text("Var").font(.caption).foregroundStyle(.secondary).frame(width: 50, alignment: .trailing)
                    }
                    Divider()
                    GridRow {
                        Text("SABP").font(.caption).foregroundStyle(.secondary)
                        Text(viewModel.format0(step.simSABP_kPa)).monospacedDigit().frame(width: 50, alignment: .trailing)
                        Text(step.actualSABP_kPa.map { viewModel.format0($0) } ?? "--").monospacedDigit().foregroundStyle(.blue).frame(width: 50, alignment: .trailing)
                        Text(step.sabpVariance_kPa.map { String(format: "%+.0f", $0) } ?? "--").monospacedDigit().foregroundStyle(varianceColor(step.sabpVariance_kPa, threshold: 50)).frame(width: 50, alignment: .trailing)
                    }
                    GridRow {
                        Text("Dynamic").font(.caption).foregroundStyle(.secondary)
                        Text(viewModel.format0(step.simSABP_Dynamic_kPa)).monospacedDigit().frame(width: 50, alignment: .trailing)
                        Text(step.actualSABP_Dynamic_kPa.map { viewModel.format0($0) } ?? "--").monospacedDigit().foregroundStyle(.blue).frame(width: 50, alignment: .trailing)
                        Text("--").foregroundStyle(.tertiary).frame(width: 50, alignment: .trailing)
                    }
                    GridRow {
                        Text("Backfill").font(.caption).foregroundStyle(.secondary)
                        Text(viewModel.format3(step.simBackfill_m3)).monospacedDigit().frame(width: 50, alignment: .trailing)
                        Text(step.actualBackfill_m3.map { viewModel.format3($0) } ?? "--").monospacedDigit().foregroundStyle(.blue).frame(width: 50, alignment: .trailing)
                        Text(step.backfillVariancePercent.map { String(format: "%+.1f%%", $0) } ?? "--").monospacedDigit().foregroundStyle(varianceColor(step.backfillVariancePercent, threshold: 5)).frame(width: 50, alignment: .trailing)
                    }
                }
                .font(.system(size: 11, design: .monospaced))
            } else {
                Text("Select a step").foregroundStyle(.secondary)
            }
        }
    }

    private func varianceColor(_ value: Double?, threshold: Double) -> Color {
        guard let v = value else { return .secondary }
        let absV = abs(v)
        if absV <= threshold / 2 { return .green }
        if absV <= threshold { return .orange }
        return .red
    }

    // MARK: - ESD and Float Status
    private var esdAndFloatStatus: some View {
        VStack(spacing: 4) {
            // ESD comparison
            Text(viewModel.esdComparisonText(project: project))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.blue)

            // Float status indicator
            let floatStatus = viewModel.floatStatus(project: project)
            if floatStatus != .unknown {
                HStack(spacing: 4) {
                    Image(systemName: floatStatus.icon)
                        .foregroundStyle(floatStatusColor(floatStatus))
                    Text(floatStatus.label)
                        .font(.caption)
                        .foregroundStyle(floatStatusColor(floatStatus))
                }
            }
        }
    }

    private func floatStatusColor(_ status: TripRecordViewModel.FloatStatus) -> Color {
        switch status {
        case .unknown: return .secondary
        case .normal: return .green
        case .pressureLow: return .orange
        case .nearCrack: return .orange
        case .cracked: return .red
        }
    }

    // MARK: - Well Visualization
    private var wellVisualization: some View {
        let title: String = {
            switch viewModel.visualizationMode {
            case .simulated: return "Well Snapshot (Simulated)"
            case .adjusted: return "Well Snapshot (Adjusted)"
            case .sideBySide: return "Simulated vs Adjusted"
            }
        }()

        return GroupBox(title) {
            GeometryReader { geo in
                if let step = viewModel.selectedStep {
                    let bitMD = step.bitMD_m

                    // Get layers based on mode
                    let simLayers = viewModel.layersForVisualization()
                    let adjLayers = viewModel.adjustedLayersForVisualization(project: project)

                    Canvas { ctx, size in
                        switch viewModel.visualizationMode {
                        case .simulated:
                            drawWellSnapshot(&ctx, size: size, ann: simLayers.annulus, str: simLayers.string, pocket: simLayers.pocket, bitMD: bitMD)

                        case .adjusted:
                            drawWellSnapshot(&ctx, size: size, ann: adjLayers.annulus, str: adjLayers.string, pocket: adjLayers.pocket, bitMD: bitMD)

                        case .sideBySide:
                            // Split view: Simulated on left, Adjusted on right
                            let halfW = size.width / 2 - 4
                            let leftRect = CGRect(x: 0, y: 0, width: halfW, height: size.height)
                            let rightRect = CGRect(x: halfW + 8, y: 0, width: halfW, height: size.height)

                            // Draw divider
                            ctx.fill(Path(CGRect(x: halfW + 2, y: 0, width: 4, height: size.height)), with: .color(.secondary.opacity(0.3)))

                            // Labels
                            ctx.draw(Text("SIM").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary), at: CGPoint(x: halfW / 2, y: 8))
                            ctx.draw(Text("ADJ").font(.system(size: 9, weight: .bold)).foregroundColor(.blue), at: CGPoint(x: halfW + 8 + halfW / 2, y: 8))

                            // Draw simulated (left)
                            drawWellSnapshotInRect(&ctx, rect: leftRect, ann: simLayers.annulus, str: simLayers.string, pocket: simLayers.pocket, bitMD: bitMD, showLabels: false)

                            // Draw adjusted (right)
                            drawWellSnapshotInRect(&ctx, rect: rightRect, ann: adjLayers.annulus, str: adjLayers.string, pocket: adjLayers.pocket, bitMD: bitMD, showLabels: false)

                            // Bit marker across both
                            let maxPocketMD = max(simLayers.pocket.map { $0.bottomMD }.max() ?? bitMD, adjLayers.pocket.map { $0.bottomMD }.max() ?? bitMD)
                            let globalMaxMD = max(bitMD, maxPocketMD)
                            let yBit = globalMaxMD > 0 ? CGFloat(bitMD / globalMaxMD) * size.height : 0
                            ctx.fill(Path(CGRect(x: 0, y: yBit - 0.5, width: size.width, height: 1)), with: .color(.accentColor.opacity(0.9)))
                        }
                    }
                } else {
                    ContentUnavailableView("Select a step", systemImage: "cursorarrow.click", description: Text("Choose a row to see the well snapshot."))
                }
            }
            .frame(minHeight: 200)
        }
    }

    // MARK: - Helper Drawing Functions

    /// Draw a complete well snapshot filling the given size
    private func drawWellSnapshot(_ ctx: inout GraphicsContext, size: CGSize, ann: [NumericalTripModel.LayerRow], str: [NumericalTripModel.LayerRow], pocket: [NumericalTripModel.LayerRow], bitMD: Double) {
        // Three-column layout: Annulus | String | Annulus
        let gap: CGFloat = 8
        let colW = (size.width - 2*gap) / 3
        let annLeft  = CGRect(x: 0, y: 0, width: colW, height: size.height)
        let strRect  = CGRect(x: colW + gap, y: 0, width: colW, height: size.height)
        let annRight = CGRect(x: 2*(colW + gap), y: 0, width: colW, height: size.height)

        // Unified vertical scale
        let maxPocketMD = pocket.map { $0.bottomMD }.max() ?? bitMD
        let globalMaxMD = max(bitMD, maxPocketMD)
        func yGlobal(_ md: Double) -> CGFloat {
            guard globalMaxMD > 0 else { return 0 }
            return CGFloat(md / globalMaxMD) * size.height
        }

        // Draw columns
        drawColumn(&ctx, rows: ann, in: annLeft,  isAnnulus: true,  bitMD: bitMD, yGlobal: yGlobal)
        drawColumn(&ctx, rows: str, in: strRect,  isAnnulus: false, bitMD: bitMD, yGlobal: yGlobal)
        drawColumn(&ctx, rows: ann, in: annRight, isAnnulus: true,  bitMD: bitMD, yGlobal: yGlobal)

        // Pocket (full width)
        for r in pocket {
            let yTop = yGlobal(r.topMD)
            let yBot = yGlobal(r.bottomMD)
            let yMin = min(yTop, yBot)
            let col = fillColor(rho: r.rho_kgpm3, explicit: r.color)
            let top = floor(yMin)
            let bottom = ceil(max(yTop, yBot))
            var sub = CGRect(x: 0, y: top, width: size.width, height: max(1, bottom - top))
            sub = sub.insetBy(dx: 0, dy: -0.25)
            ctx.fill(Path(sub), with: .color(col))
        }

        // Headers
        ctx.draw(Text("Ann").font(.caption2), at: CGPoint(x: annLeft.midX,  y: 10))
        ctx.draw(Text("Str").font(.caption2),  at: CGPoint(x: strRect.midX,  y: 10))
        ctx.draw(Text("Ann").font(.caption2), at: CGPoint(x: annRight.midX, y: 10))

        // Bit marker
        let yBit = yGlobal(bitMD)
        ctx.fill(Path(CGRect(x: 0, y: yBit - 0.5, width: size.width, height: 1)), with: .color(.accentColor.opacity(0.9)))

        // Depth ticks
        let tickCount = 5
        for i in 0...tickCount {
            let md = Double(i) / Double(tickCount) * globalMaxMD
            let yy = yGlobal(md)
            let tvd = project.tvd(of: md)
            ctx.fill(Path(CGRect(x: size.width - 8, y: yy - 0.5, width: 8, height: 1)), with: .color(.secondary))
            ctx.draw(Text(String(format: "%.0f", md)).font(.system(size: 8)), at: CGPoint(x: size.width - 10, y: yy - 4), anchor: .trailing)
            ctx.fill(Path(CGRect(x: 0, y: yy - 0.5, width: 8, height: 1)), with: .color(.secondary))
            ctx.draw(Text(String(format: "%.0f", tvd)).font(.system(size: 8)), at: CGPoint(x: 10, y: yy - 4), anchor: .leading)
        }
    }

    /// Draw well snapshot within a specific rect (for side-by-side view)
    private func drawWellSnapshotInRect(_ ctx: inout GraphicsContext, rect: CGRect, ann: [NumericalTripModel.LayerRow], str: [NumericalTripModel.LayerRow], pocket: [NumericalTripModel.LayerRow], bitMD: Double, showLabels: Bool) {
        // Simplified two-column layout for compact view: Annulus | String
        let gap: CGFloat = 4
        let colW = (rect.width - gap) / 2
        let annRect = CGRect(x: rect.minX, y: rect.minY + 16, width: colW, height: rect.height - 16)
        let strRect = CGRect(x: rect.minX + colW + gap, y: rect.minY + 16, width: colW, height: rect.height - 16)

        // Unified vertical scale
        let maxPocketMD = pocket.map { $0.bottomMD }.max() ?? bitMD
        let globalMaxMD = max(bitMD, maxPocketMD)
        func yGlobal(_ md: Double) -> CGFloat {
            guard globalMaxMD > 0 else { return rect.minY + 16 }
            return rect.minY + 16 + CGFloat(md / globalMaxMD) * (rect.height - 16)
        }

        // Draw columns
        drawColumn(&ctx, rows: ann, in: annRect, isAnnulus: true, bitMD: bitMD, yGlobal: yGlobal)
        drawColumn(&ctx, rows: str, in: strRect, isAnnulus: false, bitMD: bitMD, yGlobal: yGlobal)

        // Pocket
        for r in pocket {
            let yTop = yGlobal(r.topMD)
            let yBot = yGlobal(r.bottomMD)
            let yMin = min(yTop, yBot)
            let col = fillColor(rho: r.rho_kgpm3, explicit: r.color)
            let top = floor(yMin)
            let bottom = ceil(max(yTop, yBot))
            var sub = CGRect(x: rect.minX, y: top, width: rect.width, height: max(1, bottom - top))
            sub = sub.insetBy(dx: 0, dy: -0.25)
            ctx.fill(Path(sub), with: .color(col))
        }
    }

    private func drawColumn(_ ctx: inout GraphicsContext, rows: [NumericalTripModel.LayerRow], in rect: CGRect, isAnnulus: Bool, bitMD: Double, yGlobal: (Double) -> CGFloat) {
        for r in rows where r.bottomMD <= bitMD + 1e-9 {
            let yTop = yGlobal(r.topMD)
            let yBot = yGlobal(r.bottomMD)
            let yMin = min(yTop, yBot)
            let col = fillColor(rho: r.rho_kgpm3, explicit: r.color)
            let top = floor(yMin)
            let bottom = ceil(max(yTop, yBot))
            var sub = CGRect(x: rect.minX, y: top, width: rect.width, height: max(1, bottom - top))
            sub = sub.insetBy(dx: 0, dy: -0.25)
            ctx.fill(Path(sub), with: .color(col))
        }
    }

    private func fillColor(rho: Double, explicit: NumericalTripModel.ColorRGBA? = nil) -> Color {
        if let c = explicit {
            return Color(red: c.r, green: c.g, blue: c.b, opacity: c.a)
        }
        // Density-based greyscale
        let minRho = 800.0, maxRho = 2400.0
        let t = min(1.0, max(0.0, (rho - minRho) / (maxRho - minRho)))
        let grey = 0.95 - 0.6 * t
        return Color(white: grey)
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
                                    HStack(spacing: 12) {
                                        Text("\(Int(sim.startBitMD_m))m → \(Int(sim.endMD_m))m")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("\(sim.stepCount) steps")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(sim.createdAt, style: .date)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                                if selectedSimulation?.id == sim.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Select Simulation")
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
        .frame(minWidth: 500, minHeight: 400)
    }
}

// MARK: - Helper Views

struct ActualValueCell: View {
    let value: Double?
    let placeholder: String
    let format: String
    let isEditing: Bool
    let onCommit: (Double?) -> Void

    @State private var editText: String = ""
    @State private var isTextFieldActive = false

    var body: some View {
        if isEditing {
            TextField(placeholder, text: $editText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 65)
                .multilineTextAlignment(.trailing)
                .onAppear {
                    editText = value.map { String(format: format, $0) } ?? ""
                }
                .onChange(of: value) { _, newVal in
                    if !isTextFieldActive {
                        editText = newVal.map { String(format: format, $0) } ?? ""
                    }
                }
                .onSubmit {
                    if let d = Double(editText.replacingOccurrences(of: ",", with: ".")) {
                        onCommit(d)
                    } else if editText.isEmpty {
                        onCommit(nil)
                    }
                }
        } else {
            Text(value.map { String(format: format, $0) } ?? placeholder)
                .monospacedDigit()
                .foregroundStyle(value == nil ? .tertiary : .primary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

struct VarianceCell: View {
    let value: Double?
    let format: String
    let level: TripRecordViewModel.VarianceLevel

    var body: some View {
        if let v = value {
            Text(String(format: format, v))
                .monospacedDigit()
                .foregroundStyle(colorForLevel)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            Text("--")
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var colorForLevel: Color {
        switch level {
        case .none: return .secondary
        case .good: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

struct StatusCell: View {
    let step: TripRecordStep
    let isEditing: Bool
    let onSkip: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            // Status icon - clickable to undo skip or clear
            if isEditing && (step.skipped || step.hasActualData) {
                Button {
                    onClear()
                } label: {
                    Image(systemName: step.status.icon)
                        .foregroundStyle(iconColor)
                }
                .buttonStyle(.borderless)
                .help(step.skipped ? "Undo skip" : "Clear values")
            } else {
                Image(systemName: step.status.icon)
                    .foregroundStyle(iconColor)
            }

            // Skip button for pending steps
            if isEditing && !step.hasActualData && !step.skipped {
                Button {
                    onSkip()
                } label: {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .help("Skip this depth")
            }
        }
    }

    private var iconColor: Color {
        switch step.status {
        case .pending: return .secondary
        case .recorded: return .green
        case .skipped: return .orange
        }
    }
}

// MARK: - WebView Preview (macOS)

#if os(macOS)
import WebKit

struct WebViewPreview: NSViewRepresentable {
    let htmlContent: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }
}
#endif

#Preview {
    // Preview requires a project context
    Text("TripRecordView Preview")
}
