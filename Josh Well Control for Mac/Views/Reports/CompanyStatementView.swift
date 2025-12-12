//
//  CompanyStatementView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-08.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct CompanyStatementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Invoice.date, order: .reverse) private var invoices: [Invoice]
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \PayStub.createdAt, order: .reverse) private var payStubs: [PayStub]
    @Query(sort: \Dividend.paymentDate, order: .reverse) private var dividends: [Dividend]
    @Query(sort: \MileageLog.date, order: .reverse) private var mileageLogs: [MileageLog]

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date.now)
    @State private var statementType: CompanyStatementPDFGenerator.StatementType = .yearly
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var showingExportError = false

    typealias StatementType = CompanyStatementPDFGenerator.StatementType

    private var availableYears: [Int] {
        var years = Set<Int>()
        invoices.forEach { years.insert(Calendar.current.component(.year, from: $0.date)) }
        expenses.forEach { years.insert(Calendar.current.component(.year, from: $0.date)) }
        dividends.forEach { years.insert($0.year) }
        if years.isEmpty {
            years.insert(Calendar.current.component(.year, from: Date.now))
        }
        return years.sorted(by: >)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Controls
            HStack(spacing: 16) {
                Picker("Year", selection: $selectedYear) {
                    ForEach(availableYears, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .frame(width: 100)

                Picker("Statement Type", selection: $statementType) {
                    ForEach(StatementType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                Spacer()

                Button {
                    exportPDF()
                } label: {
                    Label("Export PDF", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.bordered)

                Button {
                    exportForAccountant()
                } label: {
                    if isExporting {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                        Text("Exporting...")
                    } else {
                        Label("Export for Accountant", systemImage: "shippingbox")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExporting)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    if statementType == .yearly {
                        yearlyStatement
                    } else {
                        quarterlyStatements
                    }
                }
                .padding(32)
            }
        }
        .alert("Export Error", isPresented: $showingExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "An unknown error occurred")
        }
    }

    // MARK: - Yearly Statement

    @ViewBuilder
    private var yearlyStatement: some View {
        let summary = generateYearlySummary(year: selectedYear)

        StatementCard(title: "Annual Financial Statement", subtitle: "Fiscal Year \(selectedYear)") {
            // Revenue Section
            SectionHeader(title: "REVENUE", icon: "arrow.up.circle.fill", color: .green)

            StatementRow(label: "Invoiced Revenue", amount: summary.totalRevenue)
            StatementRow(label: "Less: Unpaid Invoices", amount: -summary.unpaidRevenue, isSubtle: true)
            StatementDivider()
            StatementRow(label: "Net Revenue (Collected)", amount: summary.collectedRevenue, isBold: true)

            Spacer().frame(height: 20)

            // Expenses Section
            SectionHeader(title: "EXPENSES", icon: "arrow.down.circle.fill", color: .red)

            ForEach(summary.expensesByCategory.sorted(by: { $0.value > $1.value }), id: \.key) { category, amount in
                StatementRow(label: category.rawValue, amount: amount, isSubtle: true)
            }
            if summary.mileageDeduction > 0 {
                StatementRow(label: "Mileage (CRA Rate)", amount: summary.mileageDeduction, isSubtle: true)
            }
            StatementDivider()
            StatementRow(label: "Total Expenses", amount: summary.totalExpenses, isBold: true, isExpense: true)

            Spacer().frame(height: 20)

            // Payroll Section
            SectionHeader(title: "PAYROLL", icon: "person.2.fill", color: .blue)

            StatementRow(label: "Gross Wages", amount: summary.grossPayroll)
            StatementRow(label: "Employer CPP", amount: summary.employerCPP, isSubtle: true)
            StatementRow(label: "Employer EI", amount: summary.employerEI, isSubtle: true)
            StatementDivider()
            StatementRow(label: "Total Payroll Cost", amount: summary.totalPayrollCost, isBold: true, isExpense: true)

            Spacer().frame(height: 20)

            // Operating Income
            SectionHeader(title: "OPERATING RESULTS", icon: "chart.bar.fill", color: .purple)

            let operatingIncome = summary.collectedRevenue - summary.totalExpenses - summary.totalPayrollCost
            StatementRow(label: "Operating Income", amount: operatingIncome, isBold: true, isHighlight: true)

            Spacer().frame(height: 20)

            // Dividends Section
            SectionHeader(title: "DIVIDENDS", icon: "dollarsign.circle.fill", color: .orange)

            StatementRow(label: "Dividends Declared", amount: summary.dividendsDeclared)
            StatementRow(label: "Dividends Paid", amount: summary.dividendsPaid, isSubtle: true)

            Spacer().frame(height: 20)

            // Net Position
            SectionHeader(title: "NET POSITION", icon: "banknote.fill", color: .teal)

            let netPosition = operatingIncome - summary.dividendsPaid
            StatementRow(label: "Retained Earnings (After Dividends)", amount: netPosition, isBold: true, isHighlight: true)

            // Tax Summary
            Spacer().frame(height: 20)
            taxSummarySection(summary: summary)
        }
    }

    // MARK: - Quarterly Statements

    @ViewBuilder
    private var quarterlyStatements: some View {
        ForEach([1, 2, 3, 4], id: \.self) { (quarter: Int) in
            let summary = generateQuarterlySummary(year: selectedYear, quarter: quarter)

            // Only show quarters with activity
            if summary.totalRevenue > 0 || summary.totalExpenses > 0 || summary.dividendsPaid > 0 {
                StatementCard(title: "Q\(quarter) Financial Statement", subtitle: quarterDateRange(year: selectedYear, quarter: quarter)) {
                    // Revenue
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Revenue")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(summary.collectedRevenue, format: .currency(code: "CAD"))
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                        }

                        Spacer()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Expenses")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(summary.totalExpenses, format: .currency(code: "CAD"))
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(.red)
                        }

                        Spacer()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Payroll")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(summary.totalPayrollCost, format: .currency(code: "CAD"))
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                        }

                        Spacer()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Dividends")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(summary.dividendsPaid, format: .currency(code: "CAD"))
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 8)

                    StatementDivider()

                    let operatingIncome = summary.collectedRevenue - summary.totalExpenses - summary.totalPayrollCost
                    let netPosition = operatingIncome - summary.dividendsPaid

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Operating Income")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(operatingIncome, format: .currency(code: "CAD"))
                                .font(.headline)
                                .foregroundStyle(operatingIncome >= 0 ? .green : .red)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Net Position")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(netPosition, format: .currency(code: "CAD"))
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(netPosition >= 0 ? .primary : .red)
                        }
                    }

                    // Expense breakdown
                    if !summary.expensesByCategory.isEmpty {
                        Spacer().frame(height: 16)
                        Text("Expense Breakdown")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(summary.expensesByCategory.sorted(by: { $0.value > $1.value }).prefix(6), id: \.key) { category, amount in
                                HStack {
                                    Image(systemName: category.icon)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(amount, format: .currency(code: "CAD"))
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
        }

        // Show message if no data
        let hasData = (1...4).contains { quarter in
            let summary = generateQuarterlySummary(year: selectedYear, quarter: quarter)
            return summary.totalRevenue > 0 || summary.totalExpenses > 0
        }

        if !hasData {
            ContentUnavailableView {
                Label("No Financial Data", systemImage: "chart.bar")
            } description: {
                Text("No financial activity recorded for \(String(selectedYear))")
            }
        }
    }

    // MARK: - Tax Summary Section

    @ViewBuilder
    private func taxSummarySection(summary: FinancialSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TAX INFORMATION")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GST Collected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(summary.gstCollected, format: .currency(code: "CAD"))
                        .fontWeight(.medium)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("GST Paid (ITC)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(summary.gstPaid, format: .currency(code: "CAD"))
                        .fontWeight(.medium)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Net GST Owing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(summary.gstCollected - summary.gstPaid, format: .currency(code: "CAD"))
                        .fontWeight(.bold)
                        .foregroundStyle(summary.gstCollected - summary.gstPaid > 0 ? .red : .green)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Total Mileage")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(Int(summary.totalMileage)) km")
                        .fontWeight(.medium)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
        }
    }

    // MARK: - Helper Functions

    private func quarterDateRange(year: Int, quarter: Int) -> String {
        let startMonth = ((quarter - 1) * 3) + 1
        let endMonth = quarter * 3

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM"

        var startComponents = DateComponents()
        startComponents.year = year
        startComponents.month = startMonth
        startComponents.day = 1
        let startDate = Calendar.current.date(from: startComponents) ?? Date()

        var endComponents = DateComponents()
        endComponents.year = year
        endComponents.month = endMonth
        endComponents.day = 1
        let endDate = Calendar.current.date(from: endComponents) ?? Date()

        return "\(dateFormatter.string(from: startDate)) - \(dateFormatter.string(from: endDate)) \(year)"
    }

    private func generateYearlySummary(year: Int) -> FinancialSummary {
        generateSummary(year: year, quarter: nil)
    }

    private func generateQuarterlySummary(year: Int, quarter: Int) -> FinancialSummary {
        generateSummary(year: year, quarter: quarter)
    }

    private func generateSummary(year: Int, quarter: Int?) -> FinancialSummary {
        let calendar = Calendar.current

        func isInPeriod(_ date: Date) -> Bool {
            let dateYear = calendar.component(.year, from: date)
            guard dateYear == year else { return false }

            if let q = quarter {
                let dateMonth = calendar.component(.month, from: date)
                let dateQuarter = ((dateMonth - 1) / 3) + 1
                return dateQuarter == q
            }
            return true
        }

        // Revenue from invoices
        let periodInvoices = invoices.filter { isInPeriod($0.date) }
        let totalRevenue = periodInvoices.reduce(0) { $0 + $1.subtotal }
        let paidInvoices = periodInvoices.filter { $0.isPaid }
        let collectedRevenue = paidInvoices.reduce(0) { $0 + $1.subtotal }
        let unpaidRevenue = totalRevenue - collectedRevenue
        let gstCollected = periodInvoices.reduce(0) { $0 + $1.gstAmount }

        // Expenses
        let periodExpenses = expenses.filter { isInPeriod($0.date) }
        var expensesByCategory: [ExpenseCategory: Double] = [:]
        var totalExpenses: Double = 0
        var gstPaid: Double = 0

        for expense in periodExpenses {
            let amount = expense.preTaxAmount
            expensesByCategory[expense.category, default: 0] += amount
            totalExpenses += amount
            gstPaid += expense.gstAmount
        }

        // Mileage
        let periodMileage = mileageLogs.filter { isInPeriod($0.date) }
        let totalMileage = periodMileage.reduce(0) { $0 + $1.effectiveDistance }
        let mileageDeduction = MileageSummary.calculateDeduction(totalKm: totalMileage)
        totalExpenses += mileageDeduction

        // Payroll
        let periodPayStubs = payStubs.filter {
            guard let payRun = $0.payRun else { return false }
            return isInPeriod(payRun.payDate)
        }
        let grossPayroll = periodPayStubs.reduce(0) { $0 + $1.grossPay }
        let employerCPP = grossPayroll * PayrollConstants.employerCPPRate
        let employerEI = grossPayroll * PayrollConstants.employerEIRate
        let totalPayrollCost = grossPayroll + employerCPP + employerEI

        // Dividends
        let periodDividends = dividends.filter { isInPeriod($0.paymentDate) }
        let dividendsDeclared = periodDividends.reduce(0) { $0 + $1.amount }
        let dividendsPaid = periodDividends.filter { $0.isPaid }.reduce(0) { $0 + $1.amount }

        return FinancialSummary(
            totalRevenue: totalRevenue,
            collectedRevenue: collectedRevenue,
            unpaidRevenue: unpaidRevenue,
            gstCollected: gstCollected,
            expensesByCategory: expensesByCategory,
            totalExpenses: totalExpenses,
            gstPaid: gstPaid,
            mileageDeduction: mileageDeduction,
            totalMileage: totalMileage,
            grossPayroll: grossPayroll,
            employerCPP: employerCPP,
            employerEI: employerEI,
            totalPayrollCost: totalPayrollCost,
            dividendsDeclared: dividendsDeclared,
            dividendsPaid: dividendsPaid
        )
    }

    private func exportPDF() {
        #if os(macOS)
        let summaries: [(String, FinancialSummary)]
        if statementType == .yearly {
            summaries = [("Annual", generateYearlySummary(year: selectedYear))]
        } else {
            summaries = (1...4).compactMap { quarter in
                let summary = generateQuarterlySummary(year: selectedYear, quarter: quarter)
                if summary.totalRevenue > 0 || summary.totalExpenses > 0 || summary.dividendsPaid > 0 {
                    return ("Q\(quarter)", summary)
                }
                return nil
            }
        }

        guard let data = CompanyStatementPDFGenerator.shared.generatePDF(
            summaries: summaries,
            year: selectedYear,
            statementType: statementType
        ) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]

        let typeName = statementType == .yearly ? "Annual" : "Quarterly"
        panel.nameFieldStringValue = "Company_Statement_\(typeName)_\(selectedYear).pdf"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? data.write(to: url)
                NSWorkspace.shared.open(url)
            }
        }
        #endif
    }

    private func exportForAccountant() {
        #if os(macOS)
        isExporting = true

        // Filter data for selected year
        let calendar = Calendar.current

        func isInYear(_ date: Date) -> Bool {
            calendar.component(.year, from: date) == selectedYear
        }

        let yearInvoices = invoices.filter { isInYear($0.date) }
        let yearExpenses = expenses.filter { isInYear($0.date) }
        let yearMileage = mileageLogs.filter { isInYear($0.date) }
        let yearPayStubs = payStubs.filter {
            guard let payRun = $0.payRun else { return false }
            return isInYear(payRun.payDate)
        }
        let yearDividends = dividends.filter { $0.year == selectedYear }

        let summary = generateYearlySummary(year: selectedYear)

        let exportData = AccountantExportService.ExportData(
            year: selectedYear,
            quarter: nil,
            invoices: yearInvoices,
            expenses: yearExpenses,
            mileageLogs: yearMileage,
            payStubs: yearPayStubs,
            dividends: yearDividends,
            summary: summary
        )

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "Accountant_Package_\(selectedYear).zip"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try AccountantExportService.shared.exportPackage(data: exportData, to: url)
                        DispatchQueue.main.async {
                            isExporting = false
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    } catch {
                        DispatchQueue.main.async {
                            isExporting = false
                            exportError = error.localizedDescription
                            showingExportError = true
                        }
                    }
                }
            } else {
                isExporting = false
            }
        }
        #endif
    }
}

