//
//  CementJobView.swift
//  Josh Well Control for Mac
//
//  Main view for cement job planning and management.
//

import SwiftUI
import SwiftData

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct CementJobView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState

    // Query CementJobs directly instead of using relationship (more reliable with CloudKit sync)
    @Query private var allCementJobs: [CementJob]

    @State private var viewModel = CementJobViewModel()
    @State private var showingNewJobSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingSimulation = false
    @State private var jobToDelete: CementJob?

    /// CementJobs for the current project (filtered from query)
    private var cementJobs: [CementJob] {
        allCementJobs.filter { $0.project?.id == project.id }
    }

    var body: some View {
        #if os(macOS)
        HSplitView {
            // Left panel: Job list
            jobListPanel
                .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)

            // Right panel: Job details
            if let job = viewModel.selectedJob {
                jobDetailPanel(job: job)
            } else {
                emptyStateView
            }
        }
        .padding(12)
        .navigationTitle("Cement Job")
        .sheet(isPresented: $showingNewJobSheet) {
            NewCementJobSheet(project: project, viewModel: viewModel)
        }
        .alert("Delete Cement Job?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let job = jobToDelete {
                    viewModel.deleteCementJob(job, from: project, context: modelContext)
                    jobToDelete = nil
                }
            }
        } message: {
            Text("This will permanently delete the cement job and all its stages.")
        }
        .sheet(isPresented: $showingSimulation) {
            if let job = viewModel.selectedJob {
                CementJobSimulationView(project: project, job: job)
                    .frame(minWidth: 1000, minHeight: 700)
            }
        }
        .onChange(of: viewModel.selectedJob?.updatedAt) { _, _ in
            // Explicit save for CloudKit sync when job properties change
            try? modelContext.save()
        }
        .onChange(of: project) { _, _ in
            // Clear selection when project changes
            viewModel.selectedJob = nil
            viewModel.selectedStage = nil
        }
        #else
        // iOS/iPadOS layout
        NavigationSplitView {
            jobListPanelIOS
                .navigationTitle("Cement Jobs")
        } detail: {
            if let job = viewModel.selectedJob {
                jobDetailPanelIOS(job: job)
            } else {
                emptyStateView
            }
        }
        .sheet(isPresented: $showingNewJobSheet) {
            NewCementJobSheet(project: project, viewModel: viewModel)
        }
        .alert("Delete Cement Job?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let job = jobToDelete {
                    viewModel.deleteCementJob(job, from: project, context: modelContext)
                    jobToDelete = nil
                }
            }
        } message: {
            Text("This will permanently delete the cement job and all its stages.")
        }
        .fullScreenCover(isPresented: $showingSimulation) {
            if let job = viewModel.selectedJob {
                CementJobSimulationView(project: project, job: job)
            }
        }
        .onChange(of: viewModel.selectedJob?.updatedAt) { _, _ in
            // Explicit save for CloudKit sync when job properties change
            try? modelContext.save()
        }
        .onChange(of: project) { _, _ in
            // Clear selection when project changes
            viewModel.selectedJob = nil
            viewModel.selectedStage = nil
        }
        #endif
    }

    // MARK: - Job List Panel (macOS)
    #if os(macOS)
    private var jobListPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Cement Jobs")
                    .font(.headline)
                Spacer()
                Button(action: { showingNewJobSheet = true }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }

            Divider()

            if cementJobs.isEmpty {
                Text("No cement jobs yet.\nClick + to create one.")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(
                    get: { viewModel.selectedJob?.id },
                    set: { id in
                        viewModel.selectedJob = cementJobs.first { $0.id == id }
                        if let job = viewModel.selectedJob {
                            viewModel.updateVolumes(project: project)
                            viewModel.updateAllStageCalculations(job)
                        }
                    }
                )) {
                    ForEach(cementJobs, id: \.id) { job in
                        JobListRow(job: job)
                            .tag(job.id)
                            .contextMenu {
                                Button(role: .destructive) {
                                    jobToDelete = job
                                    showingDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
    #endif

    // MARK: - Job List Panel (iOS)
    #if os(iOS)
    private var jobListPanelIOS: some View {
        List(selection: Binding(
            get: { viewModel.selectedJob?.id },
            set: { id in
                viewModel.selectedJob = cementJobs.first { $0.id == id }
                if let job = viewModel.selectedJob {
                    viewModel.updateVolumes(project: project)
                    viewModel.updateAllStageCalculations(job)
                }
            }
        )) {
            if cementJobs.isEmpty {
                Text("No cement jobs yet.\nTap + to create one.")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                ForEach(cementJobs, id: \.id) { job in
                    JobListRow(job: job)
                        .tag(job.id)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                jobToDelete = job
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingNewJobSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
    }
    #endif

    // MARK: - Job Detail Panel (macOS)
    #if os(macOS)
    private func jobDetailPanel(job: CementJob) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header with job info and actions
                jobHeader(job: job)

                Divider()

                // Two-column layout
                HStack(alignment: .top, spacing: 16) {
                    // Left column: Settings and Volumes
                    VStack(alignment: .leading, spacing: 16) {
                        jobSettingsSection(job: job)
                        volumeBreakdownSection(job: job)
                        statisticsSection(job: job)
                    }
                    .frame(minWidth: 300, maxWidth: 400)

                    Divider()

                    // Right column: Stages
                    VStack(alignment: .leading, spacing: 16) {
                        stagesSection(job: job)
                    }
                    .frame(maxWidth: .infinity)
                }

                Divider()

                // Clipboard section
                clipboardSection(job: job)
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    #endif

    // MARK: - Job Detail Panel (iOS)
    #if os(iOS)
    private func jobDetailPanelIOS(job: CementJob) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header with job info and actions
                jobHeaderIOS(job: job)

                Divider()

                // Stacked layout for iOS (no side-by-side columns)
                VStack(alignment: .leading, spacing: 16) {
                    jobSettingsSectionIOS(job: job)
                    volumeBreakdownSection(job: job)
                    statisticsSection(job: job)
                    stagesSectionIOS(job: job)
                    clipboardSectionIOS(job: job)
                }
            }
            .padding(16)
        }
        .navigationTitle(job.name.isEmpty ? "Cement Job" : job.name)
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingSimulation = true }) {
                    Label("Simulate", systemImage: "play.circle")
                }
            }
        }
    }

    private func jobHeaderIOS(job: CementJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Job Name", text: Binding(
                get: { job.name },
                set: { job.name = $0; job.updatedAt = .now }
            ))
            .font(.title2.bold())
            .textFieldStyle(.roundedBorder)

            Text(job.casingType.displayName)
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack {
                Button(action: { showingSimulation = true }) {
                    Label("Run Simulation", systemImage: "play.circle")
                }
                .buttonStyle(.borderedProminent)

                Button(action: { viewModel.copyToClipboard(job) }) {
                    Label("Copy Summary", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func jobSettingsSectionIOS(job: CementJob) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // General Settings
            GroupBox("General Settings") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Casing Type:")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { job.casingType },
                            set: { job.casingType = $0 }
                        )) {
                            ForEach(CementJob.CasingType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    HStack {
                        Text("Cement Top (MD):")
                        Spacer()
                        NumericTextField(
                            placeholder: "",
                            value: Binding(
                                get: { job.topMD_m },
                                set: { job.topMD_m = $0 }
                            ),
                            fractionDigits: 0,
                            onCommit: { viewModel.updateVolumes(project: project) }
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        Text("m")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Cement Bottom (MD):")
                        Spacer()
                        NumericTextField(
                            placeholder: "",
                            value: Binding(
                                get: { job.bottomMD_m },
                                set: { job.bottomMD_m = $0 }
                            ),
                            fractionDigits: 2,
                            onCommit: { viewModel.updateVolumes(project: project) }
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        Text("m")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Float Collar (MD):")
                        Spacer()
                        NumericTextField(
                            placeholder: "",
                            value: Binding(
                                get: { job.floatCollarDepth_m },
                                set: { job.floatCollarDepth_m = $0 }
                            ),
                            fractionDigits: 0
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        Text("m")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
            }

            // Lead Cement Settings
            GroupBox("Lead Cement") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Top (MD):")
                        Spacer()
                        NumericTextField(
                            placeholder: "Top",
                            value: Binding(
                                get: { job.leadTopMD_m },
                                set: { job.leadTopMD_m = $0 }
                            ),
                            fractionDigits: 0
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("m")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Bottom:")
                        Spacer()
                        NumericTextField(
                            placeholder: "Bottom",
                            value: Binding(
                                get: { job.leadBottomMD_m },
                                set: { job.leadBottomMD_m = $0 }
                            ),
                            fractionDigits: 0
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("m")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Excess:")
                        Spacer()
                        NumericTextField(
                            placeholder: "",
                            value: Binding(
                                get: { job.leadExcessPercent },
                                set: { job.leadExcessPercent = $0 }
                            ),
                            fractionDigits: 0
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        Text("%")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Yield:")
                        Spacer()
                        NumericTextField(
                            placeholder: "",
                            value: Binding(
                                get: { job.leadYieldFactor_m3_per_tonne },
                                set: { job.leadYieldFactor_m3_per_tonne = $0 }
                            ),
                            fractionDigits: 3,
                            onCommit: { viewModel.updateAllStageCalculations(job) }
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("m³/t")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Mix Water:")
                        Spacer()
                        NumericTextField(
                            placeholder: "",
                            value: Binding(
                                get: { job.leadMixWaterRatio_m3_per_tonne },
                                set: { job.leadMixWaterRatio_m3_per_tonne = $0 }
                            ),
                            fractionDigits: 3,
                            onCommit: { viewModel.updateAllStageCalculations(job) }
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("m³/t")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
            }

            // Tail Cement Settings
            GroupBox("Tail Cement") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Top (MD):")
                        Spacer()
                        NumericTextField(
                            placeholder: "Top",
                            value: Binding(
                                get: { job.tailTopMD_m },
                                set: { job.tailTopMD_m = $0 }
                            ),
                            fractionDigits: 0
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("m")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Bottom:")
                        Spacer()
                        NumericTextField(
                            placeholder: "Bottom",
                            value: Binding(
                                get: { job.tailBottomMD_m },
                                set: { job.tailBottomMD_m = $0 }
                            ),
                            fractionDigits: 0
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("m")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Excess:")
                        Spacer()
                        NumericTextField(
                            placeholder: "",
                            value: Binding(
                                get: { job.tailExcessPercent },
                                set: { job.tailExcessPercent = $0 }
                            ),
                            fractionDigits: 0
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        Text("%")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Yield:")
                        Spacer()
                        NumericTextField(
                            placeholder: "",
                            value: Binding(
                                get: { job.tailYieldFactor_m3_per_tonne },
                                set: { job.tailYieldFactor_m3_per_tonne = $0 }
                            ),
                            fractionDigits: 3,
                            onCommit: { viewModel.updateAllStageCalculations(job) }
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("m³/t")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Mix Water:")
                        Spacer()
                        NumericTextField(
                            placeholder: "",
                            value: Binding(
                                get: { job.tailMixWaterRatio_m3_per_tonne },
                                set: { job.tailMixWaterRatio_m3_per_tonne = $0 }
                            ),
                            fractionDigits: 3,
                            onCommit: { viewModel.updateAllStageCalculations(job) }
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("m³/t")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
            }

            // Additional Volumes
            GroupBox("Additional Volumes") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Wash Up:")
                        Spacer()
                        NumericTextField(
                            placeholder: "",
                            value: Binding(
                                get: { job.washUpVolume_m3 },
                                set: { job.washUpVolume_m3 = $0 }
                            ),
                            fractionDigits: 2
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("m³")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Pump Out:")
                        Spacer()
                        NumericTextField(
                            placeholder: "",
                            value: Binding(
                                get: { job.pumpOutVolume_m3 },
                                set: { job.pumpOutVolume_m3 = $0 }
                            ),
                            fractionDigits: 2
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("m³")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
            }
        }
    }

    private func stagesSectionIOS(job: CementJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Stages")
                    .font(.headline)
                Spacer()

                Menu {
                    Button("Add Pre-Flush") { addStage(.preFlush, to: job) }
                    Button("Add Spacer") { addStage(.spacer, to: job) }
                    Button("Add Lead Cement") { addStage(.leadCement, to: job) }
                    Button("Add Tail Cement") { addStage(.tailCement, to: job) }
                    Button("Add Mud Displacement") { addStage(.mudDisplacement, to: job) }
                    Button("Add Water Displacement") { addStage(.displacement, to: job) }
                    Divider()
                    Menu("Add Operation") {
                        ForEach(CementJobStage.OperationType.allCases, id: \.self) { opType in
                            Button(opType.displayName) { addOperation(opType, to: job) }
                        }
                    }
                    Divider()
                    Button("Add Template Stages") {
                        viewModel.createTemplateStages(for: job, context: modelContext)
                    }
                } label: {
                    Label("Add Stage", systemImage: "plus")
                }
            }

            if job.sortedStages.isEmpty {
                Text("No stages yet. Add stages to build your cement job.")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .padding()
            } else {
                ForEach(job.sortedStages, id: \.id) { stage in
                    StageRowIOS(stage: stage, job: job, viewModel: viewModel, context: modelContext)
                }
            }
        }
    }

    private func clipboardSectionIOS(job: CementJob) -> some View {
        GroupBox("Job Summary") {
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.generateJobSummary(job))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(4)

                Button(action: { viewModel.copyToClipboard(job) }) {
                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(8)
        }
    }
    #endif

    // MARK: - Job Header (macOS)
    #if os(macOS)
    private func jobHeader(job: CementJob) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Job Name", text: Binding(
                    get: { job.name },
                    set: { job.name = $0; job.updatedAt = .now }
                ))
                .font(.title2.bold())
                .textFieldStyle(.plain)

                Text(job.casingType.displayName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { showingSimulation = true }) {
                Label("Run Simulation", systemImage: "play.circle")
            }
            .buttonStyle(.borderedProminent)

            Button(action: { viewModel.copyToClipboard(job) }) {
                Label("Copy Summary", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Job Settings Section (macOS)

    private func jobSettingsSection(job: CementJob) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // General Settings
            GroupBox("General Settings") {
                VStack(alignment: .leading, spacing: 12) {
                    // Casing type picker
                    HStack {
                        Text("Casing Type:")
                            .frame(width: 140, alignment: .trailing)
                        Picker("", selection: Binding(
                            get: { job.casingType },
                            set: { job.casingType = $0 }
                        )) {
                            ForEach(CementJob.CasingType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .labelsHidden()
                    }

                    // Cement Top depth
                    HStack {
                        Text("Cement Top (MD):")
                            .frame(width: 140, alignment: .trailing)
                        NumericTextField(
                            placeholder: "",
                            value: Binding(
                                get: { job.topMD_m },
                                set: { job.topMD_m = $0 }
                            ),
                            fractionDigits: 0,
                            onCommit: { viewModel.updateVolumes(project: project) }
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        Text("m")
                            .foregroundColor(.secondary)
                    }

                    // Cement Bottom depth
                    HStack {
                        Text("Cement Bottom (MD):")
                            .frame(width: 140, alignment: .trailing)
                        NumericTextField(
                            placeholder: "",
                            value: Binding(
                                get: { job.bottomMD_m },
                                set: { job.bottomMD_m = $0 }
                            ),
                            fractionDigits: 2,
                            onCommit: { viewModel.updateVolumes(project: project) }
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        Text("m")
                            .foregroundColor(.secondary)
                    }

                    // Float collar depth
                    HStack {
                        Text("Float Collar (MD):")
                            .frame(width: 140, alignment: .trailing)
                        NumericTextField(
                            placeholder: "",
                            value: Binding(
                                get: { job.floatCollarDepth_m },
                                set: { job.floatCollarDepth_m = $0 }
                            ),
                            fractionDigits: 0
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        Text("m")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
            }

            // Lead Cement Settings
            GroupBox("Lead Cement") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Top (MD):")
                            .frame(width: 100, alignment: .trailing)
                        NumericTextField(
                            placeholder: "",
                            value: Binding(
                                get: { job.leadTopMD_m },
                                set: { job.leadTopMD_m = $0 }
                            ),
                            fractionDigits: 0
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("m")
                            .foregroundColor(.secondary)

                        Text("Bottom:")
                            .frame(width: 60, alignment: .trailing)
                        NumericTextField(
                            placeholder: "",
                            value: Binding(
                                get: { job.leadBottomMD_m },
                                set: { job.leadBottomMD_m = $0 }
                            ),
                            fractionDigits: 0
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("m")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Excess:")
                            .frame(width: 100, alignment: .trailing)
                        NumericTextField(
                            placeholder: "",
                            value: Binding(
                                get: { job.leadExcessPercent },
                                set: { job.leadExcessPercent = $0 }
                            ),
                            fractionDigits: 0
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        Text("%")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Yield:")
                            .frame(width: 100, alignment: .trailing)
                        NumericTextField(
                            placeholder: "",
                            value: Binding(
                                get: { job.leadYieldFactor_m3_per_tonne },
                                set: { job.leadYieldFactor_m3_per_tonne = $0 }
                            ),
                            fractionDigits: 3,
                            onCommit: { viewModel.updateAllStageCalculations(job) }
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("m³/t")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Mix Water:")
                            .frame(width: 100, alignment: .trailing)
                        NumericTextField(
                            placeholder: "",
                            value: Binding(
                                get: { job.leadMixWaterRatio_m3_per_tonne },
                                set: { job.leadMixWaterRatio_m3_per_tonne = $0 }
                            ),
                            fractionDigits: 3,
                            onCommit: { viewModel.updateAllStageCalculations(job) }
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("m³/t")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
            }

            // Tail Cement Settings
            GroupBox("Tail Cement") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Top (MD):")
                            .frame(width: 100, alignment: .trailing)
                        NumericTextField(
                            placeholder: "",
                            value: Binding(
                                get: { job.tailTopMD_m },
                                set: { job.tailTopMD_m = $0 }
                            ),
                            fractionDigits: 0
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("m")
                            .foregroundColor(.secondary)

                        Text("Bottom:")
                            .frame(width: 60, alignment: .trailing)
                        NumericTextField(
                            placeholder: "",
                            value: Binding(
                                get: { job.tailBottomMD_m },
                                set: { job.tailBottomMD_m = $0 }
                            ),
                            fractionDigits: 0
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("m")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Excess:")
                            .frame(width: 100, alignment: .trailing)
                        NumericTextField(
                            placeholder: "",
                            value: Binding(
                                get: { job.tailExcessPercent },
                                set: { job.tailExcessPercent = $0 }
                            ),
                            fractionDigits: 0
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        Text("%")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Yield:")
                            .frame(width: 100, alignment: .trailing)
                        NumericTextField(
                            placeholder: "",
                            value: Binding(
                                get: { job.tailYieldFactor_m3_per_tonne },
                                set: { job.tailYieldFactor_m3_per_tonne = $0 }
                            ),
                            fractionDigits: 3,
                            onCommit: { viewModel.updateAllStageCalculations(job) }
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("m³/t")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Mix Water:")
                            .frame(width: 100, alignment: .trailing)
                        NumericTextField(
                            placeholder: "",
                            value: Binding(
                                get: { job.tailMixWaterRatio_m3_per_tonne },
                                set: { job.tailMixWaterRatio_m3_per_tonne = $0 }
                            ),
                            fractionDigits: 3,
                            onCommit: { viewModel.updateAllStageCalculations(job) }
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("m³/t")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
            }

            // Additional Volumes
            GroupBox("Additional Volumes") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Wash Up:")
                            .frame(width: 100, alignment: .trailing)
                        NumericTextField(
                            placeholder: "",
                            value: Binding(
                                get: { job.washUpVolume_m3 },
                                set: { job.washUpVolume_m3 = $0 }
                            ),
                            fractionDigits: 2
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("m³")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Pump Out:")
                            .frame(width: 100, alignment: .trailing)
                        NumericTextField(
                            placeholder: "",
                            value: Binding(
                                get: { job.pumpOutVolume_m3 },
                                set: { job.pumpOutVolume_m3 = $0 }
                            ),
                            fractionDigits: 2
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("m³")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
            }
        }
    }
    #endif

    // MARK: - Volume Breakdown Section (Shared)

    private func volumeBreakdownSection(job: CementJob) -> some View {
        let vb = viewModel.volumeBreakdown

        return GroupBox("Volume Breakdown") {
            VStack(alignment: .leading, spacing: 8) {
                // Lead cement section
                if vb.leadTotalVolume_m3 > 0 {
                    Text("Lead Cement")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    if vb.leadCasedVolume_m3 > 0 {
                        VolumeRow(label: "Cased:", value: vb.leadCasedVolume_m3, unit: "m³")
                    }
                    VolumeRow(label: "Open Hole:", value: vb.leadOpenHoleVolume_m3, unit: "m³")
                    VolumeRow(label: "Excess (\(Int(vb.leadExcessPercent))%):", value: vb.leadExcessVolume_m3, unit: "m³")

                    HStack {
                        Text("Lead Total:")
                            .fontWeight(.medium)
                        Spacer()
                        Text(String(format: "%.2f m³", vb.leadTotalVolume_m3))
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                    .font(.callout)
                }

                // Tail cement section
                if vb.tailTotalVolume_m3 > 0 {
                    if vb.leadTotalVolume_m3 > 0 {
                        Divider()
                    }

                    Text("Tail Cement")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    if vb.tailCasedVolume_m3 > 0 {
                        VolumeRow(label: "Cased:", value: vb.tailCasedVolume_m3, unit: "m³")
                    }
                    VolumeRow(label: "Open Hole:", value: vb.tailOpenHoleVolume_m3, unit: "m³")
                    VolumeRow(label: "Excess (\(Int(vb.tailExcessPercent))%):", value: vb.tailExcessVolume_m3, unit: "m³")

                    HStack {
                        Text("Tail Total:")
                            .fontWeight(.medium)
                        Spacer()
                        Text(String(format: "%.2f m³", vb.tailTotalVolume_m3))
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                    .font(.callout)
                }

                Divider()

                // Total cement required
                HStack {
                    Text("Total Cement:")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(String(format: "%.2f m³", vb.totalVolume_m3))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }

                Divider()

                // Mud return
                VolumeRow(label: "Mud Return:", value: vb.mudReturn_m3, unit: "m³")

                // Volume to bump
                if vb.volumeToBump_m3 > 0 {
                    VolumeRow(label: "Volume to Bump:", value: vb.volumeToBump_m3, unit: "m³")
                    Text("(to float collar @ \(String(format: "%.0f", job.floatCollarDepth_m))m)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
        }
    }

    // MARK: - Statistics Section

    private func statisticsSection(job: CementJob) -> some View {
        let stats = viewModel.getJobStatistics(job)
        let water = viewModel.getWaterRequirements(job)

        return GroupBox("Summary") {
            VStack(alignment: .leading, spacing: 8) {
                // Cement volumes
                StatRow(label: "Lead Cement:", value: String(format: "%.2f m³", stats.leadCementVolume_m3))
                StatRow(label: "Tail Cement:", value: String(format: "%.2f m³", stats.tailCementVolume_m3))
                StatRow(label: "Total Tonnage:", value: String(format: "%.2f t", stats.totalCementTonnage_t))

                Divider()

                // Water requirements by stage
                Text("Water Requirements")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                if water.preFlushWater_L > 0 {
                    StatRow(label: "Pre-Flush:", value: String(format: "%.2f m³", water.preFlushWater_L / 1000))
                }
                if water.spacerWater_L > 0 {
                    StatRow(label: "Spacer:", value: String(format: "%.2f m³", water.spacerWater_L / 1000))
                }
                if water.leadMixWater_L > 0 {
                    StatRow(label: "Lead Mix Water:", value: String(format: "%.2f m³", water.leadMixWater_L / 1000))
                }
                if water.tailMixWater_L > 0 {
                    StatRow(label: "Tail Mix Water:", value: String(format: "%.2f m³", water.tailMixWater_L / 1000))
                }
                if water.displacementWater_L > 0 {
                    StatRow(label: "Displacement:", value: String(format: "%.2f m³", water.displacementWater_L / 1000))
                }
                if water.washUpWater_L > 0 {
                    StatRow(label: "Wash Up:", value: String(format: "%.2f m³", water.washUpWater_L / 1000))
                }
                if water.pumpOutWater_L > 0 {
                    StatRow(label: "Pump Out:", value: String(format: "%.2f m³", water.pumpOutWater_L / 1000))
                }

                Divider()

                // Total water usage
                HStack {
                    Text("Total Water:")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(String(format: "%.2f m³", water.totalWater_m3))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .font(.callout)

                Text("(excludes mud displacement)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(8)
        }
    }

    // MARK: - Stages Section (macOS)
    #if os(macOS)
    private func stagesSection(job: CementJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Stages")
                    .font(.headline)
                Spacer()

                Menu {
                    Button("Add Pre-Flush") { addStage(.preFlush, to: job) }
                    Button("Add Spacer") { addStage(.spacer, to: job) }
                    Button("Add Lead Cement") { addStage(.leadCement, to: job) }
                    Button("Add Tail Cement") { addStage(.tailCement, to: job) }
                    Button("Add Mud Displacement") { addStage(.mudDisplacement, to: job) }
                    Button("Add Water Displacement") { addStage(.displacement, to: job) }
                    Divider()
                    Menu("Add Operation") {
                        ForEach(CementJobStage.OperationType.allCases, id: \.self) { opType in
                            Button(opType.displayName) { addOperation(opType, to: job) }
                        }
                    }
                    Divider()
                    Button("Add Template Stages") {
                        viewModel.createTemplateStages(for: job, context: modelContext)
                    }
                } label: {
                    Label("Add Stage", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
            }

            if job.sortedStages.isEmpty {
                Text("No stages yet. Add stages to build your cement job.")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .padding()
            } else {
                ForEach(job.sortedStages, id: \.id) { stage in
                    StageRow(stage: stage, job: job, viewModel: viewModel, context: modelContext)
                }
            }
        }
    }

    // MARK: - Clipboard Section (macOS)

    private func clipboardSection(job: CementJob) -> some View {
        GroupBox("Job Summary (Clipboard)") {
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.generateJobSummary(job))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(4)

                HStack {
                    Spacer()
                    Button(action: { viewModel.copyToClipboard(job) }) {
                        Label("Copy to Clipboard", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(8)
        }
    }
    #endif

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cylinder.split.1x2")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Cement Job Selected")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("Select a cement job from the list or create a new one.")
                .foregroundColor(.secondary)

            Button(action: { showingNewJobSheet = true }) {
                Label("New Cement Job", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helper Methods

    private func addStage(_ type: CementJobStage.StageType, to job: CementJob) {
        let stage = CementJobStage(stageType: type, name: type.displayName)
        viewModel.addStage(stage, to: job, context: modelContext)
    }

    private func addOperation(_ type: CementJobStage.OperationType, to job: CementJob) {
        let stage = CementJobStage.operation(type: type, cementJob: job)
        viewModel.addStage(stage, to: job, context: modelContext)
    }
}

// MARK: - Supporting Views

struct JobListRow: View {
    let job: CementJob

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(job.name.isEmpty ? "Untitled Job" : job.name)
                .font(.headline)
            Text(job.casingType.displayName)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(String(format: "%.0f - %.0fm", job.topMD_m, job.bottomMD_m))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct VolumeRow: View {
    let label: String
    let value: Double
    let unit: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(String(format: "%.2f %@", value, unit))
                .monospacedDigit()
        }
        .font(.callout)
    }
}

struct StatRow: View {
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

#if os(macOS)
struct StageRow: View {
    @Bindable var stage: CementJobStage
    let job: CementJob
    let viewModel: CementJobViewModel
    let context: ModelContext
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header row
            HStack {
                // Stage type indicator
                Circle()
                    .fill(stage.color)
                    .frame(width: 12, height: 12)

                Text(stage.stageType.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .leading)

                TextField("Name", text: $stage.name)
                    .textFieldStyle(.roundedBorder)

                if stage.stageType.isPumpStage {
                    TextField("Vol", value: Binding(
                        get: { stage.volume_m3 },
                        set: {
                            stage.volume_m3 = $0
                            viewModel.updateStageCalculations(stage, job: job)
                        }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)

                    Text("m³")
                        .foregroundColor(.secondary)
                        .font(.caption)

                    TextField("Density", value: $stage.density_kgm3, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)

                    Text("kg/m³")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }

                if let tonnage = stage.tonnage_t {
                    Text(String(format: "(%.2ft)", tonnage))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Move up/down buttons
                Button(action: { viewModel.moveStage(stage, direction: -1, in: job, context: context) }) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(stage.orderIndex == 0)

                Button(action: { viewModel.moveStage(stage, direction: 1, in: job, context: context) }) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(stage.orderIndex >= (job.sortedStages.count - 1))

                Divider()
                    .frame(height: 16)

                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up.chevron.down" : "ellipsis.circle")
                }
                .buttonStyle(.borderless)

                Button(action: {
                    viewModel.removeStage(stage, from: job, context: context)
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }

            // Expanded details
            if isExpanded {
                expandedDetails
                    .padding(.leading, 24)
                    .padding(.top, 4)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }

    @ViewBuilder
    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Stage type picker (always show for pump stages)
            if stage.stageType != .operation {
                HStack {
                    Text("Stage Type:")
                    Picker("", selection: Binding(
                        get: { stage.stageType },
                        set: { newType in
                            stage.stageType = newType
                            // Update name if it was the default name
                            let oldDefault = CementJobStage.StageType(rawValue: stage.stageTypeRaw)?.displayName ?? ""
                            if stage.name.isEmpty || stage.name == oldDefault {
                                stage.name = newType.displayName
                            }
                            viewModel.updateStageCalculations(stage, job: job)
                        }
                    )) {
                        ForEach(CementJobStage.StageType.allCases.filter { $0 != .operation }, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
            }

            if stage.stageType == .operation, let opType = stage.operationType {
                // Operation-specific fields
                HStack {
                    Text("Operation Type:")
                    Picker("", selection: Binding(
                        get: { stage.operationType ?? .other },
                        set: { stage.operationType = $0 }
                    )) {
                        ForEach(CementJobStage.OperationType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                if opType == .pressureTestLines || opType == .tripSet || opType == .bumpPlug || opType == .pressureTestCasing {
                    HStack {
                        Text("Pressure:")
                        TextField("", value: $stage.pressure_MPa, format: .number.precision(.fractionLength(1)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text("MPa")
                            .foregroundColor(.secondary)
                    }
                }

                if opType == .bumpPlug {
                    HStack {
                        Text("Over FCP:")
                        TextField("", value: $stage.overPressure_MPa, format: .number.precision(.fractionLength(1)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text("MPa")
                            .foregroundColor(.secondary)
                    }
                }

                if opType == .pressureTestCasing {
                    HStack {
                        Text("Duration:")
                        TextField("", value: $stage.duration_min, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text("min")
                            .foregroundColor(.secondary)
                    }
                }

                if opType == .bleedBack {
                    HStack {
                        Text("Volume:")
                        TextField("", value: $stage.operationVolume_L, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("L")
                            .foregroundColor(.secondary)
                    }
                }

                if opType == .floatCheck {
                    Toggle("Floats Closed/Held", isOn: $stage.floatsClosed)
                }

                if opType == .plugDrop {
                    Toggle("Drop Plug On The Fly", isOn: $stage.plugDropOnTheFly)
                }
            } else {
                // Pump stage fields
                HStack {
                    Text("Pump Rate:")
                    TextField("", value: $stage.pumpRate_m3permin, format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Text("m³/min")
                        .foregroundColor(.secondary)
                }

                if stage.stageType.isCementStage {
                    if let tonnage = stage.tonnage_t {
                        HStack {
                            Text("Tonnage:")
                            Text(String(format: "%.2f t", tonnage))
                                .foregroundColor(.secondary)
                        }
                    }

                    if let water = stage.mixWater_L {
                        HStack {
                            Text("Mix Water:")
                            Text(String(format: "%.2f m³", water / 1000.0))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                ColorPicker("Color:", selection: $stage.color)
            }

            HStack {
                Text("Notes:")
                TextField("", text: $stage.notes)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .font(.callout)
    }
}
#endif

// MARK: - Stage Row (iOS)
#if os(iOS)
struct StageRowIOS: View {
    @Bindable var stage: CementJobStage
    let job: CementJob
    let viewModel: CementJobViewModel
    let context: ModelContext
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header row
            HStack {
                // Stage type indicator
                Circle()
                    .fill(stage.color)
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text(stage.stageType.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(stage.name.isEmpty ? "Unnamed" : stage.name)
                        .font(.subheadline)
                }

                Spacer()

                if stage.stageType.isPumpStage {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.2f m³", stage.volume_m3))
                            .font(.subheadline)
                            .monospacedDigit()
                        Text(String(format: "%.0f kg/m³", stage.density_kgm3))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let tonnage = stage.tonnage_t {
                    Text(String(format: "(%.2ft)", tonnage))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Move up/down buttons
                Button(action: { viewModel.moveStage(stage, direction: -1, in: job, context: context) }) {
                    Image(systemName: "chevron.up")
                }
                .disabled(stage.orderIndex == 0)

                Button(action: { viewModel.moveStage(stage, direction: 1, in: job, context: context) }) {
                    Image(systemName: "chevron.down")
                }
                .disabled(stage.orderIndex >= (job.sortedStages.count - 1))

                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "xmark.circle" : "ellipsis.circle")
                }

                Button(action: {
                    viewModel.removeStage(stage, from: job, context: context)
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }

            // Expanded details
            if isExpanded {
                expandedDetailsIOS
                    .padding(.top, 8)
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var expandedDetailsIOS: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Stage type picker (for pump stages)
            if stage.stageType != .operation {
                HStack {
                    Text("Stage Type:")
                    Spacer()
                    Picker("", selection: Binding(
                        get: { stage.stageType },
                        set: { newType in
                            stage.stageType = newType
                            let oldDefault = CementJobStage.StageType(rawValue: stage.stageTypeRaw)?.displayName ?? ""
                            if stage.name.isEmpty || stage.name == oldDefault {
                                stage.name = newType.displayName
                            }
                            viewModel.updateStageCalculations(stage, job: job)
                        }
                    )) {
                        ForEach(CementJobStage.StageType.allCases.filter { $0 != .operation }, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            // Editable name
            HStack {
                Text("Name:")
                TextField("Name", text: $stage.name)
                    .textFieldStyle(.roundedBorder)
            }

            if stage.stageType.isPumpStage {
                HStack {
                    Text("Volume:")
                    TextField("Vol", value: Binding(
                        get: { stage.volume_m3 },
                        set: {
                            stage.volume_m3 = $0
                            viewModel.updateStageCalculations(stage, job: job)
                        }
                    ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .frame(width: 80)
                    Text("m³")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Density:")
                    TextField("Density", value: $stage.density_kgm3, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                        .frame(width: 80)
                    Text("kg/m³")
                        .foregroundColor(.secondary)
                }
            }

            if stage.stageType == .operation, let opType = stage.operationType {
                // Operation-specific fields
                HStack {
                    Text("Operation:")
                    Picker("", selection: Binding(
                        get: { stage.operationType ?? .other },
                        set: { stage.operationType = $0 }
                    )) {
                        ForEach(CementJobStage.OperationType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                if opType == .pressureTestLines || opType == .tripSet || opType == .bumpPlug || opType == .pressureTestCasing {
                    HStack {
                        Text("Pressure:")
                        TextField("", value: $stage.pressure_MPa, format: .number.precision(.fractionLength(1)))
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                            .frame(width: 80)
                        Text("MPa")
                            .foregroundColor(.secondary)
                    }
                }

                if opType == .bumpPlug {
                    HStack {
                        Text("Over FCP:")
                        TextField("", value: $stage.overPressure_MPa, format: .number.precision(.fractionLength(1)))
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                            .frame(width: 80)
                        Text("MPa")
                            .foregroundColor(.secondary)
                    }
                }

                if opType == .pressureTestCasing {
                    HStack {
                        Text("Duration:")
                        TextField("", value: $stage.duration_min, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                            .frame(width: 80)
                        Text("min")
                            .foregroundColor(.secondary)
                    }
                }

                if opType == .bleedBack {
                    HStack {
                        Text("Volume:")
                        TextField("", value: $stage.operationVolume_L, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                            .frame(width: 80)
                        Text("L")
                            .foregroundColor(.secondary)
                    }
                }

                if opType == .floatCheck {
                    Toggle("Floats Closed/Held", isOn: $stage.floatsClosed)
                }

                if opType == .plugDrop {
                    Toggle("Drop Plug On The Fly", isOn: $stage.plugDropOnTheFly)
                }
            } else if stage.stageType.isPumpStage {
                // Pump stage fields
                HStack {
                    Text("Pump Rate:")
                    TextField("", value: $stage.pumpRate_m3permin, format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                        .frame(width: 80)
                    Text("m³/min")
                        .foregroundColor(.secondary)
                }

                if stage.stageType.isCementStage {
                    if let tonnage = stage.tonnage_t {
                        HStack {
                            Text("Tonnage:")
                            Text(String(format: "%.2f t", tonnage))
                                .foregroundColor(.secondary)
                        }
                    }

                    if let water = stage.mixWater_L {
                        HStack {
                            Text("Mix Water:")
                            Text(String(format: "%.2f m³", water / 1000.0))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                ColorPicker("Color:", selection: $stage.color)
            }

            HStack {
                Text("Notes:")
                TextField("", text: $stage.notes)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .font(.callout)
    }
}
#endif

// MARK: - New Cement Job Sheet

struct NewCementJobSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let project: ProjectState
    let viewModel: CementJobViewModel

    @State private var name = ""
    @State private var casingType: CementJob.CasingType = .intermediate
    @State private var topMD_m: Double = 0
    @State private var bottomMD_m: Double = 0
    @State private var excessPercent: Double = 50

    var body: some View {
        VStack(spacing: 16) {
            Text("New Cement Job")
                .font(.headline)

            Form {
                TextField("Job Name:", text: $name)

                Picker("Casing Type:", selection: $casingType) {
                    ForEach(CementJob.CasingType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }

                TextField("Cement Top (MD):", value: $topMD_m, format: .number)
                TextField("Cement Bottom (MD):", value: $bottomMD_m, format: .number)
                TextField("Open Hole Excess %:", value: $excessPercent, format: .number)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    let job = viewModel.createCementJob(
                        name: name.isEmpty ? casingType.displayName : name,
                        casingType: casingType,
                        topMD_m: topMD_m,
                        bottomMD_m: bottomMD_m,
                        excessPercent: excessPercent,
                        project: project,
                        context: modelContext
                    )
                    viewModel.selectedJob = job
                    viewModel.updateVolumes(project: project)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(bottomMD_m <= topMD_m)
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            // Default bottom to deepest annulus section
            if let deepest = (project.annulus ?? []).map({ $0.bottomDepth_m }).max() {
                bottomMD_m = deepest
            }
            // Default top to previous casing shoe if any
            if let casingShoe = (project.annulus ?? []).filter({ $0.isCased }).map({ $0.bottomDepth_m }).max() {
                topMD_m = casingShoe
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CementJobView_Previews: PreviewProvider {
    static var previews: some View {
        let container = try! ModelContainer(
            for: ProjectState.self,
                 AnnulusSection.self,
                 DrillStringSection.self,
                 MudProperties.self,
                 CementJob.self,
                 CementJobStage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext
        let p = ProjectState()
        ctx.insert(p)

        // Add some annulus sections
        let cased = AnnulusSection(name: "Surface Casing", topDepth_m: 0, length_m: 500, innerDiameter_m: 0.340, outerDiameter_m: 0.127, isCased: true, project: p)
        let openHole = AnnulusSection(name: "Open Hole", topDepth_m: 500, length_m: 2000, innerDiameter_m: 0.311, outerDiameter_m: 0.127, isCased: false, project: p)
        p.annulus = [cased, openHole]
        ctx.insert(cased)
        ctx.insert(openHole)

        try? ctx.save()

        return CementJobView(project: p)
            .modelContainer(container)
            .frame(width: 1200, height: 800)
    }
}
#endif
