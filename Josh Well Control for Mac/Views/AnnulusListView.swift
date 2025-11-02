//
//  AnnulusListView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//

// AnnulusListView.swift
import SwiftUI
import SwiftData

struct AnnulusListView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState
    @State private var newName = "13-3/8\" × 5\""
    @State private var selection: AnnulusSection?
    @State private var activeSection: AnnulusSection?

    private var sortedSections: [AnnulusSection] {
        project.annulus.sorted { a, b in a.topDepth_m < b.topDepth_m }
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
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sec.name)
                                    .font(.headline)
                                // Gap warning (if any)
                                let prevBottom = index > 0 ? sortedSections[index - 1].bottomDepth_m : nil
                                if let prevBottom, sec.topDepth_m > prevBottom {
                                    Text("Gap above: \(sec.topDepth_m - prevBottom, format: .number) m")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                                Text("Top: \(sec.topDepth_m, format: .number.precision(.fractionLength(2))) m   Bottom: \(sec.bottomDepth_m, format: .number.precision(.fractionLength(2))) m   Length: \(sec.length_m, format: .number.precision(.fractionLength(2))) m   Ann Cap: \(annularCapacity_m3(sec), format: .number.precision(.fractionLength(1))) m³ (\(annularCapacityPerM_m3perm(sec), format: .number.precision(.fractionLength(5))) m³/m)   OH Cap: \(openHoleCapacity_m3(sec), format: .number.precision(.fractionLength(1))) m³ (\(openHoleCapacityPerM_m3perm(sec), format: .number.precision(.fractionLength(5))) m³/m)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                    Button { add() } label: {
                        Label("Add", systemImage: "plus")
                            .labelStyle(.iconOnly)
                    }
                }
                .padding()
            }
            .navigationTitle("Annulus")
            .toolbar {
                if hasGaps {
                    ToolbarItemGroup {
                        Button("Fill Gaps") { fillGaps() }
                            .help("Extend previous section to remove gaps up to the next section")
                    }
                }
            }
            .navigationDestination(item: $activeSection) { sec in
                AnnulusDetailView(section: sec)
            }
        }
    }

    private func annularCapacityPerM_m3perm(_ s: AnnulusSection) -> Double {
        let id = max(s.innerDiameter_m, 0)
        let od = max(s.outerDiameter_m, 0)
        let area = max(0, (.pi * (id*id - od*od) / 4.0))
        return area
    }

    private func annularCapacity_m3(_ s: AnnulusSection) -> Double {
        return annularCapacityPerM_m3perm(s) * max(s.length_m, 0)
    }

    private func openHoleCapacityPerM_m3perm(_ s: AnnulusSection) -> Double {
        let id = max(s.innerDiameter_m, 0)
        return .pi * pow(id, 2) / 4.0
    }

    private func openHoleCapacity_m3(_ s: AnnulusSection) -> Double {
        return openHoleCapacityPerM_m3perm(s) * max(s.length_m, 0)
    }

    private func add() {
        let nextTop = project.annulus.map { $0.bottomDepth_m }.max() ?? 0
        let s = AnnulusSection(
            name: newName,
            topDepth_m: nextTop,
            length_m: 100,
            innerDiameter_m: 0.216,
            outerDiameter_m: 0.127
        )
        s.project = project
        project.annulus.append(s)
        try? modelContext.save()
        newName = "New Section"
    }

    private func delete(_ section: AnnulusSection) {
        if let i = project.annulus.firstIndex(where: { $0.id == section.id }) {
            project.annulus.remove(at: i)
        }
        modelContext.delete(section)
        try? modelContext.save()
    }

    private func deleteSelected() {
        guard let sel = selection else { return }
        delete(sel)
        selection = nil
    }

    private func navigateToDetail(for section: AnnulusSection) {
        activeSection = section
    }

    private func fillGaps() {
        let secs = sortedSections
        guard secs.count > 1 else { return }
        for i in 1..<secs.count {
            let prev = secs[i - 1]
            let curr = secs[i]
            let gap = curr.topDepth_m - prev.bottomDepth_m
            if gap > 0 { prev.length_m += gap }
        }
        try? modelContext.save()
    }
}

struct AnnulusDetailView: View {
    @Bindable var section: AnnulusSection

