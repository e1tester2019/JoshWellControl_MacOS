//
//  SuperSimTimelineChartIOS.swift
//  Josh Well Control for Mac
//
//  iOS/iPadOS optimized timeline chart for Super Simulation.
//  Supports touch interaction, pinch zoom, and adaptive layout.
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
        VStack(spacing: 12) {
            // Header with chart type selector
            HStack {
                Picker("Chart Type", selection: $chartType) {
                    ForEach(ChartType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                
                Button {
                    showLegend.toggle()
                } label: {
                    Image(systemName: showLegend ? "info.circle.fill" : "info.circle")
                        .imageScale(.large)
                }
            }
            .padding(.horizontal)
            
            // Legend (collapsible)
            if showLegend {
                legendView
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Current value card (always visible when data exists)
            let data = viewModel.timelineChartData
            if !data.isEmpty {
                currentValueCard(data)
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            if data.isEmpty {
                emptyPlaceholder
            } else {
                // Chart
                chartView(data)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Zoom controls for iPad
                if sizeClass == .regular {
                    zoomControls
                        .padding(.horizontal)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showLegend)
        .animation(.easeInOut(duration: 0.2), value: viewModel.globalStepSliderValue)
    }
    
    // MARK: - Chart View
    
    @ViewBuilder
    private func chartView(_ data: [SuperSimViewModel.TimelineChartPoint]) -> some View {
        switch chartType {
        case .esd:
            esdChart(data)
        case .backPressure:
            backPressureChart(data)
        case .pumpRate:
            pumpRateChart(data)
        }
    }
    
    // MARK: - ESD Chart
    
    private func esdChart(_ data: [SuperSimViewModel.TimelineChartPoint]) -> some View {
        let allValues = data.flatMap { [$0.ESDAtControl_kgpm3, $0.totalESD_kgpm3] }
        let yMin = (allValues.min() ?? 0) - 20
        let yMax = (allValues.max() ?? 2000) + 20
        
        return Chart {
            operationBands(data, yMin: yMin, yMax: yMax)
            
            // Mud column (ESD without back pressure)
            ForEach(data) { point in
                LineMark(
                    x: .value("Step", point.globalIndex),
                    y: .value("Mud Column", point.ESDAtControl_kgpm3)
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.linear)
            }
            
            // Mud + BP (total ESD including back pressure)
            ForEach(data) { point in
                LineMark(
                    x: .value("Step", point.globalIndex),
                    y: .value("Mud + BP", point.totalESD_kgpm3)
                )
                .foregroundStyle(.cyan)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 2]))
                .interpolationMethod(.linear)
            }
            
            // Slider position indicator
            sliderIndicator(data)
        }
        .chartXScale(domain: 0...max(1, data.count - 1))
        .chartYScale(domain: yMin...yMax)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(String(format: "%.0f", v))
                            .font(.caption)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)")
                            .font(.caption)
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
    }
    
    // MARK: - Back Pressure Chart
    
    private func backPressureChart(_ data: [SuperSimViewModel.TimelineChartPoint]) -> some View {
        let allSABP = data.flatMap { [$0.SABP_kPa, $0.dynamicSABP_kPa] }
        let yMin = max(0, (allSABP.min() ?? 0) - 50)
        let yMax = (allSABP.max() ?? 1000) + 50
        
        return Chart {
            operationBands(data, yMin: yMin, yMax: yMax)
            
            // Static SABP
            ForEach(data) { point in
                LineMark(
                    x: .value("Step", point.globalIndex),
                    y: .value("Static", point.SABP_kPa)
                )
                .foregroundStyle(.red)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.linear)
            }
            
            // Dynamic SABP
            ForEach(data) { point in
                LineMark(
                    x: .value("Step", point.globalIndex),
                    y: .value("Dynamic", point.dynamicSABP_kPa)
                )
                .foregroundStyle(.orange)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 2]))
                .interpolationMethod(.linear)
            }
            
            sliderIndicator(data)
        }
        .chartXScale(domain: 0...max(1, data.count - 1))
        .chartYScale(domain: yMin...yMax)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(String(format: "%.0f", v))
                            .font(.caption)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)")
                            .font(.caption)
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
    }
    
    // MARK: - Pump Rate Chart
    
    private func pumpRateChart(_ data: [SuperSimViewModel.TimelineChartPoint]) -> some View {
        let allRates = data.map(\.pumpRate_m3perMin)
        let rateMin = 0.0
        let rateMax = (allRates.max() ?? 1.5) + 0.1
        
        return Chart {
            operationBands(data, yMin: rateMin, yMax: rateMax)
            
            // Pump rate
            ForEach(data) { point in
                LineMark(
                    x: .value("Step", point.globalIndex),
                    y: .value("Pump Rate", point.pumpRate_m3perMin)
                )
                .foregroundStyle(.purple)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.linear)
            }
            
            // APL as area
            ForEach(data) { point in
                AreaMark(
                    x: .value("Step", point.globalIndex),
                    y: .value("APL", min(point.apl_kPa / 200, rateMax)) // Normalize APL to fit
                )
                .foregroundStyle(.indigo.opacity(0.2))
                .interpolationMethod(.linear)
            }
            
            sliderIndicator(data)
        }
        .chartXScale(domain: 0...max(1, data.count - 1))
        .chartYScale(domain: rateMin...rateMax)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(String(format: "%.2f", v))
                            .font(.caption)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)")
                            .font(.caption)
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
    }
    
    // MARK: - Chart Components
    
    @ChartContentBuilder
    private func operationBands(_ data: [SuperSimViewModel.TimelineChartPoint], yMin: Double, yMax: Double) -> some ChartContent {
        let ranges = viewModel.operationRanges
        ForEach(Array(ranges.enumerated()), id: \.offset) { _, range in
            RectangleMark(
                xStart: .value("Start", range.start),
                xEnd: .value("End", range.end + 1),
                yStart: .value("YMin", yMin),
                yEnd: .value("YMax", yMax)
            )
            .foregroundStyle(bandColor(range.type))
            .opacity(0.15)
        }
    }
    
    @ChartContentBuilder
    private func sliderIndicator(_ data: [SuperSimViewModel.TimelineChartPoint]) -> some ChartContent {
        let sliderIdx = Int(viewModel.globalStepSliderValue.rounded())
        if sliderIdx >= 0, sliderIdx < data.count {
            RuleMark(x: .value("Slider", sliderIdx))
                .foregroundStyle(Color.accentColor.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 2))
        }
    }
    
    private func bandColor(_ type: OperationType) -> Color {
        switch type {
        case .tripOut: return .blue
        case .tripIn: return .green
        case .circulate: return .orange
        case .reamOut: return .purple
        case .reamIn: return .pink
        }
    }
    
    // MARK: - Scrubber Overlay (Enhanced for direct chart interaction)
    
    private func scrubberOverlay(proxy: ChartProxy, data: [SuperSimViewModel.TimelineChartPoint]) -> some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDraggingScrubber = true
                            let location = value.location
                            if let plotFrame = proxy.plotFrame {
                                let plotOrigin = geo[plotFrame].origin
                                let x = location.x - plotOrigin.x
                                if let stepValue: Int = proxy.value(atX: x) {
                                    let step = max(0, min(stepValue, data.count - 1))
                                    // Update slider to enable scrubbing
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
    
    // MARK: - Info Views
    
    // Current value card - always visible, shows slider position
    private func currentValueCard(_ data: [SuperSimViewModel.TimelineChartPoint]) -> some View {
        let sliderIdx = Int(viewModel.globalStepSliderValue.rounded())
        guard sliderIdx >= 0, sliderIdx < data.count else {
            return AnyView(EmptyView())
        }
        let point = data[sliderIdx]
        
        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Current Position")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Step \(sliderIdx) of \(data.count - 1)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                
                HStack {
                    // Operation label
                    Text(point.operationLabel)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(bandColor(point.operationType).opacity(0.3))
                        .clipShape(Capsule())
                    
                    Spacer()
                    
                    // MD
                    Text("MD: \(String(format: "%.0f", point.bitMD_m)) m")
                        .font(.caption)
                        .monospacedDigit()
                }
                
                // Values based on chart type
                HStack(spacing: 16) {
                    switch chartType {
                    case .esd:
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mud Column")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(String(format: "%.1f", point.ESDAtControl_kgpm3)) kg/m³")
                                .font(.callout.bold().monospacedDigit())
                                .foregroundStyle(.blue)
                        }
                        if point.SABP_kPa > 0 {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Mud + BP")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("\(String(format: "%.1f", point.totalESD_kgpm3)) kg/m³")
                                    .font(.callout.bold().monospacedDigit())
                                    .foregroundStyle(.cyan)
                            }
                        }
                        
                    case .backPressure:
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Static SABP")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(String(format: "%.0f", point.SABP_kPa)) kPa")
                                .font(.callout.bold().monospacedDigit())
                                .foregroundStyle(.red)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dynamic SABP")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(String(format: "%.0f", point.dynamicSABP_kPa)) kPa")
                                .font(.callout.bold().monospacedDigit())
                                .foregroundStyle(.orange)
                        }
                        
                    case .pumpRate:
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pump Rate")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(String(format: "%.2f", point.pumpRate_m3perMin)) m³/min")
                                .font(.callout.bold().monospacedDigit())
                                .foregroundStyle(.purple)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("APL")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(String(format: "%.0f", point.apl_kPa)) kPa")
                                .font(.callout.bold().monospacedDigit())
                                .foregroundStyle(.indigo)
                        }
                    }
                    Spacer()
                }
            }
            .padding(12)
            .background(Color.accentColor.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        )
    }
    
    private var legendView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Legend")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            
            // Operation types
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                legendItem(color: .blue, label: "Trip Out")
                legendItem(color: .green, label: "Trip In")
                legendItem(color: .orange, label: "Circulate")
                legendItem(color: .purple, label: "Ream Out")
                legendItem(color: .pink, label: "Ream In")
            }
            
            Divider()
            
            // Lines
            switch chartType {
            case .esd:
                HStack(spacing: 12) {
                    legendLine(color: .blue, label: "Mud Column", dashed: false)
                    legendLine(color: .cyan, label: "Mud + BP", dashed: true)
                }
            case .backPressure:
                HStack(spacing: 12) {
                    legendLine(color: .red, label: "Static", dashed: false)
                    legendLine(color: .orange, label: "Dynamic", dashed: true)
                }
            case .pumpRate:
                HStack(spacing: 12) {
                    legendLine(color: .purple, label: "Pump Rate", dashed: false)
                    legendLine(color: .indigo.opacity(0.5), label: "APL (scaled)", dashed: false)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(0.3))
                .frame(width: 16, height: 12)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
    
    private func legendLine(color: Color, label: String, dashed: Bool) -> some View {
        HStack(spacing: 4) {
            if dashed {
                HStack(spacing: 2) {
                    Rectangle().fill(color).frame(width: 6, height: 2)
                    Rectangle().fill(color).frame(width: 6, height: 2)
                }
                .frame(width: 16)
            } else {
                Rectangle().fill(color).frame(width: 16, height: 2)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
    
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
    
    // MARK: - Helpers
    
    private func visibleDomainLength(_ data: [SuperSimViewModel.TimelineChartPoint]) -> Int {
        let total = data.count
        return max(20, Int(Double(total) * zoomLevel))
    }
}

// MARK: - Array Safe Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#endif
