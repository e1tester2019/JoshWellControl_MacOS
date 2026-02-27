//
//  EquipmentDetailPaneView.swift
//  Josh Well Control for Mac
//
//  Tabbed equipment detail pane with Overview, Usage, Issues, and Transfers tabs.
//

import SwiftUI
import SwiftData

#if os(macOS)
struct EquipmentDetailPaneView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var equipment: RentalEquipment

    let onLogIssue: () -> Void
    let onEdit: () -> Void
    let onBackhaul: () -> Void

    @State private var selectedTab: DetailTab = .overview

    enum DetailTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case usage = "Usage"
        case issues = "Issues"
        case transfers = "Transfers"

        var id: String { rawValue }
    }

    // MARK: - Computed

    private var costString: String {
        let cost = equipment.sortedRentals.reduce(0.0) { $0 + $1.totalCost }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: cost)) ?? "$0"
    }

    private var dailyCostString: String {
        let cost = equipment.currentActiveRental?.costPerDay ?? 0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: cost)) ?? "$0"
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EquipmentHubLayout.sectionSpacing) {
                headerSection
                quickActions
                tabPicker
                tabContent
            }
            .padding(EquipmentHubLayout.sidebarPadding)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(equipment.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    if !equipment.serialNumber.isEmpty {
                        Text("S/N: \(equipment.serialNumber)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                EquipmentStatusBadge(status: equipment.locationStatus)
            }

            HStack(spacing: 8) {
                if let category = equipment.category {
                    Label(category.name, systemImage: category.icon)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(4)
                }

                if let vendor = equipment.vendor {
                    Label(vendor.companyName, systemImage: "building.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        HStack(spacing: 8) {
            Button {
                onLogIssue()
            } label: {
                Label("Log Issue", systemImage: "exclamationmark.triangle")
            }
            .controlSize(.small)

            if equipment.locationStatus != .withVendor {
                Button {
                    onBackhaul()
                } label: {
                    Label("Backhaul", systemImage: "arrow.uturn.backward")
                }
                .controlSize(.small)
            }

            Menu {
                Button {
                    onEdit()
                } label: {
                    Label("Edit Equipment", systemImage: "pencil")
                }

                if equipment.locationStatus != .inUse {
                    Button {
                        equipment.locationStatus = .inUse
                        equipment.touch()
                        try? modelContext.save()
                    } label: {
                        Label("Mark In Use", systemImage: "checkmark.circle.fill")
                    }
                }

                if equipment.locationStatus != .onLocation {
                    Button {
                        equipment.locationStatus = .onLocation
                        equipment.touch()
                        try? modelContext.save()
                    } label: {
                        Label("Mark On Location", systemImage: "mappin.circle")
                    }
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .controlSize(.small)

            Spacer()
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            ForEach(DetailTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            overviewTab
        case .usage:
            usageTab
        case .issues:
            issuesTab
        case .transfers:
            transfersTab
        }
    }

    // MARK: - Overview Tab

    private var overviewTab: some View {
        VStack(alignment: .leading, spacing: EquipmentHubLayout.sectionSpacing) {
            HStack(spacing: EquipmentHubLayout.sectionSpacing) {
                MetricCard(
                    title: "Total Days",
                    value: "\(equipment.totalDaysUsed)",
                    icon: "calendar",
                    accent: .blue,
                    style: .compact
                )

                MetricCard(
                    title: "Wells Used",
                    value: "\(equipment.wellsUsedCount)",
                    icon: "building.2",
                    accent: .teal,
                    style: .compact
                )

                MetricCard(
                    title: "Daily Cost",
                    value: dailyCostString,
                    icon: "dollarsign.circle",
                    accent: .purple,
                    style: .compact
                )
            }

            if let vendor = equipment.vendor {
                EquipmentCard {
                    VStack(alignment: .leading, spacing: 4) {
                        StandardSectionHeader(title: "Vendor", icon: "building.2")
                        Text(vendor.companyName)
                            .font(.body)
                        if !vendor.phone.isEmpty {
                            Text(vendor.phone)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !equipment.model.isEmpty {
                EquipmentCard {
                    VStack(alignment: .leading, spacing: 4) {
                        StandardSectionHeader(title: "Model", icon: "info.circle")
                        Text(equipment.model)
                            .font(.body)
                    }
                }
            }

            if !equipment.notes.isEmpty {
                EquipmentCard {
                    VStack(alignment: .leading, spacing: 4) {
                        StandardSectionHeader(title: "Notes", icon: "note.text")
                        Text(equipment.notes)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let lastMoved = equipment.lastMovedAt {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    Text("Last moved: \(lastMoved, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Usage Tab

    private var usageTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            StandardSectionHeader(title: "Usage History", icon: "clock.arrow.circlepath")

            if equipment.sortedRentals.isEmpty {
                Text("No usage history recorded.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .padding(.vertical, 8)
            } else {
                ForEach(equipment.sortedRentals) { rental in
                    EquipmentCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rental.well?.name ?? "Unknown Well")
                                    .fontWeight(.medium)

                                HStack(spacing: 4) {
                                    if let start = rental.startDate {
                                        Text(start, style: .date)
                                    }
                                    if let end = rental.endDate {
                                        Text("→")
                                        Text(end, style: .date)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                Text("\(rental.totalDays) days • \(rental.totalCost, format: .currency(code: "CAD"))")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            RentalStatusBadge(status: rental.status, compact: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Issues Tab

    private var issuesTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            StandardSectionHeader(title: "Issues", icon: "exclamationmark.triangle") {
                Button {
                    onLogIssue()
                } label: {
                    Label("Log Issue", systemImage: "plus")
                }
                .controlSize(.small)
            }

            if equipment.sortedIssues.isEmpty {
                Text("No issues recorded.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .padding(.vertical, 8)
            } else {
                ForEach(equipment.sortedIssues) { issue in
                    EquipmentCard {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Image(systemName: issue.issueType.icon)
                                        .foregroundStyle(issue.issueType.color)
                                        .font(.caption)
                                    Text(issue.issueType.rawValue)
                                        .fontWeight(.medium)
                                    Text("•")
                                        .foregroundStyle(.tertiary)
                                    Text(issue.severity.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(issue.severity.color)
                                }

                                Text(issue.description_)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)

                                if !issue.wellName.isEmpty {
                                    Text("at \(issue.wellName)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }

                                Text(issue.date, style: .date)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            if issue.isResolved {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Button {
                                    issue.resolve(notes: "Resolved")
                                    try? modelContext.save()
                                } label: {
                                    Text("Resolve")
                                        .font(.caption)
                                }
                                .controlSize(.mini)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Transfers Tab

    private var transfersTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            StandardSectionHeader(title: "Transfers", icon: "arrow.left.arrow.right.circle")

            let transferItems = equipment.transferItems ?? []
            if transferItems.isEmpty {
                Text("No transfers recorded.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .padding(.vertical, 8)
            } else {
                let grouped = Dictionary(grouping: transferItems) { $0.transfer?.id }
                ForEach(Array(grouped.keys.compactMap { $0 }), id: \.self) { transferID in
                    if let items = grouped[transferID], let transfer = items.first?.transfer {
                        EquipmentCard {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("MT-\(transfer.number)")
                                        .fontWeight(.medium)

                                    TransferStatusBadge(
                                        status: TransferWorkflowStatus.from(
                                            isShippingOut: transfer.isShippingOut,
                                            isShippedBack: transfer.isShippedBack
                                        )
                                    )

                                    Spacer()

                                    Text(transfer.date, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if let wellName = transfer.well?.name {
                                    Text(wellName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
#endif
