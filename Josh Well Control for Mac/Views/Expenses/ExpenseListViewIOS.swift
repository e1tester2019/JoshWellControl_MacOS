//
//  ExpenseListViewIOS.swift
//  Josh Well Control for Mac
//
//  iOS-optimized expense tracking views
//

#if os(iOS)
import SwiftUI
import SwiftData
import PhotosUI

struct ExpenseListViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var showingAddSheet = false
    @State private var filterCategory: ExpenseCategory?
    @State private var showReimbursableOnly = false

    private var filteredExpenses: [Expense] {
        var result = expenses

        if let category = filterCategory {
            result = result.filter { $0.category == category }
        }

        if showReimbursableOnly {
            result = result.filter { $0.isReimbursable && !$0.isReimbursed }
        }

        return result
    }

    private var totalAmount: Double {
        filteredExpenses.reduce(0) { $0 + $1.totalAmount }
    }

    var body: some View {
        List {
            // Summary Section
            Section {
                HStack {
                    Text("Total")
                        .font(.headline)
                    Spacer()
                    Text(totalAmount, format: .currency(code: "CAD"))
                        .font(.headline)
                        .monospacedDigit()
                }

                if showReimbursableOnly {
                    HStack {
                        Text("Unreimbursed")
                        Spacer()
                        Text("\(filteredExpenses.count)")
                            .foregroundStyle(.orange)
                    }
                }
            }

            // Filter Section
            Section("Filters") {
                Picker("Category", selection: $filterCategory) {
                    Text("All Categories").tag(nil as ExpenseCategory?)
                    ForEach(ExpenseCategory.allCases, id: \.self) { category in
                        Text(category.rawValue).tag(category as ExpenseCategory?)
                    }
                }

                Toggle("Show Unreimbursed Only", isOn: $showReimbursableOnly)
            }

            // Expenses Section
            Section("Expenses") {
                ForEach(filteredExpenses) { expense in
                    NavigationLink {
                        ExpenseDetailViewIOS(expense: expense)
                    } label: {
                        ExpenseRowIOS(expense: expense)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            modelContext.delete(expense)
                            try? modelContext.save()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if expense.isReimbursable && !expense.isReimbursed {
                            Button {
                                expense.isReimbursed = true
                                expense.reimbursedDate = Date.now
                                try? modelContext.save()
                            } label: {
                                Label("Mark Reimbursed", systemImage: "checkmark.circle")
                            }
                            .tint(.green)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Expenses")
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
            AddExpenseSheetIOS(isPresented: $showingAddSheet)
        }
    }
}

// MARK: - Expense Row

private struct ExpenseRowIOS: View {
    let expense: Expense

    var body: some View {
        HStack {
            // Category icon
            Image(systemName: expense.category.icon)
                .foregroundStyle(categoryColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(expense.vendor.isEmpty ? expense.category.rawValue : expense.vendor)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if expense.isReimbursable && !expense.isReimbursed {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    if expense.isReimbursed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }

                HStack {
                    Text(expense.date, style: .date)
                    if !expense.expenseDescription.isEmpty {
                        Text("•")
                        Text(expense.expenseDescription)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(expense.totalAmount, format: .currency(code: "CAD"))
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }

    private var categoryColor: Color {
        switch expense.category {
        case .fuel: return .orange
        case .meals: return .green
        case .lodging: return .purple
        case .vehicleMaintenance: return .gray
        case .toolsEquipment: return .blue
        case .officeSupplies: return .cyan
        case .phone: return .pink
        case .professionalServices: return .indigo
        case .insurance: return .teal
        case .travel: return .mint
        case .clothing: return .brown
        case .training: return .yellow
        case .subscriptions: return .red
        case .other: return .secondary
        }
    }
}

// MARK: - Expense Detail

struct ExpenseDetailViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var expense: Expense
    @State private var showingImagePicker = false
    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        Form {
            Section("Details") {
                Picker("Category", selection: $expense.category) {
                    ForEach(ExpenseCategory.allCases, id: \.self) { category in
                        Text(category.rawValue).tag(category)
                    }
                }

                TextField("Vendor", text: $expense.vendor)

                DatePicker("Date", selection: $expense.date, displayedComponents: .date)

                HStack {
                    Text("Amount")
                    Spacer()
                    TextField("Amount", value: $expense.amount, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
            }

            Section("Description") {
                TextEditor(text: $expense.expenseDescription)
                    .frame(minHeight: 80)
            }

            Section("Tax") {
                Picker("Province", selection: $expense.province) {
                    ForEach(Province.allCases, id: \.self) { province in
                        Text(province.rawValue).tag(province)
                    }
                }

                Toggle("Tax Included", isOn: $expense.taxIncludedInAmount)

                HStack {
                    Text("GST")
                    Spacer()
                    Text(expense.calculatedGST, format: .currency(code: "CAD"))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("PST")
                    Spacer()
                    Text(expense.calculatedPST, format: .currency(code: "CAD"))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Reimbursement") {
                Toggle("Reimbursable", isOn: $expense.isReimbursable)

                if expense.isReimbursable {
                    Toggle("Reimbursed", isOn: $expense.isReimbursed)
                }
            }

            Section("Receipt") {
                if let receiptData = expense.receiptImageData,
                   let uiImage = UIImage(data: receiptData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .cornerRadius(8)

                    Button(role: .destructive) {
                        expense.receiptImageData = nil
                    } label: {
                        Label("Remove Receipt", systemImage: "trash")
                    }
                }

                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label(expense.receiptImageData == nil ? "Add Receipt" : "Replace Receipt", systemImage: "camera")
                }
                .onChange(of: selectedItem) { _, item in
                    Task {
                        if let data = try? await item?.loadTransferable(type: Data.self) {
                            expense.receiptImageData = data
                        }
                    }
                }
            }
        }
        .navigationTitle("Expense")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Add Expense Sheet

private struct AddExpenseSheetIOS: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool

    @State private var category: ExpenseCategory = .other
    @State private var vendor = ""
    @State private var amount: Double = 0
    @State private var date = Date()
    @State private var isReimbursable = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Category", selection: $category) {
                    ForEach(ExpenseCategory.allCases, id: \.self) { cat in
                        Text(cat.rawValue).tag(cat)
                    }
                }

                TextField("Vendor", text: $vendor)

                HStack {
                    Text("Amount")
                    Spacer()
                    TextField("Amount", value: $amount, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                DatePicker("Date", selection: $date, displayedComponents: .date)

                Toggle("Reimbursable", isOn: $isReimbursable)
            }
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addExpense()
                        dismiss()
                    }
                    .disabled(amount <= 0)
                }
            }
        }
    }

    private func addExpense() {
        let expense = Expense(date: date, amount: amount, category: category)
        expense.vendor = vendor
        expense.isReimbursable = isReimbursable
        expense.calculateTaxes()
        modelContext.insert(expense)
        try? modelContext.save()
    }
}

// MARK: - Mileage Log View

struct MileageLogViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MileageLog.date, order: .reverse) private var logs: [MileageLog]
    @State private var showingAddSheet = false

    private var totalDistance: Double {
        logs.reduce(0) { $0 + $1.effectiveDistance }
    }

    private var totalDeduction: Double {
        MileageSummary.calculateDeduction(totalKm: totalDistance)
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Total Distance")
                    Spacer()
                    Text("\(totalDistance, format: .number) km")
                        .fontWeight(.medium)
                }

                HStack {
                    Text("Estimated Deduction")
                    Spacer()
                    Text(totalDeduction, format: .currency(code: "CAD"))
                        .fontWeight(.medium)
                }
            }

            Section("Logs") {
                ForEach(logs) { log in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(log.purpose.isEmpty ? "Trip" : log.purpose)
                                .font(.subheadline)
                            HStack {
                                Text(log.date, style: .date)
                                if !log.locationString.isEmpty {
                                    Text("•")
                                    Text(log.locationString)
                                        .lineLimit(1)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(log.effectiveDistance, format: .number) km")
                            if log.isRoundTrip {
                                Text("Round trip")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            modelContext.delete(log)
                            try? modelContext.save()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Mileage Log")
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
            AddMileageSheetIOS(isPresented: $showingAddSheet)
        }
    }
}

// MARK: - Add Mileage Sheet

private struct AddMileageSheetIOS: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool

    @State private var distance: Double = 0
    @State private var purpose = ""
    @State private var startLocation = ""
    @State private var endLocation = ""
    @State private var date = Date()
    @State private var isRoundTrip = false

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    Text("Distance")
                    Spacer()
                    TextField("km", value: $distance, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("km")
                        .foregroundStyle(.secondary)
                }

                Toggle("Round Trip", isOn: $isRoundTrip)

                TextField("Purpose", text: $purpose)
                TextField("Start Location", text: $startLocation)
                TextField("End Location", text: $endLocation)

                DatePicker("Date", selection: $date, displayedComponents: .date)
            }
            .navigationTitle("Add Mileage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addLog()
                        dismiss()
                    }
                    .disabled(distance <= 0)
                }
            }
        }
    }

    private func addLog() {
        let log = MileageLog(date: date, distance: distance)
        log.purpose = purpose
        log.startLocation = startLocation
        log.endLocation = endLocation
        log.isRoundTrip = isRoundTrip
        modelContext.insert(log)
        try? modelContext.save()
    }
}

#endif
