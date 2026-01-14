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
    @Query(filter: #Predicate<WorkDay> { $0.lineItem == nil && $0.manuallyMarkedInvoiced == false }, sort: \WorkDay.startDate) private var uninvoicedWorkDays: [WorkDay]

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
                            .id(invoice.id)  // Ensure proper refresh on data change
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
    @Query(filter: #Predicate<WorkDay> { $0.lineItem == nil && $0.manuallyMarkedInvoiced == false }, sort: \WorkDay.startDate) private var uninvoicedWorkDays: [WorkDay]

    @State private var selectedClient: Client?
    @State private var selectedWorkDays: Set<UUID> = []
    @State private var invoiceDate = Date.now
    @State private var customInvoiceNumber: String = ""
    @State private var useCustomNumber = false

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
        // Cap each day's total mileage at client max, then sum
        return selectedWorkDayObjects.reduce(0) { $0 + min($1.totalMileage, client.maxMileage) }
    }

    // Mileage totals by type (before cap)
    private var mileageByType: (toLocation: Double, fromLocation: Double, inField: Double, commute: Double) {
        let toLocation = selectedWorkDayObjects.reduce(0) { $0 + $1.mileageToLocation }
        let fromLocation = selectedWorkDayObjects.reduce(0) { $0 + $1.mileageFromLocation }
        let inField = selectedWorkDayObjects.reduce(0) { $0 + $1.mileageInField }
        let commute = selectedWorkDayObjects.reduce(0) { $0 + $1.mileageCommute }
        return (toLocation, fromLocation, inField, commute)
    }

    // Mileage grouped by well with breakdown by type
    private var mileageByWell: [(wellName: String, wellID: UUID?, toLocation: Double, fromLocation: Double, inField: Double, commute: Double)] {
        let grouped = Dictionary(grouping: selectedWorkDayObjects) { $0.well?.id }
        return grouped.map { (wellID, workDays) in
            let wellName = workDays.first?.well?.name ?? "No Well Assigned"
            let toLocation = workDays.reduce(0) { $0 + $1.mileageToLocation }
            let fromLocation = workDays.reduce(0) { $0 + $1.mileageFromLocation }
            let inField = workDays.reduce(0) { $0 + $1.mileageInField }
            let commute = workDays.reduce(0) { $0 + $1.mileageCommute }
            return (wellName, wellID, toLocation, fromLocation, inField, commute)
        }.sorted { $0.wellName < $1.wellName }
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

                Section("Invoice Details") {
                    DatePicker("Date", selection: $invoiceDate, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "en_GB"))

                    Toggle("Custom Invoice Number", isOn: $useCustomNumber)

                    if useCustomNumber {
                        HStack {
                            Text("Invoice #")
                            TextField("Number", text: $customInvoiceNumber)
                                .textFieldStyle(.roundedBorder)
                                #if os(macOS)
                                .frame(width: 100)
                                #endif
                        }
                    } else {
                        HStack {
                            Text("Invoice #")
                            Text("\(BusinessInfo.shared.nextInvoiceNumber)")
                                .foregroundStyle(.secondary)
                            Text("(auto)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
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
                        Section("Mileage Summary") {
                            if let client = selectedClient {
                                let mileage = mileageByType
                                let daysOverCap = selectedWorkDayObjects.filter { $0.totalMileage > client.maxMileage }.count

                                if mileage.toLocation > 0 {
                                    HStack {
                                        Text("To Location")
                                        Spacer()
                                        Text("\(Int(mileage.toLocation)) km")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if mileage.fromLocation > 0 {
                                    HStack {
                                        Text("From Location")
                                        Spacer()
                                        Text("\(Int(mileage.fromLocation)) km")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if mileage.inField > 0 {
                                    HStack {
                                        Text("In Field")
                                        Spacer()
                                        Text("\(Int(mileage.inField)) km")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if mileage.commute > 0 {
                                    HStack {
                                        Text("Commute")
                                        Spacer()
                                        Text("\(Int(mileage.commute)) km")
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
                                    Text("\(daysOverCap) work period(s) capped at \(Int(client.maxMileage)) km max")
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
                // Mileage by well with breakdown
                ForEach(mileageByWell, id: \.wellID) { wellMileage in
                    let wellTotal = wellMileage.toLocation + wellMileage.fromLocation + wellMileage.inField + wellMileage.commute
                    if wellTotal > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(wellMileage.wellName)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)

                            if wellMileage.toLocation > 0 {
                                HStack {
                                    Text("  To Location: \(Int(wellMileage.toLocation)) km")
                                    Spacer()
                                    Text(wellMileage.toLocation * client.mileageRate, format: .currency(code: "CAD"))
                                }
                                .foregroundStyle(.secondary)
                            }
                            if wellMileage.fromLocation > 0 {
                                HStack {
                                    Text("  From Location: \(Int(wellMileage.fromLocation)) km")
                                    Spacer()
                                    Text(wellMileage.fromLocation * client.mileageRate, format: .currency(code: "CAD"))
                                }
                                .foregroundStyle(.secondary)
                            }
                            if wellMileage.inField > 0 {
                                HStack {
                                    Text("  In Field: \(Int(wellMileage.inField)) km")
                                    Spacer()
                                    Text(wellMileage.inField * client.mileageRate, format: .currency(code: "CAD"))
                                }
                                .foregroundStyle(.secondary)
                            }
                            if wellMileage.commute > 0 {
                                HStack {
                                    Text("  Commute: \(Int(wellMileage.commute)) km")
                                    Spacer()
                                    Text(wellMileage.commute * client.mileageRate, format: .currency(code: "CAD"))
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Show total mileage summary
                if totalMileage > 0 {
                    HStack {
                        Text("Total Mileage: \(Int(totalMileage)) km")
                            .fontWeight(.medium)
                        Spacer()
                        Text(totalMileage * client.mileageRate, format: .currency(code: "CAD"))
                            .fontWeight(.medium)
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
        let invoiceNumber: Int

        if useCustomNumber, let customNum = Int(customInvoiceNumber), customNum > 0 {
            invoiceNumber = customNum
            // If custom number is >= next number, update the next number
            if customNum >= businessInfo.nextInvoiceNumber {
                businessInfo.nextInvoiceNumber = customNum + 1
                BusinessInfo.shared = businessInfo
            }
        } else {
            invoiceNumber = businessInfo.getNextInvoiceNumber()
        }

        let invoice = Invoice(invoiceNumber: invoiceNumber, client: client)
        invoice.date = invoiceDate

        // Store total mileage on invoice for reference
        let mileage = mileageByType
        invoice.mileageToLocation = mileage.toLocation
        invoice.mileageFromLocation = mileage.fromLocation

        modelContext.insert(invoice)

        if invoice.lineItems == nil { invoice.lineItems = [] }

        var sortOrder = 0

        // Group work days by well, rate, AND reason for day rate line items
        // This ensures different rates or reasons get separate line items
        struct WellRateKey: Hashable {
            let wellID: UUID?
            let rate: Double
            let reason: String
        }
        let workDaysByWellAndRate = Dictionary(grouping: selectedWorkDayObjects) { wd in
            WellRateKey(wellID: wd.well?.id, rate: wd.effectiveDayRate, reason: wd.customRateReason)
        }

        // Add mileage line items grouped by well (same structure as day rates)
        let workDaysByWell = Dictionary(grouping: selectedWorkDayObjects) { $0.well?.id }

        for (_, wellWorkDays) in workDaysByWell {
            guard let firstWorkDay = wellWorkDays.first else { continue }
            let well = firstWorkDay.well

            // Calculate mileage totals for this well
            let toLocation = wellWorkDays.reduce(0) { $0 + $1.mileageToLocation }
            let fromLocation = wellWorkDays.reduce(0) { $0 + $1.mileageFromLocation }
            let inField = wellWorkDays.reduce(0) { $0 + $1.mileageInField }
            let commute = wellWorkDays.reduce(0) { $0 + $1.mileageCommute }

            // Create line items for each mileage type for this well
            let mileageTypes: [(description: String, km: Double)] = [
                ("To Location", toLocation),
                ("From Location", fromLocation),
                ("In Field", inField),
                ("Commute", commute)
            ]

            for (typeDescription, km) in mileageTypes {
                guard km > 0 else { continue }

                let mileageItem = InvoiceLineItem(itemType: .mileage, quantity: Int(km), unitPrice: client.mileageRate)
                mileageItem.mileageDescription = typeDescription
                mileageItem.sortOrder = sortOrder
                sortOrder += 1

                // Add well info including AFE and cost code (same as day rates)
                if let well = well {
                    mileageItem.wellName = well.name
                    mileageItem.afeNumber = well.afeNumber ?? ""
                    mileageItem.rigName = well.rigName ?? ""
                    mileageItem.costCode = firstWorkDay.effectiveCostCode
                    mileageItem.well = well
                }

                mileageItem.invoice = invoice
                invoice.lineItems?.append(mileageItem)
                modelContext.insert(mileageItem)
            }
        }

        // Add day rate line items grouped by well and rate
        for (key, groupedWorkDays) in workDaysByWellAndRate {
            guard let firstWorkDay = groupedWorkDays.first else { continue }

            let totalDays = groupedWorkDays.reduce(0) { $0 + $1.dayCount }

            let dayRateItem = InvoiceLineItem(itemType: .dayRate, quantity: totalDays, unitPrice: key.rate)
            dayRateItem.sortOrder = sortOrder
            sortOrder += 1

            // Copy custom rate reason if present (all days in group have same rate/reason)
            dayRateItem.customRateReason = firstWorkDay.customRateReason

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
            for wd in groupedWorkDays {
                wd.lineItem = dayRateItem
                dayRateItem.workDays?.append(wd)
            }
        }

        try? modelContext.save()

        // Dismiss with animation to help SwiftUI update the list properly
        withAnimation {
            dismiss()
        }
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
                    if workDay.totalMileage > 0 {
                        Text("\(Int(workDay.totalMileage)) km")
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
