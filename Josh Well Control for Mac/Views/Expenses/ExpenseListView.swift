//
//  ExpenseListView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-08.
//

#if os(macOS)
import SwiftUI
import SwiftData

struct ExpenseListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]

    @State private var showingAddSheet = false
    @State private var selectedExpense: Expense?

    // Search and Filters
    @State private var searchText = ""
    @State private var filterCategory: ExpenseCategory?
    @State private var filterProvince: Province?
    @State private var filterStartDate: Date?
    @State private var filterEndDate: Date?
    @State private var filterReimbursable: ReimbursableFilter = .all
    @State private var showFilters = false

    enum ReimbursableFilter: String, CaseIterable {
        case all = "All"
        case reimbursable = "Reimbursable"
        case reimbursed = "Reimbursed"
        case pendingReimbursement = "Pending"
        case personal = "Personal"
    }

    private var filteredExpenses: [Expense] {
        let searchLower = searchText.lowercased()

        return expenses.filter { expense in
            // Text search filter
            if !searchText.isEmpty {
                let vendorMatch = expense.vendor.lowercased().contains(searchLower)
                let descMatch = expense.expenseDescription.lowercased().contains(searchLower)
                if !vendorMatch && !descMatch {
                    return false
                }
            }
            // Category filter
            if let cat = filterCategory, expense.category != cat {
                return false
            }
            // Province filter
            if let prov = filterProvince, expense.province != prov {
                return false
            }
            // Reimbursable filter
            switch filterReimbursable {
            case .all:
                break
            case .reimbursable:
                if !expense.isReimbursable { return false }
            case .reimbursed:
                if !expense.isReimbursed { return false }
            case .pendingReimbursement:
                if !expense.isReimbursable || expense.isReimbursed { return false }
            case .personal:
                if expense.isReimbursable { return false }
            }
            // Date range filter
            if let start = filterStartDate, expense.date < start {
                return false
            }
            if let end = filterEndDate, expense.date > end {
                return false
            }
            return true
        }
    }

    private var hasActiveFilters: Bool {
        !searchText.isEmpty || filterCategory != nil || filterProvince != nil || filterReimbursable != .all || filterStartDate != nil || filterEndDate != nil
    }

    private var groupedExpenses: [String: [Expense]] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return Dictionary(grouping: filteredExpenses) { formatter.string(from: $0.date) }
    }

    private var totalFiltered: Double {
        filteredExpenses.reduce(0) { $0 + $1.totalAmount }
    }

    var body: some View {
        NavigationStack {
            List {
                // Add Expense Section
                Section {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("Add New Expense", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                // Search and Filter section
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search vendor or description", text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    DisclosureGroup(isExpanded: $showFilters) {
                        Picker("Category", selection: $filterCategory) {
                            Text("All Categories").tag(nil as ExpenseCategory?)
                            ForEach(ExpenseCategory.allCases, id: \.self) { cat in
                                Label(cat.rawValue, systemImage: cat.icon).tag(cat as ExpenseCategory?)
                            }
                        }
                        .controlSize(.small)

                        Picker("Province", selection: $filterProvince) {
                            Text("All Provinces").tag(nil as Province?)
                            ForEach(Province.allCases, id: \.self) { prov in
                                Text(prov.rawValue).tag(prov as Province?)
                            }
                        }
                        .controlSize(.small)

                        Picker("Reimbursement", selection: $filterReimbursable) {
                            ForEach(ReimbursableFilter.allCases, id: \.self) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .controlSize(.small)

                        HStack {
                            DatePicker("From", selection: Binding(
                                get: { filterStartDate ?? Date.distantPast },
                                set: { filterStartDate = $0 }
                            ), displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "en_GB"))
                            .controlSize(.small)

                            Button {
                                filterStartDate = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .opacity(filterStartDate == nil ? 0 : 1)
                        }

                        HStack {
                            DatePicker("To", selection: Binding(
                                get: { filterEndDate ?? Date.now },
                                set: { filterEndDate = $0 }
                            ), displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "en_GB"))
                            .controlSize(.small)

                            Button {
                                filterEndDate = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .opacity(filterEndDate == nil ? 0 : 1)
                        }

                        if hasActiveFilters {
                            HStack {
                                Button("Clear Filters") {
                                    filterCategory = nil
                                    filterProvince = nil
                                    filterReimbursable = .all
                                    filterStartDate = nil
                                    filterEndDate = nil
                                }

                                Spacer()

                                Text("Total: \(totalFiltered, format: .currency(code: "CAD"))")
                                    .fontWeight(.medium)
                            }
                        }
                    } label: {
                        HStack {
                            Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                            if hasActiveFilters {
                                Spacer()
                                Text("\(filteredExpenses.count) of \(expenses.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if expenses.isEmpty {
                    ContentUnavailableView {
                        Label("No Expenses", systemImage: "dollarsign.circle")
                    } description: {
                        Text("Track your business expenses here")
                    } actions: {
                        Button("Add Expense") {
                            showingAddSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if filteredExpenses.isEmpty {
                    ContentUnavailableView {
                        Label("No Matches", systemImage: "magnifyingglass")
                    } description: {
                        Text("No expenses match your filters")
                    } actions: {
                        Button("Clear Filters") {
                            searchText = ""
                            filterCategory = nil
                            filterProvince = nil
                            filterReimbursable = .all
                            filterStartDate = nil
                            filterEndDate = nil
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    // Group by month
                    ForEach(groupedExpenses.keys.sorted().reversed(), id: \.self) { monthKey in
                        Section {
                            ForEach(groupedExpenses[monthKey] ?? []) { expense in
                                ExpenseRow(expense: expense)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedExpense = expense
                                    }
                                    .contextMenu {
                                        Button {
                                            selectedExpense = expense
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }

                                        if expense.isReimbursable && !expense.isReimbursed {
                                            Button {
                                                expense.isReimbursed = true
                                                expense.reimbursedDate = Date.now
                                                try? modelContext.save()
                                            } label: {
                                                Label("Mark Reimbursed", systemImage: "checkmark.circle")
                                            }
                                        }

                                        Divider()

                                        Button(role: .destructive) {
                                            modelContext.delete(expense)
                                            try? modelContext.save()
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                            .onDelete { indexSet in
                                deleteExpenses(at: indexSet, in: monthKey)
                            }
                        } header: {
                            HStack {
                                Text(monthKey)
                                Spacer()
                                let monthTotal = (groupedExpenses[monthKey] ?? []).reduce(0) { $0 + $1.totalAmount }
                                Text(monthTotal, format: .currency(code: "CAD"))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Expenses")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("Add Expense", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                ExpenseEditorView(expense: nil)
            }
            .sheet(item: $selectedExpense) { expense in
                ExpenseEditorView(expense: expense)
            }
        }
    }

    private func deleteExpenses(at offsets: IndexSet, in monthKey: String) {
        guard let expensesInMonth = groupedExpenses[monthKey] else { return }
        for index in offsets {
            let expense = expensesInMonth[index]
            modelContext.delete(expense)
        }
        try? modelContext.save()
    }
}

// MARK: - Expense Row

struct ExpenseRow: View {
    let expense: Expense

    var body: some View {
        HStack {
            // Category icon
            Image(systemName: expense.category.icon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(expense.vendor.isEmpty ? expense.category.rawValue : expense.vendor)
                        .fontWeight(.medium)

                    if expense.hasReceipt {
                        Image(systemName: "paperclip")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Text(expense.displayDate)
                    Text(expense.province.shortName)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(expense.province == .bc ? Color.blue.opacity(0.2) : Color.orange.opacity(0.2))
                        .cornerRadius(4)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !expense.expenseDescription.isEmpty {
                    Text(expense.expenseDescription)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(expense.totalAmount, format: .currency(code: "CAD"))
                    .fontWeight(.semibold)

                if expense.isReimbursable {
                    if expense.isReimbursed {
                        Label("Reimbursed", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Label("Pending", systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ExpenseListView()
}
#endif
