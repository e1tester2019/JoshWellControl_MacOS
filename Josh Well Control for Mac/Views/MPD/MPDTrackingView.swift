//
//  MPDTrackingView.swift
//  Josh Well Control for Mac
//
//  Managed Pressure Drilling tracking view
//  Tracks ECD (circulating) and ESD (shut-in) at heel and toe positions
//

import SwiftUI
import SwiftData
import Charts

struct MPDTrackingView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState

    // Query readings directly for reactive updates
    @Query(sort: \MPDReading.timestamp, order: .reverse) private var allReadings: [MPDReading]

    @State private var viewModel = MPDTrackingViewModel()
    @State private var showingDeleteConfirmation = false
    @State private var readingToDelete: UUID?
    @State private var refreshTrigger = UUID()
    @State private var showingExtendPrompt = false
    @State private var chartXAxisIsBitMD = false
    @State private var selectedReadings: [MPDReading] = []
    @State private var editingBitMD: Double = 0
    @State private var editingTimestampReading: MPDReading?
    @State private var editingTimestamp: Date = Date()
    @State private var chartMinMD: Double = 0
    @State private var chartMaxMD: Double = 5000
    @State private var editingChartMinMD: Double = 0
    @State private var editingChartMaxMD: Double = 5000
    @FocusState private var bitMDFieldFocused: Bool
    @FocusState private var chartMinFieldFocused: Bool
    @FocusState private var chartMaxFieldFocused: Bool

    /// Readings filtered to current sheet
    private var readings: [MPDReading] {
        guard let sheetID = viewModel.boundSheet?.id else { return [] }
        return allReadings.filter { $0.mpdSheet?.id == sheetID }
    }

    var body: some View {
        #if os(macOS)
        macOSLayout
        #else
        iOSLayout
        #endif
    }

    // MARK: - macOS Layout

    #if os(macOS)
    private var macOSLayout: some View {
        HSplitView {
            // Left panel: Configuration and Input
            ScrollView {
                VStack(spacing: 0) {
                    configurationSection
                    Divider()
                    inputSection
                    Divider()
                    previewSection
                    Spacer(minLength: 0)
                }
            }
            .frame(minWidth: 320, idealWidth: 360, maxWidth: 400)

            // Right panel: Chart and Readings
            VSplitView {
                chartSection
                    .frame(minHeight: 250, maxHeight: .infinity)
                readingsTableSection
                    .frame(minHeight: 150, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
        .navigationTitle("MPD Tracking")
        .id(refreshTrigger)
        .onAppear {
            viewModel.bootstrap(project: project, context: modelContext)
            editingBitMD = viewModel.bitMD_m
        }
        .alert("Delete Reading?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let id = readingToDelete {
                    viewModel.deleteReading(id)
                    try? modelContext.save()
                    readingToDelete = nil
                }
            }
        }
        .alert("Extend Well Geometry?", isPresented: $showingExtendPrompt) {
            Button("Cancel", role: .cancel) {}
            Button("Extend") {
                viewModel.extendGeometryToBitDepth()
            }
        } message: {
            Text("Bit depth exceeds defined geometry by \(viewModel.geometryExtensionNeeded, specifier: "%.0f")m.\n\nExtend drill string and annulus to \(viewModel.bitMD_m, specifier: "%.0f")m?")
        }
        // Auto-save configuration changes
        .onChange(of: viewModel.heelMD_m) { _, _ in saveConfiguration() }
        .onChange(of: viewModel.bitMD_m) { _, newValue in
            saveConfiguration()
            // Prompt to extend if bit exceeds geometry
            if viewModel.bitExceedsGeometry {
                showingExtendPrompt = true
            }
        }
        .onChange(of: viewModel.toeMD_m) { _, _ in saveConfiguration() }
        .onChange(of: viewModel.porePressure_kgm3) { _, _ in saveConfiguration() }
        .onChange(of: viewModel.fracGradient_kgm3) { _, _ in saveConfiguration() }
        .onChange(of: viewModel.defaultCirculatingChoke_kPa) { _, _ in saveConfiguration() }
        .onChange(of: viewModel.defaultShutInChoke_kPa) { _, _ in saveConfiguration() }
        .onChange(of: viewModel.sheetName) { _, _ in saveConfiguration() }
        .onChange(of: viewModel.inputIsCirculating) { _, isCirculating in
            // Apply appropriate default when switching modes
            if isCirculating {
                viewModel.inputChokeFriction_kPa = viewModel.defaultCirculatingChoke_kPa
            } else {
                viewModel.inputShutInPressure_kPa = viewModel.defaultShutInChoke_kPa
            }
        }
        .onChange(of: chartXAxisIsBitMD) { _, isBitMD in
            if isBitMD {
                // Initialize depth range to 100m either side of data range
                initializeChartDepthRange()
            }
        }
    }
    #endif

    private func saveConfiguration() {
        guard viewModel.boundSheet != nil else { return }
        viewModel.updateSheetConfiguration()
        try? modelContext.save()
    }

    private func applyChartDepthRange() {
        // Ensure min <= max, swap if needed
        let minVal = min(editingChartMinMD, editingChartMaxMD)
        let maxVal = max(editingChartMinMD, editingChartMaxMD)

        // Ensure we have at least a 10m range to avoid issues
        if maxVal - minVal < 10 {
            chartMinMD = minVal
            chartMaxMD = minVal + 10
        } else {
            chartMinMD = minVal
            chartMaxMD = maxVal
        }

        // Sync editing values back
        editingChartMinMD = chartMinMD
        editingChartMaxMD = chartMaxMD
    }

    private func initializeChartDepthRange() {
        // Set bounds to 100m either side of the data range
        if readings.isEmpty {
            // Fall back to heel-toe if no data
            chartMinMD = viewModel.heelMD_m
            chartMaxMD = viewModel.toeMD_m
        } else {
            let dataMin = readings.map { $0.bitMD_m }.min() ?? viewModel.heelMD_m
            let dataMax = readings.map { $0.bitMD_m }.max() ?? viewModel.toeMD_m
            chartMinMD = max(0, dataMin - 10)
            chartMaxMD = dataMax + 10
        }
        editingChartMinMD = chartMinMD
        editingChartMaxMD = chartMaxMD
    }

    // MARK: - iOS Layout

    #if os(iOS)
    private var iOSLayout: some View {
        NavigationStack {
            List {
                configurationSectionIOS
                inputSectionIOS
                previewSectionIOS
                chartSectionIOS
                readingsListSectionIOS
            }
            .navigationTitle("MPD Tracking")
            .onAppear {
                viewModel.bootstrap(project: project, context: modelContext)
                editingBitMD = viewModel.bitMD_m
            }
            .alert("Extend Well Geometry?", isPresented: $showingExtendPrompt) {
                Button("Cancel", role: .cancel) {}
                Button("Extend") {
                    viewModel.extendGeometryToBitDepth()
                }
            } message: {
                Text("Bit depth exceeds defined geometry by \(viewModel.geometryExtensionNeeded, specifier: "%.0f")m.\n\nExtend drill string and annulus to \(viewModel.bitMD_m, specifier: "%.0f")m?")
            }
            .onChange(of: viewModel.bitMD_m) { _, _ in
                if viewModel.bitExceedsGeometry {
                    showingExtendPrompt = true
                }
            }
            .onChange(of: viewModel.inputIsCirculating) { _, isCirculating in
                // Apply appropriate default when switching modes
                if isCirculating {
                    viewModel.inputChokeFriction_kPa = viewModel.defaultCirculatingChoke_kPa
                } else {
                    viewModel.inputShutInPressure_kPa = viewModel.defaultShutInChoke_kPa
                }
            }
        }
    }
    #endif

    // MARK: - Configuration Section

    #if os(macOS)
    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Configuration")
                    .font(.headline)
                Spacer()
                if viewModel.boundSheet != nil {
                    Button("Update") {
                        viewModel.updateSheetConfiguration()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button("Create Sheet") {
                        viewModel.createSheet()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Sheet Name:")
                        .foregroundStyle(.secondary)
                    TextField("Name", text: $viewModel.sheetName)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Heel MD (m):")
                        .foregroundStyle(.secondary)
                    TextField("", value: $viewModel.heelMD_m, format: .number.precision(.fractionLength(1)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                GridRow {
                    Text("Toe MD (m):")
                        .foregroundStyle(.secondary)
                    TextField("", value: $viewModel.toeMD_m, format: .number.precision(.fractionLength(1)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                GridRow {
                    Text("Pore Pressure (kg/m³):")
                        .foregroundStyle(.secondary)
                    TextField("", value: $viewModel.porePressure_kgm3, format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                GridRow {
                    Text("Frac Gradient (kg/m³):")
                        .foregroundStyle(.secondary)
                    TextField("", value: $viewModel.fracGradient_kgm3, format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                GridRow {
                    Text("Circ. Choke (kPa):")
                        .foregroundStyle(.secondary)
                    TextField("", value: $viewModel.defaultCirculatingChoke_kPa, format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                GridRow {
                    Text("S/I Pressure (kPa):")
                        .foregroundStyle(.secondary)
                    TextField("", value: $viewModel.defaultShutInChoke_kPa, format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }

            // TVD info
            HStack(spacing: 16) {
                Text("Heel: \(viewModel.heelTVD_m, specifier: "%.0f")m TVD")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Toe: \(viewModel.toeTVD_m, specifier: "%.0f")m TVD")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
    #endif

    // MARK: - Input Section

    #if os(macOS)
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Reading")
                .font(.headline)

            // Bit depth - prominent at top
            HStack {
                Text("Bit MD (m):")
                    .foregroundStyle(.secondary)
                TextField("", value: $editingBitMD, format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .focused($bitMDFieldFocused)
                    .onAppear { editingBitMD = viewModel.bitMD_m }
                    .onChange(of: bitMDFieldFocused) { _, focused in
                        if !focused {
                            // Apply on focus loss
                            viewModel.bitMD_m = editingBitMD
                        }
                    }
                    .onSubmit {
                        // Also apply on Enter
                        viewModel.bitMD_m = editingBitMD
                    }
                Text("TVD: \(viewModel.bitTVD_m, specifier: "%.0f")m")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

            // Circulating toggle
            Picker("Mode:", selection: $viewModel.inputIsCirculating) {
                Text("Circulating").tag(true)
                Text("Shut-In").tag(false)
            }
            .pickerStyle(.segmented)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                if viewModel.inputIsCirculating {
                    GridRow {
                        Text("Flow Rate (m³/min):")
                            .foregroundStyle(.secondary)
                        TextField("", value: $viewModel.inputFlowRate_m3_per_min, format: .number.precision(.fractionLength(3)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                    GridRow {
                        Text("Choke Friction (kPa):")
                            .foregroundStyle(.secondary)
                        TextField("", value: $viewModel.inputChokeFriction_kPa, format: .number.precision(.fractionLength(0)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                } else {
                    GridRow {
                        Text("Shut-In Pressure (kPa):")
                            .foregroundStyle(.secondary)
                        TextField("", value: $viewModel.inputShutInPressure_kPa, format: .number.precision(.fractionLength(0)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                }

                GridRow {
                    Text("Density Out (kg/m³):")
                        .foregroundStyle(.secondary)
                    TextField("", value: $viewModel.inputDensityOut_kgm3, format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                GridRow {
                    Text("Notes:")
                        .foregroundStyle(.secondary)
                    TextField("Optional notes", text: $viewModel.inputNotes)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Spacer()
                if viewModel.bitExceedsGeometry {
                    Button("Extend Geometry") {
                        showingExtendPrompt = true
                    }
                    .buttonStyle(.bordered)
                }
                Button(action: {
                    if viewModel.boundSheet == nil {
                        viewModel.createSheet()
                        try? modelContext.save()
                    }
                    viewModel.addReading()
                    try? modelContext.save()
                }) {
                    Label("Add Reading", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled((viewModel.boundSheet == nil && viewModel.sheetName.isEmpty) || viewModel.bitExceedsGeometry)
            }

            if viewModel.bitExceedsGeometry {
                Text("Bit depth exceeds geometry by \(viewModel.geometryExtensionNeeded, specifier: "%.0f")m")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
    }
    #endif

    // MARK: - Preview Section

    #if os(macOS)
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("")
                    Text("Heel")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Bit")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text("Toe")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if viewModel.inputIsCirculating {
                    GridRow {
                        Text("APL:")
                            .foregroundStyle(.secondary)
                        Text("\(viewModel.previewAPLToHeel_kPa, specifier: "%.0f")")
                            .monospacedDigit()
                        Text("\(viewModel.previewAPLToBit_kPa, specifier: "%.0f")")
                            .monospacedDigit()
                            .fontWeight(.medium)
                        Text("\(viewModel.previewAPLToToe_kPa, specifier: "%.0f")")
                            .monospacedDigit()
                            .font(.caption)
                    }
                    GridRow {
                        Text("ECD:")
                            .foregroundStyle(.secondary)
                        Text("\(viewModel.previewECDAtHeel_kgm3, specifier: "%.0f")")
                            .monospacedDigit()
                            .foregroundStyle(viewModel.densityColor(viewModel.previewECDAtHeel_kgm3))
                        Text("\(viewModel.previewECDAtBit_kgm3, specifier: "%.0f")")
                            .monospacedDigit()
                            .fontWeight(.medium)
                            .foregroundStyle(viewModel.densityColor(viewModel.previewECDAtBit_kgm3))
                        Text("\(viewModel.previewECDAtToe_kgm3, specifier: "%.0f")")
                            .monospacedDigit()
                            .font(.caption)
                            .foregroundStyle(viewModel.densityColor(viewModel.previewECDAtToe_kgm3))
                    }
                } else {
                    GridRow {
                        Text("ESD:")
                            .foregroundStyle(.secondary)
                        Text("\(viewModel.previewESDAtHeel_kgm3, specifier: "%.0f")")
                            .monospacedDigit()
                            .foregroundStyle(viewModel.densityColor(viewModel.previewESDAtHeel_kgm3))
                        Text("\(viewModel.previewESDAtBit_kgm3, specifier: "%.0f")")
                            .monospacedDigit()
                            .fontWeight(.medium)
                            .foregroundStyle(viewModel.densityColor(viewModel.previewESDAtBit_kgm3))
                        Text("\(viewModel.previewESDAtToe_kgm3, specifier: "%.0f")")
                            .monospacedDigit()
                            .font(.caption)
                            .foregroundStyle(viewModel.densityColor(viewModel.previewESDAtToe_kgm3))
                    }
                }
            }

            // Pressure window indicator
            HStack {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("Within window")
                    .font(.caption)
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
                Text("Below pore")
                    .font(.caption)
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text("Above frac")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .padding()
    }
    #endif

    // MARK: - Chart Section

    /// Readings sorted oldest first for chart display
    private var chartReadings: [MPDReading] {
        readings.sorted { $0.timestamp < $1.timestamp }
    }

    /// Y-axis range for chart - includes all data points with padding
    private var chartYMin: Double {
        guard !readings.isEmpty else { return viewModel.porePressure_kgm3 - 50 }
        let dataMin = readings.map { min($0.effectiveDensityAtHeel_kgm3, $0.effectiveDensityAtBit_kgm3, $0.effectiveDensityAtToe_kgm3) }.min() ?? viewModel.porePressure_kgm3
        return min(dataMin, viewModel.porePressure_kgm3) - 50
    }
    private var chartYMax: Double {
        guard !readings.isEmpty else { return viewModel.fracGradient_kgm3 + 50 }
        let dataMax = readings.map { max($0.effectiveDensityAtHeel_kgm3, $0.effectiveDensityAtBit_kgm3, $0.effectiveDensityAtToe_kgm3) }.max() ?? viewModel.fracGradient_kgm3
        return max(dataMax, viewModel.fracGradient_kgm3) + 50
    }


    #if os(macOS)
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Trend")
                    .font(.headline)
                Spacer()

                if chartXAxisIsBitMD {
                    HStack(spacing: 4) {
                        Text("From:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("", value: $editingChartMinMD, format: .number.precision(.fractionLength(0)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .focused($chartMinFieldFocused)
                            .onChange(of: chartMinFieldFocused) { _, focused in
                                if !focused { applyChartDepthRange() }
                            }
                            .onSubmit { applyChartDepthRange() }
                        Text("To:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("", value: $editingChartMaxMD, format: .number.precision(.fractionLength(0)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .focused($chartMaxFieldFocused)
                            .onChange(of: chartMaxFieldFocused) { _, focused in
                                if !focused { applyChartDepthRange() }
                            }
                            .onSubmit { applyChartDepthRange() }
                        Text("m")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            // Reset to 100m padding around data
                            initializeChartDepthRange()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Reset to data range ± 100m")
                    }
                }

                Picker("X Axis", selection: $chartXAxisIsBitMD) {
                    Text("Time").tag(false)
                    Text("Bit MD").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Selected reading info
            if !selectedReadings.isEmpty {
                selectedReadingsBanner
            }

            if readings.isEmpty {
                ContentUnavailableView {
                    Label("No Readings", systemImage: "chart.line.uptrend.xyaxis")
                } description: {
                    Text("Add readings to see the trend chart")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chartContent
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var selectedReadingsBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(selectedReadings) { reading in
                HStack(spacing: 12) {
                    // Mode indicator
                    Text(reading.isCirculating ? "ECD" : "ESD")
                        .font(.caption.bold())
                        .foregroundStyle(reading.isCirculating ? .blue : .purple)
                        .frame(width: 28)

                    Text(reading.timestamp, format: .dateTime.hour().minute())
                        .font(.caption)
                    Text("Bit: \(reading.bitMD_m, specifier: "%.0f")m")
                        .font(.caption)
                    Divider().frame(height: 12)
                    Text("Heel: \(Int(reading.effectiveDensityAtHeel_kgm3))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(viewModel.densityColor(reading.effectiveDensityAtHeel_kgm3))
                    Text("Bit: \(Int(reading.effectiveDensityAtBit_kgm3))")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(viewModel.densityColor(reading.effectiveDensityAtBit_kgm3))
                    Text("Toe: \(Int(reading.effectiveDensityAtToe_kgm3))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(viewModel.densityColor(reading.effectiveDensityAtToe_kgm3))
                    Text("kg/m³")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal)
        .overlay(alignment: .topTrailing) {
            Button {
                selectedReadings = []
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(8)
        }
    }

    /// Circulating readings sorted for chart
    private var circulatingReadings: [MPDReading] {
        chartReadings.filter { $0.isCirculating }
    }

    /// Shut-in readings sorted for chart
    private var shutInReadings: [MPDReading] {
        chartReadings.filter { !$0.isCirculating }
    }

    @ViewBuilder
    private var chartContent: some View {
        Chart {
            // Reference lines
            RuleMark(y: .value("Pore", viewModel.porePressure_kgm3))
                .foregroundStyle(.orange.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))

            RuleMark(y: .value("Frac", viewModel.fracGradient_kgm3))
                .foregroundStyle(.red.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))

            // Circulating trend line (blue)
            ForEach(circulatingReadings) { reading in
                if chartXAxisIsBitMD {
                    LineMark(
                        x: .value("Bit MD", reading.bitMD_m),
                        y: .value("ECD", reading.effectiveDensityAtBit_kgm3),
                        series: .value("Type", "Circulating")
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .symbol(.circle)
                    .symbolSize(30)
                } else {
                    LineMark(
                        x: .value("Time", reading.timestamp),
                        y: .value("ECD", reading.effectiveDensityAtBit_kgm3),
                        series: .value("Type", "Circulating")
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .symbol(.circle)
                    .symbolSize(30)
                }
            }

            // Shut-in trend line (purple)
            ForEach(shutInReadings) { reading in
                if chartXAxisIsBitMD {
                    LineMark(
                        x: .value("Bit MD", reading.bitMD_m),
                        y: .value("ESD", reading.effectiveDensityAtBit_kgm3),
                        series: .value("Type", "Shut-In")
                    )
                    .foregroundStyle(.purple)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .symbol(.square)
                    .symbolSize(30)
                } else {
                    LineMark(
                        x: .value("Time", reading.timestamp),
                        y: .value("ESD", reading.effectiveDensityAtBit_kgm3),
                        series: .value("Type", "Shut-In")
                    )
                    .foregroundStyle(.purple)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .symbol(.square)
                    .symbolSize(30)
                }
            }

            // Data marks (bars showing heel-toe range)
            ForEach(chartReadings) { reading in
                chartMarksForReading(reading)
            }
        }
        .chartYScale(domain: chartYMin...chartYMax)
        .chartYAxisLabel("Density (kg/m³)")
        .chartXAxisLabel(chartXAxisIsBitMD ? "Bit MD (m)" : "Time")
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        handleChartTap(at: location, proxy: proxy, geometry: geometry)
                    }
            }
        }
        .modifier(ChartXScaleModifier(isEnabled: chartXAxisIsBitMD, min: chartMinMD, max: chartMaxMD))
        .padding()
    }

    /// Custom modifier to conditionally apply chartXScale
    private struct ChartXScaleModifier: ViewModifier {
        let isEnabled: Bool
        let min: Double
        let max: Double

        func body(content: Content) -> some View {
            if isEnabled {
                content.chartXScale(domain: min...max)
            } else {
                content
            }
        }
    }

    @ChartContentBuilder
    private func chartMarksForReading(_ reading: MPDReading) -> some ChartContent {
        let isSelected = selectedReadings.contains { $0.id == reading.id }
        let barOpacity = isSelected ? 0.5 : 0.2
        let barColor = reading.isCirculating ? Color.blue : Color.purple

        if chartXAxisIsBitMD {
            // Range bar (heel to toe)
            RectangleMark(
                x: .value("Bit MD", reading.bitMD_m),
                yStart: .value("Heel", reading.effectiveDensityAtHeel_kgm3),
                yEnd: .value("Toe", reading.effectiveDensityAtToe_kgm3),
                width: 10
            )
            .foregroundStyle(barColor.opacity(barOpacity))
            .cornerRadius(2)
        } else {
            // Range bar (heel to toe)
            RectangleMark(
                x: .value("Time", reading.timestamp),
                yStart: .value("Heel", reading.effectiveDensityAtHeel_kgm3),
                yEnd: .value("Toe", reading.effectiveDensityAtToe_kgm3),
                width: 10
            )
            .foregroundStyle(barColor.opacity(barOpacity))
            .cornerRadius(2)
        }
    }

    private func handleChartTap(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        let xPosition = location.x - geometry[proxy.plotFrame!].origin.x

        if chartXAxisIsBitMD {
            guard let bitMD: Double = proxy.value(atX: xPosition) else { return }
            // Find all readings within 20m of tap position
            let threshold = 20.0
            selectedReadings = chartReadings.filter { abs($0.bitMD_m - bitMD) <= threshold }
                .sorted { $0.isCirculating && !$1.isCirculating } // ECD first, then ESD
        } else {
            guard let date: Date = proxy.value(atX: xPosition) else { return }
            // Find all readings within 1 minute of tap position
            let threshold: TimeInterval = 60
            selectedReadings = chartReadings.filter { abs($0.timestamp.timeIntervalSince(date)) <= threshold }
                .sorted { $0.isCirculating && !$1.isCirculating } // ECD first, then ESD
        }
    }
    #endif

    // MARK: - Readings Table Section

    #if os(macOS)
    private var readingsTableSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Readings")
                    .font(.headline)
                Spacer()
                Text("\(readings.count) readings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if readings.isEmpty {
                ContentUnavailableView {
                    Label("No Readings", systemImage: "list.bullet")
                } description: {
                    Text("Add your first reading above")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(readings) {
                    TableColumn("Time") { reading in
                        Button(action: {
                            editingTimestampReading = reading
                            editingTimestamp = reading.timestamp
                        }) {
                            HStack(spacing: 2) {
                                Text(reading.timestamp, format: .dateTime.hour().minute())
                                    .font(.caption)
                                Image(systemName: "pencil")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: Binding(
                            get: { editingTimestampReading?.id == reading.id },
                            set: { if !$0 { editingTimestampReading = nil } }
                        )) {
                            VStack(spacing: 12) {
                                Text("Edit Time")
                                    .font(.headline)
                                DatePicker("", selection: $editingTimestamp)
                                    .datePickerStyle(.graphical)
                                    .labelsHidden()
                                HStack {
                                    Button("Cancel") {
                                        editingTimestampReading = nil
                                    }
                                    .buttonStyle(.bordered)
                                    Spacer()
                                    Button("Save") {
                                        reading.timestamp = editingTimestamp
                                        try? modelContext.save()
                                        editingTimestampReading = nil
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                            .padding()
                            .frame(width: 300)
                        }
                    }
                    .width(60)

                    TableColumn("Mode") { reading in
                        Text(reading.isCirculating ? "Circ" : "S/I")
                            .font(.caption)
                            .foregroundStyle(reading.isCirculating ? .blue : .purple)
                    }
                    .width(32)

                    TableColumn("ρ") { reading in
                        Text("\(Int(reading.densityOut_kgm3))")
                            .font(.caption.monospacedDigit())
                    }
                    .width(38)

                    TableColumn("Q") { reading in
                        Text(reading.isCirculating ? String(format: "%.2f", reading.flowRate_m3_per_min) : "-")
                            .font(.caption.monospacedDigit())
                    }
                    .width(38)

                    TableColumn("APL/SIP") { reading in
                        Text(reading.isCirculating ? "\(Int(reading.aplToBit_kPa))" : "\(Int(reading.shutInPressure_kPa))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(reading.isCirculating ? .blue : .purple)
                    }
                    .width(50)

                    TableColumn("Heel") { reading in
                        Text("\(Int(reading.effectiveDensityAtHeel_kgm3))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(viewModel.densityColor(reading.effectiveDensityAtHeel_kgm3))
                    }
                    .width(38)

                    TableColumn("Bit") { reading in
                        Text("\(Int(reading.effectiveDensityAtBit_kgm3))")
                            .font(.caption.monospacedDigit())
                            .fontWeight(.medium)
                            .foregroundStyle(viewModel.densityColor(reading.effectiveDensityAtBit_kgm3))
                    }
                    .width(38)

                    TableColumn("Toe") { reading in
                        Text("\(Int(reading.effectiveDensityAtToe_kgm3))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(viewModel.densityColor(reading.effectiveDensityAtToe_kgm3).opacity(0.7))
                    }
                    .width(38)

                    TableColumn("Notes") { reading in
                        Text(reading.notes)
                            .font(.caption)
                            .lineLimit(1)
                    }

                    TableColumn("") { reading in
                        Button(action: {
                            readingToDelete = reading.id
                            showingDeleteConfirmation = true
                        }) {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .width(25)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }
    #endif

    // MARK: - iOS Sections

    #if os(iOS)
    private var configurationSectionIOS: some View {
        Section("Configuration") {
            TextField("Sheet Name", text: $viewModel.sheetName)

            HStack {
                Text("Heel MD (m)")
                Spacer()
                TextField("", value: $viewModel.heelMD_m, format: .number.precision(.fractionLength(1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
            }

            HStack {
                Text("Toe MD (m)")
                Spacer()
                TextField("", value: $viewModel.toeMD_m, format: .number.precision(.fractionLength(1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
            }

            HStack {
                Text("Pore Pressure (kg/m³)")
                Spacer()
                TextField("", value: $viewModel.porePressure_kgm3, format: .number.precision(.fractionLength(0)))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }

            HStack {
                Text("Frac Gradient (kg/m³)")
                Spacer()
                TextField("", value: $viewModel.fracGradient_kgm3, format: .number.precision(.fractionLength(0)))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }

            if viewModel.boundSheet != nil {
                Button("Update Configuration") {
                    viewModel.updateSheetConfiguration()
                }
            } else {
                Button("Create Sheet") {
                    viewModel.createSheet()
                }
            }
        }
    }

    private var inputSectionIOS: some View {
        Section("New Reading") {
            HStack {
                Text("Bit MD (m)")
                Spacer()
                TextField("", value: $editingBitMD, format: .number.precision(.fractionLength(1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .focused($bitMDFieldFocused)
                    .onChange(of: bitMDFieldFocused) { _, focused in
                        if !focused {
                            viewModel.bitMD_m = editingBitMD
                        }
                    }
                    .onSubmit {
                        viewModel.bitMD_m = editingBitMD
                    }
                Text("TVD: \(Int(viewModel.bitTVD_m))m")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

            Picker("Mode", selection: $viewModel.inputIsCirculating) {
                Text("Circulating").tag(true)
                Text("Shut-In").tag(false)
            }
            .pickerStyle(.segmented)

            if viewModel.inputIsCirculating {
                HStack {
                    Text("Flow Rate (m³/min)")
                    Spacer()
                    TextField("", value: $viewModel.inputFlowRate_m3_per_min, format: .number.precision(.fractionLength(3)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }

                HStack {
                    Text("Choke Friction (kPa)")
                    Spacer()
                    TextField("", value: $viewModel.inputChokeFriction_kPa, format: .number.precision(.fractionLength(0)))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            } else {
                HStack {
                    Text("Shut-In Pressure (kPa)")
                    Spacer()
                    TextField("", value: $viewModel.inputShutInPressure_kPa, format: .number.precision(.fractionLength(0)))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }

            HStack {
                Text("Density Out (kg/m³)")
                Spacer()
                TextField("", value: $viewModel.inputDensityOut_kgm3, format: .number.precision(.fractionLength(0)))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }

            TextField("Notes (optional)", text: $viewModel.inputNotes)

            if viewModel.bitExceedsGeometry {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Bit depth exceeds geometry by \(viewModel.geometryExtensionNeeded, specifier: "%.0f")m")
                        .foregroundStyle(.orange)
                }

                Button("Extend Geometry") {
                    showingExtendPrompt = true
                }
            }

            Button(action: {
                if viewModel.boundSheet == nil {
                    viewModel.createSheet()
                }
                viewModel.addReading()
            }) {
                Label("Add Reading", systemImage: "plus.circle.fill")
            }
            .disabled(viewModel.bitExceedsGeometry)
        }
    }

    private var previewSectionIOS: some View {
        Section("Preview") {
            if viewModel.inputIsCirculating {
                HStack {
                    Text("APL to Bit")
                    Spacer()
                    Text("\(Int(viewModel.previewAPLToBit_kPa)) kPa")
                        .monospacedDigit()
                        .fontWeight(.medium)
                }
                HStack {
                    Text("ECD at Heel")
                    Spacer()
                    Text("\(Int(viewModel.previewECDAtHeel_kgm3)) kg/m³")
                        .monospacedDigit()
                        .foregroundStyle(viewModel.densityColor(viewModel.previewECDAtHeel_kgm3))
                }
                HStack {
                    Text("ECD at Bit")
                    Spacer()
                    Text("\(Int(viewModel.previewECDAtBit_kgm3)) kg/m³")
                        .monospacedDigit()
                        .fontWeight(.medium)
                        .foregroundStyle(viewModel.densityColor(viewModel.previewECDAtBit_kgm3))
                }
                HStack {
                    Text("ECD at Toe (extrap)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(viewModel.previewECDAtToe_kgm3)) kg/m³")
                        .monospacedDigit()
                        .foregroundStyle(viewModel.densityColor(viewModel.previewECDAtToe_kgm3).opacity(0.7))
                }
            } else {
                HStack {
                    Text("ESD at Heel")
                    Spacer()
                    Text("\(Int(viewModel.previewESDAtHeel_kgm3)) kg/m³")
                        .monospacedDigit()
                        .foregroundStyle(viewModel.densityColor(viewModel.previewESDAtHeel_kgm3))
                }
                HStack {
                    Text("ESD at Bit")
                    Spacer()
                    Text("\(Int(viewModel.previewESDAtBit_kgm3)) kg/m³")
                        .monospacedDigit()
                        .fontWeight(.medium)
                        .foregroundStyle(viewModel.densityColor(viewModel.previewESDAtBit_kgm3))
                }
                HStack {
                    Text("ESD at Toe (extrap)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(viewModel.previewESDAtToe_kgm3)) kg/m³")
                        .monospacedDigit()
                        .foregroundStyle(viewModel.densityColor(viewModel.previewESDAtToe_kgm3).opacity(0.7))
                }
            }
        }
    }

    private var chartSectionIOS: some View {
        Section("Trend") {
            if viewModel.chartData.isEmpty {
                Text("Add readings to see the trend chart")
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    RuleMark(y: .value("Pore", viewModel.porePressure_kgm3))
                        .foregroundStyle(.orange.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

                    RuleMark(y: .value("Frac", viewModel.fracGradient_kgm3))
                        .foregroundStyle(.red.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))

                    ForEach(viewModel.chartData) { point in
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Heel", point.densityAtHeel_kgm3)
                        )
                        .foregroundStyle(.blue)
                    }

                    ForEach(viewModel.chartData) { point in
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Toe", point.densityAtToe_kgm3)
                        )
                        .foregroundStyle(.green)
                    }
                }
                .frame(height: 200)
            }
        }
    }

    private var readingsListSectionIOS: some View {
        Section("Readings (\(viewModel.readingRows.count))") {
            ForEach(viewModel.readingRows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(row.timestamp, format: .dateTime.hour().minute())
                            .font(.caption)
                        Spacer()
                        Text(row.isCirculating ? "Circulating" : "Shut-In")
                            .font(.caption)
                            .foregroundStyle(row.isCirculating ? .blue : .purple)
                    }
                    HStack {
                        Text("ρ: \(Int(row.densityOut_kgm3))")
                        if row.isCirculating {
                            Text("Q: \(row.flowRate_m3_per_min, specifier: "%.2f")")
                        }
                        Spacer()
                        Text("Heel: \(Int(row.effectiveDensityAtHeel_kgm3))")
                            .foregroundStyle(viewModel.densityColor(row.effectiveDensityAtHeel_kgm3))
                        Text("Bit: \(Int(row.effectiveDensityAtBit_kgm3))")
                            .fontWeight(.medium)
                            .foregroundStyle(viewModel.densityColor(row.effectiveDensityAtBit_kgm3))
                    }
                    .font(.caption.monospacedDigit())
                    if !row.notes.isEmpty {
                        Text(row.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let row = viewModel.readingRows[index]
                    viewModel.deleteReading(row.id)
                }
            }
        }
    }
    #endif
}

#Preview {
    let container = try! ModelContainer(
        for: ProjectState.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let project = ProjectState()
    container.mainContext.insert(project)

    return MPDTrackingView(project: project)
        .modelContainer(container)
        .frame(width: 1000, height: 700)
}
