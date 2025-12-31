//
//  Vendor.swift
//  Josh Well Control for Mac
//
//  Service providers for drilling operations.
//

import Foundation
import SwiftData

enum VendorServiceType: String, Codable, CaseIterable {
    case cementing = "Cementing"
    case directionalDrilling = "Directional Drilling"
    case casingCrews = "Casing Crews"
    case mudLogging = "Mud Logging"
    case wireline = "Wireline"
    case completions = "Completions"
    case rigServices = "Rig Services"
    case testing = "Testing"
    case rentals = "Rentals"
    case trucking = "Trucking"
    case other = "Other"

    var icon: String {
        switch self {
        case .cementing: return "drop.fill"
        case .directionalDrilling: return "arrow.triangle.branch"
        case .casingCrews: return "person.3"
        case .mudLogging: return "chart.line.uptrend.xyaxis"
        case .wireline: return "cable.connector"
        case .completions: return "checkmark.seal"
        case .rigServices: return "gear"
        case .testing: return "gauge"
        case .rentals: return "shippingbox"
        case .trucking: return "truck.box"
        case .other: return "ellipsis.circle"
        }
    }
}

@Model
final class Vendor {
    var id: UUID = UUID()
    var companyName: String = ""
    var serviceTypeRaw: String = VendorServiceType.other.rawValue
    var contactName: String = ""
    var contactTitle: String = ""
    var phone: String = ""
    var emergencyPhone: String = ""
    var email: String = ""
    var address: String = ""
    var notes: String = ""
    var isActive: Bool = true

    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \TaskVendorAssignment.vendor) var taskAssignments: [TaskVendorAssignment]?
    @Relationship(deleteRule: .nullify, inverse: \CallLogEntry.vendor) var callLogs: [CallLogEntry]?
    @Relationship(deleteRule: .nullify, inverse: \JobCode.defaultVendor) var defaultForJobCodes: [JobCode]?

    // Multiple contacts and addresses
    @Relationship(deleteRule: .cascade, inverse: \VendorContact.vendor) var contacts: [VendorContact]?
    @Relationship(deleteRule: .cascade, inverse: \VendorAddress.vendor) var addresses: [VendorAddress]?

    // Equipment from this vendor
    @Relationship(deleteRule: .nullify, inverse: \RentalEquipment.vendor) var equipment: [RentalEquipment]?

    /// All tasks this vendor is assigned to
    var assignedTasks: [LookAheadTask] {
        (taskAssignments ?? []).compactMap { $0.task }
    }

    init(companyName: String = "",
         serviceType: VendorServiceType = .other,
         contactName: String = "",
         phone: String = "") {
        self.companyName = companyName
        self.serviceTypeRaw = serviceType.rawValue
        self.contactName = contactName
        self.phone = phone
    }

    var serviceType: VendorServiceType {
        get { VendorServiceType(rawValue: serviceTypeRaw) ?? .other }
        set {
            serviceTypeRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    var displayName: String {
        if contactName.isEmpty {
            return companyName
        }
        return "\(companyName) - \(contactName)"
    }

    /// Formatted phone for display
    var phoneFormatted: String {
        guard !phone.isEmpty else { return "" }
        // Return as-is for now, could add formatting logic
        return phone
    }

    /// Check if vendor has emergency contact
    var hasEmergencyContact: Bool {
        !emergencyPhone.isEmpty
    }

    /// Total calls made to this vendor
    var totalCalls: Int {
        callLogs?.count ?? 0
    }

    /// Recent calls (last 30 days)
    var recentCalls: [CallLogEntry] {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date.now) ?? Date.now
        return (callLogs ?? []).filter { $0.timestamp >= thirtyDaysAgo }.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Contact Helpers

    /// Primary contact for this vendor
    var primaryContact: VendorContact? {
        (contacts ?? []).first { $0.isPrimary && $0.isActive } ?? (contacts ?? []).first { $0.isActive }
    }

    /// Active contacts sorted by primary first, then by role
    var sortedContacts: [VendorContact] {
        (contacts ?? []).filter { $0.isActive }.sorted { a, b in
            if a.isPrimary != b.isPrimary { return a.isPrimary }
            return a.role.rawValue < b.role.rawValue
        }
    }

    /// Get contacts by role
    func contacts(for role: VendorContactRole) -> [VendorContact] {
        (contacts ?? []).filter { $0.role == role && $0.isActive }
    }

    // MARK: - Address Helpers

    /// Primary address for this vendor
    var primaryAddress: VendorAddress? {
        (addresses ?? []).first { $0.isPrimary && $0.isActive } ?? (addresses ?? []).first { $0.isActive }
    }

    /// Active addresses sorted by primary first, then by type
    var sortedAddresses: [VendorAddress] {
        (addresses ?? []).filter { $0.isActive }.sorted { a, b in
            if a.isPrimary != b.isPrimary { return a.isPrimary }
            return a.addressType.rawValue < b.addressType.rawValue
        }
    }

    /// Get addresses by type
    func addresses(for type: VendorAddressType) -> [VendorAddress] {
        (addresses ?? []).filter { $0.addressType == type && $0.isActive }
    }

    /// Shipping address (first shipping type, or primary)
    var shippingAddress: VendorAddress? {
        addresses(for: .shipping).first ?? primaryAddress
    }

    // MARK: - Equipment Helpers

    /// Active equipment from this vendor
    var activeEquipment: [RentalEquipment] {
        (equipment ?? []).filter { $0.isActive }
    }

    /// Total equipment count
    var equipmentCount: Int {
        equipment?.count ?? 0
    }
}
