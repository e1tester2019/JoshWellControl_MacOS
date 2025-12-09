//
//  ExpenseReportView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-08.
//

import SwiftUI
import SwiftData

struct ExpenseReportView: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \MileageLog.date, order: .reverse) private var mileageLogs: [MileageLog]

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date.now)

    private var availableYears: [Int] {
        var years = Set<Int>()
        for expense in expenses {
            years.insert(Calendar.current.component(.year, from: expense.date))
        }
        for log in mileageLogs {
            years.insert(Calendar.current.component(.year, from: log.date))
        }
        if years.isEmpty {
            years.insert(Calendar.current.component(.year, from: Date.now))
        }
        return years.sorted().reversed()
    }

    private var yearExpenses: [Expense] {
        expenses.filter { Calendar.current.component(.year, from: $0.date) == selectedYear }
    }

    private var yearMileage: [MileageLog] {
        mileageLogs.filter { Calendar.current.component(.year, from: $0.date) == selectedYear }
    }

    private var expensesByCategory: [ExpenseCategory: [Expense]] {
        Dictionary(grouping: yearExpenses) { $0.category }
    }

    private var categorySummaries: [ExpenseSummary] {
        ExpenseCategory.allCases.compactMap { category in
            let categoryExpenses = expensesByCategory[category] ?? []
            guard !categoryExpenses.isEmpty else { return nil }

            return ExpenseSummary(
                category: category,
                count: categoryExpenses.count,
                totalAmount: categoryExpenses.reduce(0) { $0 + $1.totalAmount },
                totalGST: categoryExpenses.reduce(0) { $0 + $1.gstAmount },
                totalPST: categoryExpenses.reduce(0) { $0 + $1.pstAmount }
            )
        }.sorted { $0.totalAmount > $1.totalAmount }
    }

    private var totalExpenses: Double {
        yearExpenses.reduce(0) { $0 + $1.totalAmount }
    }

    private var totalGST: Double {
        yearExpenses.reduce(0) { $0 + $1.gstAmount }
    }

    private var totalPST: Double {
        yearExpenses.reduce(0) { $0 + $1.pstAmount }
    }

    private var totalMileageKm: Double {
        yearMileage.reduce(0) { $0 + $1.effectiveDistance }
    }

    private var mileageDeduction: Double {
        MileageSummary.calculateDeduction(totalKm: totalMileageKm)
    }

    private var expensesByProvince: [Province: Double] {
        var result: [Province: Double] = [:]
        for expense in yearExpenses {
            result[expense.province, default: 0] += expense.totalAmount
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Year selector
                    HStack {
                        Text("Tax Year")
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
                        SummaryCard(
                            title: "Total Expenses",
                            value: totalExpenses,
                            subtitle: "\(yearExpenses.count) transactions",
                            icon: "dollarsign.circle.fill",
                            color: .blue
                        )

                        SummaryCard(
                            title: "GST Paid",
                            value: totalGST,
                            subtitle: "Input tax credits",
                            icon: "percent",
                            color: .orange
                        )

                        SummaryCard(
                            title: "Mileage Deduction",
                            value: mileageDeduction,
                            subtitle: "\(Int(totalMileageKm)) km",
                            icon: "car.fill",
                            color: .green
                        )
                    }
                    .padding(.horizontal)

                    Divider()
                        .padding(.horizontal)

                    // Expenses by category
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Expenses by Category")
                            .font(.headline)
                            .padding(.horizontal)

                        if categorySummaries.isEmpty {
                            Text("No expenses recorded for \(selectedYear)")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                        } else {
                            ForEach(categorySummaries, id: \.category) { summary in
                                CategoryRow(summary: summary, totalExpenses: totalExpenses)
                            }
                            .padding(.horizontal)
                        }
                    }

                    Divider()
                        .padding(.horizontal)

                    // Province breakdown
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Expenses by Province")
                            .font(.headline)
                            .padding(.horizontal)

                        HStack(spacing: 20) {
                            ForEach(Province.allCases, id: \.self) { province in
                                let amount = expensesByProvince[province] ?? 0
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(province.rawValue)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(amount, format: .currency(code: "CAD"))
                                        .font(.title3)
                                        .fontWeight(.semibold)

                                    if province == .bc && amount > 0 {
                                        let bcExpenses = yearExpenses.filter { $0.province == .bc }
                                        let bcPST = bcExpenses.reduce(0) { $0 + $1.pstAmount }
                                        Text("PST: \(bcPST, format: .currency(code: "CAD"))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal)
                    }

                    Divider()
                        .padding(.horizontal)

                    // Mileage summary
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Mileage Summary")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Total Trips")
                                Spacer()
                                Text("\(yearMileage.count)")
                                    .fontWeight(.medium)
                            }

                            HStack {
                                Text("Total Distance")
                                Spacer()
                                Text("\(Int(totalMileageKm)) km")
                                    .fontWeight(.medium)
                            }

                            Divider()

                            let firstTierKm = min(totalMileageKm, MileageLog.firstTierLimit)
                            let secondTierKm = max(0, totalMileageKm - MileageLog.firstTierLimit)

                            HStack {
                                Text("First \(Int(MileageLog.firstTierLimit)) km @ $\(MileageLog.firstTierRate, specifier: "%.2f")")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(firstTierKm)) km = \(firstTierKm * MileageLog.firstTierRate, format: .currency(code: "CAD"))")
                            }

                            if secondTierKm > 0 {
                                HStack {
                                    Text("Remaining @ $\(MileageLog.secondTierRate, specifier: "%.2f")")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(Int(secondTierKm)) km = \(secondTierKm * MileageLog.secondTierRate, format: .currency(code: "CAD"))")
                                }
                            }

                            Divider()

                            HStack {
                                Text("Total Deduction")
                                    .fontWeight(.bold)
                                Spacer()
                                Text(mileageDeduction, format: .currency(code: "CAD"))
                                    .fontWeight(.bold)
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }

                    Divider()
                        .padding(.horizontal)

                    // Tax summary
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tax Summary")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Total Business Expenses")
                                Spacer()
                                Text(totalExpenses, format: .currency(code: "CAD"))
                                    .fontWeight(.medium)
                            }

                            HStack {
                                Text("Vehicle Mileage Deduction")
                                Spacer()
                                Text(mileageDeduction, format: .currency(code: "CAD"))
                                    .fontWeight(.medium)
                            }

                            Divider()

                            HStack {
                                Text("Total Deductions")
                                    .fontWeight(.bold)
                                Spacer()
                                Text(totalExpenses + mileageDeduction, format: .currency(code: "CAD"))
                                    .fontWeight(.bold)
                            }

                            Divider()

                            HStack {
                                Text("GST Input Tax Credits")
                                Spacer()
                                Text(totalGST, format: .currency(code: "CAD"))
                                    .fontWeight(.medium)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 20)
                }
                .padding(.vertical)
            }
            .navigationTitle("Expense Report")
        }
    }
}

// MARK: - Summary Card

struct SummaryCard: View {
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

// MARK: - Category Row

struct CategoryRow: View {
    let summary: ExpenseSummary
    let totalExpenses: Double

    private var percentage: Double {
        guard totalExpenses > 0 else { return 0 }
        return summary.totalAmount / totalExpenses
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: summary.category.icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                Text(summary.category.rawValue)

                Spacer()

                Text("\(summary.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)

                Text(summary.totalAmount, format: .currency(code: "CAD"))
                    .fontWeight(.medium)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 4)
                        .cornerRadius(2)

                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * percentage, height: 4)
                        .cornerRadius(2)
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ExpenseReportView()
}
