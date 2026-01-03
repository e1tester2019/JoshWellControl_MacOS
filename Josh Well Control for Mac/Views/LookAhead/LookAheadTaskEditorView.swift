//
//  LookAheadTaskEditorView.swift
//  Josh Well Control for Mac
//
//  Editor for creating and editing look ahead tasks.
//

import SwiftUI
import SwiftData

struct LookAheadTaskEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let schedule: LookAheadSchedule?
    let task: LookAheadTask?
    var templateTask: LookAheadTask? = nil  // For duplicating - pre-fills but creates new
    let jobCodes: [JobCode]
    let vendors: [Vendor]
    let wells: [Well]
    var preselectedWell: Well? = nil  // For adding from well dashboard

    @State private var name: String = ""
    @State private var notes: String = ""
    @State private var selectedJobCode: JobCode?
    @State private var vendorAssignmentData: [VendorAssignmentData] = []
    @State private var selectedWell: Well?
    @State private var estimatedDuration_hours: Double = 1.0  // In hours, stored in 0.25 increments
    @State private var isMetarageBased = false
    @State private var startDepth: Double = 0
    @State private var endDepth: Double = 0
    @State private var showVendorPicker = false
    @State private var vendorSearchText = ""

    private var calculatedMeterage: Double {
        max(0, endDepth - startDepth)
    }
    @State private var vendorComments: String = ""
    @State private var insertPosition: Int = 0
    @State private var isLoading: Bool = true  // Prevents recalculation during initial load

    /// Filtered vendors for picker
    private var filteredVendors: [Vendor] {
        let active = vendors.filter { $0.isActive }
        let assignedIDs = Set(vendorAssignmentData.map { $0.vendorID })

        let unassigned = active.filter { !assignedIDs.contains($0.id) }

        if vendorSearchText.isEmpty {
            return unassigned
        }
        let search = vendorSearchText.lowercased()
        return unassigned.filter {
            $0.companyName.lowercased().contains(search) ||
            $0.serviceType.rawValue.lowercased().contains(search)
        }
    }

    private var isEditing: Bool { task != nil }
    private var isDuplicating: Bool { templateTask != nil && task == nil }

    var body: some View {
        NavigationStack {
            Form {
                taskDetailsSection
                durationSection
                vendorSection
                notesSection

                if !isEditing {
                    positionSection
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Task" : (isDuplicating ? "Duplicate Task" : "Add Task"))
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 600)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty)
                }
            }
            .onAppear { loadTask() }
        }
    }

    // MARK: - Sections

    private var taskDetailsSection: some View {
        Section("Task Details") {
            TextField("Task Name", text: $name)
                .textFieldStyle(.roundedBorder)

            Picker("Job Code", selection: $selectedJobCode) {
                Text("None").tag(nil as JobCode?)
                ForEach(jobCodes) { jc in
                    Text(jc.displayName).tag(jc as JobCode?)
                }
            }
            .onChange(of: selectedJobCode) { _, newValue in
                guard !isLoading, let jc = newValue else { return }
                isMetarageBased = jc.isMetarageBased
                recalculateDuration()
            }

            Picker("Well", selection: $selectedWell) {
                Text("None").tag(nil as Well?)
                ForEach(wells) { well in
                    Text(well.name).tag(well as Well?)
                }
            }
        }
    }

    private var durationSection: some View {
        Section("Duration") {
            Toggle("Meterage-Based Estimate", isOn: $isMetarageBased)
                .onChange(of: isMetarageBased) { _, _ in
                    guard !isLoading else { return }
                    recalculateDuration()
                }

            if isMetarageBased {
                HStack {
                    Text("Start Depth")
                    Spacer()
                    TextField("", value: $startDepth, format: .number)
                        .frame(width: 100)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: startDepth) { _, _ in
                            guard !isLoading else { return }
                            recalculateDuration()
                        }
                    Text("m")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("End Depth")
                    Spacer()
                    TextField("", value: $endDepth, format: .number)
                        .frame(width: 100)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: endDepth) { _, _ in
                            guard !isLoading else { return }
                            recalculateDuration()
                        }
                    Text("m")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Total Interval")
                    Spacer()
                    Text(String(format: "%.1f m", calculatedMeterage))
                        .fontWeight(.medium)
                        .foregroundStyle(calculatedMeterage > 0 ? .primary : .secondary)
                }

                if let jc = selectedJobCode, jc.averageDurationPerMeter_min > 0 {
                    HStack {
                        Text("Average Rate")
                        Spacer()
                        Text(String(format: "%.2f min/m", jc.averageDurationPerMeter_min))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }

            // Quick duration presets
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick Set")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach([0.5, 1.0, 2.0, 4.0, 8.0, 12.0], id: \.self) { hours in
                        Button {
                            estimatedDuration_hours = hours
                        } label: {
                            Text(hours < 1 ? "30m" : "\(Int(hours))h")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(estimatedDuration_hours == hours ? Color.accentColor : Color.secondary.opacity(0.2))
                                .foregroundStyle(estimatedDuration_hours == hours ? .white : .primary)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Text("Duration")
                Spacer()
                TextField("", value: $estimatedDuration_hours, format: .number.precision(.fractionLength(2)))
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                Stepper("", value: $estimatedDuration_hours, in: 0.25...168, step: 0.25)
                    .labelsHidden()
                Text("hrs")
                    .foregroundStyle(.secondary)
            }

            // Show start and end times if editing
            if let task = task {
                Divider()

                HStack {
                    Text("Starts")
                    Spacer()
                    Text(task.startTime.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Ends")
                    Spacer()
                    Text(calculatedEndTime(from: task.startTime).formatted(date: .abbreviated, time: .shortened))
                        .fontWeight(.medium)
                        .foregroundStyle(.blue)
                }
            }

            // Show formatted duration
            if estimatedDuration_hours > 0 {
                HStack {
                    Text("Total")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatDuration(estimatedDuration_hours))
                        .fontWeight(.medium)
                }
                .font(.callout)
            }
        }
    }

    private func calculatedEndTime(from startTime: Date) -> Date {
        startTime.addingTimeInterval(estimatedDuration_hours * 3600)
    }

    private var vendorSection: some View {
        Section("Vendors & Calls") {
            // Assigned vendors list with individual call times
            if vendorAssignmentData.isEmpty {
                HStack {
                    Image(systemName: "person.2.badge.gearshape")
                        .foregroundStyle(.secondary)
                    Text("No vendors assigned")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Add Vendor") {
                        showVendorPicker = true
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ForEach($vendorAssignmentData) { $assignment in
                    VendorAssignmentRow(
                        assignment: $assignment,
                        vendor: vendors.first { $0.id == assignment.vendorID },
                        onRemove: {
                            vendorAssignmentData.removeAll { $0.id == assignment.id }
                        }
                    )
                }

                Button {
                    showVendorPicker = true
                } label: {
                    Label("Add Another Vendor", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }

            if !vendorAssignmentData.isEmpty {
                TextField("Vendor Comments", text: $vendorComments, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
        .sheet(isPresented: $showVendorPicker) {
            VendorPickerSheet(
                vendors: filteredVendors,
                searchText: $vendorSearchText,
                onSelect: { vendor in
                    vendorAssignmentData.append(VendorAssignmentData(vendorID: vendor.id))
                    vendorSearchText = ""
                    showVendorPicker = false
                }
            )
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextEditor(text: $notes)
                .frame(minHeight: 80)
        }
    }

    private var positionSection: some View {
        Section("Position in Schedule") {
            Picker("Insert After", selection: $insertPosition) {
                Text("At Beginning").tag(0)
                if let schedule = schedule {
                    ForEach(Array(schedule.sortedTasks.enumerated()), id: \.element.id) { index, t in
                        Text(t.name).tag(index + 1)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func recalculateDuration() {
        if isMetarageBased, let jc = selectedJobCode {
            // Job code returns minutes, convert to hours rounded to nearest 0.25
            let minutes = jc.estimateDuration(forMeters: calculatedMeterage)
            estimatedDuration_hours = roundToQuarterHour(minutes / 60.0)
        } else if let jc = selectedJobCode, !isMetarageBased {
            let minutes = jc.estimateDuration(forMeters: nil)
            estimatedDuration_hours = roundToQuarterHour(minutes / 60.0)
        }
    }

    private func roundToQuarterHour(_ hours: Double) -> Double {
        (hours * 4).rounded() / 4
    }

    private func formatDuration(_ hours: Double) -> String {
        let totalMinutes = Int(hours * 60)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 && m > 0 {
            return "\(h)h \(m)m"
        } else if h > 0 {
            return "\(h)h"
        }
        return "\(m)m"
    }

    private func loadTask() {
        // Set default insert position to end
        insertPosition = schedule?.taskCount ?? 0

        // Use task for editing, or templateTask for duplicating
        let sourceTask = task ?? templateTask
        guard let t = sourceTask else {
            // No source task - check for preselected well (e.g., adding from dashboard)
            if let well = preselectedWell {
                selectedWell = well
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isLoading = false
            }
            return
        }

        name = t.name + (templateTask != nil ? " (Copy)" : "")
        notes = t.notes
        selectedJobCode = t.jobCode
        // Load vendor assignments
        vendorAssignmentData = t.assignments.compactMap { assignment in
            guard let vendor = assignment.vendor else { return nil }
            return VendorAssignmentData(
                vendorID: vendor.id,
                callReminderMinutes: assignment.callReminderMinutesBefore,
                notes: assignment.notes
            )
        }
        selectedWell = t.well
        vendorComments = t.vendorComments

        // IMPORTANT: Set depths BEFORE isMetarageBased to ensure correct recalculation
        startDepth = t.startDepth_m ?? 0
        endDepth = t.endDepth_m ?? 0

        // Set all values while isLoading is true (prevents onChange handlers from recalculating)
        isMetarageBased = t.isMetarageBased

        // Convert stored minutes to hours for display
        estimatedDuration_hours = roundToQuarterHour(t.estimatedDuration_min / 60.0)

        // Delay enabling onChange handlers until after SwiftUI processes all state changes
        // onChange handlers fire asynchronously in the next render cycle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isLoading = false
        }
    }

    private func save() {
        let viewModel = LookAheadViewModel()
        viewModel.schedule = schedule

        // Convert hours back to minutes for storage
        let durationMinutes = estimatedDuration_hours * 60

        if let t = task {
            // Update existing task
            t.name = name
            t.notes = notes
            t.jobCode = selectedJobCode
            t.well = selectedWell
            t.estimatedDuration_min = durationMinutes
            t.isMetarageBased = isMetarageBased
            t.startDepth_m = isMetarageBased ? startDepth : nil
            t.endDepth_m = isMetarageBased ? endDepth : nil
            t.vendorComments = vendorComments
            t.updatedAt = .now

            // Update vendor assignments
            updateVendorAssignments(for: t)

            viewModel.updateDuration(t, newDuration: durationMinutes, context: modelContext)

            // Reschedule notifications
            if !t.assignments.isEmpty {
                CallReminderService.shared.rescheduleReminder(for: t)
            }
        } else {
            // Create new task
            let newTask = LookAheadTask(
                name: name,
                estimatedDuration_min: durationMinutes,
                sequenceOrder: insertPosition
            )
            newTask.notes = notes
            newTask.jobCode = selectedJobCode
            newTask.well = selectedWell
            newTask.isMetarageBased = isMetarageBased
            newTask.startDepth_m = isMetarageBased ? startDepth : nil
            newTask.endDepth_m = isMetarageBased ? endDepth : nil
            newTask.vendorComments = vendorComments

            viewModel.insertTask(at: insertPosition, task: newTask, context: modelContext)

            // Create vendor assignments
            createVendorAssignments(for: newTask)

            // Schedule notifications
            if !newTask.assignments.isEmpty {
                CallReminderService.shared.scheduleCallReminder(for: newTask)
            }
        }

        try? modelContext.save()
        dismiss()
    }

    private func updateVendorAssignments(for task: LookAheadTask) {
        // Remove old assignments
        for assignment in task.assignments {
            modelContext.delete(assignment)
        }

        // Create new assignments
        createVendorAssignments(for: task)
    }

    private func createVendorAssignments(for task: LookAheadTask) {
        for data in vendorAssignmentData {
            guard let vendor = vendors.first(where: { $0.id == data.vendorID }) else { continue }
            let assignment = TaskVendorAssignment(
                vendor: vendor,
                callReminderMinutesBefore: data.callReminderMinutes
            )
            assignment.notes = data.notes
            assignment.task = task
            modelContext.insert(assignment)
        }
    }
}

// MARK: - Vendor Assignment Data

struct VendorAssignmentData: Identifiable {
    let id = UUID()
    var vendorID: UUID
    var callReminderMinutes: Int = 60
    var notes: String = ""
}

// MARK: - Vendor Assignment Row

struct VendorAssignmentRow: View {
    @Binding var assignment: VendorAssignmentData
    let vendor: Vendor?
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let vendor = vendor {
                    Image(systemName: vendor.serviceType.icon)
                        .foregroundStyle(.blue)
                        .frame(width: 24)

                    VStack(alignment: .leading) {
                        Text(vendor.companyName)
                            .fontWeight(.medium)
                        if !vendor.phone.isEmpty {
                            Text(vendor.phone)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Unknown Vendor")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text("Call")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("", selection: $assignment.callReminderMinutes) {
                    Text("30 min before").tag(30)
                    Text("1 hour before").tag(60)
                    Text("2 hours before").tag(120)
                    Text("4 hours before").tag(240)
                    Text("1 day before").tag(1440)
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Vendor Picker Sheet

struct VendorPickerSheet: View {
    let vendors: [Vendor]
    @Binding var searchText: String
    var onSelect: (Vendor) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if vendors.isEmpty {
                    if searchText.isEmpty {
                        ContentUnavailableView {
                            Label("All Vendors Assigned", systemImage: "checkmark.circle")
                        } description: {
                            Text("All active vendors are already assigned to this task.")
                        }
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                } else {
                    ForEach(vendors) { vendor in
                        Button {
                            onSelect(vendor)
                        } label: {
                            HStack {
                                Image(systemName: vendor.serviceType.icon)
                                    .foregroundStyle(.blue)
                                    .frame(width: 30)

                                VStack(alignment: .leading) {
                                    Text(vendor.companyName)
                                        .foregroundStyle(.primary)
                                    HStack {
                                        Text(vendor.serviceType.rawValue)
                                        if !vendor.contactName.isEmpty {
                                            Text("•")
                                            Text(vendor.contactName)
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if !vendor.phone.isEmpty {
                                    Text(vendor.phone)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Add Vendor")
            #if os(macOS)
            .frame(minWidth: 400, minHeight: 300)
            #endif
            .searchable(text: $searchText, prompt: "Search vendors...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    LookAheadTaskEditorView(
        schedule: nil,
        task: nil,
        jobCodes: [],
        vendors: [],
        wells: []
    )
}
