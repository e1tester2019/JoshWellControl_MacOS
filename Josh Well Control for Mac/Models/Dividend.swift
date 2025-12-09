//
//  Dividend.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-08.
//

import Foundation
import SwiftData

// MARK: - Dividend Type

enum DividendType: String, Codable, CaseIterable {
    case eligible = "Eligible"
    case nonEligible = "Non-Eligible (Other Than Eligible)"

    /// Gross-up percentage for tax purposes (2024 rates)
    var grossUpRate: Double {
        switch self {
        case .eligible: return 0.38 // 38% gross-up
        case .nonEligible: return 0.15 // 15% gross-up
        }
    }

    /// Federal dividend tax credit rate
    var federalTaxCreditRate: Double {
        switch self {
        case .eligible: return 0.150198 // 15.0198% of grossed-up amount
        case .nonEligible: return 0.090301 // 9.0301% of grossed-up amount
        }
    }

    var shortName: String {
        switch self {
        case .eligible: return "Eligible"
        case .nonEligible: return "Non-Eligible"
        }
    }
}

// MARK: - Shareholder

@Model
final class Shareholder {
    var id: UUID = UUID()
    var firstName: String = ""
    var lastName: String = ""
    var address: String = ""
    var city: String = ""
    var provinceRaw: String = Province.alberta.rawValue
    var province: Province {
        get { Province(rawValue: provinceRaw) ?? .alberta }
        set { provinceRaw = newValue.rawValue }
    }
    var postalCode: String = ""
    var sinNumber: String = "" // For T5 slips
    var ownershipPercent: Double = 100.0 // Percentage of shares owned
    var isActive: Bool = true

    var notes: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \Dividend.shareholder) var dividends: [Dividend]?

    init(firstName: String = "", lastName: String = "") {
        self.firstName = firstName
        self.lastName = lastName
    }

    var fullName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }

    var fullAddress: String {
        var parts: [String] = []
        if !address.isEmpty { parts.append(address) }
        var cityLine: [String] = []
        if !city.isEmpty { cityLine.append(city) }
        if !province.rawValue.isEmpty { cityLine.append(province.shortName) }
        if !cityLine.isEmpty { parts.append(cityLine.joined(separator: ", ")) }
        if !postalCode.isEmpty { parts.append(postalCode) }
        return parts.joined(separator: "\n")
    }

    /// Total dividends paid to this shareholder for a given year
    func totalDividends(for year: Int) -> Double {
        (dividends ?? [])
            .filter { Calendar.current.component(.year, from: $0.paymentDate) == year && $0.isPaid }
            .reduce(0) { $0 + $1.amount }
    }

    /// Total eligible dividends for a given year
    func eligibleDividends(for year: Int) -> Double {
        (dividends ?? [])
            .filter { Calendar.current.component(.year, from: $0.paymentDate) == year && $0.isPaid && $0.dividendType == .eligible }
            .reduce(0) { $0 + $1.amount }
    }

    /// Total non-eligible dividends for a given year
    func nonEligibleDividends(for year: Int) -> Double {
        (dividends ?? [])
            .filter { Calendar.current.component(.year, from: $0.paymentDate) == year && $0.isPaid && $0.dividendType == .nonEligible }
            .reduce(0) { $0 + $1.amount }
    }
}

// MARK: - Dividend

@Model
final class Dividend {
    var id: UUID = UUID()
    var amount: Double = 0
    var dividendTypeRaw: String = DividendType.nonEligible.rawValue
    var dividendType: DividendType {
        get { DividendType(rawValue: dividendTypeRaw) ?? .nonEligible }
        set { dividendTypeRaw = newValue.rawValue }
    }

    var declarationDate: Date = Date.now // Date dividend was declared by directors
    var recordDate: Date = Date.now // Date to determine eligible shareholders
    var paymentDate: Date = Date.now // Date dividend is/was paid

    var isPaid: Bool = false
    var paidDate: Date?

    var resolution: String = "" // Board resolution reference
    var notes: String = ""

    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    @Relationship(deleteRule: .nullify) var shareholder: Shareholder?

    init(amount: Double = 0, shareholder: Shareholder? = nil) {
        self.amount = amount
        self.shareholder = shareholder
    }

    /// Grossed-up amount for tax purposes
    var grossedUpAmount: Double {
        amount * (1 + dividendType.grossUpRate)
    }

    /// Federal dividend tax credit
    var federalTaxCredit: Double {
        grossedUpAmount * dividendType.federalTaxCreditRate
    }

