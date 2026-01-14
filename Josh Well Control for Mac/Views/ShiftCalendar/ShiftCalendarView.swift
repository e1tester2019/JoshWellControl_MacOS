//
//  ShiftCalendarView.swift
//  Josh Well Control for Mac
//
//  Main calendar view for shift tracking on macOS with spanning LookAhead tasks.
//  Supports month, week, and day view modes.
//

import SwiftUI
import SwiftData

#if os(macOS)

// MARK: - Calendar View Mode

enum CalendarViewMode: String, CaseIterable {
    case month = "Month"
    case week = "Week"
    case day = "Day"

    var icon: String {
        switch self {
        case .month: return "calendar"
        case .week: return "calendar.day.timeline.left"
        case .day: return "sun.max"
        }
    }
}

// MARK: - Main Calendar View

struct ShiftCalendarView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ShiftEntry.date) private var allShifts: [ShiftEntry]
    @Query(sort: \Client.companyName) private var clients: [Client]
    @Query(filter: #Predicate<Well> { !$0.isArchived }, sort: \Well.name) private var wells: [Well]
    @Query(sort: \LookAheadTask.startTime) private var lookAheadTasks: [LookAheadTask]

    @State private var selectedDate: Date = Date()
    @State private var displayedMonth: Date = Date()
    @State private var viewMode: CalendarViewMode = .month
    @State private var showingSettings = false
    @State private var showingEditor = false
    @State private var selectedTask: LookAheadTask?

    private let calendar = Calendar.current

    var body: some View {
        HSplitView {
            // Calendar Grid
            VStack(spacing: 0) {
                // Header with navigation and view mode
                calendarHeader

                Divider()

                // Calendar content based on view mode
                switch viewMode {
                case .month:
                    MonthCalendarView(
                        displayedMonth: displayedMonth,
                        selectedDate: $selectedDate,
                        selectedTask: $selectedTask,
                        showingEditor: $showingEditor,
                        lookAheadTasks: lookAheadTasks,
                        shiftTypeForDate: shiftType(for:),
                        hasWorkDayForDate: hasWorkDay(for:)
                    )
                case .week:
                    WeekCalendarView(
                        selectedDate: $selectedDate,
                        selectedTask: $selectedTask,
                        showingEditor: $showingEditor,
                        lookAheadTasks: lookAheadTasks,
                        shiftTypeForDate: shiftType(for:),
                        hasWorkDayForDate: hasWorkDay(for:)
                    )
                case .day:
                    DayCalendarView(
                        selectedDate: $selectedDate,
                        selectedTask: $selectedTask,
                        lookAheadTasks: lookAheadTasks,
                        shiftTypeForDate: shiftType(for:)
                    )
                }
            }
            .frame(minWidth: 500)

            // Sidebar - show task editor or day summary
            if let task = selectedTask {
                LookAheadTaskSidebarView(
                    task: task,
                    onClose: { selectedTask = nil },
                    onTimingChanged: { changedTask, oldEndTime in
                        adjustTaskChainFromSidebar(task: changedTask, oldEndTime: oldEndTime)
                    }
                )
                .frame(minWidth: 220, idealWidth: 280, maxWidth: 400)
            } else {
                ShiftDaySummaryView(
                    selectedDate: selectedDate,
                    onEditShift: { showingEditor = true },
                    onSelectTask: { task in selectedTask = task }
                )
                .frame(minWidth: 220, idealWidth: 280, maxWidth: 400)
            }
        }
        .sheet(isPresented: $showingSettings) {
            ShiftRotationSetupView()
        }
        .sheet(isPresented: $showingEditor) {
            ShiftEditorView(date: selectedDate)
        }
        .onAppear {
            Task {
                await ShiftNotificationService.shared.scheduleNextReminder(context: modelContext)
            }
        }
    }

    // MARK: - Calendar Header

    private var calendarHeader: some View {
        HStack {
            // Previous button
            Button(action: navigatePrevious) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)

            // Date title
            Text(headerTitle)
                .font(.title2)
                .fontWeight(.semibold)
                .frame(minWidth: 200)

            // Next button
            Button(action: navigateNext) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)

            Spacer()

            // View mode picker
            Picker("View", selection: $viewMode) {
                ForEach(CalendarViewMode.allCases, id: \.self) { mode in
                    Label(mode.rawValue, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Spacer().frame(width: 16)

            // Today button
            Button(action: goToToday) {
                Text("Today")
            }
            .buttonStyle(.bordered)

            // Settings
            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    private var headerTitle: String {
        let formatter = DateFormatter()
        switch viewMode {
        case .month:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: displayedMonth)
        case .week:
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)) ?? selectedDate
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? selectedDate
            formatter.dateFormat = "MMM d"
            let startStr = formatter.string(from: weekStart)
            let endStr = formatter.string(from: weekEnd)
            formatter.dateFormat = "yyyy"
            let yearStr = formatter.string(from: weekEnd)
            return "\(startStr) - \(endStr), \(yearStr)"
        case .day:
            formatter.dateFormat = "EEEE, MMMM d, yyyy"
            return formatter.string(from: selectedDate)
        }
    }

    private func navigatePrevious() {
        switch viewMode {
        case .month:
            if let newDate = calendar.date(byAdding: .month, value: -1, to: displayedMonth) {
                displayedMonth = newDate
            }
        case .week:
            if let newDate = calendar.date(byAdding: .weekOfYear, value: -1, to: selectedDate) {
                selectedDate = newDate
            }
        case .day:
            if let newDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) {
                selectedDate = newDate
            }
        }
    }

    private func navigateNext() {
        switch viewMode {
        case .month:
            if let newDate = calendar.date(byAdding: .month, value: 1, to: displayedMonth) {
                displayedMonth = newDate
            }
        case .week:
            if let newDate = calendar.date(byAdding: .weekOfYear, value: 1, to: selectedDate) {
                selectedDate = newDate
            }
        case .day:
            if let newDate = calendar.date(byAdding: .day, value: 1, to: selectedDate) {
                selectedDate = newDate
            }
        }
    }

    private func goToToday() {
        displayedMonth = Date()
        selectedDate = Date()
    }

    // MARK: - Shift Helpers

    private func shiftType(for date: Date) -> ShiftType {
        let dayStart = calendar.startOfDay(for: date)
        if let entry = allShifts.first(where: { calendar.isDate($0.date, inSameDayAs: dayStart) }) {
            return entry.shiftType
        }
        return ShiftRotationSettings.shared.expectedShiftType(for: date)
    }

    private func hasWorkDay(for date: Date) -> Bool {
        let dayStart = calendar.startOfDay(for: date)
        if let entry = allShifts.first(where: { calendar.isDate($0.date, inSameDayAs: dayStart) }) {
            return entry.workDay != nil
        }
        return false
    }

    /// Adjust task chain when timing is changed from the sidebar editor
    private func adjustTaskChainFromSidebar(task: LookAheadTask, oldEndTime: Date) {
        let newEndTime = task.endTime

        // Calculate how much the end time shifted
        let delta = newEndTime.timeIntervalSince(oldEndTime)

        guard abs(delta) > 1 else { return }  // Ignore tiny changes

        // Find and shift all tasks that started at or after the old end time
        let sortedTasks = lookAheadTasks
            .filter { $0.id != task.id && $0.status != .cancelled }
            .sorted { $0.startTime < $1.startTime }

        for otherTask in sortedTasks {
            // If this task starts at or after where the changed task ended
            if otherTask.startTime >= oldEndTime || otherTask.startTime >= newEndTime - delta {
                otherTask.startTime = otherTask.startTime.addingTimeInterval(delta)
            }
        }
    }
}

