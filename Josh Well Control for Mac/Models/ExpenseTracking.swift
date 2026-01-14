//
//  ExpenseTracking.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-08.
//

import Foundation
import SwiftData

// MARK: - Province

enum Province: String, Codable, CaseIterable {
    case alberta = "Alberta"
    case bc = "British Columbia"

    var gstRate: Double { 0.05 } // 5% GST across Canada

    var pstRate: Double {
        switch self {
        case .alberta: return 0.0 // No PST in Alberta
        case .bc: return 0.07 // 7% PST in BC
        }
    }

    var totalTaxRate: Double {
        gstRate + pstRate
    }

    var shortName: String {
        switch self {
        case .alberta: return "AB"
        case .bc: return "BC"
        }
    }
}

// MARK: - Expense Category

enum ExpenseCategory: String, Codable, CaseIterable {
    case fuel = "Fuel"
    case meals = "Meals & Entertainment"
    case lodging = "Lodging"
    case vehicleMaintenance = "Vehicle Maintenance"
    case toolsEquipment = "Tools & Equipment"
    case officeSupplies = "Office Supplies"
    case phone = "Phone/Communications"
    case professionalServices = "Professional Services"
    case insurance = "Insurance"
    case travel = "Travel"
    case clothing = "Work Clothing/PPE"
    case training = "Training/Certification"
    case subscriptions = "Subscriptions/Software"
    case other = "Other"

