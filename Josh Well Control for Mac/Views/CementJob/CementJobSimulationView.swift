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

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            // Header with job info
            headerSection

            Divider()

            HStack(alignment: .top, spacing: 16) {
                // Left panel: Stage list and controls
                VStack(spacing: 12) {
                    tankVolumeSection
                    stageListSection
                    returnSummarySection
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
            VStack(spacing: 12) {
                currentStageInfoSectionIOS
                tankVolumeSectionIOS
                returnSummarySectionIOS
            }
            .frame(width: 340)

            // Right: Visualization and stage list
            VStack(spacing: 12) {
                fluidVisualizationSectionIOS
                stageListSectionIOS
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

                    // Cement tops labels
                    VStack(spacing: 8) {
                        Text("Cement Tops")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        fluidTopLabels(segments: viewModel.annulusStack, maxDepth: maxDepth, height: columnHeight)
                            .frame(width: 140)
                    }

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

                let textX = showTVD ? size.width - 10 - resolvedText.measure(in: size).width : 10
                let textY = y - resolvedText.measure(in: size).height / 2

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
        let cementSegments = segments.filter { $0.isCement }

        return Canvas { context, size in
            guard maxDepth > 0 else { return }

            for segment in cementSegments {
                let y = CGFloat(segment.topMD_m / maxDepth) * size.height

                // Draw segment name
                let nameText = Text(segment.name)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(segment.color)
                context.draw(context.resolve(nameText), at: CGPoint(x: 4, y: y), anchor: .topLeading)

                // Draw MD
                let mdText = Text("MD: \(Int(segment.topMD_m))m")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                context.draw(context.resolve(mdText), at: CGPoint(x: 4, y: y + 12), anchor: .topLeading)

                // Draw TVD
                let tvdText = Text("TVD: \(Int(segment.topTVD_m))m")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                context.draw(context.resolve(tvdText), at: CGPoint(x: 4, y: y + 24), anchor: .topLeading)
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
                    TextField("m³", value: $viewModel.initialTankVolume_m3, format: .number.precision(.fractionLength(1)))
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                        .frame(width: 80)
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
                    ), format: .number.precision(.fractionLength(1)))
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                        .frame(width: 80)
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
            .frame(minHeight: 300)
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
        let cementSegments = viewModel.annulusStack.filter { $0.isCement }

        return VStack(alignment: .leading, spacing: 6) {
            Text("Cement Tops")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            ForEach(cementSegments) { segment in
                VStack(alignment: .leading, spacing: 2) {
                    Text(segment.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(segment.color)
                    Text("MD: \(Int(segment.topMD_m))m  TVD: \(Int(segment.topTVD_m))m")
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

// MARK: - Preview

#if DEBUG
struct CementJobSimulationView_Previews: PreviewProvider {
    static var previews: some View {
        Text("Preview requires model context")
    }
}
#endif
