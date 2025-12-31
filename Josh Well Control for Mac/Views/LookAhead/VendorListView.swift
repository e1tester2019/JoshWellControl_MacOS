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
                let matchesCompany = vendor.companyName.lowercased().contains(search)
                let matchesService = vendor.serviceType.rawValue.lowercased().contains(search)
                let matchesContact = vendor.sortedContacts.contains { $0.name.lowercased().contains(search) }
                let matchesLegacyContact = vendor.contactName.lowercased().contains(search)
                return matchesCompany || matchesService || matchesContact || matchesLegacyContact
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

                    // Show primary contact from contacts relationship, fallback to legacy field
                    if let contact = vendor.primaryContact {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(contact.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !vendor.contactName.isEmpty {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(vendor.contactName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Show phone from primary contact or legacy field
                if let contact = vendor.primaryContact, contact.hasPhone {
                    Label(contact.primaryPhone, systemImage: "phone")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if !vendor.phone.isEmpty {
                    Label(vendor.phone, systemImage: "phone")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Info badges
            VStack(alignment: .trailing, spacing: 4) {
                // Contact count
                if vendor.sortedContacts.count > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "person.2")
                            .font(.caption2)
                        Text("\(vendor.sortedContacts.count)")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }

                // Equipment count
                if vendor.equipmentCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "shippingbox")
                            .font(.caption2)
                        Text("\(vendor.equipmentCount)")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }

                // Call count badge
                if vendor.totalCalls > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "phone.arrow.up.right")
                            .font(.caption2)
                        Text("\(vendor.totalCalls)")
                            .font(.caption)
                    }
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
    @State private var notes = ""
    @State private var isActive = true

    // Legacy single-contact fields (for backwards compatibility)
    @State private var legacyContactName = ""
    @State private var legacyContactTitle = ""
    @State private var legacyPhone = ""
    @State private var legacyEmergencyPhone = ""
    @State private var legacyEmail = ""
    @State private var legacyAddress = ""

    // Contacts and Addresses (for existing vendor)
    @State private var showAddContact = false
    @State private var editingContact: VendorContact?
    @State private var showAddAddress = false
    @State private var editingAddress: VendorAddress?

    private var isEditing: Bool { vendor != nil }
    private var hasMultipleContacts: Bool { (vendor?.contacts?.count ?? 0) > 0 }
    private var hasMultipleAddresses: Bool { (vendor?.addresses?.count ?? 0) > 0 }

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

                // Contacts section
                if isEditing {
                    contactsSection
                } else {
                    // For new vendors, show simple single-contact form
                    Section("Primary Contact") {
                        TextField("Contact Name", text: $legacyContactName)
                        TextField("Title", text: $legacyContactTitle)
                        TextField("Phone", text: $legacyPhone)
                            #if os(iOS)
                            .keyboardType(.phonePad)
                            #endif
                        TextField("24hr Emergency", text: $legacyEmergencyPhone)
                            #if os(iOS)
                            .keyboardType(.phonePad)
                            #endif
                        TextField("Email", text: $legacyEmail)
                            #if os(iOS)
                            .keyboardType(.emailAddress)
                            #endif
                    }
                }

                // Addresses section
                if isEditing {
                    addressesSection
                } else {
                    Section("Address") {
                        TextField("Address", text: $legacyAddress, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Vendor" : "Add Vendor")
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 600)
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
            .sheet(isPresented: $showAddContact) {
                ContactEditorSheet(contact: nil, vendor: vendor) { contact in
                    if let v = vendor {
                        contact.vendor = v
                        if v.contacts == nil { v.contacts = [] }
                        v.contacts?.append(contact)
                        modelContext.insert(contact)
                        try? modelContext.save()
                    }
                }
            }
            .sheet(item: $editingContact) { contact in
                ContactEditorSheet(contact: contact, vendor: vendor) { _ in
                    try? modelContext.save()
                }
            }
            .sheet(isPresented: $showAddAddress) {
                AddressEditorSheet(address: nil, vendor: vendor) { address in
                    if let v = vendor {
                        address.vendor = v
                        if v.addresses == nil { v.addresses = [] }
                        v.addresses?.append(address)
                        modelContext.insert(address)
                        try? modelContext.save()
                    }
                }
            }
            .sheet(item: $editingAddress) { address in
                AddressEditorSheet(address: address, vendor: vendor) { _ in
                    try? modelContext.save()
                }
            }
        }
    }

    // MARK: - Contacts Section

    private var contactsSection: some View {
        Section {
            if let vendor = vendor, !vendor.sortedContacts.isEmpty {
                ForEach(vendor.sortedContacts) { contact in
                    ContactRow(contact: contact)
                        .contentShape(Rectangle())
                        .onTapGesture { editingContact = contact }
                        .contextMenu {
                            Button("Edit") { editingContact = contact }
                            Button(contact.isPrimary ? "Unset Primary" : "Set as Primary") {
                                // Unset other primaries
                                for c in vendor.sortedContacts where c.id != contact.id {
                                    c.isPrimary = false
                                }
                                contact.isPrimary.toggle()
                                try? modelContext.save()
                            }
                            Divider()
                            Button(contact.isActive ? "Deactivate" : "Activate") {
                                contact.isActive.toggle()
                                try? modelContext.save()
                            }
                            Button("Delete", role: .destructive) {
                                modelContext.delete(contact)
                                try? modelContext.save()
                            }
                        }
                }
            } else {
                Text("No contacts added")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Button("Add Contact", systemImage: "plus") {
                showAddContact = true
            }
        } header: {
            HStack {
                Text("Contacts")
                Spacer()
                if let count = vendor?.sortedContacts.count, count > 0 {
                    Text("\(count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Addresses Section

    private var addressesSection: some View {
        Section {
            if let vendor = vendor, !vendor.sortedAddresses.isEmpty {
                ForEach(vendor.sortedAddresses) { address in
                    AddressRow(address: address)
                        .contentShape(Rectangle())
                        .onTapGesture { editingAddress = address }
                        .contextMenu {
                            Button("Edit") { editingAddress = address }
                            Button(address.isPrimary ? "Unset Primary" : "Set as Primary") {
                                // Unset other primaries
                                for a in vendor.sortedAddresses where a.id != address.id {
                                    a.isPrimary = false
                                }
                                address.isPrimary.toggle()
                                try? modelContext.save()
                            }
                            Divider()
                            Button(address.isActive ? "Deactivate" : "Activate") {
                                address.isActive.toggle()
                                try? modelContext.save()
                            }
                            Button("Delete", role: .destructive) {
                                modelContext.delete(address)
                                try? modelContext.save()
                            }
                        }
                }
            } else {
                Text("No addresses added")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Button("Add Address", systemImage: "plus") {
                showAddAddress = true
            }
        } header: {
            HStack {
                Text("Addresses")
                Spacer()
                if let count = vendor?.sortedAddresses.count, count > 0 {
                    Text("\(count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func loadVendor() {
        guard let v = vendor else { return }
        companyName = v.companyName
        serviceType = v.serviceType
        notes = v.notes
        isActive = v.isActive
        // Legacy fields
        legacyContactName = v.contactName
        legacyContactTitle = v.contactTitle
        legacyPhone = v.phone
        legacyEmergencyPhone = v.emergencyPhone
        legacyEmail = v.email
        legacyAddress = v.address
    }

    private func save() {
        if let v = vendor {
            v.companyName = companyName
            v.serviceType = serviceType
            v.notes = notes
            v.isActive = isActive
            v.updatedAt = .now
        } else {
            let v = Vendor(companyName: companyName, serviceType: serviceType)
            v.notes = notes
            v.isActive = isActive
            // Set legacy fields for new vendor
            v.contactName = legacyContactName
            v.contactTitle = legacyContactTitle
            v.phone = legacyPhone
            v.emergencyPhone = legacyEmergencyPhone
            v.email = legacyEmail
            v.address = legacyAddress

            // If contact info provided, also create a VendorContact
            if !legacyContactName.isEmpty {
                let contact = VendorContact(
                    name: legacyContactName,
                    title: legacyContactTitle,
                    role: .general,
                    phone: legacyPhone,
                    email: legacyEmail
                )
                contact.isPrimary = true
                contact.vendor = v
                v.contacts = [contact]
                modelContext.insert(contact)
            }

            // If address provided, also create a VendorAddress
            if !legacyAddress.isEmpty {
                let address = VendorAddress(
                    label: "Primary",
                    addressType: .shop,
                    streetAddress: legacyAddress
                )
                address.isPrimary = true
                address.vendor = v
                v.addresses = [address]
                modelContext.insert(address)
            }

            modelContext.insert(v)
        }

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Contact Row

private struct ContactRow: View {
    let contact: VendorContact

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: contact.role.icon)
                .foregroundStyle(contact.isPrimary ? .blue : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(contact.name)
                        .fontWeight(contact.isPrimary ? .medium : .regular)
                    if contact.isPrimary {
                        Text("Primary")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.2))
                            .foregroundStyle(.blue)
                            .cornerRadius(4)
                    }
                    if !contact.isActive {
                        Text("Inactive")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                HStack(spacing: 8) {
                    Text(contact.role.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !contact.title.isEmpty {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(contact.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if contact.hasPhone {
                    Text(contact.primaryPhone)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .opacity(contact.isActive ? 1 : 0.6)
    }
}

// MARK: - Address Row

private struct AddressRow: View {
    let address: VendorAddress

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: address.addressType.icon)
                .foregroundStyle(address.isPrimary ? .blue : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(address.displayLabel)
                        .fontWeight(address.isPrimary ? .medium : .regular)
                    if address.isPrimary {
                        Text("Primary")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.2))
                            .foregroundStyle(.blue)
                            .cornerRadius(4)
                    }
                    if !address.isActive {
                        Text("Inactive")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                Text(address.formattedAddress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .opacity(address.isActive ? 1 : 0.6)
    }
}

// MARK: - Contact Editor Sheet

private struct ContactEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let contact: VendorContact?
    let vendor: Vendor?
    let onSave: (VendorContact) -> Void

    @State private var name = ""
    @State private var title = ""
    @State private var role: VendorContactRole = .general
    @State private var phone = ""
    @State private var cellPhone = ""
    @State private var email = ""
    @State private var notes = ""
    @State private var isPrimary = false

    private var isEditing: Bool { contact != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact Info") {
                    TextField("Name", text: $name)
                    TextField("Title", text: $title)
                    Picker("Role", selection: $role) {
                        ForEach(VendorContactRole.allCases, id: \.self) { r in
                            Label(r.rawValue, systemImage: r.icon).tag(r)
                        }
                    }
                    Toggle("Primary Contact", isOn: $isPrimary)
                }

                Section("Phone") {
                    TextField("Office Phone", text: $phone)
                        #if os(iOS)
                        .keyboardType(.phonePad)
                        #endif
                    TextField("Cell Phone", text: $cellPhone)
                        #if os(iOS)
                        .keyboardType(.phonePad)
                        #endif
                }

                Section("Email") {
                    TextField("Email", text: $email)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        #endif
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Contact" : "Add Contact")
            #if os(macOS)
            .frame(width: 400, height: 450)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty)
                }
            }
            .onAppear { loadContact() }
        }
    }

    private func loadContact() {
        guard let c = contact else { return }
        name = c.name
        title = c.title
        role = c.role
        phone = c.phone
        cellPhone = c.cellPhone
        email = c.email
        notes = c.notes
        isPrimary = c.isPrimary
    }

    private func save() {
        let c = contact ?? VendorContact()
        c.name = name
        c.title = title
        c.role = role
        c.phone = phone
        c.cellPhone = cellPhone
        c.email = email
        c.notes = notes
        c.isPrimary = isPrimary
        onSave(c)
        dismiss()
    }
}

// MARK: - Address Editor Sheet

private struct AddressEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let address: VendorAddress?
    let vendor: Vendor?
    let onSave: (VendorAddress) -> Void

    @State private var label = ""
    @State private var addressType: VendorAddressType = .shop
    @State private var streetAddress = ""
    @State private var streetAddress2 = ""
    @State private var city = ""
    @State private var province = ""
    @State private var postalCode = ""
    @State private var country = "Canada"
    @State private var phone = ""
    @State private var fax = ""
    @State private var notes = ""
    @State private var isPrimary = false

    private var isEditing: Bool { address != nil }

    private let provinces = ["AB", "BC", "MB", "NB", "NL", "NS", "NT", "NU", "ON", "PE", "QC", "SK", "YT"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Location Info") {
                    TextField("Label (e.g., Edmonton Shop)", text: $label)
                    Picker("Type", selection: $addressType) {
                        ForEach(VendorAddressType.allCases, id: \.self) { t in
                            Label(t.rawValue, systemImage: t.icon).tag(t)
                        }
                    }
                    Toggle("Primary Address", isOn: $isPrimary)
                }

                Section("Address") {
                    TextField("Street Address", text: $streetAddress)
                    TextField("Unit/Suite", text: $streetAddress2)
                    TextField("City", text: $city)
                    Picker("Province", selection: $province) {
                        Text("Select...").tag("")
                        ForEach(provinces, id: \.self) { p in
                            Text(p).tag(p)
                        }
                    }
                    TextField("Postal Code", text: $postalCode)
                    TextField("Country", text: $country)
                }

                Section("Contact") {
                    TextField("Phone", text: $phone)
                        #if os(iOS)
                        .keyboardType(.phonePad)
                        #endif
                    TextField("Fax", text: $fax)
                        #if os(iOS)
                        .keyboardType(.phonePad)
                        #endif
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Address" : "Add Address")
            #if os(macOS)
            .frame(width: 400, height: 550)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(streetAddress.isEmpty && city.isEmpty)
                }
            }
            .onAppear { loadAddress() }
        }
    }

    private func loadAddress() {
        guard let a = address else { return }
        label = a.label
        addressType = a.addressType
        streetAddress = a.streetAddress
        streetAddress2 = a.streetAddress2
        city = a.city
        province = a.province
        postalCode = a.postalCode
        country = a.country
        phone = a.phone
        fax = a.fax
        notes = a.notes
        isPrimary = a.isPrimary
    }

    private func save() {
        let a = address ?? VendorAddress()
        a.label = label
        a.addressType = addressType
        a.streetAddress = streetAddress
        a.streetAddress2 = streetAddress2
        a.city = city
        a.province = province
        a.postalCode = postalCode
        a.country = country
        a.phone = phone
        a.fax = fax
        a.notes = notes
        a.isPrimary = isPrimary
        onSave(a)
        dismiss()
    }
}

#Preview {
    VendorListView()
        .modelContainer(for: Vendor.self)
}
