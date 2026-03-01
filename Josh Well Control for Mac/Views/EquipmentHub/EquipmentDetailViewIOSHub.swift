//
//  EquipmentDetailViewIOSHub.swift
//  Josh Well Control for Mac
//
//  Enhanced equipment detail for iOS with 4-tab segmented picker
//  (Overview / Usage / Issues / Transfers).
//

import SwiftUI
import SwiftData

#if os(iOS)
struct EquipmentDetailViewIOSHub: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var equipment: RentalEquipment

    @State private var selectedTab: DetailTab = .overview
    @State private var showingEditSheet = false
    @State private var showingIssueSheet = false

    // Deferred relationship data
    @State private var didLoad = false
    @State private var loadedRentals: [RentalItem] = []
    @State private var loadedIssues: [RentalEquipmentIssue] = []
    @State private var loadedTransferItems: [MaterialTransferItem] = []
    @State private var categoryName: String?
    @State private var categoryIcon: String?
    @State private var vendorName: String?
    @State private var vendorPhone: String?
    @State private var totalDays: Int = 0
    @State private var wellsUsed: Int = 0
    @State private var dailyCost: Double = 0
    @State private var lastMoved: Date?

    enum DetailTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case usage = "Usage"
        case issues = "Issues"
        case transfers = "Transfers"

        var id: String { rawValue }
    }

    // MARK: - Computed

    private var dailyCostString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: dailyCost)) ?? "$0"
    }

    // MARK: - Body

    var body: some View {
        List {
            // Header
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            if !equipment.serialNumber.isEmpty {
                                Text("S/N: \(equipment.serialNumber)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 8) {
                                if let name = categoryName, let icon = categoryIcon {
                                    Label(name, systemImage: icon)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.accentColor.opacity(0.1))
                                        .cornerRadius(4)
                                }
                                if let name = vendorName {
                                    Label(name, systemImage: "building.2")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                        EquipmentStatusBadge(status: equipment.locationStatus)
                    }
                }
            }

            // Tab Picker
            Section {
                Picker("", selection: $selectedTab) {
                    ForEach(DetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
            }

            // Tab Content
            if !didLoad {
                Section {
                    ProgressView("Loading...")
                }
            } else {
                switch selectedTab {
                case .overview:
                    overviewSection
                case .usage:
                    usageSection
                case .issues:
                    issuesSection
                case .transfers:
                    transfersSection
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(equipment.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", systemImage: "pencil") {
                    showingEditSheet = true
                }
            }
        }
        .task {
            categoryName = equipment.category?.name
            categoryIcon = equipment.category?.icon
            vendorName = equipment.vendor?.companyName
            vendorPhone = equipment.vendor?.phone ?? ""
            totalDays = equipment.totalDaysUsed
            wellsUsed = equipment.wellsUsedCount
            dailyCost = equipment.currentActiveRental?.costPerDay ?? 0
            lastMoved = equipment.lastMovedAt
            loadedRentals = equipment.sortedRentals
            loadedIssues = equipment.sortedIssues
            loadedTransferItems = equipment.transferItems ?? []
            didLoad = true
        }
        .sheet(isPresented: $showingEditSheet) {
            EquipmentEditSheetWrapper(equipment: equipment)
        }
        .sheet(isPresented: $showingIssueSheet) {
            NavigationStack {
                IssueLogSheetIOS(equipment: equipment)
            }
        }
    }

    // MARK: - Overview

    @ViewBuilder
    private var overviewSection: some View {
        Section("Metrics") {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                MetricCard(
                    title: "Total Days",
                    value: "\(totalDays)",
                    icon: "calendar",
                    accent: .blue,
                    style: .compact
                )
                MetricCard(
                    title: "Wells Used",
                    value: "\(wellsUsed)",
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
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        }

        if let name = vendorName {
            Section("Vendor") {
                LabeledContent("Company", value: name)
                if let phone = vendorPhone, !phone.isEmpty {
                    LabeledContent("Phone", value: phone)
                }
            }
        }

        if !equipment.model.isEmpty {
            Section("Model") {
                Text(equipment.model)
            }
        }

        if !equipment.notes.isEmpty {
            Section("Notes") {
                Text(equipment.notes)
                    .foregroundStyle(.secondary)
            }
        }

        if let lastMoved {
            Section {
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

    // MARK: - Usage

    @ViewBuilder
    private var usageSection: some View {
        Section("Usage History") {
            if loadedRentals.isEmpty {
                Text("No usage history recorded.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(loadedRentals) { rental in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rental.well?.name ?? "Unknown Well")
                                .fontWeight(.medium)
                            HStack(spacing: 4) {
                                if let start = rental.startDate {
                                    Text(start, style: .date)
                                }
                                if rental.endDate != nil {
                                    Image(systemName: "arrow.right")
                                        .font(.caption2)
                                }
                                if let end = rental.endDate {
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

    // MARK: - Issues

    @ViewBuilder
    private var issuesSection: some View {
        Section {
            if loadedIssues.isEmpty {
                Text("No issues recorded.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(loadedIssues) { issue in
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
                            Button("Resolve") {
                                issue.resolve(notes: "Resolved")
                                try? modelContext.save()
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("Issues")
                Spacer()
                Button {
                    showingIssueSheet = true
                } label: {
                    Label("Log Issue", systemImage: "plus.circle")
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Transfers

    @ViewBuilder
    private var transfersSection: some View {
        Section("Transfers") {
            if loadedTransferItems.isEmpty {
                Text("No transfers recorded.")
                    .foregroundStyle(.secondary)
            } else {
                let grouped = Dictionary(grouping: loadedTransferItems) { $0.transfer?.id }
                ForEach(Array(grouped.keys.compactMap { $0 }), id: \.self) { transferID in
                    if let items = grouped[transferID], let transfer = items.first?.transfer {
                        HStack {
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
                                }
                                if let wellName = transfer.well?.name {
                                    Text(wellName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(transfer.date, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Edit Sheet (separate struct to isolate @Query)

private struct EquipmentEditSheetWrapper: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RentalCategory.sortOrder) private var categories: [RentalCategory]
    @Query(filter: #Predicate<Vendor> { $0.serviceTypeRaw == "Rentals" }, sort: \Vendor.companyName)
    private var vendors: [Vendor]
    @Bindable var equipment: RentalEquipment

    var body: some View {
        NavigationStack {
            EquipmentEditorViewIOS(equipment: equipment, categories: categories, vendors: vendors) { _ in
                try? modelContext.save()
            }
        }
    }
}
#endif
