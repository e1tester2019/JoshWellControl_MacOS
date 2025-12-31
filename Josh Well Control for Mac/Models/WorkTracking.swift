//
//  WorkTracking.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-08.
//

import Foundation
import SwiftData

// MARK: - Client

@Model
final class Client {
    var id: UUID = UUID()
    var companyName: String = ""
    var contactName: String = ""
    var contactTitle: String = ""
    var address: String = ""
    var city: String = ""
    var province: String = ""
    var postalCode: String = ""

    // Rates
    var dayRate: Double = 1625.00
    var mileageRate: Double = 1.15
    var maxMileage: Double = 750.0

    // Default cost code for this client
    var defaultCostCode: String = ""

    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \WorkDay.client) var workDays: [WorkDay]?
    @Relationship(deleteRule: .nullify, inverse: \Invoice.client) var invoices: [Invoice]?
    @Relationship(deleteRule: .nullify, inverse: \Expense.client) var expenses: [Expense]?
    @Relationship(deleteRule: .nullify, inverse: \MileageLog.client) var mileageLogs: [MileageLog]?

    init(companyName: String = "", contactName: String = "", dayRate: Double = 1625.00, mileageRate: Double = 1.15) {
        self.companyName = companyName
        self.contactName = contactName
        self.dayRate = dayRate
        self.mileageRate = mileageRate
    }

    var fullAddress: String {
        var parts: [String] = []
        if !address.isEmpty { parts.append(address) }
        var cityLine: [String] = []
        if !city.isEmpty { cityLine.append(city) }
        if !province.isEmpty { cityLine.append(province) }
        if !cityLine.isEmpty { parts.append(cityLine.joined(separator: ", ")) }
        if !postalCode.isEmpty { parts.append(postalCode) }
        return parts.joined(separator: "\n")
    }
}

// MARK: - WorkDay

@Model
final class WorkDay {
    var id: UUID = UUID()
    var startDate: Date = Date.now
    var endDate: Date = Date.now
    var notes: String = ""

    // Override rates for this specific day (nil = use client defaults)
    var dayRateOverride: Double?

    // Mileage driven this work period (km)
    var mileage: Double = 0
    var mileageDescription: String = ""

    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify) var well: Well?
    @Relationship(deleteRule: .nullify) var client: Client?
    @Relationship(deleteRule: .nullify, inverse: \InvoiceLineItem.workDays) var lineItem: InvoiceLineItem?

    // Custom rig name and cost code per work day (overrides well defaults)
    var rigNameOverride: String?
    var costCodeOverride: String?

    // Manual invoiced flag (for marking as invoiced without an actual invoice line item link)
    var manuallyMarkedInvoiced: Bool = false
    var manuallyMarkedPaid: Bool = false
    var manualPaidDate: Date?

    init(startDate: Date = Date.now, endDate: Date = Date.now, well: Well? = nil, client: Client? = nil) {
        self.startDate = startDate
        self.endDate = endDate
        self.well = well
        self.client = client
    }

    /// Number of days in this work period (inclusive)
    var dayCount: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        let components = calendar.dateComponents([.day], from: start, to: end)
        return (components.day ?? 0) + 1 // +1 because inclusive
    }

    var effectiveDayRate: Double {
        dayRateOverride ?? client?.dayRate ?? 1625.00
    }

    var effectiveRigName: String {
        rigNameOverride ?? well?.rigName ?? ""
    }

    var effectiveCostCode: String {
        costCodeOverride ?? well?.costCode ?? client?.defaultCostCode ?? ""
    }

    /// Total earnings for this work period
    var totalEarnings: Double {
        Double(dayCount) * effectiveDayRate
    }

    /// Date range display string (day first format)
    var dateRangeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        if Calendar.current.isDate(startDate, inSameDayAs: endDate) {
            return formatter.string(from: startDate)
        } else {
            return "\(formatter.string(from: startDate)) – \(formatter.string(from: endDate))"
        }
    }

    /// Whether this work day has been invoiced (via line item link OR manual flag)
    var isInvoiced: Bool {
        lineItem != nil || manuallyMarkedInvoiced
    }

    /// Whether this work day has been paid (invoice marked as paid OR manual flag)
    var isPaid: Bool {
        (lineItem?.invoice?.isPaid ?? false) || manuallyMarkedPaid
    }

    /// Date the invoice was paid
    var paidDate: Date? {
        lineItem?.invoice?.paidDate ?? manualPaidDate
    }

    /// Whether this work day was marked manually (not via invoice system)
    var isManuallyMarked: Bool {
        manuallyMarkedInvoiced || manuallyMarkedPaid
    }
}

// MARK: - Invoice

@Model
final class Invoice {
    var id: UUID = UUID()
    var invoiceNumber: Int = 1000
    var date: Date = Date.now
    var terms: String = "15 Days"
    var serviceDescription: String = "Drilling Supervision"

