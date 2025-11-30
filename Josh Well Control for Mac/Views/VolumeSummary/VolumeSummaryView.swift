//
//  VolumeSummaryView.swift
//  Josh Well Control for Mac
//
//  Displays project-wide volume totals including drill string and annulus volumes.

import SwiftUI
import SwiftData

struct VolumeSummaryView: View {
    @Environment(\.modelContext) private var modelContext
    let project: ProjectState
    @State private var viewmodel: ViewModel

    init(project: ProjectState) {
        self.project = project
        _viewmodel = State(initialValue: ViewModel(project: project))
    }

    var body: some View {
        let totals = viewmodel.computeTotals()

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                WellSection(title: "Volume Summary", icon: "cube.box.fill", subtitle: "Holistic drill string and annulus volumes pulled from your geometry.") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                        MetricCard(title: "Drill String Capacity", value: "\(viewmodel.fmt3(totals.dsCapacity_m3)) m³", caption: "Inner fluid capacity", icon: "internaldrive")
                        MetricCard(title: "Drill String Displacement", value: "\(viewmodel.fmt3(totals.dsDisplacement_m3)) m³", caption: "Steel displacement", icon: "shippingbox")
                        MetricCard(title: "Wet Displacement", value: "\(viewmodel.fmt3(totals.dsWet_m3)) m³", caption: "Capacity + displacement", icon: "drop")
                        MetricCard(title: "Annulus w/ pipe", value: "\(viewmodel.fmt3(totals.annularWithPipe_m3)) m³", caption: "Pipe-in-hole volume", icon: "circle.grid.cross")
                        MetricCard(title: "Open hole", value: "\(viewmodel.fmt3(totals.openHole_m3)) m³", caption: "Casing/formation capacity", icon: "ruler")
                    }
                }

                if !totals.slices.isEmpty {
                    WellSection(title: "Depth Breakdown", icon: "chart.bar.fill", subtitle: "Intervals formed by string + annulus overlaps.") {
                        let slices = totals.slices
                        VStack(spacing: 10) {
                            HStack {
                                Text("Depth Range (m)")
                                Spacer()
                                Text("Area • Volume")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            ForEach(Array(slices.enumerated()), id: \.element.id) { idx, s in
                                HStack {
                                    Text("\(viewmodel.fmt0(s.top))–\(viewmodel.fmt0(s.bottom))")
                                        .frame(width: 160, alignment: .leading)
                                    Spacer()
                                    Text("\(viewmodel.fmt3(s.area_m2)) m²  •  \(viewmodel.fmt3(s.volume_m3)) m³")
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                if idx < slices.count - 1 {
                                    Divider()
                                        .opacity(0.15)
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

private struct VolumeSlice: Identifiable {
    let id = UUID()
    let top: Double
    let bottom: Double
    let area_m2: Double
    var length: Double { bottom - top }
    var volume_m3: Double { area_m2 * length }
}

private struct VolumeTotals {
    let dsCapacity_m3: Double
    let dsDisplacement_m3: Double
    let dsWet_m3: Double
    let annularWithPipe_m3: Double
    let openHole_m3: Double
    let slices: [VolumeSlice]
}

extension VolumeSummaryView {
    @Observable
    class ViewModel {
        var project: ProjectState
        init(project: ProjectState) { self.project = project }

        fileprivate func computeTotals() -> VolumeTotals {
            let dsCapacity = (project.drillString ?? []).reduce(0.0) { $0 + (.pi * pow(max($1.innerDiameter_m, 0), 2) / 4.0) * max($1.length_m, 0) }
            let dsDisplacement = (project.drillString ?? []).reduce(0.0) { $0 + (.pi * (pow(max($1.outerDiameter_m, 0), 2) - pow(max($1.innerDiameter_m, 0), 2) ) / 4.0) * max($1.length_m, 0) }
            let dsWet = dsCapacity + dsDisplacement
            let openHole = (project.annulus ?? []).reduce(0.0) { $0 + (.pi * pow(max($1.innerDiameter_m, 0), 2) / 4.0) * max($1.length_m, 0) }
            let slices = buildAnnularSlices()
            let annularWithPipe = slices.reduce(0.0) { $0 + $1.volume_m3 }
            return VolumeTotals(dsCapacity_m3: dsCapacity, dsDisplacement_m3: dsDisplacement, dsWet_m3: dsWet, annularWithPipe_m3: annularWithPipe, openHole_m3: openHole, slices: slices)
        }

        private func buildAnnularSlices() -> [VolumeSlice] {
            var boundaries = Set<Double>()
            for a in (project.annulus ?? []) { boundaries.insert(a.topDepth_m); boundaries.insert(a.bottomDepth_m) }
            for d in (project.drillString ?? []) { boundaries.insert(d.topDepth_m); boundaries.insert(d.bottomDepth_m) }
            let sorted = boundaries.sorted()
            guard sorted.count > 1 else { return [] }

            func annulusAt(_ t: Double, _ b: Double) -> AnnulusSection? { (project.annulus ?? []).first { $0.topDepth_m <= t && $0.bottomDepth_m >= b } }
            func stringAt(_ t: Double, _ b: Double) -> DrillStringSection? { (project.drillString ?? []).first { $0.topDepth_m <= t && $0.bottomDepth_m >= b } }

            var slices: [VolumeSlice] = []
            for i in 0..<(sorted.count - 1) {
                let top = sorted[i]
                let bottom = sorted[i + 1]
                guard bottom > top else { continue }
                if let annulus = annulusAt(top, bottom) {
                    let id = max(annulus.innerDiameter_m, 0)
                    let od = max(stringAt(top, bottom)?.outerDiameter_m ?? 0, 0)
                    let area = max(0, .pi * (id * id - od * od) / 4.0)
                    slices.append(VolumeSlice(top: top, bottom: bottom, area_m2: area))
                }
            }
            return slices
        }

        func fmt0(_ v: Double) -> String { String(format: "%.0f", v) }
        func fmt3(_ v: Double) -> String { String(format: "%.3f", v) }
    }
}

#if DEBUG
private struct VolumeSummaryPreview: View {
    let container: ModelContainer
    let project: ProjectState

    init() {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.container = try! ModelContainer(
            for: ProjectState.self,
                 DrillStringSection.self,
                 AnnulusSection.self,
            configurations: config
        )
        let ctx = container.mainContext
        let p = ProjectState()
        ctx.insert(p)
        let a1 = AnnulusSection(name: "Surface Hole", topDepth_m: 0, length_m: 600, innerDiameter_m: 0.340, outerDiameter_m: 0.244)
        let a2 = AnnulusSection(name: "Intermediate", topDepth_m: 700, length_m: 300, innerDiameter_m: 0.244, outerDiameter_m: 0.1778)
        p.annulus = (p.annulus ?? []) + [a1, a2]
        let d1 = DrillStringSection(name: "Drill Pipe", topDepth_m: 0, length_m: 1000, outerDiameter_m: 0.127, innerDiameter_m: 0.0953)
        p.drillString = (p.drillString ?? []) + [d1]
        try? ctx.save()
        self.project = p
    }

    var body: some View {
        VolumeSummaryView(project: project)
            .modelContainer(container)
            .frame(width: 850, height: 600)
    }
}

#Preview("Volume Summary – Sample Data") {
    VolumeSummaryPreview()
}
#endif

