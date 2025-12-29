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
    @Binding var hoveredMD: Double?
    var onHover: (Double?) -> Void

    private var planStations: [DirectionalPlanStation] {
        plan?.sortedStations ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            hoverInfo
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
                    ForEach(planStations, id: \.md) { station in
                        LineMark(
                            x: .value("EW", station.ew_m),
                            y: .value("NS", station.ns_m)
                        )
                        .foregroundStyle(.green.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    }

                    // Actual trajectory with color-coded points
                    ForEach(variances) { v in
                        // Line connecting points
                        LineMark(
                            x: .value("EW", v.surveyEW),
                            y: .value("NS", v.surveyNS)
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
                .chartXAxisLabel("East-West (m)")
                .chartYAxisLabel("North-South (m)")
                .chartLegend(position: .top)
                .chartOverlay { proxy in
                    chartHoverOverlay(proxy: proxy)
                }
                .frame(minHeight: 300)
            } else {
                emptyPlaceholder
            }
        }
    }

    private func chartHoverOverlay(proxy: ChartProxy) -> some View {
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
                            let y = location.y - plotAreaOrigin.y

                            if let ew: Double = proxy.value(atX: x),
                               let ns: Double = proxy.value(atY: y) {
                                // Find variance closest to this point
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
