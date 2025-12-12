//
//  VolumeSummaryViewIOS.swift
//  Josh Well Control for Mac
//
//  iOS-optimized volume summary view with adaptive grid layout
//

#if os(iOS)
import SwiftUI
import SwiftData

// MARK: - iOS-specific Types

private struct VolumeTotals {
    let dsCapacity_m3: Double
    let dsDisplacement_m3: Double
    let dsWet_m3: Double
    let annularWithPipe_m3: Double
    let openHole_m3: Double
    let slices: [VolumeSlice]
}

private struct VolumeSlice: Identifiable {
    let id = UUID()
    let top: Double
    let bottom: Double
    let area_m2: Double
    var length: Double { bottom - top }
    var volume_m3: Double { area_m2 * length }
}

// MARK: - ViewModel

@Observable
private class VolumeSummaryViewModel {
    var project: ProjectState

    init(project: ProjectState) {
        self.project = project
    }

    func computeTotals() -> VolumeTotals {
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

// MARK: - Main View

struct VolumeSummaryViewIOS: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let project: ProjectState
    @State private var viewmodel: VolumeSummaryViewModel

    init(project: ProjectState) {
        self.project = project
        _viewmodel = State(initialValue: VolumeSummaryViewModel(project: project))
    }

    var body: some View {
        let totals = viewmodel.computeTotals()
        let columns = horizontalSizeClass == .compact ? 1 : 2

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary Cards
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
                        VolumeCard(
                            title: "Drill String Capacity",
                            value: viewmodel.fmt3(totals.dsCapacity_m3),
                            unit: "m³",
                            icon: "internaldrive",
                            color: .blue
                        )

                        VolumeCard(
                            title: "Steel Displacement",
                            value: viewmodel.fmt3(totals.dsDisplacement_m3),
                            unit: "m³",
                            icon: "shippingbox",
                            color: .orange
                        )

                        VolumeCard(
                            title: "Wet Displacement",
                            value: viewmodel.fmt3(totals.dsWet_m3),
                            unit: "m³",
                            icon: "drop.fill",
                            color: .cyan
                        )

                        VolumeCard(
                            title: "Annulus w/ Pipe",
                            value: viewmodel.fmt3(totals.annularWithPipe_m3),
                            unit: "m³",
                            icon: "circle.grid.cross",
                            color: .green
                        )

                        VolumeCard(
                            title: "Open Hole",
                            value: viewmodel.fmt3(totals.openHole_m3),
                            unit: "m³",
                            icon: "ruler",
                            color: .purple
                        )
                    }
                } header: {
                    Label("Volume Summary", systemImage: "cube.box.fill")
                        .font(.headline)
                }

                // Depth Breakdown
                if !totals.slices.isEmpty {
                    Section {
                        VStack(spacing: 0) {
                            ForEach(Array(totals.slices.enumerated()), id: \.element.id) { idx, slice in
                                HStack {
                                    Text("\(viewmodel.fmt0(slice.top)) - \(viewmodel.fmt0(slice.bottom)) m")
                                        .font(.subheadline)

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("\(viewmodel.fmt3(slice.area_m2)) m²")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("\(viewmodel.fmt3(slice.volume_m3)) m³")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    }
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal)

                                if idx < totals.slices.count - 1 {
                                    Divider()
                                }
                            }
                        }
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(10)
                    } header: {
                        Label("Depth Breakdown", systemImage: "chart.bar.fill")
                            .font(.headline)
                    }
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Volume Summary")
    }
}

// MARK: - Volume Card

private struct VolumeCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .monospacedDigit()

                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

#endif
