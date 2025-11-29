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

    @State private var viewmodel = SwabbingViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                GroupBox(label: Label("Inputs", systemImage: "slider.horizontal.3")) {
                    inputs
                }
                if let est = viewmodel.estimate {
                    GroupBox(label: Label("Results", systemImage: "gauge")) {
                        results(est)
                    }
                }
                GroupBox(label: Label("Cumulative Swab vs Depth", systemImage: "chart.xyaxis.line")) {
                    HStack {
                        Picker("X‑axis", selection: $viewmodel.axisDirection) {
                            ForEach(SwabbingViewModel.AxisDirection.allCases) { d in Text(d.rawValue).tag(d) }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 320)
                        Spacer()
                        Button { viewmodel.compute(project: project, layers: allFinalLayers) } label: {
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
        .onAppear {
            viewmodel.syncBitDepth(to: project)
            viewmodel.preloadDefaults()
            viewmodel.compute(project: project, layers: allFinalLayers)
        }
        .onChange(of: viewmodel.bitMD_m) { viewmodel.compute(project: project, layers: allFinalLayers) }
        .onChange(of: viewmodel.theta600) { viewmodel.compute(project: project, layers: allFinalLayers) }
        .onChange(of: viewmodel.theta300) { viewmodel.compute(project: project, layers: allFinalLayers) }
        .onChange(of: viewmodel.hoistSpeed_mpermin) { viewmodel.compute(project: project, layers: allFinalLayers) }
        .onChange(of: viewmodel.eccentricityFactor) { viewmodel.compute(project: project, layers: allFinalLayers) }
        .onChange(of: viewmodel.step_m) { viewmodel.compute(project: project, layers: allFinalLayers) }
        .onChange(of: allFinalLayers) { viewmodel.compute(project: project, layers: allFinalLayers) }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up")
                .font(.title3)
            Text("Swab (POOH): uses final layers; rheology from mud checks when linked, else 600/300 fallback")
                .foregroundStyle(.secondary)
            Text(viewmodel.rheologyBadgeText)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(viewmodel.rheologyBadgeTint.opacity(0.15)))
                .overlay(Capsule().stroke(viewmodel.rheologyBadgeTint.opacity(0.35)))
                .foregroundStyle(viewmodel.rheologyBadgeTint)
            Spacer()
        }
    }

    private var inputs: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow {
                labeledField("Bit MD (m)") {
                    HStack(spacing: 4) {
                        TextField("Bit MD", value: $viewmodel.bitMD_m, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Stepper("", value: $viewmodel.bitMD_m, in: 0...100_000, step: 0.1)
                            .labelsHidden()
                            .frame(width: 20)
                    }
                }
                labeledField("Step (m)") {
                    HStack(spacing: 4) {
                        TextField("Step", value: $viewmodel.step_m, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Stepper("", value: $viewmodel.step_m, in: 0.5...50, step: 0.5)
                            .labelsHidden()
                            .frame(width: 20)
                    }
                }
                labeledField("Hoist speed (m/min)") {
                    HStack(spacing: 4) {
                        TextField("m/min", value: $viewmodel.hoistSpeed_mpermin, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Stepper("", value: $viewmodel.hoistSpeed_mpermin, in: 0...60, step: 0.5)
                            .labelsHidden()
                            .frame(width: 20)
                    }
                }
                labeledField("Eccentricity ×") {
                    HStack(spacing: 4) {
                        TextField("×", value: $viewmodel.eccentricityFactor, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Stepper("", value: $viewmodel.eccentricityFactor, in: 1.0...2.0, step: 0.05)
                            .labelsHidden()
                            .frame(width: 20)
                    }
                }
                labeledField("θ600") {
                    HStack(spacing: 4) {
                        TextField("600", value: $viewmodel.theta600, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                        Stepper("", value: $viewmodel.theta600, in: 1...200, step: 1)
                            .labelsHidden()
                            .frame(width: 20)
                    }
                }
                labeledField("θ300") {
                    HStack(spacing: 4) {
                        TextField("300", value: $viewmodel.theta300, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                        Stepper("", value: $viewmodel.theta300, in: 1...200, step: 1)
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
            if let prof = viewmodel.estimate?.profile, !prof.isEmpty {
                let xLabel = "Measured Depth (m)"
                Chart(prof.sorted { $0.MD_m < $1.MD_m }) { seg in
                    let xVal = viewmodel.axisDirection == .shallowToDeep ? seg.MD_m : max(viewmodel.bitMD_m - seg.MD_m, 0)
                    LineMark(
                        x: .value(xLabel, xVal),
                        y: .value("Cum kPa", seg.CumSwab_kPa)
                    )
                }
                .chartXScale(domain: 0...max(viewmodel.bitMD_m, 1))
                .chartXAxis {
                    if viewmodel.axisDirection == .shallowToDeep {
                        AxisMarks(values: .automatic(desiredCount: 6)) { value in
                            if let v = value.as(Double.self) {
                                // We plot x as distance-from-bit (0 at bit, max at surface). Show MD labels reversed.
                                let md = max(viewmodel.bitMD_m - v, 0)
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


#if DEBUG
private struct SwabbingPreview: View {
    let container: ModelContainer
    let project: ProjectState

    init() {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.container = try! ModelContainer(
            for: ProjectState.self,
                 DrillStringSection.self,
                 AnnulusSection.self,
                 FinalFluidLayer.self,
            configurations: config
        )
        let ctx = container.mainContext
        let p = ProjectState()
        ctx.insert(p)
        // Seed a simple layer so the preview chart can run
        ctx.insert(FinalFluidLayer(project: p, name: "Mud", placement: .annulus, topMD_m: 0, bottomMD_m: 3000, density_kgm3: 1260, color: .yellow))
        try? ctx.save()
        self.project = p
    }

    var body: some View {
        NavigationStack {
            SwabbingView(project: project)
        }
        .modelContainer(container)
        .frame(width: 900, height: 600)
    }
}

#Preview("Swabbing – Sample Data") {
    SwabbingPreview()
}
#endif
// ViewModel now in: ViewModels/SwabbingViewModel.swift