// MARK: - Month Calendar View

private struct MonthCalendarView: View {
    let displayedMonth: Date
    @Binding var selectedDate: Date
    @Binding var selectedTask: LookAheadTask?
    @Binding var showingEditor: Bool
    let lookAheadTasks: [LookAheadTask]
    let shiftTypeForDate: (Date) -> ShiftType
    let hasWorkDayForDate: (Date) -> Bool

    private let calendar = Calendar.current
    private let daysOfWeek = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        VStack(spacing: 0) {
            // Days of week header
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 0) {
                ForEach(daysOfWeek, id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))

            // Calendar weeks
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(weeksInMonth().enumerated()), id: \.offset) { _, week in
                        MonthWeekRow(
                            week: week,
                            selectedDate: $selectedDate,
                            selectedTask: $selectedTask,
                            showingEditor: $showingEditor,
                            tasks: tasksForWeek(week),
                            shiftTypeForDate: shiftTypeForDate,
                            hasWorkDayForDate: hasWorkDayForDate
                        )
                    }
                }
            }
        }
    }

    private func weeksInMonth() -> [[Date?]] {
        var weeks: [[Date?]] = []
        var currentWeek: [Date?] = []

        let components = calendar.dateComponents([.year, .month], from: displayedMonth)
        guard let firstDayOfMonth = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: displayedMonth) else {
            return weeks
        }

        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        for _ in 1..<firstWeekday {
            currentWeek.append(nil)
        }

        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                currentWeek.append(date)
                if currentWeek.count == 7 {
                    weeks.append(currentWeek)
                    currentWeek = []
                }
            }
        }

        if !currentWeek.isEmpty {
            while currentWeek.count < 7 {
                currentWeek.append(nil)
            }
            weeks.append(currentWeek)
        }

        return weeks
    }

    private func tasksForWeek(_ week: [Date?]) -> [(task: LookAheadTask, startCol: Int, endCol: Int)] {
        let validDates = week.compactMap { $0 }
        guard let weekStart = validDates.first,
              let weekEnd = validDates.last else {
            return []
        }

        let weekStartDay = calendar.startOfDay(for: weekStart)
        let weekEndDay = calendar.startOfDay(for: weekEnd).addingTimeInterval(24 * 60 * 60 - 1)

        var result: [(task: LookAheadTask, startCol: Int, endCol: Int)] = []

        for task in lookAheadTasks {
            guard task.status != .cancelled else { continue }

            let taskStart = task.startTime
            let taskEnd = task.endTime

            if taskStart <= weekEndDay && taskEnd >= weekStartDay {
                var startCol = 0
                var endCol = 6

                for (col, date) in week.enumerated() {
                    if let date = date {
                        let dayEnd = calendar.startOfDay(for: date).addingTimeInterval(24 * 60 * 60 - 1)
                        if taskStart <= dayEnd {
                            startCol = col
                            break
                        }
                    }
                }

                for (col, date) in week.enumerated().reversed() {
                    if let date = date {
                        let dayStart = calendar.startOfDay(for: date)
                        if taskEnd >= dayStart {
                            endCol = col
                            break
                        }
                    }
                }

                while startCol < week.count && week[startCol] == nil {
                    startCol += 1
                }
                while endCol >= 0 && week[endCol] == nil {
                    endCol -= 1
                }

                if startCol <= endCol {
                    result.append((task: task, startCol: startCol, endCol: endCol))
                }
            }
        }

        return result
    }
}

