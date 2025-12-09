//
//  InvoiceListView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-08.
//

import SwiftUI
import SwiftData

struct InvoiceListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Invoice.invoiceNumber, order: .reverse) private var invoices: [Invoice]
    @Query(sort: \Client.companyName) private var clients: [Client]
    @Query(filter: #Predicate<WorkDay> { $0.lineItem == nil }, sort: \WorkDay.startDate) private var uninvoicedWorkDays: [WorkDay]

    @State private var showingCreateInvoice = false
    @State private var selectedInvoice: Invoice?

    private var uninvoicedDayCount: Int {
        uninvoicedWorkDays.reduce(0) { $0 + $1.dayCount }
    }

    var body: some View {
        NavigationStack {
            List {
                if !uninvoicedWorkDays.isEmpty {
                    Section {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(uninvoicedDayCount) uninvoiced day\(uninvoicedDayCount == 1 ? "" : "s")")
                                    .fontWeight(.medium)
                                Text("Create an invoice to bill for these days")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Create Invoice") {
                                showingCreateInvoice = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }

                if invoices.isEmpty && uninvoicedWorkDays.isEmpty {
                    ContentUnavailableView {
                        Label("No Invoices", systemImage: "doc.text")
                    } description: {
                        Text("Log work days first, then create invoices")
                    }
                } else {
                    ForEach(invoices) { invoice in
                        InvoiceRow(invoice: invoice)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedInvoice = invoice
                            }
                    }
                    .onDelete(perform: deleteInvoices)
                }
            }
            .navigationTitle("Invoices")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreateInvoice = true
                    } label: {
                        Label("New Invoice", systemImage: "plus")
                    }
                    .disabled(clients.isEmpty)
                }
            }
            .sheet(isPresented: $showingCreateInvoice) {
                InvoiceCreatorView()
            }
            .sheet(item: $selectedInvoice) { invoice in
                InvoiceDetailView(invoice: invoice)
            }
        }
    }

    private func deleteInvoices(at offsets: IndexSet) {
        // Get the invoice numbers being deleted
        let deletedNumbers = offsets.map { invoices[$0].invoiceNumber }

        for index in offsets {
            let invoice = invoices[index]
            // Clear references from work days
            for item in invoice.lineItems ?? [] {
                for wd in item.workDays ?? [] {
                    wd.lineItem = nil
                }
            }
            modelContext.delete(invoice)
        }

        // Rewind invoice number if we deleted the highest one
        var businessInfo = BusinessInfo.shared
        let remainingNumbers = invoices
            .filter { !deletedNumbers.contains($0.invoiceNumber) }
            .map { $0.invoiceNumber }

        if let maxRemaining = remainingNumbers.max() {
            businessInfo.nextInvoiceNumber = maxRemaining + 1
        } else if remainingNumbers.isEmpty {
            // All invoices deleted, reset to lowest deleted number
            if let minDeleted = deletedNumbers.min() {
                businessInfo.nextInvoiceNumber = minDeleted
            }
        }
        BusinessInfo.shared = businessInfo

        try? modelContext.save()
    }
}

// MARK: - Invoice Row

