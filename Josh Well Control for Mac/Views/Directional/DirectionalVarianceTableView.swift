//
//  DirectionalVarianceTableView.swift
//  Josh Well Control for Mac
//
//  Color-coded table showing variance metrics for each survey station.
//

import SwiftUI

struct DirectionalVarianceTableView: View {
    let variances: [SurveyVariance]
    let limits: DirectionalLimits
    @Binding var hoveredVariance: SurveyVariance?
    var onHover: (SurveyVariance?) -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        headerRow
                        Divider()
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(spacing: 0) {
                                ForEach(variances) { variance in
                                    dataRow(variance)
                                    Divider()
                                }
                            }
                        }
                        .frame(maxHeight: 300)
                    }
                    .frame(minWidth: 1400)  // Ensure horizontal scroll works
                }
            }
        } label: {
            HStack {
                Label("Variance Table", systemImage: "tablecells")
                Spacer()
                Text("\(variances.count) stations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 0) {
            // Position
            headerCell("MD", width: 60)

            // Actual Rates
            Group {
                headerCell("DLS", width: 55)
                headerCell("BR", width: 55)
                headerCell("TR", width: 55)
            }

            // Plan Rates
            Group {
                headerCell("Plan DLS", width: 65)
                headerCell("Plan BR", width: 60)
                headerCell("Plan TR", width: 60)
            }

            // Required Rates (to get back on plan)
            Group {
                headerCell("Req BR", width: 60)
                headerCell("Req TR", width: 60)
            }

            // Position Variances
            Group {
                headerCell("TVD Var", width: 70)
                headerCell("VS Var", width: 70)
                headerCell("Closure", width: 65)
                headerCell("3D Dist", width: 65)
            }

            // Angle Variances
            Group {
                headerCell("Inc Δ", width: 55)
                headerCell("Azi Δ", width: 55)
            }

            headerCell("Status", width: 70)
            Spacer()
        }
        .font(.caption2)
        .fontWeight(.medium)
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .background(Color.gray.opacity(0.05))
    }

    private func headerCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .frame(width: width, alignment: .trailing)
    }

    // MARK: - Data Row

    private func dataRow(_ variance: SurveyVariance) -> some View {
        let status = variance.status(for: limits)
        let isHovered = hoveredVariance?.id == variance.id

        return HStack(spacing: 0) {
            // Position
            dataCell(String(format: "%.0f", variance.surveyMD), width: 60)

            // Actual Rates
            dataCell(String(format: "%.2f", variance.surveyDLS), width: 55)
                .foregroundStyle(variance.dlsStatus(for: limits).color)
            dataCell(formatRate(variance.surveyBR), width: 55)
                .foregroundStyle(rateColor(variance.surveyBR, plan: variance.planBR))
            dataCell(formatRate(variance.surveyTR), width: 55)
                .foregroundStyle(rateColor(variance.surveyTR, plan: variance.planTR))

            // Plan Rates
            dataCell(String(format: "%.2f", variance.planDLS), width: 65)
                .foregroundStyle(.secondary)
            dataCell(formatRate(variance.planBR), width: 60)
                .foregroundStyle(.secondary)
            dataCell(formatRate(variance.planTR), width: 60)
                .foregroundStyle(.secondary)

            // Required Rates
            dataCell(formatRate(variance.requiredBR), width: 60)
                .foregroundStyle(requiredRateColor(variance.requiredBR))
            dataCell(formatRate(variance.requiredTR), width: 60)
                .foregroundStyle(requiredRateColor(variance.requiredTR))

            // Position Variances
            dataCell(formatVariance(variance.tvdVariance), width: 70)
                .foregroundStyle(variance.tvdStatus(for: limits).color)
            dataCell(formatVariance(variance.vsVariance), width: 70)
            dataCell(String(format: "%.1f", variance.closureDistance), width: 65)
                .foregroundStyle(variance.closureStatus(for: limits).color)
            dataCell(String(format: "%.1f", variance.distance3D), width: 65)
                .foregroundStyle(variance.distance3DStatus(for: limits).color)

            // Angle Variances
            dataCell(formatVariance(variance.incVariance, decimals: 1), width: 55)
            dataCell(formatVariance(variance.aziVariance, decimals: 1), width: 55)

            statusCell(status, width: 70)

            Spacer()
        }
        .font(.caption)
        .monospacedDigit()
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(isHovered ? Color.blue.opacity(0.15) : status.color.opacity(0.05))
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                onHover(variance)
            } else if hoveredVariance?.id == variance.id {
                onHover(nil)
            }
        }
    }

    private func dataCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .frame(width: width, alignment: .trailing)
    }

    private func statusCell(_ status: VarianceStatus, width: CGFloat) -> some View {
        HStack(spacing: 2) {
            Image(systemName: status.icon)
                .foregroundStyle(status.color)
                .font(.caption2)
            Text(status.label)
                .font(.caption2)
        }
        .frame(width: width, alignment: .center)
    }

    // MARK: - Formatting

    private func formatVariance(_ value: Double, decimals: Int = 1) -> String {
        let sign = value >= 0 ? "+" : ""
        return String(format: "\(sign)%.\(decimals)f", value)
    }

    private func formatRate(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return String(format: "\(sign)%.2f", value)
    }

    /// Color for actual rate compared to plan rate
    private func rateColor(_ actual: Double, plan: Double) -> Color {
        let diff = abs(actual - plan)
        if diff < 0.5 { return .green }
        if diff < 1.5 { return .primary }
        return .orange
    }

    /// Color for required rate (higher = more correction needed)
    private func requiredRateColor(_ rate: Double) -> Color {
        let absRate = abs(rate)
        if absRate < 1.0 { return .green }
        if absRate < 3.0 { return .yellow }
        return .red
    }
}
