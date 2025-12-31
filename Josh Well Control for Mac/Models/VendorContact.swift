//
//  VendorContact.swift
//  Josh Well Control for Mac
//
//  Contact person for a vendor (operations, sales, shipping, etc.)
//

import Foundation
import SwiftData

enum VendorContactRole: String, Codable, CaseIterable {
    case operations = "Operations"
    case sales = "Sales"
    case technical = "Technical"
    case shippingReceiving = "Shipping/Receiving"
    case accounting = "Accounting"
    case emergency = "Emergency"
    case general = "General"
    case other = "Other"

    var icon: String {
        switch self {
        case .operations: return "gearshape.2"
        case .sales: return "dollarsign.circle"
        case .technical: return "wrench.and.screwdriver"
        case .shippingReceiving: return "shippingbox"
        case .accounting: return "doc.text"
        case .emergency: return "exclamationmark.triangle"
        case .general: return "person"
        case .other: return "ellipsis.circle"
        }
    }
}

@Model
final class VendorContact {
    var id: UUID = UUID()
    var name: String = ""
    var title: String = ""
    var roleRaw: String = VendorContactRole.general.rawValue
    var phone: String = ""
    var cellPhone: String = ""
    var email: String = ""
    var notes: String = ""
    var isPrimary: Bool = false
    var isActive: Bool = true
    var createdAt: Date = Date.now

    // Relationship back to vendor
    @Relationship var vendor: Vendor?

    init(name: String = "",
         title: String = "",
         role: VendorContactRole = .general,
         phone: String = "",
         email: String = "") {
        self.name = name
        self.title = title
        self.roleRaw = role.rawValue
        self.phone = phone
        self.email = email
    }

    var role: VendorContactRole {
        get { VendorContactRole(rawValue: roleRaw) ?? .general }
        set { roleRaw = newValue.rawValue }
    }

    var displayName: String {
        if title.isEmpty {
            return name
        }
        return "\(name) (\(title))"
    }

    var hasPhone: Bool {
        !phone.isEmpty || !cellPhone.isEmpty
    }

    var primaryPhone: String {
        cellPhone.isEmpty ? phone : cellPhone
    }
}
