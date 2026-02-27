//
//  EquipmentHubViewModel.swift
//  Josh Well Control for Mac
//
//  Observable ViewModel for the Equipment Hub.
//

import SwiftUI
import SwiftData

// MARK: - Hub Tab

enum HubTab: String, CaseIterable, Identifiable {
    case equipment = "Equipment"
    case transfers = "Transfers"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .equipment: return "shippingbox.fill"
        case .transfers: return "arrow.left.arrow.right.circle.fill"
        }
    }
}

// MARK: - Equipment View Mode

enum EquipmentViewMode: String, CaseIterable, Identifiable {
    case list = "List"
    case board = "Board"
    case timeline = "Timeline"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .list: return "list.bullet"
        case .board: return "rectangle.split.3x1"
        case .timeline: return "chart.bar.xaxis"
        }
    }
}

// MARK: - KPI Data

struct EquipmentKPIData {
    var inUseCount: Int = 0
    var onLocationCount: Int = 0
    var issueCount: Int = 0
    var dailyCost: Double = 0
    var activeTransferCount: Int = 0
}

// MARK: - Sheet Type

enum EquipmentHubSheet: Identifiable {
    case addEquipment
    case editEquipment(RentalEquipment)
    case issueLog(RentalEquipment)
    case categoryManager
    case transferEditor(MaterialTransfer, Well)
    case importSheet
    case bulkEdit([RentalEquipment])
    case sendToLocation([RentalEquipment])
    case equipmentReport
    case createTransfer([RentalEquipment])
    case assignWellToTransfer(MaterialTransfer)

    var id: String {
        switch self {
        case .addEquipment: return "addEquipment"
        case .editEquipment(let eq): return "editEquipment-\(eq.id)"
        case .issueLog(let eq): return "issueLog-\(eq.id)"
        case .categoryManager: return "categoryManager"
        case .transferEditor(let t, _): return "transferEditor-\(t.id)"
        case .importSheet: return "importSheet"
        case .bulkEdit: return "bulkEdit"
        case .sendToLocation: return "sendToLocation"
        case .equipmentReport: return "equipmentReport"
        case .createTransfer: return "createTransfer"
        case .assignWellToTransfer(let t): return "assignWell-\(t.id)"
        }
    }
}

// MARK: - ViewModel

@Observable
final class EquipmentHubViewModel {
    // MARK: Navigation
    var selectedTab: HubTab = .equipment
    var viewMode: EquipmentViewMode = .list

    // MARK: Search & Filters
    var searchText: String = ""
    var filterStatus: EquipmentLocation? = nil
    var filterCategory: RentalCategory? = nil
    var filterVendor: Vendor? = nil
    var filterWell: Well? = nil
    var filterActiveOnly: Bool = false

    // MARK: Selection
    var selectedEquipmentID: RentalEquipment.ID? = nil
    var selectedTransferID: MaterialTransfer.ID? = nil
    var selectedEquipmentIDs: Set<UUID> = []

    // MARK: Sheet
    var activeSheet: EquipmentHubSheet? = nil

    // MARK: Sorting
    var equipmentSortOrder: [KeyPathComparator<RentalEquipment>] = [
        .init(\.name, order: .forward)
    ]

    // MARK: - Computed: Has Active Filters

    var hasActiveFilters: Bool {
        filterStatus != nil || filterCategory != nil || filterVendor != nil || filterWell != nil || filterActiveOnly || !searchText.isEmpty
    }

    // MARK: - Filtering

    func filteredEquipment(from allEquipment: [RentalEquipment]) -> [RentalEquipment] {
        var result = allEquipment

        if filterActiveOnly {
            result = result.filter { $0.isActive }
        }

        if let status = filterStatus {
            result = result.filter { $0.locationStatus == status }
        }

        if let category = filterCategory {
            result = result.filter { $0.category?.id == category.id }
        }

        if let vendor = filterVendor {
            result = result.filter { $0.vendor?.id == vendor.id }
        }

        if let well = filterWell {
            result = result.filter { eq in
                (eq.rentalUsages ?? []).contains { $0.well?.id == well.id }
            }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(query) ||
                $0.serialNumber.localizedCaseInsensitiveContains(query) ||
                ($0.vendor?.companyName ?? "").localizedCaseInsensitiveContains(query) ||
                ($0.category?.name ?? "").localizedCaseInsensitiveContains(query)
            }
        }

        return result
    }

    func filteredTransfers(from allTransfers: [MaterialTransfer]) -> [MaterialTransfer] {
        var result = allTransfers

        if let well = filterWell {
            result = result.filter { $0.well?.id == well.id }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                "MT-\($0.number)".localizedCaseInsensitiveContains(query) ||
                ($0.destinationName ?? "").localizedCaseInsensitiveContains(query) ||
                ($0.well?.name ?? "").localizedCaseInsensitiveContains(query) ||
                ($0.shippingCompany ?? "").localizedCaseInsensitiveContains(query)
            }
        }

        // Sort newest first
        result.sort { $0.date > $1.date }

        return result
    }

    // MARK: - KPI Computation

    func computeKPIs(equipment: [RentalEquipment], transfers: [MaterialTransfer]) -> EquipmentKPIData {
        var kpi = EquipmentKPIData()

        kpi.inUseCount = equipment.filter { $0.locationStatus == .inUse }.count
        kpi.onLocationCount = equipment.filter { $0.locationStatus == .onLocation }.count
        kpi.issueCount = equipment.reduce(0) { $0 + $1.unresolvedIssueCount }

        // Daily cost: sum of costPerDay for all active rentals across all equipment
        kpi.dailyCost = equipment.compactMap { $0.currentActiveRental?.costPerDay }.reduce(0, +)

        // Active transfers: those that are shipping out but not yet shipped back
        kpi.activeTransferCount = transfers.filter { $0.isShippingOut && !$0.isShippedBack }.count

        return kpi
    }

    // MARK: - Actions

    func clearFilters() {
        searchText = ""
        filterStatus = nil
        filterCategory = nil
        filterVendor = nil
        filterWell = nil
        filterActiveOnly = false
    }

    func selectEquipment(_ equipment: RentalEquipment?) {
        selectedEquipmentID = equipment?.id
    }

    func selectTransfer(_ transfer: MaterialTransfer?) {
        selectedTransferID = transfer?.id
    }
}
