//
//  SuperSimTimelineChartIOS.swift
//  Josh Well Control for Mac
//
//  iOS/iPadOS timeline chart for Super Simulation.
//  Matches macOS chart: operation bands with labels, slider tooltip, consistent colors/legend.
//

import SwiftUI
import Charts

#if os(iOS)

struct SuperSimTimelineChartIOS: View {
    @Bindable var viewModel: SuperSimViewModel

    enum ChartType: String, CaseIterable {
        case esd = "ESD"
        case backPressure = "Back Pressure"
        case pumpRate = "Pump Rate"
    }

    @State private var chartType: ChartType = .esd
    @State private var showLegend: Bool = false
    @State private var zoomLevel: Double = 1.0
    @State private var scrollPosition: Int = 0
    @State private var isDraggingScrubber: Bool = false

    @Environment(\.horizontalSizeClass) var sizeClass

    var body: some View {
        VStack(spacing: 8) {
            // Chart type selector
            HStack {
                Picker("Chart Type", selection: $chartType) {
                    ForEach(ChartType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showLegend.toggle()
                    }
                } label: {
                    Image(systemName: showLegend ? "info.circle.fill" : "info.circle")
                        .imageScale(.large)
                }
            }
            .padding(.horizontal)

            // Legend (collapsible)
            if showLegend {
                legend
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Current value card
            let data = viewModel.timelineChartData
            if !data.isEmpty {
                currentValueCard(data)
                    .padding(.horizontal)
            }

            if data.isEmpty {
                emptyPlaceholder
            } else {
                switch chartType {
                case .esd:
                    esdChart(data)
                case .backPressure:
                    backPressureChart(data)
                case .pumpRate:
                    pumpRateChart(data)
                }

                // Zoom controls for iPad
                if sizeClass == .regular {
                    zoomControls
                        .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - Operation Ranges

    private var operationRanges: [(start: Int, end: Int, type: OperationType, label: String)] {
        viewModel.operationRanges
    }

    // MARK: - Operation Background Bands (with labels)

    @ChartContentBuilder
    private func operationBands(yMin: Double, yMax: Double) -> some ChartContent {
        ForEach(Array(operationRanges.enumerated()), id: \.offset) { _, range in
            RectangleMark(
                xStart: .value("Start", range.start),
                xEnd: .value("End", range.end),
                yStart: .value("YMin", yMin),
                yEnd: .value("YMax", yMax)
            )
            .foregroundStyle(bandColor(range.type))

            // Label at top of band
            RuleMark(x: .value("Mid", (range.start + range.end) / 2))
                .foregroundStyle(.clear)
                .annotation(position: .top, alignment: .center) {
                    Text(range.label)
                        .font(.system(size: 9))
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

    // MARK: - Slider Mark with Tooltip

    @ChartContentBuilder
    private func sliderMark(_ data: [SuperSimViewModel.TimelineChartPoint], chartType: ChartType) -> some ChartContent {
        let sliderIdx = Int(viewModel.globalStepSliderValue.rounded())
        if sliderIdx >= 0, sliderIdx < data.count {
            let point = data[sliderIdx]
            let totalSteps = max(1, data.count)
            let nearLeftEdge = Double(sliderIdx) < Double(totalSteps) * 0.15
            RuleMark(x: .value("Slider", sliderIdx))
                .foregroundStyle(Color.accentColor.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 2))
                .annotation(position: nearLeftEdge ? .topTrailing : .topLeading,
                            alignment: nearLeftEdge ? .trailing : .leading, spacing: 8) {
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
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(uiColor: .systemBackground).shadow(.drop(radius: 2))))
                }
        }
    }

    // MARK: - ESD Chart

    private func esdChart(_ data: [SuperSimViewModel.TimelineChartPoint]) -> some View {
        let allValues = data.flatMap { [$0.ESDAtControl_kgpm3, $0.totalESD_kgpm3] }
        let yMin = (allValues.min() ?? 0) - 20
        let yMax = (allValues.max() ?? 2000) + 20

        return Chart {
            operationBands(yMin: yMin, yMax: yMax)

            // Mud column line
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

            // Mud + BP line (dashed)
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

            sliderMark(data, chartType: .esd)
        }
        .chartXAxisLabel("Step")
        .chartYAxisLabel("ESD (kg/m\u{00B3})")
        .chartXScale(domain: 0...max(1, data.last?.globalIndex ?? 1))
        .chartYScale(domain: yMin...yMax)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleDomainLength(data))
        .chartScrollPosition(x: $scrollPosition)
        .chartOverlay { proxy in
            scrubberOverlay(proxy: proxy, data: data)
        }
        .frame(height: UIDevice.current.userInterfaceIdiom == .phone ? 300 : 400)
        .padding(.horizontal, 4)
    }

    // MARK: - Back Pressure Chart

    private func backPressureChart(_ data: [SuperSimViewModel.TimelineChartPoint]) -> some View {
        let allSABP = data.flatMap { [$0.SABP_kPa, $0.dynamicSABP_kPa] }
        let yMin = max(0, (allSABP.min() ?? 0) - 50)
        let yMax = (allSABP.max() ?? 1000) + 50

        return Chart {
            operationBands(yMin: yMin, yMax: yMax)

            // Static SABP
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

            // Dynamic SABP (dashed)
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

            sliderMark(data, chartType: .backPressure)
        }
        .chartXAxisLabel("Step")
        .chartYAxisLabel("SABP (kPa)")
        .chartXScale(domain: 0...max(1, data.last?.globalIndex ?? 1))
        .chartYScale(domain: yMin...yMax)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleDomainLength(data))
        .chartScrollPosition(x: $scrollPosition)
        .chartOverlay { proxy in
            scrubberOverlay(proxy: proxy, data: data)
        }
        .frame(height: UIDevice.current.userInterfaceIdiom == .phone ? 300 : 400)
        .padding(.horizontal, 4)
    }

    // MARK: - Pump Rate Chart

    private func pumpRateChart(_ data: [SuperSimViewModel.TimelineChartPoint]) -> some View {
        let allRates = data.map(\.pumpRate_m3perMin)
        let rateMin = max(0, (allRates.min() ?? 0) - 0.1)
        let rateMax = (allRates.max() ?? 1.5) + 0.1

        let allAPL = data.map(\.apl_kPa)
        let aplMax = max(1, (allAPL.max() ?? 100) * 1.1)

        return Chart {
            operationBands(yMin: rateMin, yMax: rateMax)

            // Pump rate line
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

            // APL normalized to pump rate scale (dashed)
            let scale = aplMax > 0.001 ? rateMax / aplMax : 0
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

            sliderMark(data, chartType: .pumpRate)
        }
        .chartXAxisLabel("Step")
        .chartXScale(domain: 0...max(1, data.last?.globalIndex ?? 1))
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
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleDomainLength(data))
        .chartScrollPosition(x: $scrollPosition)
        .chartOverlay { proxy in
            scrubberOverlay(proxy: proxy, data: data)
        }
        .frame(height: UIDevice.current.userInterfaceIdiom == .phone ? 300 : 400)
        .padding(.horizontal, 4)
        .overlay(alignment: .topLeading) {
            Text("Pump Rate (m\u{00B3}/min)")
                .font(.caption2)
                .foregroundStyle(.purple)
                .padding(.leading, 8)
                .padding(.top, 2)
        }
        .overlay(alignment: .topTrailing) {
            Text("APL (kPa)")
                .font(.caption2)
                .foregroundStyle(.indigo)
                .padding(.trailing, 8)
                .padding(.top, 2)
        }
    }

    // MARK: - Legend

    @ViewBuilder
    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Legend")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            // Operation type bands
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                legendSwatch(color: .blue.opacity(0.1), label: "Trip Out", style: .fill)
                legendSwatch(color: .green.opacity(0.1), label: "Trip In", style: .fill)
                legendSwatch(color: .orange.opacity(0.1), label: "Circulate", style: .fill)
                legendSwatch(color: .purple.opacity(0.1), label: "Ream Out", style: .fill)
                legendSwatch(color: .pink.opacity(0.1), label: "Ream In", style: .fill)
            }

            Divider()

            // Line colors (match macOS)
            HStack(spacing: 12) {
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
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Current Value Card

    private func currentValueCard(_ data: [SuperSimViewModel.TimelineChartPoint]) -> some View {
        let sliderIdx = Int(viewModel.globalStepSliderValue.rounded())
        guard sliderIdx >= 0, sliderIdx < data.count else {
            return AnyView(EmptyView())
        }
        let point = data[sliderIdx]

        return AnyView(
            HStack(spacing: 12) {
                // Operation badge
                Text(point.operationLabel)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(bandColor(point.operationType).opacity(3))
                    .clipShape(Capsule())

                Text("MD: \(String(format: "%.0f", point.bitMD_m))m")
                    .font(.caption)
                    .monospacedDigit()

                Spacer()

                // Values based on chart type
                switch chartType {
                case .esd:
                    Text("Mud: \(String(format: "%.1f", point.ESDAtControl_kgpm3))")
                        .font(.caption.monospacedDigit())
                    if point.SABP_kPa > 0 {
                        Text("+ BP: \(String(format: "%.1f", point.totalESD_kgpm3))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.cyan)
                    }
                case .backPressure:
                    Text("S: \(String(format: "%.0f", point.SABP_kPa))")
                        .font(.caption.monospacedDigit())
                    Text("D: \(String(format: "%.0f", point.dynamicSABP_kPa))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                case .pumpRate:
                    Text("Rate: \(String(format: "%.2f", point.pumpRate_m3perMin))")
                        .font(.caption.monospacedDigit())
                    Text("APL: \(String(format: "%.0f", point.apl_kPa))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        )
    }

    // MARK: - Scrubber Overlay (touch drag)

    private func scrubberOverlay(proxy: ChartProxy, data: [SuperSimViewModel.TimelineChartPoint]) -> some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDraggingScrubber = true
                            if let plotFrame = proxy.plotFrame {
                                let plotOrigin = geo[plotFrame].origin
                                let x = value.location.x - plotOrigin.x
                                if let stepValue: Int = proxy.value(atX: x) {
                                    let step = max(0, min(stepValue, data.count - 1))
                                    viewModel.globalStepSliderValue = Double(step)
                                }
                            }
                        }
                        .onEnded { _ in
                            isDraggingScrubber = false
                        }
                )
        }
    }

    // MARK: - Zoom & Helpers

    private var zoomControls: some View {
        HStack {
            Text("Zoom:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $zoomLevel, in: 0.2...1.0, step: 0.1)
                .frame(maxWidth: 200)
            Text("\(Int((1.0 / zoomLevel).rounded()))x")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 40)
        }
    }

    private func visibleDomainLength(_ data: [SuperSimViewModel.TimelineChartPoint]) -> Int {
        let total = data.count
        return max(20, Int(Double(total) * zoomLevel))
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Data")
                .font(.headline)
            Text("Run operations to see the timeline chart.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#endif
