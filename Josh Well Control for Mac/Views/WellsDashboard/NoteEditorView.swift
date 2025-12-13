//
//  NoteEditorView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-09.
//

import SwiftUI
import SwiftData

struct NoteEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let well: Well?
    let pad: Pad?
    let note: HandoverNote?

    @State private var title: String = ""
    @State private var content: String = ""
    @State private var category: NoteCategory = .general
    @State private var author: String = ""
    @State private var isPinned: Bool = false

    private var isEditing: Bool { note != nil }

    private var ownerName: String {
        if let well = well { return well.name }
        if let pad = pad { return "\(pad.name) (Pad)" }
        return "Unknown"
    }

    init(well: Well, note: HandoverNote?) {
        self.well = well
        self.pad = nil
        self.note = note
    }

    init(pad: Pad, note: HandoverNote?) {
        self.well = nil
        self.pad = pad
        self.note = note
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

                Section {
                    HStack {
                        Text(pad != nil ? "Pad:" : "Well:")
                        Spacer()
                        Text(ownerName)
                            .foregroundStyle(.secondary)
                    }

                    if let note = note {
                        HStack {
                            Text("Created:")
                            Spacer()
                            Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
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
        if let note = note {
            // Update existing
            note.update(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                content: content
            )
            note.category = category
            note.author = author
            note.isPinned = isPinned
        } else if let well = well {
            // Create new note for well
            _ = well.createNote(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                content: content,
                category: category,
                author: author,
                isPinned: isPinned,
                context: modelContext
            )
        } else if let pad = pad {
            // Create new note for pad
            _ = pad.createNote(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                content: content,
                category: category,
                author: author,
                isPinned: isPinned,
                context: modelContext
            )
        }

        try? modelContext.save()
        dismiss()
    }

    private func deleteNote() {
        if let note = note {
            if let well = well {
                well.notes?.removeAll { $0.id == note.id }
            }
            if let pad = pad {
                pad.notes?.removeAll { $0.id == note.id }
            }
            modelContext.delete(note)
            try? modelContext.save()
        }
        dismiss()
    }
}
