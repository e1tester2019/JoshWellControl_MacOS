//
//  PayrollReportView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-08.
//

import SwiftUI
import SwiftData

struct PayrollReportView: View {
    @Query(sort: \PayRun.payDate, order: .reverse) private var payRuns: [PayRun]
    @Query(sort: \Employee.lastName) private var employees: [Employee]

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date.now)

    private var availableYears: [Int] {
        var years = Set<Int>()
        for run in payRuns {
            years.insert(Calendar.current.component(.year, from: run.payDate))
        }
        if years.isEmpty {
            years.insert(Calendar.current.component(.year, from: Date.now))
        }
        return years.sorted().reversed()
    }

    private var yearPayRuns: [PayRun] {
        payRuns.filter {
            Calendar.current.component(.year, from: $0.payDate) == selectedYear && $0.isFinalized
        }
    }

    private var yearPayStubs: [PayStub] {
        yearPayRuns.flatMap { $0.payStubs ?? [] }
    }

    // Totals
    private var totalGross: Double {
        yearPayStubs.reduce(0) { $0 + $1.grossPay }
    }

    private var totalCPP: Double {
        yearPayStubs.reduce(0) { $0 + $1.cppDeduction }
    }

    private var totalEI: Double {
        yearPayStubs.reduce(0) { $0 + $1.eiDeduction }
    }

    private var totalFederalTax: Double {
        yearPayStubs.reduce(0) { $0 + $1.federalTax }
    }

    private var totalProvincialTax: Double {
        yearPayStubs.reduce(0) { $0 + $1.provincialTax }
    }

    private var totalNet: Double {
        yearPayStubs.reduce(0) { $0 + $1.netPay }
    }

    // Employer costs
    private var employerCPP: Double {
        totalCPP // Employer matches employee CPP
    }

    private var employerEI: Double {
        totalEI * 1.4 // Employer pays 1.4x employee EI
    }

    private var totalEmployerCosts: Double {
        totalGross + employerCPP + employerEI
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Year selector
                    HStack {
                        Text("Payroll Year")
                            .font(.headline)
                        Picker("Year", selection: $selectedYear) {
                            ForEach(availableYears, id: \.self) { year in
                                Text(String(year)).tag(year)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 300)

                        Spacer()
                    }
                    .padding(.horizontal)

                    // Summary cards
                    HStack(spacing: 16) {
                        PayrollSummaryCard(
                            title: "Total Gross",
                            value: totalGross,
                            subtitle: "\(yearPayRuns.count) pay runs",
                            icon: "dollarsign.circle.fill",
                            color: .blue
                        )

                        PayrollSummaryCard(
                            title: "Total Net Paid",
                            value: totalNet,
                            subtitle: "To employees",
                            icon: "banknote.fill",
                            color: .green
                        )

                        PayrollSummaryCard(
                            title: "Total Employer Cost",
                            value: totalEmployerCosts,
                            subtitle: "Including CPP/EI match",
                            icon: "building.2.fill",
                            color: .purple
                        )
                    }
                    .padding(.horizontal)

                    Divider()
                        .padding(.horizontal)

                    // Deductions summary
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Payroll Deductions Summary")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(spacing: 0) {
                            DeductionSummaryRow(label: "Employee CPP Contributions", amount: totalCPP, isEmployer: false)
                            DeductionSummaryRow(label: "Employer CPP Contributions", amount: employerCPP, isEmployer: true)
                            DeductionSummaryRow(label: "Employee EI Premiums", amount: totalEI, isEmployer: false)
                            DeductionSummaryRow(label: "Employer EI Premiums", amount: employerEI, isEmployer: true)
                            DeductionSummaryRow(label: "Federal Income Tax", amount: totalFederalTax, isEmployer: false)
                            DeductionSummaryRow(label: "Provincial Income Tax", amount: totalProvincialTax, isEmployer: false)

                            Divider()
                                .padding(.vertical, 8)

                            HStack {
                                Text("Total Remittances Due")
                                    .fontWeight(.bold)
                                Spacer()
                                Text(totalCPP + employerCPP + totalEI + employerEI + totalFederalTax + totalProvincialTax, format: .currency(code: "CAD"))
                                    .fontWeight(.bold)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }

                    Divider()
                        .padding(.horizontal)

                    // Employee summaries
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Employee Year-to-Date")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(employeesWithPay) { employee in
                            EmployeeYTDRow(employee: employee, year: selectedYear)
                        }
                        .padding(.horizontal)
                    }

                    Divider()
                        .padding(.horizontal)

                    // Pay runs list
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Pay Runs")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(yearPayRuns) { run in
                            PayRunSummaryRow(payRun: run)
                        }
                        .padding(.horizontal)

                        if yearPayRuns.isEmpty {
                            Text("No finalized pay runs for \(selectedYear)")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding(.vertical)
            }
            .navigationTitle("Payroll Reports")
        }
    }

    private var employeesWithPay: [Employee] {
        employees.filter { emp in
            emp.ytdYear == selectedYear && emp.ytdGrossPay > 0
        }
    }
}

// MARK: - Summary Card

struct PayrollSummaryCard: View {
    let title: String
    let value: Double
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(value, format: .currency(code: "CAD"))
                .font(.title2)
                .fontWeight(.bold)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Deduction Summary Row

struct DeductionSummaryRow: View {
    let label: String
    let amount: Double
    let isEmployer: Bool

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(isEmployer ? .secondary : .primary)
            if isEmployer {
                Text("(Employer)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(amount, format: .currency(code: "CAD"))
                .foregroundStyle(isEmployer ? .secondary : .primary)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

// MARK: - Employee YTD Row

struct EmployeeYTDRow: View {
    let employee: Employee
    let year: Int

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(employee.fullName)
                    .fontWeight(.medium)
                if !employee.employeeNumber.isEmpty {
                    Text("#\(employee.employeeNumber)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(employee.ytdGrossPay, format: .currency(code: "CAD"))
                    .fontWeight(.semibold)
            }

            HStack {
                HStack(spacing: 16) {
                    VStack(alignment: .leading) {
                        Text("CPP")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(employee.ytdCPP, format: .currency(code: "CAD"))
                            .font(.caption)
                    }
                    VStack(alignment: .leading) {
                        Text("EI")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(employee.ytdEI, format: .currency(code: "CAD"))
                            .font(.caption)
                    }
                    VStack(alignment: .leading) {
                        Text("Fed Tax")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(employee.ytdFederalTax, format: .currency(code: "CAD"))
                            .font(.caption)
                    }
                    VStack(alignment: .leading) {
                        Text("Prov Tax")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(employee.ytdProvincialTax, format: .currency(code: "CAD"))
                            .font(.caption)
                    }
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Vacation Balance")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(employee.vacationPayBalance, format: .currency(code: "CAD"))
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Pay Run Summary Row

struct PayRunSummaryRow: View {
    let payRun: PayRun

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(payRun.periodString)
                    .fontWeight(.medium)
                Text("Paid: \(payRun.payDateString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(payRun.payStubs?.count ?? 0) employees")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    VStack(alignment: .trailing) {
                        Text("Gross")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(payRun.totalGross, format: .currency(code: "CAD"))
                            .font(.callout)
                    }
                    VStack(alignment: .trailing) {
                        Text("Net")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(payRun.totalNet, format: .currency(code: "CAD"))
                            .font(.callout)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

#Preview {
    PayrollReportView()
}
