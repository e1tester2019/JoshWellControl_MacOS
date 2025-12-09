//
//  Payroll.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-08.
//

import Foundation
import SwiftData

// MARK: - Pay Frequency

enum PayFrequency: String, Codable, CaseIterable {
    case weekly = "Weekly"
    case biWeekly = "Bi-Weekly"
    case semiMonthly = "Semi-Monthly"
    case monthly = "Monthly"

    var periodsPerYear: Int {
        switch self {
        case .weekly: return 52
        case .biWeekly: return 26
        case .semiMonthly: return 24
        case .monthly: return 12
        }
    }
}

// MARK: - Pay Type

enum PayType: String, Codable, CaseIterable {
    case hourly = "Hourly"
    case salary = "Salary"
}

// MARK: - Employment Status

enum EmploymentStatus: String, Codable, CaseIterable {
    case active = "Active"
    case onLeave = "On Leave"
    case terminated = "Terminated"
}

// MARK: - Employee

@Model
final class Employee {
    var id: UUID = UUID()

    // Personal info
    var firstName: String = ""
    var lastName: String = ""
    var email: String = ""
    var phone: String = ""
    var address: String = ""
    var city: String = ""
    var provinceRaw: String = Province.alberta.rawValue
    var province: Province {
        get { Province(rawValue: provinceRaw) ?? .alberta }
        set { provinceRaw = newValue.rawValue }
    }
    var postalCode: String = ""
    var sinNumber: String = "" // Social Insurance Number (encrypted in production)

    // Employment info
    var employeeNumber: String = ""
    var startDate: Date = Date.now
    var terminationDate: Date?
    var statusRaw: String = EmploymentStatus.active.rawValue
    var status: EmploymentStatus {
        get { EmploymentStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }
    var jobTitle: String = ""

    // Pay info
    var payTypeRaw: String = PayType.hourly.rawValue
    var payType: PayType {
        get { PayType(rawValue: payTypeRaw) ?? .hourly }
        set { payTypeRaw = newValue.rawValue }
    }
    var payRate: Double = 0 // Hourly rate or annual salary
    var payFrequencyRaw: String = PayFrequency.biWeekly.rawValue
    var payFrequency: PayFrequency {
        get { PayFrequency(rawValue: payFrequencyRaw) ?? .biWeekly }
        set { payFrequencyRaw = newValue.rawValue }
    }

    // Tax info
    var federalTD1ClaimCode: Int = 1 // Basic personal amount claim code
    var provincialTD1ClaimCode: Int = 1

    // Vacation
    var vacationPayPercent: Double = 4.0 // 4% standard, 6% after 5 years in some provinces

    // YTD tracking (reset annually)
    var ytdGrossPay: Double = 0
    var ytdCPP: Double = 0
    var ytdEI: Double = 0
    var ytdFederalTax: Double = 0
    var ytdProvincialTax: Double = 0
    var ytdVacationPay: Double = 0
    var ytdVacationUsed: Double = 0
    var ytdYear: Int = Calendar.current.component(.year, from: Date.now)

    var notes: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \PayStub.employee) var payStubs: [PayStub]?

    init(firstName: String = "", lastName: String = "") {
        self.firstName = firstName
        self.lastName = lastName
    }

    var fullName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }

    var isActive: Bool {
        status == .active
    }

    /// Per-period pay for salaried employees
    var salaryPerPeriod: Double {
        guard payType == .salary else { return 0 }
        return payRate / Double(payFrequency.periodsPerYear)
    }

    /// Reset YTD values for new year
    func resetYTD(for year: Int) {
        ytdGrossPay = 0
        ytdCPP = 0
        ytdEI = 0
        ytdFederalTax = 0
        ytdProvincialTax = 0
        ytdVacationPay = 0
        ytdVacationUsed = 0
        ytdYear = year
    }

    /// Available vacation pay balance
    var vacationPayBalance: Double {
        ytdVacationPay - ytdVacationUsed
    }
}

// MARK: - Pay Run

@Model
final class PayRun {
    var id: UUID = UUID()

    var payPeriodStart: Date = Date.now
    var payPeriodEnd: Date = Date.now
    var payDate: Date = Date.now
    var payFrequencyRaw: String = PayFrequency.biWeekly.rawValue
    var payFrequency: PayFrequency {
        get { PayFrequency(rawValue: payFrequencyRaw) ?? .biWeekly }
        set { payFrequencyRaw = newValue.rawValue }
    }

    var isFinalized: Bool = false
    var finalizedAt: Date?

