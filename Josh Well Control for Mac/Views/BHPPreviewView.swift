//
//  BHPPreviewView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//


import SwiftUI

struct BHPPreviewView: View {
    @Bindable var project: ProjectState
    @State private var tvd: Double = 1500
    @State private var flowRate_m3_min: Double = 0.03
    @State private var mu_app: Double = 0.02
    @State private var sbp_kPa: Double = 200

    @State private var tvdUI: Double = 1500
    @State private var flowRateUI_m3_min: Double = 0.03
    @State private var muUI_app: Double = 0.02
    @State private var sbpUI_kPa: Double = 200

    // Cached display states
    @State private var bhpDisplay_kPa: Double = 0
    @State private var withinWindow: Bool? = nil
    @State private var poreDisplay_kPa: Double? = nil
    @State private var fracDisplay_kPa: Double? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            // Left: Inputs
            VStack(alignment: .leading, spacing: 12) {
                Text("Inputs").font(.headline)

                // TVD
                HStack {
                    Text("TVD (m)")
                    Spacer()
                    Text("\(Int(tvdUI))").monospacedDigit().frame(width: 60, alignment: .trailing)
                }
                Slider(
                    value: $tvdUI,
                    in: 0...3000,
                    step: 10,
                    label: { EmptyView() },
                    minimumValueLabel: { Text("0") },
                    maximumValueLabel: { Text("3000") },
                    onEditingChanged: { editing in if !editing { tvd = tvdUI } }
                )

                // Flow
                HStack {
                    Text("Flow (m³/min)")
                    Spacer()
                    Text("\(flowRateUI_m3_min, format: .number.precision(.fractionLength(2)))")
                        .monospacedDigit().frame(width: 60, alignment: .trailing)
                }
                Slider(
                    value: $flowRateUI_m3_min,
                    in: 0...3.5,
                    step: 0.05,
                    label: { EmptyView() },
                    minimumValueLabel: { Text("0") },
                    maximumValueLabel: { Text("3.50") },
                    onEditingChanged: { editing in if !editing { flowRate_m3_min = flowRateUI_m3_min } }
                )

                // Apparent viscosity
                HStack {
                    Text("μ_app (Pa·s)")
                    Spacer()
                    Text("\(muUI_app, format: .number.precision(.fractionLength(2)))")
                        .monospacedDigit().frame(width: 60, alignment: .trailing)
                }
                Slider(
                    value: $muUI_app,
                    in: 0...10,
                    step: 0.1,
                    label: { EmptyView() },
                    minimumValueLabel: { Text("0") },
                    maximumValueLabel: { Text("10") },
                    onEditingChanged: { editing in if !editing { mu_app = muUI_app } }
                )

                // Standpipe back pressure
                HStack {
                    Text("SABP (kPa)")
                    Spacer()
                    Text("\(Int(sbpUI_kPa))").monospacedDigit().frame(width: 60, alignment: .trailing)
                }
                Slider(
                    value: $sbpUI_kPa,
                    in: 0...7500,
                    step: 1,
                    label: { EmptyView() },
                    minimumValueLabel: { Text("0") },
                    maximumValueLabel: { Text("7500") },
                    onEditingChanged: { editing in if !editing { sbp_kPa = sbpUI_kPa } }
                )
            }
            .frame(width: 420)

            Divider()

            // Right: Results
            VStack(alignment: .leading, spacing: 8) {
                Text("Result").font(.headline)
                Text("BHP @ \(Int(tvd)) m")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(bhpDisplay_kPa, format: .number.precision(.fractionLength(1))) kPa")
                    .font(.title2)
                    .monospacedDigit()

                if let within = withinWindow {
                    if within {
                        Text("Within window ✅").foregroundStyle(.green)
                    } else {
                        Text("Outside window ⚠️").foregroundStyle(.orange)
                        if let p = poreDisplay_kPa, let f = fracDisplay_kPa {
                            if bhpDisplay_kPa < p {
                                Text("Increase flow rate or increase back pressure.")
                                    .foregroundStyle(.yellow)
                            } else if bhpDisplay_kPa > f {
                                Text("Reduce flow rate or reduce back pressure.")
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }
                }
                if let p = poreDisplay_kPa { Text("Pore: \(p, format: .number) kPa").monospacedDigit() }
                if let f = fracDisplay_kPa { Text("Frac: \(f, format: .number) kPa").monospacedDigit() }
                Spacer()
            }
            .frame(width: 360, alignment: .leading)
            .transaction { t in t.disablesAnimations = true }
            .animation(nil, value: withinWindow)
            .animation(nil, value: bhpDisplay_kPa)
        }
        .padding(16)
        .onAppear {
            tvdUI = tvd
            flowRateUI_m3_min = flowRate_m3_min
            muUI_app = mu_app
            sbpUI_kPa = sbp_kPa
            recompute()
        }
        .onChange(of: tvd) { recompute() }
        .onChange(of: flowRate_m3_min) { recompute() }
        .onChange(of: mu_app) { recompute() }
        .onChange(of: sbp_kPa) { recompute() }
        .navigationTitle("BHP Preview")
    }

