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
            VStack(alignment: .leading, spacing: 16) {
                Text("Volume Summary").font(.title2).bold()

                // Adaptive grid of summary boxes
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                    VolumeBox(title: "Drill String Capacity", value: totals.dsCapacity_m3, caption: "Inner fluid capacity volume (m³)", fmt3: viewmodel.fmt3)
                    VolumeBox(title: "Drill String Displacement", value: totals.dsDisplacement_m3, caption: "Metal displacement volume (m³)", fmt3: viewmodel.fmt3)
                    VolumeBox(title: "Wet Displacement", value: totals.dsWet_m3, caption: "Capacity + Displacement (m³)", fmt3: viewmodel.fmt3)
                    VolumeBox(title: "Annular Volume (with pipe)", value: totals.annularWithPipe_m3, caption: "Annulus volume accounting for drill string (m³)", fmt3: viewmodel.fmt3)
                    VolumeBox(title: "Open Hole Volume (no pipe)", value: totals.openHole_m3, caption: "Annulus/casing capacity ignoring pipe (m³)", fmt3: viewmodel.fmt3)
                }
                .padding(.top, 4)

                if !totals.slices.isEmpty {
                    Divider()
                    Text("Depth Breakdown").font(.headline)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(totals.slices) { s in
                            HStack {
                                Text("\(viewmodel.fmt0(s.top))–\(viewmodel.fmt0(s.bottom)) m")
                                    .frame(width: 180, alignment: .leading)
                                Text("Area: \(viewmodel.fmt3(s.area_m2)) m²  Volume: \(viewmodel.fmt3(s.volume_m3)) m³")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding()
        }
    }
}

private struct VolumeBox: View {
    let title: String
    let value: Double
    let caption: String
    let fmt3: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(fmt3(value)) m³").font(.title3).bold().monospacedDigit()
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))
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
            let dsCapacity = project.drillString.reduce(0.0) { $0 + (.pi * pow(max($1.innerDiameter_m, 0), 2) / 4.0) * max($1.length_m, 0) }
            let dsDisplacement = project.drillString.reduce(0.0) { $0 + (.pi * (pow(max($1.outerDiameter_m, 0), 2) - pow(max($1.innerDiameter_m, 0), 2) ) / 4.0) * max($1.length_m, 0) }
            let dsWet = dsCapacity + dsDisplacement
            let openHole = project.annulus.reduce(0.0) { $0 + (.pi * pow(max($1.innerDiameter_m, 0), 2) / 4.0) * max($1.length_m, 0) }
            let slices = buildAnnularSlices()
            let annularWithPipe = slices.reduce(0.0) { $0 + $1.volume_m3 }
            return VolumeTotals(dsCapacity_m3: dsCapacity, dsDisplacement_m3: dsDisplacement, dsWet_m3: dsWet, annularWithPipe_m3: annularWithPipe, openHole_m3: openHole, slices: slices)
        }

        private func buildAnnularSlices() -> [VolumeSlice] {
            var boundaries = Set<Double>()
            for a in project.annulus { boundaries.insert(a.topDepth_m); boundaries.insert(a.bottomDepth_m) }
            for d in project.drillString { boundaries.insert(d.topDepth_m); boundaries.insert(d.bottomDepth_m) }
            let sorted = boundaries.sorted()
            guard sorted.count > 1 else { return [] }

            func annulusAt(_ t: Double, _ b: Double) -> AnnulusSection? { project.annulus.first { $0.topDepth_m <= t && $0.bottomDepth_m >= b } }
            func stringAt(_ t: Double, _ b: Double) -> DrillStringSection? { project.drillString.first { $0.topDepth_m <= t && $0.bottomDepth_m >= b } }

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
        p.annulus.append(contentsOf: [a1, a2])
        let d1 = DrillStringSection(name: "Drill Pipe", topDepth_m: 0, length_m: 1000, outerDiameter_m: 0.127, innerDiameter_m: 0.0953)
        p.drillString.append(d1)
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
