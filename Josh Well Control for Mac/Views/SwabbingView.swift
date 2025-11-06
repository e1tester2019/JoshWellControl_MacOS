//
//  SwabbingView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-06.
//

import SwiftUI
import SwiftData
import Charts

struct SwabbingView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState

    // Persisted final layers for this project
    @Query private var allFinalLayers: [FinalFluidLayer]

    // Inputs (focused on swab only)
    @State private var bitMD_m: Double = 4000
    @State private var theta600: Double = 60
    @State private var theta300: Double = 40
    @State private var hoistSpeed_mpermin: Double = 10      // m/min
    @State private var eccentricityFactor: Double = 1.2     // multiplier ≥ 1
    @State private var step_m: Double = 5                   // integration step (m)
    enum AxisDirection: String, CaseIterable, Identifiable { case shallowToDeep = "Shallow→Deep", deepToShallow = "Deep→Shallow"; var id: String { rawValue } }
    @State private var axisDirection: AxisDirection = .deepToShallow

    // Outputs
    @State private var estimate: SwabEstimate? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    GroupBox(label: Label("Inputs", systemImage: "slider.horizontal.3")) {
                        inputs
                    }
                    if let est = estimate {
                        GroupBox(label: Label("Results", systemImage: "gauge")) {
                            results(est)
                        }
                    }
                    GroupBox(label: Label("Cumulative Swab vs Depth", systemImage: "chart.xyaxis.line")) {
                        HStack {
                            Picker("X‑axis", selection: $axisDirection) {
                                ForEach(AxisDirection.allCases) { d in Text(d.rawValue).tag(d) }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 320)
                            Spacer()
                            Button(action: compute) {
                                Label("Compute", systemImage: "play.fill")
                            }
                            .keyboardShortcut(.return)
                        }
                        .padding(.bottom, 8)
                        chart
                    }
                }
                .padding(16)
            }
            .onAppear(perform: preloadDefaults)
            .onChange(of: bitMD_m) { compute() }
            .onChange(of: theta600) { compute() }
            .onChange(of: theta300) { compute() }
            .onChange(of: hoistSpeed_mpermin) { compute() }
            .onChange(of: eccentricityFactor) { compute() }
            .onChange(of: step_m) { compute() }
            .navigationTitle("Swabbing")
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up")
                .font(.title3)
            Text("Swab (POOH): integrates from surface to bit using project geometry & final layers")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var inputs: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow {
                labeledField("Bit MD (m)") {
                    HStack(spacing: 4) {
                        TextField("Bit MD", value: $bitMD_m, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Stepper("", value: $bitMD_m, in: 0...100_000, step: 0.1)
                            .labelsHidden()
                            .frame(width: 20)
                    }
                }
                labeledField("Step (m)") {
                    HStack(spacing: 4) {
                        TextField("Step", value: $step_m, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Stepper("", value: $step_m, in: 0.5...50, step: 0.5)
                            .labelsHidden()
                            .frame(width: 20)
                    }
                }
                labeledField("Hoist speed (m/min)") {
                    HStack(spacing: 4) {
                        TextField("m/min", value: $hoistSpeed_mpermin, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Stepper("", value: $hoistSpeed_mpermin, in: 0...60, step: 0.5)
                            .labelsHidden()
                            .frame(width: 20)
                    }
                }
                labeledField("Eccentricity ×") {
                    HStack(spacing: 4) {
                        TextField("×", value: $eccentricityFactor, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Stepper("", value: $eccentricityFactor, in: 1.0...2.0, step: 0.05)
                            .labelsHidden()
                            .frame(width: 20)
                    }
                }
                labeledField("θ600") {
                    HStack(spacing: 4) {
                        TextField("600", value: $theta600, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                        Stepper("", value: $theta600, in: 1...200, step: 1)
                            .labelsHidden()
                            .frame(width: 20)
                    }
                }
                labeledField("θ300") {
                    HStack(spacing: 4) {
                        TextField("300", value: $theta300, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                        Stepper("", value: $theta300, in: 1...200, step: 1)
                            .labelsHidden()
                            .frame(width: 20)
                    }
                }
                Spacer().gridCellColumns(2)
            }
        }
    }

    private func results(_ est: SwabEstimate) -> some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow {
                resultBox(title: "Total swab", value: est.totalSwab_kPa, unit: "kPa")
                resultBox(title: "Recommended SABP", value: est.recommendedSABP_kPa, unit: "kPa")
                resultBox(title: "Non‑laminar flag", valueText: est.nonLaminarFlag ? "YES" : "No", tint: est.nonLaminarFlag ? .orange : .secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var chart: some View {
        Group {
            if let prof = estimate?.profile, !prof.isEmpty {
                let xLabel = "Measured Depth (m)"
                Chart(prof.sorted { $0.MD_m < $1.MD_m }) { seg in
                    let xVal = axisDirection == .shallowToDeep ? seg.MD_m : max(bitMD_m - seg.MD_m, 0)
                    LineMark(
                        x: .value(xLabel, xVal),
                        y: .value("Cum kPa", seg.CumSwab_kPa)
                    )
                }
                .chartXScale(domain: 0...max(bitMD_m, 1))
                .chartXAxis {
                    if axisDirection == .shallowToDeep {
                        AxisMarks(values: .automatic(desiredCount: 6)) { value in
                            if let v = value.as(Double.self) {
                                // We plot x as distance-from-bit (0 at bit, max at surface). Show MD labels reversed.
                                let md = max(bitMD_m - v, 0)
                                AxisGridLine()
                                AxisTick()
                                AxisValueLabel("\(Int(md))")
                            }
                        }
                    } else {
                        AxisMarks()
                    }
                }
                .chartYAxisLabel("Cum swab (kPa)")
                .chartXAxisLabel(xLabel)
                .frame(minHeight: 380)
                .padding(.top, 8)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.05))
                    VStack(spacing: 6) {
                        Image(systemName: "chart.xyaxis.line")
                            .foregroundStyle(.secondary)
                        Text("No profile yet. Click Compute to run swab.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 220)
            }
        }
    }

    // MARK: - Actions

    private func compute() {
        // Collect layers for this project
        let layers = allFinalLayers.filter { $0.project === project }
        // Geometry with pipe present down to the bit
        let geom = ProjectGeometryService(project: project, currentStringBottomMD: bitMD_m)
        // Build DTOs above the bit only
        let dto = LayerResolver.slice(layers,
                                      for: project,
                                      domain: .swabAboveBit,
                                      bitMD: bitMD_m,
                                      lowerLimitMD: 0)
        do {
            let calc = SwabCalculator() // uses defaults unless injected
            let est = try calc.estimateFromLayersPowerLaw(
                layers: dto,
                theta600: theta600,
                theta300: theta300,
                hoistSpeed_mpermin: hoistSpeed_mpermin,
                eccentricityFactor: eccentricityFactor,
                step_m: step_m,
                geom: geom,
                traj: nil,
                sabpSafety: 1.15
            )
            self.estimate = est
        } catch {
            self.estimate = nil
        }
    }

    private func preloadDefaults() {
        // If project has a max depth or similar, you could initialize bitMD here.
        if bitMD_m <= 0 { bitMD_m = 1000 }
    }

    // MARK: - UI helpers

    @ViewBuilder private func labeledField(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .trailing)
            content()
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private func resultBox(title: String, value: Double, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(Int(round(value))) \(unit)")
                .font(.title3).monospacedDigit()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))
    }

    @ViewBuilder private func resultBox(title: String, valueText: String, tint: Color = .secondary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(valueText)
                .font(.title3).monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))
    }
}

#Preview {
    do {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ProjectState.self,
                 DrillStringSection.self,
                 AnnulusSection.self,
                 FinalFluidLayer.self,
            configurations: config
        )
        let ctx = container.mainContext
        let project = ProjectState()
        ctx.insert(project)
        // Seed a simple layer so the preview chart can run
        ctx.insert(FinalFluidLayer(project: project, name: "Mud", placement: .annulus, topMD_m: 0, bottomMD_m: 3000, density_kgm3: 1260, color: .yellow))
        try? ctx.save()
        return NavigationStack {
            SwabbingView(project: project)
        }.modelContainer(container).frame(width: 900, height: 600)
    } catch {
        return Text("Preview failed: \(error.localizedDescription)")
    }
}