    /// Quarter this dividend falls in (1-4)
    var quarter: Int {
        let month = Calendar.current.component(.month, from: paymentDate)
        return ((month - 1) / 3) + 1
    }

    /// Year of payment
    var year: Int {
        Calendar.current.component(.year, from: paymentDate)
    }

    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: paymentDate)
    }

    var quarterString: String {
        "Q\(quarter) \(year)"
    }
}

// MARK: - Dividend Summary

struct DividendQuarterlySummary {
    let year: Int
    let quarter: Int
    let shareholder: Shareholder
    let eligibleAmount: Double
    let nonEligibleAmount: Double
    let totalAmount: Double
    let dividendCount: Int

    var quarterString: String {
        "Q\(quarter) \(year)"
    }

    var periodStart: Date {
        var components = DateComponents()
        components.year = year
        components.month = ((quarter - 1) * 3) + 1
        components.day = 1
        return Calendar.current.date(from: components) ?? Date.now
    }

    var periodEnd: Date {
        var components = DateComponents()
        components.year = year
        components.month = quarter * 3
        components.day = 1
        let firstOfLastMonth = Calendar.current.date(from: components) ?? Date.now
        return Calendar.current.date(byAdding: DateComponents(month: 1, day: -1), to: firstOfLastMonth) ?? Date.now
    }

    var grossedUpEligible: Double {
        eligibleAmount * (1 + DividendType.eligible.grossUpRate)
    }

    var grossedUpNonEligible: Double {
        nonEligibleAmount * (1 + DividendType.nonEligible.grossUpRate)
    }

    var totalGrossedUp: Double {
        grossedUpEligible + grossedUpNonEligible
    }
}

struct DividendYearlySummary {
    let year: Int
    let shareholder: Shareholder
    let eligibleAmount: Double
    let nonEligibleAmount: Double
    let totalAmount: Double
    let dividendCount: Int
    let quarterlyBreakdown: [DividendQuarterlySummary]

    var grossedUpEligible: Double {
        eligibleAmount * (1 + DividendType.eligible.grossUpRate)
    }

    var grossedUpNonEligible: Double {
        nonEligibleAmount * (1 + DividendType.nonEligible.grossUpRate)
    }

    var totalGrossedUp: Double {
        grossedUpEligible + grossedUpNonEligible
    }

    var federalTaxCreditEligible: Double {
        grossedUpEligible * DividendType.eligible.federalTaxCreditRate
    }

    var federalTaxCreditNonEligible: Double {
        grossedUpNonEligible * DividendType.nonEligible.federalTaxCreditRate
    }

    var totalFederalTaxCredit: Double {
        federalTaxCreditEligible + federalTaxCreditNonEligible
    }
}

// MARK: - Helper to generate summaries

struct DividendReportGenerator {

    static func quarterlySummary(for shareholder: Shareholder, year: Int, quarter: Int) -> DividendQuarterlySummary {
        let dividends = (shareholder.dividends ?? []).filter {
            $0.year == year && $0.quarter == quarter && $0.isPaid
        }

        let eligible = dividends.filter { $0.dividendType == .eligible }.reduce(0) { $0 + $1.amount }
        let nonEligible = dividends.filter { $0.dividendType == .nonEligible }.reduce(0) { $0 + $1.amount }

        return DividendQuarterlySummary(
            year: year,
            quarter: quarter,
            shareholder: shareholder,
            eligibleAmount: eligible,
            nonEligibleAmount: nonEligible,
            totalAmount: eligible + nonEligible,
            dividendCount: dividends.count
        )
    }

    static func yearlySummary(for shareholder: Shareholder, year: Int) -> DividendYearlySummary {
        let quarterlyBreakdown = (1...4).map { quarter in
            quarterlySummary(for: shareholder, year: year, quarter: quarter)
        }

        let eligible = quarterlyBreakdown.reduce(0) { $0 + $1.eligibleAmount }
        let nonEligible = quarterlyBreakdown.reduce(0) { $0 + $1.nonEligibleAmount }
        let count = quarterlyBreakdown.reduce(0) { $0 + $1.dividendCount }

        return DividendYearlySummary(
            year: year,
            shareholder: shareholder,
            eligibleAmount: eligible,
            nonEligibleAmount: nonEligible,
            totalAmount: eligible + nonEligible,
            dividendCount: count,
            quarterlyBreakdown: quarterlyBreakdown
        )
    }
}
