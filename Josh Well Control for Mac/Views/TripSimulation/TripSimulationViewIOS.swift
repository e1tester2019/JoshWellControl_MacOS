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
    @Environment(\.horizontalSizeClass) var sizeClass
    @Environment(\.verticalSizeClass) var vSizeClass

    // You typically have a selected project bound in higher views. If not, you can inject a specific instance here.
    @Bindable var project: ProjectState

    @State private var viewmodel: ViewModel
    @State private var showingExportErrorAlert = false
    @State private var exportErrorMessage = ""
    @State private var selectedTab = 0
    @State private var showHandoffConfirmation = false
    @State private var showConfigPanel = true

    init(project: ProjectState) {
        self.project = project
        _viewmodel = State(initialValue: TripSimViewModelCacheIOS.get(for: project.id))
    }

    // MARK: - Body
    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .phone {
                // iPhone: Tab-based navigation
                phoneLayout
            } else {
                // iPad: Adaptive layout based on orientation
                if sizeClass == .regular && vSizeClass == .regular {
                    iPadLandscapeLayout
                } else {
                    iPadPortraitLayout
                }
            }
        }
        .loadingOverlay(
            isShowing: viewmodel.isRunning,
            message: viewmodel.progressMessage,
            progress: viewmodel.progressValue > 0 ? viewmodel.progressValue : nil
        )
        .navigationTitle("Trip Simulation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("Run Simulation", systemImage: "play.fill") {
                        viewmodel.runSimulation(project: project)
                    }
                    .disabled(viewmodel.isRunning)
                    
                    Divider()
                    
                    Button("Save Inputs", systemImage: "square.and.arrow.down") {
                        viewmodel.saveInputs(project: project, context: modelContext)
                    }
                    
                    Divider()
                    
                    Button("Export PDF Report", systemImage: "doc.richtext") {
                        exportPDFReport()
                    }
                    .disabled(viewmodel.steps.isEmpty)
                    
                    Button("Export HTML Report", systemImage: "doc.badge.gearshape") {
                        exportHTMLReport()
                    }
                    .disabled(viewmodel.steps.isEmpty)
                    
                    Button("Export Project JSON", systemImage: "curlybraces") {
                        exportProjectJSON()
                    }

                    Divider()

                    Button("Hand Off to Trip In", systemImage: "arrow.right.circle") {
                        handoffToTripIn()
                    }
                    .disabled(viewmodel.steps.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
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
        .alert("Handoff Ready", isPresented: $showHandoffConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Wellbore state saved. Navigate to Trip In Simulation to continue.")
        }
    }
    
    // MARK: - iPhone Layout (Tabbed)
    
    private var phoneLayout: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Configuration
            configurationView
                .tabItem {
                    Label("Config", systemImage: "slider.horizontal.3")
                }
                .tag(0)
            
            // Tab 2: Steps Table
            stepsTableView
                .tabItem {
                    Label("Steps", systemImage: "tablecells")
                }
                .tag(1)
            
            // Tab 3: Wellbore Visualization
            visualizationView
                .tabItem {
                    Label("Wellbore", systemImage: "cylinder.split.1x2")
                }
                .tag(2)
            
            // Tab 4: Details (only if enabled and step selected)
            if viewmodel.showDetails && viewmodel.selectedIndex != nil {
                detailsView
                    .tabItem {
                        Label("Details", systemImage: "info.circle")
                    }
                    .tag(3)
            }
        }
        .safeAreaPadding(.bottom, 49)
    }
    
    // MARK: - iPad Portrait Layout (Stacked with Segmented Control)
    
    private var iPadPortraitLayout: some View {
        VStack(spacing: 0) {
            // Segmented control for view switching
            Picker("View", selection: $selectedTab) {
                Text("Config").tag(0)
                Text("Steps").tag(1)
                Text("Wellbore").tag(2)
                if viewmodel.showDetails && viewmodel.selectedIndex != nil {
                    Text("Details").tag(3)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content area
            Group {
                switch selectedTab {
                case 0:
                    configurationView
                case 1:
                    stepsTableView
                case 2:
                    visualizationView
                case 3:
                    detailsView
                default:
                    configurationView
                }
            }
        }
    }
    
    // MARK: - iPad Landscape Layout (Split View)
    
    private var iPadLandscapeLayout: some View {
        GeometryReader { geo in
            let sideWidth = geo.size.width * 0.35
            HStack(spacing: 0) {
                // Left side: Config OR Wellbore snapshot (toggled)
                if showConfigPanel {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Bit / Range Section
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Bit / Range")
                                    .font(.headline)

                                VStack(spacing: 10) {
                                    cleanNumberField("Start MD", value: $viewmodel.startBitMD_m, suffix: "m", note: "(\(Int(startTVD)) TVD)")
                                    cleanNumberField("End MD", value: $viewmodel.endMD_m, suffix: "m", note: "(\(Int(endTVD)) TVD)")
                                    cleanNumberField("Control MD", value: controlMDBinding, suffix: "m", note: "(\(Int(controlTVD)) TVD)")
                                    cleanNumberField("Step", value: $viewmodel.step_m, suffix: "m")
                                }
                            }
                            .padding()
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .cornerRadius(12)

                            // Fluids Section
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Fluids")
                                    .font(.headline)

                                VStack(spacing: 10) {
                                    cleanMudPicker(
                                        label: "Base mud",
                                        selection: Binding(
                                            get: { project.activeMud?.id },
                                            set: { _ in }
                                        ),
                                        onSelect: { newID in
                                            if let id = newID, let m = (project.muds ?? []).first(where: { $0.id == id }) {
                                                (project.muds ?? []).forEach { $0.isActive = false }
                                                m.isActive = true
                                                viewmodel.baseMudDensity_kgpm3 = m.density_kgm3
                                            }
                                        }
                                    )

                                    cleanMudPicker(
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

                                    cleanNumberField("Target ESD@TD", value: $viewmodel.targetESDAtTD_kgpm3, suffix: "kg/m³")
                                }
                            }
                            .padding()
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .cornerRadius(12)

                            // Choke / Float Section
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Choke / Float")
                                    .font(.headline)

                                VStack(spacing: 10) {
                                    cleanNumberField("Crack Float", value: $viewmodel.crackFloat_kPa, suffix: "kPa")
                                    cleanNumberField("Initial SABP", value: $viewmodel.initialSABP_kPa, suffix: "kPa")
                                    Toggle("Hold SABP open (0 kPa)", isOn: $viewmodel.holdSABPOpen)
                                        .font(.subheadline)
                                }
                            }
                            .padding()
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .cornerRadius(12)

                            // Options
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Options")
                                    .font(.headline)

                                VStack(spacing: 10) {
                                    cleanNumberField("Trip Speed", value: tripSpeedBinding_mpm, suffix: "m/min", note: tripSpeedDirectionText)

                                    HStack {
                                        Text("Eccentricity")
                                            .font(.subheadline)
                                            .frame(width: 100, alignment: .leading)

                                        TextField("", value: $viewmodel.eccentricityFactor, format: .number.precision(.fractionLength(2)))
                                            .textFieldStyle(.roundedBorder)
                                            .keyboardType(.decimalPad)
                                            .frame(maxWidth: .infinity)
                                            .multilineTextAlignment(.trailing)

                                        Stepper("", value: $viewmodel.eccentricityFactor, in: 1.0...2.0, step: 0.05)
                                            .labelsHidden()
                                    }

                                    Toggle("Composition colors", isOn: $viewmodel.colorByComposition)
                                        .font(.subheadline)
                                    Toggle("Show details", isOn: $viewmodel.showDetails)
                                        .font(.subheadline)
                                }
                            }
                            .padding()
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .cornerRadius(12)

                            // Slug Calibration
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Slug Calibration")
                                    .font(.headline)

                                VStack(spacing: 10) {
                                    if viewmodel.calculatedInitialPitGain_m3 > 0 {
                                        HStack {
                                            Text("Calculated:")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)

                                            Spacer()

                                            Text(String(format: "%.3f m³", viewmodel.calculatedInitialPitGain_m3))
                                                .font(.subheadline)
                                                .monospacedDigit()

                                            Button {
                                                viewmodel.observedInitialPitGain_m3 = viewmodel.calculatedInitialPitGain_m3
                                            } label: {
                                                Image(systemName: "arrow.right.circle.fill")
                                            }
                                        }

                                        Divider()
                                    }

                                    Toggle("Use observed", isOn: $viewmodel.useObservedPitGain)
                                        .font(.subheadline)

                                    HStack {
                                        Text("Observed:")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)

                                        TextField("", value: $viewmodel.observedInitialPitGain_m3, format: .number.precision(.fractionLength(3)))
                                            .textFieldStyle(.roundedBorder)
                                            .keyboardType(.decimalPad)
                                            .disabled(!viewmodel.useObservedPitGain)
                                            .multilineTextAlignment(.trailing)

                                        Text("m³")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .cornerRadius(12)

                            // Run Button
                            if viewmodel.isRunning {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text(viewmodel.progressMessage)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                    }
                                    ProgressView(value: viewmodel.progressValue)
                                        .tint(.blue)
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                                .cornerRadius(12)
                            } else {
                                Button {
                                    viewmodel.runSimulation(project: project)
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
                        .padding(12)
                    }
                    .frame(width: sideWidth)
                    .scrollDismissesKeyboard(.interactively)
                } else {
                    // Wellbore snapshot / Details
                    VStack(spacing: 0) {
                        if viewmodel.showDetails && viewmodel.selectedIndex != nil {
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

                        Text("Trip Steps")
                            .font(.headline)

                        Spacer()

                        if !viewmodel.steps.isEmpty {
                            Text("\(viewmodel.steps.count) steps")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .systemGroupedBackground))

                    Divider()

                    if viewmodel.steps.isEmpty {
                        emptyStepsView
                    } else {
                        stepsScrollList
                    }
                }
            }
        }
    }
    
    // MARK: - View Components
    
    // MARK: - Configuration View
    
    private var configurationView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Bit / Range Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Bit / Range")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    VStack(spacing: 12) {
                        cleanNumberField("Start MD", value: $viewmodel.startBitMD_m, suffix: "m", note: "(\(Int(startTVD)) TVD)")
                        cleanNumberField("End MD", value: $viewmodel.endMD_m, suffix: "m", note: "(\(Int(endTVD)) TVD)")
                        cleanNumberField("Control MD", value: controlMDBinding, suffix: "m", note: "(\(Int(controlTVD)) TVD)")
                        cleanNumberField("Step", value: $viewmodel.step_m, suffix: "m")
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                
                // Fluids Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Fluids")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    VStack(spacing: 12) {
                        cleanMudPicker(
                            label: "Base mud",
                            selection: Binding(
                                get: { project.activeMud?.id },
                                set: { _ in }
                            ),
                            onSelect: { newID in
                                if let id = newID, let m = (project.muds ?? []).first(where: { $0.id == id }) {
                                    (project.muds ?? []).forEach { $0.isActive = false }
                                    m.isActive = true
                                    viewmodel.baseMudDensity_kgpm3 = m.density_kgm3
                                }
                            }
                        )
                        
                        cleanMudPicker(
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
                        
                        cleanNumberField("Target ESD@TD", value: $viewmodel.targetESDAtTD_kgpm3, suffix: "kg/m³")
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                
                // Choke / Float Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choke / Float")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    VStack(spacing: 12) {
                        cleanNumberField("Crack Float", value: $viewmodel.crackFloat_kPa, suffix: "kPa")
                        cleanNumberField("Initial SABP", value: $viewmodel.initialSABP_kPa, suffix: "kPa")
                        
                        Toggle("Hold SABP open (0 kPa)", isOn: $viewmodel.holdSABPOpen)
                            .padding(.vertical, 4)
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                
                // Trip Speed & Options Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Trip Speed & Options")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    VStack(spacing: 12) {
                        cleanNumberField("Trip Speed", value: tripSpeedBinding_mpm, suffix: "m/min", note: tripSpeedDirectionText)
                        
                        HStack {
                            Text("Eccentricity")
                                .font(.subheadline)
                                .frame(width: 120, alignment: .leading)
                            
                            TextField("", value: $viewmodel.eccentricityFactor, format: .number.precision(.fractionLength(2)))
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.decimalPad)
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.trailing)
                            
                            Stepper("", value: $viewmodel.eccentricityFactor, in: 1.0...2.0, step: 0.05)
                                .labelsHidden()
                        }
                        
                        Divider()
                        
                        Toggle("Composition colors", isOn: $viewmodel.colorByComposition)
                        Toggle("Show details tab", isOn: $viewmodel.showDetails)
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                
                // Slug Calibration Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Slug Calibration")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    VStack(spacing: 12) {
                        if viewmodel.calculatedInitialPitGain_m3 > 0 {
                            HStack {
                                Text("Calculated:")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 120, alignment: .leading)
                                
                                Text(String(format: "%.3f m³", viewmodel.calculatedInitialPitGain_m3))
                                    .monospacedDigit()
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                
                                Button {
                                    viewmodel.observedInitialPitGain_m3 = viewmodel.calculatedInitialPitGain_m3
                                } label: {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .imageScale(.large)
                                }
                            }
                            
                            Divider()
                        }
                        
                        Toggle("Use observed", isOn: $viewmodel.useObservedPitGain)
                        
                        HStack {
                            Text("Observed:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(width: 120, alignment: .leading)
                            
                            TextField("", value: $viewmodel.observedInitialPitGain_m3, format: .number.precision(.fractionLength(3)))
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.decimalPad)
                                .disabled(!viewmodel.useObservedPitGain)
                                .multilineTextAlignment(.trailing)
                            
                            Text("m³")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .leading)
                        }
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                
                // Action button
                VStack(spacing: 12) {
                    if viewmodel.isRunning {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(viewmodel.progressMessage)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                            }
                            ProgressView(value: viewmodel.progressValue)
                                .tint(.blue)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    } else {
                        Button {
                            viewmodel.runSimulation(project: project)
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
            }
            .padding(.vertical)
        }
        .scrollDismissesKeyboard(.interactively)
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
                ForEach((project.muds ?? []).sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }), id: \.id) { m in
                    Text("\(m.name) (\(format0(m.density_kgm3)) kg/m³)").tag(m.id as UUID?)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Steps Table View
    
    private var stepsTableView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Trip Steps")
                    .font(.headline)
                Spacer()
                if !viewmodel.steps.isEmpty {
                    Text("\(viewmodel.steps.count) steps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(uiColor: .systemGroupedBackground))
            
            Divider()
            
            if viewmodel.steps.isEmpty {
                emptyStepsView
            } else {
                stepsScrollList
            }
        }
    }
    
    private var emptyStepsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tablecells")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            Text("No Steps Yet")
                .font(.title2.bold())
            
            Text("Configure the inputs and run the simulation to see trip steps.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                // Switch to config tab
                selectedTab = 0
            } label: {
                Label("Go to Configuration", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Visualization View
    
    private var visualizationView: some View {
        VStack(spacing: 0) {
            // Header with slider
            if !viewmodel.steps.isEmpty {
                VStack(spacing: 12) {
                    HStack {
                        Text("Wellbore Snapshot")
                            .font(.headline)
                        Spacer()
                        Text("Step \(viewmodel.selectedIndex ?? 0) of \(viewmodel.steps.count - 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("Bit Depth:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.2f m", viewmodel.steps[min(max(viewmodel.selectedIndex ?? 0, 0), max(viewmodel.steps.count - 1, 0))].bitMD_m))
                                .monospacedDigit()
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.medium)
                        }
                        
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
                    }
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                
                Divider()
            }
            
            // Visualization
            if viewmodel.steps.isEmpty {
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
    
    // MARK: - Details View
    
    private var detailsView: some View {
        ScrollView {
            if let idx = viewmodel.selectedIndex, viewmodel.steps.indices.contains(idx) {
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
    
    // MARK: - Portrait / Landscape Layouts (Removed)
    
    
    // MARK: - Handoff

    private func handoffToTripIn() {
        // Always use the last step — the final wellbore state after trip out
        guard let lastStep = viewmodel.steps.last else { return }
        let state = WellboreStateSnapshot(
            bitMD_m: lastStep.bitMD_m,
            bitTVD_m: lastStep.bitTVD_m,
            layersPocket: lastStep.layersPocket.map { TripLayerSnapshot(from: $0) },
            layersAnnulus: lastStep.layersAnnulus.map { TripLayerSnapshot(from: $0) },
            layersString: lastStep.layersString.map { TripLayerSnapshot(from: $0) },
            SABP_kPa: lastStep.SABP_kPa,
            ESDAtControl_kgpm3: lastStep.ESDatTD_kgpm3,
            sourceDescription: "Trip Out at \(Int(lastStep.bitMD_m))m MD",
            timestamp: .now
        )
        OperationHandoffService.shared.pendingTripInState = state
        showHandoffConfirmation = true
    }

    // MARK: - Sections (Shared Components)

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
        // Match by ID for reliable selection
        viewmodel.steps.firstIndex(where: { $0.id == row.id })
    }

    // MARK: - Formatters
    private func format0(_ v: Double) -> String { String(format: "%.0f", v) }
    private func format1(_ v: Double) -> String { String(format: "%.1f", v) }
    private func format2(_ v: Double) -> String { String(format: "%.2f", v) }
    private func format3(_ v: Double) -> String { String(format: "%.3f", v) }
    private func formatSigned3(_ v: Double) -> String { String(format: "%+.3f", v) }

    // MARK: - Steps Table
    private var stepsScrollList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewmodel.steps.enumerated()), id: \.element.id) { idx, step in
                    tripOutStepRow(step, index: idx)
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        .background(idx == (viewmodel.selectedIndex ?? -1) ? Color.accentColor.opacity(0.12) : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewmodel.selectedIndex = idx
                            viewmodel.stepSlider = Double(idx)
                        }

                    Divider()
                        .padding(.leading)
                }
            }
        }
    }

    private func tripOutStepRow(_ step: TripStep, index: Int) -> some View {
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
            }

            HStack(spacing: 0) {
                tripOutMetric("SABP", format0(step.SABP_kPa), "kPa")
                tripOutMetric("Dyn SABP", format0(step.SABP_Dynamic_kPa), "kPa")
                tripOutMetric("ESD@TD", format1(step.ESDatTD_kgpm3), "kg/m\u{00B3}")
                tripOutMetric("ESD@Ctrl", format1(step.ESDatControl_kgpm3), "kg/m\u{00B3}")
            }

            HStack(spacing: 0) {
                tripOutMetric("DP Wet", format3(step.expectedFillIfClosed_m3), "m\u{00B3}")
                tripOutMetric("Fill", format3(step.stepBackfill_m3), "m\u{00B3}")
                VStack(alignment: .leading, spacing: 1) {
                    Text("Float")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(step.floatState)
                        .font(.caption2)
                        .foregroundStyle(step.floatState.contains("OPEN") ? .orange : .green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                tripOutMetric("Backfill", format2(step.backfillRemaining_m3), "m\u{00B3}")
            }
        }
        .padding(.vertical, 2)
    }

    private func tripOutMetric(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            HStack(spacing: 1) {
                Text(value)
                    .font(.caption2)
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        return String(format: "ESD@control: %.1f kg/m³", s.ESDatControl_kgpm3)
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
                }
            } else {
                Text("No step selected.").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Subviews / helpers

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
