//
//  SurgeSwabView.swift
//  Josh Well Control for Mac
//
//  Surge/Swab pressure calculator view with separate charts for each operation.
//

import SwiftUI
import SwiftData
import Charts

struct SurgeSwabView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState

    // MARK: - State

    @State private var startBitMD_m: Double = 0
    @State private var endBitMD_m: Double = 3000
    @State private var tripSpeed_m_per_min: Double = 15
    @State private var depthStep_m: Double = 50

    // Pipe end type
    @State private var pipeEndType: SurgeSwabCalculator.PipeEndType = .closed

    // Eccentricity factor (1.0 = concentric, >1 = eccentric)
    @State private var eccentricityFactor: Double = 1.0

    // Clinging constant: auto-calculate or manual override
    @State private var useAutoClinging: Bool = true
    @State private var manualClingingConstant: Double = 0.45

    @State private var results: [SurgeSwabCalculator.DepthResult] = []
    @State private var summary: SurgeSwabCalculator.Summary?

    @State private var hoveredSwabResult: SurgeSwabCalculator.DepthResult?
    @State private var hoveredSurgeResult: SurgeSwabCalculator.DepthResult?

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                mudInfoSection
                GroupBox(label: Label("Trip Parameters", systemImage: "slider.horizontal.3")) {
                    inputsGrid
                }
                if let sum = summary {
                    GroupBox(label: Label("Summary", systemImage: "gauge")) {
                        summaryGrid(sum)
                    }
                }

                // Two separate charts
                HStack(spacing: 16) {
                    // Swab chart (POOH) - deepest on left
                    GroupBox(label: Label("Swab (Pull Out of Hole)", systemImage: "arrow.up")) {
                        swabChartControls
                        swabChart
                    }

                    // Surge chart (RIH) - deepest on right
                    GroupBox(label: Label("Surge (Run In Hole)", systemImage: "arrow.down")) {
                        surgeChartControls
                        surgeChart
                    }
                }

                // Calculation details
                if let sum = summary {
                    calculationDetailsSection(sum)
                }
            }
            .padding(16)
        }
        .onAppear {
            initializeFromProject()
            compute()
        }
        .onChange(of: project.annulus) { _, _ in compute() }
        .onChange(of: project.drillString) { _, _ in compute() }
        .onChange(of: project.activeMud?.density_kgm3) { _, _ in compute() }
        .onChange(of: project.activeMud?.pv_Pa_s) { _, _ in compute() }
        .onChange(of: project.activeMud?.yp_Pa) { _, _ in compute() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Surge/Swab Pressure Calculator")
                    .font(.headline)
                Text("Calculate pressure changes during tripping based on pipe displacement and mud rheology")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                compute()
            } label: {
                Label("Calculate", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return)
        }
    }

    // MARK: - Mud Info Section

    private var mudInfoSection: some View {
        GroupBox(label: Label("Active Mud", systemImage: "drop.fill")) {
            if let mud = project.activeMud {
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mud.name)
                            .font(.headline)
                        Text("Density: \(String(format: "%.0f", mud.density_kgm3)) kg/m³")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider().frame(height: 40)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Rheology")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        if let pv = mud.pv_Pa_s, let yp = mud.yp_Pa {
                            HStack(spacing: 16) {
                                Text("PV: \(String(format: "%.1f", pv * 1000)) mPa·s")
                                Text("YP: \(String(format: "%.1f", yp / HydraulicsDefaults.fann35_dialToPa)) lb/100ft²")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else if let d600 = mud.dial600, let d300 = mud.dial300 {
                            HStack(spacing: 16) {
                                Text("θ600: \(String(format: "%.0f", d600))")
                                Text("θ300: \(String(format: "%.0f", d300))")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else {
                            Text("No rheology data - using defaults")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("No active mud selected. Using default values (ρ=1100 kg/m³, PV=20 mPa·s, YP=10 Pa)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Inputs

    private var inputsGrid: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow {
                labeledField("Shallow MD (m)") {
                    HStack(spacing: 4) {
                        TextField("Shallow", value: $startBitMD_m, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Stepper("", value: $startBitMD_m, in: 0...20000, step: 100)
                            .labelsHidden()
                            .frame(width: 20)
                    }
                }
                labeledField("Deep MD (m)") {
                    HStack(spacing: 4) {
                        TextField("Deep", value: $endBitMD_m, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Stepper("", value: $endBitMD_m, in: 0...20000, step: 100)
                            .labelsHidden()
                            .frame(width: 20)
                    }
                }
                labeledField("Trip Speed (m/min)") {
                    HStack(spacing: 4) {
                        TextField("Speed", value: $tripSpeed_m_per_min, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Stepper("", value: $tripSpeed_m_per_min, in: 1...60, step: 1)
                            .labelsHidden()
                            .frame(width: 20)
                    }
                }
            }
            GridRow {
                labeledField("Depth Step (m)") {
                    HStack(spacing: 4) {
                        TextField("Step", value: $depthStep_m, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Stepper("", value: $depthStep_m, in: 10...500, step: 10)
                            .labelsHidden()
                            .frame(width: 20)
                    }
                }
                labeledField("Pipe End") {
                    Picker("", selection: $pipeEndType) {
                        ForEach(SurgeSwabCalculator.PipeEndType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .onChange(of: pipeEndType) { _, _ in compute() }
                }
                labeledField("Eccentricity ×") {
                    HStack(spacing: 4) {
                        TextField("Ecc", value: $eccentricityFactor, format: .number.precision(.fractionLength(1)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Stepper("", value: $eccentricityFactor, in: 1.0...2.0, step: 0.1)
                            .labelsHidden()
                            .frame(width: 20)
                    }
                    .onChange(of: eccentricityFactor) { _, _ in compute() }
                }
            }
            GridRow {
                labeledField("Clinging Constant") {
                    HStack(spacing: 8) {
                        Toggle("Auto", isOn: $useAutoClinging)
                            #if os(macOS)
                            .toggleStyle(.checkbox)
                            #endif
                            .onChange(of: useAutoClinging) { _, _ in compute() }

                        if !useAutoClinging {
                            TextField("k", value: $manualClingingConstant, format: .number.precision(.fractionLength(2)))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                            Stepper("", value: $manualClingingConstant, in: 0.3...0.65, step: 0.05)
                                .labelsHidden()
                                .frame(width: 20)
                        } else if let sum = summary {
                            Text(String(format: "≈ %.2f", sum.averageClingingConstant))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                EmptyView()
                EmptyView()
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Summary

    private func summaryGrid(_ sum: SurgeSwabCalculator.Summary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    resultBox(title: "Max Swab", value: sum.maxSwabPressure_kPa, unit: "kPa", tint: .blue)
                    resultBox(title: "Swab ECD Δ", value: sum.maxSwabECD_kgm3, unit: "kg/m³", tint: .blue)
                    resultBox(title: "Max Surge", value: sum.maxSurgePressure_kPa, unit: "kPa", tint: .red)
                    resultBox(title: "Surge ECD Δ", value: sum.maxSurgeECD_kgm3, unit: "kg/m³", tint: .red)
                }
                GridRow {
                    HStack {
                        Text("Max swab at:").font(.caption).foregroundStyle(.secondary)
                        Text("\(Int(sum.depthOfMaxSwab_m)) m").monospacedDigit()
                    }
                    HStack {
                        Text("Pipe end:").font(.caption).foregroundStyle(.secondary)
                        Text(pipeEndType.rawValue).monospacedDigit()
                    }
                    HStack {
                        Text("Max surge at:").font(.caption).foregroundStyle(.secondary)
                        Text("\(Int(sum.depthOfMaxSurge_m)) m").monospacedDigit()
                    }
                    HStack {
                        Text("Avg clinging:").font(.caption).foregroundStyle(.secondary)
                        Text(String(format: "%.3f", sum.averageClingingConstant)).monospacedDigit()
                    }
                }
                GridRow {
                    HStack {
                        Text("Pipe OD:").font(.caption).foregroundStyle(.secondary)
                        Text(String(format: "%.4f m", sum.pipeOD_m)).monospacedDigit()
                    }
                    HStack {
                        Text("Pipe ID:").font(.caption).foregroundStyle(.secondary)
                        Text(String(format: "%.4f m", sum.pipeID_m)).monospacedDigit()
                            .foregroundStyle(sum.hasMissingPipeID ? .orange : .primary)
                    }
                    HStack {
                        Text("Disp. Area:").font(.caption).foregroundStyle(.secondary)
                        Text(String(format: "%.6f m²", sum.pipeDisplacementArea_m2)).monospacedDigit()
                    }
                    EmptyView()
                }
            }

            // Warning if pipe ID is missing
            if sum.hasMissingPipeID {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Drill string inner diameter is 0 or missing. Open and Closed pipe end will give identical results. Update your drill string to add pipe ID values.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Swab Chart (POOH - deepest on left)

    private var swabChartControls: some View {
        HStack {
            Text("← Deep")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            if let hovered = hoveredSwabResult {
                HStack(spacing: 8) {
                    Text("MD: \(Int(hovered.bitMD_m))m").monospacedDigit()
                    Text("\(String(format: "%.0f", abs(hovered.swabPressure_kPa))) kPa").foregroundStyle(.blue).monospacedDigit()
                    Text("k: \(String(format: "%.2f", hovered.clingingConstant))").foregroundStyle(.secondary).monospacedDigit()
                    Text(hovered.flowRegime).font(.caption2).padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(hovered.flowRegime == "Turbulent" ? Color.orange.opacity(0.2) : Color.green.opacity(0.2)))
                }
                .font(.caption)
            }
            Spacer()
            Text("Shallow →")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    private var swabChart: some View {
        Group {
            if !results.isEmpty {
                Chart {
                    ForEach(results) { result in
                        LineMark(
                            x: .value("Depth", result.bitMD_m),
                            y: .value("Swab (kPa)", abs(result.swabPressure_kPa))
                        )
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)
                    }
                    if let hovered = hoveredSwabResult {
                        RuleMark(x: .value("Hover", hovered.bitMD_m))
                            .foregroundStyle(.primary.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                        PointMark(
                            x: .value("Depth", hovered.bitMD_m),
                            y: .value("Swab", abs(hovered.swabPressure_kPa))
                        )
                        .foregroundStyle(.blue)
                        .symbolSize(100)
                    }
                }
                .chartXScale(domain: .automatic(includesZero: false, reversed: true))  // Deepest on left
                .chartXAxisLabel("Bit Depth (m)")
                .chartYAxisLabel("Swab Pressure (kPa)")
                .frame(minHeight: 300)
                .chartOverlay { proxy in
                    swabChartHoverOverlay(proxy: proxy)
                }
            } else {
                emptyChartPlaceholder
            }
        }
    }

    private func swabChartHoverOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        if let plotFrame = proxy.plotFrame {
                            let plotAreaOrigin = geo[plotFrame].origin
                            let x = location.x - plotAreaOrigin.x
                            if let depth: Double = proxy.value(atX: x) {
                                hoveredSwabResult = results.min(by: { abs($0.bitMD_m - depth) < abs($1.bitMD_m - depth) })
                            }
                        }
                    case .ended:
                        hoveredSwabResult = nil
                    }
                }
        }
    }

    // MARK: - Surge Chart (RIH - deepest on right)

    private var surgeChartControls: some View {
        HStack {
            Text("← Shallow")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            if let hovered = hoveredSurgeResult {
                HStack(spacing: 8) {
                    Text("MD: \(Int(hovered.bitMD_m))m").monospacedDigit()
                    Text("\(String(format: "%.0f", hovered.surgePressure_kPa)) kPa").foregroundStyle(.red).monospacedDigit()
                    Text("k: \(String(format: "%.2f", hovered.clingingConstant))").foregroundStyle(.secondary).monospacedDigit()
                    Text(hovered.flowRegime).font(.caption2).padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(hovered.flowRegime == "Turbulent" ? Color.orange.opacity(0.2) : Color.green.opacity(0.2)))
                }
                .font(.caption)
            }
            Spacer()
            Text("Deep →")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    private var surgeChart: some View {
        Group {
            if !results.isEmpty {
                Chart {
                    ForEach(results) { result in
                        LineMark(
                            x: .value("Depth", result.bitMD_m),
                            y: .value("Surge (kPa)", result.surgePressure_kPa)
                        )
                        .foregroundStyle(.red)
                        .interpolationMethod(.catmullRom)
                    }
                    if let hovered = hoveredSurgeResult {
                        RuleMark(x: .value("Hover", hovered.bitMD_m))
                            .foregroundStyle(.primary.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                        PointMark(
                            x: .value("Depth", hovered.bitMD_m),
                            y: .value("Surge", hovered.surgePressure_kPa)
                        )
                        .foregroundStyle(.red)
                        .symbolSize(100)
                    }
                }
                .chartXScale(domain: .automatic(includesZero: false, reversed: false))  // Deepest on right
                .chartXAxisLabel("Bit Depth (m)")
                .chartYAxisLabel("Surge Pressure (kPa)")
                .frame(minHeight: 300)
                .chartOverlay { proxy in
                    surgeChartHoverOverlay(proxy: proxy)
                }
            } else {
                emptyChartPlaceholder
            }
        }
    }

    private func surgeChartHoverOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        if let plotFrame = proxy.plotFrame {
                            let plotAreaOrigin = geo[plotFrame].origin
                            let x = location.x - plotAreaOrigin.x
                            if let depth: Double = proxy.value(atX: x) {
                                hoveredSurgeResult = results.min(by: { abs($0.bitMD_m - depth) < abs($1.bitMD_m - depth) })
                            }
                        }
                    case .ended:
                        hoveredSurgeResult = nil
                    }
                }
        }
    }

    // MARK: - Shared

    private var emptyChartPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.05))
            VStack(spacing: 6) {
                Image(systemName: "chart.xyaxis.line")
                    .foregroundStyle(.secondary)
                Text("No results. Configure parameters and click Calculate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 300)
    }

    // MARK: - Calculation Details

    @State private var showCalculationDetails: Bool = false

    private func calculationDetailsSection(_ sum: SurgeSwabCalculator.Summary) -> some View {
        DisclosureGroup("Calculation Details", isExpanded: $showCalculationDetails) {
            VStack(alignment: .leading, spacing: 16) {
                // Pipe Displacement Comparison
                HStack(alignment: .top, spacing: 32) {
                    // Pipe Geometry
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pipe Geometry").font(.subheadline).fontWeight(.medium)
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                            GridRow {
                                Text("Outer Diameter (OD):").font(.caption).foregroundStyle(.secondary)
                                Text(String(format: "%.4f m  (%.3f in)", sum.pipeOD_m, sum.pipeOD_m * 39.3701))
                                    .font(.caption).monospacedDigit()
                            }
                            GridRow {
                                Text("Inner Diameter (ID):").font(.caption).foregroundStyle(.secondary)
                                Text(String(format: "%.4f m  (%.3f in)", sum.pipeID_m, sum.pipeID_m * 39.3701))
                                    .font(.caption).monospacedDigit()
                                    .foregroundStyle(sum.hasMissingPipeID ? .orange : .primary)
                            }
                            GridRow {
                                Text("Wall Thickness:").font(.caption).foregroundStyle(.secondary)
                                let wall = (sum.pipeOD_m - sum.pipeID_m) / 2
                                Text(String(format: "%.4f m  (%.3f in)", wall, wall * 39.3701))
                                    .font(.caption).monospacedDigit()
                            }
                        }
                    }

                    Divider()

                    // Displacement Areas
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Displacement Areas").font(.subheadline).fontWeight(.medium)
                        let closedArea = Double.pi / 4.0 * sum.pipeOD_m * sum.pipeOD_m
                        let openArea = Double.pi / 4.0 * (sum.pipeOD_m * sum.pipeOD_m - sum.pipeID_m * sum.pipeID_m)
                        let difference = closedArea - openArea
                        let ratio = openArea > 0 ? (difference / closedArea) * 100 : 0

                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                            GridRow {
                                Text("Closed (π/4 × OD²):").font(.caption).foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    Text(String(format: "%.6f m²", closedArea))
                                        .font(.caption).monospacedDigit()
                                        .foregroundStyle(pipeEndType == .closed ? .green : .secondary)
                                    if pipeEndType == .closed {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                            .font(.caption)
                                    }
                                }
                            }
                            GridRow {
                                Text("Open (π/4 × (OD²-ID²)):").font(.caption).foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    Text(String(format: "%.6f m²", openArea))
                                        .font(.caption).monospacedDigit()
                                        .foregroundStyle(pipeEndType == .open ? .green : .secondary)
                                    if pipeEndType == .open {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                            .font(.caption)
                                    }
                                }
                            }
                            GridRow {
                                Text("Ratio (Closed/Open):").font(.caption).foregroundStyle(.secondary)
                                Text(String(format: "%.2f× (Closed is %.0f%% larger)", closedArea / max(openArea, 0.0001), ratio))
                                    .font(.caption).monospacedDigit()
                            }
                            GridRow {
                                Text("Active Displacement:").font(.caption).foregroundStyle(.secondary)
                                Text(String(format: "%.6f m² (%@)", sum.pipeDisplacementArea_m2, sum.pipeEndType.rawValue))
                                    .font(.caption).monospacedDigit()
                                    .fontWeight(.medium)
                            }
                        }

                        // Verification
                        let stateMatchesSummary = (pipeEndType == sum.pipeEndType)
                        let expectedArea = pipeEndType == .closed ? closedArea : openArea
                        let areaMatchesExpected = abs(sum.pipeDisplacementArea_m2 - expectedArea) < 0.0001

                        if !stateMatchesSummary || !areaMatchesExpected {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text("Mismatch detected! View: \(pipeEndType.rawValue), Summary: \(sum.pipeEndType.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    Divider()

                    // Mud Properties
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mud Properties").font(.subheadline).fontWeight(.medium)
                        if let mud = project.activeMud {
                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                                GridRow {
                                    Text("Density:").font(.caption).foregroundStyle(.secondary)
                                    Text(String(format: "%.0f kg/m³", mud.density_kgm3))
                                        .font(.caption).monospacedDigit()
                                }
                                if let pv = mud.pv_Pa_s {
                                    GridRow {
                                        Text("Plastic Viscosity:").font(.caption).foregroundStyle(.secondary)
                                        Text(String(format: "%.1f mPa·s (%.1f cP)", pv * 1000, pv * 1000))
                                            .font(.caption).monospacedDigit()
                                    }
                                }
                                if let yp = mud.yp_Pa {
                                    GridRow {
                                        Text("Yield Point:").font(.caption).foregroundStyle(.secondary)
                                        Text(String(format: "%.1f Pa (%.1f lb/100ft²)", yp, yp / HydraulicsDefaults.fann35_dialToPa))
                                            .font(.caption).monospacedDigit()
                                    }
                                }
                            }
                        } else {
                            Text("Using defaults: ρ=1100 kg/m³, PV=20 mPa·s, YP=10 Pa")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }

                // Annulus Info
                if let annulus = project.annulus, !annulus.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Annulus Sections").font(.subheadline).fontWeight(.medium)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(annulus.sorted(by: { $0.topDepth_m < $1.topDepth_m }), id: \.id) { section in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(section.name).font(.caption).fontWeight(.medium)
                                        Text("\(Int(section.topDepth_m))-\(Int(section.bottomDepth_m)) m")
                                            .font(.caption2).foregroundStyle(.secondary)
                                        Text(String(format: "ID: %.4f m", section.innerDiameter_m))
                                            .font(.caption2).monospacedDigit()
                                    }
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.1)))
                                }
                            }
                        }
                    }
                }

                // Explanation
                if sum.hasMissingPipeID || (sum.pipeOD_m > 0 && sum.pipeID_m > 0) {
                    let closedArea = Double.pi / 4.0 * sum.pipeOD_m * sum.pipeOD_m
                    let openArea = Double.pi / 4.0 * (sum.pipeOD_m * sum.pipeOD_m - sum.pipeID_m * sum.pipeID_m)
                    let ratio = closedArea > 0 ? ((closedArea - openArea) / closedArea) * 100 : 0

                    if ratio < 10 {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Why is the difference small?")
                                    .font(.caption).fontWeight(.medium)
                                Text("For typical drill pipe, the wall thickness is thin relative to the OD (e.g., 5\" OD × 4.276\" ID = 0.362\" wall). The open-end displacement (pipe wall area only) is only about \(String(format: "%.0f", ratio))% less than closed-end (full OD area). This results in a proportionally small difference in surge/swab pressures.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.05)))
                    }
                }
            }
            .padding(.top, 8)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.05)))
    }

    // MARK: - Helpers

    @ViewBuilder
    private func labeledField(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .trailing)
            content()
        }
    }

    @ViewBuilder
    private func resultBox(title: String, value: Double, unit: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", value))
                    .font(.title3).monospacedDigit()
                    .foregroundStyle(tint)
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))
    }

    // MARK: - Computation

    private func initializeFromProject() {
        // Set default depths from annulus/drill string if available
        if let maxAnn = project.annulus?.map({ $0.bottomDepth_m }).max() {
            endBitMD_m = maxAnn
        }
        if let maxDS = project.drillString?.map({ $0.bottomDepth_m }).max() {
            endBitMD_m = max(endBitMD_m, maxDS)
        }
        // Start at surface for the range
        startBitMD_m = 0
    }

    private func compute() {
        let annulus = project.annulus ?? []
        let drillString = project.drillString ?? []

        guard !annulus.isEmpty && !drillString.isEmpty else {
            results = []
            summary = nil
            return
        }

        // Calculate from shallow to deep (results work for both charts)
        let calculator = SurgeSwabCalculator(
            tripSpeed_m_per_min: tripSpeed_m_per_min,
            startBitMD_m: startBitMD_m,
            endBitMD_m: endBitMD_m,
            depthStep_m: depthStep_m,
            annulusSections: annulus,
            drillStringSections: drillString,
            mud: project.activeMud,
            clingingConstantOverride: useAutoClinging ? nil : manualClingingConstant,
            pipeEndType: pipeEndType,
            eccentricityFactor: eccentricityFactor
        )

        results = calculator.calculate(tvdLookup: { md in
            project.tvd(of: md)
        })

        summary = calculator.summarize(results)
    }
}

#Preview {
    Text("SurgeSwabView Preview")
}
