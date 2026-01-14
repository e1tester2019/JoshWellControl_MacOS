//
//  LookAheadTaskSidebarView.swift
//  Josh Well Control for Mac
//
//  Sidebar editor view for LookAhead tasks within the Shift Calendar.
//

import SwiftUI
import SwiftData

struct LookAheadTaskSidebarView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var task: LookAheadTask
    var onClose: () -> Void
    var onTimingChanged: ((LookAheadTask, Date) -> Void)?  // Called with task and old end time

    @Query(sort: \JobCode.code) private var jobCodes: [JobCode]
    @Query(filter: #Predicate<Well> { !$0.isArchived }, sort: \Well.name) private var wells: [Well]
    @Query(sort: \Vendor.companyName) private var vendors: [Vendor]

    @State private var showingVendorPicker = false
    @State private var editableEndTime: Date = Date()
    @State private var editableDuration: Double = 60

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Status Section
                    statusSection

                    Divider()

                    // Task Details
                    detailsSection

                    Divider()

                    // Timing Section
                    timingSection

                    Divider()

                    // Vendors Section
                    vendorsSection

                    Divider()

                    // Notes Section
                    notesSection
                }
                .padding()
            }
        }
        #if os(macOS)
        .background(Color(NSColor.controlBackgroundColor))
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit Task")
                    .font(.headline)
                Text(task.dateFormatted)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: task.status.icon)
                    .foregroundColor(statusColor)
                Text("Status")
                    .font(.headline)
            }

            #if os(macOS)
            HStack(spacing: 8) {
                ForEach(LookAheadTaskStatus.allCases, id: \.self) { status in
                    Button(action: { task.status = status }) {
                        HStack(spacing: 4) {
                            Image(systemName: status.icon)
                                .font(.caption)
                            Text(status.rawValue)
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(task.status == status ? statusColor(for: status).opacity(0.2) : Color.clear)
                        .foregroundColor(task.status == status ? statusColor(for: status) : .secondary)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(task.status == status ? statusColor(for: status) : Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            #else
            Picker("Status", selection: Binding(
                get: { task.status },
                set: { task.status = $0 }
            )) {
                ForEach(LookAheadTaskStatus.allCases, id: \.self) { status in
                    Label(status.rawValue, systemImage: status.icon)
                        .tag(status)
                }
            }
            .pickerStyle(.menu)
            #endif

            // Status info
            if let startedAt = task.startedAt {
                HStack {
                    Text("Started:")
                    Spacer()
                    Text(formatDateTime(startedAt))
                        .foregroundColor(.secondary)
                }
                .font(.caption)
            }

            if let completedAt = task.completedAt {
                HStack {
                    Text("Completed:")
                    Spacer()
                    Text(formatDateTime(completedAt))
                        .foregroundColor(.secondary)
                }
                .font(.caption)
            }
        }
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet.clipboard")
                    .foregroundColor(.blue)
                Text("Details")
                    .font(.headline)
            }

            // Task Name
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Task name", text: $task.name)
                    .textFieldStyle(.roundedBorder)
            }

            // Job Code
            VStack(alignment: .leading, spacing: 4) {
                Text("Job Code")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("", selection: $task.jobCode) {
                    Text("None").tag(nil as JobCode?)
                    ForEach(jobCodes) { jobCode in
                        Text("\(jobCode.code) - \(jobCode.name)").tag(jobCode as JobCode?)
                    }
                }
                .labelsHidden()
                #if os(macOS)
                .frame(maxWidth: .infinity, alignment: .leading)
                #endif
            }

            // Well
            VStack(alignment: .leading, spacing: 4) {
                Text("Well")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("", selection: $task.well) {
                    Text("None").tag(nil as Well?)
                    ForEach(wells) { well in
                        Text(well.name).tag(well as Well?)
                    }
                }
                .labelsHidden()
                #if os(macOS)
                .frame(maxWidth: .infinity, alignment: .leading)
                #endif
            }
        }
    }

    // MARK: - Timing Section

    private var timingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.orange)
                Text("Timing")
                    .font(.headline)
            }

            // Start Time
            VStack(alignment: .leading, spacing: 4) {
                Text("Start")
                    .font(.caption)
                    .foregroundColor(.secondary)
                DatePicker("", selection: $task.startTime)
                    .labelsHidden()
                    .onChange(of: task.startTime) { oldValue, newValue in
                        // Update editable end time to maintain duration
                        editableEndTime = newValue.addingTimeInterval(editableDuration * 60)
                    }
            }

            // End Time (editable)
            VStack(alignment: .leading, spacing: 4) {
                Text("End")
                    .font(.caption)
                    .foregroundColor(.secondary)
                DatePicker("", selection: $editableEndTime)
                    .labelsHidden()
                    .onChange(of: editableEndTime) { oldValue, newValue in
                        // Calculate new duration from end time change
                        let oldEndTime = task.endTime
                        let newDuration = newValue.timeIntervalSince(task.startTime) / 60
                        if newDuration >= 15 {  // Minimum 15 minutes
                            editableDuration = newDuration
                            task.estimatedDuration_min = newDuration
                            // Trigger chaining
                            onTimingChanged?(task, oldEndTime)
                        } else {
                            // Reset to minimum
                            editableEndTime = task.startTime.addingTimeInterval(15 * 60)
                        }
                    }
            }

            // Duration (editable)
            VStack(alignment: .leading, spacing: 4) {
                Text("Duration")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    TextField("", value: $editableDuration, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onChange(of: editableDuration) { oldValue, newValue in
                            guard newValue >= 15 else {
                                editableDuration = 15
                                return
                            }
                            let oldEndTime = task.endTime
                            task.estimatedDuration_min = newValue
                            editableEndTime = task.endTime
                            // Trigger chaining
                            onTimingChanged?(task, oldEndTime)
                        }
                    Text("minutes")
                        .foregroundColor(.secondary)

                    Spacer()

                    // Quick duration buttons
                    HStack(spacing: 4) {
                        ForEach([30, 60, 120, 240], id: \.self) { mins in
                            Button("\(mins < 60 ? "\(mins)m" : "\(mins/60)h")") {
                                let oldEndTime = task.endTime
                                editableDuration = Double(mins)
                                task.estimatedDuration_min = Double(mins)
                                editableEndTime = task.endTime
                                onTimingChanged?(task, oldEndTime)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }

            // Formatted duration display
            HStack {
                Text("Total:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(formatDuration(editableDuration))
                    .font(.caption)
                    .fontWeight(.medium)
            }

            // Actual duration (if completed)
            if task.status == .completed {
                Divider()

                HStack {
                    Text("Actual Duration")
                        .frame(width: 100, alignment: .leading)
                    TextField("", value: $task.actualDuration_min, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("minutes")
                        .foregroundColor(.secondary)
                }

                if let variance = task.durationVariance_min {
                    HStack {
                        Text("Variance")
                            .frame(width: 100, alignment: .leading)
                        Text(variance >= 0 ? "+\(Int(variance))m" : "\(Int(variance))m")
                            .foregroundColor(variance > 0 ? .red : .green)
                    }
                    .font(.caption)
                }
            }
        }
        .onAppear {
            // Initialize editable values from task
            editableEndTime = task.endTime
            editableDuration = task.estimatedDuration_min
        }
        .onChange(of: task.id) { _, _ in
            // Reset when task changes
            editableEndTime = task.endTime
            editableDuration = task.estimatedDuration_min
        }
    }

    private func formatDuration(_ minutes: Double) -> String {
        let hours = Int(minutes) / 60
        let mins = Int(minutes) % 60
        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours)h"
        }
        return "\(mins)m"
    }

    // MARK: - Vendors Section

    private var vendorsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.2")
                    .foregroundColor(.purple)
                Text("Vendors")
                    .font(.headline)

                Spacer()

                Button(action: { showingVendorPicker = true }) {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
            }

            if task.assignments.isEmpty {
                Text("No vendors assigned")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(task.assignments) { assignment in
                    vendorRow(assignment)
                }
            }
        }
        .sheet(isPresented: $showingVendorPicker) {
            vendorPickerSheet
        }
    }

    private func vendorRow(_ assignment: TaskVendorAssignment) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let vendor = assignment.vendor {
                    Text(vendor.companyName)
                        .font(.callout)
                }
                if assignment.isConfirmed {
                    Text("Confirmed")
                        .font(.caption2)
                        .foregroundColor(.green)
                } else {
                    Text("Pending confirmation")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }

            Spacer()

            Button(action: { assignment.isConfirmed.toggle() }) {
                Image(systemName: assignment.isConfirmed ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(assignment.isConfirmed ? .green : .secondary)
            }
            .buttonStyle(.plain)

            Button(action: {
                if let index = task.vendorAssignments?.firstIndex(where: { $0.id == assignment.id }) {
                    task.vendorAssignments?.remove(at: index)
                    modelContext.delete(assignment)
                }
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }

    private var vendorPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(vendors) { vendor in
                    let isAssigned = task.assignedVendors.contains { $0.id == vendor.id }
                    Button(action: {
                        if !isAssigned {
                            let assignment = TaskVendorAssignment(vendor: vendor)
                            assignment.task = task
                            if task.vendorAssignments == nil {
                                task.vendorAssignments = []
                            }
                            task.vendorAssignments?.append(assignment)
                            modelContext.insert(assignment)
                        }
                        showingVendorPicker = false
                    }) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(vendor.companyName)
                                Text(vendor.serviceType.rawValue)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if isAssigned {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .disabled(isAssigned)
                }
            }
            .navigationTitle("Add Vendor")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingVendorPicker = false }
                }
            }
        }
        #if os(macOS)
        .frame(width: 300, height: 400)
        #endif
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "note.text")
                    .foregroundColor(.green)
                Text("Notes")
                    .font(.headline)
            }

            TextEditor(text: $task.notes)
                .frame(minHeight: 80)
                .font(.body)
                #if os(macOS)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                #endif
                .overlay(alignment: .topLeading) {
                    if task.notes.isEmpty {
                        Text("Add notes about this task...")
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        statusColor(for: task.status)
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

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
