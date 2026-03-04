//
//  CementJobSimulationViewIOS.swift
//  Josh Well Control for Mac
//
//  iOS/iPadOS optimized view for Cement Job Simulation
//  Supports iPhone (tabbed) and iPad (split view) layouts
//

import SwiftUI
import SwiftData

#if os(iOS)
import UIKit

struct CementJobSimulationViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) var sizeClass
    @Environment(\.verticalSizeClass) var vSizeClass
    
    @Bindable var project: ProjectState
    @Bindable var job: CementJob
    @State private var viewModel = CementJobSimulationViewModel()
    @State private var selectedTab = 0
    @State private var showCopiedAlert = false
    @State private var editableJobReport: String = ""
    
    init(project: ProjectState, job: CementJob) {
        self.project = project
        self.job = job
    }
    
    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .phone {
                // iPhone: Tab-based navigation
                phoneLayout
            } else {
                // iPad: Adaptive layout
                if sizeClass == .regular && vSizeClass == .regular {
                    iPadLandscapeLayout
                } else {
                    iPadPortraitLayout
                }
            }
        }
        .navigationTitle("Cement Job")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("Next Stage", systemImage: "forward.fill") {
                        viewModel.nextStage()
                    }
                    .disabled(viewModel.currentStageIndex >= viewModel.stages.count - 1)
                    
                    Button("Previous Stage", systemImage: "backward.fill") {
                        viewModel.previousStage()
                    }
                    .disabled(viewModel.currentStageIndex <= 0)
                    
                    Button("Jump to Start", systemImage: "arrow.counterclockwise") {
                        viewModel.jumpToStage(0)
                    }
                    
                    Divider()
                    
                    Button("Copy Report", systemImage: "doc.on.doc") {
                        editableJobReport = viewModel.generateJobReportText(
                            jobName: job.name,
                            casingType: job.casingType.displayName
                        )
                        UIPasteboard.general.string = editableJobReport
                        showCopiedAlert = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Copied", isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Job report copied to clipboard")
        }
        .onAppear {
            viewModel.bootstrap(job: job, project: project, context: modelContext)
            editableJobReport = viewModel.generateJobReportText(
                jobName: job.name,
                casingType: job.casingType.displayName
            )
        }
        .onChange(of: viewModel.currentStageIndex) {
            editableJobReport = viewModel.generateJobReportText(
                jobName: job.name,
                casingType: job.casingType.displayName
            )
        }
    }
    
    // MARK: - iPhone Layout (Tabbed)
    
    private var phoneLayout: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Job Setup
            setupView
                .tabItem {
                    Label("Setup", systemImage: "list.bullet")
                }
                .tag(0)
            
            // Tab 2: Simulation Controls
            simulationView
                .tabItem {
                    Label("Simulation", systemImage: "play.circle.fill")
                }
                .tag(1)
            
            // Tab 3: Results
            resultsView
                .tabItem {
                    Label("Results", systemImage: "chart.bar")
                }
                .tag(2)
            
            // Tab 4: Visualization
            visualizationView
                .tabItem {
                    Label("Wellbore", systemImage: "cylinder.split.1x2")
                }
                .tag(3)
        }
    }
    
    // MARK: - iPad Portrait Layout
    
    private var iPadPortraitLayout: some View {
        VStack(spacing: 0) {
            // Segmented control
            Picker("View", selection: $selectedTab) {
                Text("Setup").tag(0)
                Text("Simulation").tag(1)
                Text("Results").tag(2)
                Text("Wellbore").tag(3)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content
            Group {
                switch selectedTab {
                case 0:
                    setupView
                case 1:
                    simulationView
                case 2:
                    resultsView
                case 3:
                    visualizationView
                default:
                    setupView
                }
            }
        }
    }
    
    // MARK: - iPad Landscape Layout
    
    private var iPadLandscapeLayout: some View {
        HStack(spacing: 0) {
            // Left: Setup & Controls
            VStack(spacing: 0) {
                setupView
                Divider()
                simulationControlsCompact
            }
            .frame(width: 350)
            
            Divider()
            
            // Center: Results
            resultsView
                .frame(maxWidth: .infinity)
            
            Divider()
            
            // Right: Visualization
            visualizationView
                .frame(width: 300)
        }
    }
    
    // MARK: - Setup View
    
    private var setupView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Job info
                jobInfoSection
                
                // Tank volume
                tankVolumeSection
                
                // Loss zone
                lossZoneSection
                
                // Pump rate
                pumpRateSection
                
                // Stages list
                stageListSection
            }
            .padding()
        }
    }
    
    private var jobInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Job Information")
                .font(.headline)
            
            LabeledContent("Job Name", value: job.name)
            LabeledContent("Casing", value: job.casingType.displayName)
            LabeledContent("Stages", value: "\(job.stages?.count ?? 0)")
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var tankVolumeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tank Volume")
                .font(.headline)
            
            LabeledContent("Initial", value: String(format: "%.2f m³", viewModel.initialTankVolume_m3))
            LabeledContent("Current", value: String(format: "%.2f m³", viewModel.currentTankVolume_m3))
            
            HStack {
                Text("Change:")
                    .foregroundStyle(.secondary)
                let change = viewModel.currentTankVolume_m3 - viewModel.initialTankVolume_m3
                Text(String(format: "%+.2f m³", change))
                    .foregroundStyle(change < 0 ? .red : .primary)
                    .font(.body.monospacedDigit())
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var lossZoneSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Loss Zone")
                .font(.headline)
            
            if viewModel.lossZones.isEmpty {
                Text("No loss zones configured")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.lossZones.indices, id: \.self) { index in
                    let zone = viewModel.lossZones[index]
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Depth: \(String(format: "%.0f", zone.depth_m)) m MD")
                        Text("Frac: \(String(format: "%.0f", zone.frac_kPa)) kPa")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            if viewModel.totalLossVolume_m3 > 0.001 {
                Divider()
                Text("Total Losses: \(String(format: "%.2f", viewModel.totalLossVolume_m3)) m³")
                    .font(.subheadline.bold())
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var pumpRateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pump Rate")
                .font(.headline)
            
            HStack {
                Text("\(String(format: "%.2f", viewModel.pumpRate_m3_per_min)) m³/min")
                    .font(.body.monospacedDigit())
                Spacer()
                Stepper("", value: Binding(
                    get: { viewModel.pumpRate_m3_per_min },
                    set: { viewModel.setPumpRate($0) }
                ), in: 0.1...2.0, step: 0.1)
                    .labelsHidden()
            }
            
            if viewModel.aplAboveLossZone_kPa > 0 {
                Divider()
                Text("APL: \(String(format: "%.0f", viewModel.aplAboveLossZone_kPa)) kPa")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var stageListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stages")
                .font(.headline)
            
            ForEach(Array(viewModel.stages.enumerated()), id: \.element.id) { index, stage in
                HStack(spacing: 12) {
                    // Status indicator
                    Circle()
                        .fill(index == viewModel.currentStageIndex ? Color.blue : (index < viewModel.currentStageIndex ? Color.green : Color.gray))
                        .frame(width: 12, height: 12)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stage.name)
                            .font(.subheadline.weight(.medium))
                        if !stage.isOperation {
                            Text("\(String(format: "%.2f", stage.volume_m3)) m³")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if index == viewModel.currentStageIndex {
                        Text("Current")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.blue.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Simulation View
    
    private var simulationView: some View {
        VStack(spacing: 20) {
            // Current stage info
            currentStageInfoView
            
            // Controls
            simulationControlsView
            
            // Progress
            if viewModel.cumulativePumpedVolume_m3 > 0 {
                progressView
            }
            
            Spacer()
        }
        .padding()
    }
    
    private var currentStageInfoView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Stage")
                .font(.headline)
            
            if viewModel.currentStageIndex < viewModel.stages.count {
                let stage = viewModel.stages[viewModel.currentStageIndex]
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(stage.name)
                        .font(.title2.bold())
                    
                    if !stage.isOperation {
                        HStack {
                            Text("Volume:")
                            Text("\(String(format: "%.2f", stage.volume_m3)) m³")
                                .font(.body.monospacedDigit())
                        }
                        
                        HStack {
                            Text("Density:")
                            Text("\(String(format: "%.0f", stage.density_kgm3)) kg/m³")
                                .font(.body.monospacedDigit())
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var simulationControlsView: some View {
        HStack(spacing: 16) {
            Button {
                viewModel.previousStage()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(viewModel.currentStageIndex <= 0)
            
            Button {
                viewModel.nextStage()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.currentStageIndex >= viewModel.stages.count - 1)
            
            Button {
                viewModel.jumpToStage(0)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.title2)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
    
    private var simulationControlsCompact: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Controls")
                    .font(.headline)
                Spacer()
            }
            
            HStack(spacing: 12) {
                Button {
                    viewModel.previousStage()
                } label: {
                    Image(systemName: "backward.fill")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.currentStageIndex <= 0)
                
                Button {
                    viewModel.nextStage()
                } label: {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.currentStageIndex >= viewModel.stages.count - 1)
                
                Button {
                    viewModel.jumpToStage(0)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(uiColor: .systemGroupedBackground))
    }
    
    private var progressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Progress")
                .font(.headline)
            
            ProgressView(value: viewModel.cumulativePumpedVolume_m3, 
                        total: viewModel.totalFluidVolume_m3)
                .tint(.blue)
            
            HStack {
                Text("Pumped:")
                Text("\(String(format: "%.2f", viewModel.cumulativePumpedVolume_m3)) m³")
                    .font(.body.monospacedDigit())
                Spacer()
                Text("Total:")
                Text("\(String(format: "%.2f", viewModel.totalFluidVolume_m3)) m³")
                    .font(.body.monospacedDigit())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Results View
    
    private var resultsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Volume summary
                volumeSummarySection
                
                // Returns summary
                returnsSummarySection
                
                // Job report
                reportSection
            }
            .padding()
        }
    }
    
    private var volumeSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Volume Summary")
                .font(.headline)
            
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Total Pumped:")
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.2f", viewModel.cumulativePumpedVolume_m3)) m³")
                        .font(.body.monospacedDigit())
                }
                
                GridRow {
                    Text("Cement Pumped:")
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.2f", viewModel.totalCementPumped_m3)) m³")
                        .font(.body.monospacedDigit())
                }
                
                if viewModel.totalLossVolume_m3 > 0.001 {
                    GridRow {
                        Text("Lost to Formation:")
                            .foregroundStyle(.red)
                        Text("\(String(format: "%.2f", viewModel.totalLossVolume_m3)) m³")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var returnsSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Returns")
                .font(.headline)
            
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Expected:")
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.2f", viewModel.expectedReturn_m3)) m³")
                        .font(.body.monospacedDigit())
                }
                
                GridRow {
                    Text("Actual:")
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.2f", viewModel.actualTotalReturned_m3)) m³")
                        .font(.body.monospacedDigit())
                }
                
                GridRow {
                    Text("Difference:")
                        .foregroundStyle(.secondary)
                    let diff = viewModel.returnDifference_m3
                    Text(String(format: "%+.2f m³", diff))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(abs(diff) > 0.1 ? .red : .primary)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var reportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Job Report")
                .font(.headline)
            
            Text(editableJobReport)
                .font(.caption.monospaced())
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                .cornerRadius(8)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Visualization View
    
    private var visualizationView: some View {
        VStack {
            if !viewModel.annulusStack.isEmpty || !viewModel.stringStack.isEmpty {
                CementJobWellboreVisualizationIOS(
                    annulusStack: viewModel.annulusStack,
                    stringStack: viewModel.stringStack,
                    project: project
                )
            } else {
                emptyVisualizationView
            }
        }
    }
    
    private var emptyVisualizationView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cylinder.split.1x2")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Visualization Yet")
                .font(.headline)
            Text("Run the simulation to see cement placement.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Cement Job Wellbore Visualization (iOS)

struct CementJobWellboreVisualizationIOS: View {
    let annulusStack: [CementJobSimulationViewModel.FluidSegment]
    let stringStack: [CementJobSimulationViewModel.FluidSegment]
    let project: ProjectState
    
    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 20) {
                // Annulus
                VStack(alignment: .leading, spacing: 8) {
                    Text("Annulus")
                        .font(.caption.bold())
                    
                    wellboreColumn(segments: annulusStack)
                        .frame(width: 80)
                }
                
                // String
                VStack(alignment: .leading, spacing: 8) {
                    Text("String")
                        .font(.caption.bold())
                    
                    wellboreColumn(segments: stringStack)
                        .frame(width: 80)
                }
            }
            .padding()
        }
    }
    
    private func wellboreColumn(segments: [CementJobSimulationViewModel.FluidSegment]) -> some View {
        VStack(spacing: 0) {
            ForEach(segments) { segment in
                Rectangle()
                    .fill(segment.color)
                    .frame(height: layerHeight(for: segment))
                    .overlay {
                        if layerHeight(for: segment) > 30 {
                            Text(segment.name)
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                    }
            }
        }
        .frame(maxHeight: 500)
        .border(Color.gray.opacity(0.3))
    }
    
    private func layerHeight(for segment: CementJobSimulationViewModel.FluidSegment) -> CGFloat {
        let depth = segment.bottomMD_m - segment.topMD_m
        return CGFloat(max(20, depth / 10))  // Scale for visualization
    }
}

#endif
