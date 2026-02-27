//
//  EquipmentKPIStripView.swift
//  Josh Well Control for Mac
//
//  Row of MetricCards for Equipment Hub KPIs.
//

import SwiftUI

struct EquipmentKPIStripView: View {
    let kpis: EquipmentKPIData

    private var costString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: kpis.dailyCost)) ?? "$0"
    }

    var body: some View {
        HStack(spacing: EquipmentHubLayout.sectionSpacing) {
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
}
