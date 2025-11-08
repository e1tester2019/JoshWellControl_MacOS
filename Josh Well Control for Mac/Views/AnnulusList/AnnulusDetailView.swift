//
//  AnnulusDetailView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-08.
//

import SwiftUI
import SwiftData

struct AnnulusDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var section: AnnulusSection

    // MARK: - Derived (with overlapping drill string)
    private var assumedOD_m: Double {
        guard let project = section.project else { return 0 }
        let top = section.topDepth_m
        let bottom = section.bottomDepth_m
        var maxOD = 0.0
        for d in project.drillString where d.bottomDepth_m > top && d.topDepth_m < bottom {
            maxOD = max(maxOD, d.outerDiameter_m)
        }
        return maxOD
    }

    private var flowAreaWithPipe_m2: Double {
        let id = max(section.innerDiameter_m, 0)
        let od = max(assumedOD_m, 0)
        guard id > od else { return 0 }
        return .pi * 0.25 * (id*id - od*od)
    }

    private var equivalentDeWithPipe_m: Double {
        let id = max(section.innerDiameter_m, 0)
        let od = max(assumedOD_m, 0)
        return max(id - od, 0)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Identity") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Name")
                                .frame(width: 160, alignment: .trailing)
                                .foregroundStyle(.secondary)
                            TextField("Name", text: $section.name)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(8)
                }

                GroupBox("Placement (m)") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Top MD")
                                .frame(width: 160, alignment: .trailing)
                                .foregroundStyle(.secondary)
                            TextField("Top MD", value: $section.topDepth_m, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .monospacedDigit()
                                .onChange(of: section.topDepth_m) { enforceNoOverlap(for: section) }
                        }
                        GridRow {
                            Text("Length")
                                .frame(width: 160, alignment: .trailing)
                                .foregroundStyle(.secondary)
                            TextField("Length", value: $section.length_m, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .monospacedDigit()
                                .onChange(of: section.length_m) { enforceNoOverlap(for: section) }
                        }
                        GridRow {
                            Text("Bottom MD")
                                .frame(width: 160, alignment: .trailing)
                                .foregroundStyle(.secondary)
                            Text("\(section.bottomDepth_m, format: .number)")
                                .monospacedDigit()
                        }
                    }
                    .padding(8)
                }

                GroupBox("Geometry (m)") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Casing/WB ID")
                                .frame(width: 160, alignment: .trailing)
                                .foregroundStyle(.secondary)
                            TextField("ID", value: $section.innerDiameter_m, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .monospacedDigit()
                        }
                        GridRow {
                            Text("Flow area (with pipe)")
                                .frame(width: 160, alignment: .trailing)
                                .foregroundStyle(.secondary)
                            Text("\(flowAreaWithPipe_m2, format: .number.precision(.fractionLength(5))) m²")
                                .monospacedDigit()
                        }
                        GridRow {
                            Text("Equivalent De")
                                .frame(width: 160, alignment: .trailing)
                                .foregroundStyle(.secondary)
                            Text("\(equivalentDeWithPipe_m, format: .number.precision(.fractionLength(4))) m")
                                .monospacedDigit()
                        }
                        GridRow {
                            Text("")
                                .frame(width: 160, alignment: .trailing)
                            Text(assumedOD_m > 0 ? "Assuming string OD = \(assumedOD_m, format: .number.precision(.fractionLength(4))) m (max in interval)" : "No string inside this interval")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                }

                GroupBox("Fluids") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Fluids, rheology, and densities are configured in **Pump Schedule**.")
                        Text("This section uses those fluids at runtime.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .padding(8)
                }
            }
            .padding(16)
        }
        .onAppear { enforceNoOverlap(for: section) }
        .navigationTitle(section.name)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
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
