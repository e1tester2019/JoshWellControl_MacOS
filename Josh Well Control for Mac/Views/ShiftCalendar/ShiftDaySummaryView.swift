//
//  ShiftDaySummaryView.swift
//  Josh Well Control for Mac
//
//  Sidebar view showing summary of selected day's shift, work, and tasks.
//

import SwiftUI
import SwiftData

struct ShiftDaySummaryView: View {
    @Environment(\.modelContext) private var modelContext

    let selectedDate: Date
    var onEditShift: () -> Void
    var onSelectTask: ((LookAheadTask) -> Void)?

    @Query private var shiftEntries: [ShiftEntry]
    @Query private var lookAheadTasks: [LookAheadTask]
    @Query private var handoverNotes: [HandoverNote]
    @Query private var wellTasks: [WellTask]
    @Query private var workDays: [WorkDay]
    @Query private var expenses: [Expense]
    @Query private var mileageLogs: [MileageLog]

    // State for note/task editors using item-based sheets to avoid race conditions
    @State private var noteEditorMode: NoteEditorMode?
    @State private var taskEditorMode: TaskEditorMode?
    @State private var showingHandoverSummary = false

    private enum NoteEditorMode: Identifiable {
        case new(Date)
        case edit(HandoverNote)

        var id: String {
            switch self {
            case .new(let date): return "new-\(date.timeIntervalSince1970)"
            case .edit(let note): return note.id.uuidString
            }
        }
    }

    private enum TaskEditorMode: Identifiable {
        case new(Date)
        case edit(WellTask)

        var id: String {
            switch self {
            case .new(let date): return "new-\(date.timeIntervalSince1970)"
            case .edit(let task): return task.id.uuidString
            }
        }
    }

    private let calendar = Calendar.current

    init(selectedDate: Date, onEditShift: @escaping () -> Void, onSelectTask: ((LookAheadTask) -> Void)? = nil) {
        self.selectedDate = selectedDate
        self.onEditShift = onEditShift
        self.onSelectTask = onSelectTask

        // Initialize queries - filtering will be done in computed properties
        _shiftEntries = Query(sort: \ShiftEntry.date)
        _lookAheadTasks = Query(sort: \LookAheadTask.startTime)
        _handoverNotes = Query(sort: \HandoverNote.createdAt, order: .reverse)
        _wellTasks = Query(sort: \WellTask.dueDate)
        _workDays = Query(sort: \WorkDay.startDate)
        _expenses = Query(sort: \Expense.date, order: .reverse)
        _mileageLogs = Query(sort: \MileageLog.date, order: .reverse)
    }

    // MARK: - Filtered Data

    private var shiftEntry: ShiftEntry? {
        let dayStart = calendar.startOfDay(for: selectedDate)
        return shiftEntries.first { calendar.isDate($0.date, inSameDayAs: dayStart) }
    }

    private var currentShiftType: ShiftType {
        shiftEntry?.shiftType ?? ShiftRotationSettings.shared.expectedShiftType(for: selectedDate)
    }

    private var lookAheadTasksForDay: [LookAheadTask] {
        let dayStart = calendar.startOfDay(for: selectedDate)
        let dayEnd = dayStart.addingTimeInterval(24 * 60 * 60)

        return lookAheadTasks.filter { task in
            task.status != .cancelled &&
            task.startTime < dayEnd &&
            task.endTime > dayStart
        }.sorted { $0.startTime < $1.startTime }
    }

    private var notesForDay: [HandoverNote] {
        handoverNotes.filter { note in
            calendar.isDate(note.createdAt, inSameDayAs: selectedDate)
        }
    }

    private var tasksForDay: [WellTask] {
        wellTasks.filter { task in
            if let dueDate = task.dueDate, calendar.isDate(dueDate, inSameDayAs: selectedDate) {
                return true
            }
            if calendar.isDate(task.createdAt, inSameDayAs: selectedDate) {
                return true
            }
            return false
        }
    }

