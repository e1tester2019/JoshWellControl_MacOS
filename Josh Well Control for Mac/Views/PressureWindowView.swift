//
//  PressureWindowView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//


// PressureWindowView.swift
import SwiftUI
import SwiftData

struct PressureWindowView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState
    @State private var newDepth = 1000.0
    @State private var newPore = 11000.0
    @State private var newFrac = 17000.0
    @State private var selection = Set<PressureWindowPoint.ID>()
    @FocusState private var focusedPoint: PressureWindowPoint.ID?

    var body: some View {
        VStack {
            List(selection: $selection) {
                Section {
                    ForEach(project.window.points) { row in
                        HStack(alignment: .firstTextBaseline) {
                            Text("TVD \(row.depth_m, format: .number)")
                                .frame(width: 120, alignment: .leading)

                            // Pore column
                            VStack(alignment: .leading, spacing: 4) {
                                TextField(
                                    "Pore (kPa)",
                                    value: Binding<Double>(
                                        get: { row.pore_kPa ?? 0 },
                                        set: { row.pore_kPa = $0 }
                                    ),
                                    format: .number
                                )
                                .focused($focusedPoint, equals: row.id)

                                Text("ρ_eq: \(eqDensityString(pressure_kPa: row.pore_kPa, tvd_m: row.depth_m)) kg/m³")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            // Frac column
                            VStack(alignment: .leading, spacing: 4) {
                                TextField(
                                    "Frac (kPa)",
                                    value: Binding<Double>(
                                        get: { row.frac_kPa ?? 0 },
                                        set: { row.frac_kPa = $0 }
                                    ),
                                    format: .number
                                )
                                Text("ρ_eq: \(eqDensityString(pressure_kPa: row.frac_kPa, tvd_m: row.depth_m)) kg/m³")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Spacer()

                            // Inline row actions
                            HStack(spacing: 8) {
                                Button("Edit") {
                                    focusedPoint = row.id
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                                .help("Focus pore pressure field")

                                Button(role: .destructive) {
                                    deleteRow(row)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                        .labelStyle(.iconOnly)
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                                .help("Delete this row")
                            }
                        }
                    }
                    .onDelete(perform: deleteRows)
                } header: {
                    HStack {
                        Text("TVD (m)")
                            .frame(width: 120, alignment: .leading)
                        Text("Pore (kPa) • ρ_eq (kg/m³)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Frac (kPa) • ρ_eq (kg/m³)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
                }
            }
            HStack {
                Text("TVD (m)")
                    .frame(width: 120, alignment: .trailing)
                TextField("TVD (m)", value: $newDepth, format: .number)
                Spacer()
                Text("Pore (kPa)")
                    .frame(width: 120, alignment: .trailing)
                TextField("Pore (kPa)", value: $newPore, format: .number)
                Spacer()
                Text("Frac (kPa)")
                    .frame(width: 120, alignment: .trailing)
                TextField("Frac (kPa)", value: $newFrac, format: .number)
                Spacer()
                Button{ addRow() } label: {
                    Label("Add", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
            }
            .padding()
        }
        .navigationTitle("Pressure Window")
        .onDeleteCommand { deleteSelection() }
    }

    private func addRow() {
        let r = PressureWindowPoint(depth_m: newDepth, pore_kPa: newPore, frac_kPa: newFrac)
        r.window = project.window
        project.window.points.append(r)
        try? modelContext.save()
    }

    private func deleteRows(_ offsets: IndexSet) {
        offsets
            .map { project.window.points[$0] }
            .forEach { modelContext.delete($0) }
        try? modelContext.save()
    }

    private func deleteRow(_ row: PressureWindowPoint) {
        modelContext.delete(row)
        try? modelContext.save()
    }

    private func deleteSelection() {
        let toDelete = project.window.points.filter { selection.contains($0.id) }
        toDelete.forEach { modelContext.delete($0) }
        selection.removeAll()
        try? modelContext.save()
    }

    private func eqDensityString(pressure_kPa: Double?, tvd_m: Double) -> String {
        guard let p = pressure_kPa, tvd_m > 0 else { return "—" }
        let rho = (p * 1000.0) / (9.80665 * tvd_m)
        return String(format: "%.0f", rho)
    }
}

#if DEBUG
import SwiftData

#Preview("Pressure Window – Sample Data") {
    do {
        // In-memory SwiftData container for previews
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

        // Seed a project and a few pressure window rows
        let context = container.mainContext
        let project = ProjectState()
        context.insert(project)

        let w = project.window
        let seed: [PressureWindowPoint] = [
            .init(depth_m: 500,  pore_kPa: 6000,  frac_kPa: 11000, window: w),
            .init(depth_m: 1000, pore_kPa: 12000, frac_kPa: 18000, window: w),
            .init(depth_m: 1500, pore_kPa: 17500, frac_kPa: 26000, window: w)
        ]
        seed.forEach { context.insert($0) }
        try? context.save()

        return NavigationStack {
            PressureWindowView(project: project)
                .navigationTitle("Pressure Window")
        }
        .modelContainer(container)
        .frame(width: 900, height: 500)
    } catch {
        return Text("Preview failed: \(error.localizedDescription)")
    }
}
#endif
