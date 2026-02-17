//
//  DividendListView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-08.
//

#if os(macOS)
import SwiftUI
import SwiftData

struct DividendListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Dividend.paymentDate, order: .reverse) private var dividends: [Dividend]
    @Query(sort: \Shareholder.lastName) private var shareholders: [Shareholder]

    @State private var selectedDividend: Dividend?
    @State private var showingAddDividend = false
    @State private var showingShareholderList = false

    // Filters
    @State private var selectedShareholder: Shareholder?
    @State private var selectedYear: Int?
    @State private var selectedQuarter: Int?
    @State private var showPaidOnly = false

    private var availableYears: [Int] {
        let years = Set(dividends.map { $0.year })
        return years.sorted(by: >)
    }

    private var filteredDividends: [Dividend] {
        dividends.filter { dividend in
            if let shareholder = selectedShareholder, dividend.shareholder?.id != shareholder.id {
                return false
            }
            if let year = selectedYear, dividend.year != year {
                return false
            }
            if let quarter = selectedQuarter, dividend.quarter != quarter {
                return false
            }
            if showPaidOnly && !dividend.isPaid {
                return false
            }
            return true
        }
    }

    private var groupedDividends: [(String, [Dividend])] {
        let grouped = Dictionary(grouping: filteredDividends) { $0.quarterString }
        return grouped.sorted { $0.key > $1.key }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack(spacing: 16) {
                Picker("Shareholder", selection: $selectedShareholder) {
                    Text("All Shareholders").tag(nil as Shareholder?)
                    ForEach(shareholders) { shareholder in
                        Text(shareholder.fullName).tag(shareholder as Shareholder?)
                    }
                }
                .controlSize(.small)
                .frame(width: 180)

                Picker("Year", selection: $selectedYear) {
                    Text("All Years").tag(nil as Int?)
                    ForEach(availableYears, id: \.self) { year in
                        Text(String(year)).tag(year as Int?)
                    }
                }
                .controlSize(.small)
                .frame(width: 120)

                Picker("Quarter", selection: $selectedQuarter) {
                    Text("All Quarters").tag(nil as Int?)
                    Text("Q1").tag(1 as Int?)
                    Text("Q2").tag(2 as Int?)
                    Text("Q3").tag(3 as Int?)
                    Text("Q4").tag(4 as Int?)
                }
                .controlSize(.small)
                .frame(width: 120)

                Toggle("Paid Only", isOn: $showPaidOnly)
                    .controlSize(.small)

                Spacer()

                Button {
                    showingShareholderList = true
                } label: {
                    Label("Shareholders", systemImage: "person.2")
                }

                Button {
                    showingAddDividend = true
                } label: {
                    Label("Declare Dividend", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            if filteredDividends.isEmpty {
                ContentUnavailableView {
                    Label("No Dividends", systemImage: "dollarsign.circle")
                } description: {
                    if dividends.isEmpty {
                        Text("Declare a dividend to get started")
                    } else {
                        Text("No dividends match your filters")
                    }
                } actions: {
                    Button("Declare Dividend") {
                        showingAddDividend = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List(selection: $selectedDividend) {
                    ForEach(groupedDividends, id: \.0) { quarter, quarterDividends in
                        Section {
                            ForEach(quarterDividends) { dividend in
                                DividendRow(dividend: dividend)
                                    .tag(dividend)
                                    .contextMenu {
                                        if !dividend.isPaid {
                                            Button("Mark as Paid") {
                                                dividend.isPaid = true
                                                dividend.paidDate = Date.now
                                                try? modelContext.save()
                                            }
                                        }
                                        Divider()
                                        Button("Delete", role: .destructive) {
                                            modelContext.delete(dividend)
                                        }
                                    }
                            }
                        } header: {
                            HStack {
                                Text(quarter)
                                    .font(.headline)
                                Spacer()
                                let total = quarterDividends.reduce(0) { $0 + $1.amount }
                                Text(total, format: .currency(code: "CAD"))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            // Summary footer
            if !filteredDividends.isEmpty {
                Divider()
                HStack {
                    let paidDividends = filteredDividends.filter { $0.isPaid }
                    let unpaidDividends = filteredDividends.filter { !$0.isPaid }

                    VStack(alignment: .leading) {
                        Text("\(filteredDividends.count) dividend\(filteredDividends.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !unpaidDividends.isEmpty {
                        VStack(alignment: .trailing) {
                            Text("Declared")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(unpaidDividends.reduce(0) { $0 + $1.amount }, format: .currency(code: "CAD"))
                                .foregroundStyle(.orange)
                        }
                    }

                    VStack(alignment: .trailing) {
                        Text("Paid")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(paidDividends.reduce(0) { $0 + $1.amount }, format: .currency(code: "CAD"))
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                    }
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingAddDividend) {
            DividendEditorView(dividend: nil)
        }
        .sheet(item: $selectedDividend) { dividend in
            DividendEditorView(dividend: dividend)
        }
        .sheet(isPresented: $showingShareholderList) {
            ShareholderListView()
        }
    }
}

// MARK: - Dividend Row

struct DividendRow: View {
    let dividend: Dividend

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(dividend.shareholder?.fullName ?? "Unknown")
                        .fontWeight(.medium)

                    Text("•")
                        .foregroundStyle(.secondary)

                    Text(dividend.dividendType.shortName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(dividend.dividendType == .eligible ? Color.blue.opacity(0.2) : Color.orange.opacity(0.2))
                        .cornerRadius(4)
                }

                Text(dividend.displayDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(dividend.amount, format: .currency(code: "CAD"))
                    .fontWeight(.semibold)

                if dividend.isPaid {
                    Label("Paid", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("Declared", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Dividend Editor

struct DividendEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Shareholder.lastName) private var shareholders: [Shareholder]

    let dividend: Dividend?

    @State private var selectedShareholder: Shareholder?
    @State private var amount: Double = 0
    @State private var dividendType: DividendType = .nonEligible
    @State private var declarationDate = Date.now
    @State private var recordDate = Date.now
    @State private var paymentDate = Date.now
    @State private var isPaid = false
    @State private var resolution = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Shareholder") {
                    Picker("Shareholder", selection: $selectedShareholder) {
                        Text("Select Shareholder").tag(nil as Shareholder?)
                        ForEach(shareholders) { shareholder in
                            Text("\(shareholder.fullName) (\(shareholder.ownershipPercent, specifier: "%.0f")%)").tag(shareholder as Shareholder?)
                        }
                    }

                    if shareholders.isEmpty {
                        Text("No shareholders found. Add a shareholder first.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                Section("Dividend Details") {
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("Amount", value: $amount, format: .currency(code: "CAD"))
                            .frame(width: 150)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                    }

                    Picker("Type", selection: $dividendType) {
                        ForEach(DividendType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    Text("Most small business (CCPC) dividends are Non-Eligible")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Dates") {
                    DatePicker("Declaration Date", selection: $declarationDate, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "en_GB"))

                    DatePicker("Record Date", selection: $recordDate, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "en_GB"))

                    DatePicker("Payment Date", selection: $paymentDate, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "en_GB"))
                }

                Section("Status") {
                    Toggle("Dividend Paid", isOn: $isPaid)
                }

                Section("Reference") {
                    TextField("Board Resolution #", text: $resolution)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if amount > 0 {
                    Section("Tax Information (Preview)") {
                        HStack {
                            Text("Actual Dividend")
                            Spacer()
                            Text(amount, format: .currency(code: "CAD"))
                        }

                        HStack {
                            Text("Gross-up (\(dividendType == .eligible ? "38" : "15")%)")
                            Spacer()
                            Text(amount * dividendType.grossUpRate, format: .currency(code: "CAD"))
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Taxable Amount")
                            Spacer()
                            Text(amount * (1 + dividendType.grossUpRate), format: .currency(code: "CAD"))
                                .fontWeight(.medium)
                        }

                        HStack {
                            Text("Federal Dividend Tax Credit")
                            Spacer()
                            Text(amount * (1 + dividendType.grossUpRate) * dividendType.federalTaxCreditRate, format: .currency(code: "CAD"))
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(dividend == nil ? "Declare Dividend" : "Edit Dividend")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(selectedShareholder == nil || amount <= 0)
                }
            }
            .onAppear { loadDividend() }
        }
        .frame(minWidth: 500, minHeight: 600)
    }

    private func loadDividend() {
        guard let div = dividend else { return }
        selectedShareholder = div.shareholder
        amount = div.amount
        dividendType = div.dividendType
        declarationDate = div.declarationDate
        recordDate = div.recordDate
        paymentDate = div.paymentDate
        isPaid = div.isPaid
        resolution = div.resolution
        notes = div.notes
    }

    private func save() {
        let div = dividend ?? Dividend()
        div.shareholder = selectedShareholder
        div.amount = amount
        div.dividendType = dividendType
        div.declarationDate = declarationDate
        div.recordDate = recordDate
        div.paymentDate = paymentDate
        div.isPaid = isPaid
        div.paidDate = isPaid ? Date.now : nil
        div.resolution = resolution
        div.notes = notes
        div.updatedAt = Date.now

        if dividend == nil {
            modelContext.insert(div)
        }
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    DividendListView()
}
#endif
