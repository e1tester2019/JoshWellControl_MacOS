//
//  VendorListView.swift
//  Josh Well Control for Mac
//
//  List view for managing vendors/service providers.
//

import SwiftUI
import SwiftData

struct VendorListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Vendor.companyName) private var vendors: [Vendor]

    @State private var showAddVendor = false
    @State private var editingVendor: Vendor?
    @State private var searchText = ""
    @State private var filterServiceType: VendorServiceType?
    @State private var showInactive = false

    private var filteredVendors: [Vendor] {
        vendors.filter { vendor in
            // Active filter
            if !showInactive && !vendor.isActive { return false }

            // Service type filter
            if let type = filterServiceType, vendor.serviceType != type {
                return false
            }

            // Search filter
            if !searchText.isEmpty {
                let search = searchText.lowercased()
                return vendor.companyName.lowercased().contains(search) ||
                       vendor.contactName.lowercased().contains(search) ||
                       vendor.serviceType.rawValue.lowercased().contains(search)
            }

            return true
        }
    }

    var body: some View {
        List {
            // Search & Filters
            Section {
                TextField("Search vendors...", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                DisclosureGroup("Filters") {
                    Picker("Service Type", selection: $filterServiceType) {
                        Text("All Types").tag(nil as VendorServiceType?)
                        ForEach(VendorServiceType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type as VendorServiceType?)
                        }
                    }

                    Toggle("Show Inactive", isOn: $showInactive)
                }
            }

            // Vendors
            if filteredVendors.isEmpty {
                ContentUnavailableView {
                    Label("No Vendors", systemImage: "person.2.badge.gearshape")
                } description: {
                    Text("Add vendors to track service providers for your operations.")
                }
            } else {
                ForEach(filteredVendors) { vendor in
                    VendorRow(vendor: vendor)
                        .contentShape(Rectangle())
                        .onTapGesture { editingVendor = vendor }
                        .contextMenu {
                            Button("Edit") { editingVendor = vendor }
                            Button(vendor.isActive ? "Deactivate" : "Activate") {
                                vendor.isActive.toggle()
                                try? modelContext.save()
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                modelContext.delete(vendor)
                                try? modelContext.save()
                            }
                        }
                }
                .onDelete(perform: deleteVendors)
            }
        }
        .navigationTitle("Vendors")
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddVendor = true } label: {
                    Label("Add Vendor", systemImage: "plus")
                }
            }
        }
        #endif
        .sheet(isPresented: $showAddVendor) {
            VendorEditorView(vendor: nil)
        }
        .sheet(item: $editingVendor) { vendor in
            VendorEditorView(vendor: vendor)
        }
    }

    private func deleteVendors(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredVendors[index])
        }
        try? modelContext.save()
    }
}

// MARK: - Vendor Row

struct VendorRow: View {
    let vendor: Vendor

    var body: some View {
        HStack(spacing: 12) {
            // Service type icon
            Image(systemName: vendor.serviceType.icon)
                .font(.title2)
                .foregroundStyle(vendor.isActive ? .blue : .gray)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(vendor.companyName)
                        .font(.headline)
                    if !vendor.isActive {
                        Text("Inactive")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                }

                HStack {
                    Text(vendor.serviceType.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !vendor.contactName.isEmpty {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(vendor.contactName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !vendor.phone.isEmpty {
                    Label(vendor.phone, systemImage: "phone")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Call count badge
            if vendor.totalCalls > 0 {
                VStack(alignment: .trailing) {
                    Text("\(vendor.totalCalls)")
                        .font(.headline)
                    Text("calls")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Vendor Editor

struct VendorEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let vendor: Vendor?

    @State private var companyName = ""
    @State private var serviceType: VendorServiceType = .other
    @State private var contactName = ""
    @State private var contactTitle = ""
    @State private var phone = ""
    @State private var emergencyPhone = ""
    @State private var email = ""
    @State private var address = ""
    @State private var notes = ""
    @State private var isActive = true

    private var isEditing: Bool { vendor != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Company") {
                    TextField("Company Name", text: $companyName)
                    Picker("Service Type", selection: $serviceType) {
                        ForEach(VendorServiceType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                    Toggle("Active", isOn: $isActive)
                }

                Section("Contact") {
                    TextField("Contact Name", text: $contactName)
                    TextField("Title", text: $contactTitle)
                    TextField("Phone", text: $phone)
                        #if os(iOS)
                        .keyboardType(.phonePad)
                        #endif
                    TextField("24hr Emergency", text: $emergencyPhone)
                        #if os(iOS)
                        .keyboardType(.phonePad)
                        #endif
                    TextField("Email", text: $email)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        #endif
                }

                Section("Address") {
                    TextField("Address", text: $address, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Vendor" : "Add Vendor")
            #if os(macOS)
            .frame(minWidth: 450, minHeight: 500)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(companyName.isEmpty)
                }
            }
            .onAppear { loadVendor() }
        }
    }

    private func loadVendor() {
        guard let v = vendor else { return }
        companyName = v.companyName
        serviceType = v.serviceType
        contactName = v.contactName
        contactTitle = v.contactTitle
        phone = v.phone
        emergencyPhone = v.emergencyPhone
        email = v.email
        address = v.address
        notes = v.notes
        isActive = v.isActive
    }

    private func save() {
        if let v = vendor {
            v.companyName = companyName
            v.serviceType = serviceType
            v.contactName = contactName
            v.contactTitle = contactTitle
            v.phone = phone
            v.emergencyPhone = emergencyPhone
            v.email = email
            v.address = address
            v.notes = notes
            v.isActive = isActive
            v.updatedAt = .now
        } else {
            let v = Vendor(companyName: companyName, serviceType: serviceType, contactName: contactName, phone: phone)
            v.contactTitle = contactTitle
            v.emergencyPhone = emergencyPhone
            v.email = email
            v.address = address
            v.notes = notes
            v.isActive = isActive
            modelContext.insert(v)
        }

        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    VendorListView()
        .modelContainer(for: Vendor.self)
}
