//
//  ShiftCalendarViewIOS.swift
//  Josh Well Control for Mac
//
//  iOS version of the Shift Calendar with compact calendar and list view.
//

import SwiftUI
import SwiftData

#if os(iOS)
struct ShiftCalendarViewIOS: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ShiftEntry.date) private var allShifts: [ShiftEntry]
    @Query(sort: \Client.companyName) private var clients: [Client]
    @Query(filter: #Predicate<Well> { !$0.isArchived }, sort: \Well.name) private var wells: [Well]

    @State private var selectedDate: Date = Date()
    @State private var displayedMonth: Date = Date()
    @State private var showingSettings = false
    @State private var showingEditor = false

    private let calendar = Calendar.current
    private let daysOfWeek = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Compact Calendar
                calendarSection

                Divider()
                    .padding(.horizontal)

                // Day Summary
                ShiftDaySummaryView(
                    selectedDate: selectedDate,
                    onEditShift: { showingEditor = true }
                )
                .padding(.horizontal)
            }
        }
        .navigationTitle("Shift Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                ShiftRotationSetupView()
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                ShiftEditorView(date: selectedDate)
            }
        }
        .onAppear {
            Task {
                await ShiftNotificationService.shared.scheduleNextReminder(context: modelContext)
            }
        }
    }

    // MARK: - Calendar Section

    private var calendarSection: some View {
        VStack(spacing: 12) {
            // Month Navigation
            HStack {
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }

                Spacer()

                Text(monthYearString)
                    .font(.headline)

                Spacer()

                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                }
            }
            .padding(.horizontal)

            // Days of Week Header
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                ForEach(daysOfWeek, id: \.self) { day in
                    Text(day)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)

            // Calendar Grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                ForEach(daysInMonth(), id: \.self) { date in
                    if let date = date {
                        DayCellIOS(
                            date: date,
                            shiftType: shiftType(for: date),
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            isToday: calendar.isDateInToday(date),
                            hasWorkDay: hasWorkDay(for: date)
                        )
                        .onTapGesture {
                            selectedDate = date
                        }
                        .onLongPressGesture {
                            selectedDate = date
                            showingEditor = true
                        }
                    } else {
                        Color.clear
                            .frame(height: 44)
                    }
                }
            }
            .padding(.horizontal, 8)

            // Today Button
            Button(action: goToToday) {
                Label("Today", systemImage: "calendar.circle")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
        }
        .padding(.top)
    }

    // MARK: - Day Cell

    private struct DayCellIOS: View {
        let date: Date
        let shiftType: ShiftType
        let isSelected: Bool
        let isToday: Bool
        let hasWorkDay: Bool

        private let calendar = Calendar.current

        var body: some View {
            VStack(spacing: 2) {
                // Day number
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 14, weight: isToday ? .bold : .regular))
                    .foregroundColor(isToday ? .white : .primary)
                    .frame(width: 28, height: 28)
                    .background(isToday ? Color.accentColor : Color.clear)
                    .clipShape(Circle())

                // Shift indicator dot
                Circle()
                    .fill(shiftColor)
                    .frame(width: 8, height: 8)
                    .overlay {
                        if hasWorkDay {
                            Circle()
                                .stroke(Color.white, lineWidth: 1)
                        }
                    }
            }
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(8)
        }

        private var shiftColor: Color {
            switch shiftType {
            case .day: return .blue
            case .night: return .purple
            case .off: return .gray.opacity(0.4)
            }
        }
    }

    // MARK: - Helpers

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayedMonth)
    }

    private func previousMonth() {
        if let newDate = calendar.date(byAdding: .month, value: -1, to: displayedMonth) {
            displayedMonth = newDate
        }
    }

    private func nextMonth() {
        if let newDate = calendar.date(byAdding: .month, value: 1, to: displayedMonth) {
            displayedMonth = newDate
        }
    }

    private func goToToday() {
        displayedMonth = Date()
        selectedDate = Date()
    }

    private func daysInMonth() -> [Date?] {
        var days: [Date?] = []

        let components = calendar.dateComponents([.year, .month], from: displayedMonth)
        guard let firstDayOfMonth = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: displayedMonth) else {
            return days
        }

        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        for _ in 1..<firstWeekday {
            days.append(nil)
        }

        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                days.append(date)
            }
        }

        return days
    }

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
}

// MARK: - Legend View

struct ShiftLegendView: View {
    var body: some View {
        HStack(spacing: 16) {
            LegendItem(color: .blue, label: "Day")
            LegendItem(color: .purple, label: "Night")
            LegendItem(color: .gray.opacity(0.4), label: "Off")
        }
        .font(.caption)
    }

    private struct LegendItem: View {
        let color: Color
        let label: String

        var body: some View {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ShiftCalendarViewIOS()
    }
    .modelContainer(for: [ShiftEntry.self, Client.self, Well.self, WorkDay.self])
}
#endif
