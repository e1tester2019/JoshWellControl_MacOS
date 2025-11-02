//
//  DrillStringListView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//


// DrillStringListView.swift
import SwiftUI
import SwiftData

struct DrillStringListView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState
    @State private var isAdding = false
    @State private var newName = "5\" DP"
    @State private var selection: DrillStringSection?
    @State private var activeSection: DrillStringSection?

    var body: some View {
        NavigationStack {
            VStack {
                List(selection: $selection) {
                    ForEach(project.drillString) { sec in
                        HStack {
                            Text(sec.name)
                            Spacer()
                            HStack(spacing: 8) {
                                Button("Edit") {
                                    navigateToDetail(for: sec)
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                                .help("Open details")

                                Button(role: .destructive) {
                                    delete(sec)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                        .labelStyle(.iconOnly)
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                                .help("Delete this section")
                            }
                        }
                        .contentShape(Rectangle())
                        .tag(sec)
                    }
                    .onDelete { idx in
                        let items = idx.map { project.drillString[$0] }
                        project.drillString.remove(atOffsets: idx)
                        items.forEach { modelContext.delete($0) }
                        try? modelContext.save()
                    }
                }
                HStack {
                    TextField("New section name", text: $newName).textFieldStyle(.roundedBorder)
                    Button {
                        add()
                    } label: {
                        Label("Add", systemImage: "plus")
                            .labelStyle(.iconOnly)
                    }
                }
                .padding()
            }
            .navigationTitle("Drill String")
            .navigationDestination(item: $activeSection) { sec in
                DrillStringDetailView(section: sec)
            }
        }
    }

    private func add() {
        let s = DrillStringSection(
            name: newName,
            topDepth_m: 0, length_m: 100,
            outerDiameter_m: 0.127, innerDiameter_m: 0.0953
        )
        s.project = project
        project.drillString.append(s)
        try? modelContext.save()
        newName = "New Section"
    }

    private func delete(_ section: DrillStringSection) {
        if let i = project.drillString.firstIndex(where: { $0.id == section.id }) {
            project.drillString.remove(at: i)
        }
        modelContext.delete(section)
        try? modelContext.save()
    }

    private func deleteSelected() {
        guard let sel = selection else { return }
        delete(sel)
        selection = nil
        // Clear selection after deletion
    }

    private func navigateToDetail(for section: DrillStringSection) {
        activeSection = section
    }
}

struct DrillStringDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var section: DrillStringSection

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Name", text: $section.name)
            }
            Section("Placement (m)") {
                TextField("Top MD", value: $section.topDepth_m, format: .number)
                TextField("Length", value: $section.length_m, format: .number)
                Text("Bottom MD: \(section.bottomDepth_m, format: .number)")
            }
            Section("Geometry (m)") {
                TextField("OD", value: $section.outerDiameter_m, format: .number)
                TextField("ID", value: $section.innerDiameter_m, format: .number)
                TextField("Tool joint OD", value: Binding<Double>(
                    get: { section.toolJointOD_m ?? 0.0 },
                    set: { section.toolJointOD_m = $0 }
                ), format: .number)
                TextField("Joint length", value: $section.jointLength_m, format: .number)
            }
            Section("Mechanics") {
                TextField("Grade", text: Binding<String>(
                    get: { section.grade ?? "" },
                    set: { section.grade = $0.isEmpty ? nil : $0 }
                ))
                Text("Weight in air (kDaN/m): \(section.weightAir_kDaN_per_m, format: .number.precision(.fractionLength(3)))")
            }
        }
        .navigationTitle(section.name)
    }
}

#if DEBUG
import SwiftData

#Preview("Drill String – Sample Data") {
    do {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ProjectState.self,
                 DrillStringSection.self,
                 AnnulusSection.self,
                 PressureWindow.self,
                 PressureWindowPoint.self,
                 SlugPlan.self,
                 SlugStep.self,
                 BackfillPlan.self,
                 BackfillRule.self,
                 TripSettings.self,
                 SwabInput.self,
                 SurveyStation.self,
            configurations: config
        )

        let context = container.mainContext
        let project = ProjectState()
        context.insert(project)

        let s1 = DrillStringSection(name: "5\" DP", topDepth_m: 0, length_m: 500, outerDiameter_m: 0.127, innerDiameter_m: 0.0953)
        let s2 = DrillStringSection(name: "5\" HWDP", topDepth_m: 500, length_m: 100, outerDiameter_m: 0.127, innerDiameter_m: 0.0953)
        let s3 = DrillStringSection(name: "6-1/2\" Collar", topDepth_m: 600, length_m: 90, outerDiameter_m: 0.165, innerDiameter_m: 0.070)
        [s1, s2, s3].forEach { sec in
            sec.project = project
            project.drillString.append(sec)
            context.insert(sec)
        }
        try? context.save()

        return NavigationStack {
            DrillStringListView(project: project)
        }
        .modelContainer(container)
        .frame(width: 700, height: 450)
    } catch {
        return Text("Preview failed: \(error.localizedDescription)")
    }
}
#endif
