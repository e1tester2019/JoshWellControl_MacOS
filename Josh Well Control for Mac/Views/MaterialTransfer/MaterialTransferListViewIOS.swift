//
//  MaterialTransferListViewIOS.swift
//  Josh Well Control for Mac
//
//  iOS-optimized material transfer views
//

#if os(iOS)
import SwiftUI
import SwiftData
import UIKit

// MARK: - Standalone Material Transfers View (All Wells)

struct AllMaterialTransfersViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MaterialTransfer.date, order: .reverse) private var transfers: [MaterialTransfer]
    @Query(sort: \Well.name) private var wells: [Well]

    @State private var showingAddSheet = false
    @State private var selectedWell: Well?
    @State private var filterDirection: TransferDirection? = nil
    @State private var searchText = ""

    enum TransferDirection: String, CaseIterable {
        case shippingOut = "Shipping Out"
        case receiving = "Receiving"
    }

    private var filteredTransfers: [MaterialTransfer] {
        var result = transfers

        if let well = selectedWell {
            result = result.filter { $0.well?.id == well.id }
        }

        if let direction = filterDirection {
            result = result.filter {
                direction == .shippingOut ? $0.isShippingOut : !$0.isShippingOut
            }
        }

        if !searchText.isEmpty {
            result = result.filter { transfer in
                transfer.destinationName?.localizedCaseInsensitiveContains(searchText) == true ||
                String(transfer.number).contains(searchText) ||
                transfer.items?.contains { $0.descriptionText.localizedCaseInsensitiveContains(searchText) } == true
            }
        }

        return result
    }

    var body: some View {
        List {
            // Filters Section
            Section {
                Picker("Well", selection: $selectedWell) {
                    Text("All Wells").tag(nil as Well?)
                    ForEach(wells) { well in
                        Text(well.name).tag(well as Well?)
                    }
                }

                Picker("Direction", selection: $filterDirection) {
                    Text("All").tag(nil as TransferDirection?)
                    ForEach(TransferDirection.allCases, id: \.self) { dir in
                        HStack {
                            Image(systemName: dir == .shippingOut ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            Text(dir.rawValue)
                        }.tag(dir as TransferDirection?)
                    }
                }
            }

            // Transfers
            Section {
                if filteredTransfers.isEmpty {
                    ContentUnavailableView("No Transfers", systemImage: "shippingbox", description: Text("Create a new transfer to get started"))
                } else {
                    ForEach(filteredTransfers) { transfer in
                        NavigationLink {
                            MaterialTransferDetailViewIOS(transfer: transfer)
                        } label: {
                            TransferRowEnhanced(transfer: transfer)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                modelContext.delete(transfer)
                                try? modelContext.save()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                duplicateTransfer(transfer)
                            } label: {
                                Label("Duplicate", systemImage: "doc.on.doc")
                            }
                            .tint(.blue)
                        }
                    }
                }
            } header: {
                Text("\(filteredTransfers.count) Transfer\(filteredTransfers.count == 1 ? "" : "s")")
            }
        }
        .searchable(text: $searchText, prompt: "Search transfers...")
        .listStyle(.insetGrouped)
        .navigationTitle("Material Transfers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(wells.isEmpty)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddMaterialTransferSheetEnhanced(preselectedWell: selectedWell)
        }
    }

    private func duplicateTransfer(_ transfer: MaterialTransfer) {
        let newTransfer = MaterialTransfer()
        newTransfer.number = Int.random(in: 1000...9999)
        newTransfer.date = Date()
        newTransfer.well = transfer.well
        newTransfer.destinationName = transfer.destinationName
        newTransfer.destinationAddress = transfer.destinationAddress
        newTransfer.isShippingOut = transfer.isShippingOut
        newTransfer.transportedBy = transfer.transportedBy
        newTransfer.activity = transfer.activity

        modelContext.insert(newTransfer)

        // Duplicate items
        for item in transfer.items ?? [] {
            let newItem = MaterialTransferItem(descriptionText: item.descriptionText)
            newItem.quantity = item.quantity
            newItem.serialNumber = nil // Don't copy serial numbers
            newItem.conditionCode = item.conditionCode
            newItem.accountCode = item.accountCode
            newItem.unitPrice = item.unitPrice
            newItem.vendorOrTo = item.vendorOrTo
            newItem.transfer = newTransfer
            modelContext.insert(newItem)
        }

        try? modelContext.save()
    }
}

// MARK: - Well-Specific Material Transfer List

