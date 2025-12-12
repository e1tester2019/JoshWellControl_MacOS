//
//  SurveyListViewIOS.swift
//  Josh Well Control for Mac
//
//  iOS-optimized survey list view with touch-friendly interactions
//

#if os(iOS)
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SurveyListViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState
    @State private var showingImporter = false
    @State private var showingAddSheet = false

    private var sortedSurveys: [SurveyStation] {
        (project.surveys ?? []).sorted { $0.md < $1.md }
    }

    var body: some View {
        List {
            // Survey stations
            ForEach(sortedSurveys) { survey in
                SurveyStationRow(survey: survey)
            }
            .onDelete(perform: deleteSurveys)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Surveys")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingImporter = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }

                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .sheet(isPresented: $showingAddSheet) {
            AddSurveySheet(project: project, isPresented: $showingAddSheet)
        }
    }

    private func deleteSurveys(at offsets: IndexSet) {
        let surveysToDelete = offsets.map { sortedSurveys[$0] }
        for survey in surveysToDelete {
            if let index = project.surveys?.firstIndex(where: { $0.id == survey.id }) {
                project.surveys?.remove(at: index)
            }
            modelContext.delete(survey)
        }
        try? modelContext.save()
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }

        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)

            for line in lines {
                let parts = line.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                guard parts.count >= 3 else { continue }

                if let md = Double(parts[0]),
                   let inc = Double(parts[1]),
                   let azi = Double(parts[2]) {
                    let survey = SurveyStation(md: md, inc: inc, azi: azi)
                    survey.project = project
                    if project.surveys == nil { project.surveys = [] }
                    project.surveys?.append(survey)
                    modelContext.insert(survey)
                }
            }
            try modelContext.save()
        } catch {
            print("Import error: \(error)")
        }
    }
}

// MARK: - Survey Station Row

private struct SurveyStationRow: View {
    let survey: SurveyStation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("MD: \(survey.md, format: .number) m")
                    .font(.headline)

                Spacer()

                if let tvd = survey.tvd {
                    Text("TVD: \(tvd, format: .number) m")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Label("\(survey.inc, format: .number)°", systemImage: "angle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Label("\(survey.azi, format: .number)°", systemImage: "safari")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Survey Sheet

private struct AddSurveySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let project: ProjectState
    @Binding var isPresented: Bool

    @State private var md: Double = 0
    @State private var inclination: Double = 0
    @State private var azimuth: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Station") {
                    HStack {
                        Text("MD")
                        Spacer()
                        TextField("MD", value: $md, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("m")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Inclination")
                        Spacer()
                        TextField("Inc", value: $inclination, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("°")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Azimuth")
                        Spacer()
                        TextField("Azi", value: $azimuth, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("°")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add Survey")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addSurvey()
                        dismiss()
                    }
                }
            }
        }
    }

    private func addSurvey() {
        let survey = SurveyStation(md: md, inc: inclination, azi: azimuth)
        survey.project = project
        if project.surveys == nil { project.surveys = [] }
        project.surveys?.append(survey)
        modelContext.insert(survey)
        try? modelContext.save()
    }
}

#endif
