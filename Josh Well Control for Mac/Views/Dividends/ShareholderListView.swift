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
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Shareholder.lastName) private var shareholders: [Shareholder]

    @State private var selectedShareholder: Shareholder?
    @State private var showingAddShareholder = false

    var body: some View {
        NavigationStack {
            Group {
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
                } else {
                    List(selection: $selectedShareholder) {
                        ForEach(shareholders) { shareholder in
                            ShareholderRow(shareholder: shareholder)
                                .tag(shareholder)
                                .contextMenu {
                                    Button("Edit") {
                                        selectedShareholder = shareholder
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        modelContext.delete(shareholder)
                                    }
                                }
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }
            }
            .navigationTitle("Shareholders")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddShareholder = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .sheet(isPresented: $showingAddShareholder) {
            ShareholderEditorView(shareholder: nil)
        }
        .sheet(item: $selectedShareholder) { shareholder in
            ShareholderEditorView(shareholder: shareholder)
        }
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
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(shareholder.fullName)
                        .fontWeight(.medium)

                    if !shareholder.isActive {
                        Text("Inactive")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                }

                Text("\(shareholder.ownershipPercent, specifier: "%.1f")% ownership")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(shareholder.totalDividends(for: currentYear), format: .currency(code: "CAD"))
                    .fontWeight(.medium)

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
