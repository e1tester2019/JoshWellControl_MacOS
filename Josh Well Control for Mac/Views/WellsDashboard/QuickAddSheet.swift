//
//  QuickAddSheet.swift
//  Josh Well Control for Mac
//
//  Compact sheet for quickly adding notes or tasks from anywhere
//

import SwiftUI
import SwiftData

struct QuickAddSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var manager: QuickNoteManager

    @FocusState private var titleFocused: Bool

    private var canSave: Bool {
        !manager.pendingTitle.trimmingCharacters(in: .whitespaces).isEmpty && manager.currentWell != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                // Type toggle
                Section {
                    Picker("Type", selection: $manager.quickAddType) {
                        ForEach(QuickAddType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                // Title (required)
                Section {
                    TextField("Title", text: $manager.pendingTitle)
                        .focused($titleFocused)
                    #if os(iOS)
                        .textInputAutocapitalization(.sentences)
                    #endif
                } header: {
                    Text("Title")
                } footer: {
                    if manager.pendingTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Required")
                            .foregroundStyle(.red)
                    }
                }

                // Content/Description
                Section("Details") {
                    TextEditor(text: $manager.pendingContent)
                        .frame(minHeight: 80)
                }

                // Type-specific options
                if manager.quickAddType == .note {
                    noteOptions
                } else {
                    taskOptions
                }

                // Target (well context)
                Section("Target") {
                    if let well = manager.currentWell {
                        HStack {
                            Label(well.name, systemImage: "building.2")
                            Spacer()
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                        }
                    } else {
                        Label("No well selected", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle(manager.quickAddType == .note ? "Quick Note" : "Quick Task")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        manager.dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!canSave)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .onAppear {
                titleFocused = true
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 450)
        #endif
    }

    // MARK: - Note Options

    private var noteOptions: some View {
        Section("Options") {
            Picker("Category", selection: $manager.pendingCategory) {
                ForEach(NoteCategory.allCases, id: \.self) { category in
                    Text(category.rawValue).tag(category)
                }
            }

            Toggle("Pin to top", isOn: $manager.pendingIsPinned)
        }
    }

    // MARK: - Task Options

    private var taskOptions: some View {
        Section("Options") {
            Picker("Priority", selection: $manager.pendingPriority) {
                ForEach(TaskPriority.allCases, id: \.self) { priority in
                    HStack {
                        Circle()
                            .fill(priorityColor(priority))
                            .frame(width: 8, height: 8)
                        Text(priority.rawValue)
                    }
                    .tag(priority)
                }
            }

            DatePicker(
                "Due Date",
                selection: Binding(
                    get: { manager.pendingDueDate ?? Date() },
                    set: { manager.pendingDueDate = $0 }
                ),
                displayedComponents: [.date, .hourAndMinute]
            )

            Toggle("Has due date", isOn: Binding(
                get: { manager.pendingDueDate != nil },
                set: { enabled in
                    if enabled {
                        manager.pendingDueDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
                    } else {
                        manager.pendingDueDate = nil
                    }
                }
            ))
        }
    }

    // MARK: - Actions

    private func save() {
        if manager.quickAddType == .note {
            manager.createNote(context: modelContext)
        } else {
            manager.createTask(context: modelContext)
        }
    }

    private func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .low: return .green
        case .medium: return .blue
        case .high: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Quick Add Note") {
    let manager = QuickNoteManager.shared
    manager.quickAddType = .note
    return QuickAddSheet(manager: manager)
        .modelContainer(for: [Well.self, HandoverNote.self, WellTask.self], inMemory: true)
}

#Preview("Quick Add Task") {
    let manager = QuickNoteManager.shared
    manager.quickAddType = .task
    return QuickAddSheet(manager: manager)
        .modelContainer(for: [Well.self, HandoverNote.self, WellTask.self], inMemory: true)
}
#endif
