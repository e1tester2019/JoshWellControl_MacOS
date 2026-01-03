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

    @Query(sort: \Pad.name) private var allPads: [Pad]
    @Query(sort: \Well.name) private var allWells: [Well]

    @Bindable var manager: QuickNoteManager

    @FocusState private var titleFocused: Bool
    @State private var selectedPad: Pad?
    @State private var selectedWell: Well?

    private var canSave: Bool {
        !manager.pendingTitle.trimmingCharacters(in: .whitespaces).isEmpty && (selectedWell != nil || selectedPad != nil)
    }

    private var wellsForSelectedPad: [Well] {
        if let pad = selectedPad {
            return (pad.wells ?? []).sorted { $0.name < $1.name }
        }
        return allWells
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

                // Assignment
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
                // Initialize from manager's current context
                selectedWell = manager.currentWell
                selectedPad = manager.currentPad ?? manager.currentWell?.pad
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
            let note = HandoverNote(
                title: manager.pendingTitle.trimmingCharacters(in: .whitespaces),
                content: manager.pendingContent,
                category: manager.pendingCategory,
                author: "",
                isPinned: manager.pendingIsPinned
            )
            modelContext.insert(note)
            note.well = selectedWell
            note.pad = selectedPad
        } else {
            let task = WellTask(
                title: manager.pendingTitle.trimmingCharacters(in: .whitespaces),
                description: manager.pendingContent,
                priority: manager.pendingPriority,
                status: .pending,
                dueDate: manager.pendingDueDate,
                author: ""
            )
            modelContext.insert(task)
            task.well = selectedWell
            task.pad = selectedPad
        }

        try? modelContext.save()
        manager.dismiss()
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
