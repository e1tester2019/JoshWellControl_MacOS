//
//  HandoverSummaryView.swift
//  Josh Well Control for Mac
//
//  Quick shift summary view for verbal handover briefings.
//

import SwiftUI
import SwiftData

struct HandoverSummaryView: View {
    @Environment(\.dismiss) private var dismiss

    let selectedDate: Date

    @Query(sort: \WellTask.createdAt, order: .reverse) private var allTasks: [WellTask]
    @Query(sort: \HandoverNote.createdAt, order: .reverse) private var allNotes: [HandoverNote]

    private let calendar = Calendar.current
    private let settings = ShiftRotationSettings.shared

    // MARK: - Shift Boundaries

    private var currentShiftType: ShiftType {
        settings.expectedShiftType(for: selectedDate)
    }

    private var shiftStartTime: Date {
        var components = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        if currentShiftType == .day {
            components.hour = settings.dayShiftStartHour
            components.minute = settings.dayShiftStartMinute
        } else if currentShiftType == .night {
            components.hour = settings.nightShiftStartHour
            components.minute = settings.nightShiftStartMinute
        } else {
            components.hour = 0
            components.minute = 0
        }
        return calendar.date(from: components) ?? selectedDate
    }

    private var shiftEndTime: Date {
        settings.shiftEndTime(for: currentShiftType, on: selectedDate)
            ?? selectedDate.addingTimeInterval(12 * 3600)
    }

    // MARK: - Filtered Data

    private var tasksCreatedThisShift: [WellTask] {
        allTasks.filter { $0.createdAt >= shiftStartTime && $0.createdAt <= shiftEndTime }
    }

    private var completedThisShift: [WellTask] {
        allTasks.filter {
            $0.status == .completed &&
            $0.completedAt != nil &&
            $0.completedAt! >= shiftStartTime &&
            $0.completedAt! <= shiftEndTime
        }
    }

    private var openTasks: [WellTask] {
        allTasks.filter { $0.isPending }
            .sorted { $0.priority.sortOrder < $1.priority.sortOrder }
    }

    private var overdueTasks: [WellTask] {
        allTasks.filter { $0.isOverdue }
            .sorted { $0.priority.sortOrder < $1.priority.sortOrder }
    }

    private var notesThisShift: [HandoverNote] {
        allNotes.filter { $0.createdAt >= shiftStartTime && $0.createdAt <= shiftEndTime }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    shiftInfoHeader

                    summaryCards

                    Divider()

                    if !overdueTasks.isEmpty {
                        overdueSection
                        Divider()
                    }

                    openTasksSection

                    Divider()

                    completedSection

                    Divider()

                    notesSection
                }
                .padding()
            }
            .navigationTitle("Shift Summary")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        #endif
    }

    // MARK: - Shift Info Header

    private var shiftInfoHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectedDate.formatted(date: .complete, time: .omitted))
                .font(.title3)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                Label {
                    Text("\(currentShiftType.displayName) Shift")
                        .fontWeight(.medium)
                } icon: {
                    Image(systemName: currentShiftType.icon)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(shiftBadgeColor)
                .foregroundColor(.white)
                .cornerRadius(6)

                Text("\(shiftStartTime.formatted(date: .omitted, time: .shortened)) – \(shiftEndTime.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var shiftBadgeColor: Color {
        switch currentShiftType {
        case .day: return .orange
        case .night: return .indigo
        case .off: return .gray
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard(title: "Open Tasks", count: openTasks.count, color: .blue)
            summaryCard(title: "Completed", count: completedThisShift.count, color: .green)
            summaryCard(title: "New Notes", count: notesThisShift.count, color: .orange)
            summaryCard(title: "Overdue", count: overdueTasks.count, color: overdueTasks.isEmpty ? .gray : .red)
        }
    }

    private func summaryCard(title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Overdue Section

    private var overdueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Overdue (\(overdueTasks.count))", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)

            ForEach(overdueTasks) { task in
                taskRow(task, showOverdue: true)
            }
        }
    }

    // MARK: - Open Tasks Section

    private var openTasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Open Tasks (\(openTasks.count))", systemImage: "checklist")
                .font(.headline)

            if openTasks.isEmpty {
                Text("No open tasks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(openTasks) { task in
                    taskRow(task, showOverdue: false)
                }
            }
        }
    }

    // MARK: - Completed This Shift Section

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Completed This Shift (\(completedThisShift.count))", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)

            if completedThisShift.isEmpty {
                Text("No tasks completed this shift")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(completedThisShift) { task in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text(task.title)
                            .font(.subheadline)
                            .strikethrough()
                            .foregroundStyle(.secondary)

                        Spacer()

                        if let wellName = task.well?.name {
                            Text(wellName)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(6)
                    .background(Color.green.opacity(0.05))
                    .cornerRadius(4)
                }
            }
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes This Shift (\(notesThisShift.count))", systemImage: "note.text")
                .font(.headline)

            if notesThisShift.isEmpty {
                Text("No notes created this shift")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(notesThisShift) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Circle()
                                .fill(notePriorityColor(note))
                                .frame(width: 6, height: 6)
                            Text(note.title)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text(note.category.rawValue)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(categoryColor(note).opacity(0.2))
                                .foregroundStyle(categoryColor(note))
                                .cornerRadius(3)

                            Spacer()

                            Text(note.createdAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        if !note.content.isEmpty {
                            MarkdownListView(content: note.content)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.05))
                    .cornerRadius(6)
                }
            }
        }
    }

    // MARK: - Helpers

    private func taskRow(_ task: WellTask, showOverdue: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(taskPriorityColor(task))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if !task.taskDescription.isEmpty {
                    Text(task.taskDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let wellName = task.well?.name {
                    Text(wellName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if showOverdue, let due = task.dueDate {
                    Text("Due: \(due.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(6)
        .background(taskPriorityColor(task).opacity(0.05))
        .cornerRadius(4)
    }

    private func taskPriorityColor(_ task: WellTask) -> Color {
        switch task.priority {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .green
        }
    }

    private func notePriorityColor(_ note: HandoverNote) -> Color {
        switch note.priority {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .green
        }
    }

    private func categoryColor(_ note: HandoverNote) -> Color {
        switch note.category {
        case .safety: return .red
        case .operations: return .blue
        case .equipment: return .orange
        case .personnel: return .purple
        case .handover: return .green
        case .general: return .secondary
        }
    }
}
