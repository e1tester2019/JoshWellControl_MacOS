//
//  EquipmentHubKPIStripIOS.swift
//  Josh Well Control for Mac
//
//  Adaptive KPI grid for iOS Equipment Hub — 2-col on iPhone, HStack on iPad.
//

import SwiftUI

#if os(iOS)
struct EquipmentHubKPIStripIOS: View {
    let kpis: EquipmentKPIData
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var costString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: kpis.dailyCost)) ?? "$0"
    }

    var body: some View {
        if sizeClass == .regular {
            // iPad: horizontal strip
            HStack(spacing: 10) {
                kpiCards
            }
        } else {
            // iPhone: 2-column grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                kpiCards
            }
        }
    }

    @ViewBuilder
    private var kpiCards: some View {
        MetricCard(
            title: "In Use",
            value: "\(kpis.inUseCount)",
            icon: "checkmark.circle.fill",
            accent: .green,
            style: .compact
        )

        MetricCard(
            title: "On Location",
            value: "\(kpis.onLocationCount)",
            icon: "mappin.circle",
            accent: .blue,
            style: .compact
        )

        MetricCard(
            title: "Open Issues",
            value: "\(kpis.issueCount)",
            icon: "exclamationmark.triangle",
            accent: kpis.issueCount > 0 ? .orange : .secondary,
            style: .compact
        )

        MetricCard(
            title: "Daily Cost",
            value: costString,
            icon: "dollarsign.circle",
            accent: .purple,
            style: .compact
        )

        MetricCard(
            title: "Active Transfers",
            value: "\(kpis.activeTransferCount)",
            icon: "arrow.left.arrow.right.circle",
            accent: .teal,
            style: .compact
        )
    }
}
#endif
