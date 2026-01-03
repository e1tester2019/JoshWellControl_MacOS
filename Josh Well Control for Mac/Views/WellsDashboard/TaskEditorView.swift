//
//  TaskEditorView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-09.
//

import SwiftUI
import SwiftData

struct TaskEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Pad.name) private var allPads: [Pad]
    @Query(sort: \Well.name) private var allWells: [Well]

    let initialWell: Well?
    let initialPad: Pad?
    let task: WellTask?

    @State private var title: String = ""
    @State private var taskDescription: String = ""
    @State private var priority: TaskPriority = .medium
    @State private var status: TaskStatus = .pending
    @State private var hasDueDate: Bool = false
    @State private var dueDate: Date = Date()
    @State private var author: String = ""
    @State private var selectedWell: Well?
    @State private var selectedPad: Pad?
    @State private var isSaving = false

    private var isEditing: Bool { task != nil }

    private var wellsForSelectedPad: [Well] {
        if let pad = selectedPad {
            return (pad.wells ?? []).sorted { $0.name < $1.name }
        }
        return allWells
    }

    init(well: Well, task: WellTask?) {
        self.initialWell = well
        self.initialPad = nil
        self.task = task
    }

    init(pad: Pad, task: WellTask?) {
        self.initialWell = nil
        self.initialPad = pad
        self.task = task
    }

    /// Initialize for creating a new task without a pre-selected well/pad
    init() {
        self.initialWell = nil
        self.initialPad = nil
        self.task = nil
    }

    /// Initialize for editing an existing task
    init(task: WellTask) {
        self.initialWell = task.well
        self.initialPad = task.pad
        self.task = task
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Task" : "New Task")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Form
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                        .textFieldStyle(.roundedBorder)

                    VStack(alignment: .leading) {
                        Text("Description")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $taskDescription)
                            .frame(minHeight: 80)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }

                    TextField("Author", text: $author)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Status") {
                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { p in
                            HStack {
                                Circle()
                                    .fill(priorityColor(for: p))
                                    .frame(width: 8, height: 8)
                                Text(p.rawValue)
                            }
                            .tag(p)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Status", selection: $status) {
                        ForEach(TaskStatus.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Due Date") {
                    Toggle("Set Due Date", isOn: $hasDueDate)

                    if hasDueDate {
                        DatePicker("Due Date", selection: $dueDate, displayedComponents: [.date])
                    }
                }

                Section("Assignment") {
                    Picker("Pad", selection: $selectedPad) {
                        Text("None").tag(nil as Pad?)
                        ForEach(allPads) { pad in
                            Text(pad.name).tag(pad as Pad?)
                        }
                    }

                    Picker("Well", selection: $selectedWell) {
                        Text("None").tag(nil as Well?)
                        ForEach(wellsForSelectedPad) { well in
                            Text(well.name).tag(well as Well?)
                        }
                    }
                    .disabled(selectedPad == nil && allPads.count > 0)
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                if isEditing {
                    Button("Delete", role: .destructive) {
                        deleteTask()
                    }
                }

                Spacer()

                Button("Save") {
                    saveTask()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 450, minHeight: 500)
        .onAppear {
            if let task = task {
                title = task.title
                taskDescription = task.taskDescription
                priority = task.priority
                status = task.status
                author = task.author
                if let due = task.dueDate {
                    hasDueDate = true
                    dueDate = due
                }
                selectedWell = task.well
                selectedPad = task.pad ?? task.well?.pad
            } else {
                selectedWell = initialWell
                selectedPad = initialPad ?? initialWell?.pad
            }
        }
        .onChange(of: selectedPad) { _, newPad in
            // Reset well selection if it doesn't belong to the new pad
            if let newPad = newPad, let well = selectedWell {
                if well.pad?.id != newPad.id {
                    selectedWell = nil
                }
            }
        }
    }

    private func priorityColor(for priority: TaskPriority) -> Color {
        switch priority {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .green
        }
    }

    private func saveTask() {
        guard !isSaving else { return }
        isSaving = true

        // Immediately reset the manager flag to prevent any re-triggering
        QuickNoteManager.shared.showTaskEditor = false

        if let task = task {
            // Update existing
            task.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            task.taskDescription = taskDescription
            task.priority = priority
            task.status = status
            task.dueDate = hasDueDate ? dueDate : nil
            task.author = author
            // Update assignment
            task.well = selectedWell
            task.pad = selectedPad
        } else {
            // Create new task
            let newTask = WellTask(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: taskDescription,
                priority: priority,
                status: status,
                dueDate: hasDueDate ? dueDate : nil,
                author: author
            )
            modelContext.insert(newTask)
            newTask.well = selectedWell
            newTask.pad = selectedPad
        }

        try? modelContext.save()
        dismiss()
    }

    private func deleteTask() {
        if let task = task {
            modelContext.delete(task)
            try? modelContext.save()
        }
        dismiss()
    }
}