// MARK: - Month Week Row

private struct MonthWeekRow: View {
    let week: [Date?]
    @Binding var selectedDate: Date
    @Binding var selectedTask: LookAheadTask?
    @Binding var showingEditor: Bool
    let tasks: [(task: LookAheadTask, startCol: Int, endCol: Int)]
    let shiftTypeForDate: (Date) -> ShiftType
    let hasWorkDayForDate: (Date) -> Bool

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            if !tasks.isEmpty {
                VStack(spacing: 2) {
                    ForEach(Array(tasks.enumerated()), id: \.element.task.id) { _, item in
                        taskBar(for: item)
                            .onTapGesture {
                                selectedTask = item.task
                            }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.top, 2)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 1) {
                ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                    if let date = date {
                        MonthDayCell(
                            date: date,
                            shiftType: shiftTypeForDate(date),
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            isToday: calendar.isDateInToday(date),
                            hasWorkDay: hasWorkDayForDate(date)
                        )
                        .onTapGesture { selectedDate = date }
                        .onTapGesture(count: 2) {
                            selectedDate = date
                            showingEditor = true
                        }
                    } else {
                        Color.clear.frame(height: 60)
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private func taskBar(for item: (task: LookAheadTask, startCol: Int, endCol: Int)) -> some View {
        GeometryReader { geometry in
            let cellWidth = geometry.size.width / 7
            let startX = CGFloat(item.startCol) * cellWidth
            let width = CGFloat(item.endCol - item.startCol + 1) * cellWidth - 4

            HStack(spacing: 4) {
                Circle()
                    .fill(taskColor(for: item.task))
                    .frame(width: 6, height: 6)
                Text(item.task.name)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                if let jobCode = item.task.jobCode {
                    Text(jobCode.code)
                        .font(.system(size: 8, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(jobCode.color.opacity(0.3))
                        .cornerRadius(3)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(width: width, height: 18)
            .background(taskColor(for: item.task).opacity(0.2))
            .cornerRadius(4)
            .offset(x: startX + 2)
        }
        .frame(height: 18)
    }

    private func taskColor(for task: LookAheadTask) -> Color {
        // Use job code color if available, otherwise fall back to status color
        if let jobCode = task.jobCode {
            return jobCode.color
        }
        return statusColor(for: task.status)
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
}

// MARK: - Month Day Cell

private struct MonthDayCell: View {
    let date: Date
    let shiftType: ShiftType
    let isSelected: Bool
    let isToday: Bool
    let hasWorkDay: Bool

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 4) {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 14, weight: isToday ? .bold : .regular))
                .foregroundColor(isToday ? .white : .primary)
                .frame(width: 24, height: 24)
                .background(isToday ? Color.accentColor : Color.clear)
                .clipShape(Circle())

            HStack(spacing: 2) {
                Text(shiftType.displayName.prefix(1))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                if hasWorkDay {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(shiftBadgeColor)
            .cornerRadius(4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }

    private var shiftBadgeColor: Color {
        switch shiftType {
        case .day: return Color.blue.opacity(0.8)
        case .night: return Color.purple.opacity(0.8)
        case .off: return Color.gray.opacity(0.5)
        }
    }
}

// MARK: - Week Calendar View

private struct WeekCalendarView: View {
    @Binding var selectedDate: Date
    @Binding var selectedTask: LookAheadTask?
    @Binding var showingEditor: Bool
    let lookAheadTasks: [LookAheadTask]
    let shiftTypeForDate: (Date) -> ShiftType
    let hasWorkDayForDate: (Date) -> Bool

    private let calendar = Calendar.current
    private let hourHeight: CGFloat = 60

    var body: some View {
        let weekDays = daysOfWeek()

        VStack(spacing: 0) {
            // Week header
            HStack(spacing: 0) {
                Text("")
                    .frame(width: 60)
                ForEach(weekDays, id: \.self) { day in
                    weekDayHeader(for: day)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))

            // Time grid
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    // Time labels
                    VStack(spacing: 0) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(formatHour(hour))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 60, height: hourHeight, alignment: .topTrailing)
                                .padding(.trailing, 8)
                        }
                    }

                    // Day columns
                    ForEach(weekDays, id: \.self) { day in
                        weekDayColumn(for: day, weekDays: weekDays)
                    }
                }
            }
        }
    }

    private func daysOfWeek() -> [Date] {
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)) ?? selectedDate
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private func weekDayHeader(for date: Date) -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        let dayName = formatter.string(from: date)
        let dayNum = calendar.component(.day, from: date)
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)

        return VStack(spacing: 4) {
            Text(dayName)
                .font(.caption)
                .foregroundColor(.secondary)

            Text("\(dayNum)")
                .font(.system(size: 16, weight: isToday ? .bold : .regular))
                .foregroundColor(isToday ? .white : .primary)
                .frame(width: 28, height: 28)
                .background(isToday ? Color.accentColor : Color.clear)
                .clipShape(Circle())

            // Shift badge
            Text(shiftTypeForDate(date).displayName.prefix(1))
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(shiftColor(for: shiftTypeForDate(date)))
                .cornerRadius(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .onTapGesture { selectedDate = date }
    }

    private func weekDayColumn(for date: Date, weekDays: [Date]) -> some View {
        let dayTasks = tasksForDay(date)
        let isLastDayOfWeek = calendar.isDate(date, inSameDayAs: weekDays.last ?? date)

        return ZStack(alignment: .topLeading) {
            // Hour lines
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: hourHeight)
                        .overlay(alignment: .top) {
                            Divider()
                        }
                }
            }

            // Task blocks
            ForEach(dayTasks, id: \.id) { task in
                // Only show resize handle on the day where the task ends (or last day of week if it extends beyond)
                let taskEndsToday = calendar.isDate(task.endTime, inSameDayAs: date)
                let showResizeHandle = taskEndsToday || (task.endTime > (weekDays.last ?? date) && isLastDayOfWeek)

                ResizableWeekTaskBlock(
                    task: task,
                    displayDate: date,
                    hourHeight: hourHeight,
                    showResizeHandle: showResizeHandle,
                    onTap: { selectedTask = task },
                    onResizeEnded: { newDuration in
                        adjustTaskChain(task: task, newDuration: newDuration)
                    }
                )
            }
        }
        .frame(maxWidth: .infinity)
        .onTapGesture {
            selectedDate = date
        }
        .onTapGesture(count: 2) {
            selectedDate = date
            showingEditor = true
        }
    }

    private func tasksForDay(_ date: Date) -> [LookAheadTask] {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = dayStart.addingTimeInterval(24 * 60 * 60)

        return lookAheadTasks.filter { task in
            task.status != .cancelled &&
            task.startTime < dayEnd &&
            task.endTime > dayStart
        }
    }

    /// Adjust task duration and shift all subsequent tasks to maintain the chain
    private func adjustTaskChain(task: LookAheadTask, newDuration: Double) {
        let oldEndTime = task.endTime
        task.estimatedDuration_min = newDuration
        let newEndTime = task.endTime

        // Calculate how much the end time shifted
        let delta = newEndTime.timeIntervalSince(oldEndTime)

        // Find and shift all tasks that started at or after the old end time
        // Sort by start time to process in order
        let sortedTasks = lookAheadTasks
            .filter { $0.id != task.id && $0.status != .cancelled }
            .sorted { $0.startTime < $1.startTime }

        for otherTask in sortedTasks {
            // If this task starts at or after where the resized task ended
            if otherTask.startTime >= oldEndTime || otherTask.startTime >= newEndTime - delta {
                otherTask.startTime = otherTask.startTime.addingTimeInterval(delta)
            }
        }
    }

    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        var components = DateComponents()
        components.hour = hour
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(hour):00"
    }

    private func shiftColor(for type: ShiftType) -> Color {
        switch type {
        case .day: return Color.blue.opacity(0.8)
        case .night: return Color.purple.opacity(0.8)
        case .off: return Color.gray.opacity(0.5)
        }
    }

    private func taskColor(for task: LookAheadTask) -> Color {
        if let jobCode = task.jobCode {
            return jobCode.color
        }
        return statusColor(for: task.status)
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
}

