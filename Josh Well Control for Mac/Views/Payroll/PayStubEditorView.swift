//
//  PayStubEditorView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-08.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct PayStubEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var stub: PayStub
    let payRun: PayRun

    // Hours
    @State private var regularHours: Double = 0
    @State private var overtimeHours: Double = 0
    @State private var holidayHours: Double = 0
    @State private var sickHours: Double = 0
    @State private var vacationHours: Double = 0

    // Rates
    @State private var regularRate: Double = 0
    @State private var overtimeRate: Double = 0

    // Other earnings
    @State private var vacationPayout: Double = 0
    @State private var otherEarnings: Double = 0
    @State private var otherEarningsDescription = ""

    // Other deductions
    @State private var otherDeductions: Double = 0
    @State private var otherDeductionsDescription = ""

    @State private var notes = ""
    @State private var isCalculated = false

    private var employee: Employee? {
        stub.employee
    }

    var body: some View {
        NavigationStack {
            Form {
                if let emp = employee {
                    Section {
                        HStack {
                            Text("Employee")
                            Spacer()
                            Text(emp.fullName)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Pay Type")
                            Spacer()
                            Text(emp.payType.rawValue)
                                .foregroundStyle(.secondary)
                        }
                        if emp.payType == .salary {
                            HStack {
                                Text("Salary per Period")
                                Spacer()
                                Text(emp.salaryPerPeriod, format: .currency(code: "CAD"))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Hours Worked") {
                    HStack {
                        Text("Regular Hours")
                        Spacer()
                        TextField("hrs", value: $regularHours, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Overtime Hours")
                        Spacer()
                        TextField("hrs", value: $overtimeHours, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Holiday Hours")
                        Spacer()
                        TextField("hrs", value: $holidayHours, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Sick Hours")
                        Spacer()
                        TextField("hrs", value: $sickHours, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Vacation Hours")
                        Spacer()
                        TextField("hrs", value: $vacationHours, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("Total Hours")
                            .fontWeight(.medium)
                        Spacer()
                        let total = regularHours + overtimeHours + holidayHours + sickHours + vacationHours
                        Text("\(total, specifier: "%.2f")")
                            .fontWeight(.medium)
                    }
                }

                Section("Rates") {
                    HStack {
                        Text("Regular Rate")
                        Spacer()
                        TextField("rate", value: $regularRate, format: .currency(code: "CAD"))
                            .frame(width: 100)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Overtime Rate (1.5x)")
                        Spacer()
                        TextField("rate", value: $overtimeRate, format: .currency(code: "CAD"))
                            .frame(width: 100)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Additional Earnings") {
                    HStack {
                        Text("Vacation Payout")
                        Spacer()
                        TextField("amount", value: $vacationPayout, format: .currency(code: "CAD"))
                            .frame(width: 100)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                    }
                    if let emp = employee {
                        Text("Available: \(emp.vacationPayBalance, format: .currency(code: "CAD"))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    TextField("Other Earnings Description", text: $otherEarningsDescription)
                    HStack {
                        Text("Other Earnings")
                        Spacer()
                        TextField("amount", value: $otherEarnings, format: .currency(code: "CAD"))
                            .frame(width: 100)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Additional Deductions") {
                    TextField("Other Deductions Description", text: $otherDeductionsDescription)
                    HStack {
                        Text("Other Deductions")
                        Spacer()
                        TextField("amount", value: $otherDeductions, format: .currency(code: "CAD"))
                            .frame(width: 100)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                    }
                }

                if isCalculated {
                    Section("Earnings") {
                        HStack {
                            Text("Regular")
                            Spacer()
                            Text(stub.regularEarnings, format: .currency(code: "CAD"))
                        }
                        if stub.overtimeEarnings > 0 {
                            HStack {
                                Text("Overtime")
                                Spacer()
                                Text(stub.overtimeEarnings, format: .currency(code: "CAD"))
                            }
                        }
                        if stub.holidayPay > 0 {
                            HStack {
                                Text("Holiday")
                                Spacer()
                                Text(stub.holidayPay, format: .currency(code: "CAD"))
                            }
                        }
                        if stub.sickPay > 0 {
                            HStack {
                                Text("Sick")
                                Spacer()
                                Text(stub.sickPay, format: .currency(code: "CAD"))
                            }
                        }
                        if stub.vacationPayout > 0 {
                            HStack {
                                Text("Vacation Payout")
                                Spacer()
                                Text(stub.vacationPayout, format: .currency(code: "CAD"))
                            }
                        }
                        if stub.otherEarnings > 0 {
                            HStack {
                                Text(stub.otherEarningsDescription.isEmpty ? "Other" : stub.otherEarningsDescription)
                                Spacer()
                                Text(stub.otherEarnings, format: .currency(code: "CAD"))
                            }
                        }
                        Divider()
                        HStack {
                            Text("Gross Pay")
                                .fontWeight(.bold)
                            Spacer()
                            Text(stub.grossPay, format: .currency(code: "CAD"))
                                .fontWeight(.bold)
                        }
                    }

                    Section("Deductions") {
                        HStack {
                            Text("CPP")
                            Spacer()
                            Text(stub.cppDeduction, format: .currency(code: "CAD"))
                                .foregroundStyle(.red)
                        }
                        HStack {
                            Text("EI")
                            Spacer()
                            Text(stub.eiDeduction, format: .currency(code: "CAD"))
                                .foregroundStyle(.red)
                        }
                        HStack {
                            Text("Federal Tax")
                            Spacer()
                            Text(stub.federalTax, format: .currency(code: "CAD"))
                                .foregroundStyle(.red)
                        }
                        HStack {
                            Text("Provincial Tax")
                            Spacer()
                            Text(stub.provincialTax, format: .currency(code: "CAD"))
                                .foregroundStyle(.red)
                        }
                        if stub.otherDeductions > 0 {
                            HStack {
                                Text(stub.otherDeductionsDescription.isEmpty ? "Other" : stub.otherDeductionsDescription)
                                Spacer()
                                Text(stub.otherDeductions, format: .currency(code: "CAD"))
                                    .foregroundStyle(.red)
                            }
                        }
                        Divider()
                        HStack {
                            Text("Total Deductions")
                                .fontWeight(.medium)
                            Spacer()
                            Text(stub.totalDeductions, format: .currency(code: "CAD"))
                                .fontWeight(.medium)
                                .foregroundStyle(.red)
                        }
                    }

                    Section("Net Pay") {
                        HStack {
                            Text("Net Pay")
                                .font(.title2)
                                .fontWeight(.bold)
                            Spacer()
                            Text(stub.netPay, format: .currency(code: "CAD"))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.green)
                        }

                        HStack {
                            Text("Vacation Accrued")
                            Spacer()
                            Text(stub.vacationAccrued, format: .currency(code: "CAD"))
                                .foregroundStyle(.blue)
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 40)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Pay Stub")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Calculate") {
                        calculatePayStub()
                    }
                    .disabled(payRun.isFinalized)

                    Button("Save") {
                        save()
                    }
                    .disabled(payRun.isFinalized)

                    if isCalculated {
                        Button("Export PDF") {
                            exportPDF()
                        }
                    }
                }
            }
            .onAppear { loadStub() }
        }
        .frame(minWidth: 550, minHeight: 700)
    }

    private func loadStub() {
        regularHours = stub.regularHours
        overtimeHours = stub.overtimeHours
        holidayHours = stub.holidayHours
        sickHours = stub.sickHours
        vacationHours = stub.vacationHours
        regularRate = stub.regularRate
        overtimeRate = stub.overtimeRate
        vacationPayout = stub.vacationPayout
        otherEarnings = stub.otherEarnings
        otherEarningsDescription = stub.otherEarningsDescription
        otherDeductions = stub.otherDeductions
        otherDeductionsDescription = stub.otherDeductionsDescription
        notes = stub.notes

        // If stub has already been calculated, show results
        isCalculated = stub.grossPay > 0
    }

    private func calculatePayStub() {
        guard let emp = employee else { return }

        // Update stub with current values
        stub.regularHours = regularHours
        stub.overtimeHours = overtimeHours
        stub.holidayHours = holidayHours
        stub.sickHours = sickHours
        stub.vacationHours = vacationHours
        stub.regularRate = regularRate
        stub.overtimeRate = overtimeRate
        stub.vacationPayout = vacationPayout
        stub.otherEarnings = otherEarnings
        stub.otherEarningsDescription = otherEarningsDescription
        stub.otherDeductions = otherDeductions
        stub.otherDeductionsDescription = otherDeductionsDescription

        // Calculate pay
        stub.calculate(employee: emp, ytdCPP: emp.ytdCPP, ytdEI: emp.ytdEI)

        isCalculated = true
    }

    private func save() {
        stub.regularHours = regularHours
        stub.overtimeHours = overtimeHours
        stub.holidayHours = holidayHours
        stub.sickHours = sickHours
        stub.vacationHours = vacationHours
        stub.regularRate = regularRate
        stub.overtimeRate = overtimeRate
        stub.vacationPayout = vacationPayout
        stub.otherEarnings = otherEarnings
        stub.otherEarningsDescription = otherEarningsDescription
        stub.otherDeductions = otherDeductions
        stub.otherDeductionsDescription = otherDeductionsDescription
        stub.notes = notes

        try? modelContext.save()
        dismiss()
    }

    private func exportPDF() {
        guard let data = PayStubPDFGenerator.shared.generatePDF(for: stub, payRun: payRun) else {
            return
        }

        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let employeeName = stub.employee?.fullName.replacingOccurrences(of: " ", with: "_") ?? "Unknown"
        panel.nameFieldStringValue = "PayStub_\(employeeName)_\(payRun.payDateString.replacingOccurrences(of: " ", with: "_")).pdf"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? data.write(to: url)
                NSWorkspace.shared.open(url)
            }
        }
        #endif
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: PayStub.self, PayRun.self, Employee.self, configurations: config)

    let emp = Employee(firstName: "John", lastName: "Doe")
    emp.payRate = 35.0
    emp.payType = .hourly
    container.mainContext.insert(emp)

    let run = PayRun()
    container.mainContext.insert(run)

    let stub = PayStub()
    stub.employee = emp
    stub.payRun = run
    stub.regularRate = 35.0
    stub.overtimeRate = 52.50
    container.mainContext.insert(stub)

    return PayStubEditorView(stub: stub, payRun: run)
        .modelContainer(container)
}
