//
//  WorkTrackingContainerViewIOS.swift
//  Josh Well Control for Mac
//
//  iOS-optimized work tracking views
//

#if os(iOS)
import SwiftUI
import SwiftData
import LocalAuthentication

struct WorkTrackingContainerViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isAuthenticated = false
    @State private var showingPinEntry = false
    @State private var enteredPin = ""
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if isAuthenticated || !WorkTrackingAuth.hasPin {
                mainContent
            } else {
                lockedContent
            }
        }
        .onAppear {
            if !WorkTrackingAuth.hasPin {
                isAuthenticated = true
            }
        }
        .sheet(isPresented: $showingPinEntry) {
            PinEntrySheetIOS(enteredPin: $enteredPin, isAuthenticated: $isAuthenticated, isPresented: $showingPinEntry)
        }
    }

    private var mainContent: some View {
        TabView(selection: $selectedTab) {
            // Work Days
            workDaysList
                .tabItem {
                    Label("Work Days", systemImage: "calendar")
                }
                .tag(0)

            // Invoices
            invoicesList
                .tabItem {
                    Label("Invoices", systemImage: "doc.text")
                }
                .tag(1)

            // Clients
            clientsList
                .tabItem {
                    Label("Clients", systemImage: "person.2")
                }
                .tag(2)
        }
        .navigationTitle("Work Tracking")
    }

    private var lockedContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Work Tracking Locked")
                .font(.title2)
                .fontWeight(.medium)

            Text("Enter PIN or use biometrics to access")
                .foregroundStyle(.secondary)

            Button {
                authenticateWithBiometrics()
            } label: {
                Label("Unlock with Face ID", systemImage: "faceid")
            }
            .buttonStyle(.borderedProminent)

            Button("Enter PIN") {
                showingPinEntry = true
            }
        }
        .padding()
    }

    private func authenticateWithBiometrics() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock Work Tracking") { success, _ in
                DispatchQueue.main.async {
                    if success {
                        isAuthenticated = true
                    }
                }
            }
        } else {
            // Biometrics not available, show PIN entry
            showingPinEntry = true
        }
    }

    // MARK: - Work Days Tab

    @Query(sort: \WorkDay.startDate, order: .reverse) private var workDays: [WorkDay]
    @State private var showingAddWorkDay = false

    private var workDaysList: some View {
        List {
            ForEach(workDays) { workDay in
                NavigationLink {
                    WorkDayDetailViewIOS(workDay: workDay)
                } label: {
                    WorkDayRowIOS(workDay: workDay)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        modelContext.delete(workDay)
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
                    showingAddWorkDay = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddWorkDay) {
            AddWorkDaySheetIOS(isPresented: $showingAddWorkDay)
        }
        .overlay {
            if workDays.isEmpty {
                ContentUnavailableView("No Work Days", systemImage: "calendar.badge.plus", description: Text("Track your work days"))
            }
        }
    }

    // MARK: - Invoices Tab

    @Query(sort: \Invoice.date, order: .reverse) private var invoices: [Invoice]
    @State private var showingAddInvoice = false

    private var invoicesList: some View {
        List {
            ForEach(invoices) { invoice in
                NavigationLink {
                    InvoiceDetailViewIOS(invoice: invoice)
                } label: {
                    InvoiceRowIOS(invoice: invoice)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        modelContext.delete(invoice)
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
                    showingAddInvoice = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddInvoice) {
            AddInvoiceSheetIOS(isPresented: $showingAddInvoice)
        }
        .overlay {
            if invoices.isEmpty {
                ContentUnavailableView("No Invoices", systemImage: "doc.badge.plus", description: Text("Create invoices for your work"))
            }
        }
    }

    // MARK: - Clients Tab

    @Query(sort: \Client.companyName) private var clients: [Client]
    @State private var showingAddClient = false

    private var clientsList: some View {
        List {
            ForEach(clients) { client in
                NavigationLink {
                    ClientDetailViewIOS(client: client)
                } label: {
                    ClientRowIOS(client: client)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        modelContext.delete(client)
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
                    showingAddClient = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showingAddClient) {
            AddClientSheetIOS(isPresented: $showingAddClient)
        }
        .overlay {
            if clients.isEmpty {
                ContentUnavailableView("No Clients", systemImage: "person.badge.plus", description: Text("Add clients to track work"))
            }
        }
    }
}

// MARK: - PIN Entry Sheet

private struct PinEntrySheetIOS: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var enteredPin: String
    @Binding var isAuthenticated: Bool
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            Form {
                SecureField("Enter PIN", text: $enteredPin)
                    .keyboardType(.numberPad)

                Button("Unlock") {
                    if WorkTrackingAuth.verifyPin(enteredPin) {
                        isAuthenticated = true
                        enteredPin = ""
                        dismiss()
                    }
                }
                .disabled(enteredPin.isEmpty)
            }
            .navigationTitle("Enter PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        enteredPin = ""
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Work Day Row

private struct WorkDayRowIOS: View {
    let workDay: WorkDay

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(workDay.dateRangeString)
                    .font(.headline)
                Spacer()
                Text(workDay.totalEarnings, format: .currency(code: "CAD"))
                    .fontWeight(.medium)
            }

            HStack {
                if let client = workDay.client {
                    Text(client.companyName)
                }
                if let well = workDay.well {
                    Text("•")
                    Text(well.name)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Text("\(workDay.dayCount) day\(workDay.dayCount == 1 ? "" : "s")")
                Text("@")
                Text(workDay.effectiveDayRate, format: .currency(code: "CAD"))
                    .foregroundStyle(.blue)
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Work Day Detail

struct WorkDayDetailViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var workDay: WorkDay
    @Query(sort: \Client.companyName) private var clients: [Client]

    var body: some View {
        Form {
            Section("Dates") {
                DatePicker("Start Date", selection: $workDay.startDate, displayedComponents: .date)
                DatePicker("End Date", selection: $workDay.endDate, displayedComponents: .date)

                HStack {
                    Text("Days")
                    Spacer()
                    Text("\(workDay.dayCount)")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Client & Well") {
                Picker("Client", selection: Binding(
                    get: { workDay.client },
                    set: { workDay.client = $0 }
                )) {
                    Text("No Client").tag(nil as Client?)
                    ForEach(clients) { client in
                        Text(client.companyName).tag(client as Client?)
                    }
                }

                if let well = workDay.well {
                    HStack {
                        Text("Well")
                        Spacer()
                        Text(well.name)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Rate") {
                HStack {
                    Text("Day Rate Override")
                    Spacer()
                    TextField("Rate", value: $workDay.dayRateOverride, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                HStack {
                    Text("Effective Rate")
                    Spacer()
                    Text(workDay.effectiveDayRate, format: .currency(code: "CAD"))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Mileage") {
                HStack {
                    Text("Distance")
                    Spacer()
                    TextField("km", value: $workDay.mileage, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("km")
                        .foregroundStyle(.secondary)
                }

                TextField("Description", text: $workDay.mileageDescription)
            }

            Section("Notes") {
                TextEditor(text: $workDay.notes)
                    .frame(minHeight: 80)
            }

            Section("Totals") {
                HStack {
                    Text("Total Earnings")
                        .fontWeight(.bold)
                    Spacer()
                    Text(workDay.totalEarnings, format: .currency(code: "CAD"))
                        .fontWeight(.bold)
                }
            }
        }
        .navigationTitle("Work Day")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Invoice Row

private struct InvoiceRowIOS: View {
    let invoice: Invoice

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Invoice #\(invoice.invoiceNumber)")
                    .font(.headline)
                Spacer()
                Text(invoice.total, format: .currency(code: "CAD"))
                    .fontWeight(.medium)
            }

            HStack {
                if let client = invoice.client {
                    Text(client.companyName)
                }
                Text("•")
                Text(invoice.date, style: .date)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if invoice.isPaid {
                Label("Paid", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Label("Unpaid", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Invoice Detail

struct InvoiceDetailViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var invoice: Invoice
    @Query(sort: \Client.companyName) private var clients: [Client]

    var body: some View {
        Form {
            Section("Invoice") {
                HStack {
                    Text("Number")
                    Spacer()
                    TextField("#", value: $invoice.invoiceNumber, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                DatePicker("Date", selection: $invoice.date, displayedComponents: .date)

                TextField("Terms", text: $invoice.terms)
            }

            Section("Client") {
                Picker("Client", selection: Binding(
                    get: { invoice.client },
                    set: { invoice.client = $0 }
                )) {
                    Text("No Client").tag(nil as Client?)
                    ForEach(clients) { client in
                        Text(client.companyName).tag(client as Client?)
                    }
                }
            }

            Section("Status") {
                Toggle("Paid", isOn: $invoice.isPaid)

                if invoice.isPaid {
                    DatePicker("Paid Date", selection: Binding(
                        get: { invoice.paidDate ?? Date.now },
                        set: { invoice.paidDate = $0 }
                    ), displayedComponents: .date)
                }
            }

            Section("Totals") {
                HStack {
                    Text("Subtotal")
                    Spacer()
                    Text(invoice.subtotal, format: .currency(code: "CAD"))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("GST (5%)")
                    Spacer()
                    Text(invoice.gstAmount, format: .currency(code: "CAD"))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Total")
                        .fontWeight(.bold)
                    Spacer()
                    Text(invoice.total, format: .currency(code: "CAD"))
                        .fontWeight(.bold)
                }
            }
        }
        .navigationTitle("Invoice #\(invoice.invoiceNumber)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Client Row

private struct ClientRowIOS: View {
    let client: Client

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(client.companyName)
                .font(.headline)

            if !client.contactName.isEmpty {
                Text(client.contactName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Day Rate:")
                Text(client.dayRate, format: .currency(code: "CAD"))
                    .foregroundStyle(.blue)
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Client Detail

struct ClientDetailViewIOS: View {
    @Bindable var client: Client

    var body: some View {
        Form {
            Section("Company") {
                TextField("Company Name", text: $client.companyName)
                TextField("Contact Name", text: $client.contactName)
                TextField("Contact Title", text: $client.contactTitle)
            }

            Section("Address") {
                TextField("Address", text: $client.address)
                TextField("City", text: $client.city)
                TextField("Province", text: $client.province)
                TextField("Postal Code", text: $client.postalCode)
            }

            Section("Rates") {
                HStack {
                    Text("Day Rate")
                    Spacer()
                    TextField("Rate", value: $client.dayRate, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                HStack {
                    Text("Mileage Rate")
                    Spacer()
                    TextField("Rate", value: $client.mileageRate, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("/km")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Max Mileage")
                    Spacer()
                    TextField("km", value: $client.maxMileage, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("km")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Default Cost Code") {
                TextField("Cost Code", text: $client.defaultCostCode)
            }
        }
        .navigationTitle(client.companyName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Add Work Day Sheet

private struct AddWorkDaySheetIOS: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Client.companyName) private var clients: [Client]
    @Binding var isPresented: Bool

    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var selectedClient: Client?

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                DatePicker("End Date", selection: $endDate, displayedComponents: .date)

                Picker("Client", selection: $selectedClient) {
                    Text("No Client").tag(nil as Client?)
                    ForEach(clients) { client in
                        Text(client.companyName).tag(client as Client?)
                    }
                }
            }
            .navigationTitle("Add Work Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addWorkDay()
                        dismiss()
                    }
                }
            }
        }
    }

    private func addWorkDay() {
        let workDay = WorkDay(startDate: startDate, endDate: endDate, client: selectedClient)
        modelContext.insert(workDay)
        try? modelContext.save()
    }
}

// MARK: - Add Invoice Sheet

private struct AddInvoiceSheetIOS: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Client.companyName) private var clients: [Client]
    @Binding var isPresented: Bool

    @State private var selectedClient: Client?
    @State private var invoiceNumber: Int = BusinessInfo.shared.nextInvoiceNumber

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    Text("Invoice Number")
                    Spacer()
                    TextField("#", value: $invoiceNumber, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                Picker("Client", selection: $selectedClient) {
                    Text("No Client").tag(nil as Client?)
                    ForEach(clients) { client in
                        Text(client.companyName).tag(client as Client?)
                    }
                }
            }
            .navigationTitle("Add Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addInvoice()
                        dismiss()
                    }
                }
            }
        }
    }

    private func addInvoice() {
        let invoice = Invoice(invoiceNumber: invoiceNumber, client: selectedClient)
        modelContext.insert(invoice)
        var info = BusinessInfo.shared
        if invoiceNumber >= info.nextInvoiceNumber {
            info.nextInvoiceNumber = invoiceNumber + 1
            BusinessInfo.shared = info
        }
        try? modelContext.save()
    }
}

// MARK: - Add Client Sheet

private struct AddClientSheetIOS: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool

    @State private var companyName = ""
    @State private var contactName = ""
    @State private var dayRate: Double = 1625

    var body: some View {
        NavigationStack {
            Form {
                TextField("Company Name", text: $companyName)
                TextField("Contact Name", text: $contactName)

                HStack {
                    Text("Day Rate")
                    Spacer()
                    TextField("Rate", value: $dayRate, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
            }
            .navigationTitle("Add Client")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addClient()
                        dismiss()
                    }
                    .disabled(companyName.isEmpty)
                }
            }
        }
    }

    private func addClient() {
        let client = Client(companyName: companyName, contactName: contactName, dayRate: dayRate)
        modelContext.insert(client)
        try? modelContext.save()
    }
}

#endif