    var notes: String = ""
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \PayStub.payRun) var payStubs: [PayStub]?

    init(payPeriodStart: Date = Date.now, payPeriodEnd: Date = Date.now, payDate: Date = Date.now) {
        self.payPeriodStart = payPeriodStart
        self.payPeriodEnd = payPeriodEnd
        self.payDate = payDate
    }

    var periodString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return "\(formatter.string(from: payPeriodStart)) – \(formatter.string(from: payPeriodEnd))"
    }

    var payDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: payDate)
    }

    var totalGross: Double {
        (payStubs ?? []).reduce(0) { $0 + $1.grossPay }
    }

    var totalNet: Double {
        (payStubs ?? []).reduce(0) { $0 + $1.netPay }
    }

    var totalDeductions: Double {
        (payStubs ?? []).reduce(0) { $0 + $1.totalDeductions }
    }
}

// MARK: - Pay Stub

@Model
final class PayStub {
    var id: UUID = UUID()

    // Hours/earnings
    var regularHours: Double = 0
    var overtimeHours: Double = 0
    var holidayHours: Double = 0
    var sickHours: Double = 0
    var vacationHours: Double = 0

    // Rates
    var regularRate: Double = 0
    var overtimeRate: Double = 0 // Usually 1.5x regular

    // Earnings breakdown
    var regularEarnings: Double = 0
    var overtimeEarnings: Double = 0
    var holidayPay: Double = 0
    var sickPay: Double = 0
    var vacationPayout: Double = 0 // Vacation pay taken this period
    var otherEarnings: Double = 0
    var otherEarningsDescription: String = ""

    // Gross pay
    var grossPay: Double = 0

    // Statutory deductions
    var cppDeduction: Double = 0
    var eiDeduction: Double = 0
    var federalTax: Double = 0
    var provincialTax: Double = 0

    // Other deductions
    var otherDeductions: Double = 0
    var otherDeductionsDescription: String = ""

    // Vacation accrual
    var vacationAccrued: Double = 0

    // Net pay
    var netPay: Double = 0

    // YTD values at time of pay stub (snapshot)
    var ytdGrossPay: Double = 0
    var ytdCPP: Double = 0
    var ytdEI: Double = 0
    var ytdFederalTax: Double = 0
    var ytdProvincialTax: Double = 0
    var ytdVacationAccrued: Double = 0
    var ytdVacationUsed: Double = 0

