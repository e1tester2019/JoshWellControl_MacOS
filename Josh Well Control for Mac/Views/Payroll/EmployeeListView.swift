//
//  EmployeeListView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-08.
//

import SwiftUI
import SwiftData

struct EmployeeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Employee.lastName) private var employees: [Employee]

    @State private var showingAddSheet = false
    @State private var selectedEmployee: Employee?
    @State private var showActiveOnly = true

    private var filteredEmployees: [Employee] {
        if showActiveOnly {
            return employees.filter { $0.isActive }
        }
        return employees
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Show active only", isOn: $showActiveOnly)
                }

                if employees.isEmpty {
                    ContentUnavailableView {
                        Label("No Employees", systemImage: "person.crop.circle.badge.plus")
                    } description: {
                        Text("Add employees to start processing payroll")
                    } actions: {
                        Button("Add Employee") {
                            showingAddSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if filteredEmployees.isEmpty {
                    ContentUnavailableView {
                        Label("No Active Employees", systemImage: "person.crop.circle")
                    } description: {
                        Text("All employees are inactive or terminated")
                    } actions: {
                        Button("Show All") {
                            showActiveOnly = false
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    ForEach(filteredEmployees) { employee in
                        EmployeeRow(employee: employee)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedEmployee = employee
                            }
                    }
                    .onDelete(perform: deleteEmployees)
                }
            }
            .navigationTitle("Employees")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                EmployeeEditorView(employee: nil)
            }
            .sheet(item: $selectedEmployee) { employee in
                EmployeeEditorView(employee: employee)
            }
        }
    }

    private func deleteEmployees(at offsets: IndexSet) {
        for index in offsets {
            let employee = filteredEmployees[index]
            modelContext.delete(employee)
        }
        try? modelContext.save()
    }
}

// MARK: - Employee Row

struct EmployeeRow: View {
    let employee: Employee

