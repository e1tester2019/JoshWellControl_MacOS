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
    @Binding var hoveredMD: Double?
    var onHover: (Double?) -> Void

    private var planStations: [DirectionalPlanStation] {
        plan?.sortedStations ?? []
    }

    private var vsAzimuthRad: Double {
        vsAzimuth * .pi / 180.0
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
                Chart {
                    // Plan trajectory (green dashed line)
                    ForEach(planStations, id: \.md) { station in
                        let vs = station.vs_m ?? DirectionalSurveyService.calculateVS(
                            ns: station.ns_m,
                            ew: station.ew_m,
                            vsdRad: vsAzimuthRad
                        )
                        LineMark(
                            x: .value("VS", vs),
                            y: .value("TVD", station.tvd)
                        )
                        .foregroundStyle(.green.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    }

                    // Actual trajectory with color-coded points
                    ForEach(variances) { v in
                        // Line connecting points
                        LineMark(
                            x: .value("VS", v.surveyVS),
                            y: .value("TVD", v.surveyTVD)
                        )
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }

                    // Color-coded survey points
                    ForEach(variances) { v in
                        let status = v.status(for: limits)
                        PointMark(
                            x: .value("VS", v.surveyVS),
                            y: .value("TVD", v.surveyTVD)
                        )
                        .foregroundStyle(status.color)
                        .symbolSize(40)
                    }

                    // Hover indicator
                    if let md = hoveredMD,
                       let v = variances.min(by: { abs($0.surveyMD - md) < abs($1.surveyMD - md) }) {
                        PointMark(
                            x: .value("VS", v.surveyVS),
                            y: .value("TVD", v.surveyTVD)
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
                .chartYScale(domain: .automatic(includesZero: true))
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let tvd = value.as(Double.self) {
                                Text("\(Int(tvd))")
                            }
                        }
                    }
                }
                .chartXAxisLabel("Vertical Section (m)")
                .chartYAxisLabel("TVD (m)")
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
                            if let vs: Double = proxy.value(atX: x) {
                                // Find variance closest to this VS
                                if let closest = variances.min(by: { abs($0.surveyVS - vs) < abs($1.surveyVS - vs) }) {
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
