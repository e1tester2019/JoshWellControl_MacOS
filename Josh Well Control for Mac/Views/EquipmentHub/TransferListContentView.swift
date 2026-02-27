//
//  TransferListContentView.swift
//  Josh Well Control for Mac
//
//  Flat transfer list with status badges and item counts.
//

import SwiftUI
import SwiftData

#if os(macOS)
struct TransferListContentView: View {
    let transfers: [MaterialTransfer]
    @Binding var selectedID: MaterialTransfer.ID?

    let onOpenEditor: (MaterialTransfer) -> Void
    let onDelete: (MaterialTransfer) -> Void

    var body: some View {
        if transfers.isEmpty {
            StandardEmptyState(
                icon: "arrow.left.arrow.right.circle",
                title: "No Transfers Found",
                description: "Create a transfer from the equipment list or adjust your filters."
            )
        } else {
            List(transfers, selection: $selectedID) { transfer in
                transferRow(transfer)
                    .tag(transfer.id)
                    .contextMenu {
                        Button {
                            onOpenEditor(transfer)
                        } label: {
                            Label("Open Editor", systemImage: "pencil")
                        }

                        Divider()

                        Button(role: .destructive) {
                            onDelete(transfer)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    @ViewBuilder
    private func transferRow(_ transfer: MaterialTransfer) -> some View {
        let status = TransferWorkflowStatus.from(
            isShippingOut: transfer.isShippingOut,
            isShippedBack: transfer.isShippedBack
        )
        let itemCount = transfer.items?.count ?? 0
        let totalValue = (transfer.items ?? []).reduce(0.0) { $0 + $1.totalValue }

        HStack(spacing: 10) {
            TransferStatusBadge(status: status)

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

                HStack(spacing: 4) {
                    Text("\(itemCount) items")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if totalValue > 0 {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(totalValue, format: .currency(code: "CAD"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
#endif