    private func recompute() {
        let fluids = demoFluidStack()
        let ann = project.annulus.map { s in
            SimpleAnnLike(
                topTVD_m: s.topDepth_m,
                bottomTVD_m: s.bottomDepth_m,
                innerDiameter_m: s.innerDiameter_m,
                outerDiameter_m: s.outerDiameter_m,
                roughness_m: s.wallRoughness_m,
                density_kg_per_m3: s.density_kg_per_m3
            )
        }
        let bhp = HydraulicsCalculator.bhp_kPa(
            tvd_m: tvd,
            fluidSegments: fluids,
            annulusSections: ann,
            flowRate_m3_per_s: max(flowRate_m3_min, 0) / 60.0,
            apparentViscosity_Pa_s: max(mu_app, 1e-6),
            sbp_kPa: max(sbp_kPa, 0)
        )
        bhpDisplay_kPa = bhp

        let safe = HydraulicsCalculator.isSafe(tvd_m: tvd, bhp_kPa: bhp, window: project.window)
        withinWindow = safe.within
        poreDisplay_kPa = safe.pore_kPa
        fracDisplay_kPa = safe.frac_kPa
    }

    /// Demo stack until you wire SlugPlan & caps into segments.
    private func demoFluidStack() -> [(Double, Double, Double)] {
        // surface→800 m light cap, 800→TVD base mud
        let cap = (0.0, min(800.0, tvd), 950.0)
        let base = (min(800.0, tvd), tvd, 1200.0)
        return [cap, base]
    }
}

private struct SimpleAnnLike: AnnulusSectionLike {
    var topTVD_m: Double
    var bottomTVD_m: Double
    var innerDiameter_m: Double
    var outerDiameter_m: Double
    var roughness_m: Double
    var density_kg_per_m3: Double
}

#if DEBUG
import SwiftData

#Preview("BHP Preview – Sample Data") {
    do {
        // In‑memory container for previews
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

        // Seed data
        let context = container.mainContext
        let project = ProjectState()
        context.insert(project)

        // Annulus sections to test hydraulics
        let a1 = AnnulusSection(name: "13-3/8\" × 5\"", topDepth_m: 0, length_m: 300, innerDiameter_m: 0.340, outerDiameter_m: 0.127)
        a1.wallRoughness_m = 0.000045
        a1.density_kg_per_m3 = 1200
        let a2 = AnnulusSection(name: "9-5/8\" × 5\"", topDepth_m: 300, length_m: 600, innerDiameter_m: 0.244, outerDiameter_m: 0.127)
        a2.wallRoughness_m = 0.000045
        a2.density_kg_per_m3 = 1200
        let a3 = AnnulusSection(name: "8-1/2\" Open Hole × 5\"", topDepth_m: 900, length_m: 900, innerDiameter_m: 0.216, outerDiameter_m: 0.127)
        a3.wallRoughness_m = 0.000045
        a3.density_kg_per_m3 = 1200
        [a1, a2, a3].forEach { sec in
            sec.project = project
            if project.annulus == nil { project.annulus = [] }
            project.annulus?.append(sec)
            context.insert(sec)
        }

        // Pressure window points for safety check
        let w = project.window
        [
            PressureWindowPoint(depth_m: 500,  pore_kPa: 6000,  frac_kPa: 11000, window: w),
            PressureWindowPoint(depth_m: 1000, pore_kPa: 12000, frac_kPa: 18000, window: w),
            PressureWindowPoint(depth_m: 1500, pore_kPa: 17500, frac_kPa: 26000, window: w)
        ].forEach { context.insert($0) }

        try? context.save()

        NavigationStack {
            BHPPreviewView(project: project)
                .navigationTitle("BHP Preview")
        }
        .modelContainer(container)
        .frame(width: 700, height: 520)
    } catch {
        Text("Preview failed: \(error.localizedDescription)")
    }
}
#endif
