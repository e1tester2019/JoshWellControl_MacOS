//
//  EquipmentHubViewIOS.swift
//  Josh Well Control for Mac
//
//  Unified Equipment & Materials hub for iOS — KPI strip, tab picker,
//  filter section, search, content list, sheet routing, and toolbar.
//

import SwiftUI
import SwiftData

#if os(iOS)
struct EquipmentHubViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RentalEquipment.name) private var allEquipment: [RentalEquipment]
    @Query(sort: \RentalCategory.sortOrder) private var categories: [RentalCategory]
    @Query(filter: #Predicate<Vendor> { $0.serviceTypeRaw == "Rentals" }, sort: \Vendor.companyName)
    private var vendors: [Vendor]
    @Query(sort: \MaterialTransfer.date, order: .reverse) private var allTransfers: [MaterialTransfer]
    @Query(sort: \Well.name) private var wells: [Well]

    @State private var vm = EquipmentHubViewModel()

    // MARK: - Derived Data

    private var filteredEquipment: [RentalEquipment] {
        vm.filteredEquipment(from: allEquipment)
    }

    private var filteredTransfers: [MaterialTransfer] {
        vm.filteredTransfers(from: allTransfers)
    }

    private var kpis: EquipmentKPIData {
        vm.computeKPIs(equipment: allEquipment, transfers: allTransfers)
    }

    // MARK: - Body

    var body: some View {
        List {
            // KPI Strip
            Section {
                EquipmentHubKPIStripIOS(kpis: kpis)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            // Tab Picker
            Section {
                Picker("", selection: $vm.selectedTab) {
                    ForEach(HubTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
            }

            // Filters
            Section {
                EquipmentFilterViewIOS(
                    vm: vm,
                    categories: categories,
                    vendors: vendors,
                    wells: wells
                )
            }

            // Content
            contentSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Equipment & Materials")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $vm.searchText, prompt: vm.selectedTab == .equipment ? "Search equipment..." : "Search transfers...")
        .toolbar { hubToolbar }
        .sheet(item: $vm.activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .animation(EquipmentAnimation.tabSwitch, value: vm.selectedTab)
    }

    // MARK: - Content Section

    @ViewBuilder
    private var contentSection: some View {
        switch vm.selectedTab {
        case .equipment:
            equipmentListSection
        case .transfers:
            transferListSection
        }
    }

    // MARK: - Equipment List

    @ViewBuilder
    private var equipmentListSection: some View {
        if filteredEquipment.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("No Equipment", systemImage: "shippingbox")
                } description: {
                    if allEquipment.isEmpty {
                        Text("Add equipment to start tracking your rentals.")
                    } else {
                        Text("No equipment matches your filters.")
                    }
                } actions: {
                    if allEquipment.isEmpty {
                        Button("Add Equipment") {
                            vm.activeSheet = .addEquipment
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .listRowBackground(Color.clear)
            }
        } else {
            Section("Equipment (\(filteredEquipment.count))") {
                ForEach(filteredEquipment) { equipment in
                    NavigationLink {
                        EquipmentDetailViewIOSHub(equipment: equipment)
                    } label: {
                        EquipmentHubRowIOS(equipment: equipment)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteEquipment(equipment)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            vm.activeSheet = .issueLog(equipment)
                        } label: {
                            Label("Issue", systemImage: "exclamationmark.triangle")
                        }
                        .tint(.orange)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            vm.activeSheet = .editEquipment(equipment)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)

                        if equipment.locationStatus != .withVendor {
                            Button {
                                equipment.backhaul()
                                try? modelContext.save()
                            } label: {
                                Label("Backhaul", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.purple)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Transfer List

    @ViewBuilder
    private var transferListSection: some View {
        if filteredTransfers.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("No Transfers", systemImage: "arrow.left.arrow.right.circle")
                } description: {
                    if allTransfers.isEmpty {
                        Text("Create a transfer to start tracking materials.")
                    } else {
                        Text("No transfers match your filters.")
                    }
                }
                .listRowBackground(Color.clear)
            }
        } else {
            Section("Transfers (\(filteredTransfers.count))") {
                ForEach(filteredTransfers) { transfer in
                    NavigationLink {
                        TransferDetailViewIOS(transfer: transfer)
                    } label: {
                        TransferHubRowIOS(transfer: transfer)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteTransfer(transfer)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            if let well = transfer.well {
                                vm.activeSheet = .transferEditor(transfer, well)
                            } else {
                                vm.activeSheet = .assignWellToTransfer(transfer)
                            }
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var hubToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if vm.selectedTab == .equipment {
                    Button {
                        vm.activeSheet = .addEquipment
                    } label: {
                        Label("Add Equipment", systemImage: "plus")
                    }

                    Button {
                        vm.activeSheet = .categoryManager
                    } label: {
                        Label("Manage Categories", systemImage: "folder.badge.gearshape")
                    }
                } else {
                    // Transfers: user creates transfers via MaterialTransferEditorView
                    // which requires a well. Show "pick well" approach.
                    if let well = wells.first {
                        Button {
                            let transfer = MaterialTransfer(number: (well.transfers?.count ?? 0) + 1, date: .now)
                            transfer.well = well
                            modelContext.insert(transfer)
                            try? modelContext.save()
                            vm.activeSheet = .transferEditor(transfer, well)
                        } label: {
                            Label("New Transfer", systemImage: "plus")
                        }
                    }
                }
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: EquipmentHubSheet) -> some View {
        switch sheet {
        case .addEquipment:
            NavigationStack {
                EquipmentEditorViewIOS(equipment: nil, categories: categories, vendors: vendors) { equipment in
                    modelContext.insert(equipment)
                    try? modelContext.save()
                }
            }
        case .editEquipment(let equipment):
            NavigationStack {
                EquipmentEditorViewIOS(equipment: equipment, categories: categories, vendors: vendors) { _ in
                    try? modelContext.save()
                }
            }
        case .issueLog(let equipment):
            NavigationStack {
                IssueLogSheetIOS(equipment: equipment)
            }
        case .categoryManager:
            NavigationStack {
                RentalCategoryManagerView()
            }
        case .transferEditor(let transfer, let well):
            NavigationStack {
                MaterialTransferEditorView(well: well, transfer: transfer)
            }
        case .assignWellToTransfer(let transfer):
            assignWellSheet(for: transfer)
        case .importSheet:
            Text("Import not available on iOS")
        case .bulkEdit:
            Text("Bulk edit not available on iOS")
        case .sendToLocation:
            Text("Send to location not available on iOS")
        case .equipmentReport:
            Text("Report not available on iOS")
        case .createTransfer:
            Text("Use the Transfers tab to create transfers")
        }
    }

    private func assignWellSheet(for transfer: MaterialTransfer) -> some View {
        NavigationStack {
            Form {
                Section {
                    Text("This transfer doesn't have a well assigned. Select a well to open the editor.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section("Select Well") {
                    ForEach(wells) { well in
                        Button {
                            transfer.well = well
                            try? modelContext.save()
                            vm.activeSheet = .transferEditor(transfer, well)
                        } label: {
                            Label(well.name, systemImage: "building.2")
                        }
                    }
                }
            }
            .navigationTitle("Assign Well to MT-\(transfer.number)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        vm.activeSheet = nil
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func deleteEquipment(_ equipment: RentalEquipment) {
        modelContext.delete(equipment)
        try? modelContext.save()
    }

    private func deleteTransfer(_ transfer: MaterialTransfer) {
        modelContext.delete(transfer)
        try? modelContext.save()
    }
}

// MARK: - Equipment Row

private struct EquipmentHubRowIOS: View {
    let equipment: RentalEquipment

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: equipment.category?.icon ?? "shippingbox")
                .font(.title2)
                .foregroundStyle(equipment.isActive ? .blue : .secondary)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(equipment.name)
                        .fontWeight(.medium)
                    if equipment.hasFailures {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                HStack(spacing: 8) {
                    if !equipment.serialNumber.isEmpty {
                        Text("SN: \(equipment.serialNumber)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    EquipmentStatusBadge(status: equipment.locationStatus)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(equipment.totalDaysUsed)d")
                    .font(.caption)
                    .monospacedDigit()
                Text("\(equipment.wellsUsedCount) wells")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .opacity(equipment.isActive ? 1 : 0.6)
    }
}

// MARK: - Transfer Row

private struct TransferHubRowIOS: View {
    let transfer: MaterialTransfer

    private var workflowStatus: TransferWorkflowStatus {
        TransferWorkflowStatus.from(
            isShippingOut: transfer.isShippingOut,
            isShippedBack: transfer.isShippedBack
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            TransferStatusBadge(status: workflowStatus)

            VStack(alignment: .leading, spacing: 2) {
                Text("MT-\(transfer.number)")
                    .fontWeight(.medium)
                if let wellName = transfer.well?.name {
                    Text(wellName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(transfer.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(transfer.items?.count ?? 0) items")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
#endif