    private var workDaysForDay: [WorkDay] {
        workDays.filter { workDay in
            let start = calendar.startOfDay(for: workDay.startDate)
            let end = calendar.startOfDay(for: workDay.endDate)
            let selected = calendar.startOfDay(for: selectedDate)
            return selected >= start && selected <= end
        }
    }

    private var expensesForDay: [Expense] {
        expenses.filter { expense in
            calendar.isDate(expense.date, inSameDayAs: selectedDate)
        }
    }

    private var mileageForDay: [MileageLog] {
        mileageLogs.filter { log in
            calendar.isDate(log.date, inSameDayAs: selectedDate)
        }
    }

    private var totalExpensesForDay: Double {
        expensesForDay.reduce(0) { $0 + $1.totalAmount }
    }

    private var totalMileageForDay: Double {
        mileageForDay.reduce(0) { $0 + $1.effectiveDistance }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Date and Shift Header
                shiftHeaderSection

                Divider()

                // LookAhead Section
                lookAheadSection

                Divider()

                // Handover Notes Section
                handoverNotesSection

                Divider()

                // Tasks Section
                tasksSection

                Divider()

                // Work Logged Section
                workLoggedSection

                Divider()

                // Expenses Section
                expensesSection
            }
            .padding()
        }
        #if os(macOS)
        .background(Color(NSColor.controlBackgroundColor))
        #endif
        .sheet(item: $noteEditorMode) { mode in
            switch mode {
            case .new(let date):
                NoteEditorView(forDate: date)
            case .edit(let note):
                NoteEditorView(note: note)
            }
        }
        .sheet(item: $taskEditorMode) { mode in
            switch mode {
            case .new(let date):
                TaskEditorView(forDate: date)
            case .edit(let task):
                TaskEditorView(task: task)
            }
        }
        .sheet(isPresented: $showingHandoverSummary) {
            HandoverSummaryView(selectedDate: selectedDate)
        }
    }

    // MARK: - Shift Header Section

    private var shiftHeaderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Date
            Text(dateString)
                .font(.title2)
                .fontWeight(.semibold)

            // Shift Type Badge
            HStack {
                Label {
                    Text("\(currentShiftType.displayName) Shift")
                        .fontWeight(.medium)
                } icon: {
                    Image(systemName: currentShiftType.icon)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(shiftBadgeColor)
                .foregroundColor(.white)
                .cornerRadius(8)

                Spacer()

                Button {
                    showingHandoverSummary = true
                } label: {
                    Label("Summary", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Edit", action: onEditShift)
                    .buttonStyle(.bordered)
            }

            // Well Assignment (if any)
            if let well = shiftEntry?.well {
                HStack {
                    Image(systemName: "oilcan.fill")
                        .foregroundColor(.secondary)
                    Text(well.name)
                        .foregroundColor(.secondary)
                }
            }

            // Client Assignment (if any)
            if let client = shiftEntry?.client {
                HStack {
                    Image(systemName: "building.2")
                        .foregroundColor(.secondary)
                    Text(client.companyName)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - LookAhead Section

    private var lookAheadSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "list.bullet.clipboard")
                    .foregroundColor(.blue)
                Text("LookAhead")
                    .font(.headline)
                Spacer()
                Text("\(lookAheadTasksForDay.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: addNewTask) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }

            if lookAheadTasksForDay.isEmpty {
                HStack {
                    Text("No scheduled items")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                    Spacer()
                    Button("Add Task") {
                        addNewTask()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                ForEach(lookAheadTasksForDay) { task in
                    Button(action: { onSelectTask?(task) }) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(statusColor(for: task.status))
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.name)
                                    .lineLimit(1)
                                    .foregroundColor(.primary)

                                HStack(spacing: 6) {
                                    Text(task.timeRangeFormatted)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)

                                    if let jobCode = task.jobCode {
                                        Text(jobCode.code)
                                            .font(.caption2)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.secondary.opacity(0.2))
                                            .cornerRadius(3)
                                    }

                                    Text(task.status.rawValue)
                                        .font(.caption2)
                                        .foregroundColor(statusColor(for: task.status))
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                        .background(statusColor(for: task.status).opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func statusColor(for status: LookAheadTaskStatus) -> Color {
        switch status {
        case .scheduled: return .blue
        case .inProgress: return .orange
        case .completed: return .green
        case .delayed: return .red
        case .cancelled: return .gray
        }
    }

    // MARK: - Handover Notes Section

    private var handoverNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "note.text")
                    .foregroundColor(.orange)
                Text("Handover Notes")
                    .font(.headline)
                Spacer()
                Text("\(notesForDay.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: { addNewNote() }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
            }

            if notesForDay.isEmpty {
                HStack {
                    Text("No notes for this day")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()

                    Spacer()

                    Button(action: { addNewNote() }) {
                        Label("Add Note", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ForEach(notesForDay) { note in
                    Button(action: { editNote(note) }) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Circle()
                                    .fill(notePriorityColor(note))
                                    .frame(width: 6, height: 6)
                                Text(note.title)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if !note.content.isEmpty {
                                MarkdownListView(content: note.content)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Tasks Section

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let completedCount = tasksForDay.filter { $0.status == .completed }.count
            let pendingCount = tasksForDay.count - completedCount

            HStack {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.green)
                Text("Tasks")
                    .font(.headline)
                Spacer()
                if !tasksForDay.isEmpty {
                    Text("\(completedCount) done, \(pendingCount) pending")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button(action: { addNewWellTask() }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
            }

            if tasksForDay.isEmpty {
                HStack {
                    Text("No tasks for this day")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()

                    Spacer()

                    Button(action: { addNewWellTask() }) {
                        Label("Add Task", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ForEach(tasksForDay) { task in
                    Button(action: { editWellTask(task) }) {
                        HStack {
                            Button(action: { toggleTaskStatus(task) }) {
                                Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(task.status == .completed ? .green : .gray)
                            }
                            .buttonStyle(.plain)

                            Text(task.title)
                                .strikethrough(task.status == .completed)
                                .lineLimit(1)
                                .foregroundColor(.primary)
                            Spacer()
                            if task.isOverdue {
                                Text("Overdue")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Work Logged Section

    private var workLoggedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "briefcase.fill")
                    .foregroundColor(.purple)
                Text("Work Logged")
                    .font(.headline)
                Spacer()
            }

            if workDaysForDay.isEmpty {
                if currentShiftType != .off {
                    HStack {
                        Text("No work logged yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()

                        Spacer()

                        if shiftEntry == nil {
                            Text("Edit shift to log work")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                } else {
                    Text("Day off")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            } else {
                ForEach(workDaysForDay) { workDay in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(workDay.dayCount) day\(workDay.dayCount == 1 ? "" : "s")")
                                .fontWeight(.medium)
                            Spacer()
                            Text(formattedCurrency(workDay.totalEarnings))
                                .fontWeight(.semibold)
                        }

                        if let client = workDay.client {
                            Text(client.companyName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let well = workDay.well {
                            Text(well.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if workDay.totalMileage > 0 {
                            Text("\(Int(workDay.totalMileage)) km")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Invoice status
                        HStack(spacing: 4) {
                            if workDay.isInvoiced {
                                Label("Invoiced", systemImage: "doc.text.fill")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                            if workDay.isPaid {
                                Label("Paid", systemImage: "checkmark.seal.fill")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Expenses Section

    private var expensesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "creditcard.fill")
                    .foregroundColor(.red)
                Text("Expenses")
                    .font(.headline)
                Spacer()
                if totalExpensesForDay > 0 {
                    Text(formattedCurrency(totalExpensesForDay))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }
            }

            if expensesForDay.isEmpty && mileageForDay.isEmpty {
                Text("No expenses recorded")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                // Expense items
                ForEach(expensesForDay) { expense in
                    HStack(spacing: 8) {
                        Image(systemName: expense.category.icon)
                            .foregroundColor(.secondary)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(expense.vendor.isEmpty ? expense.category.rawValue : expense.vendor)
                                .font(.callout)
                                .lineLimit(1)

                            if !expense.expenseDescription.isEmpty {
                                Text(expense.expenseDescription)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        Text(formattedCurrency(expense.totalAmount))
                            .font(.callout)
                            .fontWeight(.medium)
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(6)
                }

                // Mileage items
                ForEach(mileageForDay) { mileage in
                    HStack(spacing: 8) {
                        Image(systemName: "car.fill")
                            .foregroundColor(.secondary)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(mileage.locationString.isEmpty ? "Mileage" : mileage.locationString)
                                .font(.callout)
                                .lineLimit(1)

                            Text("\(Int(mileage.effectiveDistance)) km")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // CRA deduction estimate
                        let deduction = MileageSummary.calculateDeduction(totalKm: mileage.effectiveDistance)
                        Text(formattedCurrency(deduction))
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                    .padding(8)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(6)
                }

                // Summary if both expenses and mileage exist
                if !expensesForDay.isEmpty && !mileageForDay.isEmpty {
                    Divider()
                    HStack {
                        Text("Net")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        let mileageDeduction = mileageForDay.reduce(0) { $0 + MileageSummary.calculateDeduction(totalKm: $1.effectiveDistance) }
                        Text("\(formattedCurrency(totalExpensesForDay)) spent, \(formattedCurrency(mileageDeduction)) mileage")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: selectedDate)
    }

    private var shiftBadgeColor: Color {
        switch currentShiftType {
        case .day: return .blue
        case .night: return .purple
        case .off: return .gray
        }
    }

    private func formattedCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }

    // MARK: - Actions

    private func addNewTask() {
        // Calculate a sensible start time for the new task
        let newStartTime: Date
        if let lastTask = lookAheadTasksForDay.last {
            // Start after the last task
            newStartTime = lastTask.endTime
        } else {
            // Default to 8:00 AM on the selected day, or current time if today
            let dayStart = calendar.startOfDay(for: selectedDate)
            let defaultStart = dayStart.addingTimeInterval(8 * 60 * 60) // 8:00 AM
            if calendar.isDateInToday(selectedDate) && Date() > defaultStart {
                // If today and past 8 AM, start at next 15-minute interval
                let now = Date()
                let minutes = calendar.component(.minute, from: now)
                let roundedMinutes = ((minutes / 15) + 1) * 15
                newStartTime = calendar.date(bySettingHour: calendar.component(.hour, from: now),
                                             minute: roundedMinutes % 60,
                                             second: 0,
                                             of: selectedDate) ?? now
            } else {
                newStartTime = defaultStart
            }
        }

        // Create a new task with default values
        let newTask = LookAheadTask(
            name: "New Task",
            estimatedDuration_min: 60
        )
        newTask.startTime = newStartTime

        // Assign to the current well if one is set on the shift
        if let well = shiftEntry?.well {
            newTask.well = well
        }

        modelContext.insert(newTask)

        // Select the new task for editing
        onSelectTask?(newTask)
    }

    private func notePriorityColor(_ note: HandoverNote) -> Color {
        switch note.priority {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .green
        }
    }

    private func addNewNote() {
        noteEditorMode = .new(selectedDate)
    }

    private func editNote(_ note: HandoverNote) {
        noteEditorMode = .edit(note)
    }

    private func addNewWellTask() {
        taskEditorMode = .new(selectedDate)
    }

    private func editWellTask(_ task: WellTask) {
        taskEditorMode = .edit(task)
    }

    private func toggleTaskStatus(_ task: WellTask) {
        if task.status == .completed {
            task.status = .pending
        } else {
            task.status = .completed
        }
        try? modelContext.save()
    }
}
