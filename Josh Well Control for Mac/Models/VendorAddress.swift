//
//  VendorAddress.swift
//  Josh Well Control for Mac
//
//  Physical address for a vendor (shop, warehouse, office, etc.)
//

import Foundation
import SwiftData

enum VendorAddressType: String, Codable, CaseIterable {
    case shop = "Shop"
    case warehouse = "Warehouse"
    case office = "Office"
    case shipping = "Shipping"
    case billing = "Billing"
    case other = "Other"

    var icon: String {
        switch self {
        case .shop: return "wrench.and.screwdriver"
        case .warehouse: return "building.2"
        case .office: return "building"
        case .shipping: return "shippingbox"
        case .billing: return "doc.text"
        case .other: return "mappin"
        }
    }
}

@Model
final class VendorAddress {
    var id: UUID = UUID()
    var label: String = ""  // e.g., "Edmonton Shop", "Calgary Warehouse"
    var addressTypeRaw: String = VendorAddressType.shop.rawValue
    var streetAddress: String = ""
    var streetAddress2: String = ""
    var city: String = ""
    var province: String = ""
    var postalCode: String = ""
    var country: String = "Canada"
    var phone: String = ""
    var fax: String = ""
    var notes: String = ""
    var isPrimary: Bool = false
    var isActive: Bool = true
    var createdAt: Date = Date.now

    // Relationship back to vendor
    @Relationship var vendor: Vendor?

    init(label: String = "",
         addressType: VendorAddressType = .shop,
         streetAddress: String = "",
         city: String = "",
         province: String = "") {
        self.label = label
        self.addressTypeRaw = addressType.rawValue
        self.streetAddress = streetAddress
        self.city = city
        self.province = province
    }

    var addressType: VendorAddressType {
        get { VendorAddressType(rawValue: addressTypeRaw) ?? .shop }
        set { addressTypeRaw = newValue.rawValue }
    }

    /// Formatted single-line address
    var formattedAddress: String {
        var parts: [String] = []
        if !streetAddress.isEmpty { parts.append(streetAddress) }
        if !streetAddress2.isEmpty { parts.append(streetAddress2) }
        if !city.isEmpty { parts.append(city) }
        if !province.isEmpty { parts.append(province) }
        if !postalCode.isEmpty { parts.append(postalCode) }
        return parts.joined(separator: ", ")
    }

    /// Formatted multi-line address for display
    var formattedAddressMultiLine: String {
        var lines: [String] = []
        if !streetAddress.isEmpty { lines.append(streetAddress) }
        if !streetAddress2.isEmpty { lines.append(streetAddress2) }
        var cityLine = ""
        if !city.isEmpty { cityLine += city }
        if !province.isEmpty { cityLine += cityLine.isEmpty ? province : ", \(province)" }
        if !postalCode.isEmpty { cityLine += cityLine.isEmpty ? postalCode : " \(postalCode)" }
        if !cityLine.isEmpty { lines.append(cityLine) }
        if !country.isEmpty && country != "Canada" { lines.append(country) }
        return lines.joined(separator: "\n")
    }

    var displayLabel: String {
        if label.isEmpty {
            return "\(addressType.rawValue) - \(city)"
        }
        return label
    }
}
