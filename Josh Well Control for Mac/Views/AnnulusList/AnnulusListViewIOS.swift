//
//  AnnulusListViewIOS.swift
//  Josh Well Control for Mac
//
//  iOS-optimized annulus list view with touch-friendly interactions
//

#if os(iOS)
import SwiftUI
import SwiftData

struct AnnulusListViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    let project: ProjectState
    @State private var viewmodel: AnnulusListView.ViewModel
    @State private var showingAddSheet = false

    init(project: ProjectState) {
        self.project = project
        _viewmodel = State(initialValue: AnnulusListView.ViewModel(project: project))
    }

    var body: some View {
        List {
            ForEach(Array(viewmodel.sortedSections.enumerated()), id: \.element.id) { index, sec in
                NavigationLink {
                    AnnulusDetailViewIOS(section: sec)
                } label: {
                    AnnulusSectionRow(
                        section: sec,
                        prevBottom: index > 0 ? viewmodel.sortedSections[index - 1].bottomDepth_m : nil,
                        viewmodel: viewmodel
                    )
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewmodel.delete(sec)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Annulus")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }

            if viewmodel.hasGaps {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fill Gaps") {
                        viewmodel.fillGaps()
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddAnnulusSectionSheet(viewmodel: viewmodel, isPresented: $showingAddSheet)
        }
        .onAppear {
            viewmodel.attach(context: modelContext)
            viewmodel.refreshIfNeeded()
        }
    }
}

// MARK: - Section Row

private struct AnnulusSectionRow: View {
    let section: AnnulusSection
    let prevBottom: Double?
    let viewmodel: AnnulusListView.ViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: section.isCased ? "pipe.and.drop" : "circle.dotted")
                    .foregroundColor(section.isCased ? .blue : .orange)

                Text(section.name)
                    .font(.headline)

                Text(section.isCased ? "(Cased)" : "(Open)")
                    .font(.caption)
                    .foregroundStyle(section.isCased ? .blue : .orange)
            }

            // Gap warning
            if let prevBottom, section.topDepth_m > prevBottom {
                Label("Gap: \(section.topDepth_m - prevBottom, format: .number) m", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Details
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Top: \(section.topDepth_m, format: .number) m")
                    Text("Bottom: \(section.bottomDepth_m, format: .number) m")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("ID: \(section.innerDiameter_m * 1000, format: .number) mm")
                    Text("Length: \(section.length_m, format: .number) m")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Section Sheet

private struct AddAnnulusSectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewmodel: AnnulusListView.ViewModel
    @Binding var isPresented: Bool
    @State private var name = "New Section"

    var body: some View {
        NavigationStack {
            Form {
                TextField("Section Name", text: $name)
            }
            .navigationTitle("Add Section")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        viewmodel.newName = name
                        viewmodel.add()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

// MARK: - Detail View

struct AnnulusDetailViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var section: AnnulusSection

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Name", text: $section.name)

                Toggle("Cased Hole", isOn: $section.isCased)
            }

            Section("Placement") {
                HStack {
                    Text("Top MD")
                    Spacer()
                    TextField("Top", value: $section.topDepth_m, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("m")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Length")
                    Spacer()
                    TextField("Length", value: $section.length_m, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("m")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Bottom MD")
                    Spacer()
                    Text("\(section.bottomDepth_m, format: .number) m")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Geometry") {
                HStack {
                    Text("Inner Diameter")
                    Spacer()
                    TextField("ID", value: $section.innerDiameter_m, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("m")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Calculated") {
                HStack {
                    Text("Open Hole Capacity")
                    Spacer()
                    Text(String(format: "%.3f m³", openHoleCapacity))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Capacity/m")
                    Spacer()
                    Text(String(format: "%.5f m³/m", capacityPerM))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(section.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var openHoleCapacity: Double {
        let id = max(section.innerDiameter_m, 0)
        return .pi * pow(id, 2) / 4.0 * max(section.length_m, 0)
    }

    private var capacityPerM: Double {
        let id = max(section.innerDiameter_m, 0)
        return .pi * pow(id, 2) / 4.0
    }
}

#endif
