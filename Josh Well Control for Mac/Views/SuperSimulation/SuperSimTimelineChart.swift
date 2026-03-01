//
//  SuperSimTimelineChart.swift
//  Josh Well Control for Mac
//
//  Combined timeline chart spanning all Super Simulation operations.
//  Colored background bands show operation type; consistent line colors with legend.
//

import SwiftUI
import Charts

#if os(macOS)
struct SuperSimTimelineChart: View {
    @Bindable var viewModel: SuperSimViewModel

    enum ChartType: String, CaseIterable {
        case esd = "ESD"
        case backPressure = "Back Pressure"
        case pumpRate = "Pump Rate"
    }

    @State private var chartType: ChartType = .esd
    @State private var hoveredPoint: SuperSimViewModel.TimelineChartPoint?
    @State private var isScrollable: Bool = false
    @State private var zoomLevel: Double = 1.0
    @State private var scrollPosition: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 20) {
                Picker("", selection: $chartType) {
                    ForEach(ChartType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)

                Spacer(minLength: 20)

                if let point = hoveredPoint {
                    hoverInfo(point)
                }
            }

            // Scroll + zoom controls
            HStack(spacing: 12) {
                Toggle("Scrollable", isOn: $isScrollable)
                    .toggleStyle(.checkbox)
                    .font(.caption)

                if isScrollable {
                    Text("Zoom:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $zoomLevel, in: 0.1...1.0)
                        .frame(width: 120)
                    Text("\(Int((1.0 / zoomLevel).rounded()))x")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 30)
                }

                Spacer()

                // Legend
                legend
            }

            let data = viewModel.timelineChartData
            if data.isEmpty {
                emptyPlaceholder
                    .layoutPriority(1)
            } else {
                switch chartType {
                case .esd:
                    esdChart(data)
                        .layoutPriority(1)
                case .backPressure:
                    backPressureChart(data)
                        .layoutPriority(1)
                case .pumpRate:
                    pumpRateChart(data)
                        .layoutPriority(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Legend

    @ViewBuilder
    private var legend: some View {
        HStack(spacing: 12) {
            // Operation type colors (background bands)
            HStack(spacing: 4) {
                legendSwatch(color: .blue.opacity(0.1), label: "Trip Out", style: .fill)
                legendSwatch(color: .green.opacity(0.1), label: "Trip In", style: .fill)
                legendSwatch(color: .orange.opacity(0.1), label: "Circulate", style: .fill)
                legendSwatch(color: .purple.opacity(0.1), label: "Ream Out", style: .fill)
                legendSwatch(color: .pink.opacity(0.1), label: "Ream In", style: .fill)
            }

            Divider().frame(height: 12)

            // Line colors
            switch chartType {
            case .esd:
                legendSwatch(color: .primary, label: "Mud Column", style: .line)
                legendSwatch(color: .cyan, label: "Mud + BP", style: .dashed)
            case .backPressure:
                legendSwatch(color: .red, label: "Static", style: .line)
                legendSwatch(color: .red.opacity(0.5), label: "Dynamic", style: .dashed)
            case .pumpRate:
                legendSwatch(color: .purple, label: "Pump Rate", style: .line)
                legendSwatch(color: .indigo, label: "APL", style: .dashed)
            }
        }
        .font(.caption2)
    }

    private enum SwatchStyle { case fill, line, dashed }

    private func legendSwatch(color: Color, label: String, style: SwatchStyle) -> some View {
        HStack(spacing: 3) {
            switch style {
            case .fill:
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 12, height: 10)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(color.opacity(0.5), lineWidth: 0.5))
            case .line:
                Rectangle().fill(color).frame(width: 12, height: 2)
            case .dashed:
                HStack(spacing: 1) {
                    Rectangle().fill(color).frame(width: 4, height: 2)
                    Rectangle().fill(color).frame(width: 4, height: 2)
                }
                .frame(width: 12)
            }
            Text(label).foregroundStyle(.secondary)
        }
    }

    // MARK: - Operation Background Bands

    /// Operation ranges from the view model (start, end, type, label)
    private var operationRanges: [(start: Int, end: Int, type: OperationType, label: String)] {
        viewModel.operationRanges
    }

    @ChartContentBuilder
    private func operationBands(yMin: Double, yMax: Double) -> some ChartContent {
        ForEach(Array(operationRanges.enumerated()), id: \.offset) { idx, range in
            RectangleMark(
                xStart: .value("Start", range.start),
                xEnd: .value("End", range.end),
                yStart: .value("YMin", yMin),
                yEnd: .value("YMax", yMax)
            )
            .foregroundStyle(bandColor(range.type))

            // Label at the midpoint
            RuleMark(x: .value("Mid", (range.start + range.end) / 2))
                .foregroundStyle(.clear)
                .annotation(position: idx.isMultiple(of: 2) ? .top : .bottom, alignment: .center) {
                    Text(range.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func bandColor(_ type: OperationType) -> Color {
        switch type {
        case .tripOut: return .blue.opacity(0.08)
        case .tripIn: return .green.opacity(0.08)
        case .circulate: return .orange.opacity(0.08)
        case .reamOut: return .purple.opacity(0.08)
        case .reamIn: return .pink.opacity(0.08)
        }
    }

    // MARK: - ESD Chart

    @ChartContentBuilder
    private func esdLines(_ data: [SuperSimViewModel.TimelineChartPoint]) -> some ChartContent {
        ForEach(data) { point in
            LineMark(
                x: .value("Step", point.globalIndex),
                y: .value("Mud Column (kg/m\u{00B3})", point.ESDAtControl_kgpm3),
                series: .value("Series", "Mud Column")
            )
            .foregroundStyle(Color.primary)
            .interpolationMethod(.linear)
            .lineStyle(StrokeStyle(lineWidth: 2))
        }
    }

    @ChartContentBuilder
    private func esdTotalLines(_ data: [SuperSimViewModel.TimelineChartPoint]) -> some ChartContent {
        ForEach(data) { point in
            LineMark(
                x: .value("Step", point.globalIndex),
                y: .value("Mud + BP (kg/m\u{00B3})", point.totalESD_kgpm3),
                series: .value("Series", "Mud + BP")
            )
            .foregroundStyle(.cyan)
            .interpolationMethod(.linear)
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
        }
    }

    @ChartContentBuilder
    private func esdHoverMarks(_ point: SuperSimViewModel.TimelineChartPoint) -> some ChartContent {
        hoverMarks(point, yValue: point.ESDAtControl_kgpm3, yLabel: "Mud Column (kg/m\u{00B3})")
        PointMark(
            x: .value("Step", point.globalIndex),
            y: .value("Mud + BP (kg/m\u{00B3})", point.totalESD_kgpm3)
        )
        .foregroundStyle(.cyan)
        .symbolSize(60)
        .symbol(.diamond)
    }

    private func esdChart(_ data: [SuperSimViewModel.TimelineChartPoint]) -> some View {
        let allValues = data.flatMap { [$0.ESDAtControl_kgpm3, $0.totalESD_kgpm3] }
        let yMin = (allValues.min() ?? 0) - 20
        let yMax = (allValues.max() ?? 2000) + 20

        let chart = Chart {
            operationBands(yMin: yMin, yMax: yMax)
            esdLines(data)
            esdTotalLines(data)
            sliderMark(data, chartType: .esd)
            if let point = hoveredPoint {
                esdHoverMarks(point)
            }
        }
        .chartXAxisLabel("Step")
        .chartYAxisLabel("ESD (kg/m\u{00B3})")
        .chartXScale(domain: 0...(max(1, data.last?.globalIndex ?? 1)))
        .chartYScale(domain: yMin...yMax)
        .frame(minHeight: 500, maxHeight: .infinity)

        return applyScrollAndHover(chart, data: data)
    }

    // MARK: - Back Pressure Chart

    @ChartContentBuilder
    private func bpStaticLines(_ data: [SuperSimViewModel.TimelineChartPoint]) -> some ChartContent {
        ForEach(data) { point in
            LineMark(
                x: .value("Step", point.globalIndex),
                y: .value("Static SABP (kPa)", point.SABP_kPa),
                series: .value("Series", "Static")
            )
            .foregroundStyle(.red)
            .interpolationMethod(.linear)
            .lineStyle(StrokeStyle(lineWidth: 2))
        }
    }

    @ChartContentBuilder
    private func bpDynamicLines(_ data: [SuperSimViewModel.TimelineChartPoint]) -> some ChartContent {
        ForEach(data) { point in
            LineMark(
                x: .value("Step", point.globalIndex),
                y: .value("Dynamic SABP (kPa)", point.dynamicSABP_kPa),
                series: .value("Series", "Dynamic")
            )
            .foregroundStyle(.red.opacity(0.5))
            .interpolationMethod(.linear)
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
        }
    }

    @ChartContentBuilder
    private func bpHoverMarks(_ point: SuperSimViewModel.TimelineChartPoint) -> some ChartContent {
        hoverMarks(point, yValue: point.SABP_kPa, yLabel: "Static SABP (kPa)")
        PointMark(
            x: .value("Step", point.globalIndex),
            y: .value("Dynamic SABP (kPa)", point.dynamicSABP_kPa)
        )
        .foregroundStyle(.red.opacity(0.5))
        .symbolSize(60)
        .symbol(.diamond)
    }

    private func backPressureChart(_ data: [SuperSimViewModel.TimelineChartPoint]) -> some View {
        let allSABP = data.flatMap { [$0.SABP_kPa, $0.dynamicSABP_kPa] }
        let yMin = max(0, (allSABP.min() ?? 0) - 50)
        let yMax = (allSABP.max() ?? 1000) + 50

        let chart = Chart {
            operationBands(yMin: yMin, yMax: yMax)
            bpStaticLines(data)
            bpDynamicLines(data)
            sliderMark(data, chartType: .backPressure)
            if let point = hoveredPoint {
                bpHoverMarks(point)
            }
        }
        .chartXAxisLabel("Step")
        .chartYAxisLabel("SABP (kPa)")
        .chartXScale(domain: 0...(max(1, data.last?.globalIndex ?? 1)))
        .chartYScale(domain: yMin...yMax)
        .frame(minHeight: 500, maxHeight: .infinity)

        return applyScrollAndHover(chart, data: data)
    }

    // MARK: - Pump Rate Chart

    @ChartContentBuilder
    private func pumpRateLines(_ data: [SuperSimViewModel.TimelineChartPoint]) -> some ChartContent {
        ForEach(data) { point in
            LineMark(
                x: .value("Step", point.globalIndex),
                y: .value("Pump Rate (m\u{00B3}/min)", point.pumpRate_m3perMin),
                series: .value("Series", "Pump Rate")
            )
            .foregroundStyle(.purple)
            .interpolationMethod(.linear)
            .lineStyle(StrokeStyle(lineWidth: 2))
        }
    }

    @ChartContentBuilder
    private func aplLinesNormalized(_ data: [SuperSimViewModel.TimelineChartPoint], aplMax: Double, yMax: Double) -> some ChartContent {
        let scale = aplMax > 0.001 ? yMax / aplMax : 0
        ForEach(data) { point in
            LineMark(
                x: .value("Step", point.globalIndex),
                y: .value("APL (normalized)", point.apl_kPa * scale),
                series: .value("Series", "APL")
            )
            .foregroundStyle(.indigo)
            .interpolationMethod(.linear)
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
        }
    }

    @ChartContentBuilder
    private func pumpRateHoverMarks(_ point: SuperSimViewModel.TimelineChartPoint) -> some ChartContent {
        hoverMarks(point, yValue: point.pumpRate_m3perMin, yLabel: "Pump Rate (m\u{00B3}/min)")
    }

    private func pumpRateChart(_ data: [SuperSimViewModel.TimelineChartPoint]) -> some View {
        // Pump rate on primary (leading) Y axis, APL on secondary (trailing) Y axis
        let allRates = data.map(\.pumpRate_m3perMin)
        let rateMin = max(0, (allRates.min() ?? 0) - 0.1)
        let rateMax = (allRates.max() ?? 1.5) + 0.1

        let allAPL = data.map(\.apl_kPa)
        let aplMax = max(1, (allAPL.max() ?? 100) * 1.1)

        let chart = Chart {
            operationBands(yMin: rateMin, yMax: rateMax)
            pumpRateLines(data)
            aplLinesNormalized(data, aplMax: aplMax, yMax: rateMax)
            sliderMark(data, chartType: .pumpRate)
            if let point = hoveredPoint {
                pumpRateHoverMarks(point)
            }
        }
        .chartXAxisLabel("Step")
        .chartXScale(domain: 0...(max(1, data.last?.globalIndex ?? 1)))
        .chartYScale(domain: rateMin...rateMax)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(String(format: "%.2f", v))
                            .foregroundStyle(.purple)
                    }
                }
            }
            AxisMarks(position: .trailing) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        let aplValue = aplMax > 0.001 ? v / rateMax * aplMax : 0
                        Text(String(format: "%.0f", aplValue))
                            .foregroundStyle(.indigo)
                    }
                }
            }
        }
        .frame(minHeight: 500, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            Text("Pump Rate (m\u{00B3}/min)")
                .font(.caption2)
                .foregroundStyle(.purple)
                .padding(.leading, 4)
                .padding(.top, 2)
        }
        .overlay(alignment: .topTrailing) {
            Text("APL (kPa)")
                .font(.caption2)
                .foregroundStyle(.indigo)
                .padding(.trailing, 4)
                .padding(.top, 2)
        }

        return applyScrollAndHover(chart, data: data)
    }

    // MARK: - Slider Mark with Tooltip

    @ChartContentBuilder
    private func sliderMark(_ data: [SuperSimViewModel.TimelineChartPoint], chartType: ChartType) -> some ChartContent {
        let sliderIdx = Int(viewModel.globalStepSliderValue.rounded())
        if sliderIdx >= 0, sliderIdx < data.count {
            let point = data[sliderIdx]
            RuleMark(x: .value("Slider", sliderIdx))
                .foregroundStyle(Color.accentColor.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 2))
                .annotation(position: .topLeading, alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(point.operationLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        switch chartType {
                        case .esd:
                            Text("Mud: \(String(format: "%.1f", point.ESDAtControl_kgpm3)) kg/m\u{00B3}")
                                .font(.caption2.bold())
                            if point.SABP_kPa > 0 {
                                Text("+ BP: \(String(format: "%.1f", point.totalESD_kgpm3)) kg/m\u{00B3}")
                                    .font(.caption2)
                                    .foregroundStyle(.cyan)
                            }
                        case .backPressure:
                            Text("S: \(String(format: "%.0f", point.SABP_kPa)) kPa")
                                .font(.caption2.bold())
                            Text("D: \(String(format: "%.0f", point.dynamicSABP_kPa)) kPa")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        case .pumpRate:
                            Text("Rate: \(String(format: "%.2f", point.pumpRate_m3perMin)) m\u{00B3}/min")
                                .font(.caption2.bold())
                            Text("APL: \(String(format: "%.0f", point.apl_kPa)) kPa")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text("MD: \(String(format: "%.0f", point.bitMD_m))m")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.background.shadow(.drop(radius: 2))))
                }
        }
    }

    // MARK: - Hover Marks

    @ChartContentBuilder
    private func hoverMarks(_ point: SuperSimViewModel.TimelineChartPoint, yValue: Double, yLabel: String) -> some ChartContent {
        RuleMark(x: .value("Hover", point.globalIndex))
            .foregroundStyle(.primary.opacity(0.3))
            .lineStyle(StrokeStyle(lineWidth: 1))
        PointMark(
            x: .value("Step", point.globalIndex),
            y: .value(yLabel, yValue)
        )
        .foregroundStyle(.primary)
        .symbolSize(100)
    }

    // MARK: - Scroll + Hover

    @ViewBuilder
    private func applyScrollAndHover<C: View>(_ chart: C, data: [SuperSimViewModel.TimelineChartPoint]) -> some View {
        if isScrollable {
            let totalSteps = max(1, data.count)
            let visibleSteps = max(10, Int(Double(totalSteps) * zoomLevel))
            chart
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: visibleSteps)
                .chartScrollPosition(x: $scrollPosition)
                .chartOverlay { proxy in
                    hoverOverlay(proxy: proxy, data: data)
                }
                .onAppear {
                    let target = Int(viewModel.globalStepSliderValue.rounded())
                    let halfVisible = visibleSteps / 2
                    let maxScroll = max(0, totalSteps - visibleSteps)
                    scrollPosition = min(max(0, target - halfVisible), maxScroll)
                }
                .onChange(of: viewModel.globalStepSliderValue) {
                    let target = Int(viewModel.globalStepSliderValue.rounded())
                    let halfVisible = visibleSteps / 2
                    let maxScroll = max(0, totalSteps - visibleSteps)
                    scrollPosition = min(max(0, target - halfVisible), maxScroll)
                }
        } else {
            chart
                .chartOverlay { proxy in
                    hoverOverlay(proxy: proxy, data: data)
                }
        }
    }

    // MARK: - Hover Info

    private func hoverInfo(_ point: SuperSimViewModel.TimelineChartPoint) -> some View {
        HStack(spacing: 8) {
            Text(point.operationLabel)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(bandColor(point.operationType).opacity(3)))
            Text("MD: \(String(format: "%.0f", point.bitMD_m))m")
                .monospacedDigit()

            switch chartType {
            case .esd:
                Text("Mud: \(String(format: "%.1f", point.ESDAtControl_kgpm3)) kg/m\u{00B3}")
                    .monospacedDigit()
                if point.SABP_kPa > 0 {
                    Text("+ BP: \(String(format: "%.1f", point.totalESD_kgpm3)) kg/m\u{00B3}")
                        .monospacedDigit()
                        .foregroundStyle(.cyan)
                }
            case .backPressure:
                Text("Static: \(String(format: "%.0f", point.SABP_kPa)) kPa")
                    .monospacedDigit()
                Text("Dynamic: \(String(format: "%.0f", point.dynamicSABP_kPa)) kPa")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            case .pumpRate:
                Text("Rate: \(String(format: "%.2f", point.pumpRate_m3perMin)) m\u{00B3}/min")
                    .monospacedDigit()
                Text("APL: \(String(format: "%.0f", point.apl_kPa)) kPa")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .font(.caption)
    }

    // MARK: - Hover Overlay

    private func hoverOverlay(proxy: ChartProxy, data: [SuperSimViewModel.TimelineChartPoint]) -> some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        if let plotFrame = proxy.plotFrame {
                            let plotAreaOrigin = geo[plotFrame].origin
                            let x = location.x - plotAreaOrigin.x
                            if let stepValue: Double = proxy.value(atX: x) {
                                let step = Int(stepValue.rounded())
                                hoveredPoint = data.first { $0.globalIndex == step }
                                    ?? data.min(by: { abs($0.globalIndex - step) < abs($1.globalIndex - step) })
                            }
                        }
                    case .ended:
                        hoveredPoint = nil
                    }
                }
        }
    }

    // MARK: - Empty Placeholder

    private var emptyPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.05))
            VStack(spacing: 6) {
                Image(systemName: "chart.xyaxis.line")
                    .foregroundStyle(.secondary)
                Text("Run operations to see the timeline chart.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 200)
    }
}
#endif
