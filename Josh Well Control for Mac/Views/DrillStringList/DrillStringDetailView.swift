//
//  DrillStringDetailView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-08.
//
import SwiftUI
import SwiftData

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
