//
//  EquipmentBoardView.swift
//  Josh Well Control for Mac
//
//  Kanban board with columns for each EquipmentLocation status.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

#if os(macOS)
struct EquipmentBoardView: View {
    let equipment: [RentalEquipment]
    @Binding var selectedID: RentalEquipment.ID?
    let onStatusChange: (RentalEquipment, EquipmentLocation) -> Void

    private var columns: [(status: EquipmentLocation, items: [RentalEquipment])] {
        EquipmentLocation.allCases.map { status in
            (status: status, items: equipment.filter { $0.locationStatus == status })
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: EquipmentHubLayout.boardColumnSpacing) {
            ForEach(columns, id: \.status) { column in
                boardColumn(status: column.status, items: column.items)
            }
        }
        .padding(EquipmentHubLayout.sidebarPadding)
    }

    // MARK: - Column

    @ViewBuilder
    private func boardColumn(status: EquipmentLocation, items: [RentalEquipment]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Column header
            HStack {
                Image(systemName: status.icon)
                    .foregroundStyle(status.color)
                Text(status.rawValue)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(8)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(EquipmentStatusPalette.cellBackground(for: status))
            .cornerRadius(8)

            // Cards
            ScrollView(.vertical) {
                LazyVStack(spacing: 6) {
                    ForEach(items) { eq in
                        boardCard(eq, columnStatus: status)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onDrop(of: [.text], isTargeted: nil) { providers in
            handleDrop(providers: providers, targetStatus: status)
        }
    }

    // MARK: - Card

    @ViewBuilder
    private func boardCard(_ eq: RentalEquipment, columnStatus: EquipmentLocation) -> some View {
        let isSelected = selectedID == eq.id

        EquipmentCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(eq.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer()
                    if eq.unresolvedIssueCount > 0 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }

                if !eq.serialNumber.isEmpty {
                    Text("S/N: \(eq.serialNumber)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    if let category = eq.category {
                        Label(category.name, systemImage: category.icon)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if let vendor = eq.vendor {
                        Text(vendor.companyName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .onTapGesture {
            selectedID = eq.id
        }
        .onDrag {
            NSItemProvider(object: eq.id.uuidString as NSString)
        }
    }

    // MARK: - Drag & Drop

    private func handleDrop(providers: [NSItemProvider], targetStatus: EquipmentLocation) -> Bool {
        for provider in providers {
            provider.loadObject(ofClass: NSString.self) { item, _ in
                guard let uuidString = item as? String,
                      let uuid = UUID(uuidString: uuidString),
                      let eq = equipment.first(where: { $0.id == uuid }) else { return }

                DispatchQueue.main.async {
                    if eq.locationStatus != targetStatus {
                        onStatusChange(eq, targetStatus)
                    }
                }
            }
        }
        return true
    }
}
#endif
