//
//  LookAheadListView.swift
//  Josh Well Control for Mac
//
//  Main view for the Look Ahead Scheduler showing timeline of tasks.
//

import SwiftUI
import SwiftData

enum TaskGroupingMode: String, CaseIterable {
    case byDate = "By Date"
    case byWell = "By Well"
    case bySequence = "Timeline"
}

struct LookAheadListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LookAheadSchedule.createdAt, order: .reverse) private var schedules: [LookAheadSchedule]
    @Query(sort: \JobCode.name) private var jobCodes: [JobCode]
    @Query(sort: \Vendor.companyName) private var vendors: [Vendor]
    @Query(sort: \Well.name) private var wells: [Well]

    @State private var viewModel = LookAheadViewModel()
    @State private var selectedSchedule: LookAheadSchedule?
    @State private var activeSheet: SheetType?
    @State private var showAnalytics = false

    // Multi-select
    @State private var selectedTaskIDs: Set<UUID> = []
    @State private var isSelectionMode = false

    // Grouping
    @State private var groupingMode: TaskGroupingMode = .byDate

    // MARK: - Sheet Types

    private enum SheetType: Identifiable {
        case addTask
        case editTask(LookAheadTask)
        case duplicateTask(LookAheadTask)
        case bulkDuplicate
        case scheduleEditor
        case completeTask(LookAheadTask)

        var id: String {
            switch self {
            case .addTask: return "addTask"
            case .editTask(let task): return "editTask-\(task.id)"
            case .duplicateTask(let task): return "duplicateTask-\(task.id)"
            case .bulkDuplicate: return "bulkDuplicate"
            case .scheduleEditor: return "scheduleEditor"
            case .completeTask(let task): return "completeTask-\(task.id)"
            }
        }
    }

    var body: some View {
        Group {
            if selectedSchedule != nil {
                mainContent
            } else {
                emptyState
            }
        }
        .navigationTitle("Look Ahead Scheduler")
        #if os(macOS)
        .toolbar { toolbarContent }
        #endif
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addTask:
                LookAheadTaskEditorView(
                    schedule: selectedSchedule,
                    task: nil,
                    jobCodes: jobCodes,
                    vendors: vendors,
                    wells: wells
                )
            case .editTask(let task):
                LookAheadTaskEditorView(
                    schedule: selectedSchedule,
                    task: task,
                    jobCodes: jobCodes,
                    vendors: vendors,
                    wells: wells
                )
            case .duplicateTask(let sourceTask):
                LookAheadTaskEditorView(
                    schedule: selectedSchedule,
                    task: nil,
                    templateTask: sourceTask,
                    jobCodes: jobCodes,
                    vendors: vendors,
                    wells: wells
                )
            case .bulkDuplicate:
                BulkDuplicateSheet(
                    schedule: selectedSchedule,
                    selectedTaskIDs: selectedTaskIDs,
                    wells: wells,
                    onComplete: {
                        selectedTaskIDs.removeAll()
                        isSelectionMode = false
                    }
                )
            case .scheduleEditor:
                LookAheadScheduleEditorView(schedule: selectedSchedule)
            case .completeTask(let task):
                TaskCompleteSheet(task: task, viewModel: viewModel)
            }
        }
        .onAppear {
            // Select active schedule or most recent
            selectedSchedule = schedules.first(where: { $0.isActive }) ?? schedules.first
            viewModel.schedule = selectedSchedule
            viewModel.calculateAnalytics()
        }
        .onChange(of: selectedSchedule) { _, newValue in
            viewModel.schedule = newValue
            viewModel.calculateAnalytics()
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        #if os(macOS)
        HSplitView {
            taskList
                .frame(minWidth: 400)
            if showAnalytics {
                analyticsPanel
                    .frame(minWidth: 300, maxWidth: 400)
            }
        }
        #else
        taskList
        #endif
    }

    private var taskList: some View {
        VStack(spacing: 0) {
            // Selection mode toolbar
            if isSelectionMode {
                selectionToolbar
            }

            List {
                if let schedule = selectedSchedule {
                    scheduleHeaderSection(schedule)

                    // Group based on mode
                    switch groupingMode {
                    case .byDate:
                        tasksGroupedByDate(schedule)
                    case .byWell:
                        tasksGroupedByWell(schedule)
                    case .bySequence:
                        tasksInSequence(schedule)
                    }

                    if schedule.taskCount == 0 {
                        ContentUnavailableView {
                            Label("No Tasks", systemImage: "calendar.badge.plus")
                        } description: {
                            Text("Add your first task to start building the schedule.")
                        } actions: {
                            Button("Add Task") { activeSheet = .addTask }
                        }
                    }
                }
            }
            #if os(macOS)
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .onDeleteCommand {
                // Delete selected task on macOS when Delete key is pressed
                if let task = viewModel.selectedTask {
                    viewModel.deleteTask(task, context: modelContext)
                    viewModel.selectedTask = nil
                }
            }
            #endif
        }
    }

    // MARK: - Selection Toolbar

    private var selectionToolbar: some View {
        HStack {
            Text("\(selectedTaskIDs.count) selected")
                .fontWeight(.medium)

            Spacer()

            Button("Select All") {
                if let schedule = selectedSchedule {
                    selectedTaskIDs = Set(schedule.sortedTasks.map { $0.id })
                }
            }
            .buttonStyle(.borderless)

            Button("Duplicate Selected") {
                activeSheet = .bulkDuplicate
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedTaskIDs.isEmpty)

            Button("Cancel") {
                selectedTaskIDs.removeAll()
                isSelectionMode = false
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Grouping Views

    @ViewBuilder
    private func tasksGroupedByDate(_ schedule: LookAheadSchedule) -> some View {
        ForEach(schedule.taskDates, id: \.self) { date in
            Section {
                ForEach(schedule.tasks(for: date)) { task in
                    #if os(macOS)
                    draggableTaskRow(for: task, in: schedule)
                    #else
                    taskRow(for: task)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.deleteTask(task, context: modelContext)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    #endif
                }
                #if os(iOS)
                .onMove { source, destination in
                    moveTasksInDateGroup(schedule: schedule, date: date, from: source, to: destination)
                }
                #endif
            } header: {
                Text(formatSectionDate(date))
                    .font(.headline)
            }
        }
    }

    @ViewBuilder
    private func tasksGroupedByWell(_ schedule: LookAheadSchedule) -> some View {
        // Group consecutive tasks by well while maintaining sequence order
        // This supports batch drilling where the same well appears multiple times
        let consecutiveGroups = buildConsecutiveWellGroups(schedule.sortedTasks)

        ForEach(Array(consecutiveGroups.enumerated()), id: \.offset) { index, group in
            Section {
                ForEach(group.tasks) { task in
                    #if os(macOS)
                    draggableTaskRow(for: task, in: schedule)
                    #else
                    taskRow(for: task)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.deleteTask(task, context: modelContext)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    #endif
                }
            } header: {
                HStack {
                    if let well = group.well {
                        Label(well.name, systemImage: "building.2")
                    } else {
                        Label("No Well Assigned", systemImage: "questionmark.circle")
                    }
                    Spacer()
                    Text("\(group.tasks.count) tasks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.headline)
            }
        }
    }

    /// Groups consecutive tasks by well while maintaining sequence order
    private func buildConsecutiveWellGroups(_ tasks: [LookAheadTask]) -> [WellTaskGroup] {
        var groups: [WellTaskGroup] = []
        var currentGroup: WellTaskGroup?

        for task in tasks {
            let taskWellID = task.well?.id

            if let group = currentGroup, group.wellID == taskWellID {
                // Same well as current group, add to it
                currentGroup?.tasks.append(task)
            } else {
                // Different well, start a new group
                if let group = currentGroup {
                    groups.append(group)
                }
                currentGroup = WellTaskGroup(well: task.well, tasks: [task])
            }
        }

        // Don't forget the last group
        if let group = currentGroup {
            groups.append(group)
        }

        return groups
    }

    @ViewBuilder
    private func tasksInSequence(_ schedule: LookAheadSchedule) -> some View {
        Section {
            ForEach(schedule.sortedTasks) { task in
                #if os(macOS)
                draggableTaskRow(for: task, in: schedule)
                #else
                taskRow(for: task)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            viewModel.deleteTask(task, context: modelContext)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                #endif
            }
            #if os(iOS)
            .onMove { source, destination in
                viewModel.moveTasks(from: source, to: destination, context: modelContext)
            }
            #endif
        } header: {
            #if os(macOS)
            Text("All Tasks (Drag handle ≡ to Reorder)")
                .font(.headline)
            #else
            Text("All Tasks (Drag to Reorder)")
                .font(.headline)
            #endif
        }
    }

    #if os(macOS)
    @ViewBuilder
    private func draggableTaskRow(for task: LookAheadTask, in schedule: LookAheadSchedule) -> some View {
        HStack(spacing: 8) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .font(.caption)
                .frame(width: 16)
                .draggable(task.id.uuidString) {
                    // Drag preview
                    HStack {
                        Image(systemName: "calendar.badge.clock")
                        Text(task.name)
                    }
                    .padding(8)
                    .background(.regularMaterial)
                    .cornerRadius(8)
                }

            taskRow(for: task)
        }
        .dropDestination(for: String.self) { droppedItems, _ in
            guard let droppedIDString = droppedItems.first,
                  let droppedID = UUID(uuidString: droppedIDString),
                  let droppedTask = schedule.sortedTasks.first(where: { $0.id == droppedID }),
                  droppedTask.id != task.id else {
                return false
            }

            // Move the dropped task to this position
            let targetPosition = task.sequenceOrder
            viewModel.moveTask(droppedTask, to: targetPosition, context: modelContext)
            return true
        }
    }
    #endif

    @ViewBuilder
    private func taskRow(for task: LookAheadTask) -> some View {
        HStack {
            if isSelectionMode {
                Image(systemName: selectedTaskIDs.contains(task.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedTaskIDs.contains(task.id) ? .blue : .secondary)
                    .onTapGesture {
                        toggleSelection(task)
                    }
            }

            LookAheadTaskRow(
                task: task,
                isSelected: viewModel.selectedTask?.id == task.id,
                onTap: {
                    if isSelectionMode {
                        toggleSelection(task)
                    } else {
                        viewModel.selectedTask = task
                    }
                },
                onEdit: { activeSheet = .editTask(task) },
                onDuplicate: { activeSheet = .duplicateTask(task) },
                onDelete: { viewModel.deleteTask(task, context: modelContext) },
                onStart: { startTask(task) },
                onComplete: { activeSheet = .completeTask(task) },
                onDelay: { delayTask(task) },
                onDurationChange: { newMinutes in
                    viewModel.updateDuration(task, newDuration: newMinutes, context: modelContext)
                }
            )
        }
    }

    private func toggleSelection(_ task: LookAheadTask) {
        if selectedTaskIDs.contains(task.id) {
            selectedTaskIDs.remove(task.id)
        } else {
            selectedTaskIDs.insert(task.id)
        }
    }

    private func moveTasksInDateGroup(schedule: LookAheadSchedule, date: Date, from source: IndexSet, to destination: Int) {
        let tasksForDate = schedule.tasks(for: date)
        guard let firstIndex = source.first,
              firstIndex < tasksForDate.count,
              destination <= tasksForDate.count else { return }

        // Calculate global positions
        let allTasks = schedule.sortedTasks
        guard let globalSourceIndex = allTasks.firstIndex(where: { $0.id == tasksForDate[firstIndex].id }) else { return }

        let destTask = destination < tasksForDate.count ? tasksForDate[destination] : tasksForDate.last
        guard let globalDestIndex = allTasks.firstIndex(where: { $0.id == destTask?.id }) else { return }

        viewModel.moveTasks(from: IndexSet(integer: globalSourceIndex), to: globalDestIndex, context: modelContext)
    }

    private func deleteTasksAtOffsets(_ offsets: IndexSet) {
        guard let schedule = selectedSchedule else { return }
        let tasks = schedule.sortedTasks
        for index in offsets {
            guard index < tasks.count else { continue }
            viewModel.deleteTask(tasks[index], context: modelContext)
        }
    }

    @ViewBuilder
    private func scheduleHeaderSection(_ schedule: LookAheadSchedule) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(schedule.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    if schedule.isActive {
                        Text("Active")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.2))
                            .foregroundStyle(.green)
                            .cornerRadius(4)
                    }
                }

                HStack {
                    Label(schedule.dateRangeFormatted, systemImage: "calendar")
                    Spacer()
                    Text("\(schedule.taskCount) tasks")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)

                if schedule.taskCount > 0 {
                    progressBar(schedule)
                }

                // Call status summary
                if !schedule.tasksNeedingCalls.isEmpty {
                    HStack {
                        Image(systemName: "phone.badge.waveform")
                            .foregroundStyle(.orange)
                        Text("\(schedule.tasksNeedingCalls.count) tasks need vendor calls")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func progressBar(_ schedule: LookAheadSchedule) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(schedule.completedTaskCount)/\(schedule.taskCount) completed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(schedule.progressPercentage * 100))%")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green)
                        .frame(width: geo.size.width * schedule.progressPercentage)
                }
            }
            .frame(height: 8)
        }
    }

    private var analyticsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Analytics")
                    .font(.headline)

                if let schedule = selectedSchedule {
                    Group {
                        MetricRow(title: "Total Duration", value: schedule.totalDurationFormatted)
                        MetricRow(title: "Tasks Completed", value: "\(schedule.completedTaskCount)")
                        MetricRow(title: "In Progress", value: "\(schedule.inProgressTaskCount)")
                        MetricRow(title: "Pending Calls", value: "\(schedule.tasksNeedingCalls.count)")

                        if let avgVariance = schedule.averageVariancePercentage {
                            MetricRow(
                                title: "Avg Variance",
                                value: String(format: "%+.1f%%", avgVariance),
                                valueColor: abs(avgVariance) < 10 ? .green : .orange
                            )
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var emptyState: some View {
        StandardEmptyState(
            icon: "list.bullet.clipboard",
            title: "No Tasks",
            description: "Create a look-ahead task to get started",
            actionLabel: "Create Schedule",
            action: { createNewSchedule() }
        )
    }

    // MARK: - Toolbar

    #if os(macOS)
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { activeSheet = .addTask } label: {
                Label("Add Task", systemImage: "plus")
            }
            .disabled(selectedSchedule == nil)
        }

        ToolbarItem {
            Button {
                isSelectionMode.toggle()
                if !isSelectionMode {
                    selectedTaskIDs.removeAll()
                }
            } label: {
                Label("Select", systemImage: isSelectionMode ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .disabled(selectedSchedule == nil)
        }

        ToolbarItem {
            Picker("Group", selection: $groupingMode) {
                ForEach(TaskGroupingMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
        }

        ToolbarItem {
            Button { showAnalytics.toggle() } label: {
                Label("Analytics", systemImage: showAnalytics ? "chart.bar.fill" : "chart.bar")
            }
        }

        ToolbarItem {
            Menu {
                ForEach(schedules) { schedule in
                    Button {
                        selectedSchedule = schedule
                    } label: {
                        HStack {
                            Text(schedule.name)
                            if schedule.isActive {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Button("New Schedule...") { createNewSchedule() }
                if selectedSchedule != nil {
                    Button("Edit Schedule...") { activeSheet = .scheduleEditor }
                    Button("Duplicate Schedule") { duplicateSchedule() }
                    Divider()
                    Button {
                        viewModel.recalculateAllTimes(context: modelContext)
                    } label: {
                        Label("Recalculate Timeline", systemImage: "arrow.clockwise")
                    }
                }
            } label: {
                Label("Schedules", systemImage: "list.bullet")
            }
        }
    }
    #endif

    // MARK: - Actions

    private func createNewSchedule() {
        let newSchedule = viewModel.createSchedule(
            name: "Schedule \(schedules.count + 1)",
            startDate: Date.now,
            context: modelContext
        )
        selectedSchedule = newSchedule
    }

    private func duplicateSchedule() {
        if let duplicate = viewModel.duplicateSchedule(context: modelContext) {
            selectedSchedule = duplicate
        }
    }

    private func startTask(_ task: LookAheadTask) {
        viewModel.startTask(task, context: modelContext)
    }

    private func delayTask(_ task: LookAheadTask) {
        viewModel.delayTask(task, context: modelContext)
    }

    private func deleteTasks(for date: Date, at offsets: IndexSet) {
        guard let schedule = selectedSchedule else { return }
        let tasksForDate = schedule.tasks(for: date)
        for index in offsets {
            guard index < tasksForDate.count else { continue }
            viewModel.deleteTask(tasksForDate[index], context: modelContext)
        }
    }

    private func formatSectionDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter.string(from: date)
    }
}

// MARK: - Task Row

struct LookAheadTaskRow: View {
    let task: LookAheadTask
    let isSelected: Bool
    var onTap: () -> Void
    var onEdit: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void
    var onStart: () -> Void
    var onComplete: () -> Void
    var onDelay: () -> Void
    var onDurationChange: ((Double) -> Void)? = nil

    @State private var showDurationPicker = false

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                // Task name and job code
                HStack {
                    Text(task.name)
                        .font(.headline)
                    if let jc = task.jobCode {
                        Text(jc.code)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(4)
                    }
                    Spacer()
                    Text(task.status.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.2))
                        .foregroundStyle(statusColor)
                        .cornerRadius(6)
                }

                // Time and duration
                HStack {
                    Text(task.timeRangeFormatted)
                        .font(.callout)

                    // Clickable duration with popover
                    Button {
                        showDurationPicker = true
                    } label: {
                        Text("(\(task.estimatedDurationFormatted))")
                            .font(.callout)
                            .foregroundStyle(.blue)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showDurationPicker) {
                        QuickDurationPicker(
                            currentMinutes: task.estimatedDuration_min,
                            onChange: { minutes in
                                onDurationChange?(minutes)
                                showDurationPicker = false
                            }
                        )
                    }

                    if let well = task.well {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Label(well.name, systemImage: "building.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Vendors and call status
                if !task.assignedVendors.isEmpty {
                    HStack {
                        // Show vendor names (up to 2, then "+N more")
                        let vendorNames = task.assignedVendors.prefix(2).map { $0.companyName }
                        let extraCount = task.assignedVendors.count - 2

                        Label {
                            if extraCount > 0 {
                                Text(vendorNames.joined(separator: ", ") + " +\(extraCount)")
                            } else {
                                Text(vendorNames.joined(separator: ", "))
                            }
                        } icon: {
                            Image(systemName: "person.2.badge.gearshape")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Spacer()

                        callStatusBadge
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .contextMenu {
            Button("Edit") { onEdit() }
            Button("Duplicate") { onDuplicate() }

            Divider()

            if task.status == .scheduled {
                Button("Start") { onStart() }
            }

            if task.status == .scheduled || task.status == .inProgress {
                Button("Complete...") { onComplete() }
                Button("Mark Delayed") { onDelay() }
            }

            Divider()

            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .scheduled: return .blue
        case .inProgress: return .orange
        case .completed: return .green
        case .delayed: return .red
        case .cancelled: return .gray
        }
    }

    @ViewBuilder
    private var callStatusBadge: some View {
        let hasConfirmed = task.hasConfirmedCall
        let callCount = task.callCount

        HStack(spacing: 4) {
            if hasConfirmed {
                Label("Confirmed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if callCount > 0 {
                Label("\(callCount) call(s)", systemImage: "phone.fill")
                    .foregroundStyle(.orange)
            } else if task.isCallOverdue {
                Label("Call Overdue", systemImage: "phone.badge.waveform")
                    .foregroundStyle(.red)
            } else {
                Label("Pending", systemImage: "phone")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
    }
}

// MARK: - Task Complete Sheet

struct TaskCompleteSheet: View {
    let task: LookAheadTask
    let viewModel: LookAheadViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var actualDuration: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    Text(task.name)
                        .font(.headline)
                        .lineLimit(2)
                    if let jc = task.jobCode {
                        Text(jc.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Duration") {
                    LabeledContent("Estimated") {
                        Text(task.estimatedDurationFormatted)
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Actual (minutes)") {
                        TextField("", value: $actualDuration, format: .number)
                            .frame(width: 100)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                    }

                    if actualDuration > 0 {
                        let variance = actualDuration - task.estimatedDuration_min
                        let variancePercent = task.estimatedDuration_min > 0
                            ? (variance / task.estimatedDuration_min) * 100
                            : 0
                        LabeledContent("Variance") {
                            Text(String(format: "%+.0f min (%+.1f%%)", variance, variancePercent))
                                .foregroundStyle(abs(variancePercent) < 10 ? .green : .orange)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Complete Task")
            #if os(macOS)
            .frame(minWidth: 450, minHeight: 280)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Complete") {
                        viewModel.completeTask(task, actualDuration: actualDuration, context: modelContext)
                        dismiss()
                    }
                    .disabled(actualDuration <= 0)
                }
            }
            .onAppear {
                actualDuration = task.estimatedDuration_min
            }
        }
    }
}

// MARK: - Supporting Types

/// Groups consecutive tasks by well for batch drilling display
struct WellTaskGroup {
    let well: Well?
    var tasks: [LookAheadTask]

    var wellID: UUID? { well?.id }
}

// MARK: - Supporting Views

struct MetricRow: View {
    let title: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(valueColor)
        }
    }
}

// MARK: - Bulk Duplicate Sheet

struct BulkDuplicateSheet: View {
    let schedule: LookAheadSchedule?
    let selectedTaskIDs: Set<UUID>
    let wells: [Well]
    var onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var targetWell: Well?
    @State private var depthOffset: Double = 0
    @State private var applyDepthOffset = false

    private var selectedTasks: [LookAheadTask] {
        guard let schedule = schedule else { return [] }
        return schedule.sortedTasks.filter { selectedTaskIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Selected Tasks") {
                    Text("\(selectedTasks.count) tasks to duplicate")
                        .font(.headline)

                    ForEach(selectedTasks.prefix(5)) { task in
                        HStack {
                            Text(task.name)
                            Spacer()
                            if let well = task.well {
                                Text(well.name)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.callout)
                    }
                    if selectedTasks.count > 5 {
                        Text("... and \(selectedTasks.count - 5) more")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                Section("Target Well") {
                    Picker("Assign to Well", selection: $targetWell) {
                        Text("Keep Original").tag(nil as Well?)
                        ForEach(wells) { well in
                            Text(well.name).tag(well as Well?)
                        }
                    }
                }

                Section("Depth Adjustment") {
                    Toggle("Apply Depth Offset", isOn: $applyDepthOffset)

                    if applyDepthOffset {
                        HStack {
                            Text("Offset")
                            Spacer()
                            TextField("", value: $depthOffset, format: .number)
                                .frame(width: 100)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                            Text("m")
                                .foregroundStyle(.secondary)
                        }

                        Text("Positive = deeper, Negative = shallower")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text("Duplicated tasks will be added to the end of the schedule. You can then drag to reorder them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Duplicate Tasks")
            #if os(macOS)
            .frame(minWidth: 450, minHeight: 400)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Duplicate \(selectedTasks.count) Tasks") {
                        duplicateTasks()
                    }
                    .disabled(selectedTasks.isEmpty)
                }
            }
        }
    }

    private func duplicateTasks() {
        guard let schedule = schedule else { return }

        let currentMaxOrder = schedule.sortedTasks.last?.sequenceOrder ?? -1
        var nextOrder = currentMaxOrder + 1

        // Track the end time of the last created task for proper cascading
        var lastEndTime: Date = schedule.sortedTasks.last?.endTime ?? schedule.startDate

        for task in selectedTasks {
            let newTask = LookAheadTask(
                name: task.name,
                estimatedDuration_min: task.estimatedDuration_min,
                sequenceOrder: nextOrder
            )

            newTask.notes = task.notes
            newTask.jobCode = task.jobCode
            newTask.well = targetWell ?? task.well
            newTask.isMetarageBased = task.isMetarageBased
            newTask.callReminderMinutesBefore = task.callReminderMinutesBefore
            newTask.vendorComments = task.vendorComments
            newTask.schedule = schedule

            // Apply depth offset if enabled
            if applyDepthOffset {
                if let start = task.startDepth_m {
                    newTask.startDepth_m = start + depthOffset
                }
                if let end = task.endDepth_m {
                    newTask.endDepth_m = end + depthOffset
                }
            } else {
                newTask.startDepth_m = task.startDepth_m
                newTask.endDepth_m = task.endDepth_m
            }

            // Calculate start time based on the previous task's end time
            newTask.startTime = lastEndTime

            // Update lastEndTime for the next iteration
            lastEndTime = newTask.endTime

            modelContext.insert(newTask)

            // Copy vendor assignments
            for assignment in task.assignments {
                guard let vendor = assignment.vendor else { continue }
                let newAssignment = TaskVendorAssignment(
                    vendor: vendor,
                    callReminderMinutesBefore: assignment.callReminderMinutesBefore
                )
                newAssignment.notes = assignment.notes
                newAssignment.task = newTask
                modelContext.insert(newAssignment)
            }

            nextOrder += 1
        }

        try? modelContext.save()
        onComplete()
        dismiss()
    }
}

// MARK: - Quick Duration Picker

struct QuickDurationPicker: View {
    let currentMinutes: Double
    var onChange: (Double) -> Void

    @State private var customHours: Double = 1.0

    private let presets: [(String, Double)] = [
        ("30m", 30),
        ("1h", 60),
        ("2h", 120),
        ("4h", 240),
        ("6h", 360),
        ("8h", 480),
        ("12h", 720),
        ("24h", 1440)
    ]

    var body: some View {
        VStack(spacing: 12) {
            Text("Set Duration")
                .font(.headline)
                .padding(.top, 8)

            // Quick presets in a grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(presets, id: \.1) { label, minutes in
                    Button {
                        onChange(minutes)
                    } label: {
                        Text(label)
                            .font(.callout)
                            .fontWeight(currentMinutes == minutes ? .bold : .regular)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(currentMinutes == minutes ? Color.accentColor : Color.secondary.opacity(0.2))
                            .foregroundStyle(currentMinutes == minutes ? .white : .primary)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Custom duration with stepper
            HStack {
                Text("Custom:")
                    .foregroundStyle(.secondary)

                Stepper(value: $customHours, in: 0.25...48, step: 0.25) {
                    Text(formatHours(customHours))
                        .frame(width: 60, alignment: .trailing)
                        .fontWeight(.medium)
                }

                Button("Apply") {
                    onChange(customHours * 60)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            // Current value display
            Text("Current: \(formatMinutes(currentMinutes))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
        .padding()
        .frame(width: 280)
        .onAppear {
            customHours = currentMinutes / 60.0
        }
    }

    private func formatHours(_ hours: Double) -> String {
        if hours < 1 {
            return "\(Int(hours * 60))m"
        } else if hours == Double(Int(hours)) {
            return "\(Int(hours))h"
        } else {
            let h = Int(hours)
            let m = Int((hours - Double(h)) * 60)
            return "\(h)h \(m)m"
        }
    }

    private func formatMinutes(_ minutes: Double) -> String {
        let totalMinutes = Int(minutes)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 && m > 0 {
            return "\(h)h \(m)m"
        } else if h > 0 {
            return "\(h)h"
        }
        return "\(m)m"
    }
}

#Preview {
    LookAheadListView()
        .modelContainer(for: [LookAheadSchedule.self, LookAheadTask.self, JobCode.self, Vendor.self])
}
