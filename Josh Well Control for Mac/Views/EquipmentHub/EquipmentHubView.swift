//
//  EquipmentHubView.swift
//  Josh Well Control for Mac
//
//  Unified Equipment & Materials hub — top-level container with KPI strip,
//  tab picker, filter bar, and HSplitView for master-detail.
//

import SwiftUI
import SwiftData

#if os(macOS)
struct EquipmentHubView: View {
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

    private var selectedEquipment: RentalEquipment? {
        guard let id = vm.selectedEquipmentID else { return nil }
        return allEquipment.first { $0.id == id }
    }

    private var selectedTransfer: MaterialTransfer? {
        guard let id = vm.selectedTransferID else { return nil }
        return allTransfers.first { $0.id == id }
    }

    /// Whether the detail pane should be visible
    private var hasDetailSelection: Bool {
        switch vm.selectedTab {
        case .equipment: return selectedEquipment != nil
        case .transfers: return selectedTransfer != nil
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // KPI Strip
            EquipmentKPIStripView(kpis: kpis)
                .padding(.horizontal, EquipmentHubLayout.sidebarPadding)
                .padding(.top, 12)
                .padding(.bottom, 8)

            // Tab Picker + Filter Bar
            VStack(spacing: 8) {
                HStack {
                    Picker("", selection: $vm.selectedTab) {
                        ForEach(HubTab.allCases) { tab in
                            Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)

                    Spacer()
                }
                .padding(.horizontal, EquipmentHubLayout.sidebarPadding)

                EquipmentFilterChipsView(
                    vm: vm,
                    categories: categories,
                    vendors: vendors,
                    wells: wells
                )
                .padding(.horizontal, EquipmentHubLayout.sidebarPadding)
            }
            .padding(.bottom, 8)

            Divider()

            // Main Content: HSplitView
            HSplitView {
                leftPane
                    .frame(minWidth: EquipmentHubLayout.listMinWidth)

                if hasDetailSelection {
                    rightPane
                        .frame(
                            minWidth: EquipmentHubLayout.detailMinWidth,
                            idealWidth: EquipmentHubLayout.detailIdealWidth,
                            maxWidth: EquipmentHubLayout.detailMaxWidth
                        )
                }
            }
            .transaction { t in t.animation = nil }
        }
        .navigationTitle("Equipment & Materials")
        .toolbar { hubToolbar }
        .sheet(item: $vm.activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .animation(EquipmentAnimation.tabSwitch, value: vm.selectedTab)
        .animation(EquipmentAnimation.filterChange, value: vm.searchText)
    }

    // MARK: - Left Pane

    @ViewBuilder
    private var leftPane: some View {
        switch vm.selectedTab {
        case .equipment:
            switch vm.viewMode {
            case .list:
                EquipmentListContentView(
                    equipment: filteredEquipment,
                    selectedID: $vm.selectedEquipmentID,
                    selectedIDs: $vm.selectedEquipmentIDs,
                    sortOrder: $vm.equipmentSortOrder,
                    onLogIssue: { eq in vm.activeSheet = .issueLog(eq) },
                    onEdit: { eq in vm.activeSheet = .editEquipment(eq) },
                    onBackhaul: { eq in
                        eq.backhaul()
                        try? modelContext.save()
                    },
                    onDelete: { eq in
                        modelContext.delete(eq)
                        try? modelContext.save()
                        if vm.selectedEquipmentID == eq.id {
                            vm.selectedEquipmentID = nil
                        }
                    }
                )
            case .board:
                EquipmentBoardView(
                    equipment: filteredEquipment,
                    selectedID: $vm.selectedEquipmentID,
                    onStatusChange: { eq, newStatus in
                        eq.locationStatus = newStatus
                        eq.touch()
                        try? modelContext.save()
                    }
                )
            case .timeline:
                EquipmentTimelineView(
                    equipment: filteredEquipment,
                    selectedID: $vm.selectedEquipmentID
                ) { rental, newStart, newEnd in
                    rental.startDate = newStart
                    rental.endDate = newEnd
                    try? modelContext.save()
                }
            }

        case .transfers:
            TransferListContentView(
                transfers: filteredTransfers,
                selectedID: $vm.selectedTransferID,
                onOpenEditor: { transfer in
                    if let well = transfer.well {
                        vm.activeSheet = .transferEditor(transfer, well)
                    } else {
                        vm.activeSheet = .assignWellToTransfer(transfer)
                    }
                },
                onDelete: { transfer in
                    modelContext.delete(transfer)
                    try? modelContext.save()
                    if vm.selectedTransferID == transfer.id {
                        vm.selectedTransferID = nil
                    }
                }
            )
        }
    }

    // MARK: - Right Pane

    @ViewBuilder
    private var rightPane: some View {
        switch vm.selectedTab {
        case .equipment:
            if let equipment = selectedEquipment {
                EquipmentDetailPaneView(
                    equipment: equipment,
                    onLogIssue: { vm.activeSheet = .issueLog(equipment) },
                    onEdit: { vm.activeSheet = .editEquipment(equipment) },
                    onBackhaul: {
                        equipment.backhaul()
                        try? modelContext.save()
                    }
                )
                .id(equipment.id)
            }

        case .transfers:
            if let transfer = selectedTransfer {
                TransferDetailPaneView(
                    transfer: transfer,
                    onOpenEditor: {
                        if let well = transfer.well {
                            vm.activeSheet = .transferEditor(transfer, well)
                        } else {
                            vm.activeSheet = .assignWellToTransfer(transfer)
                        }
                    },
                    onAdvanceStatus: {
                        advanceTransferStatus(transfer)
                    }
                )
                .id(transfer.id)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var hubToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if vm.selectedTab == .equipment {
                Button {
                    vm.activeSheet = .addEquipment
                } label: {
                    Label("Add Equipment", systemImage: "plus")
                }
                .help("Add Equipment (⌘N)")

                Menu {
                    Button {
                        vm.activeSheet = .categoryManager
                    } label: {
                        Label("Manage Categories", systemImage: "folder.badge.gearshape")
                    }

                    Button {
                        vm.activeSheet = .importSheet
                    } label: {
                        Label("Import Equipment", systemImage: "square.and.arrow.down")
                    }

                    if !vm.selectedEquipmentIDs.isEmpty {
                        Divider()

                        Button {
                            let selected = allEquipment.filter { vm.selectedEquipmentIDs.contains($0.id) }
                            vm.activeSheet = .bulkEdit(selected)
                        } label: {
                            Label("Bulk Edit (\(vm.selectedEquipmentIDs.count))", systemImage: "pencil.circle")
                        }

                        Button {
                            let selected = allEquipment.filter { vm.selectedEquipmentIDs.contains($0.id) }
                            vm.activeSheet = .sendToLocation(selected)
                        } label: {
                            Label("Send to Location", systemImage: "arrow.right.circle")
                        }

                        Button {
                            let selected = allEquipment.filter { vm.selectedEquipmentIDs.contains($0.id) }
                            vm.activeSheet = .createTransfer(selected)
                        } label: {
                            Label("Create Transfer", systemImage: "arrow.left.arrow.right")
                        }
                    }

                    Divider()

                    Button {
                        vm.activeSheet = .equipmentReport
                    } label: {
                        Label("On Location Report", systemImage: "doc.text")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: EquipmentHubSheet) -> some View {
        switch sheet {
        case .addEquipment:
            EquipmentEditorSheet(equipment: nil, categories: categories, vendors: vendors) { equipment in
                modelContext.insert(equipment)
                try? modelContext.save()
                vm.selectedEquipmentID = equipment.id
            }
        case .editEquipment(let equipment):
            EquipmentEditorSheet(equipment: equipment, categories: categories, vendors: vendors) { _ in
                try? modelContext.save()
            }
        case .issueLog(let equipment):
            IssueLogSheet(equipment: equipment)
        case .categoryManager:
            RentalCategoryManagerView()
        case .transferEditor(let transfer, let well):
            MaterialTransferEditorView(well: well, transfer: transfer)
        case .assignWellToTransfer(let transfer):
            AssignWellToTransferSheet(transfer: transfer, wells: wells) { well in
                transfer.well = well
                try? modelContext.save()
                vm.activeSheet = .transferEditor(transfer, well)
            }
        case .importSheet:
            EquipmentImportSheet(
                csvText: .constant(""),
                categories: categories,
                vendors: vendors,
                existingEquipment: allEquipment
            ) {
                vm.activeSheet = nil
            }
        case .bulkEdit(let equipment):
            BulkEquipmentEditSheet(
                equipment: equipment,
                categories: categories,
                vendors: vendors
            ) {
                vm.activeSheet = nil
                vm.selectedEquipmentIDs.removeAll()
            }
        case .sendToLocation(let equipment):
            SendToLocationSheet(equipment: equipment) {
                vm.activeSheet = nil
                vm.selectedEquipmentIDs.removeAll()
            }
        case .equipmentReport:
            let onLocation = allEquipment.filter {
                $0.locationStatus == .inUse || $0.locationStatus == .onLocation
            }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            EquipmentOnLocationReportPreview(equipment: onLocation)
        case .createTransfer(let equipment):
            CreateTransferFromEquipmentSheet(
                equipment: equipment,
                wells: wells
            ) { transfer in
                modelContext.insert(transfer)
                try? modelContext.save()
                vm.selectedTab = .transfers
                vm.selectedTransferID = transfer.id
                vm.activeSheet = nil
                vm.selectedEquipmentIDs.removeAll()
            }
        }
    }

    // MARK: - Helpers

    private func advanceTransferStatus(_ transfer: MaterialTransfer) {
        let current = TransferWorkflowStatus.from(
            isShippingOut: transfer.isShippingOut,
            isShippedBack: transfer.isShippedBack
        )
        switch current {
        case .draft:
            transfer.isShippingOut = true
        case .shippedOut:
            transfer.isShippedBack = true
        case .returned:
            break // Already at final state
        }
        try? modelContext.save()
    }
}

// MARK: - Assign Well to Transfer Sheet

/// Shown when trying to open the editor for a transfer that has no well assigned.
private struct AssignWellToTransferSheet: View {
    @Environment(\.dismiss) private var dismiss
    let transfer: MaterialTransfer
    let wells: [Well]
    let onAssign: (Well) -> Void

    @State private var selectedWell: Well?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Assign Well to MT-\(transfer.number)")
                .font(.headline)

            Text("This transfer doesn't have a well assigned. Select a well to open the editor.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Well", selection: $selectedWell) {
                Text("Select a well...").tag(nil as Well?)
                ForEach(wells) { well in
                    Text(well.name).tag(well as Well?)
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Assign & Open") {
                    guard let well = selectedWell else { return }
                    dismiss()
                    onAssign(well)
                }
                .disabled(selectedWell == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 350)
    }
}

// MARK: - Create Transfer From Equipment Sheet

private struct CreateTransferFromEquipmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let equipment: [RentalEquipment]
    let wells: [Well]
    let onSave: (MaterialTransfer) -> Void

    @State private var selectedWell: Well?
    @State private var destinationName = ""
    @State private var isShippingOut = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Transfer")
                .font(.headline)

            Form {
                Section("Transfer Details") {
                    Picker("Well", selection: $selectedWell) {
                        Text("Select a well...").tag(nil as Well?)
                        ForEach(wells) { well in
                            Text(well.name).tag(well as Well?)
                        }
                    }

                    TextField("Destination", text: $destinationName)

                    Toggle("Shipping Out", isOn: $isShippingOut)
                }

                Section("Equipment (\(equipment.count) items)") {
                    ForEach(equipment) { eq in
                        HStack {
                            Image(systemName: eq.category?.icon ?? "shippingbox")
                                .foregroundStyle(.secondary)
                            Text(eq.displayName)
                            Spacer()
                            EquipmentStatusBadge(status: eq.locationStatus)
                        }
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") {
                    guard let well = selectedWell else { return }
                    let transfer = MaterialTransfer(
                        number: (well.transfers?.count ?? 0) + 1,
                        date: .now
                    )
                    transfer.well = well
                    transfer.destinationName = destinationName
                    transfer.isShippingOut = isShippingOut

                    var items: [MaterialTransferItem] = []
                    for eq in equipment {
                        let item = MaterialTransferItem(quantity: 1, descriptionText: eq.name)
                        item.serialNumber = eq.serialNumber
                        item.isRentalEquipment = true
                        item.equipment = eq
                        items.append(item)
                    }
                    transfer.items = items

                    onSave(transfer)
                }
                .disabled(selectedWell == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 500, height: 500)
    }
}
#endif
