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

    var body: some View {
        NavigationStack {
            VStack {
                List(selection: $selection) {
                    ForEach(project.annulus) { sec in
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
                        let items = idx.map { project.annulus[$0] }
                        project.annulus.remove(atOffsets: idx)
                        items.forEach { modelContext.delete($0) }
                        try? modelContext.save()
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
            .navigationDestination(item: $activeSection) { sec in
                AnnulusDetailView(section: sec)
            }
        }
    }

    private func add() {
        let s = AnnulusSection(
            name: newName,
            topDepth_m: 0, length_m: 100,
            innerDiameter_m: 0.216, // 8.5 in
            outerDiameter_m: 0.127  // 5 in DP
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
}

struct AnnulusDetailView: View {
    @Bindable var section: AnnulusSection

    var body: some View {
        ScrollView {
            Form {
                        Section { TextField("Name", text: $section.name) }
                        Section("Placement (m)") {
                            TextField("Top MD", value: $section.topDepth_m, format: .number)
                            TextField("Length", value: $section.length_m, format: .number)
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
        
        .navigationTitle(section.name)
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