    var icon: String {
        switch self {
        case .fuel: return "fuelpump.fill"
        case .meals: return "fork.knife"
        case .lodging: return "bed.double.fill"
        case .vehicleMaintenance: return "wrench.and.screwdriver.fill"
        case .toolsEquipment: return "hammer.fill"
        case .officeSupplies: return "pencil.and.ruler.fill"
        case .phone: return "phone.fill"
        case .professionalServices: return "briefcase.fill"
        case .insurance: return "shield.fill"
        case .travel: return "airplane"
        case .clothing: return "tshirt.fill"
        case .training: return "graduationcap.fill"
        case .subscriptions: return "app.badge.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

// MARK: - Payment Method

enum PaymentMethod: String, Codable, CaseIterable {
    case cash = "Cash"
    case debit = "Debit"
    case creditCard = "Credit Card"
    case companyCard = "Company Card"
    case etransfer = "E-Transfer"
    case other = "Other"
}

// MARK: - Trip Tracking Mode

enum TripTrackingMode: String, Codable, CaseIterable {
    case manual = "Manual"
    case pointToPoint = "Point-to-Point"
    case activeTracking = "Active Tracking"
    case routeBased = "Route-Based"
}

// MARK: - Expense

@Model
final class Expense {
    var id: UUID = UUID()
    var date: Date = Date.now
    var amount: Double = 0 // Pre-tax amount
    var vendor: String = ""
    var expenseDescription: String = ""

    // Category stored as raw value for SwiftData compatibility
    var categoryRaw: String = ExpenseCategory.other.rawValue
    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    // Province for tax calculation
    var provinceRaw: String = Province.alberta.rawValue
    var province: Province {
        get { Province(rawValue: provinceRaw) ?? .alberta }
        set { provinceRaw = newValue.rawValue }
    }

    // Payment method
    var paymentMethodRaw: String = PaymentMethod.creditCard.rawValue
    var paymentMethod: PaymentMethod {
        get { PaymentMethod(rawValue: paymentMethodRaw) ?? .creditCard }
        set { paymentMethodRaw = newValue.rawValue }
    }

    // Tax amounts (can be manually overridden)
    var gstAmount: Double = 0
    var pstAmount: Double = 0
    var taxIncludedInAmount: Bool = true // If true, amount includes tax

    // Receipt image - stored externally for performance
    @Attribute(.externalStorage) var receiptImageData: Data?
    @Attribute(.externalStorage) var receiptThumbnailData: Data?
    var receiptFileName: String?
    var receiptIsPDF: Bool = false
    var hasReceiptAttached: Bool = false  // Lightweight flag to avoid loading image data

    // OCR-extracted fields (iOS receipt scanning)
    var ocrVendor: String?
    var ocrDate: Date?
    var ocrTotalAmount: Double?
    var ocrSubtotal: Double?
    var ocrGSTAmount: Double?
    var ocrPSTAmount: Double?
    var ocrSuggestedCategoryRaw: String?
    var ocrSuggestedCategory: ExpenseCategory? {
        get {
            guard let raw = ocrSuggestedCategoryRaw else { return nil }
            return ExpenseCategory(rawValue: raw)
        }
        set { ocrSuggestedCategoryRaw = newValue?.rawValue }
    }
    var wasOCRProcessed: Bool = false
    var ocrConfidence: Double?

    // Reimbursement tracking
    var isReimbursable: Bool = false
    var isReimbursed: Bool = false
    var reimbursedDate: Date?

    // Optional links
    @Relationship(deleteRule: .nullify) var client: Client?
    @Relationship(deleteRule: .nullify) var well: Well?

    var notes: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(date: Date = Date.now, amount: Double = 0, category: ExpenseCategory = .other) {
        self.date = date
        self.amount = amount
        self.categoryRaw = category.rawValue
    }

    // Computed properties
    var totalAmount: Double {
        if taxIncludedInAmount {
            return amount
        } else {
            return amount + gstAmount + pstAmount
        }
    }

    var preTaxAmount: Double {
        if taxIncludedInAmount {
            // Back-calculate pre-tax from total
            return amount / (1 + province.totalTaxRate)
        } else {
            return amount
        }
    }

    var calculatedGST: Double {
        preTaxAmount * province.gstRate
    }

    var calculatedPST: Double {
        preTaxAmount * province.pstRate
    }

    /// Auto-calculate taxes based on province
    func calculateTaxes() {
        gstAmount = calculatedGST
        pstAmount = calculatedPST
    }

    var hasReceipt: Bool {
        hasReceiptAttached
    }

    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Mileage Log (for CRA tracking)

@Model
final class MileageLog {
    var id: UUID = UUID()
    var date: Date = Date.now
    var startLocation: String = ""
    var endLocation: String = ""
    var distance: Double = 0 // kilometers
    var purpose: String = ""
    var isRoundTrip: Bool = false

    // CRA mileage rates by tax year
    // Format: year -> (firstTierRate, secondTierRate, firstTierLimit)
    // Add new years as CRA announces rates
    static let ratesByYear: [Int: (firstTier: Double, secondTier: Double, limit: Double)] = [
        2024: (0.70, 0.64, 5000),
        2025: (0.72, 0.66, 5000),
    ]

    /// Get rates for a specific year, falling back to most recent known year
    static func rates(for year: Int) -> (firstTier: Double, secondTier: Double, limit: Double) {
        if let rates = ratesByYear[year] {
            return rates
        }
        // Fall back to most recent known year
        let sortedYears = ratesByYear.keys.sorted()
        if let mostRecent = sortedYears.last(where: { $0 <= year }) ?? sortedYears.last {
            return ratesByYear[mostRecent]!
        }
        return (0.72, 0.66, 5000) // Ultimate fallback
    }

    /// Convenience for current year rates
    static var firstTierRate: Double {
        rates(for: Calendar.current.component(.year, from: Date())).firstTier
    }

    static var secondTierRate: Double {
        rates(for: Calendar.current.component(.year, from: Date())).secondTier
    }

    static var firstTierLimit: Double {
        rates(for: Calendar.current.component(.year, from: Date())).limit
    }

    // GPS Coordinates (iOS tracking)
    var startLatitude: Double?
    var startLongitude: Double?
    var endLatitude: Double?
    var endLongitude: Double?

    // Trip timing (for active tracking)
    var tripStartTime: Date?
    var tripEndTime: Date?
    var duration: TimeInterval? // seconds

    // Tracking mode
    var trackingModeRaw: String = TripTrackingMode.manual.rawValue
    var trackingMode: TripTrackingMode {
        get { TripTrackingMode(rawValue: trackingModeRaw) ?? .manual }
        set { trackingModeRaw = newValue.rawValue }
    }

    // Route points for active tracking
    @Relationship(deleteRule: .cascade) var routePoints: [TripRoutePoint]?

    // Map snapshot for PDF export
    @Attribute(.externalStorage) var mapSnapshotData: Data?

    // Route-based tracking fields
    var wasRouteCalculated: Bool = false
    var calculatedDistance: Double?  // km from MKDirections (may differ from distance field)
    var expectedTravelTime: TimeInterval?

    // Destination info (for route-based trips)
    var destinationName: String?
    var destinationLatitude: Double?
    var destinationLongitude: Double?
    var destinationSourceRaw: String?  // Encoded DestinationSource

    // Optional links
    @Relationship(deleteRule: .nullify) var client: Client?
    @Relationship(deleteRule: .nullify) var well: Well?

    var notes: String = ""
    var createdAt: Date = Date.now

    init(date: Date = Date.now, distance: Double = 0) {
        self.date = date
        self.distance = distance
    }

    var effectiveDistance: Double {
        isRoundTrip ? distance * 2 : distance
    }

    var hasGPSData: Bool {
        startLatitude != nil && startLongitude != nil &&
        endLatitude != nil && endLongitude != nil
    }

    var hasRoute: Bool {
        guard let points = routePoints else { return false }
        return !points.isEmpty
    }

    var formattedDuration: String? {
        guard let duration = duration else { return nil }
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes) min"
        }
    }

    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    var locationString: String {
        if startLocation.isEmpty && endLocation.isEmpty {
            return ""
        } else if startLocation.isEmpty {
            return endLocation
        } else if endLocation.isEmpty {
            return startLocation
        } else {
            return "\(startLocation) → \(endLocation)"
        }
    }
}

// MARK: - Trip Route Point (for GPS tracking)

@Model
final class TripRoutePoint {
    var id: UUID = UUID()
    var latitude: Double = 0
    var longitude: Double = 0
    var altitude: Double?
    var timestamp: Date = Date.now
    var speed: Double? // m/s
    var course: Double? // degrees

    @Relationship(inverse: \MileageLog.routePoints)
    var mileageLog: MileageLog?

    init(latitude: Double, longitude: Double, timestamp: Date = Date.now) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
    }
}

// MARK: - Expense Summary (for reports)

struct ExpenseSummary {
    let category: ExpenseCategory
    let count: Int
    let totalAmount: Double
    let totalGST: Double
    let totalPST: Double
}

struct MileageSummary {
    let totalKilometers: Double
    let totalTrips: Int
    let estimatedDeduction: Double

    /// Calculate CRA deduction based on tiered rates for a specific tax year
    /// - Parameters:
    ///   - totalKm: Total kilometers to calculate deduction for
    ///   - yearToDateKm: Kilometers already driven this year (for tier calculation)
    ///   - year: Tax year to use for rates (defaults to current year)
    static func calculateDeduction(totalKm: Double, yearToDateKm: Double = 0, year: Int? = nil) -> Double {
        let taxYear = year ?? Calendar.current.component(.year, from: Date())
        let rates = MileageLog.rates(for: taxYear)

        let remainingFirstTier = max(0, rates.limit - yearToDateKm)
        let kmAtFirstRate = min(totalKm, remainingFirstTier)
        let kmAtSecondRate = max(0, totalKm - kmAtFirstRate)

        return (kmAtFirstRate * rates.firstTier) + (kmAtSecondRate * rates.secondTier)
    }
}
