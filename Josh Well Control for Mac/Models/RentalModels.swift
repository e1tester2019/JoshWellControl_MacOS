import Foundation
import SwiftData

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

    /// Optional quick-entry window; if `usageDates` is empty, `totalDays` falls back to inclusive days between start and end.
    var startDate: Date?
    var endDate: Date?

    /// Canonical record of actual usage. Use this when the tool is not used on every day in the interval.
    var usageDates: [Date] = []

    var onLocation: Bool = false
    var invoiced: Bool = false

    var costPerDay: Double = 0.0

    @Relationship(deleteRule: .cascade, inverse: \RentalAdditionalCost.rentalItem) var additionalCosts: [RentalAdditionalCost]?

    /// Parent relationship — the Well owns its rentals.
    @Relationship var well: Well?

    init(
        name: String = "Rental",
        detail: String? = nil,
        serialNumber: String? = nil,
        used: Bool = false,
        startDate: Date? = nil,
        endDate: Date? = nil,
        usageDates: [Date] = [],
        onLocation: Bool = false,
        invoiced: Bool = false,
        costPerDay: Double = 0,
        well: Well? = nil
    ) {
        self.name = name
        self.detail = detail
        self.serialNumber = serialNumber
        let norm = usageDates.map { Calendar.current.startOfDay(for: $0) }
        self.usageDates = Array(Set(norm)).sorted()
        self.used = used
        self.startDate = startDate
        self.endDate = endDate
        self.onLocation = onLocation
        self.invoiced = invoiced
        self.costPerDay = costPerDay
        self.well = well
    }

    /// Number of billable days. If specific usage days are provided, use that count; otherwise, inclusive days between start and end.
    var totalDays: Int {
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
        if let idx = usageDates.firstIndex(of: d) {
            usageDates.remove(at: idx)
        } else {
            usageDates.append(d)
            usageDates = Array(Set(usageDates)).sorted()
        }
    }
}