    var body: some View {
        ScrollView {
            Form {
                        Section { TextField("Name", text: $section.name) }
                        Section("Placement (m)") {
                            TextField("Top MD", value: $section.topDepth_m, format: .number)
                                .onChange(of: section.topDepth_m) { enforceNoOverlap(for: section) }
                            TextField("Length", value: $section.length_m, format: .number)
                                .onChange(of: section.length_m) { enforceNoOverlap(for: section) }
                            Text("Bottom MD: \(section.bottomDepth_m, format: .number)")
                        }
                        Section("Geometry (m)") {
                            TextField("Casing/WB ID", value: $section.innerDiameter_m, format: .number)
                            TextField("String OD", value: $section.outerDiameter_m, format: .number)
                            Text("Flow area: \(section.flowArea_m2, format: .number.precision(.fractionLength(5))) m²")
                            Text("De: \(section.equivalentDiameter_m, format: .number.precision(.fractionLength(4))) m")
                        }
                        Section("Fluid") {
                            Picker("Rheology", selection: $section.rheologyModelRaw) {
                                Text("Newtonian").tag(AnnulusSection.RheologyModel.newtonian.rawValue)
                                Text("Bingham").tag(AnnulusSection.RheologyModel.bingham.rawValue)
                                Text("Power Law").tag(AnnulusSection.RheologyModel.powerLaw.rawValue)
                                Text("Herschel–Bulkley").tag(AnnulusSection.RheologyModel.herschelBulkley.rawValue)
                            }
                            TextField("Density (kg/m³)", value: $section.density_kg_per_m3, format: .number)
                            Group {
                                TextField("μ (Pa·s)", value: $section.dynamicViscosity_Pa_s, format: .number)
                                TextField("PV (Pa·s)", value: $section.pv_Pa_s, format: .number)
                                TextField("YP (Pa)", value: $section.yp_Pa, format: .number)
                                TextField("n (–)", value: $section.n_powerLaw, format: .number)
                                TextField("k (Pa·sⁿ)", value: $section.k_powerLaw_Pa_s_n, format: .number)
                                TextField("τ₀ (Pa)", value: $section.hb_tau0_Pa, format: .number)
                                TextField("n (HB –)", value: $section.hb_n, format: .number)
                                TextField("k (HB Pa·sⁿ)", value: $section.hb_k_Pa_s_n, format: .number)
                            }
                        }
                    }
        }
        .onAppear { enforceNoOverlap(for: section) }
        .navigationTitle(section.name)
    }

    private func enforceNoOverlap(for current: AnnulusSection) {
        guard let project = current.project else { return }
        let others = project.annulus.filter { $0.id != current.id }.sorted { $0.topDepth_m < $1.topDepth_m }
        let prev = others.last { $0.topDepth_m <= current.topDepth_m }
        let next = others.first { $0.topDepth_m >= current.topDepth_m }
        if let prev, current.topDepth_m < prev.bottomDepth_m { current.topDepth_m = prev.bottomDepth_m }
        if current.length_m < 0 { current.length_m = 0 }
        if let next {
            let maxLen = max(0, next.topDepth_m - current.topDepth_m)
            if current.length_m > maxLen { current.length_m = maxLen }
        }
    }
}


#if DEBUG
import SwiftData

#Preview("Annulus – Sample Data") {
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

        let a1 = AnnulusSection(name: "13-3/8\" × 5\"", topDepth_m: 0, length_m: 300, innerDiameter_m: 0.340, outerDiameter_m: 0.127)
        let a2 = AnnulusSection(name: "9-5/8\" × 5\"", topDepth_m: 300, length_m: 600, innerDiameter_m: 0.244, outerDiameter_m: 0.127)
        let a3 = AnnulusSection(name: "8-1/2\" Open Hole × 5\"", topDepth_m: 900, length_m: 400, innerDiameter_m: 0.216, outerDiameter_m: 0.127)
        [a1, a2, a3].forEach { sec in
            sec.project = project
            project.annulus.append(sec)
            context.insert(sec)
        }
        try? context.save()

        return AnnulusListView(project: project)
            .modelContainer(container)
            .frame(width: 720, height: 460)
    } catch {
        return Text("Preview failed: \\ (error.localizedDescription)")
    }
}
#endif
