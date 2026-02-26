//
//  ShiftCalendarView.swift
//  Josh Well Control for Mac
//
//  Main calendar view for shift tracking on macOS.
//  Supports month, timeline, week, and day view modes.
//

import SwiftUI
import SwiftData

#if os(macOS)

// MARK: - Calendar View Mode

enum CalendarViewMode: String, CaseIterable {
    case month = "Month"
    case timeline = "Timeline"
    case week = "Week"
    case day = "Day"

    var icon: String {
        switch self {
        case .month: return "calendar"
        case .timeline: return "slider.horizontal.3"
        case .week: return "calendar.day.timeline.left"
        case .day: return "sun.max"
        }
    }
}

// MARK: - Main Calendar View

struct ShiftCalendarView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ShiftEntry.date) private var allShifts: [ShiftEntry]
    @Query(sort: \WorkDay.startDate) private var allWorkDays: [WorkDay]
    @Query(sort: \Client.companyName) private var clients: [Client]
    @Query(filter: #Predicate<Well> { !$0.isArchived }, sort: \Well.name) private var wells: [Well]

    @State private var selectedDate: Date = Date()
    @State private var displayedMonth: Date = Date()
    @State private var viewMode: CalendarViewMode = .month
    @State private var showingSettings = false
    @State private var showingEditor = false

    private let calendar = Calendar.current

    /// O(1) shift lookup dictionary — rebuilt when allShifts changes
    private var shiftDictionary: [Date: ShiftEntry] {
        var dict: [Date: ShiftEntry] = [:]
        for entry in allShifts {
            let dayStart = calendar.startOfDay(for: entry.date)
            dict[dayStart] = entry
        }
        return dict
    }

    /// O(1) work day lookup — maps every date covered by a WorkDay to that WorkDay.
    /// Handles multi-day WorkDays by expanding startDate...endDate into individual dates.
    private var workDayDictionary: [Date: WorkDay] {
        var dict: [Date: WorkDay] = [:]
        for workDay in allWorkDays {
            let start = calendar.startOfDay(for: workDay.startDate)
            let end = calendar.startOfDay(for: workDay.endDate)
            // Single-day or multi-day WorkDay
            var current = start
            while current <= end {
                dict[current] = workDay
                guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
                current = next
            }
        }
        return dict
    }

    var body: some View {
        HSplitView {
            // Calendar Grid
            VStack(spacing: 0) {
                calendarHeader

                Divider()

                switch viewMode {
                case .month:
                    MonthCalendarView(
                        displayedMonth: displayedMonth,
                        selectedDate: $selectedDate,
                        showingEditor: $showingEditor,
                        shiftTypeForDate: shiftType(for:),
                        hasWorkDayForDate: hasWorkDay(for:),
                        isConfirmedShift: isConfirmedShift(for:)
                    )
                case .timeline:
                    TimelineCalendarView(
                        selectedDate: $selectedDate,
                        showingEditor: $showingEditor,
                        allShifts: allShifts,
                        shiftTypeForDate: shiftType(for:),
                        hasWorkDayForDate: hasWorkDay(for:),
                        shiftEntryForDate: shiftEntry(for:),
                        workDayForDate: workDay(for:)
                    )
                case .week:
                    WeekCalendarView(
                        selectedDate: $selectedDate,
                        showingEditor: $showingEditor,
                        shiftTypeForDate: shiftType(for:),
                        hasWorkDayForDate: hasWorkDay(for:),
                        shiftEntryForDate: shiftEntry(for:),
                        workDayForDate: workDay(for:)
                    )
                case .day:
                    DayCalendarView(
                        selectedDate: $selectedDate,
                        shiftTypeForDate: shiftType(for:),
                        shiftEntryForDate: shiftEntry(for:),
                        workDayForDate: workDay(for:)
                    )
                }
            }
            .frame(minWidth: 500)

            // Sidebar — always show day summary
            ShiftDaySummaryView(
                selectedDate: selectedDate,
                onEditShift: { showingEditor = true }
            )
            .frame(minWidth: 220, idealWidth: 280, maxWidth: 400)
        }
        .sheet(isPresented: $showingSettings) {
            ShiftRotationSetupView()
        }
        .sheet(isPresented: $showingEditor) {
            ShiftEditorView(date: selectedDate)
        }
        // Keyboard shortcuts (hidden buttons for menu-bar shortcuts)
        .background {
            Group {
                Button("") { goToToday() }
                    .keyboardShortcut("t", modifiers: .command)
                Button("") { showingEditor = true }
                    .keyboardShortcut("e", modifiers: .command)
                Button("") { viewMode = .month }
                    .keyboardShortcut("1", modifiers: .command)
                Button("") { viewMode = .timeline }
                    .keyboardShortcut("2", modifiers: .command)
                Button("") { viewMode = .week }
                    .keyboardShortcut("3", modifiers: .command)
                Button("") { viewMode = .day }
                    .keyboardShortcut("4", modifiers: .command)
                Button("") { navigatePrevious() }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { navigateNext() }
                    .keyboardShortcut(.rightArrow, modifiers: [])
            }
            .frame(width: 0, height: 0)
            .opacity(0)
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
            Button(action: navigatePrevious) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)

            Text(headerTitle)
                .font(.title2)
                .fontWeight(.semibold)
                .frame(minWidth: 200)

            Button(action: navigateNext) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)

            Spacer()

            Picker("View", selection: $viewMode) {
                ForEach(CalendarViewMode.allCases, id: \.self) { mode in
                    Label(mode.rawValue, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)

            Spacer().frame(width: 16)

            Button(action: goToToday) {
                Text("Today")
            }
            .buttonStyle(.bordered)

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
        case .timeline:
            let endDate = calendar.date(byAdding: .day, value: 6, to: selectedDate) ?? selectedDate
            formatter.dateFormat = "MMM d"
            let startStr = formatter.string(from: selectedDate)
            let endStr = formatter.string(from: endDate)
            formatter.dateFormat = "yyyy"
            let yearStr = formatter.string(from: endDate)
            return "\(startStr) - \(endStr), \(yearStr)"
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
        withAnimation(CalendarAnimation.monthTransition) {
            switch viewMode {
            case .month:
                if let newDate = calendar.date(byAdding: .month, value: -1, to: displayedMonth) {
                    displayedMonth = newDate
                }
            case .timeline:
                if let newDate = calendar.date(byAdding: .day, value: -7, to: selectedDate) {
                    selectedDate = newDate
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
    }

    private func navigateNext() {
        withAnimation(CalendarAnimation.monthTransition) {
            switch viewMode {
            case .month:
                if let newDate = calendar.date(byAdding: .month, value: 1, to: displayedMonth) {
                    displayedMonth = newDate
                }
            case .timeline:
                if let newDate = calendar.date(byAdding: .day, value: 7, to: selectedDate) {
                    selectedDate = newDate
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
    }

    private func goToToday() {
        displayedMonth = Date()
        selectedDate = Date()
    }

    // MARK: - Shift Helpers (O(1) via dictionary)

    private func shiftType(for date: Date) -> ShiftType {
        let dayStart = calendar.startOfDay(for: date)
        if let entry = shiftDictionary[dayStart] {
            return entry.shiftType
        }
        // If no ShiftEntry but a WorkDay covers this date, treat as Day shift
        if workDayDictionary[dayStart] != nil {
            return .day
        }
        return ShiftRotationSettings.shared.expectedShiftType(for: date)
    }

    private func hasWorkDay(for date: Date) -> Bool {
        let dayStart = calendar.startOfDay(for: date)
        // Check ShiftEntry's linked WorkDay first, then standalone WorkDays
        if shiftDictionary[dayStart]?.workDay != nil {
            return true
        }
        return workDayDictionary[dayStart] != nil
    }

    private func isConfirmedShift(for date: Date) -> Bool {
        let dayStart = calendar.startOfDay(for: date)
        // Confirmed if there's a ShiftEntry OR a WorkDay covering this date
        if shiftDictionary[dayStart] != nil {
            return true
        }
        return workDayDictionary[dayStart] != nil
    }

    private func shiftEntry(for date: Date) -> ShiftEntry? {
        let dayStart = calendar.startOfDay(for: date)
        return shiftDictionary[dayStart]
    }

    private func workDay(for date: Date) -> WorkDay? {
        let dayStart = calendar.startOfDay(for: date)
        // Prefer ShiftEntry's linked WorkDay, fall back to standalone
        return shiftDictionary[dayStart]?.workDay ?? workDayDictionary[dayStart]
    }
}

// MARK: - Month Calendar View

private struct MonthCalendarView: View {
    let displayedMonth: Date
    @Binding var selectedDate: Date
    @Binding var showingEditor: Bool
    let shiftTypeForDate: (Date) -> ShiftType
    let hasWorkDayForDate: (Date) -> Bool
    let isConfirmedShift: (Date) -> Bool

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
                            showingEditor: $showingEditor,
                            shiftTypeForDate: shiftTypeForDate,
                            hasWorkDayForDate: hasWorkDayForDate,
                            isConfirmedShift: isConfirmedShift
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
}

// MARK: - Month Week Row

private struct MonthWeekRow: View {
    let week: [Date?]
    @Binding var selectedDate: Date
    @Binding var showingEditor: Bool
    let shiftTypeForDate: (Date) -> ShiftType
    let hasWorkDayForDate: (Date) -> Bool
    let isConfirmedShift: (Date) -> Bool

    private let calendar = Calendar.current

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 1) {
            ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                if let date = date {
                    MonthDayCell(
                        date: date,
                        shiftType: shiftTypeForDate(date),
                        isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                        isToday: calendar.isDateInToday(date),
                        hasWorkDay: hasWorkDayForDate(date),
                        isConfirmed: isConfirmedShift(date)
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
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
}

// MARK: - Month Day Cell

private struct MonthDayCell: View {
    let date: Date
    let shiftType: ShiftType
    let isSelected: Bool
    let isToday: Bool
    let hasWorkDay: Bool
    let isConfirmed: Bool

    @State private var isHovered = false

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                // Day number
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 16, weight: isToday ? .bold : .regular, design: .rounded))
                    .foregroundColor(isToday ? .white : .primary)
                    .frame(width: 28, height: 28)
                    .background(isToday ? Color.accentColor : Color.clear)
                    .clipShape(Circle())

                // Work day indicator
                HStack(spacing: 3) {
                    if hasWorkDay {
                        Image(systemName: "briefcase.fill")
                            .font(.system(size: 8))
                            .foregroundColor(ShiftColorPalette.color(for: shiftType))
                    }
                    ShiftBadge(shiftType, confirmed: isConfirmed, compact: true)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)

            // Bottom confirmation bar
            ShiftConfirmationBar(shiftType: shiftType, isConfirmed: isConfirmed)
        }
        .background(
            ShiftCellBackground(shiftType: shiftType, isSelected: isSelected, isToday: isToday)
        )
        .scaleEffect(isHovered && !isSelected ? 1.02 : 1.0)
        .animation(CalendarAnimation.cellSelection, value: isSelected)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityDescription: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        let dateStr = formatter.string(from: date)
        var description = "\(dateStr), \(shiftType.displayName) Shift"
        if !isConfirmed {
            description += " (predicted)"
        }
        if hasWorkDay {
            description += ", work logged"
        }
        if isToday {
            description += ", today"
        }
        return description
    }
}

// MARK: - Timeline Calendar View

private struct TimelineCalendarView: View {
    @Binding var selectedDate: Date
    @Binding var showingEditor: Bool
    let allShifts: [ShiftEntry]
    let shiftTypeForDate: (Date) -> ShiftType
    let hasWorkDayForDate: (Date) -> Bool
    let shiftEntryForDate: (Date) -> ShiftEntry?
    let workDayForDate: (Date) -> WorkDay?

    private let calendar = Calendar.current

    private var visibleDays: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: selectedDate)) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Day columns
            HStack(spacing: 0) {
                ForEach(visibleDays, id: \.self) { day in
                    timelineDayColumn(for: day)
                        .frame(maxWidth: .infinity)
                        .onTapGesture { selectedDate = day }
                        .onTapGesture(count: 2) {
                            selectedDate = day
                            showingEditor = true
                        }
                }
            }
        }
    }

    private func timelineDayColumn(for date: Date) -> some View {
        let shift = shiftTypeForDate(date)
        let entry = shiftEntryForDate(date)
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)

        return VStack(spacing: 0) {
            // Day header
            VStack(spacing: 4) {
                Text(dayOfWeek(date))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 18, weight: isToday ? .bold : .medium, design: .rounded))
                    .foregroundColor(isToday ? .white : .primary)
                    .frame(width: 32, height: 32)
                    .background(isToday ? Color.accentColor : Color.clear)
                    .clipShape(Circle())

                // Shift type badge
                ShiftBadge(shift, confirmed: true)
            }
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Work details
            VStack(alignment: .leading, spacing: 8) {
                if let entry = entry {
                    if let client = entry.client {
                        Label(client.companyName, systemImage: "building.2")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    if let well = entry.well {
                        Label(well.name, systemImage: "oilcan.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    if let workDay = entry.workDay {
                        HStack {
                            Image(systemName: "dollarsign.circle.fill")
                                .foregroundColor(.green)
                            Text(formattedCurrency(workDay.totalEarnings))
                                .font(.caption)
                                .fontWeight(.medium)
                        }

                        if workDay.totalMileage > 0 {
                            Label("\(Int(workDay.totalMileage)) km", systemImage: "car.fill")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    if !entry.notes.isEmpty {
                        Label("Has notes", systemImage: "note.text")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else if let wd = workDayForDate(date) {
                    // Standalone WorkDay (no ShiftEntry)
                    if let client = wd.client {
                        Label(client.companyName, systemImage: "building.2")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    if let well = wd.well {
                        Label(well.name, systemImage: "oilcan.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    HStack {
                        Image(systemName: "dollarsign.circle.fill")
                            .foregroundColor(.green)
                        Text(formattedCurrency(wd.totalEarnings))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                } else if shift != .off {
                    Text("Not confirmed")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(ShiftColorPalette.color(for: shift).opacity(0.06))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.15), lineWidth: isSelected ? 2 : 0.5)
        )
    }

    private func dayOfWeek(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func formattedCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
}

// MARK: - Week Calendar View

private struct WeekCalendarView: View {
    @Binding var selectedDate: Date
    @Binding var showingEditor: Bool
    let shiftTypeForDate: (Date) -> ShiftType
    let hasWorkDayForDate: (Date) -> Bool
    let shiftEntryForDate: (Date) -> ShiftEntry?
    let workDayForDate: (Date) -> WorkDay?

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
                        weekDayColumn(for: day)
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
        let shift = shiftTypeForDate(date)

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

            Text(shift.displayName.prefix(1))
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(ShiftColorPalette.color(for: shift))
                .cornerRadius(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .onTapGesture { selectedDate = date }
    }

    private func weekDayColumn(for date: Date) -> some View {
        let shift = shiftTypeForDate(date)

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

            // Shift block (if working)
            if shift != .off {
                shiftBlock(for: date, shift: shift)
            }

            // Current time indicator
            if calendar.isDateInToday(date) {
                currentTimeIndicator
            }
        }
        .frame(maxWidth: .infinity)
        .onTapGesture { selectedDate = date }
        .onTapGesture(count: 2) {
            selectedDate = date
            showingEditor = true
        }
    }

    private func shiftBlock(for date: Date, shift: ShiftType) -> some View {
        let settings = ShiftRotationSettings.shared
        let startHour: Double
        let endHour: Double

        if shift == .day {
            startHour = Double(settings.dayShiftStartHour) + Double(settings.dayShiftStartMinute) / 60
            endHour = Double(settings.nightShiftStartHour) + Double(settings.nightShiftStartMinute) / 60
        } else {
            startHour = Double(settings.nightShiftStartHour) + Double(settings.nightShiftStartMinute) / 60
            endHour = 24.0
        }

        let topOffset = startHour * hourHeight
        let blockHeight = (endHour - startHour) * hourHeight

        return VStack(alignment: .leading, spacing: 4) {
            Text("\(shift.displayName) Shift")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ShiftColorPalette.color(for: shift))

            if let entry = shiftEntryForDate(date), let client = entry.client {
                Text(client.companyName)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else if let wd = workDayForDate(date), let client = wd.client {
                Text(client.companyName)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            if let entry = shiftEntryForDate(date), let workDay = entry.workDay {
                Text(formattedCurrency(workDay.totalEarnings))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.green)
            } else if let wd = workDayForDate(date) {
                Text(formattedCurrency(wd.totalEarnings))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.green)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: blockHeight, alignment: .top)
        .background(ShiftColorPalette.color(for: shift).opacity(0.1))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(ShiftColorPalette.color(for: shift).opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 2)
        .offset(y: topOffset)
    }

    private var currentTimeIndicator: some View {
        let now = Date()
        let currentHour = Double(calendar.component(.hour, from: now)) + Double(calendar.component(.minute, from: now)) / 60
        let yOffset = currentHour * hourHeight

        return HStack(spacing: 0) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
            Rectangle()
                .fill(Color.red)
                .frame(height: 1)
        }
        .offset(y: yOffset - 4)
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

    private func formattedCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
}

// MARK: - Day Calendar View

private struct DayCalendarView: View {
    @Binding var selectedDate: Date
    let shiftTypeForDate: (Date) -> ShiftType
    let shiftEntryForDate: (Date) -> ShiftEntry?
    let workDayForDate: (Date) -> WorkDay?

    private let calendar = Calendar.current

    var body: some View {
        let shift = shiftTypeForDate(selectedDate)
        let entry = shiftEntryForDate(selectedDate)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Shift type banner
                HStack {
                    Image(systemName: shift.icon)
                        .font(.title2)
                    Text("\(shift.displayName) Shift")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                }
                .foregroundColor(.white)
                .padding()
                .background(
                    LinearGradient(
                        colors: ShiftColorPalette.gradient(for: shift),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)

                // Key metrics
                if let entry = entry {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        if let workDay = entry.workDay {
                            metricCard(
                                title: "Earnings",
                                value: formattedCurrency(workDay.totalEarnings),
                                icon: "dollarsign.circle.fill",
                                color: .green
                            )

                            metricCard(
                                title: "Mileage",
                                value: workDay.totalMileage > 0 ? "\(Int(workDay.totalMileage)) km" : "—",
                                icon: "car.fill",
                                color: .blue
                            )
                        }

                        if let client = entry.client {
                            metricCard(
                                title: "Client",
                                value: client.companyName,
                                icon: "building.2",
                                color: .purple
                            )
                        }

                        if let well = entry.well {
                            metricCard(
                                title: "Well",
                                value: well.name,
                                icon: "oilcan.fill",
                                color: .orange
                            )
                        }
                    }

                    // Notes
                    if !entry.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Notes", systemImage: "note.text")
                                .font(.headline)
                            Text(entry.notes)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }

                    // Invoice status
                    if let workDay = entry.workDay, workDay.isInvoiced {
                        HStack {
                            Label("Invoiced", systemImage: "doc.text.fill")
                                .foregroundColor(.blue)
                            if workDay.isPaid {
                                Label("Paid", systemImage: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        .font(.callout)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                } else if let wd = workDayForDate(selectedDate) {
                    // Standalone WorkDay (no ShiftEntry)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        metricCard(
                            title: "Earnings",
                            value: formattedCurrency(wd.totalEarnings),
                            icon: "dollarsign.circle.fill",
                            color: .green
                        )

                        metricCard(
                            title: "Mileage",
                            value: wd.totalMileage > 0 ? "\(Int(wd.totalMileage)) km" : "—",
                            icon: "car.fill",
                            color: .blue
                        )

                        if let client = wd.client {
                            metricCard(
                                title: "Client",
                                value: client.companyName,
                                icon: "building.2",
                                color: .purple
                            )
                        }

                        if let well = wd.well {
                            metricCard(
                                title: "Well",
                                value: well.name,
                                icon: "oilcan.fill",
                                color: .orange
                            )
                        }
                    }

                    if wd.isInvoiced {
                        HStack {
                            Label("Invoiced", systemImage: "doc.text.fill")
                                .foregroundColor(.blue)
                            if wd.isPaid {
                                Label("Paid", systemImage: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        .font(.callout)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                } else if shift != .off {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("Predicted from rotation")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Double-click or use the sidebar to confirm this shift")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "house.fill")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("Day Off")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
            .padding()
        }
    }

    private func metricCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func formattedCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
}

#Preview {
    ShiftCalendarView()
        .modelContainer(for: [ShiftEntry.self, Client.self, Well.self, WorkDay.self])
}
#endif
