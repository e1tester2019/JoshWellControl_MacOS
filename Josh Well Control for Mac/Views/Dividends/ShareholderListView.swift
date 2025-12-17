//
//  ShareholderListView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-08.
//

#if os(macOS)
import SwiftUI
import SwiftData

struct ShareholderListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Shareholder.lastName) private var shareholders: [Shareholder]

    @State private var selectedShareholder: Shareholder?
    @State private var showingAddShareholder = false
    @State private var showActiveOnly = true

    private var filteredShareholders: [Shareholder] {
        if showActiveOnly {
            return shareholders.filter { $0.isActive }
        }
        return shareholders
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Show active only", isOn: $showActiveOnly)
                }

                if shareholders.isEmpty {
                    ContentUnavailableView {
                        Label("No Shareholders", systemImage: "person.2")
                    } description: {
                        Text("Add shareholders to track dividend payments")
                    } actions: {
                        Button("Add Shareholder") {
                            showingAddShareholder = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if filteredShareholders.isEmpty {
                    ContentUnavailableView {
                        Label("No Active Shareholders", systemImage: "person.2")
                    } description: {
                        Text("All shareholders are inactive")
                    } actions: {
                        Button("Show All") {
                            showActiveOnly = false
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    ForEach(filteredShareholders) { shareholder in
                        ShareholderRow(shareholder: shareholder)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedShareholder = shareholder
                            }
                    }
                    .onDelete(perform: deleteShareholders)
                }
            }
            .navigationTitle("Shareholders")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddShareholder = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddShareholder) {
                ShareholderEditorView(shareholder: nil)
            }
            .sheet(item: $selectedShareholder) { shareholder in
                ShareholderEditorView(shareholder: shareholder)
            }
        }
    }

    private func deleteShareholders(at offsets: IndexSet) {
        for index in offsets {
            let shareholder = filteredShareholders[index]
            modelContext.delete(shareholder)
        }
        try? modelContext.save()
    }
}

// MARK: - Shareholder Row

struct ShareholderRow: View {
    let shareholder: Shareholder

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date.now)
    }

    var body: some View {
        HStack {
            // Status indicator
            Circle()
                .fill(shareholder.isActive ? Color.green : Color.gray)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(shareholder.fullName)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text("\(shareholder.ownershipPercent, specifier: "%.1f")% ownership")
                    if !shareholder.isActive {
                        Text("Inactive")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(shareholder.totalDividends(for: currentYear), format: .currency(code: "CAD"))
                    .fontWeight(.semibold)

                Text("\(currentYear) YTD")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Shareholder Editor

struct ShareholderEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let shareholder: Shareholder?

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var address = ""
    @State private var city = ""
    @State private var province: Province = .alberta
    @State private var postalCode = ""
    @State private var sinNumber = ""
    @State private var ownershipPercent: Double = 100
    @State private var isActive = true
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Personal Information") {
                    TextField("First Name", text: $firstName)
                    TextField("Last Name", text: $lastName)
                }

                Section("Address") {
                    TextField("Street Address", text: $address)
                    TextField("City", text: $city)
                    Picker("Province", selection: $province) {
                        ForEach(Province.allCases, id: \.self) { prov in
                            Text(prov.rawValue).tag(prov)
                        }
                    }
                    TextField("Postal Code", text: $postalCode)
                }

                Section("Tax Information") {
                    SecureField("SIN (for T5 slips)", text: $sinNumber)
                    Text("Social Insurance Number is required for T5 slip preparation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Ownership") {
                    HStack {
                        Text("Ownership Percentage")
                        Spacer()
                        TextField("%", value: $ownershipPercent, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                        Text("%")
                    }

                    Toggle("Active Shareholder", isOn: $isActive)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(shareholder == nil ? "Add Shareholder" : "Edit Shareholder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(firstName.isEmpty && lastName.isEmpty)
                }
            }
            .onAppear { loadShareholder() }
        }
        .frame(minWidth: 450, minHeight: 500)
    }

    private func loadShareholder() {
        guard let sh = shareholder else { return }
        firstName = sh.firstName
        lastName = sh.lastName
        address = sh.address
        city = sh.city
        province = sh.province
        postalCode = sh.postalCode
        sinNumber = sh.sinNumber
        ownershipPercent = sh.ownershipPercent
        isActive = sh.isActive
        notes = sh.notes
    }

    private func save() {
        let sh = shareholder ?? Shareholder()
        sh.firstName = firstName
        sh.lastName = lastName
        sh.address = address
        sh.city = city
        sh.province = province
        sh.postalCode = postalCode
        sh.sinNumber = sinNumber
        sh.ownershipPercent = ownershipPercent
        sh.isActive = isActive
        sh.notes = notes
        sh.updatedAt = Date.now

        if shareholder == nil {
            modelContext.insert(sh)
        }
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    ShareholderListView()
}
#endif
