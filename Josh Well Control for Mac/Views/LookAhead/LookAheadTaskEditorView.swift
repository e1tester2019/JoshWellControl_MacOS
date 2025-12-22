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
    @State private var estimatedDuration: Double = 60
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
                if let jc = newValue {
                    isMetarageBased = jc.isMetarageBased
                    recalculateDuration()
                }
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

            HStack {
                Text("Estimated Duration")
                Spacer()
                TextField("", value: $estimatedDuration, format: .number)
                    .frame(width: 100)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                Text("min")
                    .foregroundStyle(.secondary)
            }

            // Show formatted duration
            if estimatedDuration > 0 {
                HStack {
                    Text("Duration")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatDuration(estimatedDuration))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
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
            estimatedDuration = jc.estimateDuration(forMeters: calculatedMeterage)
        } else if let jc = selectedJobCode, !isMetarageBased {
            estimatedDuration = jc.estimateDuration(forMeters: nil)
        }
    }

    private func formatDuration(_ minutes: Double) -> String {
        let hours = Int(minutes) / 60
        let mins = Int(minutes) % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
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
        estimatedDuration = t.estimatedDuration_min
        isMetarageBased = t.isMetarageBased
        startDepth = t.startDepth_m ?? 0
        endDepth = t.endDepth_m ?? 0
        vendorComments = t.vendorComments
    }

    private func save() {
        let viewModel = LookAheadViewModel()
        viewModel.schedule = schedule

        if let t = task {
            // Update existing task
            t.name = name
            t.notes = notes
            t.jobCode = selectedJobCode
            t.well = selectedWell
            t.estimatedDuration_min = estimatedDuration
            t.isMetarageBased = isMetarageBased
            t.startDepth_m = isMetarageBased ? startDepth : nil
            t.endDepth_m = isMetarageBased ? endDepth : nil
            t.vendorComments = vendorComments
            t.updatedAt = .now

            // Update vendor assignments
            updateVendorAssignments(for: t)

            viewModel.updateDuration(t, newDuration: estimatedDuration, context: modelContext)

            // Reschedule notifications
            if !t.assignments.isEmpty {
                CallReminderService.shared.rescheduleReminder(for: t)
            }
        } else {
            // Create new task
            let newTask = LookAheadTask(
                name: name,
                estimatedDuration_min: estimatedDuration,
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
