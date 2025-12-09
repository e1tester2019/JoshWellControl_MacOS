//
//  MileageLogView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-08.
//

import SwiftUI
import SwiftData

struct MileageLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MileageLog.date, order: .reverse) private var mileageLogs: [MileageLog]

    @State private var showingAddSheet = false
    @State private var selectedLog: MileageLog?

    // Filters
    @State private var filterYear: Int?
    @State private var filterStartDate: Date?
    @State private var filterEndDate: Date?
    @State private var showFilters = false

    private var availableYears: [Int] {
        let years = Set(mileageLogs.map { Calendar.current.component(.year, from: $0.date) })
        return years.sorted().reversed()
    }

    private var filteredLogs: [MileageLog] {
        mileageLogs.filter { log in
            // Year filter
            if let year = filterYear {
                let logYear = Calendar.current.component(.year, from: log.date)
                if logYear != year { return false }
            }
            // Date range filter
            if let start = filterStartDate, log.date < start {
                return false
            }
            if let end = filterEndDate, log.date > end {
                return false
            }
            return true
        }
    }

    private var hasActiveFilters: Bool {
        filterYear != nil || filterStartDate != nil || filterEndDate != nil
    }

    private var totalKilometers: Double {
        filteredLogs.reduce(0) { $0 + $1.effectiveDistance }
    }

    private var yearToDateKm: Double {
        let currentYear = Calendar.current.component(.year, from: Date.now)
        return mileageLogs
            .filter { Calendar.current.component(.year, from: $0.date) == currentYear }
            .reduce(0) { $0 + $1.effectiveDistance }
    }

    private var estimatedDeduction: Double {
        MileageSummary.calculateDeduction(totalKm: totalKilometers)
    }

    private var groupedLogs: [String: [MileageLog]] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return Dictionary(grouping: filteredLogs) { formatter.string(from: $0.date) }
    }

    var body: some View {
        NavigationStack {
            List {
                // Summary section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Total Distance")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(Int(totalKilometers)) km")
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }

                            Spacer()

                            VStack(alignment: .trailing) {
                                Text("Est. Deduction")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(estimatedDeduction, format: .currency(code: "CAD"))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.green)
                            }
                        }

                        Divider()

                        HStack {
                            Text("CRA Rates:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("$\(MileageLog.firstTierRate, specifier: "%.2f")/km (first 5,000 km)")
                                .font(.caption)
                            Text("$\(MileageLog.secondTierRate, specifier: "%.2f")/km (after)")
                                .font(.caption)
                        }

                        if filterYear == nil {
                            Text("Year to date: \(Int(yearToDateKm)) km")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Filter section
                Section {
                    DisclosureGroup(isExpanded: $showFilters) {
                        Picker("Year", selection: $filterYear) {
                            Text("All Years").tag(nil as Int?)
                            ForEach(availableYears, id: \.self) { year in
                                Text(String(year)).tag(year as Int?)
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
                                filterYear = nil
                                filterStartDate = nil
                                filterEndDate = nil
                            }
                        }
                    } label: {
                        HStack {
                            Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                            if hasActiveFilters {
                                Spacer()
                                Text("\(filteredLogs.count) trips")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if mileageLogs.isEmpty {
                    ContentUnavailableView {
                        Label("No Mileage Logged", systemImage: "car.fill")
                    } description: {
                        Text("Track your business travel for CRA deductions")
                    } actions: {
                        Button("Log Trip") {
                            showingAddSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if filteredLogs.isEmpty {
                    ContentUnavailableView {
                        Label("No Matches", systemImage: "magnifyingglass")
                    } description: {
                        Text("No trips match your filters")
                    } actions: {
                        Button("Clear Filters") {
                            filterYear = nil
                            filterStartDate = nil
                            filterEndDate = nil
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    // Group by month
                    ForEach(groupedLogs.keys.sorted().reversed(), id: \.self) { monthKey in
                        Section {
                            ForEach(groupedLogs[monthKey] ?? []) { log in
                                MileageLogRow(log: log)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedLog = log
                                    }
                            }
                            .onDelete { indexSet in
                                deleteLogs(at: indexSet, in: monthKey)
                            }
                        } header: {
                            HStack {
                                Text(monthKey)
                                Spacer()
                                let monthKm = (groupedLogs[monthKey] ?? []).reduce(0) { $0 + $1.effectiveDistance }
                                Text("\(Int(monthKm)) km")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Mileage Log")
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
                MileageLogEditorView(log: nil)
            }
            .sheet(item: $selectedLog) { log in
                MileageLogEditorView(log: log)
            }
        }
    }

    private func deleteLogs(at offsets: IndexSet, in monthKey: String) {
        guard let logsInMonth = groupedLogs[monthKey] else { return }
        for index in offsets {
            let log = logsInMonth[index]
            modelContext.delete(log)
        }
        try? modelContext.save()
    }
}

// MARK: - Mileage Log Row

struct MileageLogRow: View {
    let log: MileageLog

    var body: some View {
        HStack {
            Image(systemName: "car.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(log.purpose.isEmpty ? "Trip" : log.purpose)
                    .fontWeight(.medium)

                if !log.locationString.isEmpty {
                    Text(log.locationString)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Text(log.displayDate)
                    if log.isRoundTrip {
                        Text("Round trip")
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int(log.effectiveDistance)) km")
                    .fontWeight(.semibold)

                let deduction = MileageSummary.calculateDeduction(totalKm: log.effectiveDistance)
                Text(deduction, format: .currency(code: "CAD"))
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Mileage Log Editor

struct MileageLogEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Client.companyName) private var clients: [Client]
    @Query(sort: \Well.name) private var wells: [Well]

    let log: MileageLog?

    @State private var date = Date.now
    @State private var startLocation = ""
    @State private var endLocation = ""
    @State private var distance: Double = 0
    @State private var purpose = ""
    @State private var isRoundTrip = false
    @State private var selectedClient: Client?
    @State private var selectedWell: Well?
    @State private var notes = ""

    private var effectiveDistance: Double {
        isRoundTrip ? distance * 2 : distance
    }

    private var estimatedDeduction: Double {
        MileageSummary.calculateDeduction(totalKm: effectiveDistance)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Trip Details") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "en_GB"))

                    TextField("Purpose (e.g., Client meeting, Site visit)", text: $purpose)

                    TextField("Start Location", text: $startLocation)
                    TextField("End Location", text: $endLocation)
                }

                Section("Distance") {
                    HStack {
                        Text("One-way Distance")
                        Spacer()
                        TextField("km", value: $distance, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                        Text("km")
                    }

                    Toggle("Round trip", isOn: $isRoundTrip)

                    HStack {
                        Text("Total Distance")
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(Int(effectiveDistance)) km")
                            .fontWeight(.semibold)
                    }

                    HStack {
                        Text("Est. Deduction")
                        Spacer()
                        Text(estimatedDeduction, format: .currency(code: "CAD"))
                            .foregroundStyle(.green)
                            .fontWeight(.medium)
                    }
                }

                Section("Link to Job (Optional)") {
                    Picker("Client", selection: $selectedClient) {
                        Text("None").tag(nil as Client?)
                        ForEach(clients) { client in
                            Text(client.companyName).tag(client as Client?)
                        }
                    }

                    Picker("Well", selection: $selectedWell) {
                        Text("None").tag(nil as Well?)
                        ForEach(wells) { well in
                            Text(well.name).tag(well as Well?)
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(log == nil ? "Log Trip" : "Edit Trip")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(distance <= 0)
                }
            }
            .onAppear { loadLog() }
        }
        .frame(minWidth: 450, minHeight: 500)
    }

    private func loadLog() {
        guard let log = log else { return }
        date = log.date
        startLocation = log.startLocation
        endLocation = log.endLocation
        distance = log.distance
        purpose = log.purpose
        isRoundTrip = log.isRoundTrip
        selectedClient = log.client
        selectedWell = log.well
        notes = log.notes
    }

    private func save() {
        let entry = log ?? MileageLog()
        entry.date = date
        entry.startLocation = startLocation
        entry.endLocation = endLocation
        entry.distance = distance
        entry.purpose = purpose
        entry.isRoundTrip = isRoundTrip
        entry.client = selectedClient
        entry.well = selectedWell
        entry.notes = notes

        if log == nil {
            modelContext.insert(entry)
        }
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    MileageLogView()
}