// MARK: - Day Calendar View

private struct DayCalendarView: View {
    @Binding var selectedDate: Date
    @Binding var selectedTask: LookAheadTask?
    let lookAheadTasks: [LookAheadTask]
    let shiftTypeForDate: (Date) -> ShiftType

    private let calendar = Calendar.current
    private let hourHeight: CGFloat = 60

    var body: some View {
        let dayTasks = tasksForDay()

        VStack(spacing: 0) {
            // Day header
            HStack {
                VStack(alignment: .leading) {
                    Text(shiftTypeForDate(selectedDate).displayName + " Shift")
                        .font(.headline)
                        .foregroundColor(shiftColor(for: shiftTypeForDate(selectedDate)))
                    Text("\(dayTasks.count) task\(dayTasks.count == 1 ? "" : "s") scheduled")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            // Time grid
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    // Time labels
                    VStack(spacing: 0) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(formatHour(hour))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 60, height: hourHeight, alignment: .topTrailing)
                                .padding(.trailing, 8)
                        }
                    }

                    // Main column
                    ZStack(alignment: .topLeading) {
                        // Hour lines
                        VStack(spacing: 0) {
                            ForEach(0..<24, id: \.self) { _ in
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.1))
                                    .frame(height: hourHeight)
                                    .overlay(alignment: .top) {
                                        Divider()
                                    }
                            }
                        }

