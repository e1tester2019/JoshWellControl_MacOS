//
//  TopProfileChartView.swift
//  Josh Well Control for Mac
//
//  Top view chart showing NS vs EW with plan and actual trajectories.
//

import SwiftUI
import Charts

struct TopProfileChartView: View {
    let variances: [SurveyVariance]
    let plan: DirectionalPlan?
    let limits: DirectionalLimits
    let bitProjection: BitProjection?  // Optional bit projection to display
    @Binding var hoveredMD: Double?
    var onHover: (Double?) -> Void

    // Zoom and pan state
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero

    // Rectangle selection for zoom
    @State private var selectionRect: CGRect? = nil
    @State private var selectionStart: CGPoint? = nil
    @State private var isSelectingRect: Bool = false

    // Custom domain override (set by rect selection)
    @State private var customEwRange: ClosedRange<Double>? = nil
    @State private var customNsRange: ClosedRange<Double>? = nil

    private var planStations: [DirectionalPlanStation] {
        plan?.sortedStations ?? []
    }

    // Compute data ranges for proper scaling
    private var dataRanges: (ewMin: Double, ewMax: Double, nsMin: Double, nsMax: Double) {
        var ewValues: [Double] = []
        var nsValues: [Double] = []

        for station in planStations {
            ewValues.append(station.ew_m)
            nsValues.append(station.ns_m)
        }

        for v in variances {
            ewValues.append(v.surveyEW)
            nsValues.append(v.surveyNS)
        }

        // Include bit projection if available
        if let bit = bitProjection {
            ewValues.append(bit.bitEW)
            nsValues.append(bit.bitNS)
        }

        var ewMin = ewValues.min() ?? 0
        var ewMax = ewValues.max() ?? 100
        var nsMin = nsValues.min() ?? 0
        var nsMax = nsValues.max() ?? 100

        // Ensure we have valid ranges (min < max)
        if ewMin >= ewMax {
            ewMin = ewMax - 100
        }
        if nsMin >= nsMax {
            nsMax = nsMin + 100
        }

        // Add some padding
        let ewPadding = max((ewMax - ewMin) * 0.05, 10)
        let nsPadding = max((nsMax - nsMin) * 0.05, 10)

        return (ewMin - ewPadding, ewMax + ewPadding, nsMin - nsPadding, nsMax + nsPadding)
    }

