//
//  SideProfileChartView.swift
//  Josh Well Control for Mac
//
//  Side view chart showing TVD vs Vertical Section with plan and actual trajectories.
//

import SwiftUI
import Charts

struct SideProfileChartView: View {
    let variances: [SurveyVariance]
    let plan: DirectionalPlan?
    let limits: DirectionalLimits
    let vsAzimuth: Double  // Effective VS azimuth (from plan or project)
    let bitProjection: BitProjection?  // Optional bit projection to display
    let formations: [FormationTop]
    let showFormations: Bool
    @Binding var hoveredMD: Double?
    var onHover: (Double?) -> Void

    // Palette for formation line colors
    private static let formationPalette: [Color] = [
        .brown, .purple, .cyan, .pink, .mint, .indigo, .teal, .orange
    ]

    private func formationColor(for index: Int, formation: FormationTop) -> Color {
        if let hex = formation.colorHex, let c = Color(hex: hex) {
            return c
        }
        return Self.formationPalette[index % Self.formationPalette.count]
    }

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
    @State private var customVsRange: ClosedRange<Double>? = nil
    @State private var customTvdRange: ClosedRange<Double>? = nil

    private var planStations: [DirectionalPlanStation] {
        plan?.sortedStations ?? []
    }

    private var vsAzimuthRad: Double {
        vsAzimuth * .pi / 180.0
    }

    // Compute data ranges for proper scaling
    private var dataRanges: (vsMin: Double, vsMax: Double, tvdMin: Double, tvdMax: Double) {
        var vsValues: [Double] = []
        var tvdValues: [Double] = []

        for station in planStations {
            let vs = station.vs_m ?? DirectionalSurveyService.calculateVS(
                ns: station.ns_m, ew: station.ew_m, vsdRad: vsAzimuthRad
            )
            vsValues.append(vs)
            tvdValues.append(station.tvd)
        }

        for v in variances {
            vsValues.append(v.surveyVS)
            tvdValues.append(v.surveyTVD)
        }

        // Include bit projection if available
        if let bit = bitProjection {
            vsValues.append(bit.bitVS)
            tvdValues.append(bit.bitTVD)
        }

        var vsMin = vsValues.min() ?? 0
        var vsMax = vsValues.max() ?? 100
        var tvdMin = tvdValues.min() ?? 0
        var tvdMax = tvdValues.max() ?? 100

        // Ensure we have valid ranges (min < max)
        if vsMin >= vsMax {
            vsMin = vsMax - 100
        }
        if tvdMin >= tvdMax {
            tvdMax = tvdMin + 100
        }

        // Add some padding
        let vsPadding = max((vsMax - vsMin) * 0.05, 10)
        let tvdPadding = max((tvdMax - tvdMin) * 0.05, 10)

        return (vsMin - vsPadding, vsMax + vsPadding, tvdMin - tvdPadding, tvdMax + tvdPadding)
    }