    var body: some View {
        HStack {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(employee.fullName)
                        .fontWeight(.medium)

                    if !employee.employeeNumber.isEmpty {
                        Text("#\(employee.employeeNumber)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !employee.jobTitle.isEmpty {
                    Text(employee.jobTitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Text(employee.payType.rawValue)
                    Text(employee.payFrequency.rawValue)
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if employee.payType == .hourly {
                    Text("\(employee.payRate, format: .currency(code: "CAD"))/hr")
                        .fontWeight(.semibold)
                } else {
                    Text("\(employee.payRate, format: .currency(code: "CAD"))/yr")
                        .fontWeight(.semibold)
                }

                Text("YTD: \(employee.ytdGrossPay, format: .currency(code: "CAD"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch employee.status {
        case .active: return .green
        case .onLeave: return .orange
        case .terminated: return .red
        }
    }
}

// MARK: - Employee Editor

struct EmployeeEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let employee: Employee?

    // Personal info
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var city = ""
    @State private var province: Province = .alberta
    @State private var postalCode = ""
    @State private var sinNumber = ""

    // Employment info
    @State private var employeeNumber = ""
    @State private var startDate = Date.now
    @State private var status: EmploymentStatus = .active
    @State private var jobTitle = ""

    // Pay info
    @State private var payType: PayType = .hourly
    @State private var payRate: Double = 0
    @State private var payFrequency: PayFrequency = .biWeekly

    // Tax info
    @State private var federalTD1ClaimCode = 1
    @State private var provincialTD1ClaimCode = 1
    @State private var vacationPayPercent: Double = 4.0

    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Personal Information") {
                    TextField("First Name", text: $firstName)
                    TextField("Last Name", text: $lastName)
                    TextField("Email", text: $email)
                    TextField("Phone", text: $phone)
                }

                Section("Address") {
                    TextField("Address", text: $address)
                    TextField("City", text: $city)
                    Picker("Province", selection: $province) {
                        ForEach(Province.allCases, id: \.self) { prov in
                            Text(prov.rawValue).tag(prov)
                        }
                    }
                    TextField("Postal Code", text: $postalCode)
                }

                Section("Employment") {
                    TextField("Employee Number", text: $employeeNumber)
                    TextField("Job Title", text: $jobTitle)
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "en_GB"))
                    Picker("Status", selection: $status) {
                        ForEach(EmploymentStatus.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                }

                Section("Pay") {
                    Picker("Pay Type", selection: $payType) {
                        ForEach(PayType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    HStack {
                        Text(payType == .hourly ? "Hourly Rate" : "Annual Salary")
                        Spacer()
                        TextField("Rate", value: $payRate, format: .currency(code: "CAD"))
                            .frame(width: 120)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                    }

                    Picker("Pay Frequency", selection: $payFrequency) {
                        ForEach(PayFrequency.allCases, id: \.self) { freq in
                            Text(freq.rawValue).tag(freq)
                        }
                    }

                    if payType == .salary {
                        HStack {
                            Text("Per Period")
                            Spacer()
                            let perPeriod = payRate / Double(payFrequency.periodsPerYear)
                            Text(perPeriod, format: .currency(code: "CAD"))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Tax & Benefits") {
                    TextField("SIN", text: $sinNumber)
                        .help("Social Insurance Number")

                    Stepper("Federal TD1 Claim Code: \(federalTD1ClaimCode)", value: $federalTD1ClaimCode, in: 0...10)
                    Stepper("Provincial TD1 Claim Code: \(provincialTD1ClaimCode)", value: $provincialTD1ClaimCode, in: 0...10)

                    HStack {
                        Text("Vacation Pay %")
                        Spacer()
                        TextField("%", value: $vacationPayPercent, format: .number)
                            .frame(width: 60)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                        Text("%")
                    }
                }

                if let emp = employee {
                    Section("Year-to-Date (\(emp.ytdYear))") {
                        HStack {
                            Text("Gross Pay")
                            Spacer()
                            Text(emp.ytdGrossPay, format: .currency(code: "CAD"))
                        }
                        HStack {
                            Text("CPP")
                            Spacer()
                            Text(emp.ytdCPP, format: .currency(code: "CAD"))
                        }
                        HStack {
                            Text("EI")
                            Spacer()
                            Text(emp.ytdEI, format: .currency(code: "CAD"))
                        }
                        HStack {
                            Text("Federal Tax")
                            Spacer()
                            Text(emp.ytdFederalTax, format: .currency(code: "CAD"))
                        }
                        HStack {
                            Text("Provincial Tax")
                            Spacer()
                            Text(emp.ytdProvincialTax, format: .currency(code: "CAD"))
                        }
                        HStack {
                            Text("Vacation Accrued")
                            Spacer()
                            Text(emp.ytdVacationPay, format: .currency(code: "CAD"))
                        }
                        HStack {
                            Text("Vacation Used")
                            Spacer()
                            Text(emp.ytdVacationUsed, format: .currency(code: "CAD"))
                        }
                        HStack {
                            Text("Vacation Balance")
                                .fontWeight(.medium)
                            Spacer()
                            Text(emp.vacationPayBalance, format: .currency(code: "CAD"))
                                .fontWeight(.medium)
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(employee == nil ? "Add Employee" : "Edit Employee")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(firstName.isEmpty || lastName.isEmpty)
                }
            }
            .onAppear { loadEmployee() }
        }
        .frame(minWidth: 500, minHeight: 700)
    }

    private func loadEmployee() {
        guard let emp = employee else { return }
        firstName = emp.firstName
        lastName = emp.lastName
        email = emp.email
        phone = emp.phone
        address = emp.address
        city = emp.city
        province = emp.province
        postalCode = emp.postalCode
        sinNumber = emp.sinNumber
        employeeNumber = emp.employeeNumber
        startDate = emp.startDate
        status = emp.status
        jobTitle = emp.jobTitle
        payType = emp.payType
        payRate = emp.payRate
        payFrequency = emp.payFrequency
        federalTD1ClaimCode = emp.federalTD1ClaimCode
        provincialTD1ClaimCode = emp.provincialTD1ClaimCode
        vacationPayPercent = emp.vacationPayPercent
        notes = emp.notes
    }

    private func save() {
        let emp = employee ?? Employee()
        emp.firstName = firstName
        emp.lastName = lastName
        emp.email = email
        emp.phone = phone
        emp.address = address
        emp.city = city
        emp.province = province
        emp.postalCode = postalCode
        emp.sinNumber = sinNumber
        emp.employeeNumber = employeeNumber
        emp.startDate = startDate
        emp.status = status
        emp.jobTitle = jobTitle
        emp.payType = payType
        emp.payRate = payRate
        emp.payFrequency = payFrequency
        emp.federalTD1ClaimCode = federalTD1ClaimCode
        emp.provincialTD1ClaimCode = provincialTD1ClaimCode
        emp.vacationPayPercent = vacationPayPercent
        emp.notes = notes
        emp.updatedAt = Date.now

        if employee == nil {
            modelContext.insert(emp)
        }
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    EmployeeListView()
}
