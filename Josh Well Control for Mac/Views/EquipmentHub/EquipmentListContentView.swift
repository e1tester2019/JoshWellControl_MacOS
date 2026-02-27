//
//  EquipmentListContentView.swift
//  Josh Well Control for Mac
//
//  Flat sortable Table for equipment list in the Hub.
//

import SwiftUI
import SwiftData

#if os(macOS)
struct EquipmentListContentView: View {
    let equipment: [RentalEquipment]
    @Binding var selectedID: RentalEquipment.ID?
    @Binding var selectedIDs: Set<UUID>
    @Binding var sortOrder: [KeyPathComparator<RentalEquipment>]

    let onLogIssue: (RentalEquipment) -> Void
    let onEdit: (RentalEquipment) -> Void
    let onBackhaul: (RentalEquipment) -> Void
    let onDelete: (RentalEquipment) -> Void

    var body: some View {
        if equipment.isEmpty {
            StandardEmptyState(
                icon: "shippingbox",
                title: "No Equipment Found",
                description: "Add equipment or adjust your filters."
            )
        } else {
            Table(equipment, selection: $selectedID, sortOrder: $sortOrder) {
                TableColumn("Status", value: \.locationStatusRaw) { eq in
                    EquipmentStatusBadge(status: eq.locationStatus)
                }
                .width(min: 90, ideal: 110, max: 130)

                TableColumn("Name", value: \.name) { eq in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(eq.name)
                            .fontWeight(.medium)
                        if !eq.serialNumber.isEmpty {
                            Text(eq.serialNumber)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .width(min: 120, ideal: 180)

                TableColumn("Category") { eq in
                    if let category = eq.category {
                        Label(category.name, systemImage: category.icon)
                            .font(.caption)
                    } else {
                        Text("—")
                            .foregroundStyle(.tertiary)
                    }
                }
                .width(min: 80, ideal: 120, max: 160)

                TableColumn("Vendor") { eq in
                    Text(eq.vendor?.companyName ?? "—")
                        .foregroundStyle(eq.vendor != nil ? .primary : .tertiary)
                }
                .width(min: 80, ideal: 120, max: 160)

                TableColumn("Location") { eq in
                    Text(eq.currentLocationName.isEmpty ? "—" : eq.currentLocationName)
                        .foregroundStyle(eq.currentLocationName.isEmpty ? .tertiary : .primary)
                        .font(.caption)
                }
                .width(min: 70, ideal: 100, max: 140)

                TableColumn("Issues") { eq in
                    let count = eq.unresolvedIssueCount
                    if count > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption2)
                            Text("\(count)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } else {
                        Text("—")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                    }
                }
                .width(min: 50, ideal: 60, max: 80)

                TableColumn("Days") { eq in
                    Text("\(eq.totalDaysUsed)")
                        .font(.caption)
                        .monospacedDigit()
                }
                .width(min: 40, ideal: 50, max: 70)
            }
            .contextMenu(forSelectionType: RentalEquipment.ID.self) { ids in
                if let id = ids.first, let eq = equipment.first(where: { $0.id == id }) {
                    Button {
                        onEdit(eq)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    Button {
                        onLogIssue(eq)
                    } label: {
                        Label("Log Issue", systemImage: "exclamationmark.triangle")
                    }

                    if eq.locationStatus != .withVendor {
                        Button {
                            onBackhaul(eq)
                        } label: {
                            Label("Backhaul to Vendor", systemImage: "arrow.uturn.backward")
                        }
                    }

                    Divider()

                    Button(role: .destructive) {
                        onDelete(eq)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .onChange(of: selectedID) { _, newValue in
                // Sync single selection to multi-select set for toolbar actions
                if let id = newValue {
                    selectedIDs = [id]
                }
            }
        }
    }
}
#endif
