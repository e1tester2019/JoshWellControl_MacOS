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
    @Environment(\.dismiss) private var dismiss
    @Bindable var section: DrillStringSection
    
    @State private var showTotals = false
    @State private var capField: Double = 0 // in m^3 per chosen mode
    @State private var wetField: Double = 0
    @State private var isSyncing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Identity") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Name").frame(width: 140, alignment: .trailing).foregroundStyle(.secondary)
                            TextField("Name", text: $section.name)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(8)
                }

                GroupBox("Placement (m)") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Top MD").frame(width: 140, alignment: .trailing).foregroundStyle(.secondary)
                            TextField("Top MD", value: $section.topDepth_m, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .monospacedDigit()
                                .onChange(of: section.topDepth_m) { _, _ in enforceNoOverlap(for: section) }
                        }
                        GridRow {
                            Text("Length").frame(width: 140, alignment: .trailing).foregroundStyle(.secondary)
                            TextField("Length", value: $section.length_m, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .monospacedDigit()
                                .onChange(of: section.length_m) { _, _ in enforceNoOverlap(for: section) }
                        }
                        GridRow {
                            Text("Bottom MD").frame(width: 140, alignment: .trailing).foregroundStyle(.secondary)
                            Text("\(section.bottomDepth_m, format: .number)")
                                .monospacedDigit()
                        }
                    }
                    .padding(8)
                }

                GroupBox("Geometry (m)") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("OD").frame(width: 140, alignment: .trailing).foregroundStyle(.secondary)
                            TextField("OD", value: $section.outerDiameter_m, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .monospacedDigit()
                        }
                        GridRow {
                            Text("ID").frame(width: 140, alignment: .trailing).foregroundStyle(.secondary)
                            TextField("ID", value: $section.innerDiameter_m, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .monospacedDigit()
                        }
                        GridRow {
                            Text("Tool joint OD").frame(width: 140, alignment: .trailing).foregroundStyle(.secondary)
                            TextField("Tool joint OD", value: Binding<Double>(
                                get: { section.toolJointOD_m ?? 0.0 },
                                set: { section.toolJointOD_m = $0 }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .monospacedDigit()
                        }
                        GridRow {
                            Text("Joint length").frame(width: 140, alignment: .trailing).foregroundStyle(.secondary)
                            TextField("Joint length", value: $section.jointLength_m, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .monospacedDigit()
                        }
                    }
                    .padding(8)
                }

                GroupBox("Hydraulics & Displacements") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Toggle("Show totals (× Length)", isOn: $showTotals)
                                .toggleStyle(.switch)
                                .gridCellColumns(2)
                        }
                        GridRow {
                            Text("Capacity")
                                .frame(width: 140, alignment: .trailing)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                TextField(showTotals ? "m³" : "m³/m", value: $capField, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .monospacedDigit()
                                    .onChange(of: capField) { _ in updateGeometryFromFields() }
                                Text(showTotals ? "m³" : "m³/m").foregroundStyle(.secondary)
                            }
                        }
                        GridRow {
                            Text("Wet displacement")
                                .frame(width: 140, alignment: .trailing)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                TextField(showTotals ? "m³" : "m³/m", value: $wetField, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .monospacedDigit()
                                    .onChange(of: wetField) { _ in updateGeometryFromFields() }
                                Text(showTotals ? "m³" : "m³/m").foregroundStyle(.secondary)
                            }
                        }
                        GridRow {
                            Text("Steel displacement")
                                .frame(width: 140, alignment: .trailing)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Text("\(steelDisplay, format: .number)")
                                    .monospacedDigit()
                                Text(showTotals ? "m³" : "m³/m").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(8)
                }

                GroupBox("Mechanics") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Grade").frame(width: 140, alignment: .trailing).foregroundStyle(.secondary)
                            TextField("Grade", text: Binding<String>(
                                get: { section.grade ?? "" },
                                set: { section.grade = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Weight in air (kDaN/m)").frame(width: 140, alignment: .trailing).foregroundStyle(.secondary)
                            Text("\(section.weightAir_kDaN_per_m, format: .number.precision(.fractionLength(3)))")
                                .monospacedDigit()
                        }
                    }
                    .padding(8)
                }
            }
            .padding(16)
            .onAppear { updateFieldsFromGeometry() }
            .onChange(of: section.innerDiameter_m) { _, _ in updateFieldsFromGeometry() }
            .onChange(of: section.outerDiameter_m) { _, _ in updateFieldsFromGeometry() }
            .onChange(of: section.length_m) { _, _ in updateFieldsFromGeometry() }
            .onChange(of: showTotals) { _, _ in updateFieldsFromGeometry() }
        }
        .navigationTitle(section.name)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
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
    func areaFromDiameter(_ d: Double) -> Double { .pi * d * d / 4 }
    func diameterFromArea(_ a: Double) -> Double { a <= 0 ? 0 : sqrt(4 * a / .pi) }
    var capPerM: Double { areaFromDiameter(section.innerDiameter_m) }
    var wetPerM: Double { areaFromDiameter(section.outerDiameter_m) }
    var steelPerM: Double { max(0, wetPerM - capPerM) }
    var factor: Double { showTotals ? max(0, section.length_m) : 1 }
    var capDisplay: Double { capPerM * factor }
    var wetDisplay: Double { wetPerM * factor }
    var steelDisplay: Double { steelPerM * factor }

    private func updateFieldsFromGeometry() {
        guard !isSyncing else { return }
        isSyncing = true
        let cap = capDisplay
        let wet = wetDisplay
        capField = cap.isFinite ? max(0, cap) : 0
        wetField = wet.isFinite ? max(0, wet) : 0
        isSyncing = false
    }

    private func updateGeometryFromFields() {
        guard !isSyncing else { return }
        isSyncing = true
        // Convert displayed values back to per‑meter
        let f = max(1e-12, factor)
        let capPerMInput = max(0, capField / f)
        let wetPerMInput = max(0, wetField / f)
        // Back‑solve diameters
        var newID = diameterFromArea(capPerMInput)
        var newOD = diameterFromArea(wetPerMInput)
        if newOD < newID { newOD = newID }
        // Apply
        section.innerDiameter_m = newID.isFinite ? newID : section.innerDiameter_m
        section.outerDiameter_m = newOD.isFinite ? newOD : section.outerDiameter_m
        isSyncing = false
    }
}