    // Adjusted ranges based on zoom/pan or custom selection
    private var adjustedRanges: (ewMin: Double, ewMax: Double, nsMin: Double, nsMax: Double) {
        // If custom ranges are set (from rect selection), use them
        if let ewRange = customEwRange, let nsRange = customNsRange {
            return (ewRange.lowerBound, ewRange.upperBound, nsRange.lowerBound, nsRange.upperBound)
        }

        let ranges = dataRanges
        let ewRange = max(ranges.ewMax - ranges.ewMin, 1)  // Ensure positive range
        let nsRange = max(ranges.nsMax - ranges.nsMin, 1)

        // Apply zoom
        let ewCenter = (ranges.ewMin + ranges.ewMax) / 2
        let nsCenter = (ranges.nsMin + ranges.nsMax) / 2
        let zoomedEwRange = ewRange / scale
        let zoomedNsRange = nsRange / scale

        // Apply pan
        let ewOffset = -Double(offset.width) * zoomedEwRange / 400
        let nsOffset = Double(offset.height) * zoomedNsRange / 400

        return (
            ewCenter + ewOffset - zoomedEwRange / 2,
            ewCenter + ewOffset + zoomedEwRange / 2,
            nsCenter + nsOffset - zoomedNsRange / 2,
            nsCenter + nsOffset + zoomedNsRange / 2
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                hoverInfo
                Spacer()
                // Zoom controls
                HStack(spacing: 4) {
                    // Rectangle selection toggle
                    Toggle(isOn: $isSelectingRect) {
                        Image(systemName: "rectangle.dashed")
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.borderless)
                    .help("Drag to select zoom area")
                    .foregroundStyle(isSelectingRect ? .blue : .primary)

                    Divider()
                        .frame(height: 16)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scale = max(0.5, scale - 0.25)
                            customEwRange = nil
                            customNsRange = nil
                        }
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .buttonStyle(.borderless)

                    Text(customEwRange != nil ? "Custom" : "\(Int(scale * 100))%")
                        .font(.caption2)
                        .monospacedDigit()
                        .frame(width: 45)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scale = min(5.0, scale + 0.25)
                            customEwRange = nil
                            customNsRange = nil
                        }
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scale = 1.0
                            offset = .zero
                            customEwRange = nil
                            customNsRange = nil
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Reset zoom")
                }
            }
            chartView
        }
    }

    // MARK: - Hover Info

    private var hoverInfo: some View {
        HStack {
            if let md = hoveredMD,
               let variance = variances.min(by: { abs($0.surveyMD - md) < abs($1.surveyMD - md) }) {
                HStack(spacing: 12) {
                    Text("MD: \(Int(variance.surveyMD))m")
                        .monospacedDigit()
                    Text("Closure: \(SurveyVariance.formatDistance(variance.closureDistance))")
                        .foregroundStyle(variance.closureStatus(for: limits).color)
                        .monospacedDigit()
                    Text("3D Dist: \(SurveyVariance.formatDistance(variance.distance3D))")
                        .foregroundStyle(variance.distance3DStatus(for: limits).color)
                        .monospacedDigit()
                }
                .font(.caption)
            }
            Spacer()
        }
        .frame(height: 20)
    }

    // MARK: - Chart

    private var chartView: some View {
        Group {
            if !planStations.isEmpty || !variances.isEmpty {
                Chart {
                    // Plan trajectory (green dashed line)
                    ForEach(Array(planStations.enumerated()), id: \.offset) { index, station in
                        LineMark(
                            x: .value("EW", station.ew_m),
                            y: .value("NS", station.ns_m),
                            series: .value("Series", "Plan")
                        )
                        .foregroundStyle(.green.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    }

                    // Actual trajectory with color-coded points
                    ForEach(Array(variances.enumerated()), id: \.offset) { index, v in
                        // Line connecting points
                        LineMark(
                            x: .value("EW", v.surveyEW),
                            y: .value("NS", v.surveyNS),
                            series: .value("Series", "Actual")
                        )
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }

                    // Color-coded survey points
                    ForEach(variances) { v in
                        let status = v.status(for: limits)
                        PointMark(
                            x: .value("EW", v.surveyEW),
                            y: .value("NS", v.surveyNS)
                        )
                        .foregroundStyle(status.color)
                        .symbolSize(40)
                    }

                    // Bit projection - line from last survey to bit
                    if let bit = bitProjection, let lastVariance = variances.last {
                        // Dashed line from last survey to bit
                        LineMark(
                            x: .value("EW", lastVariance.surveyEW),
                            y: .value("NS", lastVariance.surveyNS),
                            series: .value("Series", "BitProjection")
                        )
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))

                        LineMark(
                            x: .value("EW", bit.bitEW),
                            y: .value("NS", bit.bitNS),
                            series: .value("Series", "BitProjection")
                        )
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))

                        // Bit position marker
                        let bitStatus = bit.status(for: limits)
                        PointMark(
                            x: .value("EW", bit.bitEW),
                            y: .value("NS", bit.bitNS)
                        )
                        .foregroundStyle(bitStatus.color)
                        .symbolSize(80)
                        .symbol(.diamond)
                        .annotation(position: .top, spacing: 4) {
                            Text("BIT")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.orange)
                        }

                        // Show plan position at bit MD
                        PointMark(
                            x: .value("EW", bit.planEW),
                            y: .value("NS", bit.planNS)
                        )
                        .foregroundStyle(.green.opacity(0.7))
                        .symbolSize(50)
                        .symbol(.circle)
                    }

                    // Hover indicator
                    if let md = hoveredMD,
                       let v = variances.min(by: { abs($0.surveyMD - md) < abs($1.surveyMD - md) }) {
                        // Highlight actual point
                        PointMark(
                            x: .value("EW", v.surveyEW),
                            y: .value("NS", v.surveyNS)
                        )
                        .foregroundStyle(.primary)
                        .symbolSize(120)
                        .symbol(.circle)

                        // Show plan point at same MD
                        PointMark(
                            x: .value("EW", v.planEW),
                            y: .value("NS", v.planNS)
                        )
                        .foregroundStyle(.green)
                        .symbolSize(80)
                        .symbol(.diamond)

                        // Line connecting actual to plan (offset visualization)
                        LineMark(
                            x: .value("EW", v.surveyEW),
                            y: .value("NS", v.surveyNS)
                        )
                        .foregroundStyle(.orange.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [2, 2]))

                        LineMark(
                            x: .value("EW", v.planEW),
                            y: .value("NS", v.planNS)
                        )
                        .foregroundStyle(.orange.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [2, 2]))
                    }
                }
                .chartXScale(domain: adjustedRanges.ewMin...adjustedRanges.ewMax)
                .chartYScale(domain: adjustedRanges.nsMin...adjustedRanges.nsMax)
                .chartXAxisLabel("East-West (m)")
                .chartYAxisLabel("North-South (m)")
                .chartLegend(.hidden)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        ZStack {
                            // Hover and selection handling
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    guard !isSelectingRect else { return }
                                    switch phase {
                                    case .active(let location):
                                        if let plotFrame = proxy.plotFrame {
                                            let plotAreaOrigin = geo[plotFrame].origin
                                            let x = location.x - plotAreaOrigin.x
                                            let y = location.y - plotAreaOrigin.y

                                            if let ew: Double = proxy.value(atX: x),
                                               let ns: Double = proxy.value(atY: y) {
                                                if let closest = variances.min(by: {
                                                    let d1 = sqrt(pow($0.surveyEW - ew, 2) + pow($0.surveyNS - ns, 2))
                                                    let d2 = sqrt(pow($1.surveyEW - ew, 2) + pow($1.surveyNS - ns, 2))
                                                    return d1 < d2
                                                }) {
                                                    onHover(closest.surveyMD)
                                                }
                                            }
                                        }
                                    case .ended:
                                        onHover(nil)
                                    }
                                }
                                .gesture(
                                    DragGesture(minimumDistance: 5)
                                        .onChanged { value in
                                            if isSelectingRect {
                                                if selectionStart == nil {
                                                    selectionStart = value.startLocation
                                                }
                                                if let start = selectionStart {
                                                    let minX = min(start.x, value.location.x)
                                                    let minY = min(start.y, value.location.y)
                                                    let width = abs(value.location.x - start.x)
                                                    let height = abs(value.location.y - start.y)
                                                    selectionRect = CGRect(x: minX, y: minY, width: width, height: height)
                                                }
                                            } else {
                                                // Regular pan
                                                offset = CGSize(
                                                    width: lastOffset.width + value.translation.width,
                                                    height: lastOffset.height + value.translation.height
                                                )
                                            }
                                        }
                                        .onEnded { value in
                                            if isSelectingRect, let rect = selectionRect, let plotFrame = proxy.plotFrame {
                                                let plotArea = geo[plotFrame]

                                                // Convert rect to data coordinates
                                                let relativeRect = CGRect(
                                                    x: rect.minX - plotArea.minX,
                                                    y: rect.minY - plotArea.minY,
                                                    width: rect.width,
                                                    height: rect.height
                                                )

                                                if let ewMin: Double = proxy.value(atX: relativeRect.minX),
                                                   let ewMax: Double = proxy.value(atX: relativeRect.maxX),
                                                   let nsMax: Double = proxy.value(atY: relativeRect.minY),
                                                   let nsMin: Double = proxy.value(atY: relativeRect.maxY) {

                                                    withAnimation(.easeInOut(duration: 0.3)) {
                                                        customEwRange = min(ewMin, ewMax)...max(ewMin, ewMax)
                                                        customNsRange = min(nsMin, nsMax)...max(nsMin, nsMax)
                                                    }
                                                }

                                                selectionRect = nil
                                                selectionStart = nil
                                                isSelectingRect = false
                                            } else {
                                                lastOffset = offset
                                            }
                                        }
                                )

                            // Selection rectangle overlay
                            if let rect = selectionRect {
                                Rectangle()
                                    .stroke(Color.blue, lineWidth: 2)
                                    .background(Color.blue.opacity(0.1))
                                    .frame(width: rect.width, height: rect.height)
                                    .position(x: rect.midX, y: rect.midY)
                            }
                        }
                    }
                }
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            customEwRange = nil
                            customNsRange = nil
                            scale = max(0.5, min(5.0, lastScale * value))
                        }
                        .onEnded { _ in
                            lastScale = scale
                        }
                )
                .frame(minHeight: 300)
            } else {
                emptyPlaceholder
            }
        }
    }

    private var emptyPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.05))
            VStack(spacing: 6) {
                Image(systemName: "viewfinder")
                    .foregroundStyle(.secondary)
                Text("No data available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 300)
    }
}
