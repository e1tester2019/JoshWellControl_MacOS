//
//  EquipmentDesignSystem.swift
//  Josh Well Control for Mac
//
//  Centralized visual design for the Equipment Hub.
//

import SwiftUI

// MARK: - Equipment Status Palette

enum EquipmentStatusPalette {
    static func color(for status: EquipmentLocation) -> Color {
        status.color
    }

    static func gradient(for status: EquipmentLocation) -> [Color] {
        switch status {
        case .inUse: return [.green, .mint]
        case .onLocation: return [.blue, .cyan]
        case .withVendor: return [.gray, .gray.opacity(0.7)]
        }
    }

    static func cellBackground(for status: EquipmentLocation) -> Color {
        switch status {
        case .inUse: return .green.opacity(0.08)
        case .onLocation: return .blue.opacity(0.08)
        case .withVendor: return .clear
        }
    }
}

// MARK: - Rental Status Palette

enum RentalStatusPalette {
    static func color(for status: RentalItemStatus) -> Color {
        status.color
    }
}

// MARK: - Transfer Workflow Status

enum TransferWorkflowStatus: String, CaseIterable {
    case draft = "Draft"
    case shippedOut = "Shipped Out"
    case returned = "Returned"

    var icon: String {
        switch self {
        case .draft: return "doc.badge.clock"
        case .shippedOut: return "shippingbox.fill"
        case .returned: return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .draft: return .orange
        case .shippedOut: return .blue
        case .returned: return .green
        }
    }

    var stepIndex: Int {
        switch self {
        case .draft: return 0
        case .shippedOut: return 1
        case .returned: return 2
        }
    }

    /// Derive status from MaterialTransfer boolean flags
    static func from(isShippingOut: Bool, isShippedBack: Bool) -> TransferWorkflowStatus {
        if isShippedBack { return .returned }
        if isShippingOut { return .shippedOut }
        return .draft
    }
}

// MARK: - Equipment Status Badge

struct EquipmentStatusBadge: View {
    let status: EquipmentLocation

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: status.icon)
                .font(.system(size: 9))
            Text(status.rawValue)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(EquipmentStatusPalette.color(for: status))
        .cornerRadius(6)
    }
}

// MARK: - Rental Status Badge

struct RentalStatusBadge: View {
    let status: RentalItemStatus
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            if !compact {
                Image(systemName: status.icon)
                    .font(.system(size: 9))
            }
            Text(compact ? String(status.rawValue.prefix(1)) : status.rawValue)
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 2 : 4)
        .background(RentalStatusPalette.color(for: status))
        .cornerRadius(compact ? 4 : 6)
    }
}

// MARK: - Transfer Status Badge

struct TransferStatusBadge: View {
    let status: TransferWorkflowStatus

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: status.icon)
                .font(.system(size: 9))
            Text(status.rawValue)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.color)
        .cornerRadius(6)
    }
}

// MARK: - Equipment Card

struct EquipmentCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            #if os(macOS)
            .background(.ultraThinMaterial)
            #else
            .background(Color(.systemBackground))
            #endif
            .cornerRadius(10)
            .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
    }
}

// MARK: - Animation Constants

enum EquipmentAnimation {
    static let selection = Animation.spring(response: 0.3, dampingFraction: 0.7)
    static let tabSwitch = Animation.easeInOut(duration: 0.2)
    static let filterChange = Animation.easeInOut(duration: 0.15)
    static let detailTransition = Animation.easeInOut(duration: 0.25)
}

// MARK: - Layout Constants

enum EquipmentHubLayout {
    static let listMinWidth: CGFloat = 450
    static let detailMinWidth: CGFloat = 300
    static let detailIdealWidth: CGFloat = 340
    static let detailMaxWidth: CGFloat = 400
    static let kpiStripHeight: CGFloat = 80
    static let filterBarHeight: CGFloat = 44
    static let rowHeight: CGFloat = 36
    static let boardCardMinWidth: CGFloat = 250
    static let boardColumnSpacing: CGFloat = 12
    static let sidebarPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 12

    #if os(iOS)
    static let iOSKPIGridSpacing: CGFloat = 10
    static let iOSRowVerticalPadding: CGFloat = 4
    static let iOSListInsets: CGFloat = 16
    static let iOSTabPickerInsets = EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
    #endif
}
