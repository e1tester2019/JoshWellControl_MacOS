//
//  TripInSimulationViewIOS.swift
//  Josh Well Control for Mac
//
//  iOS view for trip-in simulation - running pipe into a well.
//  Adaptive layout: iPhone tabs, iPad portrait segmented, iPad landscape split view.
//

#if os(iOS)
import SwiftUI
import SwiftData
import UIKit

struct TripInSimulationViewIOS: View {
    // MARK: - Environment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) var sizeClass
    @Environment(\.verticalSizeClass) var vSizeClass

    @Bindable var project: ProjectState

    @State private var viewModel: TripInSimulationViewModel
    @State private var selectedTab = 0
    @State private var showDetails = true

    init(project: ProjectState) {
        self.project = project
        _viewModel = State(initialValue: TripInViewModelCache.get(for: project.id))
    }

    // MARK: - Body
    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .phone {
                phoneLayout
            } else {
                if sizeClass == .regular && vSizeClass == .regular {
                    iPadLandscapeLayout
                } else {
                    iPadPortraitLayout
                }
            }
        }
        .loadingOverlay(
            isShowing: viewModel.isRunning,
            message: viewModel.progressMessage,
            progress: viewModel.progressValue > 0 ? viewModel.progressValue : nil
        )
        .navigationTitle("Trip In Simulation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("Run Simulation", systemImage: "play.fill") {
                        runSimulation()
                    }
                    .disabled(viewModel.isRunning)

                    Divider()

                    Button("Save Inputs", systemImage: "square.and.arrow.down") {
                        viewModel.saveInputs(project: project, context: modelContext)
                    }

                    Button("Clear Results", systemImage: "trash") {
                        viewModel.steps = []
                    }
                    .disabled(viewModel.steps.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            if let state = OperationHandoffService.shared.pendingTripInState {
                OperationHandoffService.shared.pendingTripInState = nil
                viewModel.importFromWellboreState(state, project: project)
            } else if viewModel.steps.isEmpty && viewModel.endBitMD_m == 0 {
                if !viewModel.loadSavedInputs(project: project) {
                    viewModel.bootstrap(from: project)
                }
            }
        }
        .onChange(of: viewModel.selectedIndex) { _, newVal in
            viewModel.stepSlider = Double(newVal)
        }
    }

    // MARK: - iPhone Layout (Tabbed)

    private var phoneLayout: some View {
        TabView(selection: $selectedTab) {
            configurationView
                .tabItem {
                    Label("Setup", systemImage: "slider.horizontal.3")
                }
                .tag(0)

            stepsTableView
                .tabItem {
                    Label("Results", systemImage: "tablecells")
                }
                .tag(1)

            visualizationView
                .tabItem {
                    Label("Wellbore", systemImage: "cylinder.split.1x2")
                }
                .tag(2)

            if showDetails && viewModel.selectedIndex < viewModel.steps.count {
                detailsView
                    .tabItem {
                        Label("Details", systemImage: "info.circle")
                    }
                    .tag(3)
            }
        }
        .safeAreaPadding(.bottom, 49)
    }

    // MARK: - iPad Portrait Layout (Segmented)

    private var iPadPortraitLayout: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedTab) {
                Text("Setup").tag(0)
                Text("Results").tag(1)
                Text("Wellbore").tag(2)
                if showDetails && viewModel.selectedIndex < viewModel.steps.count {
                    Text("Details").tag(3)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Group {
                switch selectedTab {
                case 0: configurationView
                case 1: stepsTableView
                case 2: visualizationView
                case 3: detailsView
                default: configurationView
                }
            }
        }
    }

    // MARK: - iPad Landscape Layout (Split View)

    @State private var showConfigPanel = true

    private var iPadLandscapeLayout: some View {
        GeometryReader { geo in
            let sideWidth = geo.size.width * 0.35
            HStack(spacing: 0) {
                // Left side: Config OR Wellbore snapshot (toggled)
                if showConfigPanel {
                    ScrollView {
                        VStack(spacing: 16) {
                            depthsCard
                            stringConfigCard
                            floatedCasingCard
                            surgeCard
                            fluidsCard
                            importedStateCard
                            runButtonCard
                        }
                        .padding(12)
                    }
                    .frame(width: sideWidth)
                    .scrollDismissesKeyboard(.interactively)
                } else {
                    VStack(spacing: 0) {
                        if showDetails && viewModel.selectedIndex < viewModel.steps.count {
                            Picker("", selection: $selectedTab) {
                                Text("Wellbore").tag(2)
                                Text("Details").tag(3)
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color(uiColor: .systemGroupedBackground))

                            Divider()

                            if selectedTab == 3 {
                                detailsView
                            } else {
                                visualizationView
                            }
                        } else {
                            visualizationView
                        }
                    }
                    .frame(width: sideWidth)
                }

                Divider()

                // Right: Steps table (remaining width)
                VStack(spacing: 0) {
                    HStack {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showConfigPanel.toggle()
                            }
                        } label: {
                            Label(
                                showConfigPanel ? "Wellbore" : "Config",
                                systemImage: showConfigPanel ? "cylinder.split.1x2" : "slider.horizontal.3"
                            )
                            .font(.subheadline)
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Text("Trip In Steps")
                            .font(.headline)

                        Spacer()

                        if !viewModel.steps.isEmpty {
                            Text("\(viewModel.steps.count) steps")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .systemGroupedBackground))

                    Divider()

                    if viewModel.steps.isEmpty {
                        emptyStepsView
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(viewModel.steps.enumerated()), id: \.element.id) { idx, step in
                                    stepRow(step, index: idx)
                                        .padding(.horizontal)
                                        .padding(.vertical, 4)
                                        .background(idx == viewModel.selectedIndex ? Color.accentColor.opacity(0.12) : Color.clear)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            viewModel.selectedIndex = idx
                                            viewModel.stepSlider = Double(idx)
                                        }
                                    Divider().padding(.leading)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Configuration View

    private var configurationView: some View {
        ScrollView {
            VStack(spacing: 20) {
                cardSection("Depths") {
                    cleanNumberField("Start MD", value: $viewModel.startBitMD_m, suffix: "m", note: "(\(Int(startTVD)) TVD)")
                    cleanNumberField("End MD", value: $viewModel.endBitMD_m, suffix: "m", note: "(\(Int(endTVD)) TVD)")
                    cleanNumberField("Control MD", value: $viewModel.controlMD_m, suffix: "m", note: "(\(Int(controlTVD)) TVD)")
                    cleanNumberField("Step", value: $viewModel.step_m, suffix: "m")
                }

                cardSection("String Configuration") {
                    HStack {
                        Text("Name")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .leading)
                        TextField("String Name", text: $viewModel.stringName)
                            .textFieldStyle(.roundedBorder)
                    }
                    cleanNumberField("Pipe OD", value: $viewModel.pipeOD_m, suffix: "m")
                    cleanNumberField("Pipe ID", value: $viewModel.pipeID_m, suffix: "m")
                }

                cardSection("Floated Casing") {
                    Toggle("Floated Casing", isOn: $viewModel.isFloatedCasing)
                        .padding(.vertical, 4)
                    if viewModel.isFloatedCasing {
                        cleanNumberField("Float Sub MD", value: $viewModel.floatSubMD_m, suffix: "m")
                        cleanNumberField("Crack Pressure", value: $viewModel.crackFloat_kPa, suffix: "kPa")
                    }
                }

                cardSection("Surge Pressure") {
                    cleanNumberField("Trip Speed", value: $viewModel.tripSpeed_m_per_min, suffix: "m/min", note: "Positive = run in hole")

                    HStack {
                        Text("Eccentricity")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .leading)

                        TextField("", value: $viewModel.eccentricityFactor, format: .number.precision(.fractionLength(2)))
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.trailing)

                        Stepper("", value: $viewModel.eccentricityFactor, in: 1.0...2.0, step: 0.05)
                            .labelsHidden()
                    }
                }

                cardSection("Fluids") {
                    cleanNumberField("Base Mud", value: $viewModel.baseMudDensity_kgpm3, suffix: "kg/m\u{00B3}")
                    cleanNumberField("Target ESD", value: $viewModel.targetESD_kgpm3, suffix: "kg/m\u{00B3}")

                    cleanMudPicker(
                        label: "Fill Mud",
                        selection: $viewModel.fillMudID,
                        onSelect: { _ in
                            viewModel.updateFillMudDensity(from: project.muds ?? [])
                        }
                    )
                }

                importedStateCardInline

                // Action button
                VStack(spacing: 12) {
                    if viewModel.isRunning {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(viewModel.progressMessage)
                                    .font(.subheadline)
                            }
                            ProgressView(value: viewModel.progressValue)
                                .tint(.blue)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    } else {
                        Button {
                            runSimulation()
                        } label: {
                            Label("Run Simulation", systemImage: "play.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding(.horizontal)
                    }
                }
                .padding(.top, 8)

                Toggle("Show details tab", isOn: $showDetails)
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Card Sections for iPad Landscape Config

    private var depthsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Depths")
                .font(.headline)
            VStack(spacing: 12) {
                cleanNumberField("Start MD", value: $viewModel.startBitMD_m, suffix: "m", note: "(\(Int(startTVD)) TVD)")
                cleanNumberField("End MD", value: $viewModel.endBitMD_m, suffix: "m", note: "(\(Int(endTVD)) TVD)")
                cleanNumberField("Control MD", value: $viewModel.controlMD_m, suffix: "m", note: "(\(Int(controlTVD)) TVD)")
                cleanNumberField("Step", value: $viewModel.step_m, suffix: "m")
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var stringConfigCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("String Configuration")
                .font(.headline)
            VStack(spacing: 12) {
                HStack {
                    Text("Name")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)
                    TextField("String Name", text: $viewModel.stringName)
                        .textFieldStyle(.roundedBorder)
                }
                cleanNumberField("Pipe OD", value: $viewModel.pipeOD_m, suffix: "m")
                cleanNumberField("Pipe ID", value: $viewModel.pipeID_m, suffix: "m")
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var floatedCasingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Floated Casing")
                .font(.headline)
            VStack(spacing: 12) {
                Toggle("Floated Casing", isOn: $viewModel.isFloatedCasing)
                    .padding(.vertical, 4)
                if viewModel.isFloatedCasing {
                    cleanNumberField("Float Sub MD", value: $viewModel.floatSubMD_m, suffix: "m")
                    cleanNumberField("Crack Pressure", value: $viewModel.crackFloat_kPa, suffix: "kPa")
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var surgeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Surge Pressure")
                .font(.headline)
            VStack(spacing: 12) {
                cleanNumberField("Trip Speed", value: $viewModel.tripSpeed_m_per_min, suffix: "m/min", note: "Positive = run in hole")

                HStack {
                    Text("Eccentricity")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)

                    TextField("", value: $viewModel.eccentricityFactor, format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.trailing)

                    Stepper("", value: $viewModel.eccentricityFactor, in: 1.0...2.0, step: 0.05)
                        .labelsHidden()
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var fluidsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fluids")
                .font(.headline)
            VStack(spacing: 12) {
                cleanNumberField("Base Mud", value: $viewModel.baseMudDensity_kgpm3, suffix: "kg/m\u{00B3}")
                cleanNumberField("Target ESD", value: $viewModel.targetESD_kgpm3, suffix: "kg/m\u{00B3}")

                cleanMudPicker(
                    label: "Fill Mud",
                    selection: $viewModel.fillMudID,
                    onSelect: { _ in
                        viewModel.updateFillMudDensity(from: project.muds ?? [])
                    }
                )
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var importedStateCard: some View {
        Group {
            if viewModel.sourceType != .none {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Imported State")
                        .font(.headline)
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundStyle(.blue)
                            Text(viewModel.sourceDisplayName)
                                .font(.subheadline)
                        }
                        if !viewModel.importedPocketLayers.isEmpty {
                            HStack {
                                Text("Pocket layers:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(viewModel.importedPocketLayers.count)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
        }
    }

    /// Inline version for configurationView (with horizontal padding)
    private var importedStateCardInline: some View {
        Group {
            if viewModel.sourceType != .none {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Imported State")
                        .font(.headline)
                        .padding(.horizontal)
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundStyle(.blue)
                            Text(viewModel.sourceDisplayName)
                                .font(.subheadline)
                        }
                        if !viewModel.importedPocketLayers.isEmpty {
                            HStack {
                                Text("Pocket layers:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(viewModel.importedPocketLayers.count)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
            }
        }
    }

    private var runButtonCard: some View {
        Group {
            if viewModel.isRunning {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(viewModel.progressMessage)
                            .font(.subheadline)
                    }
                    ProgressView(value: viewModel.progressValue)
                        .tint(.blue)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
            } else {
                Button {
                    runSimulation()
                } label: {
                    Label("Run Simulation", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    // MARK: - Steps Table View

    private var stepsTableView: some View {
        Group {
            if viewModel.steps.isEmpty {
                VStack(spacing: 0) {
                    HStack {
                        Text("Trip In Steps")
                            .font(.headline)
                        Spacer()
                    }
                    .padding()
                    .background(Color(uiColor: .systemGroupedBackground))
                    Divider()
                    emptyStepsView
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                        // Header
                        HStack {
                            Text("Trip In Steps")
                                .font(.headline)
                            Spacer()
                            Text("\(viewModel.steps.count) steps")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(uiColor: .systemGroupedBackground))

                        // Summary cards
                        summaryCardsRow
                            .padding(.horizontal)
                            .padding(.vertical, 8)

                        Divider()

                        // Step rows
                        ForEach(Array(viewModel.steps.enumerated()), id: \.element.id) { idx, step in
                            stepRow(step, index: idx)
                                .padding(.horizontal)
                                .padding(.vertical, 4)
                                .background(idx == viewModel.selectedIndex ? Color.accentColor.opacity(0.12) : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.selectedIndex = idx
                                    viewModel.stepSlider = Double(idx)
                                }

                            Divider()
                                .padding(.leading)
                        }
                    }
                }
            }
        }
    }

    private func stepRow(_ step: TripInSimulationViewModel.TripInStep, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Step \(index + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("MD: \(format0(step.bitMD_m))m")
                    .font(.subheadline.bold())
                Text("TVD: \(format0(step.bitTVD_m))m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if step.isBelowTarget {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            HStack(spacing: 0) {
                metricPill("Fill", format3(step.stepFillVolume_m3), "m\u{00B3}")
                metricPill("Cum", format3(step.cumulativeFillVolume_m3), "m\u{00B3}")
                metricPill("ESD", format1(step.ESDAtControl_kgpm3), "kg/m\u{00B3}", highlight: step.isBelowTarget)
                metricPill("Choke", format0(step.requiredChokePressure_kPa), "kPa")
            }

            if step.surgePressure_kPa > 0 {
                HStack(spacing: 0) {
                    metricPill("Surge", format0(step.surgePressure_kPa), "kPa")
                    metricPill("Dyn ESD", format1(step.dynamicESDAtControl_kgpm3), "kg/m\u{00B3}")
                }
            }

            if viewModel.isFloatedCasing {
                HStack {
                    Text("Float: \(step.floatState)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\u{0394}P: \(format0(step.differentialPressureAtBottom_kPa)) kPa")
                        .font(.caption2)
                        .foregroundStyle(step.differentialPressureAtBottom_kPa > viewModel.crackFloat_kPa ? .red : .secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func metricPill(_ label: String, _ value: String, _ unit: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            HStack(spacing: 1) {
                Text(value)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(highlight ? .orange : .primary)
                Text(unit)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Summary Cards

    private var summaryCardsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                summaryCard("Total Fill", value: format3(viewModel.totalFillVolume_m3), unit: "m\u{00B3}", icon: "drop.fill", color: .blue)
                summaryCard("Disp Returns", value: format3(viewModel.totalDisplacementReturns_m3), unit: "m\u{00B3}", icon: "arrow.up.circle", color: .green)
                summaryCard("Min ESD@Ctrl", value: format1(viewModel.minESDAtControl_kgpm3), unit: "kg/m\u{00B3}", icon: "gauge", color: .orange)
                summaryCard("Max Choke", value: format0(viewModel.maxChokePressure_kPa), unit: "kPa", icon: "gauge.with.dots.needle.33percent", color: .red)

                if viewModel.isFloatedCasing {
                    summaryCard("Max \u{0394}P", value: format0(viewModel.maxDifferentialPressure_kPa), unit: "kPa", icon: "arrow.up.arrow.down", color: .purple)
                }

                if let depthBelow = viewModel.depthBelowTarget_m {
                    summaryCard("Below Target", value: format0(depthBelow), unit: "m MD", icon: "exclamationmark.triangle.fill", color: .orange)
                }

                if viewModel.tripSpeed_m_per_min > 0 {
                    summaryCard("Max Surge", value: format0(viewModel.maxSurgePressure_kPa), unit: "kPa", icon: "waveform.path.ecg", color: .indigo)
                }
            }
        }
    }

    private func summaryCard(_ title: String, value: String, unit: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(10)
    }

    private var emptyStepsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tablecells")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No Steps Yet")
                .font(.title2.bold())

            Text("Configure the inputs and run the simulation to see trip-in steps.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                selectedTab = 0
            } label: {
                Label("Go to Configuration", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // (Steps displayed via stepsListView above)

    // MARK: - Visualization View

    private var visualizationView: some View {
        VStack(spacing: 0) {
            if !viewModel.steps.isEmpty {
                VStack(spacing: 12) {
                    HStack {
                        Text("Wellbore Snapshot")
                            .font(.headline)
                        Spacer()
                        Text("Step \(viewModel.selectedIndex + 1) of \(viewModel.steps.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        let safeIdx = min(max(viewModel.selectedIndex, 0), max(viewModel.steps.count - 1, 0))
                        HStack(spacing: 8) {
                            Text("Bit Depth:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if viewModel.steps.indices.contains(safeIdx) {
                                Text(String(format: "%.1f m", viewModel.steps[safeIdx].bitMD_m))
                                    .monospacedDigit()
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.medium)
                            }
                        }

                        Slider(
                            value: Binding(
                                get: { viewModel.stepSlider },
                                set: { newVal in
                                    viewModel.stepSlider = newVal
                                    let idx = min(max(Int(round(newVal)), 0), max(viewModel.steps.count - 1, 0))
                                    viewModel.selectedIndex = idx
                                }
                            ),
                            in: 0...Double(max(viewModel.steps.count - 1, 0)), step: 1
                        )
                    }
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))

                Divider()
            }

            if viewModel.steps.isEmpty {
                emptyVisualizationView
            } else {
                VStack(spacing: 0) {
                    visualization
                        .frame(maxHeight: .infinity)

                    if !esdAtControlText.isEmpty {
                        Text(esdAtControlText)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                    }
                }
            }
        }
    }

    private var emptyVisualizationView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cylinder.split.1x2")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No Results Yet")
                .font(.title2.bold())

            Text("Run the simulation to see wellbore visualization.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Canvas Visualization

    /// Selected fill mud for string color
    private var selectedFillMud: MudProperties? {
        guard let mudID = viewModel.fillMudID else { return nil }
        return (project.muds ?? []).first { $0.id == mudID }
    }

    private var visualization: some View {
        GroupBox("Well Snapshot") {
            GeometryReader { geo in
                Group {
                    if viewModel.steps.indices.contains(viewModel.selectedIndex) {
                        let step = viewModel.steps[viewModel.selectedIndex]
                        let pocketLayers = step.layersPocket

                        Canvas { ctx, size in
                            // Depth range: always extend to TD
                            let tdMD = viewModel.endBitMD_m
                            let globalMaxMD = max(tdMD, viewModel.controlMD_m, step.bitMD_m, pocketLayers.map { $0.bottomMD }.max() ?? 0)
                            guard globalMaxMD > 0 else { return }

                            let bitMD = step.bitMD_m
                            let margin: CGFloat = 24
                            let leftMargin: CGFloat = 35
                            let rightMargin: CGFloat = 35

                            // MD -> Y coordinate
                            func yGlobal(_ md: Double) -> CGFloat {
                                let usable = size.height - 2 * margin
                                return margin + CGFloat(md / globalMaxMD) * usable
                            }

                            // Wellbore rectangle (the hole)
                            let wellboreRect = CGRect(
                                x: leftMargin, y: margin,
                                width: size.width - leftMargin - rightMargin,
                                height: size.height - 2 * margin
                            )

                            // Wellbore background — fill with base mud color first so there are no gaps
                            let baseMudColor: Color
                            if let mud = project.activeMud {
                                baseMudColor = Color(red: mud.colorR, green: mud.colorG, blue: mud.colorB, opacity: mud.colorA)
                            } else {
                                baseMudColor = Color(white: 0.5)
                            }
                            ctx.fill(Path(wellboreRect), with: .color(baseMudColor))

                            // Draw pocket layers (fluid in the well) on top
                            let sortedPocket = pocketLayers.sorted { $0.topMD < $1.topMD }

                            // Consolidate adjacent layers with same color
                            struct ConsolidatedLayer {
                                var topMD: Double
                                var bottomMD: Double
                                var r: Double, g: Double, b: Double, a: Double
                            }

                            var consolidated: [ConsolidatedLayer] = []
                            for layer in sortedPocket {
                                let r = layer.colorR ?? 0.5
                                let g = layer.colorG ?? 0.5
                                let b = layer.colorB ?? 0.5
                                let a = layer.colorA ?? 1.0

                                if let last = consolidated.last,
                                   abs(last.bottomMD - layer.topMD) < 1.0,
                                   abs(last.r - r) < 0.01 && abs(last.g - g) < 0.01 && abs(last.b - b) < 0.01 {
                                    consolidated[consolidated.count - 1].bottomMD = layer.bottomMD
                                } else {
                                    consolidated.append(ConsolidatedLayer(
                                        topMD: layer.topMD, bottomMD: layer.bottomMD,
                                        r: r, g: g, b: b, a: a
                                    ))
                                }
                            }

                            for layer in consolidated {
                                let yTop = yGlobal(layer.topMD)
                                let yBot = yGlobal(layer.bottomMD)
                                let yMin = min(yTop, yBot)
                                let h = max(1, abs(yBot - yTop))
                                let layerRect = CGRect(x: wellboreRect.minX, y: yMin, width: wellboreRect.width, height: h)
                                let col = Color(red: layer.r, green: layer.g, blue: layer.b, opacity: layer.a)
                                ctx.fill(Path(layerRect), with: .color(col))
                            }

                            // Wellbore outline
                            ctx.stroke(Path(wellboreRect), with: .color(.gray), lineWidth: 1)

                            // Drill string — from surface down to current bit depth
                            let stringWidth = wellboreRect.width * 0.4
                            let stringX = wellboreRect.midX - stringWidth / 2

                            if bitMD > 0 {
                                let yTop = yGlobal(0)
                                let yBot = yGlobal(bitMD)
                                let stringHeight = yBot - yTop

                                // String outer wall (steel)
                                let stringOuterRect = CGRect(x: stringX, y: yTop, width: stringWidth, height: stringHeight)
                                ctx.fill(Path(stringOuterRect), with: .color(Color(white: 0.35)))

                                // Fill mud inside string
                                let inset: CGFloat = 4
                                let fillMudColor: Color
                                if let mud = selectedFillMud {
                                    fillMudColor = Color(red: mud.colorR, green: mud.colorG, blue: mud.colorB, opacity: 0.9)
                                } else {
                                    fillMudColor = Color.blue.opacity(0.7)
                                }
                                let fillRect = CGRect(x: stringX + inset, y: yTop, width: stringWidth - 2 * inset, height: stringHeight)
                                ctx.fill(Path(fillRect), with: .color(fillMudColor))

                                // String outline
                                ctx.stroke(Path(stringOuterRect), with: .color(.black), lineWidth: 1.5)

                                // Bit indicator at bottom of string
                                let bitRect = CGRect(x: stringX - 2, y: yBot - 4, width: stringWidth + 4, height: 6)
                                ctx.fill(Path(bitRect), with: .color(.red.opacity(0.8)))
                            }

                            // Control depth marker (shoe) — dashed orange line
                            let yControl = yGlobal(viewModel.controlMD_m)
                            ctx.stroke(Path { p in
                                p.move(to: CGPoint(x: wellboreRect.minX, y: yControl))
                                p.addLine(to: CGPoint(x: wellboreRect.maxX, y: yControl))
                            }, with: .color(.orange), style: StrokeStyle(lineWidth: 1.5, dash: [6, 3]))

                            // Depth ticks (TVD left, MD right)
                            let tickCount = 5
                            for i in 0...tickCount {
                                let md = Double(i) / Double(tickCount) * globalMaxMD
                                let tvd = project.tvd(of: md)
                                let yy = yGlobal(md)

                                ctx.draw(
                                    Text(String(format: "%.0f", tvd)).font(.system(size: 9)).foregroundColor(.secondary),
                                    at: CGPoint(x: wellboreRect.minX - 5, y: yy),
                                    anchor: .trailing
                                )
                                ctx.draw(
                                    Text(String(format: "%.0f", md)).font(.system(size: 9)).foregroundColor(.secondary),
                                    at: CGPoint(x: wellboreRect.maxX + 5, y: yy),
                                    anchor: .leading
                                )
                            }

                            // Axis labels
                            ctx.draw(Text("TVD").font(.system(size: 8)).foregroundColor(.secondary), at: CGPoint(x: wellboreRect.minX - 5, y: margin - 10), anchor: .trailing)
                            ctx.draw(Text("MD").font(.system(size: 8)).foregroundColor(.secondary), at: CGPoint(x: wellboreRect.maxX + 5, y: margin - 10), anchor: .leading)
                        }
                    } else {
                        ContentUnavailableView("Select a step", systemImage: "cursorarrow.click", description: Text("Choose a row from the table to see the well snapshot."))
                    }
                }
            }
            .frame(minHeight: 280)
        }
    }

    // MARK: - ESD @ Control Label

    private var esdAtControlText: String {
        guard viewModel.steps.indices.contains(viewModel.selectedIndex) else { return "" }
        let s = viewModel.steps[viewModel.selectedIndex]
        return String(format: "ESD@control: %.1f kg/m\u{00B3}  |  Choke: %.0f kPa", s.ESDAtControl_kgpm3, s.requiredChokePressure_kPa)
    }

    // MARK: - Details View

    private var detailsView: some View {
        ScrollView {
            if viewModel.steps.indices.contains(viewModel.selectedIndex) {
                detailAccordion
                    .padding()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Select a step")
                        .font(.headline)
                    Text("Choose a step from the table to view detailed information.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var detailAccordion: some View {
        GroupBox("Step Details") {
            if viewModel.steps.indices.contains(viewModel.selectedIndex) {
                let s = viewModel.steps[viewModel.selectedIndex]
                VStack(alignment: .leading, spacing: 8) {
                    DisclosureGroup("Summary") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            gridRow("Bit MD", format0(s.bitMD_m) + " m")
                            gridRow("Bit TVD", format0(s.bitTVD_m) + " m")
                            gridRow("ESD@Control", format1(s.ESDAtControl_kgpm3) + " kg/m\u{00B3}")
                            gridRow("Target ESD", format1(viewModel.targetESD_kgpm3) + " kg/m\u{00B3}")
                            gridRow("Choke Pressure", format0(s.requiredChokePressure_kPa) + " kPa")
                            if s.isBelowTarget {
                                GridRow {
                                    Text("Below Target")
                                        .foregroundStyle(.orange)
                                        .fontWeight(.semibold)
                                    Text("Yes")
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }

                    DisclosureGroup("Volumes") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            gridRow("Step Fill", format3(s.stepFillVolume_m3) + " m\u{00B3}")
                            gridRow("Cumulative Fill", format3(s.cumulativeFillVolume_m3) + " m\u{00B3}")
                            gridRow("Step Disp Returns", format3(s.stepDisplacementReturns_m3) + " m\u{00B3}")
                            gridRow("Cum Disp Returns", format3(s.cumulativeDisplacementReturns_m3) + " m\u{00B3}")
                            gridRow("Expected Fill (Closed)", format3(s.expectedFillClosed_m3) + " m\u{00B3}")
                            gridRow("Expected Fill (Open)", format3(s.expectedFillOpen_m3) + " m\u{00B3}")
                        }
                        .padding(.top, 4)
                    }

                    if viewModel.isFloatedCasing {
                        DisclosureGroup("Floated Casing") {
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                                gridRow("Float State", s.floatState)
                                gridRow("Differential Pressure", format0(s.differentialPressureAtBottom_kPa) + " kPa")
                                gridRow("Annulus P@Bit", format0(s.annulusPressureAtBit_kPa) + " kPa")
                                gridRow("String P@Bit", format0(s.stringPressureAtBit_kPa) + " kPa")
                                gridRow("Crack Pressure", format0(viewModel.crackFloat_kPa) + " kPa")
                            }
                            .padding(.top, 4)
                        }
                    }

                    if viewModel.tripSpeed_m_per_min > 0 {
                        DisclosureGroup("Surge Pressure") {
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                                gridRow("Surge Pressure", format0(s.surgePressure_kPa) + " kPa")
                                gridRow("Surge ECD", format1(s.surgeECD_kgm3) + " kg/m\u{00B3}")
                                gridRow("Dynamic ESD@Ctrl", format1(s.dynamicESDAtControl_kgpm3) + " kg/m\u{00B3}")
                            }
                            .padding(.top, 4)
                        }
                    }

                    DisclosureGroup("Annulus Layers (\(s.layersAnnulus.count))") {
                        layerTable(s.layersAnnulus)
                    }

                    DisclosureGroup("String Layers (\(s.layersString.count))") {
                        layerTable(s.layersString)
                    }

                    DisclosureGroup("Pocket Layers (\(s.layersPocket.count))") {
                        layerTable(s.layersPocket)
                    }
                }
            } else {
                Text("No step selected.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helper Views

    private func gridRow(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(.secondary)
            Text(v)
        }
    }

    private func layerTable(_ rows: [TripLayerSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack(spacing: 0) {
                Text("Top MD").font(.caption2).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
                Text("Bot MD").font(.caption2).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
                Text("\u{03C1} kg/m\u{00B3}").font(.caption2).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                Text("\u{0394}P kPa").font(.caption2).foregroundStyle(.secondary).frame(width: 65, alignment: .leading)
                Text("Vol m\u{00B3}").font(.caption2).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
            }
            .padding(.top, 4)

            Divider()

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    Text(format1(row.topMD)).font(.caption).monospacedDigit().frame(width: 60, alignment: .leading)
                    Text(format1(row.bottomMD)).font(.caption).monospacedDigit().frame(width: 60, alignment: .leading)
                    Text(format0(row.rho_kgpm3)).font(.caption).monospacedDigit().frame(width: 70, alignment: .leading)
                    Text(format0(row.deltaHydroStatic_kPa)).font(.caption).monospacedDigit().frame(width: 65, alignment: .leading)
                    Text(format3(row.volume_m3)).font(.caption).monospacedDigit().frame(width: 70, alignment: .leading)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Card Section Builder

    private func cardSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 12) {
                content()
            }
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }

    // MARK: - Clean Input Field Helper

    private func cleanNumberField(_ label: String, value: Binding<Double>, suffix: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .leading)

                TextField("", value: value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)

                Text(suffix)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
            }

            if let note = note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .padding(.leading, 120)
            }
        }
    }

    private func cleanMudPicker(label: String, selection: Binding<UUID?>, onSelect: @escaping (UUID?) -> Void) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)

            Picker("", selection: Binding(
                get: { selection.wrappedValue },
                set: { newID in
                    selection.wrappedValue = newID
                    onSelect(newID)
                }
            )) {
                Text("None").tag(nil as UUID?)
                ForEach((project.muds ?? []).sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }), id: \.id) { m in
                    HStack {
                        Circle()
                            .fill(Color(red: m.colorR, green: m.colorG, blue: m.colorB))
                            .frame(width: 10, height: 10)
                        Text("\(m.name) (\(format0(m.density_kgm3)) kg/m\u{00B3})")
                    }
                    .tag(m.id as UUID?)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Formatters

    private func format0(_ v: Double) -> String { String(format: "%.0f", v) }
    private func format1(_ v: Double) -> String { String(format: "%.1f", v) }
    private func format2(_ v: Double) -> String { String(format: "%.2f", v) }
    private func format3(_ v: Double) -> String { String(format: "%.3f", v) }

    // MARK: - TVD Computed Properties

    private var startTVD: Double { project.tvd(of: viewModel.startBitMD_m) }
    private var endTVD: Double { project.tvd(of: viewModel.endBitMD_m) }
    private var controlTVD: Double { project.tvd(of: viewModel.controlMD_m) }

    // MARK: - Actions

    private func runSimulation() {
        viewModel.runSimulation(project: project)
        selectedTab = 1
    }
}

#Preview {
    NavigationStack {
        Text("Trip In Simulation iOS Preview")
    }
}
#endif