struct MaterialTransferListViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    let well: Well
    @Query(sort: \MaterialTransfer.date, order: .reverse) private var allTransfers: [MaterialTransfer]
    @State private var showingAddSheet = false

    private var transfers: [MaterialTransfer] {
        allTransfers.filter { $0.well?.id == well.id }
    }

    var body: some View {
        List {
            ForEach(transfers) { transfer in
                NavigationLink {
                    MaterialTransferDetailViewIOS(transfer: transfer)
                } label: {
                    TransferRowEnhanced(transfer: transfer)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        deleteTransfer(transfer)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Material Transfers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddMaterialTransferSheetEnhanced(preselectedWell: well)
        }
        .overlay {
            if transfers.isEmpty {
                ContentUnavailableView("No Transfers", systemImage: "shippingbox", description: Text("Track material transfers for this well"))
            }
        }
    }

    private func deleteTransfer(_ transfer: MaterialTransfer) {
        modelContext.delete(transfer)
        try? modelContext.save()
    }
}

// MARK: - Enhanced Transfer Row

private struct TransferRowEnhanced: View {
    let transfer: MaterialTransfer

    var body: some View {
        HStack(spacing: 12) {
            // Direction indicator
            Image(systemName: transfer.isShippingOut ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.title2)
                .foregroundStyle(transfer.isShippingOut ? .orange : .green)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Transfer #\(transfer.number)")
                        .font(.headline)

                    Spacer()

                    Text(transfer.date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let wellName = transfer.well?.name {
                    Text(wellName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    if let dest = transfer.destinationName, !dest.isEmpty {
                        Label(dest, systemImage: "mappin")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let items = transfer.items, !items.isEmpty {
                        Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Material Transfer Detail

struct MaterialTransferDetailViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var transfer: MaterialTransfer
    @State private var showingAddItemSheet = false
    @State private var editingItem: MaterialTransferItem?

    // Rental integration
    @State private var showAddFromRentals = false
    @State private var selectedRentalIDs: Set<UUID> = []
    @State private var showCreateRentals = false
    @State private var selectedTransferItemIDs: Set<UUID> = []
    @State private var showAffectedRentals = false
    @State private var alertMessage: String?

    var body: some View {
        List {
            // Transfer Info Section
            Section("Transfer Details") {
                HStack {
                    Text("Transfer #")
                    Spacer()
                    TextField("#", value: $transfer.number, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                DatePicker("Date", selection: $transfer.date, displayedComponents: .date)

                // Direction Toggle
                HStack {
                    Text("Direction")
                    Spacer()
                    Picker("", selection: $transfer.isShippingOut) {
                        Label("Receiving", systemImage: "arrow.down.circle.fill")
                            .tag(false)
                        Label("Shipping Out", systemImage: "arrow.up.circle.fill")
                            .tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }

            Section("Location") {
                TextField("Destination Name", text: Binding(
                    get: { transfer.destinationName ?? "" },
                    set: { transfer.destinationName = $0.isEmpty ? nil : $0 }
                ))

                TextField("Destination Address", text: Binding(
                    get: { transfer.destinationAddress ?? "" },
                    set: { transfer.destinationAddress = $0.isEmpty ? nil : $0 }
                ))
            }

            Section("Transport") {
                TextField("Transported By", text: Binding(
                    get: { transfer.transportedBy ?? "" },
                    set: { transfer.transportedBy = $0.isEmpty ? nil : $0 }
                ))

                TextField("Activity/Notes", text: Binding(
                    get: { transfer.activity ?? "" },
                    set: { transfer.activity = $0.isEmpty ? nil : $0 }
                ))
            }

            // Items Section
            Section {
                if let items = transfer.items, !items.isEmpty {
                    ForEach(items) { item in
                        ItemRowView(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingItem = item
                            }
                    }
                    .onDelete(perform: deleteItems)
                } else {
                    Text("No items added")
                        .foregroundStyle(.secondary)
                        .italic()
                }

                Button {
                    showingAddItemSheet = true
                } label: {
                    Label("Add Item", systemImage: "plus.circle.fill")
                }
            } header: {
                HStack {
                    Text("Items")
                    Spacer()
                    if let items = transfer.items, !items.isEmpty {
                        Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Totals Section
            if let items = transfer.items, !items.isEmpty {
                Section("Summary") {
                    HStack {
                        Text("Total Items")
                        Spacer()
                        Text("\(items.count)")
                            .foregroundStyle(.secondary)
                    }

                    let totalValue = items.reduce(0.0) { $0 + (($1.unitPrice ?? 0) * $1.quantity) }
                    if totalValue > 0 {
                        HStack {
                            Text("Total Value")
                            Spacer()
                            Text(totalValue, format: .currency(code: "CAD"))
                                .fontWeight(.semibold)
                        }
                    }
                }
            }

            // Rental Integration Section
            if let well = transfer.well {
                Section("Rental Integration") {
                    // Add from rentals
                    Button {
                        showAddFromRentals = true
                    } label: {
                        Label("Add From Rentals", systemImage: "shippingbox.fill")
                    }
                    .disabled((well.rentals ?? []).isEmpty)

                    // Create rentals from transfer lines
                    Button {
                        showCreateRentals = true
                    } label: {
                        Label("Create Rentals From Lines", systemImage: "plus.rectangle.on.folder")
                    }
                    .disabled((transfer.items ?? []).isEmpty)

                    // Preview/Apply rental status changes
                    let affectedCount = affectedRentalCount(well: well)
                    Button {
                        showAffectedRentals = true
                    } label: {
                        HStack {
                            Label("Preview Rental Changes", systemImage: "eye")
                            Spacer()
                            if affectedCount > 0 {
                                Text("\(affectedCount)")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundStyle(.orange)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .disabled(affectedCount == 0)
                }
            }

            // Export Section
            Section {
                Button {
                    exportPDF()
                } label: {
                    Label("Export PDF", systemImage: "square.and.arrow.up")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Transfer #\(transfer.number)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddItemSheet) {
            TransferItemEditorSheet(transfer: transfer, item: nil)
        }
        .sheet(item: $editingItem) { item in
            TransferItemEditorSheet(transfer: transfer, item: item)
        }
        .sheet(isPresented: $showAddFromRentals) {
            if let well = transfer.well {
                AddFromRentalsSheetIOS(
                    rentals: well.rentals ?? [],
                    selected: $selectedRentalIDs,
                    onCancel: {
                        selectedRentalIDs.removeAll()
                        showAddFromRentals = false
                    },
                    onAdd: {
                        addItemsFromSelectedRentals()
                        selectedRentalIDs.removeAll()
                        showAddFromRentals = false
                    }
                )
            }
        }
        .sheet(isPresented: $showCreateRentals) {
            if let well = transfer.well {
                CreateRentalsSheetIOS(
                    items: transfer.items ?? [],
                    selected: $selectedTransferItemIDs,
                    onCancel: {
                        selectedTransferItemIDs.removeAll()
                        showCreateRentals = false
                    },
                    onCreate: {
                        createRentalsFromSelectedLines(well: well)
                        selectedTransferItemIDs.removeAll()
                        showCreateRentals = false
                    }
                )
            }
        }
        .sheet(isPresented: $showAffectedRentals) {
            if let well = transfer.well {
                AffectedRentalsSheetIOS(
                    rentals: affectedRentals(well: well),
                    isShippingOut: transfer.isShippingOut,
                    onCancel: { showAffectedRentals = false },
                    onApply: {
                        let count = applyRentalChanges(well: well)
                        alertMessage = count > 0
                            ? (transfer.isShippingOut ? "Marked \(count) rental(s) off location." : "Restored \(count) rental(s) to on location.")
                            : "No matching rentals to update."
                        showAffectedRentals = false
                    }
                )
            }
        }
        .alert("Update Complete", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        guard var items = transfer.items else { return }
        for index in offsets {
            let item = items[index]
            modelContext.delete(item)
        }
        offsets.forEach { items.remove(at: $0) }
        transfer.items = items
        try? modelContext.save()
    }

    private func exportPDF() {
        guard let well = transfer.well,
              let data = MaterialTransferPDFGenerator.shared.generatePDF(for: transfer, well: well) else {
            return
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Transfer_\(transfer.number).pdf")
        do {
            try data.write(to: tempURL)
            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                var presenter = rootVC
                while let presented = presenter.presentedViewController {
                    presenter = presented
                }
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = presenter.view
                    popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                presenter.present(activityVC, animated: true)
            }
        } catch {
            print("Failed to write PDF: \(error)")
        }
    }

    // MARK: - Rental Integration Helpers

    private func affectedRentalCount(well: Well) -> Int {
        let serials = Set((transfer.items ?? []).compactMap { $0.serialNumber?.lowercased() }.filter { !$0.isEmpty })
        guard !serials.isEmpty else { return 0 }
        return (well.rentals ?? []).filter { rental in
            guard let sn = rental.serialNumber?.lowercased(), serials.contains(sn) else { return false }
            return transfer.isShippingOut ? rental.onLocation : !rental.onLocation
        }.count
    }

    private func affectedRentals(well: Well) -> [RentalItem] {
        let serials = Set((transfer.items ?? []).compactMap { $0.serialNumber?.lowercased() }.filter { !$0.isEmpty })
        guard !serials.isEmpty else { return [] }
        return (well.rentals ?? []).filter { rental in
            guard let sn = rental.serialNumber?.lowercased(), serials.contains(sn) else { return false }
            return transfer.isShippingOut ? rental.onLocation : !rental.onLocation
        }
    }

    @discardableResult
    private func applyRentalChanges(well: Well) -> Int {
        let matches = affectedRentals(well: well)
        var updated = 0
        for rental in matches {
            if transfer.isShippingOut && rental.onLocation {
                rental.onLocation = false
                updated += 1
            } else if !transfer.isShippingOut && !rental.onLocation {
                rental.onLocation = true
                updated += 1
            }
        }
        if updated > 0 { try? modelContext.save() }
        return updated
    }

    private func addItemsFromSelectedRentals() {
        guard let well = transfer.well, !selectedRentalIDs.isEmpty else { return }
        let selected = (well.rentals ?? []).filter { selectedRentalIDs.contains($0.id) }
        for rental in selected {
            let item = MaterialTransferItem(descriptionText: rental.name)
            item.quantity = 1
            item.detailText = rental.detail
            item.conditionCode = rental.used ? "USED" : "NEW"
            item.serialNumber = rental.serialNumber
            item.transfer = transfer
            if transfer.items == nil { transfer.items = [] }
            transfer.items?.append(item)
            modelContext.insert(item)
        }
        try? modelContext.save()
    }

    private func createRentalsFromSelectedLines(well: Well) {
        guard !selectedTransferItemIDs.isEmpty else { return }
        let chosen = (transfer.items ?? []).filter { selectedTransferItemIDs.contains($0.id) }
        for item in chosen {
            let rental = RentalItem(
                name: item.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
                detail: item.detailText,
                serialNumber: item.serialNumber,
                startDate: transfer.date,
                endDate: nil,
                usageDates: [],
                onLocation: !transfer.isShippingOut, // If receiving, on location; if shipping out, off location
                invoiced: false,
                costPerDay: 0,
                well: well
            )
            rental.used = (item.conditionCode?.lowercased() == "used")
            if well.rentals == nil { well.rentals = [] }
            well.rentals?.append(rental)
            modelContext.insert(rental)
        }
        try? modelContext.save()
    }
}

// MARK: - Item Row View

private struct ItemRowView: View {
    let item: MaterialTransferItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.descriptionText)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if let condition = item.conditionCode, !condition.isEmpty {
                    ConditionBadge(condition: condition)
                }
            }

            HStack(spacing: 12) {
                Label("\(Int(item.quantity))", systemImage: "number")
                    .font(.caption)

                if let weight = item.estimatedWeight, weight > 0 {
                    Label("\(Int(weight)) lb", systemImage: "scalemass")
                        .font(.caption)
                }

                if let serial = item.serialNumber, !serial.isEmpty {
                    Label(serial, systemImage: "barcode")
                        .font(.caption)
                }

                Spacer()

                if let price = item.unitPrice, price > 0 {
                    Text(price * item.quantity, format: .currency(code: "CAD"))
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            .foregroundStyle(.secondary)

            if let vendor = item.vendorOrTo, !vendor.isEmpty {
                Label(vendor, systemImage: "shippingbox")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Condition Badge

private struct ConditionBadge: View {
    let condition: String

    private var color: Color {
        switch condition.uppercased() {
        case "NEW", "N": return .green
        case "GOOD", "G": return .blue
        case "FAIR", "F": return .orange
        case "POOR", "P", "SCRAP", "S": return .red
        default: return .gray
        }
    }

    var body: some View {
        Text(condition)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Enhanced Add Material Transfer Sheet

private struct AddMaterialTransferSheetEnhanced: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Well.name) private var wells: [Well]

    let preselectedWell: Well?

    @State private var number: Int = Int.random(in: 1000...9999)
    @State private var date = Date()
    @State private var selectedWell: Well?
    @State private var isShippingOut = true
    @State private var destinationName = ""
    @State private var destinationAddress = ""
    @State private var transportedBy = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Transfer Info") {
                    HStack {
                        Text("Transfer Number")
                        Spacer()
                        TextField("#", value: $number, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }

                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    Picker("Well", selection: $selectedWell) {
                        Text("Select Well").tag(nil as Well?)
                        ForEach(wells) { well in
                            Text(well.name).tag(well as Well?)
                        }
                    }
                }

                Section("Direction") {
                    Picker("Type", selection: $isShippingOut) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.green)
                            Text("Receiving")
                        }.tag(false)

                        HStack {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundStyle(.orange)
                            Text("Shipping Out")
                        }.tag(true)
                    }
                    .pickerStyle(.inline)
                }

                Section("Destination") {
                    TextField("Name/Company", text: $destinationName)
                    TextField("Address", text: $destinationAddress)
                }

                Section("Transport") {
                    TextField("Transported By", text: $transportedBy)
                }
            }
            .navigationTitle("New Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createTransfer()
                        dismiss()
                    }
                    .disabled(selectedWell == nil)
                }
            }
            .onAppear {
                if selectedWell == nil {
                    selectedWell = preselectedWell ?? wells.first
                }
            }
        }
    }

    private func createTransfer() {
        guard let well = selectedWell else { return }

        let transfer = MaterialTransfer()
        transfer.number = number
        transfer.date = date
        transfer.well = well
        transfer.isShippingOut = isShippingOut
        transfer.destinationName = destinationName.isEmpty ? nil : destinationName
        transfer.destinationAddress = destinationAddress.isEmpty ? nil : destinationAddress
        transfer.transportedBy = transportedBy.isEmpty ? nil : transportedBy

        modelContext.insert(transfer)
        try? modelContext.save()
    }
}

// MARK: - Transfer Item Editor Sheet (Add/Edit)

private struct TransferItemEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let transfer: MaterialTransfer
    let item: MaterialTransferItem?

    @State private var description = ""
    @State private var quantity: Double = 1
    @State private var serialNumber = ""
    @State private var condition: String = ""
    @State private var accountCode = ""
    @State private var unitPrice: Double = 0
    @State private var estimatedWeight: Double = 0
    @State private var vendorOrTo = ""

    private let conditions = ["NEW", "GOOD", "FAIR", "POOR", "SCRAP"]

    private var isEditing: Bool { item != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Description", text: $description)

                    HStack {
                        Text("Quantity")
                        Spacer()
                        TextField("Qty", value: $quantity, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)

                        Stepper("", value: $quantity, in: 1...9999)
                            .labelsHidden()
                    }

                    TextField("Serial Number", text: $serialNumber)

                    HStack {
                        Text("Est. Weight")
                        Spacer()
                        TextField("0", value: $estimatedWeight, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("lb")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Condition") {
                    Picker("Condition", selection: $condition) {
                        Text("Not Specified").tag("")
                        ForEach(conditions, id: \.self) { cond in
                            HStack {
                                ConditionBadge(condition: cond)
                                Text(cond)
                            }.tag(cond)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section("Value") {
                    HStack {
                        Text("Unit Price")
                        Spacer()
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("0.00", value: $unitPrice, format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }

                    if unitPrice > 0 && quantity > 0 {
                        HStack {
                            Text("Total")
                            Spacer()
                            Text(unitPrice * quantity, format: .currency(code: "CAD"))
                                .fontWeight(.semibold)
                        }
                    }

                    TextField("Account Code", text: $accountCode)
                }

                Section("Destination") {
                    TextField("Vendor / To Location", text: $vendorOrTo)
                    Text("Items with different destinations will be grouped separately on the PDF")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(isEditing ? "Edit Item" : "Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        saveItem()
                        dismiss()
                    }
                    .disabled(description.isEmpty)
                }
            }
            .onAppear {
                if let item = item {
                    description = item.descriptionText
                    quantity = item.quantity
                    serialNumber = item.serialNumber ?? ""
                    condition = item.conditionCode ?? ""
                    accountCode = item.accountCode ?? ""
                    unitPrice = item.unitPrice ?? 0
                    estimatedWeight = item.estimatedWeight ?? 0
                    vendorOrTo = item.vendorOrTo ?? ""
                }
            }
        }
    }

    private func saveItem() {
        let targetItem: MaterialTransferItem

        if let existing = item {
            targetItem = existing
        } else {
            targetItem = MaterialTransferItem(descriptionText: "")
            targetItem.transfer = transfer
            if transfer.items == nil { transfer.items = [] }
            transfer.items?.append(targetItem)
            modelContext.insert(targetItem)
        }

        targetItem.descriptionText = description
        targetItem.quantity = quantity
        targetItem.serialNumber = serialNumber.isEmpty ? nil : serialNumber
        targetItem.conditionCode = condition.isEmpty ? nil : condition
        targetItem.accountCode = accountCode.isEmpty ? nil : accountCode
        targetItem.unitPrice = unitPrice > 0 ? unitPrice : nil
        targetItem.estimatedWeight = estimatedWeight > 0 ? estimatedWeight : nil
        targetItem.vendorOrTo = vendorOrTo.isEmpty ? nil : vendorOrTo

        try? modelContext.save()
    }
}

// MARK: - Add From Rentals Sheet

private struct AddFromRentalsSheetIOS: View {
    let rentals: [RentalItem]
    @Binding var selected: Set<UUID>
    var onCancel: () -> Void
    var onAdd: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if rentals.isEmpty {
                    ContentUnavailableView("No Rentals", systemImage: "shippingbox", description: Text("This well has no rental items"))
                } else {
                    ForEach(rentals) { rental in
                        Toggle(isOn: Binding(
                            get: { selected.contains(rental.id) },
                            set: { newVal in
                                if newVal { selected.insert(rental.id) } else { selected.remove(rental.id) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rental.name)
                                    .font(.headline)

                                if let detail = rental.detail, !detail.isEmpty {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }

                                HStack(spacing: 12) {
                                    if let sn = rental.serialNumber, !sn.isEmpty {
                                        Label(sn, systemImage: "barcode")
                                            .font(.caption2)
                                    }

                                    Label(rental.onLocation ? "On Location" : "Off Location", systemImage: rental.onLocation ? "checkmark.circle" : "xmark.circle")
                                        .font(.caption2)
                                        .foregroundStyle(rental.onLocation ? .green : .orange)
                                }
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Add From Rentals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selected.count))") { onAdd() }
                        .disabled(selected.isEmpty)
                }
            }
        }
    }
}

// MARK: - Create Rentals Sheet

private struct CreateRentalsSheetIOS: View {
    let items: [MaterialTransferItem]
    @Binding var selected: Set<UUID>
    var onCancel: () -> Void
    var onCreate: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    ContentUnavailableView("No Items", systemImage: "doc.text", description: Text("Add items to the transfer first"))
                } else {
                    Section {
                        ForEach(items) { item in
                            Toggle(isOn: Binding(
                                get: { selected.contains(item.id) },
                                set: { newVal in
                                    if newVal { selected.insert(item.id) } else { selected.remove(item.id) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.descriptionText)
                                        .font(.headline)

                                    HStack(spacing: 12) {
                                        if let sn = item.serialNumber, !sn.isEmpty {
                                            Label(sn, systemImage: "barcode")
                                                .font(.caption)
                                        }

                                        if let condition = item.conditionCode, !condition.isEmpty {
                                            ConditionBadge(condition: condition)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    } footer: {
                        Text("Selected items will be added as rental items to the well")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Create Rentals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create (\(selected.count))") { onCreate() }
                        .disabled(selected.isEmpty)
                }
            }
        }
    }
}

// MARK: - Affected Rentals Sheet

private struct AffectedRentalsSheetIOS: View {
    let rentals: [RentalItem]
    let isShippingOut: Bool
    var onCancel: () -> Void
    var onApply: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if rentals.isEmpty {
                    ContentUnavailableView("No Matches", systemImage: "magnifyingglass", description: Text("No rentals match the serial numbers on this transfer"))
                } else {
                    Section {
                        ForEach(rentals) { rental in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(rental.name)
                                        .font(.headline)

                                    if let sn = rental.serialNumber, !sn.isEmpty {
                                        Label(sn, systemImage: "barcode")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(rental.onLocation ? "On Location" : "Off Location")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Image(systemName: "arrow.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Text(isShippingOut ? "Off Location" : "On Location")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(isShippingOut ? .orange : .green)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text(isShippingOut ? "Will mark off location:" : "Will restore to on location:")
                    } footer: {
                        Text("Matching is based on serial numbers")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Preview Changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isShippingOut ? "Mark Off Location" : "Restore") { onApply() }
                        .disabled(rentals.isEmpty)
                }
            }
        }
    }
}

#endif
