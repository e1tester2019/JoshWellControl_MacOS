//
//  MaterialTransferListViewIOS.swift
//  Josh Well Control for Mac
//
//  iOS-optimized material transfer views
//

#if os(iOS)
import SwiftUI
import SwiftData

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
                    TransferRow(transfer: transfer)
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
            AddMaterialTransferSheet(well: well, isPresented: $showingAddSheet)
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

// MARK: - Transfer Row

private struct TransferRow: View {
    let transfer: MaterialTransfer

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Transfer #\(transfer.number)")
                    .font(.headline)
                Spacer()
                Text(transfer.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let dest = transfer.destinationName, !dest.isEmpty {
                Text("To: \(dest)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let items = transfer.items, !items.isEmpty {
                Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.blue)
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

    var body: some View {
        List {
            Section("Details") {
                HStack {
                    Text("Transfer Number")
                    Spacer()
                    TextField("#", value: $transfer.number, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                DatePicker("Date", selection: $transfer.date, displayedComponents: .date)

                TextField("Destination", text: Binding(
                    get: { transfer.destinationName ?? "" },
                    set: { transfer.destinationName = $0.isEmpty ? nil : $0 }
                ))

                TextField("Activity", text: Binding(
                    get: { transfer.activity ?? "" },
                    set: { transfer.activity = $0.isEmpty ? nil : $0 }
                ))
            }

            Section("Items") {
                if let items = transfer.items, !items.isEmpty {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.descriptionText)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            HStack {
                                Text("Qty: \(item.quantity, format: .number)")
                                if let serial = item.serialNumber, !serial.isEmpty {
                                    Text("• S/N: \(serial)")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            if let condition = item.conditionCode, !condition.isEmpty {
                                Text("Condition: \(condition)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete(perform: deleteItems)
                }

                Button {
                    showingAddItemSheet = true
                } label: {
                    Label("Add Item", systemImage: "plus")
                }
            }

            Section {
                Button {
                    // Share transfer PDF
                } label: {
                    Label("Share Transfer", systemImage: "square.and.arrow.up")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Transfer #\(transfer.number)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddItemSheet) {
            AddTransferItemSheet(transfer: transfer, isPresented: $showingAddItemSheet)
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
}

// MARK: - Add Material Transfer Sheet

private struct AddMaterialTransferSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let well: Well
    @Binding var isPresented: Bool

    @State private var number: Int = Int.random(in: 1000...9999)
    @State private var destination = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    Text("Transfer Number")
                    Spacer()
                    TextField("#", value: $number, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                TextField("Destination", text: $destination)

                DatePicker("Date", selection: $date, displayedComponents: .date)
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
                }
            }
        }
    }

    private func createTransfer() {
        let transfer = MaterialTransfer()
        transfer.number = number
        transfer.destinationName = destination.isEmpty ? nil : destination
        transfer.date = date
        transfer.well = well
        modelContext.insert(transfer)
        try? modelContext.save()
    }
}

// MARK: - Add Transfer Item Sheet

private struct AddTransferItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let transfer: MaterialTransfer
    @Binding var isPresented: Bool

    @State private var description = ""
    @State private var quantity: Double = 1
    @State private var serialNumber = ""
    @State private var condition = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Description", text: $description)

                HStack {
                    Text("Quantity")
                    Spacer()
                    TextField("Qty", value: $quantity, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                TextField("Serial Number", text: $serialNumber)

                TextField("Condition", text: $condition)
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addItem()
                        dismiss()
                    }
                    .disabled(description.isEmpty)
                }
            }
        }
    }

    private func addItem() {
        let item = MaterialTransferItem(descriptionText: "")
        item.descriptionText = description
        item.quantity = quantity
        item.serialNumber = serialNumber.isEmpty ? nil : serialNumber
        item.conditionCode = condition.isEmpty ? nil : condition
        item.transfer = transfer
        if transfer.items == nil { transfer.items = [] }
        transfer.items?.append(item)
        modelContext.insert(item)
        try? modelContext.save()
    }
}

#endif
