//
//  PressureWindowViewIOS.swift
//  Josh Well Control for Mac
//
//  iOS-optimized pressure window view with form-based editing
//

#if os(iOS)
import SwiftUI
import SwiftData
import Charts

struct PressureWindowViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState

    private var window: PressureWindow {
        project.window
    }

    private var sortedPoints: [PressureWindowPoint] {
        (window.points ?? []).sorted { $0.depth_m < $1.depth_m }
    }

    var body: some View {
        List {
            // Reference Points Section
            Section {
                ForEach(sortedPoints) { point in
                    PressurePointRowIOS(point: point, window: window)
                }
                .onDelete(perform: deletePoints)

                Button {
                    addPoint()
                } label: {
                    Label("Add Point", systemImage: "plus")
                }
            } header: {
                Text("Reference Points")
            } footer: {
                Text("Define pore pressure and fracture gradient at key TVD depths.")
            }

            // Chart Section
            Section("Pressure Window") {
                if sortedPoints.count >= 2 {
                    PressureWindowChartIOS(points: sortedPoints)
                        .frame(height: 300)
                } else {
                    Text("Add at least 2 points to see the chart")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                }
            }

            // Equivalent Mud Weights Section
            Section("Equivalent Mud Weights") {
                ForEach(sortedPoints) { point in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TVD: \(point.depth_m, format: .number) m")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        HStack {
                            Text("Pore EMW:")
                            Spacer()
                            Text("\(poreEMW(at: point), format: .number.precision(.fractionLength(0))) kg/m³")
                                .foregroundStyle(.blue)
                        }
                        .font(.caption)

                        HStack {
                            Text("Frac EMW:")
                            Spacer()
                            Text("\(fracEMW(at: point), format: .number.precision(.fractionLength(0))) kg/m³")
                                .foregroundStyle(.red)
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Pressure Window")
    }

    private func addPoint() {
        let lastDepth = sortedPoints.last?.depth_m ?? 0
        let point = PressureWindowPoint(depth_m: lastDepth + 100, pore_kPa: 1000, frac_kPa: 2000, window: window)
        if window.points == nil { window.points = [] }
        window.points?.append(point)
        modelContext.insert(point)
        try? modelContext.save()
    }

    private func deletePoints(at offsets: IndexSet) {
        let pointsToDelete = offsets.map { sortedPoints[$0] }
        for point in pointsToDelete {
            if let idx = window.points?.firstIndex(where: { $0.id == point.id }) {
                window.points?.remove(at: idx)
            }
            modelContext.delete(point)
        }
        try? modelContext.save()
    }

    private func poreEMW(at point: PressureWindowPoint) -> Double {
        guard point.depth_m > 0, let pore = point.pore_kPa else { return 0 }
        return pore / (9.80665 * point.depth_m / 1000)
    }

    private func fracEMW(at point: PressureWindowPoint) -> Double {
        guard point.depth_m > 0, let frac = point.frac_kPa else { return 0 }
        return frac / (9.80665 * point.depth_m / 1000)
    }
}

// MARK: - Pressure Point Row

private struct PressurePointRowIOS: View {
    @Bindable var point: PressureWindowPoint
    let window: PressureWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Depth")
                Spacer()
                TextField("Depth", value: $point.depth_m, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("m")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Pore Pressure")
                Spacer()
                TextField("Pore", value: Binding(
                    get: { point.pore_kPa ?? 0 },
                    set: { point.pore_kPa = $0 }
                ), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("kPa")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Frac Pressure")
                Spacer()
                TextField("Frac", value: Binding(
                    get: { point.frac_kPa ?? 0 },
                    set: { point.frac_kPa = $0 }
                ), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("kPa")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }
}

// MARK: - Pressure Window Chart

private struct PressureWindowChartIOS: View {
    let points: [PressureWindowPoint]

    var body: some View {
        Chart {
            // Pore pressure line
            ForEach(points) { point in
                if let pore = point.pore_kPa {
                    LineMark(
                        x: .value("Pressure", pore),
                        y: .value("Depth", point.depth_m)
                    )
                    .foregroundStyle(.blue)
                    .symbol(.circle)
                }
            }

            // Frac pressure line
            ForEach(points) { point in
                if let frac = point.frac_kPa {
                    LineMark(
                        x: .value("Pressure", frac),
                        y: .value("Depth", point.depth_m)
                    )
                    .foregroundStyle(.red)
                    .symbol(.triangle)
                }
            }

            // Safe operating window area
            ForEach(points) { point in
                if let pore = point.pore_kPa, let frac = point.frac_kPa {
                    RectangleMark(
                        xStart: .value("Pore", pore),
                        xEnd: .value("Frac", frac),
                        yStart: .value("Depth Start", point.depth_m - 25),
                        yEnd: .value("Depth End", point.depth_m + 25)
                    )
                    .foregroundStyle(.green.opacity(0.2))
                }
            }
        }
        .chartYScale(domain: .automatic(includesZero: true))
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxisLabel("Pressure (kPa)")
        .chartYAxisLabel("Depth (m)")
        .chartLegend(position: .top)
    }
}

#endif
