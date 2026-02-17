//
//  PayrollListView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-08.
//

import SwiftUI
import SwiftData

struct PayrollListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PayRun.payDate, order: .reverse) private var payRuns: [PayRun]
    @Query(filter: #Predicate<Employee> { $0.statusRaw == "Active" }, sort: \Employee.lastName) private var activeEmployees: [Employee]

    @State private var showingCreatePayRun = false
    @State private var selectedPayRun: PayRun?

    var body: some View {
        NavigationStack {
            List {
                // Quick stats
                if !payRuns.isEmpty {
                    Section {
                        HStack(spacing: 12) {
                            MetricCard(
                                title: "Active Employees",
                                value: "\(activeEmployees.count)",
                                style: .compact
                            )

                            if let lastRun = payRuns.first {
                                MetricCard(
                                    title: "Last Pay Run",
                                    value: lastRun.payDateString,
                                    style: .compact
                                )
                            }
                        }
                    }
                }

                if payRuns.isEmpty {
                    ContentUnavailableView {
                        Label("No Pay Runs", systemImage: "dollarsign.circle")
                    } description: {
                        Text("Create a pay run to process payroll")
                    } actions: {
                        Button("Create Pay Run") {
                            showingCreatePayRun = true
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(activeEmployees.isEmpty)
                    }
                } else {
                    // Group by year
                    let groupedRuns = Dictionary(grouping: payRuns) {
                        Calendar.current.component(.year, from: $0.payDate)
                    }

                    ForEach(groupedRuns.keys.sorted().reversed(), id: \.self) { year in
                        Section {
                            ForEach(groupedRuns[year] ?? []) { payRun in
                                PayRunRow(payRun: payRun)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedPayRun = payRun
                                    }
                            }
                            .onDelete { indexSet in
                                deletePayRuns(at: indexSet, in: year, from: groupedRuns)
                            }
                        } header: {
                            Text(String(year))
                        }
                    }
                }
            }
            .navigationTitle("Payroll")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreatePayRun = true
                    } label: {
                        Label("New Pay Run", systemImage: "plus")
                    }
                    .disabled(activeEmployees.isEmpty)
                }
            }
            .sheet(isPresented: $showingCreatePayRun) {
                PayRunEditorView(payRun: nil)
            }
            .sheet(item: $selectedPayRun) { payRun in
                PayRunDetailView(payRun: payRun)
            }
        }
    }

    private func deletePayRuns(at offsets: IndexSet, in year: Int, from groupedRuns: [Int: [PayRun]]) {
        guard let runsInYear = groupedRuns[year] else { return }
        for index in offsets {
            let payRun = runsInYear[index]
            // Don't allow deleting finalized pay runs
            if !payRun.isFinalized {
                modelContext.delete(payRun)
            }
        }
        try? modelContext.save()
    }
}

// MARK: - Pay Run Row

struct PayRunRow: View {
    let payRun: PayRun

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(payRun.periodString)
                        .fontWeight(.medium)

