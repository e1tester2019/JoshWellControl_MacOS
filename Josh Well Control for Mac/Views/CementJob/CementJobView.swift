//
//  CementJobView.swift
//  Josh Well Control for Mac
//
//  Main view for cement job planning and management.
//

import SwiftUI
import SwiftData

struct CementJobView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState
    @State private var viewModel = CementJobViewModel()
    @State private var showingNewJobSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var jobToDelete: CementJob?

    var body: some View {
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
    }

    // MARK: - Job List Panel

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

            if (project.cementJobs ?? []).isEmpty {
                Text("No cement jobs yet.\nClick + to create one.")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(
                    get: { viewModel.selectedJob?.id },
                    set: { id in
                        viewModel.selectedJob = (project.cementJobs ?? []).first { $0.id == id }
                        if let job = viewModel.selectedJob {
                            viewModel.updateVolumes(project: project)
                            viewModel.updateAllStageCalculations(job)
                        }
                    }
                )) {
                    ForEach(project.cementJobs ?? [], id: \.id) { job in
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

    // MARK: - Job Detail Panel

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

    // MARK: - Job Header

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

            Button(action: { viewModel.copyToClipboard(job) }) {
                Label("Copy Summary", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Job Settings Section

    private func jobSettingsSection(job: CementJob) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // General Settings
            GroupBox("General Settings") {
                VStack(alignment: .leading, spacing: 12) {
                    // Casing type picker
                    HStack {
                        Text("Casing Type:")
                            .frame(width: 120, alignment: .trailing)
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

                    // Top depth
                    HStack {
                        Text("Cement Top (MD):")
                            .frame(width: 120, alignment: .trailing)
                        TextField("", value: Binding(
                            get: { job.topMD_m },
                            set: { job.topMD_m = $0; viewModel.updateVolumes(project: project) }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        Text("m")
                            .foregroundColor(.secondary)
                    }

                    // Bottom depth
                    HStack {
                        Text("Cement Bottom (MD):")
                            .frame(width: 120, alignment: .trailing)
                        TextField("", value: Binding(
                            get: { job.bottomMD_m },
                            set: { job.bottomMD_m = $0; viewModel.updateVolumes(project: project) }
                        ), format: .number)
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
                        TextField("", value: Binding(
                            get: { job.leadTopMD_m },
                            set: { job.leadTopMD_m = $0 }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("m")
                            .foregroundColor(.secondary)

                        Text("Bottom:")
                            .frame(width: 60, alignment: .trailing)
                        TextField("", value: Binding(
                            get: { job.leadBottomMD_m },
                            set: { job.leadBottomMD_m = $0 }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("m")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Excess:")
                            .frame(width: 100, alignment: .trailing)
                        TextField("", value: Binding(
                            get: { job.leadExcessPercent },
                            set: { job.leadExcessPercent = $0 }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        Text("%")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Yield:")
                            .frame(width: 100, alignment: .trailing)
                        TextField("", value: Binding(
                            get: { job.leadYieldFactor_m3_per_tonne },
                            set: {
                                job.leadYieldFactor_m3_per_tonne = $0
                                viewModel.updateAllStageCalculations(job)
                            }
                        ), format: .number.precision(.fractionLength(3)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("m³/t")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Mix Water:")
                            .frame(width: 100, alignment: .trailing)
                        TextField("", value: Binding(
                            get: { job.leadMixWaterRatio_L_per_tonne },
                            set: {
                                job.leadMixWaterRatio_L_per_tonne = $0
                                viewModel.updateAllStageCalculations(job)
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("L/t")
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
                        TextField("", value: Binding(
                            get: { job.tailTopMD_m },
                            set: { job.tailTopMD_m = $0 }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("m")
                            .foregroundColor(.secondary)

                        Text("Bottom:")
                            .frame(width: 60, alignment: .trailing)
                        TextField("", value: Binding(
                            get: { job.tailBottomMD_m },
                            set: { job.tailBottomMD_m = $0 }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("m")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Excess:")
                            .frame(width: 100, alignment: .trailing)
                        TextField("", value: Binding(
                            get: { job.tailExcessPercent },
                            set: { job.tailExcessPercent = $0 }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        Text("%")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Yield:")
                            .frame(width: 100, alignment: .trailing)
                        TextField("", value: Binding(
                            get: { job.tailYieldFactor_m3_per_tonne },
                            set: {
                                job.tailYieldFactor_m3_per_tonne = $0
                                viewModel.updateAllStageCalculations(job)
                            }
                        ), format: .number.precision(.fractionLength(3)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("m³/t")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Mix Water:")
                            .frame(width: 100, alignment: .trailing)
                        TextField("", value: Binding(
                            get: { job.tailMixWaterRatio_L_per_tonne },
                            set: {
                                job.tailMixWaterRatio_L_per_tonne = $0
                                viewModel.updateAllStageCalculations(job)
                            }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("L/t")
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
                        TextField("", value: Binding(
                            get: { job.washUpVolume_m3 },
                            set: { job.washUpVolume_m3 = $0 }
                        ), format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        Text("m³")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Pump Out:")
                            .frame(width: 100, alignment: .trailing)
                        TextField("", value: Binding(
                            get: { job.pumpOutVolume_m3 },
                            set: { job.pumpOutVolume_m3 = $0 }
                        ), format: .number.precision(.fractionLength(2)))
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

    // MARK: - Volume Breakdown Section

    private func volumeBreakdownSection(job: CementJob) -> some View {
        GroupBox("Volume Breakdown") {
            VStack(alignment: .leading, spacing: 8) {
                // By section
                ForEach(viewModel.volumeBreakdown.sectionVolumes) { section in
                    HStack {
                        Image(systemName: section.isCased ? "pipe.and.drop" : "circle.dotted")
                            .foregroundColor(section.isCased ? .blue : .orange)
                        Text(section.sectionName)
                        Spacer()
                        Text(String(format: "%.2f m³", section.volume_m3))
                            .monospacedDigit()
                        Text(section.isCased ? "(cased)" : "(open)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                }

                if !viewModel.volumeBreakdown.sectionVolumes.isEmpty {
                    Divider()
                }

                // Totals
                VolumeRow(label: "Cased Hole:", value: viewModel.volumeBreakdown.casedVolume_m3, unit: "m³")
                VolumeRow(label: "Open Hole:", value: viewModel.volumeBreakdown.openHoleVolume_m3, unit: "m³")
                VolumeRow(label: "Excess (\(Int(job.excessPercent))%):", value: viewModel.volumeBreakdown.excessVolume_m3, unit: "m³")

                Divider()

                HStack {
                    Text("Total Required:")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(String(format: "%.2f m³", viewModel.volumeBreakdown.totalVolume_m3))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
            .padding(8)
        }
    }

    // MARK: - Statistics Section

    private func statisticsSection(job: CementJob) -> some View {
        let stats = viewModel.getJobStatistics(job)

        return GroupBox("Summary") {
            VStack(alignment: .leading, spacing: 8) {
                // Cement volumes
                StatRow(label: "Lead Cement:", value: String(format: "%.2f m³", stats.leadCementVolume_m3))
                StatRow(label: "Tail Cement:", value: String(format: "%.2f m³", stats.tailCementVolume_m3))
                StatRow(label: "Total Tonnage:", value: String(format: "%.2f t", stats.totalCementTonnage_t))
                StatRow(label: "Mix Water:", value: String(format: "%.2f m³ (%.0f L)", stats.totalMixWater_m3, stats.totalMixWater_L))

                Divider()

                // Displacement
                StatRow(label: "Displacement:", value: String(format: "%.2f m³ (%.0f L)", stats.displacementVolume_m3, stats.displacementVolume_L))

                // Additional volumes
                if stats.washUpVolume_m3 > 0 || stats.pumpOutVolume_m3 > 0 {
                    if stats.washUpVolume_m3 > 0 {
                        StatRow(label: "Wash Up:", value: String(format: "%.2f m³", stats.washUpVolume_m3))
                    }
                    if stats.pumpOutVolume_m3 > 0 {
                        StatRow(label: "Pump Out:", value: String(format: "%.2f m³", stats.pumpOutVolume_m3))
                    }
                }

                Divider()

                // Total water usage
                HStack {
                    Text("Total Water:")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(String(format: "%.2f m³ (%.0f L)", stats.totalWaterUsage_m3, stats.totalWaterUsage_L))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .font(.callout)

                Text("(displacement + mix water + pump out + wash up)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(8)
        }
    }

    // MARK: - Stages Section

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
                    Button("Add Displacement") { addStage(.displacement, to: job) }
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

    // MARK: - Clipboard Section

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

                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
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
                            Text(String(format: "%.0f L", water))
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
