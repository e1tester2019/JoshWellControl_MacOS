//
//  DirectionalDashboardView.swift
//  Josh Well Control for Mac
//
//  Main dashboard for directional drilling plan vs actual comparison.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum ChartViewMode: String, CaseIterable {
    case all = "All"
    case charts2D = "2D Expanded"
    case chart3D = "3D Expanded"

    var icon: String {
        switch self {
        case .all: return "rectangle.split.2x2"
        case .charts2D: return "chart.xyaxis.line"
        case .chart3D: return "cube"
        }
    }
}

enum Engine3D: String, CaseIterable {
    case sceneKit = "SceneKit"
    case realityKit = "RealityKit"

    var icon: String {
        switch self {
        case .sceneKit: return "cube"
        case .realityKit: return "cube.transparent"
        }
    }
}

struct DirectionalDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState

    @State private var vm = DirectionalDashboardViewModel()
    @State private var chartViewMode: ChartViewMode = .all
    @State private var engine3D: Engine3D = .sceneKit

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                toolbarSection

                if vm.selectedPlan != nil {
                    chartsSection
                    scenarioSurveySection
                    bitProjectionSection
                    DirectionalVarianceTableView(
                        variances: vm.variances,
                        limits: vm.limits,
                        hoveredVariance: $vm.hoveredVariance,
                        onHover: { vm.setHoveredVariance($0) }
                    )
                } else {
                    emptyStateView
                }
            }
            .padding(16)
        }
        .onAppear {
            vm.attach(project: project, context: modelContext)
        }
        .onChange(of: project) { _, newProject in
            vm.attach(project: newProject, context: modelContext)
        }
        .onChange(of: project.surveys) { _, _ in
            vm.recalculateVariances()
        }
        .onChange(of: project.directionalLimits) { _, _ in
            vm.recalculateVariances()
        }
        .fileImporter(
            isPresented: $vm.showingImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText, .utf8PlainText, .spreadsheet],
            allowsMultipleSelection: false
        ) { result in
            vm.handleImport(result)
        }
        .sheet(isPresented: $vm.showingLimitsSheet) {
            DirectionalLimitsSheet(limits: project.directionalLimits)
        }
        .alert("Import Error",
               isPresented: Binding(get: { vm.importError != nil }, set: { if !$0 { vm.importError = nil } })) {
            Button("OK") { vm.importError = nil }
        } message: {
            Text(vm.importError ?? "Unknown error")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.turn.up.right.diamond")
                .font(.title3)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Directional Planning")
                    .font(.headline)
                Text("Compare actual wellbore trajectory against planned path")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            // Status indicator
            if let summary = vm.summary {
                statusBadge(summary)
            }
        }
    }

    private func statusBadge(_ summary: DirectionalVarianceService.VarianceSummary) -> some View {
        let status = vm.overallStatus()
        return HStack(spacing: 6) {
            Image(systemName: status.icon)
                .foregroundStyle(status.color)
            Text("\(summary.stationCount) stations")
                .font(.caption)
            if summary.alarmCount > 0 {
                Text("\(summary.alarmCount) alarms")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if summary.warningCount > 0 {
                Text("\(summary.warningCount) warnings")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(status.color.opacity(0.1)))
    }

    // MARK: - Toolbar

    private var toolbarSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Plan selector
                Picker("Plan", selection: $vm.selectedPlan) {
                    Text("Select a Plan").tag(nil as DirectionalPlan?)
                    ForEach(vm.sortedPlans) { plan in
                        Text("\(plan.name) (\(plan.revision))")
                            .tag(plan as DirectionalPlan?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 250)
                .onChange(of: vm.selectedPlan) { _, newPlan in
                    vm.selectPlan(newPlan)
                }

                Button {
                    vm.showingImporter = true
                } label: {
                    Label("Import Plan", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)

                Button {
                    vm.showingLimitsSheet = true
                } label: {
                    Label("Limits", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)

                if let plan = vm.selectedPlan {
                    Button(role: .destructive) {
                        vm.deletePlan(plan)
                    } label: {
                        Label("Delete Plan", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                // Quick stats
                if let summary = vm.summary {
                    HStack(spacing: 16) {
                        quickStat("Max 3D", String(format: "%.1f m", summary.maxDistance3D))
                        quickStat("Max DLS", String(format: "%.1f°/30m", summary.maxDLS))
                        quickStat("Max TVD Var", String(format: "%.1f m", summary.maxTVDVariance))
                    }
                    .font(.caption)
                }
            }

            // Second row: View controls and VS Azimuth
            if vm.selectedPlan != nil {
                HStack(spacing: 16) {
                    // View mode toggle
                    Picker("View", selection: $chartViewMode) {
                        ForEach(ChartViewMode.allCases, id: \.self) { mode in
                            Label(mode.rawValue, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 300)

                    Spacer()

                    // VS Azimuth display with edit capability
                    vsAzimuthControl
                }
            }
        }
    }

    private func quickStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
                .fontWeight(.medium)
        }
    }

    @ViewBuilder
    private var vsAzimuthControl: some View {
        if let plan = vm.selectedPlan {
            HStack(spacing: 6) {
                Image(systemName: "location.north.line")
                    .foregroundStyle(.blue)
                Text("VS Azimuth:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                NumericTextField(
                    placeholder: "°",
                    value: Binding(
                        get: { plan.vsAzimuth_deg ?? vm.vsdDirection },
                        set: { newValue in
                            plan.vsAzimuth_deg = newValue
                            vm.recalculateVariances()
                        }
                    ),
                    fractionDigits: 2
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                .font(.caption)
                .monospacedDigit()

                Text("°")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if plan.vsAzimuth_deg != nil {
                    Button {
                        plan.vsAzimuth_deg = nil
                        vm.recalculateVariances()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Clear VS azimuth (use project default)")
                }

                Text(plan.vsAzimuth_deg != nil ? "(plan)" : "(default)")
                    .font(.caption2)
                    .foregroundStyle(plan.vsAzimuth_deg != nil ? .green : .orange)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.1)))
        }
    }

    // MARK: - Scenario Survey Section

    private var scenarioSurveySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                // Scenario list
                if vm.scenarioSurveys.isEmpty {
                    HStack {
                        Text("No scenario surveys. Add one to project ahead.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    // Header row
                    HStack(spacing: 0) {
                        Text("#")
                            .frame(width: 30, alignment: .leading)
                        Text("MD")
                            .frame(width: 70, alignment: .trailing)
                        Text("Inc")
                            .frame(width: 60, alignment: .trailing)
                        Text("Azi")
                            .frame(width: 60, alignment: .trailing)
                        Text("TVD")
                            .frame(width: 70, alignment: .trailing)
                        Text("VS")
                            .frame(width: 70, alignment: .trailing)
                        Text("DLS")
                            .frame(width: 60, alignment: .trailing)
                        Spacer()
                        Text("Actions")
                            .frame(width: 60)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)

                    Divider()

                    ForEach(Array(vm.scenarioSurveys.enumerated()), id: \.element.id) { index, scenario in
                        scenarioRow(index: index, scenario: scenario)
                    }
                }

                Divider()

                // Add new scenario controls
                addScenarioControls
            }
        } label: {
            HStack {
                Label("Scenario Surveys", systemImage: "questionmark.circle")
                if !vm.scenarioSurveys.isEmpty {
                    Text("(\(vm.scenarioSurveys.count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !vm.scenarioSurveys.isEmpty {
                    Button(role: .destructive) {
                        vm.clearScenarioSurveys()
                    } label: {
                        Label("Clear All", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func scenarioRow(index: Int, scenario: ScenarioSurvey) -> some View {
        HStack(spacing: 0) {
            Text("\(index + 1)")
                .frame(width: 30, alignment: .leading)
                .foregroundStyle(.orange)
            Text(String(format: "%.1f", scenario.md))
                .frame(width: 70, alignment: .trailing)
            Text(String(format: "%.2f°", scenario.inc))
                .frame(width: 60, alignment: .trailing)
            Text(String(format: "%.2f°", scenario.azi))
                .frame(width: 60, alignment: .trailing)
            Text(String(format: "%.1f", scenario.tvd))
                .frame(width: 70, alignment: .trailing)
            Text(String(format: "%.1f", scenario.vs_m))
                .frame(width: 70, alignment: .trailing)
            Text(String(format: "%.2f", scenario.dls))
                .frame(width: 60, alignment: .trailing)
                .foregroundStyle(scenario.dls > vm.limits.maxDLS_deg_per30m ? .red :
                                scenario.dls > vm.limits.warningDLS_deg_per30m ? .yellow : .primary)
            Spacer()
            Button(role: .destructive) {
                vm.deleteScenarioSurvey(at: index)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .frame(width: 60)
        }
        .font(.caption)
        .monospacedDigit()
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(4)
    }

    @State private var newScenarioDistance: Double = 30.0
    @State private var newScenarioInc: Double = 0.0
    @State private var newScenarioAzi: Double = 0.0
    @State private var scenarioInitialized: Bool = false

    private var addScenarioControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Scenario Survey")
                .font(.caption)
                .fontWeight(.medium)

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("Distance:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    NumericTextField(placeholder: "m", value: $newScenarioDistance, fractionDigits: 1)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .font(.caption)
                        .monospacedDigit()
                    Text("m")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    Text("Inc:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    NumericTextField(placeholder: "°", value: $newScenarioInc, fractionDigits: 2)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .font(.caption)
                        .monospacedDigit()
                    Text("°")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    Text("Azi:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    NumericTextField(placeholder: "°", value: $newScenarioAzi, fractionDigits: 2)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .font(.caption)
                        .monospacedDigit()
                    Text("°")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    vm.addScenarioSurvey(distance: newScenarioDistance, inc: newScenarioInc, azi: newScenarioAzi)
                    // Update defaults for next scenario
                    let defaults = vm.getDefaultsForNewScenario()
                    newScenarioDistance = defaults.distance
                    newScenarioInc = defaults.inc
                    newScenarioAzi = defaults.azi
                } label: {
                    Label("Add", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .disabled(newScenarioDistance <= 0)

                Spacer()

                // Quick presets
                Menu {
                    Button("Hold Angle") {
                        let defaults = vm.getDefaultsForNewScenario()
                        newScenarioInc = defaults.inc
                        newScenarioAzi = defaults.azi
                    }
                    Button("Build +1°") {
                        let defaults = vm.getDefaultsForNewScenario()
                        newScenarioInc = defaults.inc + 1.0
                        newScenarioAzi = defaults.azi
                    }
                    Button("Drop -1°") {
                        let defaults = vm.getDefaultsForNewScenario()
                        newScenarioInc = max(0, defaults.inc - 1.0)
                        newScenarioAzi = defaults.azi
                    }
                    Button("Turn Left 5°") {
                        let defaults = vm.getDefaultsForNewScenario()
                        newScenarioInc = defaults.inc
                        newScenarioAzi = (defaults.azi - 5.0).truncatingRemainder(dividingBy: 360)
                    }
                    Button("Turn Right 5°") {
                        let defaults = vm.getDefaultsForNewScenario()
                        newScenarioInc = defaults.inc
                        newScenarioAzi = (defaults.azi + 5.0).truncatingRemainder(dividingBy: 360)
                    }
                } label: {
                    Label("Presets", systemImage: "slider.horizontal.3")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
            }

            // Preview of projected position
            previewSection
        }
        .onAppear {
            if !scenarioInitialized {
                let defaults = vm.getDefaultsForNewScenario()
                newScenarioDistance = defaults.distance
                newScenarioInc = defaults.inc
                newScenarioAzi = defaults.azi
                scenarioInitialized = true
            }
        }
        .onChange(of: vm.scenarioSurveys.count) { _, _ in
            // Update defaults when scenarios change
            let defaults = vm.getDefaultsForNewScenario()
            newScenarioDistance = defaults.distance
            newScenarioInc = defaults.inc
            newScenarioAzi = defaults.azi
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if newScenarioDistance > 0 {
            let preview: ScenarioSurvey? = {
                if let lastScenario = vm.scenarioSurveys.last {
                    return ScenarioSurvey.projectFromScenario(
                        from: lastScenario,
                        distance: newScenarioDistance,
                        inc: newScenarioInc,
                        azi: newScenarioAzi,
                        vsdDirection: vm.effectiveVsAzimuth
                    )
                } else if let lastSurvey = vm.surveys.last {
                    return ScenarioSurvey.project(
                        from: lastSurvey,
                        distance: newScenarioDistance,
                        inc: newScenarioInc,
                        azi: newScenarioAzi,
                        vsdDirection: vm.effectiveVsAzimuth
                    )
                }
                return nil
            }()

            if let preview = preview {
                HStack(spacing: 16) {
                    Text("Preview:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("MD: \(String(format: "%.1f", preview.md))m")
                    Text("TVD: \(String(format: "%.1f", preview.tvd))m")
                    Text("VS: \(String(format: "%.1f", preview.vs_m))m")
                    Text("DLS: \(String(format: "%.2f", preview.dls))°/30m")
                        .foregroundStyle(preview.dls > vm.limits.maxDLS_deg_per30m ? .red :
                                        preview.dls > vm.limits.warningDLS_deg_per30m ? .yellow : .primary)
                }
                .font(.caption2)
                .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Bit Projection Section

    private var bitProjectionSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                // Controls row
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Text("Survey to Bit:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        NumericTextField(
                            placeholder: "m",
                            value: Binding(
                                get: { vm.surveyToBitDistance },
                                set: { vm.updateBitProjectionDistance($0) }
                            ),
                            fractionDigits: 1
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .font(.caption)
                        .monospacedDigit()
                        Text("m")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Toggle(isOn: Binding(
                        get: { vm.useRatesForProjection },
                        set: { _ in vm.toggleUseRatesForProjection() }
                    )) {
                        Text("Apply current BR/TR")
                            .font(.caption)
                    }
                    #if os(macOS)
                    .toggleStyle(.checkbox)
                    #endif

                    Divider()
                        .frame(height: 20)

                    // Target TVD
                    HStack(spacing: 6) {
                        Text("Target TVD:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        NumericTextField(
                            placeholder: "m",
                            value: Binding(
                                get: { vm.targetTVD ?? vm.bitProjection?.planTVD ?? 0 },
                                set: { vm.targetTVD = $0 }
                            ),
                            fractionDigits: 1
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .font(.caption)
                        .monospacedDigit()
                        Text("m")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if vm.targetTVD != nil {
                            Button {
                                vm.targetTVD = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Use plan TVD")
                        }
                    }

                    Spacer()

                    if let proj = vm.bitProjection {
                        let status = proj.status(for: vm.limits)
                        HStack(spacing: 4) {
                            Image(systemName: status.icon)
                                .foregroundStyle(status.color)
                            Text(status.label)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 4).fill(status.color.opacity(0.15)))
                    }
                }

                // Projection data
                if let proj = vm.bitProjection {
                    Divider()

                    // Row 1: Position comparison (Actual vs Plan)
                    HStack(spacing: 0) {
                        // Labels column
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("")
                                .font(.caption2)
                            Text("Actual")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("Plan")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("Variance")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 55)

                        // MD column
                        comparisonColumn(
                            label: "MD",
                            actual: proj.bitMD,
                            plan: nil,  // No plan MD to compare
                            variance: nil,
                            unit: "m",
                            decimals: 1
                        )

                        // TVD column
                        comparisonColumn(
                            label: "TVD",
                            actual: proj.bitTVD,
                            plan: proj.planTVD,
                            variance: proj.tvdVariance,
                            unit: "m",
                            decimals: 1,
                            status: proj.status(for: vm.limits)
                        )

                        // VS column
                        comparisonColumn(
                            label: "VS",
                            actual: proj.bitVS,
                            plan: proj.planVS,
                            variance: proj.vsVariance,
                            unit: "m",
                            decimals: 1
                        )

                        Divider()
                            .padding(.horizontal, 8)

                        // Inc column
                        comparisonColumn(
                            label: "Inc",
                            actual: proj.bitInc,
                            plan: proj.planInc,
                            variance: proj.incVariance,
                            unit: "°",
                            decimals: 2
                        )

                        // Azi column
                        comparisonColumn(
                            label: "Azi",
                            actual: proj.bitAzi,
                            plan: proj.planAzi,
                            variance: proj.aziVariance,
                            unit: "°",
                            decimals: 2
                        )

                        Divider()
                            .padding(.horizontal, 8)

                        // Distance metrics
                        VStack(alignment: .leading, spacing: 4) {
                            Text("3D Dist")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f m", proj.distance3D))
                                .font(.caption)
                                .fontWeight(.bold)
                                .monospacedDigit()
                                .foregroundStyle(proj.status(for: vm.limits).color)
                            Text("Closure")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f m", proj.closureDistance))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(proj.status(for: vm.limits).color)
                        }
                        .frame(width: 70)

                        Divider()
                            .padding(.horizontal, 8)

                        // Required rates to land
                        VStack(alignment: .leading, spacing: 4) {
                            if let targetBR = proj.requiredBRToTarget, let dist = proj.distanceToTarget {
                                Text("TO TARGET TVD (\(String(format: "%.0f", proj.targetTVD ?? 0))m)")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                HStack(spacing: 12) {
                                    requiredRateValue("BR", targetBR)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Dist")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(String(format: "%.0f m", dist))
                                            .font(.caption)
                                            .monospacedDigit()
                                    }
                                }
                            } else {
                                Text("TO PLAN")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 12) {
                                    requiredRateValue("BR", proj.requiredBR)
                                    requiredRateValue("TR", proj.requiredTR)
                                }
                            }
                        }

                        Spacer()
                    }
                } else {
                    Text("No survey data available for projection")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
            }
        } label: {
            HStack {
                Label("Bit Projection", systemImage: "arrow.up.right.circle")
                Spacer()
                if let proj = vm.bitProjection {
                    if vm.scenarioSurveys.isEmpty {
                        Text("From last survey at \(String(format: "%.0f", proj.surveyMD))m")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "questionmark.circle.fill")
                                .foregroundStyle(.orange)
                            Text("From scenario #\(vm.scenarioSurveys.count) at \(String(format: "%.0f", proj.surveyMD))m")
                                .foregroundStyle(.orange)
                        }
                        .font(.caption2)
                    }
                }
            }
        }
    }

    private func projectionValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }

    private func projectionVariance(_ label: String, _ value: Double, alwaysPositive: Bool = false, status: VarianceStatus = .ok) -> some View {
        let formatted = alwaysPositive ?
            String(format: "%.1f m", value) :
            String(format: "%+.1f", value)
        let color: Color = status == .ok ? .primary : status.color

        return VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(formatted)
                .font(.caption)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }

    private func requiredRateValue(_ label: String, _ rate: Double) -> some View {
        let formatted = String(format: "%+.2f°/30m", rate)
        let absRate = abs(rate)
        let color: Color = absRate < 1.0 ? .green : (absRate < 3.0 ? .yellow : .red)

        return VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(formatted)
                .font(.caption)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }

    private func comparisonColumn(
        label: String,
        actual: Double,
        plan: Double?,
        variance: Double?,
        unit: String,
        decimals: Int,
        status: VarianceStatus = .ok
    ) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(String(format: "%.\(decimals)f", actual))
                .font(.caption)
                .monospacedDigit()
            if let plan = plan {
                Text(String(format: "%.\(decimals)f", plan))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                Text("-")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let variance = variance {
                Text(String(format: "%+.\(decimals)f", variance))
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(status == .ok ? .primary : status.color)
            } else {
                Text("-")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 70)
    }

    // MARK: - Charts Section

    private var chartsSection: some View {
        VStack(spacing: 16) {
            switch chartViewMode {
            case .all:
                // All views - compact layout
                charts2DRow(minHeight: 350, expanded: false)
                #if os(macOS)
                chart3DView(minHeight: 400)
                #endif

            case .charts2D:
                // 2D charts only - expanded, equal width, full height
                charts2DRow(minHeight: 600, expanded: true)

            case .chart3D:
                // 3D view only - expanded
                #if os(macOS)
                chart3DView(minHeight: 700)
                #endif
            }
        }
    }

    private func charts2DRow(minHeight: CGFloat, expanded: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Side View (TVD vs VS)
            GroupBox {
                SideProfileChartView(
                    variances: vm.variances,
                    plan: vm.selectedPlan,
                    limits: vm.limits,
                    vsAzimuth: vm.effectiveVsAzimuth,
                    bitProjection: vm.bitProjection,
                    hoveredMD: $vm.hoveredMD,
                    onHover: { vm.setHoveredMD($0) }
                )
            } label: {
                Label("Side View (TVD vs VS)", systemImage: "rectangle.split.1x2")
            }
            .frame(maxWidth: expanded ? .infinity : nil)

            // Top View (NS vs EW)
            GroupBox {
                TopProfileChartView(
                    variances: vm.variances,
                    plan: vm.selectedPlan,
                    limits: vm.limits,
                    bitProjection: vm.bitProjection,
                    hoveredMD: $vm.hoveredMD,
                    onHover: { vm.setHoveredMD($0) }
                )
            } label: {
                Label("Top View (NS vs EW)", systemImage: "viewfinder")
            }
            .frame(maxWidth: expanded ? .infinity : nil)
        }
        .frame(minHeight: minHeight)
    }

    #if os(macOS)
    private func chart3DView(minHeight: CGFloat) -> some View {
        GroupBox {
            Group {
                switch engine3D {
                case .sceneKit:
                    Trajectory3DView(
                        variances: vm.variances,
                        plan: vm.selectedPlan,
                        limits: vm.limits,
                        bitProjection: vm.bitProjection,
                        hoveredMD: $vm.hoveredMD,
                        onHover: { vm.setHoveredMD($0) }
                    )
                case .realityKit:
                    Trajectory3DViewRealityKit(
                        variances: vm.variances,
                        plan: vm.selectedPlan,
                        limits: vm.limits,
                        bitProjection: vm.bitProjection,
                        hoveredMD: $vm.hoveredMD,
                        onHover: { vm.setHoveredMD($0) }
                    )
                }
            }
        } label: {
            HStack {
                Label("3D Trajectory View", systemImage: engine3D.icon)

                Picker("Engine", selection: $engine3D) {
                    ForEach(Engine3D.allCases, id: \.self) { engine in
                        Label(engine.rawValue, systemImage: engine.icon)
                            .tag(engine)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Spacer()
                Text("Drag to rotate • Scroll to zoom")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: minHeight)
    }
    #endif

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Directional Plan Selected")
                .font(.headline)
            Text("Import a directional plan CSV file to compare against actual survey data.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                vm.showingImporter = true
            } label: {
                Label("Import Plan", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.05)))
    }
}
