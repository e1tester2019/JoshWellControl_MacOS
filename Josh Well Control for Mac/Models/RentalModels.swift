import Foundation
import SwiftData
import SwiftUI

/// Status of a rental item during its use on a well
enum RentalItemStatus: String, Codable, CaseIterable {
    case notRun = "Not Run"
    case working = "Working"
    case issues = "Issues"
    case failed = "Failed"

    var icon: String {
        switch self {
        case .notRun: return "circle.dashed"
        case .working: return "checkmark.circle.fill"
        case .issues: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .notRun: return .secondary
        case .working: return .green
        case .issues: return .orange
        case .failed: return .red
        }
    }
}

/// An additional one-off cost associated with a rental item (e.g., delivery, pickup, damage, etc.).
@Model
final class RentalAdditionalCost {
    var id: UUID = UUID()
    var descriptionText: String = ""
    var amount: Double = 0.0
    var date: Date?

    // Relationship back to rental item (inverse declared on parent side only)
    var rentalItem: RentalItem?

    init(descriptionText: String = "", amount: Double = 0, date: Date? = nil) {
        self.descriptionText = descriptionText
        self.amount = amount
        self.date = date
    }
}

/// Represents a rented tool/equipment for a well, tracking usage days and costs.
@Model
final class RentalItem {
    var id: UUID = UUID()
    var name: String = "Rental"
    var detail: String?
    var serialNumber: String?
    var used: Bool = false
    var statusRaw: String = RentalItemStatus.notRun.rawValue
    var issueNotes: String = ""  // Specific issues during this rental period

    /// Optional quick-entry window; if `usageDates` is empty, `totalDays` falls back to inclusive days between start and end.
    var startDate: Date?
    var endDate: Date?

    /// Canonical record of actual usage stored as JSON-encoded Data (CloudKit doesn't support [Date] arrays).
    var usageDatesData: Data?

    var onLocation: Bool = false
    var invoiced: Bool = false
    var transferredAt: Date?  // When this rental was transferred to this well

    var costPerDay: Double = 0.0

    @Relationship(deleteRule: .cascade, inverse: \RentalAdditionalCost.rentalItem) var additionalCosts: [RentalAdditionalCost]?

    /// Parent relationship — the Well owns its rentals.
    @Relationship var well: Well?

    /// Link to equipment registry (optional - for tracking across wells)
    @Relationship var equipment: RentalEquipment?

    /// Reference to the rental this was transferred from (for history tracking)
    @Relationship var transferredFrom: RentalItem?

    /// Rentals that were transferred from this one
    @Relationship(deleteRule: .nullify, inverse: \RentalItem.transferredFrom) var transferredTo: [RentalItem]?

    // MARK: - Computed Accessor for usageDates

    /// Access usage dates as [Date] array (stored as JSON-encoded Data for CloudKit compatibility)
    var usageDates: [Date] {
        get {
            guard let data = usageDatesData else { return [] }
            return (try? JSONDecoder().decode([Date].self, from: data)) ?? []
        }
        set {
            usageDatesData = try? JSONEncoder().encode(newValue)
        }
    }

    var status: RentalItemStatus {
        get { RentalItemStatus(rawValue: statusRaw) ?? .notRun }
        set {
            statusRaw = newValue.rawValue
            // Sync used flag with status
            used = (newValue != .notRun)
        }
    }

    init(
        name: String = "Rental",
        detail: String? = nil,
        serialNumber: String? = nil,
        used: Bool = false,
        status: RentalItemStatus = .notRun,
        startDate: Date? = nil,
        endDate: Date? = nil,
        usageDates: [Date] = [],
        onLocation: Bool = false,
        invoiced: Bool = false,
        costPerDay: Double = 0,
        well: Well? = nil,
        equipment: RentalEquipment? = nil
    ) {
        self.name = name
        self.detail = detail
        self.serialNumber = serialNumber
        self.statusRaw = status.rawValue
        let norm = usageDates.map { Calendar.current.startOfDay(for: $0) }
        self.usageDates = Array(Set(norm)).sorted()
        self.used = used || (status != .notRun)
        self.startDate = startDate
        self.endDate = endDate
        self.onLocation = onLocation
        self.invoiced = invoiced
        self.costPerDay = costPerDay
        self.well = well
        self.equipment = equipment
    }

    /// Number of billable days. Returns 0 if not marked as used. Otherwise, if specific usage days are provided, use that count; otherwise, inclusive days between start and end.
    var totalDays: Int {
        // If not marked as used/run, return 0 days
        if !used { return 0 }
        if !usageDates.isEmpty { return usageDates.count }
        guard let s = startDate, let e = endDate else { return 0 }
        let cal = Calendar.current
        let start = cal.startOfDay(for: s)
        let end = cal.startOfDay(for: e)
        let comps = cal.dateComponents([.day], from: start, to: end)
        let d = (comps.day ?? 0)
        return max(d + 1, 0)
    }

    /// Sum of all additional one-off costs.
    var additionalCostsTotal: Double { (additionalCosts ?? []).reduce(0) { $0 + $1.amount } }

    /// Total cost = (days * costPerDay) + sum(additional costs)
    var totalCost: Double { (Double(totalDays) * max(costPerDay, 0)) + additionalCostsTotal }

    /// Toggle a date in `usageDates` (normalized to start-of-day).
    func toggleUsage(on date: Date) {
        let d = Calendar.current.startOfDay(for: date)
        var dates = usageDates
        if let idx = dates.firstIndex(of: d) {
            dates.remove(at: idx)
        } else {
            dates.append(d)
        }
        usageDates = Array(Set(dates)).sorted()
    }

    // MARK: - Transfer Support

    /// Create a transfer copy of this rental for a new well
    func createTransferCopy(to destinationWell: Well) -> RentalItem {
        let copy = RentalItem(
            name: name,
            detail: detail,
            serialNumber: serialNumber,
            used: false,
            status: .notRun,
            startDate: Date(),
            endDate: Date(),
            usageDates: [],
            onLocation: true,
            invoiced: false,
            costPerDay: costPerDay,
            well: destinationWell,
            equipment: equipment
        )
        copy.transferredFrom = self
        copy.transferredAt = Date()
        return copy
    }

    /// Whether this rental was transferred from another well
    var wasTransferred: Bool {
        transferredFrom != nil
    }

    /// Source well name (if transferred)
    var transferredFromWellName: String? {
        transferredFrom?.well?.name
    }

    /// Has this rental been transferred to other wells?
    var hasBeenTransferred: Bool {
        !(transferredTo ?? []).isEmpty
    }

    /// Display name including equipment info if linked
    var displayName: String {
        if let eq = equipment {
            return eq.displayName
        }
        if let sn = serialNumber, !sn.isEmpty {
            return "\(name) (\(sn))"
        }
        return name
    }

    /// Category from linked equipment
    var category: RentalCategory? {
        equipment?.category
    }

    /// Vendor from linked equipment
    var vendor: Vendor? {
        equipment?.vendor
    }
}

