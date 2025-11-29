//
//  PressureWindowView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//

import SwiftUI
import SwiftData

struct PressureWindowView: View {
    @Environment(\.modelContext) private var modelContext
    let project: ProjectState
    @State private var viewmodel: ViewModel
    @FocusState private var focusedPoint: PressureWindowPoint.ID?

    init(project: ProjectState) {
        self.project = project
        _viewmodel = State(initialValue: ViewModel(project: project))
    }

    private var pageBackgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .underPageBackgroundColor)
        #else
        Color(.systemGroupedBackground)
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                WellSection(
                    title: "Pressure Envelope",
                    icon: "waveform.path.ecg",
                    subtitle: "Track pore & fracture gradients versus TVD."
                ) {
                    if viewmodel.points.isEmpty {
                        Text("No reference points yet. Use the form below to seed pore/frac pairs.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 12) {
                            headerRow
                            ForEach(viewmodel.points) { point in
                                PressurePointRow(
                                    point: point,
                                    eqDensityString: viewmodel.eqDensityString,
                                    focus: $focusedPoint,
                                    onDelete: { viewmodel.deleteRow(point) }
                                )
                            }
                        }
                    }
                }

                WellSection(
                    title: "Add Reference Point",
                    icon: "plus.circle.fill",
                    subtitle: "Seed a pore/frac pair at a target TVD."
                ) {
                    addRowForm
                }
            }
            .padding(24)
        }
        .background(pageBackgroundColor)
        .navigationTitle("Pressure Window")
        .onAppear { viewmodel.attach(context: modelContext) }
    }

    private var headerRow: some View {
        HStack {
            Text("TVD (m)")
                .frame(width: 120, alignment: .leading)
            Text("Pore (kPa) • ρ_eq (kg/m³)")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Frac (kPa) • ρ_eq (kg/m³)")
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer().frame(width: 64)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var addRowForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("TVD (m)")
                        .frame(width: 140, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    TextField("TVD (m)", value: $viewmodel.newDepth, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .monospacedDigit()
                }
                GridRow {
                    Text("Pore (kPa)")
                        .frame(width: 140, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    TextField("Pore (kPa)", value: $viewmodel.newPore, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .monospacedDigit()
                }
                GridRow {
                    Text("Frac (kPa)")
                        .frame(width: 140, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    TextField("Frac (kPa)", value: $viewmodel.newFrac, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .monospacedDigit()
                }
            }

            Button {
                viewmodel.addRow()
            } label: {
                Label("Add Point", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct PressurePointRow: View {
    @Bindable var point: PressureWindowPoint
    let eqDensityString: (Double?, Double) -> String
    let focus: FocusState<PressureWindowPoint.ID?>.Binding
    let onDelete: () -> Void

    private var cardBackgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemBackground)
        #endif
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("TVD \(point.depth_m, format: .number)")
                .monospacedDigit()
                .frame(width: 120, alignment: .leading)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Pore (kPa)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(
                    "Pore (kPa)",
                    value: optionalBinding(\PressureWindowPoint.pore_kPa),
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .focused(focus, equals: point.id)
                Text("ρ_eq: \(eqDensityString(point.pore_kPa, point.depth_m)) kg/m³")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Frac (kPa)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(
                    "Frac (kPa)",
                    value: optionalBinding(\PressureWindowPoint.frac_kPa),
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                Text("ρ_eq: \(eqDensityString(point.frac_kPa, point.depth_m)) kg/m³")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            VStack(spacing: 8) {
                Button {
                    focus.wrappedValue = point.id
                } label: {
                    Label("Focus", systemImage: "pencil")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Focus pore pressure field")

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.gray.opacity(0.25))
        )
    }

    private func optionalBinding(_ keyPath: ReferenceWritableKeyPath<PressureWindowPoint, Double?>) -> Binding<Double> {
        Binding(
            get: { point[keyPath: keyPath] ?? 0 },
            set: { point[keyPath: keyPath] = $0 }
        )
    }
}

extension PressureWindowView {
    @Observable
    class ViewModel {
        var project: ProjectState
        var newDepth: Double = 1000.0
        var newPore: Double = 11000.0
        var newFrac: Double = 17000.0
        private var context: ModelContext?

        init(project: ProjectState) { self.project = project }
        func attach(context: ModelContext) { self.context = context }

        var points: [PressureWindowPoint] {
            project.window.points.sorted { $0.depth_m < $1.depth_m }
        }

        func addRow() {
            let r = PressureWindowPoint(depth_m: newDepth, pore_kPa: newPore, frac_kPa: newFrac)
            r.window = project.window
            project.window.points.append(r)
            try? context?.save()
        }

        func deleteRow(_ row: PressureWindowPoint) {
            context?.delete(row)
            try? context?.save()
        }

        func eqDensityString(pressure_kPa: Double?, tvd_m: Double) -> String {
            guard let p = pressure_kPa, tvd_m > 0 else { return "—" }
            let rho = (p * 1000.0) / (9.80665 * tvd_m)
            return String(format: "%.0f", rho)
        }
    }
}

#if DEBUG
private struct PressureWindowPreview: View {
    let container: ModelContainer
    let project: ProjectState

    init() {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.container = try! ModelContainer(
            for: ProjectState.self,
                 PressureWindow.self,
                 PressureWindowPoint.self,
            configurations: config
        )
        let context = container.mainContext
        let p = ProjectState()
        context.insert(p)
        let w = p.window
        let seed: [PressureWindowPoint] = [
            .init(depth_m: 500,  pore_kPa: 6000,  frac_kPa: 11000, window: w),
            .init(depth_m: 1000, pore_kPa: 12000, frac_kPa: 18000, window: w),
            .init(depth_m: 1500, pore_kPa: 17500, frac_kPa: 26000, window: w)
        ]
        seed.forEach { context.insert($0) }
        try? context.save()
        self.project = p
    }

    var body: some View {
        NavigationStack {
            PressureWindowView(project: project)
                .navigationTitle("Pressure Window")
        }
        .modelContainer(container)
        .frame(width: 900, height: 500)
    }
}

#Preview("Pressure Window – Sample Data") {
    PressureWindowPreview()
}
#endif