                    if payRun.isFinalized {
                        Label("Finalized", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Label("Draft", systemImage: "pencil.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Text("Pay Date: \(payRun.payDateString)")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("\(payRun.payStubs?.count ?? 0) employees")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(payRun.totalNet, format: .currency(code: "CAD"))
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)

                Text("Gross: \(payRun.totalGross, format: .currency(code: "CAD"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Pay Run Editor (Create New)

struct PayRunEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Employee> { $0.statusRaw == "Active" }, sort: \Employee.lastName) private var activeEmployees: [Employee]

    let payRun: PayRun?

    @State private var payPeriodStart = Date.now.addingTimeInterval(-14 * 24 * 60 * 60)
    @State private var payPeriodEnd = Date.now
    @State private var payDate = Date.now
    @State private var payFrequency: PayFrequency = .biWeekly
    @State private var selectedEmployees: Set<UUID> = []
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Pay Period") {
                    DatePicker("Period Start", selection: $payPeriodStart, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "en_GB"))
                    DatePicker("Period End", selection: $payPeriodEnd, in: payPeriodStart..., displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "en_GB"))
                    DatePicker("Pay Date", selection: $payDate, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "en_GB"))

                    Picker("Pay Frequency", selection: $payFrequency) {
                        ForEach(PayFrequency.allCases, id: \.self) { freq in
                            Text(freq.rawValue).tag(freq)
                        }
                    }
                }

                Section("Employees (\(selectedEmployees.count) selected)") {
                    ForEach(activeEmployees) { employee in
                        Button {
                            if selectedEmployees.contains(employee.id) {
                                selectedEmployees.remove(employee.id)
                            } else {
                                selectedEmployees.insert(employee.id)
                            }
                        } label: {
                            HStack {
                                Image(systemName: selectedEmployees.contains(employee.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedEmployees.contains(employee.id) ? .blue : .secondary)

                                Text(employee.fullName)

                                Spacer()

                                if employee.payType == .hourly {
                                    Text("\(employee.payRate, format: .currency(code: "CAD"))/hr")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("\(employee.salaryPerPeriod, format: .currency(code: "CAD"))/period")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    HStack {
                        Button("Select All") {
                            for emp in activeEmployees {
                                selectedEmployees.insert(emp.id)
                            }
                        }
                        .buttonStyle(.bordered)

                        Button("Clear") {
                            selectedEmployees.removeAll()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 40)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Create Pay Run")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createPayRun() }
                        .disabled(selectedEmployees.isEmpty)
                }
            }
            .onAppear {
                // Select all employees by default
                for emp in activeEmployees {
                    selectedEmployees.insert(emp.id)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 550)
    }

    private func createPayRun() {
        let run = PayRun(payPeriodStart: payPeriodStart, payPeriodEnd: payPeriodEnd, payDate: payDate)
        run.payFrequency = payFrequency
        run.notes = notes

        modelContext.insert(run)

        // Create pay stubs for selected employees
        let selectedEmps = activeEmployees.filter { selectedEmployees.contains($0.id) }

        for employee in selectedEmps {
            let stub = PayStub()
            stub.employee = employee
            stub.payRun = run
            stub.regularRate = employee.payType == .hourly ? employee.payRate : employee.salaryPerPeriod / 80.0 // Assume 80 hours bi-weekly
            stub.overtimeRate = stub.regularRate * 1.5

            // For salary employees, auto-fill standard hours
            if employee.payType == .salary {
                switch payFrequency {
                case .weekly: stub.regularHours = 40
                case .biWeekly: stub.regularHours = 80
                case .semiMonthly: stub.regularHours = 86.67
                case .monthly: stub.regularHours = 173.33
                }
            }

            if run.payStubs == nil { run.payStubs = [] }
            run.payStubs?.append(stub)
            modelContext.insert(stub)
        }

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Pay Run Detail View

struct PayRunDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var payRun: PayRun

    @State private var selectedStub: PayStub?
    @State private var showingFinalizeConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Period")
                        Spacer()
                        Text(payRun.periodString)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Pay Date")
                        Spacer()
                        Text(payRun.payDateString)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Status")
                        Spacer()
                        if payRun.isFinalized {
                            Label("Finalized", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Draft", systemImage: "pencil.circle")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Total Gross")
                        Spacer()
                        Text(payRun.totalGross, format: .currency(code: "CAD"))
                            .fontWeight(.medium)
                    }
                    HStack {
                        Text("Total Deductions")
                        Spacer()
                        Text(payRun.totalDeductions, format: .currency(code: "CAD"))
                            .foregroundStyle(.red)
                    }
                    HStack {
                        Text("Total Net Pay")
                            .fontWeight(.bold)
                        Spacer()
                        Text(payRun.totalNet, format: .currency(code: "CAD"))
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                    }
                }

                Section("Pay Stubs") {
                    ForEach(payRun.payStubs ?? []) { stub in
                        PayStubRow(stub: stub)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedStub = stub
                            }
                    }
                }

                if !payRun.isFinalized {
                    Section {
                        Button {
                            showingFinalizeConfirm = true
                        } label: {
                            Label("Finalize Pay Run", systemImage: "checkmark.seal")
                        }
                        .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Pay Run")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $selectedStub) { stub in
                PayStubEditorView(stub: stub, payRun: payRun)
            }
            .confirmationDialog("Finalize Pay Run?", isPresented: $showingFinalizeConfirm) {
                Button("Finalize") {
                    finalizePayRun()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will lock the pay run and update employee YTD totals. This cannot be undone.")
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }

    private func finalizePayRun() {
        // Update employee YTD values
        for stub in payRun.payStubs ?? [] {
            guard let employee = stub.employee else { continue }

            // Check if we need to reset YTD for new year
            let payYear = Calendar.current.component(.year, from: payRun.payDate)
            if employee.ytdYear != payYear {
                employee.ytdGrossPay = 0
                employee.ytdCPP = 0
                employee.ytdEI = 0
                employee.ytdFederalTax = 0
                employee.ytdProvincialTax = 0
                employee.ytdVacationPay = 0
                employee.ytdVacationUsed = 0
                employee.ytdYear = payYear
            }

            // Update YTD
            employee.ytdGrossPay += stub.grossPay
            employee.ytdCPP += stub.cppDeduction
            employee.ytdEI += stub.eiDeduction
            employee.ytdFederalTax += stub.federalTax
            employee.ytdProvincialTax += stub.provincialTax
            employee.ytdVacationPay += stub.vacationAccrued
            employee.ytdVacationUsed += stub.vacationPayout

            // Snapshot YTD values on stub
            stub.ytdGrossPay = employee.ytdGrossPay
            stub.ytdCPP = employee.ytdCPP
            stub.ytdEI = employee.ytdEI
            stub.ytdFederalTax = employee.ytdFederalTax
            stub.ytdProvincialTax = employee.ytdProvincialTax
            stub.ytdVacationAccrued = employee.ytdVacationPay
            stub.ytdVacationUsed = employee.ytdVacationUsed
        }

        payRun.isFinalized = true
        payRun.finalizedAt = Date.now

        try? modelContext.save()
    }
}

// MARK: - Pay Stub Row

struct PayStubRow: View {
    let stub: PayStub

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(stub.employee?.fullName ?? "Unknown")
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text("\(stub.totalHours, specifier: "%.1f") hrs")
                    if stub.overtimeHours > 0 {
                        Text("(\(stub.overtimeHours, specifier: "%.1f") OT)")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(stub.netPay, format: .currency(code: "CAD"))
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)

                Text("Gross: \(stub.grossPay, format: .currency(code: "CAD"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    PayrollListView()
}
