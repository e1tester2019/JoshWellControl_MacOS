//
//  WorkDayListView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-08.
//

import SwiftUI
import SwiftData

struct WorkDayListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkDay.startDate, order: .reverse) private var workDays: [WorkDay]
    @Query(sort: \Well.name) private var wells: [Well]
    @Query(sort: \Client.companyName) private var clients: [Client]

    @State private var showingAddSheet = false
    @State private var selectedWorkDay: WorkDay?

    // Filters
    @State private var filterWell: Well?
    @State private var filterClient: Client?
    @State private var filterStatus: StatusFilter = .all
    @State private var filterStartDate: Date?
    @State private var filterEndDate: Date?
    @State private var showFilters = false

    enum StatusFilter: String, CaseIterable {
        case all = "All"
        case uninvoiced = "Uninvoiced"
        case invoiced = "Invoiced (Unpaid)"
        case paid = "Paid"
    }

    private var filteredWorkDays: [WorkDay] {
        workDays.filter { wd in
            // Well filter
            if let well = filterWell, wd.well?.id != well.id {
                return false
            }
            // Client filter
            if let client = filterClient, wd.client?.id != client.id {
                return false
            }
            // Status filter
            switch filterStatus {
            case .all:
                break
            case .uninvoiced:
                if wd.isInvoiced { return false }
            case .invoiced:
                if !wd.isInvoiced || wd.isPaid { return false }
            case .paid:
                if !wd.isPaid { return false }
            }
            // Date range filter
            if let start = filterStartDate, wd.startDate < start {
                return false
            }
            if let end = filterEndDate, wd.startDate > end {
                return false
            }
            return true
        }
    }

    private var hasActiveFilters: Bool {
        filterWell != nil || filterClient != nil || filterStatus != .all || filterStartDate != nil || filterEndDate != nil
    }

    var body: some View {
        NavigationStack {
            List {
                // Filter section
                Section {
                    DisclosureGroup(isExpanded: $showFilters) {
                        Picker("Client", selection: $filterClient) {
                            Text("All Clients").tag(nil as Client?)
                            ForEach(clients) { client in
                                Text(client.companyName).tag(client as Client?)
                            }
                        }

                        Picker("Well", selection: $filterWell) {
                            Text("All Wells").tag(nil as Well?)
                            ForEach(wells) { well in
                                Text(well.name).tag(well as Well?)
                            }
                        }

                        Picker("Status", selection: $filterStatus) {
                            ForEach(StatusFilter.allCases, id: \.self) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }

                        HStack {
                            DatePicker("From", selection: Binding(
                                get: { filterStartDate ?? Date.distantPast },
                                set: { filterStartDate = $0 }
                            ), displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "en_GB"))

                            Button {
                                filterStartDate = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .opacity(filterStartDate == nil ? 0 : 1)
                        }

                        HStack {
                            DatePicker("To", selection: Binding(
                                get: { filterEndDate ?? Date.now },
                                set: { filterEndDate = $0 }
                            ), displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "en_GB"))

                            Button {
                                filterEndDate = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .opacity(filterEndDate == nil ? 0 : 1)
                        }

                        if hasActiveFilters {
                            Button("Clear Filters") {
                                filterWell = nil
                                filterClient = nil
                                filterStatus = .all
                                filterStartDate = nil
                                filterEndDate = nil
                            }
                        }
                    } label: {
                        HStack {
                            Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                            if hasActiveFilters {
                                Spacer()
                                Text("\(filteredWorkDays.count) of \(workDays.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if workDays.isEmpty {
                    ContentUnavailableView {
                        Label("No Work Days", systemImage: "calendar.badge.plus")
                    } description: {
                        Text("Log your first work period to start tracking")
                    } actions: {
                        Button("Add Work Period") {
                            showingAddSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if filteredWorkDays.isEmpty {
                    ContentUnavailableView {
                        Label("No Matches", systemImage: "magnifyingglass")
                    } description: {
                        Text("No work days match your filters")
                    } actions: {
                        Button("Clear Filters") {
                            filterWell = nil
                            filterClient = nil
                            filterStatus = .all
                            filterStartDate = nil
                            filterEndDate = nil
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    // Group by month
                    ForEach(groupedWorkDays.keys.sorted().reversed(), id: \.self) { monthKey in
                        Section {
                            ForEach(groupedWorkDays[monthKey] ?? []) { workDay in
                                WorkDayRow(workDay: workDay)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedWorkDay = workDay
                                    }
                                    .contextMenu {
                                        Button("Edit") {
                                            selectedWorkDay = workDay
                                        }
                                        Divider()
                                        Button("Delete", role: .destructive) {
                                            modelContext.delete(workDay)
                                            try? modelContext.save()
                                        }
                                    }
                            }
                            .onDelete { indexSet in
                                deleteWorkDays(at: indexSet, in: monthKey)
                            }
                        } header: {
                            HStack {
                                Text(monthKey)
                                Spacer()
                                let totalDays = (groupedWorkDays[monthKey] ?? []).reduce(0) { $0 + $1.dayCount }
                                Text("\(totalDays) day\(totalDays == 1 ? "" : "s")")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Work Days")
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
                WorkDayEditorView(workDay: nil)
            }
            .sheet(item: $selectedWorkDay) { workDay in
                WorkDayEditorView(workDay: workDay)
            }
        }
    }

    private var groupedWorkDays: [String: [WorkDay]] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return Dictionary(grouping: filteredWorkDays) { formatter.string(from: $0.startDate) }
    }

    private func deleteWorkDays(at offsets: IndexSet, in monthKey: String) {
        guard let daysInMonth = groupedWorkDays[monthKey] else { return }
        for index in offsets {
            let workDay = daysInMonth[index]
            modelContext.delete(workDay)
        }
        try? modelContext.save()
    }
}

// MARK: - Work Day Row

struct WorkDayRow: View {
    let workDay: WorkDay

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(workDay.dateRangeString)
                        .fontWeight(.medium)
                    if workDay.dayCount > 1 {
                        Text("(\(workDay.dayCount) days)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                if let well = workDay.well {
                    HStack(spacing: 8) {
                        Text(well.name)
                        if let afe = well.afeNumber, !afe.isEmpty {
                            Text("AFE: \(afe)")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    if let client = workDay.client {
                        Text(client.companyName)
                    }
                    let rigName = workDay.effectiveRigName
                    if !rigName.isEmpty {
                        Text(rigName)
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(workDay.totalEarnings, format: .currency(code: "CAD"))
                    .fontWeight(.semibold)

                if workDay.totalMileage > 0 {
                    Text("\(Int(workDay.totalMileage)) km")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if workDay.isPaid {
                    Label("Paid", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if workDay.isInvoiced {
                    Label("Invoiced", systemImage: "doc.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Work Day Editor

struct WorkDayEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Well.name) private var wells: [Well]
    @Query(sort: \Client.companyName) private var clients: [Client]

    let workDay: WorkDay?

    @State private var startDate = Date.now
    @State private var endDate = Date.now
    @State private var selectedWell: Well?
    @State private var selectedClient: Client?
    @State private var notes = ""
    @State private var dayRateOverride: Double?
    @State private var useCustomRate = false
    @State private var customRateReason: String = ""
    @State private var rigNameOverride = ""
    @State private var costCodeOverride = ""
    @State private var useCustomRig = false
    @State private var useCustomCostCode = false
    @State private var mileageToLocation: Double = 0
    @State private var mileageFromLocation: Double = 0
    @State private var mileageInField: Double = 0
    @State private var mileageCommute: Double = 0
    @State private var manuallyMarkedInvoiced: Bool = false
    @State private var manuallyMarkedPaid: Bool = false
    @State private var manualPaidDate: Date = Date.now
    @State private var showDeleteConfirmation: Bool = false

    private var dayCount: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        let components = calendar.dateComponents([.day], from: start, to: end)
        return max(1, (components.day ?? 0) + 1)
    }

    private var effectiveRate: Double {
        if useCustomRate, let rate = dayRateOverride {
            return rate
        }
        return selectedClient?.dayRate ?? 1625.00
    }

    private var totalMileage: Double {
        mileageToLocation + mileageFromLocation + mileageInField + mileageCommute
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Date Range") {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "en_GB"))
                    DatePicker("End Date", selection: $endDate, in: startDate..., displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "en_GB"))

                    HStack {
                        Text("Days")
                        Spacer()
                        Text("\(dayCount)")
                            .fontWeight(.medium)
                    }
                }

                Section("Assignment") {
                    Picker("Client", selection: $selectedClient) {
                        Text("None").tag(nil as Client?)
                        ForEach(clients) { client in
                            Text(client.companyName).tag(client as Client?)
                        }
                    }

                    Picker("Well", selection: $selectedWell) {
                        Text("None").tag(nil as Well?)
                        ForEach(wells) { well in
                            VStack(alignment: .leading) {
                                Text(well.name)
                                if let afe = well.afeNumber, !afe.isEmpty {
                                    Text("AFE: \(afe)").font(.caption).foregroundStyle(.secondary)
                                }
                            }.tag(well as Well?)
                        }
                    }

                    if let well = selectedWell {
                        if let afe = well.afeNumber, !afe.isEmpty {
                            HStack {
                                Text("AFE")
                                Spacer()
                                Text(afe).foregroundStyle(.secondary)
                            }
                        }
                        if let rig = well.rigName, !rig.isEmpty {
                            HStack {
                                Text("Rig")
                                Spacer()
                                Text(rig).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Day Rate") {
                    Toggle("Use custom rate", isOn: $useCustomRate)

                    if useCustomRate {
                        HStack {
                            Text("Rate per day")
                            Spacer()
                            TextField("Rate", value: $dayRateOverride, format: .currency(code: "CAD"))
                                .frame(width: 120)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                        }

                        TextField("Reason for custom rate (appears on invoice)", text: $customRateReason)
                    } else if let client = selectedClient {
                        HStack {
                            Text("Client Rate")
                            Spacer()
                            Text(client.dayRate, format: .currency(code: "CAD"))
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Text("Total (\(dayCount) days)")
                            .fontWeight(.medium)
                        Spacer()
                        Text(Double(dayCount) * effectiveRate, format: .currency(code: "CAD"))
                            .fontWeight(.semibold)
                    }
                }

                Section("Mileage") {
                    HStack {
                        Text("To Location")
                        Spacer()
                        TextField("km", value: $mileageToLocation, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                        Text("km")
                    }

                    HStack {
                        Text("From Location")
                        Spacer()
                        TextField("km", value: $mileageFromLocation, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                        Text("km")
                    }

                    HStack {
                        Text("In Field")
                        Spacer()
                        TextField("km", value: $mileageInField, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                        Text("km")
                    }

                    HStack {
                        Text("Commute")
                        Spacer()
                        TextField("km", value: $mileageCommute, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                        Text("km")
                    }

                    if let client = selectedClient, totalMileage > 0 {
                        Divider()

                        HStack {
                            Text("Total")
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(Int(totalMileage)) km")
                                .fontWeight(.medium)
                        }

                        let cappedMileage = min(totalMileage, client.maxMileage)
                        HStack {
                            Text("Mileage cost")
                            Spacer()
                            Text(cappedMileage * client.mileageRate, format: .currency(code: "CAD"))
                                .foregroundStyle(.secondary)
                        }
                        if totalMileage > client.maxMileage {
                            Text("Capped at \(Int(client.maxMileage)) km total")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section("Overrides (optional)") {
                    Toggle("Custom rig name", isOn: $useCustomRig)
                    if useCustomRig {
                        TextField("Rig Name", text: $rigNameOverride)
                    }

                    Toggle("Custom cost code", isOn: $useCustomCostCode)
                    if useCustomCostCode {
                        TextField("Cost Code", text: $costCodeOverride)
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }

                Section("Invoicing Status") {
                    if workDay?.lineItem != nil {
                        Label("Linked to invoice #\(workDay?.lineItem?.invoice?.invoiceNumber ?? 0)", systemImage: "link.circle.fill")
                            .foregroundStyle(.blue)
                    } else {
                        Toggle("Mark as Invoiced", isOn: $manuallyMarkedInvoiced)

                        if manuallyMarkedInvoiced {
                            Toggle("Mark as Paid", isOn: $manuallyMarkedPaid)

                            if manuallyMarkedPaid {
                                DatePicker("Paid Date", selection: $manualPaidDate, displayedComponents: .date)
                                    .environment(\.locale, Locale(identifier: "en_GB"))
                            }
                        }
                    }
                }

                if workDay != nil {
                    Section {
                        Button("Delete Work Day", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(workDay == nil ? "Add Work Period" : "Edit Work Period")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(selectedWell == nil || selectedClient == nil)
                }
            }
            .onAppear { loadWorkDay() }
            .confirmationDialog(
                "Delete Work Day",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let wd = workDay {
                        modelContext.delete(wd)
                        try? modelContext.save()
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete this work day? This action cannot be undone.")
            }
        }
        .frame(minWidth: 450, minHeight: 550)
    }

    private func loadWorkDay() {
        guard let wd = workDay else { return }
        startDate = wd.startDate
        endDate = wd.endDate
        selectedWell = wd.well
        selectedClient = wd.client
        notes = wd.notes
        dayRateOverride = wd.dayRateOverride
        useCustomRate = wd.dayRateOverride != nil
        customRateReason = wd.customRateReason
        rigNameOverride = wd.rigNameOverride ?? ""
        costCodeOverride = wd.costCodeOverride ?? ""
        useCustomRig = wd.rigNameOverride != nil
        useCustomCostCode = wd.costCodeOverride != nil
        mileageToLocation = wd.mileageToLocation
        mileageFromLocation = wd.mileageFromLocation
        mileageInField = wd.mileageInField
        mileageCommute = wd.mileageCommute
        manuallyMarkedInvoiced = wd.manuallyMarkedInvoiced
        manuallyMarkedPaid = wd.manuallyMarkedPaid
        manualPaidDate = wd.manualPaidDate ?? Date.now
    }

    private func save() {
        let wd = workDay ?? WorkDay()
        wd.startDate = startDate
        wd.endDate = endDate
        wd.well = selectedWell
        wd.client = selectedClient
        wd.notes = notes
        wd.dayRateOverride = useCustomRate ? dayRateOverride : nil
        wd.customRateReason = useCustomRate ? customRateReason : ""
        wd.rigNameOverride = useCustomRig && !rigNameOverride.isEmpty ? rigNameOverride : nil
        wd.costCodeOverride = useCustomCostCode && !costCodeOverride.isEmpty ? costCodeOverride : nil
        wd.mileageToLocation = mileageToLocation
        wd.mileageFromLocation = mileageFromLocation
        wd.mileageInField = mileageInField
        wd.mileageCommute = mileageCommute
        wd.manuallyMarkedInvoiced = manuallyMarkedInvoiced
        wd.manuallyMarkedPaid = manuallyMarkedPaid
        wd.manualPaidDate = manuallyMarkedPaid ? manualPaidDate : nil

        if workDay == nil {
            modelContext.insert(wd)
        }
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    WorkDayListView()
}
