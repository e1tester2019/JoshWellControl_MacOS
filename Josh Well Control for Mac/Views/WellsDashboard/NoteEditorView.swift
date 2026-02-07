//
//  NoteEditorView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-09.
//

import SwiftUI
import SwiftData
import Combine

struct NoteEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Pad.name) private var allPads: [Pad]
    @Query(sort: \Well.name) private var allWells: [Well]

    let initialWell: Well?
    let initialPad: Pad?
    let note: HandoverNote?
    let noteDate: Date?  // Date to assign to new notes (for schedule view)

    @State private var title: String = ""
    @State private var content: String = ""
    @State private var category: NoteCategory = .general
    @State private var author: String = ""
    @State private var isPinned: Bool = false
    @State private var selectedWell: Well?
    @State private var selectedPad: Pad?
    @State private var createdDate: Date = Date()
    @State private var isSaving = false

    private var isEditing: Bool { note != nil }

    private var wellsForSelectedPad: [Well] {
        if let pad = selectedPad {
            return (pad.wells ?? []).sorted { $0.name < $1.name }
        }
        return allWells
    }

    init(well: Well, note: HandoverNote?) {
        self.initialWell = well
        self.initialPad = nil
        self.note = note
        self.noteDate = nil
    }

    init(pad: Pad, note: HandoverNote?) {
        self.initialWell = nil
        self.initialPad = pad
        self.note = note
        self.noteDate = nil
    }

    /// Initialize for creating a new note without a pre-selected well/pad
    init() {
        self.initialWell = nil
        self.initialPad = nil
        self.note = nil
        self.noteDate = nil
    }

    /// Initialize for creating a new note for a specific date (from schedule view)
    init(forDate date: Date) {
        self.initialWell = nil
        self.initialPad = nil
        self.note = nil
        self.noteDate = date
    }

    /// Initialize for editing an existing note
    init(note: HandoverNote) {
        self.initialWell = note.well
        self.initialPad = note.pad
        self.note = note
        self.noteDate = nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Note" : "New Handover Note")
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
                        Text("Content")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $content)
                            .frame(minHeight: 150)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }

                    TextField("Author", text: $author)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Classification") {
                    Picker("Category", selection: $category) {
                        ForEach(NoteCategory.allCases, id: \.self) { cat in
                            HStack {
                                Circle()
                                    .fill(categoryColor(for: cat))
                                    .frame(width: 8, height: 8)
                                Text(cat.rawValue)
                            }
                            .tag(cat)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Pin this note", isOn: $isPinned)
                        .help("Pinned notes appear at the top of the list")
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

                Section("Date") {
                    DatePicker("Created", selection: $createdDate, displayedComponents: [.date, .hourAndMinute])

                    if let note = note {
                        HStack {
                            Text("Last Updated:")
                            Spacer()
                            Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                if isEditing {
                    Button("Delete", role: .destructive) {
                        deleteNote()
                    }
                }

                Spacer()

                Button("Save") {
                    saveNote()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 450)
        .onAppear {
            if let note = note {
                title = note.title
                content = note.content
                category = note.category
                author = note.author
                isPinned = note.isPinned
                selectedWell = note.well
                selectedPad = note.pad ?? note.well?.pad
                createdDate = note.createdAt
            } else {
                selectedWell = initialWell
                selectedPad = initialPad ?? initialWell?.pad
                // Use noteDate if provided (from schedule view), otherwise use current time
                createdDate = noteDate ?? Date()
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

    private func categoryColor(for category: NoteCategory) -> Color {
        switch category {
        case .safety: return .red
        case .operations: return .blue
        case .equipment: return .orange
        case .personnel: return .purple
        case .handover: return .green
        case .general: return .secondary
        }
    }

    private func saveNote() {
        guard !isSaving else { return }
        isSaving = true

        // Immediately reset the manager flag to prevent any re-triggering
        QuickNoteManager.shared.showNoteEditor = false

        if let note = note {
            // Update existing
            note.update(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                content: content
            )
            note.category = category
            note.author = author
            note.isPinned = isPinned
            // Update the created date (allows backdating)
            note.createdAt = createdDate
            // Update assignment
            note.well = selectedWell
            note.pad = selectedPad
        } else {
            // Create new note
            let newNote = HandoverNote(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                content: content,
                category: category,
                author: author,
                isPinned: isPinned
            )
            // Use the selected created date
            newNote.createdAt = createdDate
            modelContext.insert(newNote)
            newNote.well = selectedWell
            newNote.pad = selectedPad
        }

        try? modelContext.save()
        dismiss()
    }

    private func deleteNote() {
        if let note = note {
            modelContext.delete(note)
            try? modelContext.save()
        }
        dismiss()
    }
}
