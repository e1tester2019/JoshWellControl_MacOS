//
//  RentalItemsViewIOS.swift
//  Josh Well Control for Mac
//
//  iOS-optimized rental items view
//

#if os(iOS)
import SwiftUI
import SwiftData

struct RentalItemsViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    let well: Well
    @Query(sort: \RentalItem.startDate, order: .reverse) private var allRentals: [RentalItem]
    @State private var showingAddSheet = false

    private var rentals: [RentalItem] {
        allRentals.filter { $0.well?.id == well.id }
    }

    private var totalCost: Double {
        rentals.reduce(0) { $0 + $1.totalCost }
    }

    var body: some View {
        List {
            // Summary Section
            if !rentals.isEmpty {
                Section {
                    HStack {
                        Text("Total Rental Cost")
                            .font(.headline)
                        Spacer()
                        Text(totalCost, format: .currency(code: "CAD"))
                            .font(.headline)
                            .monospacedDigit()
                    }
                }
            }

            // Rentals Section
            Section("Rental Items") {
                ForEach(rentals) { rental in
                    NavigationLink {
                        RentalItemDetailViewIOS(rental: rental)
                    } label: {
                        RentalRow(rental: rental)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteRental(rental)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Rental Items")
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
            AddRentalSheet(well: well, isPresented: $showingAddSheet)
        }
        .overlay {
            if rentals.isEmpty {
                ContentUnavailableView("No Rentals", systemImage: "shippingbox.circle", description: Text("Track rented equipment for this well"))
            }
        }
    }

    private func deleteRental(_ rental: RentalItem) {
        modelContext.delete(rental)
        try? modelContext.save()
    }
}

// MARK: - Rental Row

private struct RentalRow: View {
    let rental: RentalItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(rental.name)
                    .font(.headline)
                Spacer()
                Text(rental.totalCost, format: .currency(code: "CAD"))
                    .fontWeight(.medium)
            }

            HStack {
                let days = rental.totalDays
                if days > 0 {
                    Text("\(days) day\(days == 1 ? "" : "s")")
                } else if let start = rental.startDate, let end = rental.endDate {
                    Text(start, style: .date)
                    Text("-")
                    Text(end, style: .date)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Text(rental.costPerDay, format: .currency(code: "CAD"))
                Text("/day")
            }
            .font(.caption)
            .foregroundStyle(.blue)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Rental Item Detail

struct RentalItemDetailViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var rental: RentalItem
    @State private var showingAddCostSheet = false

    var body: some View {
        List {
            Section("Details") {
                TextField("Name", text: $rental.name)

                TextField("Vendor", text: Binding(
                    get: { rental.detail ?? "" },
                    set: { rental.detail = $0.isEmpty ? nil : $0 }
                ))

                HStack {
                    Text("Daily Rate")
                    Spacer()
                    TextField("Rate", value: $rental.costPerDay, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                HStack {
                    Text("Total Days")
                    Spacer()
                    Text("\(rental.totalDays)")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Date Range") {
                DatePicker("Start Date", selection: Binding(
                    get: { rental.startDate ?? Date() },
                    set: { rental.startDate = $0 }
                ), displayedComponents: .date)

                DatePicker("End Date", selection: Binding(
                    get: { rental.endDate ?? Date() },
                    set: { rental.endDate = $0 }
                ), displayedComponents: .date)
            }

            Section("Additional Costs") {
                if let costs = rental.additionalCosts, !costs.isEmpty {
                    ForEach(costs) { cost in
                        HStack {
                            Text(cost.descriptionText)
                            Spacer()
                            Text(cost.amount, format: .currency(code: "CAD"))
                        }
                    }
                    .onDelete(perform: deleteAdditionalCosts)
                }

                Button {
                    showingAddCostSheet = true
                } label: {
                    Label("Add Cost", systemImage: "plus")
                }
            }

            Section("Summary") {
                HStack {
                    Text("Base Cost")
                    Spacer()
                    Text(Double(rental.totalDays) * rental.costPerDay, format: .currency(code: "CAD"))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Additional Costs")
                    Spacer()
                    Text(rental.additionalCostsTotal, format: .currency(code: "CAD"))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Total")
                        .fontWeight(.bold)
                    Spacer()
                    Text(rental.totalCost, format: .currency(code: "CAD"))
                        .fontWeight(.bold)
                }
            }

            Section("Serial Number") {
                TextField("Serial Number", text: Binding(
                    get: { rental.serialNumber ?? "" },
                    set: { rental.serialNumber = $0.isEmpty ? nil : $0 }
                ))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(rental.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddCostSheet) {
            AddAdditionalCostSheet(rental: rental, isPresented: $showingAddCostSheet)
        }
    }

    private func deleteAdditionalCosts(at offsets: IndexSet) {
        guard var costs = rental.additionalCosts else { return }
        for index in offsets {
            let cost = costs[index]
            modelContext.delete(cost)
        }
        offsets.forEach { costs.remove(at: $0) }
        rental.additionalCosts = costs
        try? modelContext.save()
    }
}

// MARK: - Add Rental Sheet

private struct AddRentalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let well: Well
    @Binding var isPresented: Bool

    @State private var name = ""
    @State private var dailyRate: Double = 100
    @State private var usageDays: Int = 1

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)

                HStack {
                    Text("Daily Rate")
                    Spacer()
                    TextField("Rate", value: $dailyRate, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                Stepper("Usage Days: \(usageDays)", value: $usageDays, in: 1...365)
            }
            .navigationTitle("Add Rental")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addRental()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }

    private func addRental() {
        let rental = RentalItem(name: name, costPerDay: dailyRate, well: well)
        modelContext.insert(rental)
        try? modelContext.save()
    }
}

// MARK: - Add Additional Cost Sheet

private struct AddAdditionalCostSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let rental: RentalItem
    @Binding var isPresented: Bool

    @State private var description = ""
    @State private var amount: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                TextField("Description", text: $description)

                HStack {
                    Text("Amount")
                    Spacer()
                    TextField("Amount", value: $amount, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
            }
            .navigationTitle("Add Cost")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addCost()
                        dismiss()
                    }
                    .disabled(description.isEmpty || amount <= 0)
                }
            }
        }
    }

    private func addCost() {
        let cost = RentalAdditionalCost(descriptionText: description, amount: amount)
        cost.rentalItem = rental
        if rental.additionalCosts == nil { rental.additionalCosts = [] }
        rental.additionalCosts?.append(cost)
        modelContext.insert(cost)
        try? modelContext.save()
    }
}

#endif