    var notes: String = ""
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify) var employee: Employee?
    @Relationship(deleteRule: .nullify) var payRun: PayRun?

    init() {}

    var totalDeductions: Double {
        cppDeduction + eiDeduction + federalTax + provincialTax + otherDeductions
    }

    var totalHours: Double {
        regularHours + overtimeHours + holidayHours + sickHours + vacationHours
    }

    /// Calculate all values based on hours and rates
    func calculate(employee: Employee, ytdCPP: Double, ytdEI: Double) {
        // Calculate earnings
        regularEarnings = regularHours * regularRate
        overtimeEarnings = overtimeHours * overtimeRate
        holidayPay = holidayHours * regularRate
        sickPay = sickHours * regularRate

        // Gross pay
        grossPay = regularEarnings + overtimeEarnings + holidayPay + sickPay + vacationPayout + otherEarnings

        // Vacation accrual
        vacationAccrued = grossPay * (employee.vacationPayPercent / 100.0)

        // Calculate statutory deductions
        calculateCPP(ytdCPP: ytdCPP)
        calculateEI(ytdEI: ytdEI)
        calculateTax(employee: employee)

        // Net pay
        netPay = grossPay - totalDeductions
    }

    /// Calculate CPP deduction
    private func calculateCPP(ytdCPP: Double) {
        // 2024 CPP rates
        let cppRate = 0.0595
        let cppMaxContribution = 3867.50
        let cppExemption = 3500.0 / 26.0 // Per pay period for bi-weekly

        let pensionableEarnings = max(0, grossPay - cppExemption)
        var cpp = pensionableEarnings * cppRate

        // Check against annual maximum
        let remainingRoom = max(0, cppMaxContribution - ytdCPP)
        cpp = min(cpp, remainingRoom)

        cppDeduction = cpp
    }

    /// Calculate EI deduction
    private func calculateEI(ytdEI: Double) {
        // 2024 EI rates
        let eiRate = 0.0166
        let eiMaxContribution = 1049.12

        var ei = grossPay * eiRate

        // Check against annual maximum
        let remainingRoom = max(0, eiMaxContribution - ytdEI)
        ei = min(ei, remainingRoom)

        eiDeduction = ei
    }

    /// Calculate federal and provincial tax (simplified)
    /// Note: For accurate tax, use CRA PDOC or integrate with payroll service
    private func calculateTax(employee: Employee) {
        // This is a simplified calculation - real payroll should use CRA tables
        // or the CRA's Payroll Deductions Online Calculator (PDOC)

        let annualizedGross = grossPay * Double(employee.payFrequency.periodsPerYear)
        let annualizedCPP = cppDeduction * Double(employee.payFrequency.periodsPerYear)
        let annualizedEI = eiDeduction * Double(employee.payFrequency.periodsPerYear)

        // Taxable income (very simplified)
        let taxableIncome = annualizedGross - annualizedCPP - annualizedEI

        // Federal tax (2024 brackets - simplified)
        let federalAnnual = calculateFederalTax(taxableIncome: taxableIncome, claimCode: employee.federalTD1ClaimCode)
        federalTax = max(0, federalAnnual / Double(employee.payFrequency.periodsPerYear))

        // Provincial tax
        let provincialAnnual = calculateProvincialTax(
            taxableIncome: taxableIncome,
            province: employee.province,
            claimCode: employee.provincialTD1ClaimCode
        )
        provincialTax = max(0, provincialAnnual / Double(employee.payFrequency.periodsPerYear))
    }

    private func calculateFederalTax(taxableIncome: Double, claimCode: Int) -> Double {
        // 2024 Federal tax brackets (simplified)
        // Basic personal amount: ~$15,705 for claim code 1
        let basicPersonalAmount = 15705.0 * Double(claimCode)
        let taxableAfterCredits = max(0, taxableIncome - basicPersonalAmount)

        // Pre-calculate bracket amounts to avoid compiler timeout
        let bracket1Tax: Double = 55867.0 * 0.15
        let bracket2Tax: Double = 55866.0 * 0.205
        let bracket3Tax: Double = 61472.0 * 0.26
        let bracket4Tax: Double = 73547.0 * 0.29

        var tax = 0.0
        if taxableAfterCredits > 0 {
            if taxableAfterCredits <= 55867 {
                tax = taxableAfterCredits * 0.15
            } else if taxableAfterCredits <= 111733 {
                tax = bracket1Tax + (taxableAfterCredits - 55867) * 0.205
            } else if taxableAfterCredits <= 173205 {
                tax = bracket1Tax + bracket2Tax + (taxableAfterCredits - 111733) * 0.26
            } else if taxableAfterCredits <= 246752 {
                tax = bracket1Tax + bracket2Tax + bracket3Tax + (taxableAfterCredits - 173205) * 0.29
            } else {
                tax = bracket1Tax + bracket2Tax + bracket3Tax + bracket4Tax + (taxableAfterCredits - 246752) * 0.33
            }
        }
        return tax
    }

    private func calculateProvincialTax(taxableIncome: Double, province: Province, claimCode: Int) -> Double {
        var tax = 0.0

        switch province {
        case .alberta:
            // Alberta: 10% flat tax
            let basicPersonalAmount = 21003.0 * Double(claimCode)
            let taxableAfterCredits = max(0, taxableIncome - basicPersonalAmount)
            tax = taxableAfterCredits * 0.10

        case .bc:
            // BC: Progressive tax - pre-calculate bracket amounts
            let basicPersonalAmount = 12580.0 * Double(claimCode)
            let taxableAfterCredits = max(0, taxableIncome - basicPersonalAmount)

            let b1: Double = 47937.0 * 0.0506
            let b2: Double = 47938.0 * 0.077
            let b3: Double = 14201.0 * 0.105
            let b4: Double = 23588.0 * 0.1229
            let b5: Double = 47568.0 * 0.147
            let b6: Double = 71520.0 * 0.168

            if taxableAfterCredits <= 47937 {
                tax = taxableAfterCredits * 0.0506
            } else if taxableAfterCredits <= 95875 {
                tax = b1 + (taxableAfterCredits - 47937) * 0.077
            } else if taxableAfterCredits <= 110076 {
                tax = b1 + b2 + (taxableAfterCredits - 95875) * 0.105
            } else if taxableAfterCredits <= 133664 {
                tax = b1 + b2 + b3 + (taxableAfterCredits - 110076) * 0.1229
            } else if taxableAfterCredits <= 181232 {
                tax = b1 + b2 + b3 + b4 + (taxableAfterCredits - 133664) * 0.147
            } else if taxableAfterCredits <= 252752 {
                tax = b1 + b2 + b3 + b4 + b5 + (taxableAfterCredits - 181232) * 0.168
            } else {
                tax = b1 + b2 + b3 + b4 + b5 + b6 + (taxableAfterCredits - 252752) * 0.205
            }
        }

        return tax
    }
}

// MARK: - Payroll Constants (2024)

struct PayrollConstants {
    // CPP (Canada Pension Plan) 2024
    static let cppRate: Double = 0.0595
    static let cppMaxPensionableEarnings: Double = 68500.0
    static let cppBasicExemption: Double = 3500.0
    static let cppMaxContribution: Double = 3867.50

    // EI (Employment Insurance) 2024
    static let eiRate: Double = 0.0166
    static let eiMaxInsurableEarnings: Double = 63200.0
    static let eiMaxContribution: Double = 1049.12

    // Employer contributions
    static let employerCPPRate: Double = 0.0595 // Same as employee
    static let employerEIRate: Double = 0.0232 // 1.4x employee rate
}
