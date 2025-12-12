//
//  PayrollListViewIOS.swift
//  Josh Well Control for Mac
//
//  iOS-optimized payroll views
//

#if os(iOS)
import SwiftUI
import SwiftData

struct PayrollListViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PayRun.payPeriodEnd, order: .reverse) private var payRuns: [PayRun]
    @State private var showingAddSheet = false
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Pay Runs
            payRunsList
                .tabItem {
                    Label("Pay Runs", systemImage: "calendar.badge.clock")
                }
                .tag(0)

            // Employees
            employeesList
                .tabItem {
                    Label("Employees", systemImage: "person.2")
                }
                .tag(1)
        }
        .navigationTitle("Payroll")
    }

    // MARK: - Pay Runs List

    private var payRunsList: some View {
        List {
            ForEach(payRuns) { payRun in
                NavigationLink {
                    PayRunDetailViewIOS(payRun: payRun)
                } label: {
                    PayRunRowIOS(payRun: payRun)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        modelContext.delete(payRun)
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
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddPayRunSheetIOS(isPresented: $showingAddSheet)
        }
        .overlay {
            if payRuns.isEmpty {
                ContentUnavailableView("No Pay Runs", systemImage: "calendar.badge.plus", description: Text("Create pay runs to process payroll"))
            }
        }
    }

    // MARK: - Employees List

    @Query(sort: \Employee.lastName) private var employees: [Employee]
    @State private var showingAddEmployeeSheet = false

    private var employeesList: some View {
        List {
            ForEach(employees) { employee in
                NavigationLink {
                    EmployeeDetailViewIOS(employee: employee)
                } label: {
                    EmployeeRowIOS(employee: employee)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        modelContext.delete(employee)
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
                    showingAddEmployeeSheet = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showingAddEmployeeSheet) {
            AddEmployeeSheetIOS(isPresented: $showingAddEmployeeSheet)
        }
        .overlay {
            if employees.isEmpty {
                ContentUnavailableView("No Employees", systemImage: "person.badge.plus", description: Text("Add employees to process payroll"))
            }
        }
    }
}

// MARK: - Pay Run Row

private struct PayRunRowIOS: View {
    let payRun: PayRun

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Pay Period")
                    .font(.headline)
                Spacer()
                Text(payRun.totalGross, format: .currency(code: "CAD"))
                    .fontWeight(.medium)
            }

            HStack {
                Text(payRun.payPeriodStart, style: .date)
                Text("-")
                Text(payRun.payPeriodEnd, style: .date)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let stubs = payRun.payStubs, !stubs.isEmpty {
                Text("\(stubs.count) pay stub\(stubs.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Pay Run Detail

struct PayRunDetailViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var payRun: PayRun
    @State private var showingAddStubSheet = false

    var body: some View {
        List {
            Section("Period") {
                DatePicker("Start", selection: $payRun.payPeriodStart, displayedComponents: .date)
                DatePicker("End", selection: $payRun.payPeriodEnd, displayedComponents: .date)
                DatePicker("Pay Date", selection: $payRun.payDate, displayedComponents: .date)
            }

            Section("Pay Stubs") {
                if let stubs = payRun.payStubs, !stubs.isEmpty {
                    ForEach(stubs) { stub in
                        NavigationLink {
                            PayStubDetailViewIOS(stub: stub)
                        } label: {
                            PayStubRowIOS(stub: stub)
                        }
                    }
                    .onDelete(perform: deleteStubs)
                }

                Button {
                    showingAddStubSheet = true
                } label: {
                    Label("Add Pay Stub", systemImage: "plus")
                }
            }

            Section("Summary") {
                HStack {
                    Text("Total Gross")
                    Spacer()
                    Text(payRun.totalGross, format: .currency(code: "CAD"))
                }

                HStack {
                    Text("Total Net")
                    Spacer()
                    Text(payRun.totalNet, format: .currency(code: "CAD"))
                        .fontWeight(.medium)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Pay Run")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddStubSheet) {
            AddPayStubSheetIOS(payRun: payRun, isPresented: $showingAddStubSheet)
        }
    }

    private func deleteStubs(at offsets: IndexSet) {
        guard var stubs = payRun.payStubs else { return }
        for index in offsets {
            let stub = stubs[index]
            modelContext.delete(stub)
        }
        offsets.forEach { stubs.remove(at: $0) }
        payRun.payStubs = stubs
        try? modelContext.save()
    }
}

// MARK: - Pay Stub Row

private struct PayStubRowIOS: View {
    let stub: PayStub

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(stub.employee?.fullName ?? "Unknown")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(stub.regularHours, format: .number) hrs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(stub.grossPay, format: .currency(code: "CAD"))
                    .font(.subheadline)
                Text(stub.netPay, format: .currency(code: "CAD"))
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }
}

// MARK: - Pay Stub Detail

struct PayStubDetailViewIOS: View {
    @Bindable var stub: PayStub

    var body: some View {
        List {
            Section("Employee") {
                HStack {
                    Text("Name")
                    Spacer()
                    Text(stub.employee?.fullName ?? "Unknown")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Hours") {
                HStack {
                    Text("Regular")
                    Spacer()
                    TextField("Hrs", value: $stub.regularHours, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }

                HStack {
                    Text("Overtime")
                    Spacer()
                    TextField("Hrs", value: $stub.overtimeHours, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }

                HStack {
                    Text("Vacation")
                    Spacer()
                    TextField("Hrs", value: $stub.vacationHours, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }

            Section("Earnings") {
                HStack {
                    Text("Gross Pay")
                    Spacer()
                    Text(stub.grossPay, format: .currency(code: "CAD"))
                        .fontWeight(.medium)
                }
            }

            Section("Deductions") {
                HStack {
                    Text("CPP")
                    Spacer()
                    Text(stub.cppDeduction, format: .currency(code: "CAD"))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("EI")
                    Spacer()
                    Text(stub.eiDeduction, format: .currency(code: "CAD"))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Federal Tax")
                    Spacer()
                    Text(stub.federalTax, format: .currency(code: "CAD"))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Provincial Tax")
                    Spacer()
                    Text(stub.provincialTax, format: .currency(code: "CAD"))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Total Deductions")
                    Spacer()
                    Text(stub.totalDeductions, format: .currency(code: "CAD"))
                        .fontWeight(.medium)
                }
            }

            Section("Net Pay") {
                HStack {
                    Text("Net Pay")
                        .fontWeight(.bold)
                    Spacer()
                    Text(stub.netPay, format: .currency(code: "CAD"))
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Pay Stub")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Employee Row

private struct EmployeeRowIOS: View {
    let employee: Employee

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(employee.fullName)
                .font(.headline)

            HStack {
                if employee.isActive {
                    Text("Active")
                        .foregroundStyle(.green)
                } else {
                    Text("Inactive")
                        .foregroundStyle(.secondary)
                }

                Text("•")

                Text(employee.payType.rawValue)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                Text(employee.payRate, format: .currency(code: "CAD"))
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text(employee.payType == .hourly ? "/hr" : "/yr")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Employee Detail

struct EmployeeDetailViewIOS: View {
    @Bindable var employee: Employee

    var body: some View {
        Form {
            Section("Personal") {
                TextField("First Name", text: $employee.firstName)
                TextField("Last Name", text: $employee.lastName)
                TextField("SIN", text: $employee.sinNumber)
                    .keyboardType(.numberPad)
            }

            Section("Contact") {
                TextField("Email", text: $employee.email)
                    .keyboardType(.emailAddress)
                TextField("Phone", text: $employee.phone)
                    .keyboardType(.phonePad)
                TextField("Address", text: $employee.address)
            }

            Section("Employment") {
                Picker("Status", selection: $employee.status) {
                    ForEach(EmploymentStatus.allCases, id: \.self) { status in
                        Text(status.rawValue).tag(status)
                    }
                }

                Picker("Pay Type", selection: $employee.payType) {
                    ForEach(PayType.allCases, id: \.self) { payType in
                        Text(payType.rawValue).tag(payType)
                    }
                }

                HStack {
                    Text(employee.payType == .hourly ? "Hourly Rate" : "Annual Salary")
                    Spacer()
                    TextField("Rate", value: $employee.payRate, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                DatePicker("Start Date", selection: $employee.startDate, displayedComponents: .date)
            }

            Section("Tax") {
                Picker("Province", selection: $employee.province) {
                    ForEach(Province.allCases, id: \.self) { province in
                        Text(province.rawValue).tag(province)
                    }
                }

                Picker("Federal TD1 Claim Code", selection: $employee.federalTD1ClaimCode) {
                    ForEach(1...10, id: \.self) { code in
                        Text("Code \(code)").tag(code)
                    }
                }

                Picker("Provincial TD1 Claim Code", selection: $employee.provincialTD1ClaimCode) {
                    ForEach(1...10, id: \.self) { code in
                        Text("Code \(code)").tag(code)
                    }
                }
            }
        }
        .navigationTitle(employee.fullName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Add Pay Run Sheet

private struct AddPayRunSheetIOS: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool

    @State private var periodStart = Date()
    @State private var periodEnd = Date()
    @State private var payDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Period Start", selection: $periodStart, displayedComponents: .date)
                DatePicker("Period End", selection: $periodEnd, displayedComponents: .date)
                DatePicker("Pay Date", selection: $payDate, displayedComponents: .date)
            }
            .navigationTitle("New Pay Run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createPayRun()
                        dismiss()
                    }
                }
            }
        }
    }

    private func createPayRun() {
        let payRun = PayRun(payPeriodStart: periodStart, payPeriodEnd: periodEnd, payDate: payDate)
        modelContext.insert(payRun)
        try? modelContext.save()
    }
}

// MARK: - Add Pay Stub Sheet

private struct AddPayStubSheetIOS: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Employee.lastName) private var employees: [Employee]
    let payRun: PayRun
    @Binding var isPresented: Bool

    @State private var selectedEmployee: Employee?
    @State private var regularHours: Double = 80

    private var activeEmployees: [Employee] {
        employees.filter { $0.isActive }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Employee", selection: $selectedEmployee) {
                    Text("Select Employee").tag(nil as Employee?)
                    ForEach(activeEmployees) { employee in
                        Text(employee.fullName).tag(employee as Employee?)
                    }
                }

                HStack {
                    Text("Regular Hours")
                    Spacer()
                    TextField("Hrs", value: $regularHours, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }
            .navigationTitle("Add Pay Stub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addStub()
                        dismiss()
                    }
                    .disabled(selectedEmployee == nil)
                }
            }
        }
    }

    private func addStub() {
        guard let employee = selectedEmployee else { return }
        let stub = PayStub()
        stub.employee = employee
        stub.payRun = payRun
        stub.regularHours = regularHours
        stub.regularRate = employee.payRate
        stub.overtimeRate = employee.payRate * 1.5
        if payRun.payStubs == nil { payRun.payStubs = [] }
        payRun.payStubs?.append(stub)
        modelContext.insert(stub)
        try? modelContext.save()
    }
}

// MARK: - Add Employee Sheet

private struct AddEmployeeSheetIOS: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var payRate: Double = 25

    var body: some View {
        NavigationStack {
            Form {
                TextField("First Name", text: $firstName)
                TextField("Last Name", text: $lastName)

                HStack {
                    Text("Hourly Rate")
                    Spacer()
                    TextField("Rate", value: $payRate, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
            }
            .navigationTitle("Add Employee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addEmployee()
                        dismiss()
                    }
                    .disabled(firstName.isEmpty || lastName.isEmpty)
                }
            }
        }
    }

    private func addEmployee() {
        let employee = Employee(firstName: firstName, lastName: lastName)
        employee.payRate = payRate
        modelContext.insert(employee)
        try? modelContext.save()
    }
}

#endif
