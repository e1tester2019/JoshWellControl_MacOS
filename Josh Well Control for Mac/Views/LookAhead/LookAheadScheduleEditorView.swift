//
//  LookAheadScheduleEditorView.swift
//  Josh Well Control for Mac
//
//  Editor for creating and editing look ahead schedules.
//

import SwiftUI
import SwiftData

struct LookAheadScheduleEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Pad.name) private var pads: [Pad]
    @Query(sort: \Well.name) private var wells: [Well]

    let schedule: LookAheadSchedule?

    @State private var name: String = ""
    @State private var startDate: Date = Date.now
    @State private var notes: String = ""
    @State private var selectedPad: Pad?
    @State private var selectedWell: Well?
    @State private var isActive: Bool = true

    private var isEditing: Bool { schedule != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Schedule Details") {
                    TextField("Schedule Name", text: $name)
                        .textFieldStyle(.roundedBorder)

                    DatePicker("Start Date & Time", selection: $startDate)

                    Toggle("Active Schedule", isOn: $isActive)
                }

                Section("Location (Optional)") {
                    Picker("Pad", selection: $selectedPad) {
                        Text("None").tag(nil as Pad?)
                        ForEach(pads) { pad in
                            Text(pad.name).tag(pad as Pad?)
                        }
                    }

                    Picker("Well", selection: $selectedWell) {
                        Text("None").tag(nil as Well?)
                        ForEach(wells) { well in
                            Text(well.name).tag(well as Well?)
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }

                if isEditing, let schedule = schedule {
                    Section("Statistics") {
                        HStack {
                            Text("Tasks")
                            Spacer()
                            Text("\(schedule.taskCount)")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Duration")
                            Spacer()
                            Text(schedule.totalDurationFormatted)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("End Date")
                            Spacer()
                            Text(schedule.calculatedEndDate.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Schedule" : "New Schedule")
            #if os(macOS)
            .frame(minWidth: 450, minHeight: 400)
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
            .onAppear { loadSchedule() }
        }
    }

    private func loadSchedule() {
        guard let s = schedule else {
            name = "Schedule \(Date.now.formatted(date: .abbreviated, time: .omitted))"
            return
        }
        name = s.name
        startDate = s.startDate
        notes = s.notes
        selectedPad = s.pad
        selectedWell = s.well
        isActive = s.isActive
    }

    private func save() {
        if let s = schedule {
            // Update existing
            let dateChanged = s.startDate != startDate
            s.name = name
            s.startDate = startDate
            s.notes = notes
            s.pad = selectedPad
            s.well = selectedWell
            s.isActive = isActive
            s.updatedAt = .now

            // If start date changed, cascade all task times
            if dateChanged {
                let viewModel = LookAheadViewModel()
                viewModel.schedule = s
                viewModel.updateScheduleStartDate(startDate, context: modelContext)
            }

            // If marked active, deactivate others
            if isActive {
                let descriptor = FetchDescriptor<LookAheadSchedule>()
                if let all = try? modelContext.fetch(descriptor) {
                    for other in all where other.id != s.id {
                        other.isActive = false
                    }
                }
            }
        } else {
            // Create new
            let newSchedule = LookAheadSchedule(name: name, startDate: startDate)
            newSchedule.notes = notes
            newSchedule.pad = selectedPad
            newSchedule.well = selectedWell
            newSchedule.isActive = isActive

            // If marked active, deactivate others
            if isActive {
                let descriptor = FetchDescriptor<LookAheadSchedule>()
                if let all = try? modelContext.fetch(descriptor) {
                    for other in all {
                        other.isActive = false
                    }
                }
            }

            modelContext.insert(newSchedule)
        }

        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    LookAheadScheduleEditorView(schedule: nil)
}