    // Mileage
    var mileageToLocation: Double = 0
    var mileageFromLocation: Double = 0

    // Status
    var isPaid: Bool = false
    var paidDate: Date?

    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    @Relationship(deleteRule: .nullify) var client: Client?
    @Relationship(deleteRule: .cascade, inverse: \InvoiceLineItem.invoice) var lineItems: [InvoiceLineItem]?

    init(invoiceNumber: Int = 1000, client: Client? = nil) {
        self.invoiceNumber = invoiceNumber
        self.client = client
    }

    // Computed totals
    var dayRateSubtotal: Double {
        (lineItems ?? []).filter { $0.itemType == .dayRate }.reduce(0) { $0 + $1.total }
    }

    var mileageSubtotal: Double {
        (lineItems ?? []).filter { $0.itemType == .mileage }.reduce(0) { $0 + $1.total }
    }

    var subtotal: Double {
        (lineItems ?? []).reduce(0) { $0 + $1.total }
    }

    var gstAmount: Double {
        subtotal * 0.05
    }

    var total: Double {
        subtotal + gstAmount
    }

    var totalDays: Int {
        (lineItems ?? []).filter { $0.itemType == .dayRate }.reduce(0) { $0 + $1.quantity }
    }
}

// MARK: - InvoiceLineItem

@Model
final class InvoiceLineItem {
    var id: UUID = UUID()

    enum ItemType: String, Codable {
        case dayRate = "dayRate"
        case mileage = "mileage"
    }

    var itemTypeRaw: String = ItemType.dayRate.rawValue
    var itemType: ItemType {
        get { ItemType(rawValue: itemTypeRaw) ?? .dayRate }
        set { itemTypeRaw = newValue.rawValue }
    }

    var quantity: Int = 1
    var unitPrice: Double = 0
    var sortOrder: Int = 0

    // Well/job info for this line item
    var wellName: String = ""
    var afeNumber: String = ""
    var rigName: String = ""
    var costCode: String = ""

    // For mileage items
    var mileageDescription: String = ""

    @Relationship(deleteRule: .nullify) var invoice: Invoice?
    @Relationship(deleteRule: .nullify) var workDays: [WorkDay]?
    @Relationship(deleteRule: .nullify) var well: Well?

    init(itemType: ItemType = .dayRate, quantity: Int = 1, unitPrice: Double = 0) {
        self.itemTypeRaw = itemType.rawValue
        self.quantity = quantity
        self.unitPrice = unitPrice
    }

    var total: Double {
        Double(quantity) * unitPrice
    }

    var descriptionText: String {
        switch itemType {
        case .dayRate:
            return "Drilling Supervisor Day Rate"
        case .mileage:
            if mileageDescription.isEmpty {
                return "Mileage"
            } else {
                return "Mileage - \(mileageDescription)"
            }
        }
    }
}

// MARK: - BusinessInfo (Singleton stored in UserDefaults)

struct BusinessInfo: Codable {
    var companyName: String = "2729772 ALBERTA INC."
    var phone: String = "587-877-9320"
    var email: String = "joshsallows@gmail.com"
    var address: String = "41 Drake Landing Loop"
    var city: String = "Okotoks"
    var province: String = "Alberta"
    var postalCode: String = "T1S0H2"
    var gstNumber: String = "74804 0169 RT0001"

    // Next invoice number tracking
    var nextInvoiceNumber: Int = 1005

    static var shared: BusinessInfo {
        get {
            if let data = UserDefaults.standard.data(forKey: "BusinessInfo"),
               let info = try? JSONDecoder().decode(BusinessInfo.self, from: data) {
                return info
            }
            return BusinessInfo()
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "BusinessInfo")
            }
        }
    }

    var fullAddress: String {
        "\(address)\n\(city), \(province)\n\(postalCode)"
    }

    mutating func getNextInvoiceNumber() -> Int {
        let num = nextInvoiceNumber
        nextInvoiceNumber += 1
        BusinessInfo.shared = self
        return num
    }
}

// MARK: - Work Tracking PIN (stored securely)

struct WorkTrackingAuth {
    private static let pinKey = "WorkTrackingPIN"

    static var hasPin: Bool {
        UserDefaults.standard.string(forKey: pinKey) != nil
    }

    static func setPin(_ pin: String) {
        UserDefaults.standard.set(pin, forKey: pinKey)
    }

    static func verifyPin(_ pin: String) -> Bool {
        guard let storedPin = UserDefaults.standard.string(forKey: pinKey) else {
            return true // No pin set, allow access
        }
        return pin == storedPin
    }

    static func clearPin() {
        UserDefaults.standard.removeObject(forKey: pinKey)
    }
}
