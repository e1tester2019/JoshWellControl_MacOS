//
//  TransferDetailPaneView.swift
//  Josh Well Control for Mac
//
//  Transfer detail with workflow stepper and line items.
//

import SwiftUI
import SwiftData

#if os(macOS)
struct TransferDetailPaneView: View {
    @Bindable var transfer: MaterialTransfer

    let onOpenEditor: () -> Void
    let onAdvanceStatus: () -> Void

    private var workflowStatus: TransferWorkflowStatus {
        TransferWorkflowStatus.from(
            isShippingOut: transfer.isShippingOut,
            isShippedBack: transfer.isShippedBack
        )
    }

    private var totalValue: Double {
        (transfer.items ?? []).reduce(0.0) { $0 + $1.totalValue }
    }

    private var totalWeight: Double {
        (transfer.items ?? []).compactMap { $0.estimatedWeight }.reduce(0, +)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EquipmentHubLayout.sectionSpacing) {
                headerSection
                stepperSection
                detailsSection
                itemsSection
                actionsSection
            }
            .padding(EquipmentHubLayout.sidebarPadding)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MT-\(transfer.number)")
                    .font(.title2)
                    .fontWeight(.semibold)

                if let wellName = transfer.well?.name {
                    Label(wellName, systemImage: "building.2")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            TransferStatusBadge(status: workflowStatus)
        }
    }

    // MARK: - Stepper

    private var stepperSection: some View {
        EquipmentCard {
            TransferStatusStepper(currentStatus: workflowStatus) { step in
                // Advance or regress to tapped step
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
            }
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
        EquipmentCard {
            VStack(alignment: .leading, spacing: 8) {
                StandardSectionHeader(title: "Details", icon: "info.circle")

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("Date")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(transfer.date, style: .date)
                            .font(.caption)
                    }

                    if let dest = transfer.destinationName, !dest.isEmpty {
                        GridRow {
                            Text("Destination")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(dest)
                                .font(.caption)
                        }
                    }

                    if let shipping = transfer.shippingCompany, !shipping.isEmpty {
                        GridRow {
                            Text("Shipping Co.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(shipping)
                                .font(.caption)
                        }
                    }

                    if let truck = transfer.transportedBy, !truck.isEmpty {
                        GridRow {
                            Text("Truck #")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(truck)
                                .font(.caption)
                        }
                    }

                    if let activity = transfer.activity, !activity.isEmpty {
                        GridRow {
                            Text("Activity")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(activity)
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Items

    private var itemsSection: some View {
        EquipmentCard {
            VStack(alignment: .leading, spacing: 8) {
                StandardSectionHeader(
                    title: "Line Items",
                    icon: "list.bullet",
                    subtitle: "\(transfer.items?.count ?? 0) items"
                )

                let items = transfer.items ?? []
                if items.isEmpty {
                    Text("No items added yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        HStack(spacing: 8) {
                            if item.isRentalEquipment {
                                Image(systemName: "shippingbox.fill")
                                    .foregroundStyle(.blue)
                                    .font(.caption)
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.displayName)
                                    .font(.caption)
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
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if item.totalValue > 0 {
                                Text(item.totalValue, format: .currency(code: "CAD"))
                                    .font(.caption)
                                    .monospacedDigit()
                            }
                        }
                        .padding(.vertical, 2)

                        if item.id != items.last?.id {
                            Divider()
                        }
                    }

                    Divider()

                    HStack {
                        Text("Total")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Spacer()
                        if totalWeight > 0 {
                            Text("\(totalWeight, specifier: "%.0f") lbs")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if totalValue > 0 {
                            Text(totalValue, format: .currency(code: "CAD"))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        HStack(spacing: 8) {
            Button {
                onOpenEditor()
            } label: {
                Label("Open Editor", systemImage: "pencil.circle")
            }
            .controlSize(.small)

            if workflowStatus != .returned {
                Button {
                    onAdvanceStatus()
                } label: {
                    Label(
                        workflowStatus == .draft ? "Mark Shipped Out" : "Mark Returned",
                        systemImage: "arrow.forward.circle"
                    )
                }
                .controlSize(.small)
                .tint(.blue)
            }

            Spacer()
        }
    }
}
#endif
