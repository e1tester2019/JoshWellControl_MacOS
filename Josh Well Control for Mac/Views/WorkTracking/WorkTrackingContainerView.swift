//
//  WorkTrackingContainerView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-08.
//

#if os(macOS)
import SwiftUI
import SwiftData

struct WorkTrackingContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isUnlocked = false
    @State private var pinEntry = ""
    @State private var showError = false
    @State private var isSettingPin = false
    @State private var newPin = ""
    @State private var confirmPin = ""

    var body: some View {
        Group {
            if isUnlocked {
                WorkTrackingMainView()
            } else {
                pinEntryView
            }
        }
        .onAppear {
            // Auto-unlock if no PIN is set
            if !WorkTrackingAuth.hasPin {
                isSettingPin = true
            }
        }
    }

    private var pinEntryView: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            if isSettingPin {
                setPinView
            } else {
                enterPinView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var enterPinView: some View {
        VStack(spacing: 16) {
            Text("Enter PIN")
                .font(.title2)
                .fontWeight(.semibold)

            SecureField("PIN", text: $pinEntry)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit { verifyPin() }

            if showError {
                Text("Incorrect PIN")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack(spacing: 12) {
                Button("Unlock") { verifyPin() }
                    .buttonStyle(.borderedProminent)
                    .disabled(pinEntry.isEmpty)

                Button("Reset PIN") {
                    isSettingPin = true
                    pinEntry = ""
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var setPinView: some View {
        VStack(spacing: 16) {
            Text(WorkTrackingAuth.hasPin ? "Reset PIN" : "Set Up PIN")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Protect your work tracking data with a PIN")
                .foregroundStyle(.secondary)
                .font(.callout)

            if WorkTrackingAuth.hasPin {
                SecureField("Current PIN", text: $pinEntry)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }

            SecureField("New PIN", text: $newPin)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)

            SecureField("Confirm PIN", text: $confirmPin)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit { setNewPin() }

            if showError {
                Text("PINs don't match or current PIN is incorrect")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack(spacing: 12) {
                Button("Save PIN") { setNewPin() }
                    .buttonStyle(.borderedProminent)
                    .disabled(newPin.isEmpty || confirmPin.isEmpty)

                if WorkTrackingAuth.hasPin {
                    Button("Cancel") {
                        isSettingPin = false
                        newPin = ""
                        confirmPin = ""
                        pinEntry = ""
                        showError = false
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func verifyPin() {
        if WorkTrackingAuth.verifyPin(pinEntry) {
            isUnlocked = true
            showError = false
        } else {
            showError = true
            pinEntry = ""
        }
    }

    private func setNewPin() {
        // Verify current PIN if one exists
        if WorkTrackingAuth.hasPin && !WorkTrackingAuth.verifyPin(pinEntry) {
            showError = true
            return
        }

        // Verify new PINs match
        if newPin != confirmPin {
            showError = true
            return
        }

        WorkTrackingAuth.setPin(newPin)
        isUnlocked = true
        isSettingPin = false
        showError = false
        newPin = ""
        confirmPin = ""
        pinEntry = ""
    }
}

// MARK: - Main Work Tracking View

struct WorkTrackingMainView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab = 0
    @State private var showingSettings = false

    var body: some View {
        TabView(selection: $selectedTab) {
            // Work & Invoicing
            WorkDayListView()
                .tabItem {
                    Label("Work Days", systemImage: "calendar")
                }
                .tag(0)

            InvoiceListView()
                .tabItem {
                    Label("Invoices", systemImage: "doc.text")
                }
                .tag(1)

            // Expenses
            ExpenseListView()
                .tabItem {
                    Label("Expenses", systemImage: "dollarsign.circle")
                }
                .tag(2)

            MileageLogView()
                .tabItem {
                    Label("Mileage", systemImage: "car.fill")
                }
                .tag(3)

            // Payroll
            PayrollListView()
                .tabItem {
                    Label("Payroll", systemImage: "banknote")
                }
                .tag(4)

            EmployeeListView()
                .tabItem {
                    Label("Employees", systemImage: "person.3")
                }
                .tag(5)

            // Dividends
            DividendListView()
                .tabItem {
                    Label("Dividends", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(6)

            DividendStatementView()
                .tabItem {
                    Label("Dividend Statements", systemImage: "doc.text.magnifyingglass")
                }
                .tag(7)

            // Reports
            CompanyStatementView()
                .tabItem {
                    Label("Company Statements", systemImage: "building.2")
                }
                .tag(8)

            ExpenseReportView()
                .tabItem {
                    Label("Expense Report", systemImage: "chart.bar")
                }
                .tag(9)

            PayrollReportView()
                .tabItem {
                    Label("Payroll Report", systemImage: "chart.pie")
                }
                .tag(10)

            // Settings
            ClientListView()
                .tabItem {
                    Label("Clients", systemImage: "person.2")
                }
                .tag(11)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            BusinessInfoSettingsView()
        }
    }
}

// MARK: - Preview

#Preview {
    WorkTrackingContainerView()
}
#endif
