//
//  DrillStringListViewIOS.swift
//  Josh Well Control for Mac
//
//  iOS-optimized drill string list view with touch-friendly interactions
//

#if os(iOS)
import SwiftUI
import SwiftData

struct DrillStringListViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    let project: ProjectState
    @State private var viewmodel: DrillStringListView.ViewModel
    @State private var showingAddSheet = false

    init(project: ProjectState) {
        self.project = project
        _viewmodel = State(initialValue: DrillStringListView.ViewModel(project: project))
    }

    var body: some View {
        List {
            ForEach(Array(viewmodel.sortedSections.enumerated()), id: \.element.id) { index, sec in
                NavigationLink {
                    DrillStringDetailViewIOS(section: sec)
                } label: {
                    DrillStringSectionRow(
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
        .navigationTitle("Drill String")
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
            AddDrillStringSectionSheet(viewmodel: viewmodel, isPresented: $showingAddSheet)
        }
        .onAppear {
            viewmodel.attach(context: modelContext)
        }
        .onChange(of: project) { _, newProject in
            viewmodel.project = newProject
        }
    }
}

// MARK: - Section Row

private struct DrillStringSectionRow: View {
    let section: DrillStringSection
    let prevBottom: Double?
    let viewmodel: DrillStringListView.ViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.name)
                .font(.headline)

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
                    Text("OD: \(section.outerDiameter_m * 1000, format: .number) mm")
                    Text("ID: \(section.innerDiameter_m * 1000, format: .number) mm")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Section Sheet

private struct AddDrillStringSectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewmodel: DrillStringListView.ViewModel
    @Binding var isPresented: Bool
    @State private var name = "5\" DP"

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

struct DrillStringDetailViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var section: DrillStringSection

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Name", text: $section.name)
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
                    Text("Outer Diameter")
                    Spacer()
                    TextField("OD", value: $section.outerDiameter_m, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("m")
                        .foregroundStyle(.secondary)
                }

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

                HStack {
                    Text("Tool Joint OD")
                    Spacer()
                    TextField("TJ OD", value: Binding(
                        get: { section.toolJointOD_m ?? 0 },
                        set: { section.toolJointOD_m = $0 }
                    ), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    Text("m")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Joint Length")
                    Spacer()
                    TextField("Joint", value: $section.jointLength_m, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("m")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Calculated") {
                HStack {
                    Text("Capacity")
                    Spacer()
                    Text(String(format: "%.3f m³", capacity))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Displacement")
                    Spacer()
                    Text(String(format: "%.3f m³", displacement))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Weight in Air")
                    Spacer()
                    Text(String(format: "%.3f kDaN/m", section.weightAir_kDaN_per_m))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Grade") {
                TextField("Grade", text: Binding(
                    get: { section.grade ?? "" },
                    set: { section.grade = $0.isEmpty ? nil : $0 }
                ))
            }
        }
        .navigationTitle(section.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var capacity: Double {
        let id = max(section.innerDiameter_m, 0)
        return .pi * pow(id, 2) / 4.0 * max(section.length_m, 0)
    }

    private var displacement: Double {
        let od = max(section.outerDiameter_m, 0)
        return .pi * pow(od, 2) / 4.0 * max(section.length_m, 0)
    }
}

#endif
