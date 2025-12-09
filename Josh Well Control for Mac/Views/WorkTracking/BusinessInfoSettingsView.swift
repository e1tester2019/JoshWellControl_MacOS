//
//  BusinessInfoSettingsView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-08.
//

import SwiftUI

struct BusinessInfoSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var companyName: String
    @State private var phone: String
    @State private var email: String
    @State private var address: String
    @State private var city: String
    @State private var province: String
    @State private var postalCode: String
    @State private var gstNumber: String
    @State private var nextInvoiceNumber: Int

    @State private var showingResetPIN = false
    @State private var currentPIN = ""
    @State private var newPIN = ""
    @State private var confirmPIN = ""
    @State private var pinError = ""

    init() {
        let info = BusinessInfo.shared
        _companyName = State(initialValue: info.companyName)
        _phone = State(initialValue: info.phone)
        _email = State(initialValue: info.email)
        _address = State(initialValue: info.address)
        _city = State(initialValue: info.city)
        _province = State(initialValue: info.province)
        _postalCode = State(initialValue: info.postalCode)
        _gstNumber = State(initialValue: info.gstNumber)
        _nextInvoiceNumber = State(initialValue: info.nextInvoiceNumber)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Business Information") {
                    TextField("Company Name", text: $companyName)
                    TextField("Phone", text: $phone)
                    TextField("Email", text: $email)
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

                Section("Tax") {
                    TextField("GST Number", text: $gstNumber)
                }

                Section("Invoice Numbering") {
                    HStack {
                        Text("Next Invoice Number")
                        Spacer()
                        TextField("Number", value: $nextInvoiceNumber, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Section("Security") {
                    Button("Change PIN") {
                        showingResetPIN = true
                    }

                    Button("Remove PIN", role: .destructive) {
                        WorkTrackingAuth.clearPin()
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .sheet(isPresented: $showingResetPIN) {
                changePINView
            }
        }
        .frame(minWidth: 450, minHeight: 500)
    }

    private var changePINView: some View {
        NavigationStack {
            Form {
                if WorkTrackingAuth.hasPin {
                    Section("Current PIN") {
                        SecureField("Enter current PIN", text: $currentPIN)
                    }
                }

                Section("New PIN") {
                    SecureField("New PIN", text: $newPIN)
                    SecureField("Confirm PIN", text: $confirmPIN)
                }

                if !pinError.isEmpty {
                    Section {
                        Text(pinError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Change PIN")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingResetPIN = false
                        currentPIN = ""
                        newPIN = ""
                        confirmPIN = ""
                        pinError = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { changePIN() }
                        .disabled(newPIN.isEmpty || confirmPIN.isEmpty)
                }
            }
        }
        .frame(width: 350, height: 300)
    }

    private func changePIN() {
        if WorkTrackingAuth.hasPin && !WorkTrackingAuth.verifyPin(currentPIN) {
            pinError = "Current PIN is incorrect"
            return
        }

        if newPIN != confirmPIN {
            pinError = "New PINs don't match"
            return
        }

        WorkTrackingAuth.setPin(newPIN)
        showingResetPIN = false
        currentPIN = ""
        newPIN = ""
        confirmPIN = ""
        pinError = ""
    }

    private func save() {
        var info = BusinessInfo.shared
        info.companyName = companyName
        info.phone = phone
        info.email = email
        info.address = address
        info.city = city
        info.province = province
        info.postalCode = postalCode
        info.gstNumber = gstNumber
        info.nextInvoiceNumber = nextInvoiceNumber
        BusinessInfo.shared = info
        dismiss()
    }
}

#Preview {
    BusinessInfoSettingsView()
}