                        // Task blocks - now using local state management
                        ForEach(dayTasks, id: \.id) { task in
                            ResizableTaskBlock(
                                task: task,
                                selectedDate: selectedDate,
                                hourHeight: hourHeight,
                                onTap: { selectedTask = task },
                                onResizeEnded: { newDuration in
                                    adjustTaskChain(task: task, newDuration: newDuration)
                                }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func tasksForDay() -> [LookAheadTask] {
        let dayStart = calendar.startOfDay(for: selectedDate)
        let dayEnd = dayStart.addingTimeInterval(24 * 60 * 60)

        return lookAheadTasks.filter { task in
            task.status != .cancelled &&
            task.startTime < dayEnd &&
            task.endTime > dayStart
        }
    }

    /// Adjust task duration and shift all subsequent tasks to maintain the chain
    private func adjustTaskChain(task: LookAheadTask, newDuration: Double) {
        let oldEndTime = task.endTime
        task.estimatedDuration_min = newDuration
        let newEndTime = task.endTime

        // Calculate how much the end time shifted
        let delta = newEndTime.timeIntervalSince(oldEndTime)

        // Find and shift all tasks that started at or after the old end time
        // Sort by start time to process in order
        let sortedTasks = lookAheadTasks
            .filter { $0.id != task.id && $0.status != .cancelled }
            .sorted { $0.startTime < $1.startTime }

        for otherTask in sortedTasks {
            // If this task starts at or after where the resized task ended
            if otherTask.startTime >= oldEndTime || otherTask.startTime >= newEndTime - delta {
                otherTask.startTime = otherTask.startTime.addingTimeInterval(delta)
            }
        }
    }

    private func taskColor(for task: LookAheadTask) -> Color {
        if let jobCode = task.jobCode {
            return jobCode.color
        }
        return statusColor(for: task.status)
    }

    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        var components = DateComponents()
        components.hour = hour
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(hour):00"
    }

    private func shiftColor(for type: ShiftType) -> Color {
        switch type {
        case .day: return .blue
        case .night: return .purple
        case .off: return .gray
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
}

// MARK: - Resizable Week Task Block

private struct ResizableWeekTaskBlock: View {
    let task: LookAheadTask
    let displayDate: Date
    let hourHeight: CGFloat
    let showResizeHandle: Bool
    let onTap: () -> Void
    let onResizeEnded: (Double) -> Void

    // Use @GestureState for smooth gesture tracking - auto-resets when gesture ends
    @GestureState private var dragOffset: CGFloat = 0

    private let calendar = Calendar.current
    private let minimumHeight: CGFloat = 20
    private let minimumDuration: Double = 15
    private let snapInterval: Double = 15

    // Computed: whether we're currently dragging
    private var isDragging: Bool { dragOffset != 0 }

    var body: some View {
        let dayStart = calendar.startOfDay(for: displayDate)
        let dayEnd = dayStart.addingTimeInterval(24 * 60 * 60)

        let blockStart = max(task.startTime, dayStart)
        let blockEnd = min(task.endTime, dayEnd)

        let startMinutes = blockStart.timeIntervalSince(dayStart) / 60
        let baseDurationMinutes = blockEnd.timeIntervalSince(blockStart) / 60

        let topOffset = CGFloat(startMinutes) / 60 * hourHeight
        let baseHeight = max(minimumHeight, CGFloat(baseDurationMinutes) / 60 * hourHeight)
        let currentHeight = max(minimumHeight, baseHeight + dragOffset)

        // Calculate snapped duration for display (computed, not stored)
        let snappedDuration: Double = {
            let newHeight = max(minimumHeight, baseHeight + dragOffset)
            let rawDuration = calculateRawDuration(from: newHeight, baseHeight: baseHeight)
            return max(minimumDuration, round(rawDuration / snapInterval) * snapInterval)
        }()

        let color = taskColor(for: task)

        return VStack(spacing: 0) {
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(task.name)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(2)

                if !isDragging, let jobCode = task.jobCode {
                    Text(jobCode.code)
                        .font(.system(size: 8))
                        .foregroundColor(color)
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            // Resize handle
            if showResizeHandle {
                VStack(spacing: 2) {
                    if isDragging {
                        Text(formatEndTime(task.startTime.addingTimeInterval(snappedDuration * 60)))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    HStack(spacing: 1) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle()
                                .fill(Color.white.opacity(0.8))
                                .frame(width: 3, height: 3)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: isDragging ? 24 : 12)
                .background(isDragging ? color : color.opacity(0.15))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .updating($dragOffset) { value, state, _ in
                            // Only update the gesture state - no other state changes
                            state = value.translation.height
                        }
                        .onEnded { value in
                            let finalHeight = max(minimumHeight, baseHeight + value.translation.height)
                            let newDuration = calculateNewTotalDuration(from: finalHeight, baseHeight: baseHeight)
                            onResizeEnded(max(minimumDuration, newDuration))
                        }
                )
                #if os(macOS)
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeUpDown.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                #endif
            }
        }
        .frame(height: currentHeight)
        .background(color.opacity(isDragging ? 0.5 : 0.3))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isDragging ? color : color.opacity(0.5), lineWidth: isDragging ? 2 : 1)
        )
        .padding(.horizontal, 2)
        .offset(y: topOffset)
        .onTapGesture {
            onTap()
        }
    }

    private func calculateRawDuration(from newBlockHeight: CGFloat, baseHeight: CGFloat) -> Double {
        let dayStart = calendar.startOfDay(for: displayDate)
        let newBlockDuration = Double(newBlockHeight / hourHeight * 60)

        if task.startTime < dayStart {
            let priorDuration = dayStart.timeIntervalSince(task.startTime) / 60
            return priorDuration + newBlockDuration
        } else {
            return newBlockDuration
        }
    }

    private func calculateNewTotalDuration(from newBlockHeight: CGFloat, baseHeight: CGFloat) -> Double {
        let rawDuration = calculateRawDuration(from: newBlockHeight, baseHeight: baseHeight)
        return round(rawDuration / snapInterval) * snapInterval
    }

    private func formatEndTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        if !calendar.isDate(date, inSameDayAs: task.startTime) {
            formatter.dateFormat = "MMM d, h:mm a"
        } else {
            formatter.dateFormat = "h:mm a"
        }
        return "→ " + formatter.string(from: date)
    }

    private func taskColor(for task: LookAheadTask) -> Color {
        if let jobCode = task.jobCode {
            return jobCode.color
        }
        return statusColor(for: task.status)
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
}

// MARK: - Resizable Task Block (Day View)

private struct ResizableTaskBlock: View {
    let task: LookAheadTask
    let selectedDate: Date
    let hourHeight: CGFloat
    let onTap: () -> Void
    let onResizeEnded: (Double) -> Void

    // Use @GestureState for smooth gesture tracking - auto-resets when gesture ends
    @GestureState private var dragOffset: CGFloat = 0

    private let calendar = Calendar.current
    private let minimumHeight: CGFloat = 30
    private let minimumDuration: Double = 15
    private let snapInterval: Double = 15

    // Computed: whether we're currently dragging
    private var isDragging: Bool { dragOffset != 0 }

    var body: some View {
        let dayStart = calendar.startOfDay(for: selectedDate)
        let dayEnd = dayStart.addingTimeInterval(24 * 60 * 60)

        let blockStart = max(task.startTime, dayStart)
        let blockEnd = min(task.endTime, dayEnd)

        let startMinutes = blockStart.timeIntervalSince(dayStart) / 60
        let baseDurationMinutes = blockEnd.timeIntervalSince(blockStart) / 60

        let topOffset = CGFloat(startMinutes) / 60 * hourHeight
        let baseHeight = max(minimumHeight, CGFloat(baseDurationMinutes) / 60 * hourHeight)
        let currentHeight = max(minimumHeight, baseHeight + dragOffset)

        // Calculate snapped duration for display (computed, not stored)
        let snappedDuration: Double = {
            let newHeight = max(minimumHeight, baseHeight + dragOffset)
            let rawDuration = Double(newHeight / hourHeight * 60)
            return max(minimumDuration, round(rawDuration / snapInterval) * snapInterval)
        }()

        let color = taskColor(for: task)

        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(color)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        if isDragging {
                            Text(formatEndDateTime(task.startTime.addingTimeInterval(snappedDuration * 60)))
                                .font(.caption)
                                .foregroundColor(.orange)
                                .fontWeight(.medium)
                            Text(formatDuration(snappedDuration))
                                .font(.system(size: 9))
                                .foregroundColor(.orange)
                        } else {
                            Text(task.timeRangeFormatted)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if !isDragging, let jobCode = task.jobCode {
                            Text(jobCode.code)
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(jobCode.color.opacity(0.3))
                                .cornerRadius(3)
                        }

                        if !isDragging {
                            Text(task.status.rawValue)
                                .font(.system(size: 9))
                                .foregroundColor(statusColor(for: task.status))
                        }
                    }
                }

                Spacer()
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            // Resize handle
            VStack(spacing: 2) {
                if isDragging {
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle().fill(Color.white).frame(width: 4, height: 4)
                        }
                    }
                } else {
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle().fill(color.opacity(0.5)).frame(width: 4, height: 4)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 16)
            .background(isDragging ? color : color.opacity(0.1))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .updating($dragOffset) { value, state, _ in
                        // Only update the gesture state - no other state changes
                        state = value.translation.height
                    }
                    .onEnded { value in
                        let newHeight = max(minimumHeight, baseHeight + value.translation.height)
                        let rawDuration = Double(newHeight / hourHeight * 60)
                        let finalDuration = max(minimumDuration, round(rawDuration / snapInterval) * snapInterval)
                        onResizeEnded(finalDuration)
                    }
            )
            #if os(macOS)
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            #endif
        }
        .frame(height: currentHeight)
        .background(color.opacity(isDragging ? 0.2 : 0.1))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isDragging ? color : Color.clear, lineWidth: 2)
        )
        .padding(.horizontal, 8)
        .offset(y: topOffset)
        .onTapGesture {
            onTap()
        }
    }

    private func calculateDuration(from height: CGFloat) -> Double {
        return Double(height / hourHeight * 60)
    }

    private func snapDuration(_ duration: Double) -> Double {
        return round(duration / snapInterval) * snapInterval
    }

    private func formatDuration(_ minutes: Double) -> String {
        let hours = Int(minutes) / 60
        let mins = Int(minutes) % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins) min"
    }

    private func formatEndDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        if !calendar.isDate(date, inSameDayAs: task.startTime) {
            formatter.dateFormat = "→ MMM d, h:mm a"
        } else {
            formatter.dateFormat = "→ h:mm a"
        }
        return formatter.string(from: date)
    }

    private func taskColor(for task: LookAheadTask) -> Color {
        if let jobCode = task.jobCode {
            return jobCode.color
        }
        return statusColor(for: task.status)
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
}

#Preview {
    ShiftCalendarView()
        .modelContainer(for: [ShiftEntry.self, Client.self, Well.self, WorkDay.self, LookAheadTask.self])
}
#endif
