//
//  DividendStatementView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-08.
//

import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct DividendStatementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Shareholder.lastName) private var shareholders: [Shareholder]
    @Query(sort: \Dividend.paymentDate, order: .reverse) private var dividends: [Dividend]

    @State private var selectedShareholder: Shareholder?
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date.now)
    @State private var statementType: StatementType = .yearly

    enum StatementType: String, CaseIterable {
        case quarterly = "Quarterly"
        case yearly = "Yearly"
    }

    private var availableYears: [Int] {
        let years = Set(dividends.map { $0.year })
        if years.isEmpty {
            return [Calendar.current.component(.year, from: Date.now)]
        }
        return years.sorted(by: >)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Controls
            HStack(spacing: 16) {
                Picker("Shareholder", selection: $selectedShareholder) {
                    Text("All Shareholders").tag(nil as Shareholder?)
                    ForEach(shareholders) { shareholder in
                        Text(shareholder.fullName).tag(shareholder as Shareholder?)
                    }
                }
                .frame(width: 200)

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
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Statement content
            ScrollView {
                VStack(spacing: 24) {
                    if statementType == .yearly {
                        yearlyStatementContent
                    } else {
                        quarterlyStatementContent
                    }
                }
                .padding(32)
            }
        }
    }

    @ViewBuilder
    private var yearlyStatementContent: some View {
        let shareholdersToShow = selectedShareholder.map { [$0] } ?? shareholders.filter { $0.isActive }

        ForEach(shareholdersToShow) { shareholder in
            let summary = DividendReportGenerator.yearlySummary(for: shareholder, year: selectedYear)

            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(BusinessInfo.shared.companyName)
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Dividend Statement - \(String(selectedYear))")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Annual Summary")
                            .font(.headline)
                        Text("Tax Year \(String(selectedYear))")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 8)

                Divider()

                // Shareholder info
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Shareholder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(shareholder.fullName)
                            .fontWeight(.medium)
                        if !shareholder.fullAddress.isEmpty {
                            Text(shareholder.fullAddress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Ownership")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(shareholder.ownershipPercent, specifier: "%.1f")%")
                            .fontWeight(.medium)
                    }
                }
                .padding(.vertical, 8)

                // Quarterly breakdown
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quarterly Breakdown")
                        .font(.headline)

                    // Header row
                    HStack {
                        Text("Quarter")
                            .frame(width: 80, alignment: .leading)
                        Text("Eligible")
                            .frame(width: 100, alignment: .trailing)
                        Text("Non-Eligible")
                            .frame(width: 100, alignment: .trailing)
                        Text("Total")
                            .frame(width: 100, alignment: .trailing)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)

                    Divider()

                    ForEach(summary.quarterlyBreakdown, id: \.quarter) { quarter in
                        HStack {
                            Text(quarter.quarterString)
                                .frame(width: 80, alignment: .leading)
                            Text(quarter.eligibleAmount, format: .currency(code: "CAD"))
                                .frame(width: 100, alignment: .trailing)
                                .foregroundStyle(quarter.eligibleAmount > 0 ? .primary : .secondary)
                            Text(quarter.nonEligibleAmount, format: .currency(code: "CAD"))
                                .frame(width: 100, alignment: .trailing)
                                .foregroundStyle(quarter.nonEligibleAmount > 0 ? .primary : .secondary)
                            Text(quarter.totalAmount, format: .currency(code: "CAD"))
                                .frame(width: 100, alignment: .trailing)
                                .fontWeight(quarter.totalAmount > 0 ? .medium : .regular)
                        }
                        .padding(.vertical, 2)
                    }

                    Divider()

                    // Totals row
                    HStack {
                        Text("Total")
                            .fontWeight(.bold)
                            .frame(width: 80, alignment: .leading)
                        Text(summary.eligibleAmount, format: .currency(code: "CAD"))
                            .frame(width: 100, alignment: .trailing)
                            .fontWeight(.semibold)
                        Text(summary.nonEligibleAmount, format: .currency(code: "CAD"))
                            .frame(width: 100, alignment: .trailing)
                            .fontWeight(.semibold)
                        Text(summary.totalAmount, format: .currency(code: "CAD"))
                            .frame(width: 100, alignment: .trailing)
                            .fontWeight(.bold)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)

                // Tax summary
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tax Information (for T5 Preparation)")
                        .font(.headline)

                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                        GridRow {
                            Text("").gridColumnAlignment(.leading)
                            Text("Eligible").gridColumnAlignment(.trailing)
                            Text("Non-Eligible").gridColumnAlignment(.trailing)
                            Text("Total").gridColumnAlignment(.trailing)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Divider()
                            .gridCellColumns(4)

                        GridRow {
                            Text("Actual Dividends")
                            Text(summary.eligibleAmount, format: .currency(code: "CAD"))
                            Text(summary.nonEligibleAmount, format: .currency(code: "CAD"))
                            Text(summary.totalAmount, format: .currency(code: "CAD"))
                        }

                        GridRow {
                            Text("Gross-up Amount")
                            Text(summary.grossedUpEligible - summary.eligibleAmount, format: .currency(code: "CAD"))
                                .foregroundStyle(.secondary)
                            Text(summary.grossedUpNonEligible - summary.nonEligibleAmount, format: .currency(code: "CAD"))
                                .foregroundStyle(.secondary)
                            Text(summary.totalGrossedUp - summary.totalAmount, format: .currency(code: "CAD"))
                                .foregroundStyle(.secondary)
                        }

                        GridRow {
                            Text("Taxable Amount")
                                .fontWeight(.medium)
                            Text(summary.grossedUpEligible, format: .currency(code: "CAD"))
                                .fontWeight(.medium)
                            Text(summary.grossedUpNonEligible, format: .currency(code: "CAD"))
                                .fontWeight(.medium)
                            Text(summary.totalGrossedUp, format: .currency(code: "CAD"))
                                .fontWeight(.bold)
                        }

                        Divider()
                            .gridCellColumns(4)

                        GridRow {
                            Text("Federal Dividend Tax Credit")
                            Text(summary.federalTaxCreditEligible, format: .currency(code: "CAD"))
                                .foregroundStyle(.green)
                            Text(summary.federalTaxCreditNonEligible, format: .currency(code: "CAD"))
                                .foregroundStyle(.green)
                            Text(summary.totalFederalTaxCredit, format: .currency(code: "CAD"))
                                .foregroundStyle(.green)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(8)

                // T5 Box reference
                VStack(alignment: .leading, spacing: 4) {
                    Text("T5 Slip Reference")
                        .font(.caption)
                        .fontWeight(.medium)

                    HStack(spacing: 24) {
                        VStack(alignment: .leading) {
                            Text("Box 10: Actual eligible dividends")
                            Text("Box 11: Taxable eligible dividends")
                            Text("Box 12: Eligible dividend tax credit")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        VStack(alignment: .leading) {
                            Text("Box 23: Actual other dividends")
                            Text("Box 24: Taxable other dividends")
                            Text("Box 25: Other dividend tax credit")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.05))
                .cornerRadius(8)

                if selectedShareholder == nil && shareholder.id != shareholdersToShow.last?.id {
                    Divider()
                        .padding(.vertical, 16)
                }
            }
            .padding()
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
    }

    @ViewBuilder
    private var quarterlyStatementContent: some View {
        let shareholdersToShow = selectedShareholder.map { [$0] } ?? shareholders.filter { $0.isActive }

        ForEach(1...4, id: \.self) { quarter in
            let hasData = shareholdersToShow.contains { shareholder in
                let summary = DividendReportGenerator.quarterlySummary(for: shareholder, year: selectedYear, quarter: quarter)
                return summary.totalAmount > 0
            }

            if hasData {
                VStack(alignment: .leading, spacing: 16) {
                    // Quarter header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(BusinessInfo.shared.companyName)
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("Quarterly Dividend Statement")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Q\(quarter) \(String(selectedYear))")
                                .font(.title2)
                                .fontWeight(.bold)

                            let summary = DividendReportGenerator.quarterlySummary(for: shareholdersToShow.first!, year: selectedYear, quarter: quarter)
                            Text("\(summary.periodStart.formatted(date: .abbreviated, time: .omitted)) - \(summary.periodEnd.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    ForEach(shareholdersToShow) { shareholder in
                        let summary = DividendReportGenerator.quarterlySummary(for: shareholder, year: selectedYear, quarter: quarter)

                        if summary.totalAmount > 0 {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(shareholder.fullName)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text("\(shareholder.ownershipPercent, specifier: "%.1f")% ownership")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        if summary.eligibleAmount > 0 {
                                            HStack {
                                                Text("Eligible Dividends")
                                                    .font(.caption)
                                                Spacer()
                                                Text(summary.eligibleAmount, format: .currency(code: "CAD"))
                                            }
                                        }
                                        if summary.nonEligibleAmount > 0 {
                                            HStack {
                                                Text("Non-Eligible Dividends")
                                                    .font(.caption)
                                                Spacer()
                                                Text(summary.nonEligibleAmount, format: .currency(code: "CAD"))
                                            }
                                        }
                                    }
                                    .frame(maxWidth: 300)

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("Quarter Total")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(summary.totalAmount, format: .currency(code: "CAD"))
                                            .font(.title3)
                                            .fontWeight(.bold)
                                    }
                                }
                                .padding()
                                .background(Color.gray.opacity(0.05))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding()
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            }
        }

        // Show message if no dividends
        let totalDividends = shareholdersToShow.reduce(0.0) { total, shareholder in
            total + (1...4).reduce(0.0) { quarterTotal, quarter in
                quarterTotal + DividendReportGenerator.quarterlySummary(for: shareholder, year: selectedYear, quarter: quarter).totalAmount
            }
        }

        if totalDividends == 0 {
            ContentUnavailableView {
                Label("No Dividends", systemImage: "dollarsign.circle")
            } description: {
                Text("No dividends were paid in \(String(selectedYear))")
            }
        }
    }

    private func exportPDF() {
        let shareholdersToShow = selectedShareholder.map { [$0] } ?? shareholders.filter { $0.isActive }

        guard let data = DividendStatementPDFGenerator.shared.generatePDF(
            shareholders: shareholdersToShow,
            year: selectedYear,
            statementType: statementType
        ) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]

        let typeName = statementType == .yearly ? "Annual" : "Quarterly"
        let shareholderName = selectedShareholder?.fullName.replacingOccurrences(of: " ", with: "_") ?? "All"
        panel.nameFieldStringValue = "Dividend_Statement_\(typeName)_\(selectedYear)_\(shareholderName).pdf"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? data.write(to: url)
                NSWorkspace.shared.open(url)
            }
        }
    }
}

#Preview {
    DividendStatementView()
}
