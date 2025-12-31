//
//  RentalEquipment.swift
//  Josh Well Control for Mac
//
//  Equipment registry - tracks physical rental items across their lifetime.
//  Each piece of equipment can have multiple RentalItem usage records (per well).
//

import Foundation
import SwiftData
import SwiftUI

/// Tracks equipment status
enum EquipmentLocation: String, Codable, CaseIterable {
    case inUse = "In Use"
    case onLocation = "On Location"
    case withVendor = "With Vendor"

    var icon: String {
        switch self {
        case .inUse: return "checkmark.circle.fill"
        case .onLocation: return "mappin.circle"
        case .withVendor: return "building.2"
        }
    }

    var color: Color {
        switch self {
        case .inUse: return .green
        case .onLocation: return .blue
        case .withVendor: return .secondary
        }
    }
}

@Model
final class RentalEquipment {
    var id: UUID = UUID()
    var serialNumber: String = ""
    var name: String = ""
    var description_: String = ""  // 'description' is reserved
    var model: String = ""
    var notes: String = ""
    var isActive: Bool = true
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    // Location tracking
    var locationStatusRaw: String = EquipmentLocation.withVendor.rawValue
    var currentLocationName: String = ""  // Well/Pad name or vendor name
    var lastMovedAt: Date?

    // Relationships
    @Relationship var category: RentalCategory?
    @Relationship var vendor: Vendor?

    @Relationship(deleteRule: .cascade, inverse: \RentalEquipmentIssue.equipment)
    var issues: [RentalEquipmentIssue]?

    @Relationship(deleteRule: .nullify, inverse: \RentalItem.equipment)
    var rentalUsages: [RentalItem]?

    @Relationship(deleteRule: .nullify, inverse: \MaterialTransferItem.equipment)
    var transferItems: [MaterialTransferItem]?

    init(serialNumber: String = "",
         name: String = "",
         description: String = "",
         model: String = "") {
        self.serialNumber = serialNumber
        self.name = name
        self.description_ = description
        self.model = model
    }

    // MARK: - Computed Properties

    /// Current location status
    var locationStatus: EquipmentLocation {
        get { EquipmentLocation(rawValue: locationStatusRaw) ?? .withVendor }
        set {
            locationStatusRaw = newValue.rawValue
            lastMovedAt = .now
        }
    }

    /// Display name with serial number
    var displayName: String {
        if serialNumber.isEmpty {
            return name
        }
        return "\(name) (\(serialNumber))"
    }

    /// Total days used across all wells
    var totalDaysUsed: Int {
        (rentalUsages ?? []).reduce(0) { $0 + $1.totalDays }
    }

    /// Number of wells this equipment has been used on
    var wellsUsedCount: Int {
        Set((rentalUsages ?? []).compactMap { $0.well?.id }).count
    }

    /// Current active rental (if any) - equipment marked as "run" on a well
    var currentActiveRental: RentalItem? {
        (rentalUsages ?? []).first { $0.used && !$0.invoiced }
    }

    /// The well where this equipment is currently active
    var currentWell: Well? {
        currentActiveRental?.well
    }

    /// Check if equipment is currently in use on any well
    var isCurrentlyInUse: Bool {
        currentActiveRental != nil
    }

    /// All rentals sorted by date (most recent first)
    var sortedRentals: [RentalItem] {
        (rentalUsages ?? []).sorted { a, b in
            let aDate = a.startDate ?? .distantPast
            let bDate = b.startDate ?? .distantPast
            return aDate > bDate
        }
    }

    /// Issues sorted by date (most recent first)
    var sortedIssues: [RentalEquipmentIssue] {
        (issues ?? []).sorted { $0.date > $1.date }
    }

    /// Count of unresolved issues
    var unresolvedIssueCount: Int {
        (issues ?? []).filter { !$0.isResolved }.count
    }

    /// Has any failure issues
    var hasFailures: Bool {
        (issues ?? []).contains { $0.issueType == .failure }
    }

    /// Last issue (most recent)
    var lastIssue: RentalEquipmentIssue? {
        sortedIssues.first
    }

    // MARK: - Methods

    /// Check if this equipment can be transferred to a new well
    /// Returns nil if OK, or error message if not allowed
    func canTransfer(to destinationWell: Well) -> String? {
        guard let current = currentActiveRental else {
            return nil // Not currently active, can be assigned anywhere
        }

        if current.well?.id == destinationWell.id {
            return "Equipment is already on this well"
        }

        // Could add more validation here
        return nil
    }

    /// Log timestamp when modified
    func touch() {
        updatedAt = .now
    }

    // MARK: - Location Management

    /// Mark equipment as in use at a location
    func markInUse(at locationName: String) {
        locationStatus = .inUse
        currentLocationName = locationName
        touch()
    }

    /// Mark equipment as on location but not in use (standby)
    func markOnLocation(at locationName: String) {
        locationStatus = .onLocation
        currentLocationName = locationName
        touch()
    }

    /// Mark equipment as received at a location (from vendor or transfer) - defaults to on location
    func receiveAt(locationName: String) {
        locationStatus = .onLocation
        currentLocationName = locationName
        touch()
    }

    /// Mark equipment as shipped back to vendor
    func backhaul() {
        locationStatus = .withVendor
        currentLocationName = vendor?.companyName ?? "Vendor"
        touch()
    }
}