    // Adjusted ranges based on zoom/pan or custom selection
    private var adjustedRanges: (vsMin: Double, vsMax: Double, tvdMin: Double, tvdMax: Double) {
        // If custom ranges are set (from rect selection), use them
        if let vsRange = customVsRange, let tvdRange = customTvdRange {
            return (vsRange.lowerBound, vsRange.upperBound, tvdRange.lowerBound, tvdRange.upperBound)
        }

        let ranges = dataRanges
        let vsRange = max(ranges.vsMax - ranges.vsMin, 1)  // Ensure positive range
        let tvdRange = max(ranges.tvdMax - ranges.tvdMin, 1)

        // Apply zoom
        let vsCenter = (ranges.vsMin + ranges.vsMax) / 2
        let tvdCenter = (ranges.tvdMin + ranges.tvdMax) / 2
        let zoomedVsRange = vsRange / scale
        let zoomedTvdRange = tvdRange / scale

        // Apply pan (offset is in points, convert to data units)
        let vsOffset = -Double(offset.width) * zoomedVsRange / 400  // Rough conversion
        let tvdOffset = Double(offset.height) * zoomedTvdRange / 400

        return (
            vsCenter + vsOffset - zoomedVsRange / 2,
            vsCenter + vsOffset + zoomedVsRange / 2,
            tvdCenter + tvdOffset - zoomedTvdRange / 2,
            tvdCenter + tvdOffset + zoomedTvdRange / 2
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
                            customVsRange = nil
                            customTvdRange = nil
                        }
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .buttonStyle(.borderless)

                    Text(customVsRange != nil ? "Custom" : "\(Int(scale * 100))%")
                        .font(.caption2)
                        .monospacedDigit()
                        .frame(width: 45)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scale = min(5.0, scale + 0.25)
                            customVsRange = nil
                            customTvdRange = nil
                        }
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scale = 1.0
                            offset = .zero
                            customVsRange = nil
                            customTvdRange = nil
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
                    Text("TVD Var: \(SurveyVariance.formatVariance(variance.tvdVariance))")
                        .foregroundStyle(variance.tvdStatus(for: limits).color)
                        .monospacedDigit()
                    Text("VS Var: \(SurveyVariance.formatVariance(variance.vsVariance))")
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
                let ranges = adjustedRanges
                Chart {
                    // Formation lines (behind everything else)
                    if showFormations {
                        ForEach(Array(formations.enumerated()), id: \.element.id) { index, formation in
                            // Dip angle is from vertical: 90° = horizontal, 0° = vertical
                            // Slope from horizontal = tan(90° - dipAngle)
                            let slopeRad = (90.0 - formation.dipAngle_deg) * .pi / 180.0
                            let tanSlope = tan(slopeRad)
                            let color = formationColor(for: index, formation: formation)
                            let seriesID = "Fm_\(formation.id.uuidString)"

                            // Use multiple points so the line clips correctly at all zoom levels
                            ForEach(0..<11, id: \.self) { i in
                                let vs = ranges.vsMin + (ranges.vsMax - ranges.vsMin) * Double(i) / 10.0
                                let tvd = formation.tvdTop_m + vs * tanSlope
                                LineMark(
                                    x: .value("VS", vs),
                                    y: .value("TVD", -tvd),
                                    series: .value("Series", seriesID)
                                )
                                .foregroundStyle(color.opacity(0.6))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [8, 4]))
                            }

                            // Label at right edge
                            let labelTVD = formation.tvdTop_m + ranges.vsMax * tanSlope
                            let dipFromHoriz = 90.0 - formation.dipAngle_deg
                            PointMark(
                                x: .value("VS", ranges.vsMax),
                                y: .value("TVD", -labelTVD)
                            )
                            .foregroundStyle(.clear)
                            .symbolSize(1)
                            .annotation(position: .topTrailing, spacing: 2) {
                                Text("\(formation.name)\(abs(dipFromHoriz) > 0.05 ? String(format: " %.1f°", dipFromHoriz) : "")")
                                    .font(.caption2)
                                    .foregroundStyle(color)
                            }
                        }
                    }

                    // Plan trajectory (green dashed line)
                    // Negate TVD to flip axis (depth increases downward)
                    ForEach(Array(planStations.enumerated()), id: \.offset) { index, station in
                        let vs = station.vs_m ?? DirectionalSurveyService.calculateVS(
                            ns: station.ns_m,
                            ew: station.ew_m,
                            vsdRad: vsAzimuthRad
                        )
                        LineMark(
                            x: .value("VS", vs),
                            y: .value("TVD", -station.tvd),
                            series: .value("Series", "Plan")
                        )
                        .foregroundStyle(.green.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    }

                    // Actual trajectory with color-coded points
                    ForEach(Array(variances.enumerated()), id: \.offset) { index, v in
                        // Line connecting points
                        LineMark(
                            x: .value("VS", v.surveyVS),
                            y: .value("TVD", -v.surveyTVD),
                            series: .value("Series", "Actual")
                        )
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }

                    // Color-coded survey points
                    ForEach(variances) { v in
                        let status = v.status(for: limits)
                        PointMark(
                            x: .value("VS", v.surveyVS),
                            y: .value("TVD", -v.surveyTVD)
                        )
                        .foregroundStyle(status.color)
                        .symbolSize(40)
                    }

                    // Bit projection - line from last survey to bit
                    if let bit = bitProjection, let lastVariance = variances.last {
                        // Dashed line from last survey to bit
                        LineMark(
                            x: .value("VS", lastVariance.surveyVS),
                            y: .value("TVD", -lastVariance.surveyTVD),
                            series: .value("Series", "BitProjection")
                        )
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))

                        LineMark(
                            x: .value("VS", bit.bitVS),
                            y: .value("TVD", -bit.bitTVD),
                            series: .value("Series", "BitProjection")
                        )
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))

                        // Bit position marker (triangle pointing down)
                        let bitStatus = bit.status(for: limits)
                        PointMark(
                            x: .value("VS", bit.bitVS),
                            y: .value("TVD", -bit.bitTVD)
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
                            x: .value("VS", bit.planVS),
                            y: .value("TVD", -bit.planTVD)
                        )
                        .foregroundStyle(.green.opacity(0.7))
                        .symbolSize(50)
                        .symbol(.circle)
                    }

                    // Hover indicator
                    if let md = hoveredMD,
                       let v = variances.min(by: { abs($0.surveyMD - md) < abs($1.surveyMD - md) }) {
                        PointMark(
                            x: .value("VS", v.surveyVS),
                            y: .value("TVD", -v.surveyTVD)
                        )
                        .foregroundStyle(.primary)
                        .symbolSize(120)
                        .symbol(.circle)

                        // Vertical line to show connection to plan
                        RuleMark(x: .value("VS", v.surveyVS))
                            .foregroundStyle(.primary.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                // Domain uses negated values (so -tvdMax to -tvdMin gives proper order)
                .chartYScale(domain: -ranges.tvdMax ... -ranges.tvdMin)
                .chartXScale(domain: ranges.vsMin...ranges.vsMax)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            // Display as positive (negate the negated value)
                            if let tvd = value.as(Double.self) {
                                Text("\(Int(-tvd))")
                            }
                        }
                    }
                }
                .chartXAxisLabel("Vertical Section (m)")
                .chartYAxisLabel("TVD (m)")
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
                                            if let vs: Double = proxy.value(atX: x) {
                                                if let closest = variances.min(by: { abs($0.surveyVS - vs) < abs($1.surveyVS - vs) }) {
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

                                                if let vsMin: Double = proxy.value(atX: relativeRect.minX),
                                                   let vsMax: Double = proxy.value(atX: relativeRect.maxX),
                                                   let tvdMinNeg: Double = proxy.value(atY: relativeRect.minY),
                                                   let tvdMaxNeg: Double = proxy.value(atY: relativeRect.maxY) {
                                                    // Convert back from negated values
                                                    let tvdMin = min(-tvdMinNeg, -tvdMaxNeg)
                                                    let tvdMax = max(-tvdMinNeg, -tvdMaxNeg)

                                                    withAnimation(.easeInOut(duration: 0.3)) {
                                                        customVsRange = min(vsMin, vsMax)...max(vsMin, vsMax)
                                                        customTvdRange = tvdMin...tvdMax
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
                            customVsRange = nil
                            customTvdRange = nil
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
                Image(systemName: "chart.xyaxis.line")
                    .foregroundStyle(.secondary)
                Text("No data available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 300)
    }
}