// MARK: - Financial Summary Model

struct FinancialSummary {
    let totalRevenue: Double
    let collectedRevenue: Double
    let unpaidRevenue: Double
    let gstCollected: Double
    let expensesByCategory: [ExpenseCategory: Double]
    let totalExpenses: Double
    let gstPaid: Double
    let mileageDeduction: Double
    let totalMileage: Double
    let grossPayroll: Double
    let employerCPP: Double
    let employerEI: Double
    let totalPayrollCost: Double
    let dividendsDeclared: Double
    let dividendsPaid: Double
}

// MARK: - Supporting Views

struct StatementCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(BusinessInfo.shared.companyName)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(subtitle)
                        .font(.headline)
                    Text("Generated \(Date.now.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            content
        }
        .padding(24)
        #if os(macOS)
        .background(Color(NSColor.controlBackgroundColor))
        #else
        .background(Color(uiColor: .secondarySystemBackground))
        #endif
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 8)
    }
}

struct StatementRow: View {
    let label: String
    let amount: Double
    var isBold: Bool = false
    var isSubtle: Bool = false
    var isExpense: Bool = false
    var isHighlight: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(isBold ? .body : .callout)
                .fontWeight(isBold ? .semibold : .regular)
                .foregroundStyle(isSubtle ? .secondary : .primary)

            Spacer()

            Text(amount, format: .currency(code: "CAD"))
                .font(isBold ? .body : .callout)
                .fontWeight(isBold ? .bold : .medium)
                .foregroundStyle(amountColor)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, isSubtle ? 16 : 0)
        .background(isHighlight ? Color.blue.opacity(0.05) : Color.clear)
        .cornerRadius(4)
    }

    private var amountColor: Color {
        if isHighlight {
            return amount >= 0 ? .green : .red
        }
        if isExpense {
            return .red
        }
        return .primary
    }
}

struct StatementDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(height: 1)
            .padding(.vertical, 4)
    }
}

#Preview {
    CompanyStatementView()
}
