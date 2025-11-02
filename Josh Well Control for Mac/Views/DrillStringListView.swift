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

    private var sortedSections: [DrillStringSection] {
        project.drillString.sorted { a, b in a.topDepth_m < b.topDepth_m }
    }

    private var hasGaps: Bool {
        let secs = sortedSections
        guard secs.count > 1 else { return false }
        for i in 1..<secs.count {
            if secs[i].topDepth_m > secs[i - 1].bottomDepth_m { return true }
        }
        return false
    }

    var body: some View {
        NavigationStack {
            VStack {
                List(selection: $selection) {
                    ForEach(Array(sortedSections.enumerated()), id: \.element.id) { index, sec in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(sec.name)")
                                Text("Top: \(sec.topDepth_m, format: .number.precision(.fractionLength(2))) m   Bottom: \(sec.bottomDepth_m, format: .number.precision(.fractionLength(2))) m Length: \(sec.length_m, format: .number.precision(.fractionLength(2))) m   Cap: \(sectionCapacity_m3(sec), format: .number.precision(.fractionLength(1))) m³ (\(sectionCapacityPerM_m3perm(sec), format: .number.precision(.fractionLength(5))) m³/m)   Disp: \(sectionDisplacement_m3(sec), format: .number.precision(.fractionLength(1))) m³ (\(sectionDisplacementPerM_m3perm(sec), format: .number.precision(.fractionLength(5))) m³/m)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                let prevBottom = index > 0 ? sortedSections[index - 1].bottomDepth_m : nil
                                if let prevBottom, sec.topDepth_m > prevBottom {
                                    Text("Gap above: \(sec.topDepth_m - prevBottom, format: .number) m")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                            Spacer()
                            HStack(spacing: 8) {
                                Button("Edit") { navigateToDetail(for: sec) }
                                    .buttonStyle(.borderless)
                                    .controlSize(.small)
                                    .help("Open details")
                                Button(role: .destructive) { delete(sec) } label: {
                                    Label("Delete", systemImage: "trash").labelStyle(.iconOnly)
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
                        let items = idx.map { sortedSections[$0] }
                        items.forEach { delete($0) }
                    }
                }
                HStack {
                    TextField("New section name", text: $newName).textFieldStyle(.roundedBorder)
                    Button {
                        add()
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
                .padding()
            }
            .navigationTitle("Drill String")
            .toolbar {
                if hasGaps {
                    ToolbarItemGroup {
                        Button("Fill Gaps") { fillGaps() }
                            .help("Extend previous section to remove gaps up to the next section")
                    }
                }
            }
            .navigationDestination(item: $activeSection) { sec in
                DrillStringDetailView(section: sec)
            }
        }
    }

    private func add() {
        // Compute next available top as the max bottom among sections
        let nextTop = project.drillString.map { $0.bottomDepth_m }.max() ?? 0
        let s = DrillStringSection(
            name: newName,
            topDepth_m: nextTop,
            length_m: 100,
            outerDiameter_m: 0.127,
            innerDiameter_m: 0.0953
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

    private func fillGaps() {
        let sections = sortedSections
        guard sections.count > 1 else { return }
        for i in 1..<sections.count {
            let prev = sections[i - 1]
            let curr = sections[i]
            let gap = curr.topDepth_m - prev.bottomDepth_m
            if gap > 0 { prev.length_m += gap }
        }
        try? modelContext.save()
    }

    private func sectionCapacity_m3(_ s: DrillStringSection) -> Double {
        let id = max(s.innerDiameter_m, 0)
        let L = max(s.length_m, 0)
        return .pi * pow(id, 2) / 4.0 * L
    }
    private func sectionDisplacement_m3(_ s: DrillStringSection) -> Double {
        let od = max(s.outerDiameter_m, 0)
        let L = max(s.length_m, 0)
        return .pi * pow(od, 2) / 4.0 * L
    }
    private func sectionCapacityPerM_m3perm(_ s: DrillStringSection) -> Double {
        let id = max(s.innerDiameter_m, 0)
        return .pi * pow(id, 2) / 4.0
    }
    private func sectionDisplacementPerM_m3perm(_ s: DrillStringSection) -> Double {
        let od = max(s.outerDiameter_m, 0)
        return .pi * pow(od, 2) / 4.0
    }
}

struct DrillStringDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var section: DrillStringSection

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $section.name)
            }
            Section("Placement (m)") {
                TextField("Top MD", value: $section.topDepth_m, format: .number)
                    .onChange(of: section.topDepth_m) { enforceNoOverlap(for: section) }
                TextField("Length", value: $section.length_m, format: .number)
                    .onChange(of: section.length_m) { enforceNoOverlap(for: section) }
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
        .onAppear { enforceNoOverlap(for: section) }
    }

    private func enforceNoOverlap(for current: DrillStringSection) {
        guard let project = current.project else { return }
        // Sort others by top depth
        let others = project.drillString.filter { $0.id != current.id }.sorted { $0.topDepth_m < $1.topDepth_m }
        // Find neighbors
        let prev = others.last { $0.topDepth_m <= current.topDepth_m }
        let next = others.first { $0.topDepth_m >= current.topDepth_m && $0.id != current.id }

        // Clamp top to not cross previous bottom
        if let prev, current.topDepth_m < prev.bottomDepth_m { current.topDepth_m = prev.bottomDepth_m }
        // Ensure positive length
        if current.length_m < 0 { current.length_m = 0 }
        // Clamp length so bottom doesn't cross next top
        if let next {
            let maxLen = max(0, next.topDepth_m - current.topDepth_m)
            if current.length_m > maxLen { current.length_m = maxLen }
        }
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
