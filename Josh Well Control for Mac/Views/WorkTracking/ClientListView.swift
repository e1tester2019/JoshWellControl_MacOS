//
//  ClientListView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-08.
//

import SwiftUI
import SwiftData

struct ClientListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Client.companyName) private var clients: [Client]

    @State private var showingAddClient = false
    @State private var selectedClient: Client?

    var body: some View {
        NavigationStack {
            List {
                if clients.isEmpty {
                    ContentUnavailableView {
                        Label("No Clients", systemImage: "person.2")
                    } description: {
                        Text("Add your first client to get started")
                    } actions: {
                        Button("Add Client") {
                            showingAddClient = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    ForEach(clients) { client in
                        ClientRow(client: client)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedClient = client
                            }
                    }
                    .onDelete(perform: deleteClients)
                }
            }
            .navigationTitle("Clients")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddClient = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddClient) {
                ClientEditorView(client: nil)
            }
            .sheet(item: $selectedClient) { client in
                ClientEditorView(client: client)
            }
        }
    }

    private func deleteClients(at offsets: IndexSet) {
        for index in offsets {
            let client = clients[index]
            modelContext.delete(client)
        }
        try? modelContext.save()
    }
}

// MARK: - Client Row

struct ClientRow: View {
    let client: Client

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(client.companyName)
                    .fontWeight(.medium)

                if !client.contactName.isEmpty {
                    Text(client.contactName)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Text("Day: \(client.dayRate, format: .currency(code: "CAD"))")
                    Text("Mileage: \(client.mileageRate, format: .currency(code: "CAD"))/km")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            Spacer()

            let workDayCount = client.workDays?.count ?? 0
            let invoiceCount = client.invoices?.count ?? 0

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(workDayCount) days")
                Text("\(invoiceCount) invoices")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Client Editor

struct ClientEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let client: Client?

    @State private var companyName = ""
    @State private var contactName = ""
    @State private var contactTitle = ""
    @State private var address = ""
    @State private var city = ""
    @State private var province = ""
    @State private var postalCode = ""
    @State private var dayRate: Double = 1625.00
    @State private var mileageRate: Double = 1.15
    @State private var maxMileage: Double = 750
    @State private var defaultCostCode = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Company") {
                    TextField("Company Name", text: $companyName)
                }

                Section("Contact") {
                    TextField("Contact Name", text: $contactName)
                    TextField("Title", text: $contactTitle)
                }

                Section("Address") {
                    TextField("Street Address", text: $address)
                    HStack {
                        TextField("City", text: $city)
                        TextField("Province", text: $province)
                            .frame(width: 100)
                    }
                    TextField("Postal Code", text: $postalCode)
                        .frame(width: 120)
                }

                Section("Rates") {
                    HStack {
                        Text("Day Rate")
                        Spacer()
                        TextField("Day Rate", value: $dayRate, format: .currency(code: "CAD"))
                            .frame(width: 120)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("Mileage Rate")
                        Spacer()
                        TextField("$/km", value: $mileageRate, format: .currency(code: "CAD"))
                            .frame(width: 120)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("Max Mileage")
                        Spacer()
                        TextField("km", value: $maxMileage, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                        Text("km")
                    }
                }

                Section("Defaults") {
                    TextField("Default Cost Code", text: $defaultCostCode)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(client == nil ? "Add Client" : "Edit Client")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(companyName.isEmpty)
                }
            }
            .onAppear { loadClient() }
        }
        .frame(minWidth: 450, minHeight: 500)
    }

    private func loadClient() {
        guard let c = client else { return }
        companyName = c.companyName
        contactName = c.contactName
        contactTitle = c.contactTitle
        address = c.address
        city = c.city
        province = c.province
        postalCode = c.postalCode
        dayRate = c.dayRate
        mileageRate = c.mileageRate
        maxMileage = c.maxMileage
        defaultCostCode = c.defaultCostCode
    }

    private func save() {
        let c = client ?? Client()
        c.companyName = companyName
        c.contactName = contactName
        c.contactTitle = contactTitle
        c.address = address
        c.city = city
        c.province = province
        c.postalCode = postalCode
        c.dayRate = dayRate
        c.mileageRate = mileageRate
        c.maxMileage = maxMileage
        c.defaultCostCode = defaultCostCode
        c.updatedAt = .now

        if client == nil {
            modelContext.insert(c)
        }
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    ClientListView()
}
