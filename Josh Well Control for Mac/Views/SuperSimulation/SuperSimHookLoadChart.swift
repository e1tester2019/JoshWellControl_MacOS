//
//  SuperSimHookLoadChart.swift
//  Josh Well Control for Mac
//
//  Hook load vs depth chart spanning all Super Simulation operations.
//  Shows Pickup (green), Slack-off (red), Rotating (blue), Free Hanging (gray dashed).
//  Operation background bands match the timeline chart pattern.
//

import SwiftUI
import Charts

#if os(macOS)
struct SuperSimHookLoadChart: View {
    @Bindable var viewModel: SuperSimViewModel

    @State private var hoveredIndex: Int?

    var body: some View {
        let data = viewModel.hookLoadChartData
        let hasHookLoad = data.contains { $0.pickup_kDaN != nil || $0.slackOff_kDaN != nil }

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Hook Load vs Depth")
                    .font(.headline)
                Spacer()
                if let pt = hoveredIndex.flatMap({ idx in data.first { $0.globalIndex == idx } }) {
                    hoverInfo(pt)
                }
            }

            HStack(spacing: 12) {
                Spacer()
                legend
            }

            if !hasHookLoad {
                emptyPlaceholder
            } else {
                hookLoadChart(data)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                legendSwatch(color: .blue.opacity(0.1), label: "Trip Out", dashed: false, isBand: true)
                legendSwatch(color: .green.opacity(0.1), label: "Trip In", dashed: false, isBand: true)
                legendSwatch(color: .orange.opacity(0.1), label: "Circulate", dashed: false, isBand: true)
                legendSwatch(color: .purple.opacity(0.1), label: "Ream Out", dashed: false, isBand: true)
                legendSwatch(color: .pink.opacity(0.1), label: "Ream In", dashed: false, isBand: true)
            }
            Divider().frame(height: 12)
            legendSwatch(color: .green, label: "Pickup", dashed: false, isBand: false)
            legendSwatch(color: .red, label: "Slack-off", dashed: false, isBand: false)
            legendSwatch(color: .blue, label: "Rotating", dashed: false, isBand: false)
            legendSwatch(color: .gray, label: "Free Hang", dashed: true, isBand: false)
        }
        .font(.caption2)
    }

    private func legendSwatch(color: Color, label: String, dashed: Bool, isBand: Bool) -> some View {
        HStack(spacing: 3) {
            if isBand {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 12, height: 10)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(color.opacity(0.5), lineWidth: 0.5))
            } else if dashed {
                HStack(spacing: 1) {
                    Rectangle().fill(color).frame(width: 4, height: 2)
                    Rectangle().fill(color).frame(width: 4, height: 2)
                }
                .frame(width: 12)
            } else {
                Rectangle().fill(color).frame(width: 12, height: 2)
            }
            Text(label).foregroundStyle(.secondary)
        }
    }

    // MARK: - Chart

    private func hookLoadChart(_ data: [SuperSimViewModel.HookLoadChartPoint]) -> some View {
        let allValues = data.compactMap(\.pickup_kDaN) + data.compactMap(\.slackOff_kDaN)
            + data.compactMap(\.rotating_kDaN) + data.compactMap(\.freeHanging_kDaN)
        let yMin = (allValues.min() ?? 0) - 5
        let yMax = (allValues.max() ?? 100) + 5
        let ranges = viewModel.operationRanges

        return Chart {
            // Operation background bands
            ForEach(Array(ranges.enumerated()), id: \.offset) { _, range in
                RectangleMark(
                    xStart: .value("Start", range.start),
                    xEnd: .value("End", range.end),
                    yStart: .value("YMin", yMin),
                    yEnd: .value("YMax", yMax)
                )
                .foregroundStyle(bandColor(range.type))

                RuleMark(x: .value("Mid", (range.start + range.end) / 2))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, alignment: .center) {
                        Text(range.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }

            // Pickup line
            ForEach(data.filter { $0.pickup_kDaN != nil }) { pt in
                LineMark(
                    x: .value("Step", pt.globalIndex),
                    y: .value("Hook Load", pt.pickup_kDaN!),
                    series: .value("Series", "Pickup")
                )
                .foregroundStyle(.green)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.linear)
            }

            // Slack-off line
            ForEach(data.filter { $0.slackOff_kDaN != nil }) { pt in
                LineMark(
                    x: .value("Step", pt.globalIndex),
                    y: .value("Hook Load", pt.slackOff_kDaN!),
                    series: .value("Series", "Slack-off")
                )
                .foregroundStyle(.red)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.linear)
            }

            // Rotating line
            ForEach(data.filter { $0.rotating_kDaN != nil }) { pt in
                LineMark(
                    x: .value("Step", pt.globalIndex),
                    y: .value("Hook Load", pt.rotating_kDaN!),
                    series: .value("Series", "Rotating")
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.linear)
            }

            // Free hanging line (dashed)
            ForEach(data.filter { $0.freeHanging_kDaN != nil }) { pt in
                LineMark(
                    x: .value("Step", pt.globalIndex),
                    y: .value("Hook Load", pt.freeHanging_kDaN!),
                    series: .value("Series", "Free Hanging")
                )
                .foregroundStyle(.gray)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .interpolationMethod(.linear)
            }

            // Slider mark
            sliderMark(data, yMin: yMin, yMax: yMax)

            // Hover marks
            if let idx = hoveredIndex, let pt = data.first(where: { $0.globalIndex == idx }) {
                RuleMark(x: .value("Hover", idx))
                    .foregroundStyle(.primary.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                if let v = pt.pickup_kDaN {
                    PointMark(x: .value("Step", idx), y: .value("HL", v))
                        .foregroundStyle(.green).symbolSize(60)
                }
                if let v = pt.slackOff_kDaN {
                    PointMark(x: .value("Step", idx), y: .value("HL", v))
                        .foregroundStyle(.red).symbolSize(60)
                }
                if let v = pt.rotating_kDaN {
                    PointMark(x: .value("Step", idx), y: .value("HL", v))
                        .foregroundStyle(.blue).symbolSize(60)
                }
                if let v = pt.freeHanging_kDaN {
                    PointMark(x: .value("Step", idx), y: .value("HL", v))
                        .foregroundStyle(.gray).symbolSize(60)
                }
            }
        }
        .chartXAxisLabel("Step")
        .chartYAxisLabel("Hook Load (kDaN)")
        .chartXScale(domain: 0...(max(1, data.last?.globalIndex ?? 1)))
        .chartYScale(domain: yMin...yMax)
        .chartLegend(.hidden)
        .frame(minHeight: 500, maxHeight: .infinity)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            if let plotFrame = proxy.plotFrame {
                                let origin = geo[plotFrame].origin
                                let x = location.x - origin.x
                                if let stepValue: Double = proxy.value(atX: x) {
                                    let step = Int(stepValue.rounded())
                                    hoveredIndex = data.first { $0.globalIndex == step }?.globalIndex
                                        ?? data.min(by: { abs($0.globalIndex - step) < abs($1.globalIndex - step) })?.globalIndex
                                }
                            }
                        case .ended:
                            hoveredIndex = nil
                        }
                    }
            }
        }
    }

    // MARK: - Slider Mark

    @ChartContentBuilder
    private func sliderMark(_ data: [SuperSimViewModel.HookLoadChartPoint], yMin: Double, yMax: Double) -> some ChartContent {
        let sliderIdx = Int(viewModel.globalStepSliderValue.rounded())
        if sliderIdx >= 0, sliderIdx < data.count {
            let pt = data[sliderIdx]
            let totalSteps = max(1, data.count)
            let nearLeftEdge = Double(sliderIdx) < Double(totalSteps) * 0.15
            RuleMark(x: .value("Slider", sliderIdx))
                .foregroundStyle(Color.accentColor.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 2))
                .annotation(position: nearLeftEdge ? .topTrailing : .topLeading,
                            alignment: nearLeftEdge ? .trailing : .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pt.operationLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("MD: \(String(format: "%.0f", pt.bitMD_m))m")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let v = pt.pickup_kDaN {
                            HStack(spacing: 4) {
                                Circle().fill(.green).frame(width: 6, height: 6)
                                Text("PU: \(String(format: "%.1f", v)) kDaN")
                                    .font(.caption2)
                            }
                        }
                        if let v = pt.slackOff_kDaN {
                            HStack(spacing: 4) {
                                Circle().fill(.red).frame(width: 6, height: 6)
                                Text("SO: \(String(format: "%.1f", v)) kDaN")
                                    .font(.caption2)
                            }
                        }
                        if let v = pt.rotating_kDaN {
                            HStack(spacing: 4) {
                                Circle().fill(.blue).frame(width: 6, height: 6)
                                Text("Rot: \(String(format: "%.1f", v)) kDaN")
                                    .font(.caption2)
                            }
                        }
                        if let v = pt.freeHanging_kDaN {
                            HStack(spacing: 4) {
                                Circle().fill(.gray).frame(width: 6, height: 6)
                                Text("FH: \(String(format: "%.1f", v)) kDaN")
                                    .font(.caption2)
                            }
                        }
                    }
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.background.shadow(.drop(radius: 2))))
                }
        }
    }

    // MARK: - Hover Info

    private func hoverInfo(_ pt: SuperSimViewModel.HookLoadChartPoint) -> some View {
        HStack(spacing: 8) {
            Text(pt.operationLabel)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(bandColor(pt.operationType).opacity(3)))
            Text("MD: \(String(format: "%.0f", pt.bitMD_m))m")
                .monospacedDigit()
            if let v = pt.pickup_kDaN {
                Text("PU: \(String(format: "%.1f", v))")
                    .monospacedDigit()
                    .foregroundStyle(.green)
            }
            if let v = pt.slackOff_kDaN {
                Text("SO: \(String(format: "%.1f", v))")
                    .monospacedDigit()
                    .foregroundStyle(.red)
            }
            if let v = pt.freeHanging_kDaN {
                Text("FH: \(String(format: "%.1f", v))")
                    .monospacedDigit()
                    .foregroundStyle(.gray)
            }
        }
        .font(.caption)
    }

    // MARK: - Helpers

    private func bandColor(_ type: OperationType) -> Color {
        switch type {
        case .tripOut: return .blue.opacity(0.08)
        case .tripIn: return .green.opacity(0.08)
        case .circulate: return .orange.opacity(0.08)
        case .reamOut: return .purple.opacity(0.08)
        case .reamIn: return .pink.opacity(0.08)
        }
    }

    private var emptyPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.05))
            VStack(spacing: 6) {
                Image(systemName: "chart.xyaxis.line")
                    .foregroundStyle(.secondary)
                Text("No hook load data. Enable T&D and run operations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 200)
    }
}
#endif
