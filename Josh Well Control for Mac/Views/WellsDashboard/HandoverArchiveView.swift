//
//  HandoverArchiveView.swift
//  Josh Well Control for Mac
//
//  Browse archived handover reports
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Combine

#if os(macOS)
import AppKit
#endif

struct HandoverArchiveView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HandoverReportArchive.exportDate, order: .reverse) private var archives: [HandoverReportArchive]

    @State private var selectedArchive: HandoverReportArchive?
    @State private var searchText = ""

    private var filteredArchives: [HandoverReportArchive] {
        if searchText.isEmpty {
            return archives
        }
        let search = searchText.lowercased()
        return archives.filter { archive in
            // Only search reportTitle to avoid JSON decoding overhead in filter
            archive.reportTitle.lowercased().contains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredArchives.isEmpty {
                    ContentUnavailableView {
                        Label("No Archives", systemImage: "archivebox")
                    } description: {
                        Text("Exported handover reports will appear here")
                    }
                } else {
                    ForEach(filteredArchives) { archive in
                        ArchiveRow(archive: archive)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedArchive = archive
                            }
                    }
                    .onDelete(perform: deleteArchives)
                }
            }
            .searchable(text: $searchText, prompt: "Search archives...")
            .navigationTitle("Handover Archives")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $selectedArchive) { archive in
                ArchiveDetailView(archive: archive)
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 500)
        #endif
    }

    private func deleteArchives(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredArchives[index])
        }
        try? modelContext.save()
    }
}

// MARK: - Archive Row

struct ArchiveRow: View {
    let archive: HandoverReportArchive

    // Cache decoded values to avoid repeated JSON decoding
    private var wellCount: Int {
        archive.wellNamesData.flatMap { data in
            try? JSONDecoder().decode([String].self, from: data).count
        } ?? 0
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(archive.reportTitle)
                    .font(.headline)

                Text(archive.dateRangeString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Label("\(archive.taskCount)", systemImage: "checklist")
                        .font(.caption)
                        .foregroundStyle(.blue)

                    Label("\(archive.noteCount)", systemImage: "note.text")
                        .font(.caption)
                        .foregroundStyle(.green)

                    if wellCount > 0 {
                        Label("\(wellCount) wells", systemImage: "building.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Exported")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(archive.exportDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if archive.pdfData != nil {
                    Label("PDF", systemImage: "doc.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Archive Detail View

struct ArchiveDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let archive: HandoverReportArchive

    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(archive.reportTitle)
                        .font(.title2)
                        .fontWeight(.bold)

                    HStack(spacing: 16) {
                        Label(archive.dateRangeString, systemImage: "calendar")
                        Label("Exported \(archive.exportDateString)", systemImage: "clock")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    if !archive.wellNames.isEmpty {
                        Text("Wells: \(archive.wellNames.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.secondary.opacity(0.1))

                Divider()

                // Tabs
                Picker("View", selection: $selectedTab) {
                    Text("Tasks (\(archive.taskCount))").tag(0)
                    Text("Notes (\(archive.noteCount))").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                // Content
                if selectedTab == 0 {
                    tasksContent
                } else {
                    notesContent
                }

                Spacer()
            }
            .navigationTitle("Archive Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }

                #if os(macOS)
                if archive.pdfData != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            exportPDF()
                        } label: {
                            Label("Export PDF", systemImage: "arrow.down.doc")
                        }
                    }
                }
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 600)
        #endif
    }

    private var tasksContent: some View {
        Group {
            if archive.archivedTasks.isEmpty {
                ContentUnavailableView("No Tasks", systemImage: "checklist", description: Text("This report had no tasks"))
            } else {
                List(archive.archivedTasks) { task in
                    ArchivedTaskRow(task: task)
                }
                .listStyle(.inset)
            }
        }
    }

    private var notesContent: some View {
        Group {
            if archive.archivedNotes.isEmpty {
                ContentUnavailableView("No Notes", systemImage: "note.text", description: Text("This report had no notes"))
            } else {
                List(archive.archivedNotes) { note in
                    ArchivedNoteRow(note: note)
                }
                .listStyle(.inset)
            }
        }
    }

    #if os(macOS)
    private func exportPDF() {
        guard let pdfData = archive.pdfData else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "\(archive.reportTitle).pdf"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? pdfData.write(to: url)
                NSWorkspace.shared.open(url)
            }
        }
    }
    #endif
}

// MARK: - Archived Task Row

struct ArchivedTaskRow: View {
    let task: ArchivedTask

    private var priorityColor: Color {
        switch task.priority {
        case "Critical": return .red
        case "High": return .orange
        case "Medium": return .yellow
        case "Low": return .green
        default: return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(priorityColor)
                .frame(width: 10, height: 10)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(task.title)
                        .font(.headline)
                        .strikethrough(task.status == "Completed")

                    Text("[\(task.status)]")
                        .font(.caption)
                        .foregroundStyle(task.status == "Completed" ? .green : .secondary)
                }

                if !task.description.isEmpty {
                    Text(task.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                HStack(spacing: 12) {
                    if let wellName = task.wellName {
                        Label(wellName, systemImage: "drop.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if let padName = task.padName {
                        Label("\(padName) (Pad)", systemImage: "square.grid.2x2")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }

                    if let due = task.dueDate {
                        Label(due.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(task.priority)
                        .font(.caption2)
                        .foregroundStyle(priorityColor)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Archived Note Row

struct ArchivedNoteRow: View {
    let note: ArchivedNote

    private var categoryColor: Color {
        switch note.category {
        case "Safety": return .red
        case "Operations": return .blue
        case "Equipment": return .orange
        case "Personnel": return .purple
        case "Handover": return .green
        default: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(note.title)
                    .font(.headline)

                Text("[\(note.category)]")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(categoryColor.opacity(0.2))
                    .foregroundStyle(categoryColor)
                    .cornerRadius(4)
            }

            if !note.content.isEmpty {
                Text(note.content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }

            HStack(spacing: 12) {
                if let wellName = note.wellName {
                    Label(wellName, systemImage: "drop.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let padName = note.padName {
                    Label("\(padName) (Pad)", systemImage: "square.grid.2x2")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }

                if !note.author.isEmpty {
                    Label(note.author, systemImage: "person")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    HandoverArchiveView()
}
