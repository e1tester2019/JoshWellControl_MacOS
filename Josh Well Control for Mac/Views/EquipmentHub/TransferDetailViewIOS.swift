//
//  TransferDetailViewIOS.swift
//  Josh Well Control for Mac
//
//  Transfer detail for iOS with workflow stepper, info sections,
//  line items, and action buttons.
//

import SwiftUI
import SwiftData

#if os(iOS)
struct TransferDetailViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var transfer: MaterialTransfer

    @State private var showingEditor = false
    @State private var showingAssignWell = false
    @State private var loadedItems: [MaterialTransferItem] = []
    @State private var didLoadItems = false

    private var workflowStatus: TransferWorkflowStatus {
        TransferWorkflowStatus.from(
            isShippingOut: transfer.isShippingOut,
            isShippedBack: transfer.isShippedBack
        )
    }

    private var totalValue: Double {
        loadedItems.reduce(0.0) { $0 + $1.totalValue }
    }

    private var totalWeight: Double {
        loadedItems.compactMap { $0.estimatedWeight }.reduce(0, +)
    }

    var body: some View {
        List {
            // Workflow Stepper
            Section {
                TransferStatusStepper(currentStatus: workflowStatus) { step in
                    withAnimation {
                        switch step {
                        case .draft:
                            transfer.isShippingOut = false
                            transfer.isShippedBack = false
                        case .shippedOut:
                            transfer.isShippingOut = true
                            transfer.isShippedBack = false
                        case .returned:
                            transfer.isShippingOut = true
                            transfer.isShippedBack = true
                        }
                        try? modelContext.save()
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }

            // Transfer Info
            Section("Details") {
                LabeledContent("Date") {
                    Text(transfer.date, style: .date)
                }

                if let well = transfer.well {
                    LabeledContent("Well", value: well.name)
                }

                if let dest = transfer.destinationName, !dest.isEmpty {
                    LabeledContent("Destination", value: dest)
                }

                if let shipping = transfer.shippingCompany, !shipping.isEmpty {
                    LabeledContent("Shipping Co.", value: shipping)
                }

                if let truck = transfer.transportedBy, !truck.isEmpty {
                    LabeledContent("Truck #", value: truck)
                }

                if let activity = transfer.activity, !activity.isEmpty {
                    LabeledContent("Activity", value: activity)
                }
            }

            // Line Items
            Section {
                if !didLoadItems {
                    ProgressView("Loading items...")
                } else if loadedItems.isEmpty {
                    Text("No items added yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(loadedItems) { item in
                        HStack(spacing: 8) {
                            if item.isRentalEquipment {
                                Image(systemName: "shippingbox.fill")
                                    .foregroundStyle(.blue)
                                    .font(.caption)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.descriptionText)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                HStack(spacing: 4) {
                                    Text("Qty: \(item.quantity, specifier: "%.0f")")
                                    if let sn = item.serialNumber, !sn.isEmpty {
                                        Text("• S/N: \(sn)")
                                    }
                                    if let condition = item.conditionCode, !condition.isEmpty {
                                        Text("• \(condition)")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if item.totalValue > 0 {
                                Text(item.totalValue, format: .currency(code: "CAD"))
                                    .font(.caption)
                                    .monospacedDigit()
                            }
                        }
                    }

                    // Totals
                    HStack {
                        Text("Total")
                            .fontWeight(.semibold)
                        Spacer()
                        if totalWeight > 0 {
                            Text("\(totalWeight, specifier: "%.0f") lbs")
                                .foregroundStyle(.secondary)
                        }
                        if totalValue > 0 {
                            Text(totalValue, format: .currency(code: "CAD"))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                    }
                    .font(.subheadline)
                }
            } header: {
                HStack {
                    Text("Line Items")
                    Spacer()
                    Text("\(loadedItems.count) items")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            // Actions
            Section {
                Button {
                    openEditor()
                } label: {
                    Label("Open Editor", systemImage: "pencil.circle")
                }

                if workflowStatus != .returned {
                    Button {
                        advanceStatus()
                    } label: {
                        Label(
                            workflowStatus == .draft ? "Mark Shipped Out" : "Mark Returned",
                            systemImage: "arrow.forward.circle"
                        )
                    }
                    .tint(.blue)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("MT-\(transfer.number)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Load items off the initial render to avoid blocking navigation
            loadedItems = transfer.items ?? []
            didLoadItems = true
        }
        .sheet(isPresented: $showingEditor) {
            if let well = transfer.well {
                NavigationStack {
                    MaterialTransferEditorView(well: well, transfer: transfer)
                }
            }
        }
        .sheet(isPresented: $showingAssignWell) {
            assignWellSheet
        }
    }

    // MARK: - Helpers

    private func openEditor() {
        if transfer.well != nil {
            showingEditor = true
        } else {
            showingAssignWell = true
        }
    }

    private func advanceStatus() {
        switch workflowStatus {
        case .draft:
            transfer.isShippingOut = true
        case .shippedOut:
            transfer.isShippedBack = true
        case .returned:
            break
        }
        try? modelContext.save()
    }

    // MARK: - Assign Well Sheet

    @ViewBuilder
    private var assignWellSheet: some View {
        AssignWellSheetIOS(transfer: transfer) {
            showingAssignWell = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showingEditor = true
            }
        } onCancel: {
            showingAssignWell = false
        }
    }
}

// MARK: - Assign Well Sheet (separate struct to isolate @Query)

private struct AssignWellSheetIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Well.name) private var wells: [Well]
    @Bindable var transfer: MaterialTransfer
    let onAssign: () -> Void
    let onCancel: () -> Void

    var body: some View {
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
                            onAssign()
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
                        onCancel()
                    }
                }
            }
        }
    }
}
#endif