struct InvoiceRow: View {
    let invoice: Invoice

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Invoice #\(invoice.invoiceNumber)")
                        .fontWeight(.semibold)
                    if invoice.isPaid {
                        Label("Paid", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                if let client = invoice.client {
                    Text(client.companyName)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text(dateFormatter.string(from: invoice.date))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(invoice.total, format: .currency(code: "CAD"))
                    .fontWeight(.semibold)

                Text("\(invoice.totalDays) days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Invoice Creator

struct InvoiceCreatorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Client.companyName) private var clients: [Client]
    @Query(filter: #Predicate<WorkDay> { $0.lineItem == nil }, sort: \WorkDay.startDate) private var uninvoicedWorkDays: [WorkDay]

    @State private var selectedClient: Client?
    @State private var selectedWorkDays: Set<UUID> = []
    @State private var invoiceDate = Date.now

    private var workDaysForClient: [WorkDay] {
        guard let client = selectedClient else { return [] }
        return uninvoicedWorkDays.filter { $0.client?.id == client.id }
    }

    private var selectedWorkDayObjects: [WorkDay] {
        workDaysForClient.filter { selectedWorkDays.contains($0.id) }
    }

    private var totalDaysSelected: Int {
        selectedWorkDayObjects.reduce(0) { $0 + $1.dayCount }
    }

    private var totalMileage: Double {
        guard let client = selectedClient else { return 0 }
        // Cap each day's mileage at client max, then sum
        return selectedWorkDayObjects.reduce(0) { $0 + min($1.mileage, client.maxMileage) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Client") {
                    Picker("Client", selection: $selectedClient) {
                        Text("Select a client").tag(nil as Client?)
                        ForEach(clients) { client in
                            Text(client.companyName).tag(client as Client?)
                        }
                    }
                    .onChange(of: selectedClient) { _, newClient in
                        selectedWorkDays.removeAll()
                        if newClient != nil {
                            // Auto-select all work days for this client
                            for wd in workDaysForClient {
                                selectedWorkDays.insert(wd.id)
                            }
                        }
                    }
                }

                Section("Invoice Date") {
                    DatePicker("Date", selection: $invoiceDate, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "en_GB"))
                }

                if selectedClient != nil {
                    Section("Work Periods (\(totalDaysSelected) days selected)") {
                        if workDaysForClient.isEmpty {
                            Text("No uninvoiced work periods for this client")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(workDaysForClient) { workDay in
                                WorkDaySelectionRow(workDay: workDay, isSelected: selectedWorkDays.contains(workDay.id)) {
                                    if selectedWorkDays.contains(workDay.id) {
                                        selectedWorkDays.remove(workDay.id)
                                    } else {
                                        selectedWorkDays.insert(workDay.id)
                                    }
                                }
                            }

                            if !workDaysForClient.isEmpty {
                                HStack {
                                    Button("Select All") {
                                        for wd in workDaysForClient {
                                            selectedWorkDays.insert(wd.id)
                                        }
                                    }
                                    .buttonStyle(.bordered)

                                    Button("Clear") {
                                        selectedWorkDays.removeAll()
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }

                    if totalMileage > 0 {
                        Section("Mileage (\(selectedWorkDayObjects.filter { $0.mileage > 0 }.count) entries)") {
                            if let client = selectedClient {
                                let daysOverCap = selectedWorkDayObjects.filter { $0.mileage > client.maxMileage }.count

                                ForEach(selectedWorkDayObjects.filter { $0.mileage > 0 }.sorted { $0.startDate < $1.startDate }) { wd in
                                    let cappedKm = min(wd.mileage, client.maxMileage)
                                    HStack {
                                        VStack(alignment: .leading) {
                                            if wd.mileageDescription.isEmpty {
                                                Text("Mileage")
                                            } else {
                                                Text(wd.mileageDescription)
                                            }
                                            Text(wd.dateRangeString)
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                        Spacer()
                                        Text("\(Int(cappedKm)) km")
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Divider()

                                HStack {
                                    Text("Total")
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text("\(Int(totalMileage)) km")
                                        .fontWeight(.medium)
                                }

                                HStack {
                                    Text("Mileage cost")
                                    Spacer()
                                    Text(totalMileage * client.mileageRate, format: .currency(code: "CAD"))
                                        .fontWeight(.medium)
                                }

                                if daysOverCap > 0 {
                                    Text("\(daysOverCap) entry capped at \(Int(client.maxMileage)) km max")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }

                                Text("Rate: \(client.mileageRate, format: .currency(code: "CAD"))/km")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section("Preview") {
                        invoicePreview
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Create Invoice")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createInvoice() }
                        .disabled(selectedClient == nil || selectedWorkDays.isEmpty)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 600)
    }

    @ViewBuilder
    private var invoicePreview: some View {
        if let client = selectedClient {
            let dayRateTotal = selectedWorkDayObjects.reduce(0.0) { $0 + $1.totalEarnings }
            // totalMileage is already capped per day
            let mileageTotal = totalMileage * client.mileageRate
            let subtotal = dayRateTotal + mileageTotal
            let gst = subtotal * 0.05

            VStack(alignment: .leading, spacing: 8) {
                // Individual mileage entries
                ForEach(selectedWorkDayObjects.filter { $0.mileage > 0 }.sorted { $0.startDate < $1.startDate }) { wd in
                    let cappedKm = min(wd.mileage, client.maxMileage)
                    HStack {
                        if wd.mileageDescription.isEmpty {
                            Text("Mileage (\(Int(cappedKm)) km)")
                        } else {
                            Text("\(wd.mileageDescription) (\(Int(cappedKm)) km)")
                        }
                        Spacer()
                        Text(cappedKm * client.mileageRate, format: .currency(code: "CAD"))
                    }
                    .foregroundStyle(.secondary)
                }

                HStack {
                    Text("\(totalDaysSelected) days")
                    Spacer()
                    Text(dayRateTotal, format: .currency(code: "CAD"))
                }

                Divider()

                HStack {
                    Text("Subtotal")
                    Spacer()
                    Text(subtotal, format: .currency(code: "CAD"))
                }

                HStack {
                    Text("GST (5%)")
                    Spacer()
                    Text(gst, format: .currency(code: "CAD"))
                }

                Divider()

                HStack {
                    Text("Total")
                        .fontWeight(.bold)
                    Spacer()
                    Text(subtotal + gst, format: .currency(code: "CAD"))
                        .fontWeight(.bold)
                }
            }
            .font(.callout)
        }
    }

    private func createInvoice() {
        guard let client = selectedClient, !selectedWorkDays.isEmpty else { return }

        var businessInfo = BusinessInfo.shared
        let invoiceNumber = businessInfo.getNextInvoiceNumber()

        let invoice = Invoice(invoiceNumber: invoiceNumber, client: client)
        invoice.date = invoiceDate

        // Store total mileage on invoice for reference
        invoice.mileageToLocation = totalMileage
        invoice.mileageFromLocation = 0

        modelContext.insert(invoice)

        if invoice.lineItems == nil { invoice.lineItems = [] }

        var sortOrder = 0

        // Group work days by well for day rate line items
        let workDaysByWell = Dictionary(grouping: selectedWorkDayObjects) { $0.well?.id }

        // Add individual mileage line items for each work day with mileage
        for workDay in selectedWorkDayObjects.sorted(by: { $0.startDate < $1.startDate }) {
            guard workDay.mileage > 0 else { continue }

            let cappedMileage = min(workDay.mileage, client.maxMileage)
            let mileageItem = InvoiceLineItem(itemType: .mileage, quantity: Int(cappedMileage), unitPrice: client.mileageRate)
            mileageItem.mileageDescription = workDay.mileageDescription
            mileageItem.sortOrder = sortOrder
            sortOrder += 1

            if let well = workDay.well {
                mileageItem.wellName = well.name
                mileageItem.afeNumber = well.afeNumber ?? ""
                mileageItem.rigName = well.rigName ?? ""
                mileageItem.costCode = workDay.effectiveCostCode
                mileageItem.well = well
            }

            mileageItem.invoice = invoice
            invoice.lineItems?.append(mileageItem)
            modelContext.insert(mileageItem)
        }

        // Add day rate line items grouped by well
        for (_, wellWorkDays) in workDaysByWell {
            guard let firstWorkDay = wellWorkDays.first else { continue }

            let totalDays = wellWorkDays.reduce(0) { $0 + $1.dayCount }
            let totalEarnings = wellWorkDays.reduce(0.0) { $0 + $1.totalEarnings }
            let avgRate = totalEarnings / Double(totalDays)

            let dayRateItem = InvoiceLineItem(itemType: .dayRate, quantity: totalDays, unitPrice: avgRate)
            dayRateItem.sortOrder = sortOrder
            sortOrder += 1

            if let well = firstWorkDay.well {
                dayRateItem.wellName = well.name
                dayRateItem.afeNumber = well.afeNumber ?? ""
                dayRateItem.rigName = well.rigName ?? ""
                dayRateItem.costCode = firstWorkDay.effectiveCostCode
                dayRateItem.well = well
            }

            dayRateItem.invoice = invoice
            invoice.lineItems?.append(dayRateItem)
            modelContext.insert(dayRateItem)

            // Link work days to this line item
            if dayRateItem.workDays == nil { dayRateItem.workDays = [] }
            for wd in wellWorkDays {
                wd.lineItem = dayRateItem
                dayRateItem.workDays?.append(wd)
            }
        }

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Work Day Selection Row

struct WorkDaySelectionRow: View {
    let workDay: WorkDay
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)

                VStack(alignment: .leading) {
                    HStack {
                        Text(workDay.dateRangeString)
                        if workDay.dayCount > 1 {
                            Text("(\(workDay.dayCount) days)")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    if let well = workDay.well {
                        Text(well.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text(workDay.totalEarnings, format: .currency(code: "CAD"))
                        .foregroundStyle(.secondary)
                    if workDay.mileage > 0 {
                        HStack(spacing: 4) {
                            Text("\(Int(workDay.mileage)) km")
                            if !workDay.mileageDescription.isEmpty {
                                Text("(\(workDay.mileageDescription))")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    InvoiceListView()
}
