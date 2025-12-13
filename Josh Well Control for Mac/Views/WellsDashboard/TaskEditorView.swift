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

    let well: Well?
    let pad: Pad?
    let task: WellTask?

    @State private var title: String = ""
    @State private var taskDescription: String = ""
    @State private var priority: TaskPriority = .medium
    @State private var status: TaskStatus = .pending
    @State private var hasDueDate: Bool = false
    @State private var dueDate: Date = Date()
    @State private var author: String = ""

    private var isEditing: Bool { task != nil }

    private var ownerName: String {
        if let well = well { return well.name }
        if let pad = pad { return "\(pad.name) (Pad)" }
        return "Unknown"
    }

    init(well: Well, task: WellTask?) {
        self.well = well
        self.pad = nil
        self.task = task
    }

    init(pad: Pad, task: WellTask?) {
        self.well = nil
        self.pad = pad
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
                            .datePickerStyle(.graphical)
                    }
                }

                Section {
                    HStack {
                        Text(pad != nil ? "Pad:" : "Well:")
                        Spacer()
                        Text(ownerName)
                            .foregroundStyle(.secondary)
                    }
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
        if let task = task {
            // Update existing
            task.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            task.taskDescription = taskDescription
            task.priority = priority
            task.status = status
            task.dueDate = hasDueDate ? dueDate : nil
            task.author = author
        } else if let well = well {
            // Create new task for well
            let newTask = well.createTask(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: taskDescription,
                priority: priority,
                dueDate: hasDueDate ? dueDate : nil,
                author: author,
                context: modelContext
            )
            newTask.status = status
        } else if let pad = pad {
            // Create new task for pad
            let newTask = pad.createTask(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: taskDescription,
                priority: priority,
                dueDate: hasDueDate ? dueDate : nil,
                author: author,
                context: modelContext
            )
            newTask.status = status
        }

        try? modelContext.save()
        dismiss()
    }

    private func deleteTask() {
        if let task = task {
            if let well = well {
                well.tasks?.removeAll { $0.id == task.id }
            }
            if let pad = pad {
                pad.tasks?.removeAll { $0.id == task.id }
            }
            modelContext.delete(task)
            try? modelContext.save()
        }
        dismiss()
    }
}
