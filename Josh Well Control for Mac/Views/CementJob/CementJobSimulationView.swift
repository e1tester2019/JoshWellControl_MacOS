//
//  CementJobSimulationView.swift
//  Josh Well Control for Mac
//
//  Interactive cement job simulation view with fluid tracking and tank volume monitoring
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct CementJobSimulationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var project: ProjectState
    @Bindable var job: CementJob
    @State private var viewModel = CementJobSimulationViewModel()
    @State private var showCopiedAlert = false
    @State private var lossZoneDepthInput: Double = 0
    @State private var showLossZoneDebug = false
    @State private var editableJobReport: String = ""

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            // Header with job info
            headerSection

            Divider()

            HStack(alignment: .top, spacing: 16) {
                // Left panel: Stage list and controls
                ScrollView {
                    VStack(spacing: 12) {
                        tankVolumeSection
                        lossZoneSection
                        pumpRateSection
                        stageListSection
                        returnSummarySection
                        jobReportSection
                    }
                }
                .frame(width: 320)

                Divider()

                // Right panel: Visualization
                VStack(spacing: 12) {
                    currentStageInfoSection
                    fluidVisualizationSection
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .onAppear {
            viewModel.bootstrap(job: job, project: project, context: modelContext)
            editableJobReport = viewModel.generateJobReportText(jobName: job.name, casingType: job.casingType.displayName)
        }
        .onChange(of: viewModel.currentStageIndex) {
            editableJobReport = viewModel.generateJobReportText(jobName: job.name, casingType: job.casingType.displayName)
        }
        .navigationTitle("Cement Job Simulation")
        #else
        // iOS/iPadOS layout
        bodyIOS
        #endif
    }

    // MARK: - iOS Body
    #if os(iOS)
    private var bodyIOS: some View {
        NavigationStack {
            GeometryReader { geo in
                let isLandscape = geo.size.width > geo.size.height

                ScrollView {
                    VStack(spacing: 0) {
                        // Job info header
                        sheetHeaderIOS

                        Divider()
                            .padding(.vertical, 8)

                        if isLandscape {
                            // Landscape: side-by-side layout
                            landscapeLayoutIOS
                        } else {
                            // Portrait: stacked layout
                            portraitLayoutIOS
                        }
                    }
                }
            }
            .navigationTitle("Cement Job Simulation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: copyJobReport) {
                            Label("Copy Job Report", systemImage: "doc.text")
                        }
                        Button(action: copySimulationSummary) {
                            Label("Copy Detailed Summary", systemImage: "doc.on.doc")
                        }
                        Divider()
                        Button(action: copyWellProfileImage) {
                            Label("Copy Well Profile Image", systemImage: "photo")
                        }
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
            .overlay(alignment: .top) {
                if showCopiedAlert {
                    Text("Copied!")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.green.opacity(0.9)))
                        .foregroundColor(.white)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 60)
                }
            }
        }
        .onAppear {
            viewModel.bootstrap(job: job, project: project, context: modelContext)
            editableJobReport = viewModel.generateJobReportText(jobName: job.name, casingType: job.casingType.displayName)
        }
        .onChange(of: viewModel.currentStageIndex) {
            editableJobReport = viewModel.generateJobReportText(jobName: job.name, casingType: job.casingType.displayName)
        }
    }

    private var sheetHeaderIOS: some View {
        VStack(spacing: 4) {
            Text(job.name.isEmpty ? "Cement Job" : job.name)
                .font(.headline)

            Text("\(job.casingType.displayName) - \(String(format: "%.0f", job.topMD_m))m to \(String(format: "%.0f", job.bottomMD_m))m")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var landscapeLayoutIOS: some View {
        HStack(alignment: .top, spacing: 16) {
            // Left: Controls
            ScrollView {
                VStack(spacing: 12) {
                    currentStageInfoSectionIOS
                    tankVolumeSectionIOS
                    lossZoneSectionIOS
                    pumpRateSectionIOS
                    returnSummarySectionIOS
                }
            }
            .frame(width: 340)

            // Right: Visualization, stage list, and job report
            VStack(spacing: 12) {
                fluidVisualizationSectionIOS
                stageListSectionIOS
                jobReportSectionIOS
            }
        }
        .padding()
    }

    private var portraitLayoutIOS: some View {
        VStack(spacing: 16) {
            // Current stage and controls at top
            currentStageInfoSectionIOS

            // Visualization
            fluidVisualizationSectionIOS

            // Stage list
            stageListSectionIOS

            // Tank and return info
            HStack(alignment: .top, spacing: 12) {
                tankVolumeSectionIOS
                returnSummarySectionIOS
            }

            // Loss zone and pump rate
            HStack(alignment: .top, spacing: 12) {
                lossZoneSectionIOS
                pumpRateSectionIOS
            }

            // Job report
            jobReportSectionIOS
        }
        .padding()
    }
    #endif

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(job.name)
                    .font(.headline)
                Text("\(job.casingType.displayName) - \(String(format: "%.0f", job.topMD_m))m to \(String(format: "%.0f", job.bottomMD_m))m")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Navigation controls
            HStack(spacing: 12) {
                Button(action: { viewModel.previousStage() }) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title2)
                }
                .disabled(viewModel.isAtStart)
                .buttonStyle(.plain)

                Text("Stage \(viewModel.currentStageIndex + 1) of \(viewModel.stages.count)")
                    .font(.caption)
                    .monospacedDigit()

                Button(action: { viewModel.nextStage() }) {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title2)
                }
                .disabled(viewModel.isAtEnd)
                .buttonStyle(.plain)
            }

            Spacer().frame(width: 20)

            // Copy and Close buttons
            HStack(spacing: 12) {
                Menu {
                    Button(action: copyJobReport) {
                        Label("Copy Job Report", systemImage: "doc.text")
                    }
                    Button(action: copySimulationSummary) {
                        Label("Copy Detailed Summary", systemImage: "doc.on.doc")
                    }
                    Divider()
                    Button(action: copyWellProfileImage) {
                        Label("Copy Well Profile Image", systemImage: "photo")
                    }
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .menuStyle(.borderlessButton)

                Button(action: { dismiss() }) {
                    Label("Close", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding()
        .overlay(alignment: .topTrailing) {
            if showCopiedAlert {
                Text("Copied!")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.green.opacity(0.9)))
                    .foregroundColor(.white)
                    .transition(.opacity)
                    .offset(x: -100, y: 8)
            }
        }
    }

    // MARK: - Tank Volume Section

    private var tankVolumeSection: some View {
        GroupBox("Tank Volume Tracking") {
            VStack(alignment: .leading, spacing: 12) {
                // Initial tank volume
                HStack {
                    Text("Initial Volume:")
                        .frame(width: 120, alignment: .leading)
                    TextField("m³", value: $viewModel.initialTankVolume_m3, format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Text("m³")
                        .foregroundColor(.secondary)
                }

                Divider()

                // Expected tank volume (what it should be at 1:1 ratio)
                HStack {
                    Text("Expected Volume:")
                        .frame(width: 120, alignment: .leading)
                    Text(String(format: "%.2f m³", viewModel.expectedTankVolume_m3))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }

                // Actual/Current tank volume
                HStack {
                    Text("Actual Volume:")
                        .frame(width: 120, alignment: .leading)
                    TextField("m³", value: Binding(
                        get: { viewModel.currentTankVolume_m3 },
                        set: { viewModel.recordTankVolume($0) }
                    ), format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Text("m³")
                        .foregroundColor(.secondary)

                    if !viewModel.isAutoTrackingTankVolume {
                        Button(action: { viewModel.resetTankVolumeToExpected() }) {
                            Image(systemName: "arrow.counterclockwise")
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help("Reset to expected volume")
                    }
                }

                // Difference display
                if abs(viewModel.tankVolumeDifference_m3) > 0.01 {
                    HStack {
                        Text("Difference:")
                            .frame(width: 120, alignment: .leading)
                        Text(String(format: "%+.2f m³", viewModel.tankVolumeDifference_m3))
                            .fontWeight(.medium)
                            .foregroundColor(viewModel.tankVolumeDifference_m3 >= 0 ? .green : .orange)
                            .monospacedDigit()

                        if viewModel.tankVolumeDifference_m3 < 0 {
                            Text("(losses)")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else if viewModel.tankVolumeDifference_m3 > 0 {
                            Text("(gains)")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }

                // Auto-tracking indicator
                if viewModel.isAutoTrackingTankVolume {
                    HStack {
                        Image(systemName: "link")
                            .foregroundColor(.green)
                        Text("Auto-tracking with slider")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack {
                        Image(systemName: "link.badge.plus")
                            .foregroundColor(.orange)
                        Text("Manual override active")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(8)
        }
    }

    // MARK: - Loss Zone Section

    private var lossZoneSection: some View {
        GroupBox("Loss Zone Simulation") {
            VStack(alignment: .leading, spacing: 12) {
                // Add loss zone input
                HStack {
                    Text("Depth:")
                        .frame(width: 80, alignment: .leading)
                    TextField("MD", value: $lossZoneDepthInput, format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("m MD")
                        .foregroundColor(.secondary)

                    Button(action: {
                        if lossZoneDepthInput > 0 && lossZoneDepthInput < viewModel.shoeDepth_m {
                            viewModel.addLossZone(atMD: lossZoneDepthInput)
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .disabled(lossZoneDepthInput <= 0 || lossZoneDepthInput >= viewModel.shoeDepth_m)
                }

                // Active loss zones
                if viewModel.lossZones.isEmpty {
                    Text("No loss zones configured")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(viewModel.lossZones.enumerated()), id: \.offset) { index, zone in
                        HStack(alignment: .top) {
                            Image(systemName: zone.isActive ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(zone.isActive ? .green : .secondary)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("\(Int(zone.depth_m))m MD")
                                        .fontWeight(.medium)
                                    Text("(\(Int(zone.tvd_m))m TVD)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                // Frac pressure and gradient
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Frac Pressure")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("\(String(format: "%.0f", zone.frac_kPa)) kPa")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.red)
                                    }

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Gradient")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("\(String(format: "%.2f", zone.fracGradient_kPa_per_m)) kPa/m")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("EMW")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("\(String(format: "%.0f", zone.fracEMW_kg_m3)) kg/m³")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                }
                            }

                            Spacer()

                            Button(action: {
                                viewModel.lossZones.remove(at: index)
                                viewModel.updateFluidStacks()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Show losses info if any
                if viewModel.totalLossVolume_m3 > 0.01 {
                    Divider()
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Formation Losses:")
                        Spacer()
                        Text(String(format: "%.2f m³", viewModel.totalLossVolume_m3))
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                            .monospacedDigit()
                    }
                }

                // Debug toggle
                if !viewModel.lossZones.isEmpty {
                    Divider()
                    Toggle("Show Debug", isOn: $showLossZoneDebug)
                        .font(.caption)

                    if showLossZoneDebug {
                        ScrollView {
                            Text(viewModel.lossZoneDebugInfo)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                    }
                }
            }
            .padding(8)
        }
    }

    // MARK: - Pump Rate Section

    private var pumpRateSection: some View {
        GroupBox("Pump Rate & Velocities") {
            VStack(alignment: .leading, spacing: 12) {
                // Pump rate slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Pump Rate:")
                            .frame(width: 90, alignment: .leading)
                        Text(String(format: "%.2f m³/min", viewModel.pumpRate_m3_per_min))
                            .fontWeight(.medium)
                            .monospacedDigit()
                        Spacer()
                    }

                    Slider(
                        value: Binding(
                            get: { viewModel.pumpRate_m3_per_min },
                            set: { viewModel.setPumpRate($0) }
                        ),
                        in: 0.05...2.0,
                        step: 0.05
                    )

                    HStack {
                        Text("0.05")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("2.0 m³/min")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Show APL and total pressure at loss zone if there's an active loss zone
                if !viewModel.lossZones.isEmpty && viewModel.totalPressureAtLossZone_kPa > 0 {
                    Divider()
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("APL")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(String(format: "%.0f", viewModel.aplAboveLossZone_kPa)) kPa")
                                .font(.caption)
                                .fontWeight(.medium)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Total @ LZ")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(String(format: "%.0f", viewModel.totalPressureAtLossZone_kPa)) kPa")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                }

                // Annular velocities per section
                if !viewModel.annulusSectionInfos.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Annular Velocities")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        ForEach(viewModel.annulusSectionInfos) { section in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(section.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Text("\(Int(section.topMD_m))-\(Int(section.bottomMD_m))m")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text(String(format: "%.1f m/min", section.velocity_m_per_min))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(section.isOverSpeedLimit ? .red : .primary)
                                    .monospacedDigit()

                                if section.isOverSpeedLimit {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                        }

                        // Max velocity limit warning
                        if let maxVel = viewModel.maxVelocityLimit_m_per_min {
                            HStack {
                                Text("Max limit:")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.1f m/min", maxVel))
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    // MARK: - Stage List Section

    private var stageListSection: some View {
        GroupBox("Cement Job Stages") {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(viewModel.stages.enumerated()), id: \.element.id) { index, stage in
                        stageRow(stage: stage, index: index)
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: 300)
        }
    }

    private func stageRow(stage: CementJobSimulationViewModel.SimulationStage, index: Int) -> some View {
        let isCurrentStage = index == viewModel.currentStageIndex
        let isCompleted = index < viewModel.currentStageIndex
        let isPending = index > viewModel.currentStageIndex

        return Button(action: { viewModel.jumpToStage(index) }) {
            HStack(spacing: 8) {
                // Status indicator
                ZStack {
                    Circle()
                        .fill(stage.isOperation ? Color.clear : stage.color)
                        .frame(width: 24, height: 24)

                    if stage.isOperation {
                        Image(systemName: operationIcon(stage.operationType))
                            .font(.caption)
                            .foregroundColor(.primary)
                    }

                    if isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .background(Circle().fill(.white).padding(2))
                    } else if isCurrentStage {
                        Circle()
                            .strokeBorder(Color.accentColor, lineWidth: 3)
                            .frame(width: 28, height: 28)
                    }
                }

                // Stage info
                VStack(alignment: .leading, spacing: 2) {
                    Text(stage.name)
                        .font(.callout)
                        .fontWeight(isCurrentStage ? .semibold : .regular)
                        .lineLimit(1)

                    if !stage.isOperation && stage.volume_m3 > 0 {
                        Text(String(format: "%.2f m³ @ %.0f kg/m³", stage.volume_m3, stage.density_kgm3))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else if stage.isOperation {
                        Text(operationSubtitle(stage))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Tank reading if recorded
                if let tankReading = viewModel.tankVolumeForStage(stage.id) {
                    Text(String(format: "%.1f m³", tankReading))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                // Progress for current stage
                if isCurrentStage && !stage.isOperation {
                    Text(String(format: "%.0f%%", viewModel.progress * 100))
                        .font(.caption)
                        .foregroundColor(.accentColor)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isCurrentStage ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .opacity(isPending ? 0.6 : 1.0)
        }
        .buttonStyle(.plain)
    }

    private func operationIcon(_ opType: CementJobStage.OperationType?) -> String {
        switch opType {
        case .pressureTestLines, .pressureTestCasing: return "gauge.with.needle"
        case .tripSet: return "arrow.down.to.line"
        case .plugDrop: return "arrow.down.circle"
        case .bumpPlug: return "arrow.up.circle"
        case .floatCheck: return "checkmark.seal"
        case .bleedBack: return "arrow.up.forward"
        case .rigOut: return "wrench"
        default: return "gearshape"
        }
    }

    private func operationSubtitle(_ stage: CementJobSimulationViewModel.SimulationStage) -> String {
        guard let sourceStage = stage.sourceStage else { return "" }

        if let pressure = sourceStage.pressure_MPa {
            return String(format: "%.1f MPa", pressure)
        }
        if let duration = sourceStage.duration_min {
            return String(format: "%.0f min", duration)
        }
        return stage.operationType?.displayName ?? ""
    }

    // MARK: - Operation Edit Fields

    @ViewBuilder
    private func operationEditFields(for stage: CementJobStage, opType: CementJobStage.OperationType?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Name field
            HStack {
                Text("Name:")
                    .frame(width: 80, alignment: .trailing)
                TextField("Name", text: Binding(
                    get: { stage.name },
                    set: { stage.name = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }

            switch opType {
            case .pressureTestLines:
                HStack {
                    Text("Pressure:")
                        .frame(width: 80, alignment: .trailing)
                    TextField("", value: Binding(
                        get: { stage.pressure_MPa ?? 0 },
                        set: { stage.pressure_MPa = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    Text("MPa")
                        .foregroundColor(.secondary)
                }

            case .tripSet:
                HStack {
                    Text("Pressure:")
                        .frame(width: 80, alignment: .trailing)
                    TextField("", value: Binding(
                        get: { stage.pressure_MPa ?? 0 },
                        set: { stage.pressure_MPa = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    Text("MPa")
                        .foregroundColor(.secondary)
                }

            case .bumpPlug:
                HStack {
                    Text("Over FCP:")
                        .frame(width: 80, alignment: .trailing)
                    TextField("", value: Binding(
                        get: { stage.overPressure_MPa ?? 0 },
                        set: { stage.overPressure_MPa = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    Text("MPa")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Final:")
                        .frame(width: 80, alignment: .trailing)
                    TextField("", value: Binding(
                        get: { stage.pressure_MPa ?? 0 },
                        set: { stage.pressure_MPa = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    Text("MPa")
                        .foregroundColor(.secondary)
                }

            case .pressureTestCasing:
                HStack {
                    Text("Pressure:")
                        .frame(width: 80, alignment: .trailing)
                    TextField("", value: Binding(
                        get: { stage.pressure_MPa ?? 0 },
                        set: { stage.pressure_MPa = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    Text("MPa")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Duration:")
                        .frame(width: 80, alignment: .trailing)
                    TextField("", value: Binding(
                        get: { stage.duration_min ?? 0 },
                        set: { stage.duration_min = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    Text("min")
                        .foregroundColor(.secondary)
                }

            case .floatCheck:
                Toggle("Floats Held", isOn: Binding(
                    get: { stage.floatsClosed },
                    set: { stage.floatsClosed = $0 }
                ))

            case .bleedBack:
                HStack {
                    Text("Volume:")
                        .frame(width: 80, alignment: .trailing)
                    TextField("", value: Binding(
                        get: { stage.operationVolume_L ?? 0 },
                        set: { stage.operationVolume_L = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    Text("L")
                        .foregroundColor(.secondary)
                }

            case .plugDrop:
                HStack {
                    Text("Volume:")
                        .frame(width: 80, alignment: .trailing)
                    TextField("", value: Binding(
                        get: { stage.operationVolume_L ?? 0 },
                        set: { stage.operationVolume_L = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    Text("L")
                        .foregroundColor(.secondary)
                }
                Toggle("Drop On The Fly", isOn: Binding(
                    get: { stage.plugDropOnTheFly },
                    set: { stage.plugDropOnTheFly = $0 }
                ))

            case .rigOut, .other, .none:
                EmptyView()
            }
        }
        .font(.callout)
        .padding(.top, 4)
    }

    // MARK: - Return Summary Section

    private var returnSummarySection: some View {
        GroupBox("Returns Summary") {
            VStack(alignment: .leading, spacing: 8) {
                SummaryRow(label: "Volume Pumped:", value: String(format: "%.2f m³", viewModel.cumulativePumpedVolume_m3))
                SummaryRow(label: "Expected Return:", value: String(format: "%.2f m³", viewModel.expectedReturn_m3))
                SummaryRow(label: "Actual Return:", value: String(format: "%.2f m³", viewModel.actualTotalReturned_m3))

                Divider()

                HStack {
                    Text("Return Ratio:")
                        .fontWeight(.medium)
                    Spacer()
                    Text(String(format: "1:%.2f", viewModel.overallReturnRatio))
                        .fontWeight(.bold)
                        .foregroundColor(returnRatioColor)
                        .monospacedDigit()
                }

                if abs(viewModel.returnDifference_m3) > 0.01 {
                    HStack {
                        Text("Difference:")
                        Spacer()
                        Text(String(format: "%+.2f m³", -viewModel.returnDifference_m3))
                            .foregroundColor(viewModel.returnDifference_m3 > 0 ? .orange : .green)
                            .monospacedDigit()
                    }
                    .font(.caption)
                }
            }
            .padding(8)
        }
    }

    private var returnRatioColor: Color {
        let ratio = viewModel.overallReturnRatio
        if ratio >= 0.95 { return .green }
        if ratio >= 0.8 { return .yellow }
        return .orange
    }

    // MARK: - Job Report Section

    private var jobReportSection: some View {
        GroupBox("Job Report") {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $editableJobReport)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minHeight: 80, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)

                HStack {
                    Button {
                        editableJobReport = viewModel.generateJobReportText(jobName: job.name, casingType: job.casingType.displayName)
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)

                    Spacer()

                    Button {
                        copyToClipboard(editableJobReport)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            .padding(8)
        }
    }

    // MARK: - Current Stage Info Section

    private var currentStageInfoSection: some View {
        GroupBox {
            if let stage = viewModel.currentStage {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if stage.isOperation {
                            Image(systemName: operationIcon(stage.operationType))
                                .font(.title2)
                                .foregroundColor(.accentColor)
                        } else {
                            Circle()
                                .fill(stage.color)
                                .frame(width: 24, height: 24)
                        }

                        Text(viewModel.stageDescription(stage))
                            .font(.headline)

                        Spacer()

                        Text("Stage \(viewModel.currentStageIndex + 1)")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.secondary.opacity(0.2)))
                    }

                    if !stage.isOperation {
                        // Progress slider
                        VStack(alignment: .leading, spacing: 4) {
                            Slider(value: Binding(
                                get: { viewModel.progress },
                                set: { viewModel.setProgress($0) }
                            ), in: 0...1)

                            HStack {
                                Text("0%")
                                Spacer()
                                Text(String(format: "%.1f m³ pumped", stage.volume_m3 * viewModel.progress))
                                    .fontWeight(.medium)
                                Spacer()
                                Text("100%")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    } else {
                        // Editable operation fields
                        if let sourceStage = stage.sourceStage {
                            operationEditFields(for: sourceStage, opType: stage.operationType)
                        }

                        // Editable notes for operation (persisted to model)
                        if let sourceStage = stage.sourceStage {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Notes:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("Add notes for this step...", text: Binding(
                                    get: { sourceStage.notes },
                                    set: { sourceStage.notes = $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                            }
                            .padding(.top, 8)
                        }

                        // Mark complete button for operations
                        HStack {
                            Spacer()
                            Button(action: { viewModel.nextStage() }) {
                                Label("Mark Complete", systemImage: "checkmark.circle")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.isAtEnd)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(8)
            } else {
                Text("No stages configured")
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
    }

    // MARK: - Fluid Visualization Section

    private var fluidVisualizationSection: some View {
        let maxDepth = viewModel.shoeDepth_m // Use shoe depth as the common reference

        return GroupBox("Well Fluid Profile") {
            GeometryReader { geo in
                // Account for header row height
                let headerHeight: CGFloat = 20
                let columnHeight = geo.size.height - 50 - headerHeight

                HStack(alignment: .top, spacing: 8) {
                    // TVD scale (left side)
                    VStack(spacing: 8) {
                        Text("TVD")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        depthScaleView(height: columnHeight, maxDepth: maxDepth, showTVD: true)
                            .frame(width: 55)
                    }

                    // String column
                    VStack(spacing: 8) {
                        Text("String")
                            .font(.caption)
                            .fontWeight(.medium)
                        fluidColumnWithTops(
                            segments: viewModel.stringStack,
                            maxDepth: maxDepth,
                            height: columnHeight,
                            showTops: false
                        )
                        .frame(width: 50)
                    }

                    // Annulus column
                    VStack(spacing: 8) {
                        Text("Annulus")
                            .font(.caption)
                            .fontWeight(.medium)
                        fluidColumnWithTops(
                            segments: viewModel.annulusStack,
                            maxDepth: maxDepth,
                            height: columnHeight,
                            showTops: true
                        )
                        .frame(width: 70)
                    }

                    // MD scale (right of annulus)
                    VStack(spacing: 8) {
                        Text("MD")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        depthScaleView(height: columnHeight, maxDepth: maxDepth, showTVD: false)
                            .frame(width: 55)
                    }

                    Spacer().frame(width: 16)

                    // Fluid tops labels with callout lines
                    VStack(spacing: 8) {
                        Text("Fluid Tops")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 28)
                        fluidTopLabels(segments: viewModel.annulusStack, maxDepth: maxDepth, height: columnHeight)
                            .padding(.leading, 28)  // Space for callout lines
                    }
                    .frame(width: 170)

                    Spacer()

                    // Legend and cement returns
                    VStack(alignment: .leading, spacing: 12) {
                        fluidLegend
                        cementReturnsDisplay
                    }
                    .frame(width: 160)
                }
                .padding()
            }
            .frame(minHeight: 450)
        }
    }

    private func depthScaleView(height: CGFloat, maxDepth: Double, showTVD: Bool) -> some View {
        let interval = depthInterval(for: maxDepth)
        let depths = Array(stride(from: 0.0, through: maxDepth, by: interval))

        return Canvas { context, size in
            guard maxDepth > 0 else { return }

            for md in depths {
                let displayValue = showTVD ? viewModel.tvd(of: md) : md
                let y = CGFloat(md / maxDepth) * size.height

                // Draw tick mark
                let tickX = showTVD ? size.width - 6 : 0
                let tickRect = CGRect(x: tickX, y: y - 0.5, width: 6, height: 1)
                context.fill(Path(tickRect), with: .color(.secondary.opacity(0.5)))

                // Draw text
                let text = Text("\(Int(displayValue))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                let resolvedText = context.resolve(text)

                context.draw(resolvedText, at: CGPoint(x: showTVD ? size.width - 10 : 10, y: y), anchor: showTVD ? .trailing : .leading)
            }
        }
        .frame(height: height)
    }

    private func depthInterval(for maxDepth: Double) -> Double {
        if maxDepth <= 500 { return 100 }
        if maxDepth <= 1000 { return 200 }
        if maxDepth <= 2000 { return 500 }
        return 1000
    }

    private func fluidColumnWithTops(segments: [CementJobSimulationViewModel.FluidSegment], maxDepth: Double, height: CGFloat, showTops: Bool) -> some View {
        ZStack(alignment: .top) {
            // Background
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.1))

            // Fluid segments
            ForEach(segments) { segment in
                let top = maxDepth > 0 ? CGFloat(segment.topMD_m / maxDepth) * height : 0
                let bottom = maxDepth > 0 ? CGFloat(segment.bottomMD_m / maxDepth) * height : 0
                let segmentHeight = max(1, bottom - top)

                Rectangle()
                    .fill(segment.color)
                    .frame(height: segmentHeight)
                    .offset(y: top)
            }

            // Outline
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.primary.opacity(0.3), lineWidth: 1)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func fluidTopLabels(segments: [CementJobSimulationViewModel.FluidSegment], maxDepth: Double, height: CGFloat) -> some View {
        // Find actual fluid transitions (where fluid type changes)
        let sortedSegments = segments.sorted { $0.topMD_m < $1.topMD_m }

        // Build list of fluid transitions to display
        var transitions: [(name: String, color: Color, md: Double, tvd: Double, isTop: Bool)] = []
        var lastFluidName: String? = nil

        for (index, segment) in sortedSegments.enumerated() {
            let isLastSegment = index == sortedSegments.count - 1

            if segment.name != lastFluidName {
                transitions.append((
                    name: segment.name,
                    color: segment.color,
                    md: segment.topMD_m,
                    tvd: segment.topTVD_m,
                    isTop: true
                ))
            }

            if segment.isCement && !isLastSegment {
                let nextSegment = sortedSegments[index + 1]
                if nextSegment.name != segment.name {
                    transitions.append((
                        name: "\(segment.name) BTM",
                        color: segment.color,
                        md: segment.bottomMD_m,
                        tvd: segment.bottomTVD_m,
                        isTop: false
                    ))
                }
            }

            lastFluidName = segment.name
        }

        // Space out labels to avoid overlap (minimum 32pt apart)
        let minSpacing: CGFloat = 32
        var labelYPositions: [CGFloat] = []
        for transition in transitions {
            let naturalY = CGFloat(transition.md / maxDepth) * height
            var adjustedY = naturalY

            // Push down if overlapping with previous label
            if let lastY = labelYPositions.last {
                if adjustedY < lastY + minSpacing {
                    adjustedY = lastY + minSpacing
                }
            }
            // Don't go past bottom
            adjustedY = min(adjustedY, height - 20)
            labelYPositions.append(adjustedY)
        }

        return Canvas { context, size in
            guard maxDepth > 0 else { return }

            for (index, transition) in transitions.enumerated() {
                let actualY = CGFloat(transition.md / maxDepth) * size.height
                let labelY = labelYPositions[index]

                // Draw callout line from label to actual position
                if abs(labelY - actualY) > 2 {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: labelY + 6))
                    path.addLine(to: CGPoint(x: -8, y: labelY + 6))
                    path.addLine(to: CGPoint(x: -12, y: actualY))
                    path.addLine(to: CGPoint(x: -20, y: actualY))
                    context.stroke(path, with: .color(transition.color.opacity(0.6)), lineWidth: 1)

                    // Small circle at actual position
                    let circle = Path(ellipseIn: CGRect(x: -23, y: actualY - 3, width: 6, height: 6))
                    context.fill(circle, with: .color(transition.color))
                } else {
                    // Just a short line
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: actualY))
                    path.addLine(to: CGPoint(x: -20, y: actualY))
                    context.stroke(path, with: .color(transition.color.opacity(0.6)), lineWidth: 1)
                    let circle = Path(ellipseIn: CGRect(x: -23, y: actualY - 3, width: 6, height: 6))
                    context.fill(circle, with: .color(transition.color))
                }

                // Draw fluid name
                let nameText = Text(transition.name)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(transition.color)
                context.draw(context.resolve(nameText), at: CGPoint(x: 2, y: labelY), anchor: .topLeading)

                // Draw MD/TVD on same line
                let depthText = Text("\(Int(transition.md))m / \(Int(transition.tvd))m")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                context.draw(context.resolve(depthText), at: CGPoint(x: 2, y: labelY + 12), anchor: .topLeading)
            }
        }
        .frame(height: height)
    }

    private var fluidLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Fluids")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            ForEach(uniqueFluids, id: \.name) { fluid in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(fluid.color)
                        .frame(width: 16, height: 16)
                    Text(fluid.name)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
        }
    }

    private var cementReturnsDisplay: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cement Returns")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                Text(String(format: "%.2f m³", viewModel.cementReturns_m3))
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    // MARK: - iOS Sections
    #if os(iOS)

    private var currentStageInfoSectionIOS: some View {
        GroupBox {
            if let stage = viewModel.currentStage {
                VStack(alignment: .leading, spacing: 12) {
                    // Stage header with navigation
                    HStack {
                        // Previous button
                        Button(action: { viewModel.previousStage() }) {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.title2)
                        }
                        .disabled(viewModel.isAtStart)

                        Spacer()

                        // Stage info
                        VStack(spacing: 4) {
                            HStack(spacing: 8) {
                                if stage.isOperation {
                                    Image(systemName: operationIcon(stage.operationType))
                                        .font(.title3)
                                        .foregroundColor(.accentColor)
                                } else {
                                    Circle()
                                        .fill(stage.color)
                                        .frame(width: 20, height: 20)
                                }

                                Text(viewModel.stageDescription(stage))
                                    .font(.headline)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }

                            Text("Stage \(viewModel.currentStageIndex + 1) of \(viewModel.stages.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Next button
                        Button(action: { viewModel.nextStage() }) {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.title2)
                        }
                        .disabled(viewModel.isAtEnd)
                    }

                    Divider()

                    if !stage.isOperation {
                        // Progress slider for pump stages
                        VStack(alignment: .leading, spacing: 8) {
                            Slider(value: Binding(
                                get: { viewModel.progress },
                                set: { viewModel.setProgress($0) }
                            ), in: 0...1)

                            HStack {
                                Text("0%")
                                    .font(.caption)
                                Spacer()
                                Text(String(format: "%.1f m³ pumped", stage.volume_m3 * viewModel.progress))
                                    .font(.callout)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("100%")
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                        }
                    } else {
                        // Editable operation fields
                        if let sourceStage = stage.sourceStage {
                            operationEditFieldsIOS(for: sourceStage, opType: stage.operationType)
                        }

                        // Editable notes (persisted to model)
                        if let sourceStage = stage.sourceStage {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Notes:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("Add notes...", text: Binding(
                                    get: { sourceStage.notes },
                                    set: { sourceStage.notes = $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                            }
                        }

                        // Mark complete button - use simultaneousGesture to avoid TextField focus issues
                        Button {
                            // Dismiss keyboard first if needed
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            viewModel.nextStage()
                        } label: {
                            Label("Mark Complete", systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isAtEnd)
                        .padding(.top, 4)
                        .contentShape(Rectangle())
                    }
                }
                .padding(8)
            } else {
                Text("No stages configured")
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
    }

    private var tankVolumeSectionIOS: some View {
        GroupBox("Tank Volume") {
            VStack(alignment: .leading, spacing: 10) {
                // Initial volume
                HStack {
                    Text("Initial:")
                    Spacer()
                    TextField("m³", value: $viewModel.initialTankVolume_m3, format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                        .frame(width: 100)
                    Text("m³")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Expected
                HStack {
                    Text("Expected:")
                    Spacer()
                    Text(String(format: "%.1f m³", viewModel.expectedTankVolume_m3))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }

                // Actual
                HStack {
                    Text("Actual:")
                    Spacer()
                    TextField("m³", value: Binding(
                        get: { viewModel.currentTankVolume_m3 },
                        set: { viewModel.recordTankVolume($0) }
                    ), format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                        .frame(width: 100)
                    Text("m³")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Difference
                if abs(viewModel.tankVolumeDifference_m3) > 0.01 {
                    HStack {
                        Text("Diff:")
                        Spacer()
                        Text(String(format: "%+.1f m³", viewModel.tankVolumeDifference_m3))
                            .fontWeight(.medium)
                            .foregroundColor(viewModel.tankVolumeDifference_m3 >= 0 ? .green : .orange)
                            .monospacedDigit()
                    }
                }
            }
            .font(.callout)
            .padding(8)
        }
    }

    private var returnSummarySectionIOS: some View {
        GroupBox("Returns") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Pumped:")
                    Spacer()
                    Text(String(format: "%.1f m³", viewModel.cumulativePumpedVolume_m3))
                        .monospacedDigit()
                }

                HStack {
                    Text("Returned:")
                    Spacer()
                    Text(String(format: "%.1f m³", viewModel.actualTotalReturned_m3))
                        .monospacedDigit()
                }

                Divider()

                HStack {
                    Text("Ratio:")
                        .fontWeight(.medium)
                    Spacer()
                    Text(String(format: "1:%.2f", viewModel.overallReturnRatio))
                        .fontWeight(.bold)
                        .foregroundColor(returnRatioColor)
                        .monospacedDigit()
                }

                // Cement returns
                HStack {
                    Text("Cement:")
                        .foregroundColor(.orange)
                    Spacer()
                    Text(String(format: "%.2f m³", viewModel.cementReturns_m3))
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                        .monospacedDigit()
                }
            }
            .font(.callout)
            .padding(8)
        }
    }

    // MARK: - Job Report Section iOS

    private var jobReportSectionIOS: some View {
        GroupBox("Job Report") {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $editableJobReport)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minHeight: 80, maxHeight: 100)
                    .scrollContentBackground(.hidden)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)

                HStack {
                    Button {
                        editableJobReport = viewModel.generateJobReportText(jobName: job.name, casingType: job.casingType.displayName)
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)

                    Spacer()

                    Button {
                        UIPasteboard.general.string = editableJobReport
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            .padding(8)
        }
    }

    // MARK: - Loss Zone Section iOS

    private var lossZoneSectionIOS: some View {
        GroupBox("Loss Zone") {
            VStack(alignment: .leading, spacing: 10) {
                // Add loss zone input
                HStack {
                    Text("Depth:")
                    TextField("MD", value: $lossZoneDepthInput, format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .frame(width: 70)
                    Text("m")
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: {
                        if lossZoneDepthInput > 0 && lossZoneDepthInput < viewModel.shoeDepth_m {
                            viewModel.addLossZone(atMD: lossZoneDepthInput)
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .disabled(lossZoneDepthInput <= 0 || lossZoneDepthInput >= viewModel.shoeDepth_m)
                }

                // Active loss zones
                if viewModel.lossZones.isEmpty {
                    Text("No loss zones configured")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(viewModel.lossZones.enumerated()), id: \.offset) { index, zone in
                        HStack {
                            Image(systemName: zone.isActive ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(zone.isActive ? .green : .secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("\(Int(zone.depth_m))m MD")
                                        .fontWeight(.medium)
                                    Text("(\(Int(zone.tvd_m))m TVD)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                HStack(spacing: 8) {
                                    Text("Frac: \(String(format: "%.0f", zone.frac_kPa)) kPa")
                                        .font(.caption2)
                                        .foregroundColor(.red)

                                    Text("EMW: \(String(format: "%.0f", zone.fracEMW_kg_m3)) kg/m³")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            Button(action: {
                                viewModel.lossZones.remove(at: index)
                                viewModel.updateFluidStacks()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }

                // Show losses info if any
                if viewModel.totalLossVolume_m3 > 0.01 {
                    Divider()
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Losses:")
                        Spacer()
                        Text(String(format: "%.2f m³", viewModel.totalLossVolume_m3))
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                            .monospacedDigit()
                    }
                }

                // Debug toggle for loss zone info
                if !viewModel.lossZones.isEmpty || !viewModel.isAutoTrackingTankVolume {
                    DisclosureGroup("Debug Info", isExpanded: $showLossZoneDebug) {
                        Text(viewModel.lossZoneDebugInfo)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption)
                }
            }
            .font(.callout)
            .padding(8)
        }
    }

    // MARK: - Pump Rate Section iOS

    private var pumpRateSectionIOS: some View {
        GroupBox("Pump Rate") {
            VStack(alignment: .leading, spacing: 10) {
                // Pump rate slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Rate:")
                        Spacer()
                        Text(String(format: "%.2f m³/min", viewModel.pumpRate_m3_per_min))
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }

                    Slider(
                        value: Binding(
                            get: { viewModel.pumpRate_m3_per_min },
                            set: { viewModel.setPumpRate($0) }
                        ),
                        in: 0.05...2.0,
                        step: 0.05
                    )

                    HStack {
                        Text("0.05")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("2.0 m³/min")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Show APL and total pressure at loss zone if there's an active loss zone
                if !viewModel.lossZones.isEmpty && viewModel.totalPressureAtLossZone_kPa > 0 {
                    Divider()
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("APL")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(String(format: "%.0f", viewModel.aplAboveLossZone_kPa)) kPa")
                                .font(.caption)
                                .fontWeight(.medium)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Total @ LZ")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(String(format: "%.0f", viewModel.totalPressureAtLossZone_kPa)) kPa")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                }

                // Annular velocities
                if !viewModel.annulusSectionInfos.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Annular Velocities")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        ForEach(viewModel.annulusSectionInfos) { section in
                            HStack {
                                Text(section.name)
                                    .font(.caption2)
                                    .lineLimit(1)

                                Spacer()

                                Text(String(format: "%.1f m/min", section.velocity_m_per_min))
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(section.isOverSpeedLimit ? .red : .primary)
                                    .monospacedDigit()

                                if section.isOverSpeedLimit {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption2)
                                        .foregroundColor(.red)
                                }
                            }
                        }

                        // Max velocity limit warning
                        if let maxVel = viewModel.maxVelocityLimit_m_per_min {
                            HStack {
                                Text("Max:")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.1f m/min", maxVel))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .font(.callout)
            .padding(8)
        }
    }

    private var stageListSectionIOS: some View {
        GroupBox("Stages") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(viewModel.stages.enumerated()), id: \.element.id) { index, stage in
                        stageChipIOS(stage: stage, index: index)
                    }
                }
                .padding(8)
            }
        }
    }

    private func stageChipIOS(stage: CementJobSimulationViewModel.SimulationStage, index: Int) -> some View {
        let isCurrentStage = index == viewModel.currentStageIndex
        let isCompleted = index < viewModel.currentStageIndex

        return Button(action: { viewModel.jumpToStage(index) }) {
            VStack(spacing: 4) {
                ZStack {
                    if stage.isOperation {
                        Circle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 40, height: 40)
                        Image(systemName: operationIcon(stage.operationType))
                            .font(.caption)
                    } else {
                        Circle()
                            .fill(stage.color)
                            .frame(width: 40, height: 40)
                    }

                    if isCompleted {
                        Circle()
                            .fill(.white)
                            .frame(width: 20, height: 20)
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
                .overlay {
                    if isCurrentStage {
                        Circle()
                            .strokeBorder(Color.accentColor, lineWidth: 3)
                            .frame(width: 44, height: 44)
                    }
                }

                Text(stage.name)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 60)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var fluidVisualizationSectionIOS: some View {
        let maxDepth = viewModel.shoeDepth_m

        return GroupBox("Well Profile") {
            GeometryReader { geo in
                let columnHeight = geo.size.height - 40

                HStack(alignment: .top, spacing: 4) {
                    // TVD scale
                    VStack(spacing: 4) {
                        Text("TVD")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        depthScaleViewIOS(height: columnHeight, maxDepth: maxDepth, showTVD: true)
                            .frame(width: 40)
                    }

                    // String column
                    VStack(spacing: 4) {
                        Text("String")
                            .font(.caption2)
                        fluidColumnWithTops(
                            segments: viewModel.stringStack,
                            maxDepth: maxDepth,
                            height: columnHeight,
                            showTops: false
                        )
                        .frame(width: 40)
                    }

                    // Annulus column
                    VStack(spacing: 4) {
                        Text("Ann")
                            .font(.caption2)
                        fluidColumnWithTops(
                            segments: viewModel.annulusStack,
                            maxDepth: maxDepth,
                            height: columnHeight,
                            showTops: true
                        )
                        .frame(width: 50)
                    }

                    // MD scale
                    VStack(spacing: 4) {
                        Text("MD")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        depthScaleViewIOS(height: columnHeight, maxDepth: maxDepth, showTVD: false)
                            .frame(width: 40)
                    }

                    Spacer().frame(width: 8)

                    // Cement tops and legend
                    VStack(alignment: .leading, spacing: 8) {
                        cementTopsDisplayIOS
                        Spacer()
                        fluidLegendIOS
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(8)
            }
            .frame(minHeight: 220, maxHeight: 280)
        }
    }

    private func depthScaleViewIOS(height: CGFloat, maxDepth: Double, showTVD: Bool) -> some View {
        let interval = depthInterval(for: maxDepth)
        let depths = Array(stride(from: 0.0, through: maxDepth, by: interval))

        return Canvas { context, size in
            guard maxDepth > 0 else { return }

            for md in depths {
                let displayValue = showTVD ? viewModel.tvd(of: md) : md
                let y = CGFloat(md / maxDepth) * size.height

                // Draw tick mark
                let tickX = showTVD ? size.width - 4 : 0
                let tickRect = CGRect(x: tickX, y: y - 0.5, width: 4, height: 1)
                context.fill(Path(tickRect), with: .color(.secondary.opacity(0.5)))

                // Draw text
                let text = Text("\(Int(displayValue))")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                let resolvedText = context.resolve(text)

                context.draw(resolvedText, at: CGPoint(x: showTVD ? size.width - 6 : 6, y: y), anchor: showTVD ? .trailing : .leading)
            }
        }
        .frame(height: height)
    }

    private var cementTopsDisplayIOS: some View {
        // Find actual fluid transitions (where fluid type changes)
        let sortedSegments = viewModel.annulusStack.sorted { $0.topMD_m < $1.topMD_m }

        var transitions: [(name: String, color: Color, md: Double, tvd: Double)] = []
        var lastFluidName: String? = nil

        for (index, segment) in sortedSegments.enumerated() {
            let isLastSegment = index == sortedSegments.count - 1

            if segment.name != lastFluidName {
                transitions.append((segment.name, segment.color, segment.topMD_m, segment.topTVD_m))
            }

            if segment.isCement && !isLastSegment {
                let nextSegment = sortedSegments[index + 1]
                if nextSegment.name != segment.name {
                    transitions.append(("\(segment.name) BTM", segment.color, segment.bottomMD_m, segment.bottomTVD_m))
                }
            }

            lastFluidName = segment.name
        }

        return VStack(alignment: .leading, spacing: 4) {
            Text("Fluid Tops")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            ForEach(Array(transitions.enumerated()), id: \.offset) { _, transition in
                HStack(spacing: 4) {
                    Circle()
                        .fill(transition.color)
                        .frame(width: 6, height: 6)
                    Text(transition.name)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(transition.color)
                    Text("\(Int(transition.md))m / \(Int(transition.tvd))m")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var fluidLegendIOS: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Fluids")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            ForEach(uniqueFluids, id: \.name) { fluid in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(fluid.color)
                        .frame(width: 12, height: 12)
                    Text(fluid.name)
                        .font(.caption2)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private func operationEditFieldsIOS(for stage: CementJobStage, opType: CementJobStage.OperationType?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Name field
            HStack {
                Text("Name:")
                Spacer()
                TextField("Name", text: Binding(
                    get: { stage.name },
                    set: { stage.name = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
            }

            switch opType {
            case .pressureTestLines:
                HStack {
                    Text("Pressure:")
                    Spacer()
                    TextField("", value: Binding(
                        get: { stage.pressure_MPa ?? 0 },
                        set: { stage.pressure_MPa = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .frame(width: 80)
                    Text("MPa")
                        .foregroundColor(.secondary)
                }

            case .tripSet:
                HStack {
                    Text("Pressure:")
                    Spacer()
                    TextField("", value: Binding(
                        get: { stage.pressure_MPa ?? 0 },
                        set: { stage.pressure_MPa = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .frame(width: 80)
                    Text("MPa")
                        .foregroundColor(.secondary)
                }

            case .bumpPlug:
                HStack {
                    Text("Over FCP:")
                    Spacer()
                    TextField("", value: Binding(
                        get: { stage.overPressure_MPa ?? 0 },
                        set: { stage.overPressure_MPa = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .frame(width: 80)
                    Text("MPa")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Final:")
                    Spacer()
                    TextField("", value: Binding(
                        get: { stage.pressure_MPa ?? 0 },
                        set: { stage.pressure_MPa = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .frame(width: 80)
                    Text("MPa")
                        .foregroundColor(.secondary)
                }

            case .pressureTestCasing:
                HStack {
                    Text("Pressure:")
                    Spacer()
                    TextField("", value: Binding(
                        get: { stage.pressure_MPa ?? 0 },
                        set: { stage.pressure_MPa = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .frame(width: 80)
                    Text("MPa")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Duration:")
                    Spacer()
                    TextField("", value: Binding(
                        get: { stage.duration_min ?? 0 },
                        set: { stage.duration_min = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .frame(width: 80)
                    Text("min")
                        .foregroundColor(.secondary)
                }

            case .floatCheck:
                Toggle("Floats Held", isOn: Binding(
                    get: { stage.floatsClosed },
                    set: { stage.floatsClosed = $0 }
                ))

            case .bleedBack:
                HStack {
                    Text("Volume:")
                    Spacer()
                    TextField("", value: Binding(
                        get: { stage.operationVolume_L ?? 0 },
                        set: { stage.operationVolume_L = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .frame(width: 80)
                    Text("L")
                        .foregroundColor(.secondary)
                }

            case .plugDrop:
                HStack {
                    Text("Volume:")
                    Spacer()
                    TextField("", value: Binding(
                        get: { stage.operationVolume_L ?? 0 },
                        set: { stage.operationVolume_L = $0 }
                    ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .frame(width: 80)
                    Text("L")
                        .foregroundColor(.secondary)
                }
                Toggle("Drop On The Fly", isOn: Binding(
                    get: { stage.plugDropOnTheFly },
                    set: { stage.plugDropOnTheFly = $0 }
                ))

            case .rigOut, .other, .none:
                EmptyView()
            }
        }
        .font(.callout)
    }

    #endif

    private var uniqueFluids: [(name: String, color: Color)] {
        var seen = Set<String>()
        var result: [(name: String, color: Color)] = []

        for segment in viewModel.stringStack + viewModel.annulusStack {
            if !seen.contains(segment.name) {
                seen.insert(segment.name)
                result.append((segment.name, segment.color))
            }
        }

        return result
    }

    // MARK: - Copy Summary

    private func copySimulationSummary() {
        let summaryText = viewModel.generateSummaryText(jobName: job.name)
        copyToClipboard(summaryText)
    }

    private func copyJobReport() {
        let reportText = viewModel.generateJobReportText(jobName: job.name, casingType: job.casingType.displayName)
        copyToClipboard(reportText)
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif

        withAnimation {
            showCopiedAlert = true
        }

        // Hide the alert after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopiedAlert = false
            }
        }
    }

    // MARK: - Copy Well Profile Image

    private func copyWellProfileImage() {
        let jobReportText = viewModel.generateJobReportText(jobName: job.name, casingType: job.casingType.displayName)
        let wellName = project.well?.name ?? "Unknown Well"

        let profileView = WellProfileRenderView(
            job: job,
            wellName: wellName,
            stringStack: viewModel.stringStack,
            annulusStack: viewModel.annulusStack,
            shoeDepth_m: viewModel.shoeDepth_m,
            floatCollarDepth_m: viewModel.floatCollarDepth_m,
            cementReturns_m3: viewModel.cementReturns_m3,
            totalLosses_m3: viewModel.totalLossVolume_m3,
            tvdMapper: { viewModel.tvd(of: $0) },
            uniqueFluids: uniqueFluids,
            jobReportText: jobReportText
        )

        let size = CGSize(width: 700, height: 620)
        let success = ClipboardService.shared.copyViewToClipboard(profileView, size: size)

        if success {
            withAnimation {
                showCopiedAlert = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showCopiedAlert = false
                }
            }
        }
    }
}

// MARK: - Supporting Views

private struct SummaryRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.callout)
    }
}

// MARK: - Well Profile Render View (for clipboard export)

/// A self-contained view that renders the well profile for clipboard export
private struct WellProfileRenderView: View {
    let job: CementJob
    let wellName: String
    let stringStack: [CementJobSimulationViewModel.FluidSegment]
    let annulusStack: [CementJobSimulationViewModel.FluidSegment]
    let shoeDepth_m: Double
    let floatCollarDepth_m: Double
    let cementReturns_m3: Double
    let totalLosses_m3: Double
    let tvdMapper: (Double) -> Double
    let uniqueFluids: [(name: String, color: Color)]
    let jobReportText: String

    var body: some View {
        VStack(spacing: 12) {
            // Header with well name
            VStack(spacing: 4) {
                Text(wellName)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                Text(job.name.isEmpty ? "Cement Job" : job.name)
                    .font(.headline)
                    .foregroundColor(.black)
                Text("\(job.casingType.displayName) - \(String(format: "%.0f", job.topMD_m))m to \(String(format: "%.0f", job.bottomMD_m))m")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding(.top, 12)

            // Main content
            HStack(alignment: .top, spacing: 16) {
                // TVD scale
                VStack(alignment: .trailing, spacing: 4) {
                    Text("TVD (m)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.gray)
                    depthScaleColumn(showTVD: true, height: 380)
                        .frame(width: 50)
                }

                // String column
                VStack(spacing: 4) {
                    Text("String")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.black)
                    fluidColumn(segments: stringStack, height: 380)
                        .frame(width: 50)
                }

                // Annulus column
                VStack(spacing: 4) {
                    Text("Annulus")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.black)
                    fluidColumn(segments: annulusStack, height: 380)
                        .frame(width: 60)
                }

                // MD scale
                VStack(alignment: .leading, spacing: 4) {
                    Text("MD (m)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.gray)
                    depthScaleColumn(showTVD: false, height: 380)
                        .frame(width: 50)
                }

                // Fluid tops and legend
                VStack(alignment: .leading, spacing: 12) {
                    fluidTopsSection
                    legendSection
                    cementReturnsSection
                }
                .frame(width: 200)
            }
            .padding(.horizontal, 20)

            // Job Report Text
            VStack(alignment: .leading, spacing: 8) {
                Text("Job Summary")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.gray)

                Text(jobReportText)
                    .font(.system(size: 11))
                    .foregroundColor(.black)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.1))
        }
        .background(Color.white)
    }

    private func depthScaleColumn(showTVD: Bool, height: CGFloat) -> some View {
        let interval = depthInterval(for: shoeDepth_m)
        let depths = Array(stride(from: 0.0, through: shoeDepth_m, by: interval))

        return Canvas { context, size in
            guard shoeDepth_m > 0 else { return }

            for md in depths {
                let displayValue = showTVD ? tvdMapper(md) : md
                let y = CGFloat(md / shoeDepth_m) * size.height

                // Draw tick
                let tickX = showTVD ? size.width - 4 : 0
                let tickRect = CGRect(x: tickX, y: y - 0.5, width: 4, height: 1)
                context.fill(Path(tickRect), with: .color(.gray.opacity(0.5)))

                // Draw text
                let text = Text("\(Int(displayValue))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                let resolvedText = context.resolve(text)
                context.draw(resolvedText, at: CGPoint(x: showTVD ? size.width - 6 : 6, y: y), anchor: showTVD ? .trailing : .leading)
            }
        }
        .frame(height: height)
    }

    private func depthInterval(for maxDepth: Double) -> Double {
        if maxDepth <= 500 { return 100 }
        if maxDepth <= 1000 { return 200 }
        if maxDepth <= 2000 { return 500 }
        return 1000
    }

    private func fluidColumn(segments: [CementJobSimulationViewModel.FluidSegment], height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.1))

            ForEach(segments) { segment in
                let top = shoeDepth_m > 0 ? CGFloat(segment.topMD_m / shoeDepth_m) * height : 0
                let bottom = shoeDepth_m > 0 ? CGFloat(segment.bottomMD_m / shoeDepth_m) * height : 0
                let segmentHeight = max(1, bottom - top)

                Rectangle()
                    .fill(segment.color)
                    .frame(height: segmentHeight)
                    .offset(y: top)
            }

            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.primary.opacity(0.3), lineWidth: 1)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var fluidTopsSection: some View {
        let sortedSegments = annulusStack.sorted { $0.topMD_m < $1.topMD_m }

        var transitions: [(name: String, color: Color, md: Double, tvd: Double)] = []
        var lastFluidName: String? = nil

        for (index, segment) in sortedSegments.enumerated() {
            let isLastSegment = index == sortedSegments.count - 1

            if segment.name != lastFluidName {
                transitions.append((segment.name, segment.color, segment.topMD_m, segment.topTVD_m))
            }

            if segment.isCement && !isLastSegment {
                let nextSegment = sortedSegments[index + 1]
                if nextSegment.name != segment.name {
                    transitions.append(("\(segment.name) BTM", segment.color, segment.bottomMD_m, segment.bottomTVD_m))
                }
            }

            lastFluidName = segment.name
        }

        return VStack(alignment: .leading, spacing: 6) {
            Text("Fluid Tops")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)

            ForEach(Array(transitions.enumerated()), id: \.offset) { _, transition in
                HStack(spacing: 4) {
                    Circle()
                        .fill(transition.color)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(transition.name)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(transition.color)
                        Text("\(Int(transition.md))m MD / \(Int(transition.tvd))m TVD")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var legendSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Fluids")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)

            ForEach(uniqueFluids, id: \.name) { fluid in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(fluid.color)
                        .frame(width: 14, height: 14)
                    Text(fluid.name)
                        .font(.caption2)
                        .lineLimit(1)
                }
            }
        }
    }

    private var cementReturnsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cement Returns
            VStack(alignment: .leading, spacing: 4) {
                Text("Cement Returns")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.gray)

                Text(String(format: "%.2f m³", cementReturns_m3))
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                    .monospacedDigit()
            }

            // Losses (if any)
            if totalLosses_m3 > 0.01 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Formation Losses")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.gray)

                    Text(String(format: "%.2f m³", totalLosses_m3))
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                        .monospacedDigit()
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.1)))
    }
}

// MARK: - Preview

#if DEBUG
struct CementJobSimulationView_Previews: PreviewProvider {
    static var previews: some View {
        Text("Preview requires model context")
    }
}
#endif
