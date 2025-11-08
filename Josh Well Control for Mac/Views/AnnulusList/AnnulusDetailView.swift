//
//  AnnulusDetailView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-08.
//

import SwiftUI
import SwiftData

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
                            Text("String OD is auto-calculated from overlapping drill string sections")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
