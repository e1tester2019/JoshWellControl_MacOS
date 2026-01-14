//
//  ShiftRotationSetupView.swift
//  Josh Well Control for Mac
//
//  Settings view for configuring shift rotation and notifications.
//

import SwiftUI
import SwiftData

struct ShiftRotationSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var settings = ShiftRotationSettings.shared

    @State private var showingGenerateConfirmation = false
    @State private var daysToGenerate = 60

    var body: some View {
        NavigationStack {
            #if os(macOS)
            macOSContent
            #else
            iOSContent
            #endif
        }
        #if os(macOS)
        .frame(width: 500, height: 650)
        #endif
    }

    // MARK: - macOS Content

    #if os(macOS)
    private var macOSContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Shift Settings")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            // Form content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Rotation Pattern
                    settingsSection(title: "Rotation Pattern") {
                        VStack(spacing: 12) {
                            rotationRow(
                                icon: "sun.max.fill",
                                color: .blue,
                                label: "Days",
                                value: $settings.daysInRotation
                            )

                            rotationRow(
                                icon: "moon.fill",
                                color: .purple,
                                label: "Nights",
                                value: $settings.nightsInRotation
                            )

                            rotationRow(
                                icon: "house.fill",
                                color: .gray,
                                label: "Days Off",
                                value: $settings.daysOffInRotation
                            )

                            Divider()

                            HStack {
                                Text("Total Cycle")
                                Spacer()
                                Text("\(settings.totalCycleDays) days")
                                    .fontWeight(.semibold)
                            }
                        }
                    }

                    // Rotation Start Date
                    settingsSection(title: "Rotation Start") {
                        VStack(alignment: .leading, spacing: 8) {
                            DatePicker(
                                "First Day of Rotation",
                                selection: Binding(
                                    get: { settings.rotationStartDate ?? Date() },
                                    set: { settings.rotationStartDate = $0 }
                                ),
                                displayedComponents: .date
                            )

                            if settings.rotationStartDate == nil {
                                Text("Set the start date of your current rotation cycle")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                HStack {
                                    Text("Today's expected shift:")
                                    Spacer()
                                    let expected = settings.expectedShiftType(for: Date())
                                    Label(expected.displayName, systemImage: expected.icon)
                                        .foregroundColor(shiftColor(for: expected))
                                }
                                .font(.caption)
                            }
                        }
                    }

                    // Shift Times
                    settingsSection(title: "Shift Times") {
                        VStack(spacing: 12) {
                            HStack {
                                Text("Day Shift Start")
                                Spacer()
                                timePicker(hour: $settings.dayShiftStartHour, minute: $settings.dayShiftStartMinute)
                            }

                            HStack {
                                Text("Night Shift Start")
                                Spacer()
                                timePicker(hour: $settings.nightShiftStartHour, minute: $settings.nightShiftStartMinute)
                            }

                            Text("Day shift ends when night shift starts, and vice versa")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Notifications
                    settingsSection(title: "End of Shift Reminders") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Enable Reminders", isOn: $settings.endOfShiftReminderEnabled)

                            if settings.endOfShiftReminderEnabled {
                                HStack {
                                    Text("Remind me")
                                    Spacer()
                                    Picker("", selection: $settings.reminderMinutesBefore) {
                                        Text("At shift end").tag(0)
                                        Text("15 min before").tag(15)
                                        Text("30 min before").tag(30)
                                        Text("1 hour before").tag(60)
                                    }
                                    .labelsHidden()
                                    .frame(width: 150)
                                }

                                if let nextReminder = ShiftNotificationService.shared.nextScheduledReminder {
                                    HStack {
                                        Text("Next reminder:")
                                        Spacer()
                                        Text(formatDateTime(nextReminder))
                                            .foregroundColor(.secondary)
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    }

                    // Generate Schedule
                    settingsSection(title: "Generate Shifts") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Days to generate")
                                Spacer()
                                Picker("", selection: $daysToGenerate) {
                                    Text("30 days").tag(30)
                                    Text("60 days").tag(60)
                                    Text("90 days").tag(90)
                                }
                                .labelsHidden()
                                .frame(width: 120)
                            }

                            Button(action: { showingGenerateConfirmation = true }) {
                                HStack {
                                    Image(systemName: "calendar.badge.plus")
                                    Text("Generate Shift Schedule")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(settings.rotationStartDate == nil)

                            Text("Creates shift entries based on your rotation pattern. Existing entries will be preserved.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Footer buttons
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveSettings()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .confirmationDialog(
            "Generate Shift Schedule",
            isPresented: $showingGenerateConfirmation,
            titleVisibility: .visible
        ) {
            Button("Generate") {
                generateSchedule()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will create \(daysToGenerate) days of shift entries starting from today. Existing entries will not be overwritten.")
        }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func rotationRow(icon: String, color: Color, label: String, value: Binding<Int>) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            Text(label)
            Spacer()
            Stepper("\(value.wrappedValue)", value: value, in: 1...30)
                .labelsHidden()
            Text("\(value.wrappedValue)")
                .frame(width: 30, alignment: .trailing)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func timePicker(hour: Binding<Int>, minute: Binding<Int>) -> some View {
        HStack(spacing: 4) {
            Picker("", selection: hour) {
                ForEach(0..<24, id: \.self) { h in
                    Text(formatHour(h)).tag(h)
                }
            }
            .labelsHidden()
            .frame(width: 80)

            Text(":")

            Picker("", selection: minute) {
                ForEach([0, 15, 30, 45], id: \.self) { m in
                    Text(String(format: "%02d", m)).tag(m)
                }
            }
            .labelsHidden()
            .frame(width: 60)
        }
    }
    #endif

    // MARK: - iOS Content

    #if os(iOS)
    private var iOSContent: some View {
        Form {
            // Rotation Pattern
            Section("Rotation Pattern") {
                Stepper(value: $settings.daysInRotation, in: 1...30) {
                    HStack {
                        Image(systemName: "sun.max.fill")
                            .foregroundColor(.blue)
                        Text("Days")
                        Spacer()
                        Text("\(settings.daysInRotation)")
                            .foregroundColor(.secondary)
                    }
                }

                Stepper(value: $settings.nightsInRotation, in: 1...30) {
                    HStack {
                        Image(systemName: "moon.fill")
                            .foregroundColor(.purple)
                        Text("Nights")
                        Spacer()
                        Text("\(settings.nightsInRotation)")
                            .foregroundColor(.secondary)
                    }
                }

                Stepper(value: $settings.daysOffInRotation, in: 1...30) {
                    HStack {
                        Image(systemName: "house.fill")
                            .foregroundColor(.gray)
                        Text("Days Off")
                        Spacer()
                        Text("\(settings.daysOffInRotation)")
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text("Total Cycle")
                    Spacer()
                    Text("\(settings.totalCycleDays) days")
                        .fontWeight(.semibold)
                }
            }

            // Rotation Start Date
            Section("Rotation Start") {
                DatePicker(
                    "First Day of Rotation",
                    selection: Binding(
                        get: { settings.rotationStartDate ?? Date() },
                        set: { settings.rotationStartDate = $0 }
                    ),
                    displayedComponents: .date
                )

                if settings.rotationStartDate == nil {
                    Text("Set the start date of your current rotation cycle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    HStack {
                        Text("Today's expected shift:")
                        Spacer()
                        let expected = settings.expectedShiftType(for: Date())
                        Label(expected.displayName, systemImage: expected.icon)
                            .foregroundColor(shiftColor(for: expected))
                    }
                    .font(.caption)
                }
            }

            // Shift Times
            Section("Shift Times") {
                HStack {
                    Text("Day Shift Start")
                    Spacer()
                    Picker("Hour", selection: $settings.dayShiftStartHour) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(formatHour(hour)).tag(hour)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 80)

                    Text(":")

                    Picker("Minute", selection: $settings.dayShiftStartMinute) {
                        ForEach([0, 15, 30, 45], id: \.self) { minute in
                            Text(String(format: "%02d", minute)).tag(minute)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 60)
                }

                HStack {
                    Text("Night Shift Start")
                    Spacer()
                    Picker("Hour", selection: $settings.nightShiftStartHour) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(formatHour(hour)).tag(hour)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 80)

                    Text(":")

                    Picker("Minute", selection: $settings.nightShiftStartMinute) {
                        ForEach([0, 15, 30, 45], id: \.self) { minute in
                            Text(String(format: "%02d", minute)).tag(minute)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 60)
                }

                Text("Day shift ends when night shift starts, and vice versa")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Notifications
            Section("End of Shift Reminders") {
                Toggle("Enable Reminders", isOn: $settings.endOfShiftReminderEnabled)

                if settings.endOfShiftReminderEnabled {
                    Picker("Remind me", selection: $settings.reminderMinutesBefore) {
                        Text("At shift end").tag(0)
                        Text("15 min before").tag(15)
                        Text("30 min before").tag(30)
                        Text("1 hour before").tag(60)
                    }

                    if let nextReminder = ShiftNotificationService.shared.nextScheduledReminder {
                        HStack {
                            Text("Next reminder:")
                            Spacer()
                            Text(formatDateTime(nextReminder))
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }

            // Generate Schedule
            Section("Generate Shifts") {
                HStack {
                    Text("Days to generate")
                    Spacer()
                    Picker("Days", selection: $daysToGenerate) {
                        Text("30 days").tag(30)
                        Text("60 days").tag(60)
                        Text("90 days").tag(90)
                    }
                    .labelsHidden()
                }

                Button(action: { showingGenerateConfirmation = true }) {
                    HStack {
                        Image(systemName: "calendar.badge.plus")
                        Text("Generate Shift Schedule")
                    }
                }
                .disabled(settings.rotationStartDate == nil)

                Text("Creates shift entries based on your rotation pattern. Existing entries will be preserved.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Shift Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveSettings()
                }
            }
        }
        .confirmationDialog(
            "Generate Shift Schedule",
            isPresented: $showingGenerateConfirmation,
            titleVisibility: .visible
        ) {
            Button("Generate") {
                generateSchedule()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will create \(daysToGenerate) days of shift entries starting from today. Existing entries will not be overwritten.")
        }
    }
    #endif

    // MARK: - Actions

    private func saveSettings() {
        ShiftRotationSettings.shared = settings

        // Reschedule notifications with new settings
        Task {
            await ShiftNotificationService.shared.scheduleNextReminder(context: modelContext)
        }

        dismiss()
    }

    private func generateSchedule() {
        guard settings.rotationStartDate != nil else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // First fetch existing entries to avoid duplicates
        let descriptor = FetchDescriptor<ShiftEntry>(sortBy: [SortDescriptor(\ShiftEntry.date)])
        let existingEntries = (try? modelContext.fetch(descriptor)) ?? []
        let existingDates = Set(existingEntries.map { calendar.startOfDay(for: $0.date) })

        // Generate entries for each day
        for dayOffset in 0..<daysToGenerate {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: today) else {
                continue
            }

            let dayStart = calendar.startOfDay(for: date)

            // Skip if entry already exists for this date
            if existingDates.contains(dayStart) {
                continue
            }

            let expectedType = settings.expectedShiftType(for: date)
            let entry = ShiftEntry(date: dayStart, shiftType: expectedType)
            modelContext.insert(entry)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to generate schedule: \(error)")
        }
    }

    // MARK: - Helpers

    private func shiftColor(for type: ShiftType) -> Color {
        switch type {
        case .day: return .blue
        case .night: return .purple
        case .off: return .gray
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

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
}
