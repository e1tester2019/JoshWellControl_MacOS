//
//  DividendListViewIOS.swift
//  Josh Well Control for Mac
//
//  iOS-optimized dividend views
//

#if os(iOS)
import SwiftUI
import SwiftData

struct DividendListViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Dividend.paymentDate, order: .reverse) private var dividends: [Dividend]
    @Query(sort: \Shareholder.lastName) private var shareholders: [Shareholder]
    @State private var showingAddSheet = false
    @State private var selectedTab = 0
    @State private var showingAddShareholderSheet = false

    var body: some View {
        TabView(selection: $selectedTab) {
            // Dividends
            dividendsList
                .tabItem {
                    Label("Dividends", systemImage: "dollarsign.circle")
                }
                .tag(0)

            // Shareholders
            shareholdersList
                .tabItem {
                    Label("Shareholders", systemImage: "person.2.circle")
                }
                .tag(1)
        }
        .navigationTitle("Dividends")
    }

    // MARK: - Dividends List

    private var dividendsList: some View {
        List {
            // Summary
            if !dividends.isEmpty {
                Section {
                    HStack {
                        Text("Total Dividends")
                            .font(.headline)
                        Spacer()
                        Text(totalDividends, format: .currency(code: "CAD"))
                            .font(.headline)
                            .monospacedDigit()
                    }
                }
            }

            // Dividends
            Section("Dividend Payments") {
                ForEach(dividends) { dividend in
                    NavigationLink {
                        DividendDetailViewIOS(dividend: dividend)
                    } label: {
                        DividendRowIOS(dividend: dividend)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            modelContext.delete(dividend)
                            try? modelContext.save()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddDividendSheetIOS(isPresented: $showingAddSheet)
        }
        .overlay {
            if dividends.isEmpty {
                ContentUnavailableView("No Dividends", systemImage: "dollarsign.circle", description: Text("Record dividend payments"))
            }
        }
    }

    private var totalDividends: Double {
        dividends.reduce(0) { $0 + $1.amount }
    }

    // MARK: - Shareholders List

    private var shareholdersList: some View {
        List {
            ForEach(shareholders) { shareholder in
                NavigationLink {
                    ShareholderDetailViewIOS(shareholder: shareholder)
                } label: {
                    ShareholderRowIOS(shareholder: shareholder)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        modelContext.delete(shareholder)
                        try? modelContext.save()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddShareholderSheet = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showingAddShareholderSheet) {
            AddShareholderSheetIOS(isPresented: $showingAddShareholderSheet)
        }
        .overlay {
            if shareholders.isEmpty {
                ContentUnavailableView("No Shareholders", systemImage: "person.2.badge.plus", description: Text("Add shareholders to record dividends"))
            }
        }
    }
}

// MARK: - Dividend Row

private struct DividendRowIOS: View {
    let dividend: Dividend

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(dividend.shareholder?.fullName ?? "Unknown")
                    .font(.headline)
                Spacer()
                Text(dividend.amount, format: .currency(code: "CAD"))
                    .fontWeight(.medium)
            }

            HStack {
                Text(dividend.paymentDate, style: .date)
                Text("•")
                Text(dividend.dividendType.shortName)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if dividend.isPaid {
                Text("Paid")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2))
                    .foregroundStyle(.green)
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Dividend Detail

struct DividendDetailViewIOS: View {
    @Bindable var dividend: Dividend

    var body: some View {
        List {
            Section("Details") {
                HStack {
                    Text("Shareholder")
                    Spacer()
                    Text(dividend.shareholder?.fullName ?? "None")
                        .foregroundStyle(.secondary)
                }

                DatePicker("Payment Date", selection: $dividend.paymentDate, displayedComponents: .date)

                HStack {
                    Text("Amount")
                    Spacer()
                    TextField("Amount", value: $dividend.amount, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                Picker("Type", selection: $dividend.dividendType) {
                    Text("Eligible").tag(DividendType.eligible)
                    Text("Non-Eligible").tag(DividendType.nonEligible)
                }

                Toggle("Paid", isOn: $dividend.isPaid)
            }

            Section("Tax Information") {
                HStack {
                    Text("Grossed-Up Amount")
                    Spacer()
                    Text(dividend.grossedUpAmount, format: .currency(code: "CAD"))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Federal Tax Credit")
                    Spacer()
                    Text(dividend.federalTaxCredit, format: .currency(code: "CAD"))
                        .foregroundStyle(.green)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Dividend")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Shareholder Row

private struct ShareholderRowIOS: View {
    let shareholder: Shareholder

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(shareholder.fullName)
                .font(.headline)

            HStack {
                Text("\(shareholder.ownershipPercent, specifier: "%.1f")%")
                    .foregroundStyle(.blue)
                Text("ownership")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Shareholder Detail

struct ShareholderDetailViewIOS: View {
    @Bindable var shareholder: Shareholder

    var body: some View {
        Form {
            Section("Personal") {
                TextField("First Name", text: $shareholder.firstName)
                TextField("Last Name", text: $shareholder.lastName)
                TextField("SIN", text: $shareholder.sinNumber)
                    .keyboardType(.numberPad)
            }

            Section("Address") {
                TextField("Address", text: $shareholder.address)
                TextField("City", text: $shareholder.city)
                Picker("Province", selection: $shareholder.province) {
                    ForEach(Province.allCases, id: \.self) { province in
                        Text(province.rawValue).tag(province)
                    }
                }
                TextField("Postal Code", text: $shareholder.postalCode)
            }

            Section("Ownership") {
                HStack {
                    Text("Ownership %")
                    Spacer()
                    TextField("%", value: $shareholder.ownershipPercent, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("%")
                        .foregroundStyle(.secondary)
                }

                Toggle("Active", isOn: $shareholder.isActive)
            }

            Section("Dividends") {
                if let dividends = shareholder.dividends, !dividends.isEmpty {
                    let total = dividends.reduce(0) { $0 + $1.amount }
                    HStack {
                        Text("Total Dividends")
                        Spacer()
                        Text(total, format: .currency(code: "CAD"))
                            .fontWeight(.medium)
                    }

                    ForEach(dividends.sorted { $0.paymentDate > $1.paymentDate }) { dividend in
                        HStack {
                            Text(dividend.paymentDate, style: .date)
                            Spacer()
                            Text(dividend.amount, format: .currency(code: "CAD"))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No dividends recorded")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(shareholder.fullName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Add Dividend Sheet

private struct AddDividendSheetIOS: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Shareholder.lastName) private var shareholders: [Shareholder]
    @Binding var isPresented: Bool

    @State private var selectedShareholder: Shareholder?
    @State private var amount: Double = 0
    @State private var paymentDate = Date()
    @State private var dividendType: DividendType = .eligible

    var body: some View {
        NavigationStack {
            Form {
                Picker("Shareholder", selection: $selectedShareholder) {
                    Text("Select Shareholder").tag(nil as Shareholder?)
                    ForEach(shareholders) { shareholder in
                        Text(shareholder.fullName).tag(shareholder as Shareholder?)
                    }
                }

                HStack {
                    Text("Amount")
                    Spacer()
                    TextField("Amount", value: $amount, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                DatePicker("Payment Date", selection: $paymentDate, displayedComponents: .date)

                Picker("Type", selection: $dividendType) {
                    Text("Eligible").tag(DividendType.eligible)
                    Text("Non-Eligible").tag(DividendType.nonEligible)
                }
            }
            .navigationTitle("Add Dividend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addDividend()
                        dismiss()
                    }
                    .disabled(selectedShareholder == nil || amount <= 0)
                }
            }
        }
    }

    private func addDividend() {
        let dividend = Dividend(amount: amount, shareholder: selectedShareholder)
        dividend.paymentDate = paymentDate
        dividend.dividendType = dividendType
        modelContext.insert(dividend)
        try? modelContext.save()
    }
}

// MARK: - Add Shareholder Sheet

private struct AddShareholderSheetIOS: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var ownershipPercent: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                TextField("First Name", text: $firstName)
                TextField("Last Name", text: $lastName)

                HStack {
                    Text("Ownership %")
                    Spacer()
                    TextField("%", value: $ownershipPercent, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("%")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Shareholder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addShareholder()
                        dismiss()
                    }
                    .disabled(firstName.isEmpty && lastName.isEmpty)
                }
            }
        }
    }

    private func addShareholder() {
        let shareholder = Shareholder(firstName: firstName, lastName: lastName)
        shareholder.ownershipPercent = ownershipPercent
        modelContext.insert(shareholder)
        try? modelContext.save()
    }
}

#endif
