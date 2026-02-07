//
//  ShiftEditorView.swift
//  Josh Well Control for Mac
//
//  Editor view for creating/editing shift entries and auto-managing WorkDays.
//

import SwiftUI
import SwiftData

struct ShiftEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let date: Date

    @Query(sort: \Client.companyName) private var clients: [Client]
    @Query(filter: #Predicate<Well> { !$0.isArchived }, sort: \Well.name) private var wells: [Well]
    @Query(sort: \Pad.name) private var pads: [Pad]

    @State private var shiftType: ShiftType = .off
    @State private var selectedClient: Client?
    @State private var selectedPad: Pad?
    @State private var selectedWell: Well?

    /// Wells filtered by selected pad
    private var filteredWells: [Well] {
        if let pad = selectedPad {
            return wells.filter { $0.pad?.id == pad.id }
        }
        return wells
    }
    @State private var notes: String = ""

    // Mileage fields
    @State private var mileageToLocation: Double = 0
    @State private var mileageFromLocation: Double = 0
    @State private var mileageInField: Double = 0
    @State private var mileageCommute: Double = 0

    // State for existing data
    @State private var existingShiftEntry: ShiftEntry?
    @State private var showingDeleteConfirmation = false
    @State private var hasLoadedData = false

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            #if os(macOS)
            macOSContent
            #else
            iOSContent
            #endif
        }
        #if os(macOS)
        .frame(width: 500, height: 600)
        #endif
    }

    // MARK: - macOS Content

    #if os(macOS)
    private var macOSContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Shift")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            // Form content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Date Display
                    formRow(label: "Date") {
                        Text(dateString)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Shift Type
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Shift Type")
                            .font(.headline)

                        Picker("", selection: $shiftType) {
                            ForEach(ShiftType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    // Client & Well Assignment (only for working shifts)
                    if shiftType != .off {
                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Assignment")
                                .font(.headline)

                            formRow(label: "Client") {
                                Picker("", selection: $selectedClient) {
                                    Text("None").tag(nil as Client?)
                                    ForEach(clients) { client in
                                        Text(client.companyName).tag(client as Client?)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 200)
                            }

                            formRow(label: "Pad") {
                                Picker("", selection: $selectedPad) {
                                    Text("All Pads").tag(nil as Pad?)
                                    ForEach(pads) { pad in
                                        Text(pad.name).tag(pad as Pad?)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 200)
                                .onChange(of: selectedPad) { _, newPad in
                                    // Clear well selection if it's not in the new pad
                                    if let well = selectedWell, let pad = newPad {
                                        if well.pad?.id != pad.id {
                                            selectedWell = nil
                                        }
                                    }
                                }
                            }

                            formRow(label: "Well") {
                                Picker("", selection: $selectedWell) {
                                    Text("None").tag(nil as Well?)
                                    ForEach(filteredWells) { well in
                                        Text(well.name).tag(well as Well?)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 200)
                            }

                            if filteredWells.isEmpty && selectedPad != nil {
                                Text("No wells on this pad")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if selectedClient == nil {
                                Text("Select a client to log this as billable work")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }

                        Divider()

                        // Mileage
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Mileage (km)")
                                .font(.headline)

                            mileageRow(label: "To Location", value: $mileageToLocation)
                            mileageRow(label: "From Location", value: $mileageFromLocation)
                            mileageRow(label: "In Field", value: $mileageInField)
                            mileageRow(label: "Commute", value: $mileageCommute)

                            if totalMileage > 0 {
                                formRow(label: "Total") {
                                    Text("\(Int(totalMileage)) km")
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }

                    Divider()

                    // Notes
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.headline)

                        TextEditor(text: $notes)
                            .frame(height: 80)
                            .font(.body)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                            .overlay(alignment: .topLeading) {
                                if notes.isEmpty {
                                    Text("Add notes about this shift...")
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 8)
                                        .allowsHitTesting(false)
                                }
                            }
                    }

                    // Work Day Preview (only when client assigned)
                    if shiftType != .off && selectedClient != nil {
                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "briefcase.fill")
                                    .foregroundColor(.purple)
                                Text("Work Day")
                                    .font(.headline)
                            }

                            Text("WorkDay will be \(existingShiftEntry?.workDay != nil ? "updated" : "created")")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            formRow(label: "Day Rate") {
                                Text(formattedCurrency(selectedClient?.dayRate ?? 0))
                            }

                            if totalMileage > 0, let client = selectedClient {
                                formRow(label: "Mileage Rate") {
                                    Text("\(formattedCurrency(client.mileageRate))/km")
                                }
                            }
                        }
                    }

                    // Delete button for existing entries
                    if existingShiftEntry != nil {
                        Divider()

                        Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Shift Entry")
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }

            Divider()

            // Footer buttons
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveShift()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .confirmationDialog(
            "Delete Shift Entry?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteShift()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if existingShiftEntry?.workDay?.isInvoiced == true {
                Text("This shift has an associated WorkDay that has been invoiced. Deleting will also remove the WorkDay.")
            } else {
                Text("This will delete the shift entry and any associated WorkDay.")
            }
        }
        .onAppear {
            if !hasLoadedData {
                loadExistingData()
                hasLoadedData = true
            }
        }
    }

    @ViewBuilder
    private func formRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .frame(width: 120, alignment: .trailing)
            content()
            Spacer()
        }
    }

    @ViewBuilder
    private func mileageRow(label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
                .frame(width: 120, alignment: .trailing)
            TextField("0", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            Spacer()
        }
    }
    #endif

    // MARK: - iOS Content

    #if os(iOS)
    private var iOSContent: some View {
        Form {
            // Date Display
            Section {
                HStack {
                    Text("Date")
                    Spacer()
                    Text(dateString)
                        .foregroundColor(.secondary)
                }
            }

            // Shift Type
            Section("Shift Type") {
                Picker("Shift", selection: $shiftType) {
                    ForEach(ShiftType.allCases, id: \.self) { type in
                        Label(type.displayName, systemImage: type.icon)
                            .tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Client & Well Assignment (only for working shifts)
            if shiftType != .off {
                Section("Assignment") {
                    Picker("Client", selection: $selectedClient) {
                        Text("None").tag(nil as Client?)
                        ForEach(clients) { client in
                            Text(client.companyName).tag(client as Client?)
                        }
                    }

                    Picker("Pad", selection: $selectedPad) {
                        Text("All Pads").tag(nil as Pad?)
                        ForEach(pads) { pad in
                            Text(pad.name).tag(pad as Pad?)
                        }
                    }
                    .onChange(of: selectedPad) { _, newPad in
                        if let well = selectedWell, let pad = newPad {
                            if well.pad?.id != pad.id {
                                selectedWell = nil
                            }
                        }
                    }

                    Picker("Well", selection: $selectedWell) {
                        Text("None").tag(nil as Well?)
                        ForEach(filteredWells) { well in
                            Text(well.name).tag(well as Well?)
                        }
                    }

                    if filteredWells.isEmpty && selectedPad != nil {
                        Text("No wells on this pad")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if selectedClient == nil {
                        Text("Select a client to log this as billable work")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                // Mileage
                Section("Mileage (km)") {
                    HStack {
                        Text("To Location")
                        Spacer()
                        TextField("0", value: $mileageToLocation, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .keyboardType(.decimalPad)
                    }

                    HStack {
                        Text("From Location")
                        Spacer()
                        TextField("0", value: $mileageFromLocation, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .keyboardType(.decimalPad)
                    }

                    HStack {
                        Text("In Field")
                        Spacer()
                        TextField("0", value: $mileageInField, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .keyboardType(.decimalPad)
                    }

                    HStack {
                        Text("Commute")
                        Spacer()
                        TextField("0", value: $mileageCommute, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .keyboardType(.decimalPad)
                    }

                    if totalMileage > 0 {
                        HStack {
                            Text("Total")
                                .fontWeight(.semibold)
                            Spacer()
                            Text("\(Int(totalMileage)) km")
                                .fontWeight(.semibold)
                        }
                    }
                }
            }

            // Notes
            Section("Notes") {
                TextField("Add notes about this shift...", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            // Work Day Preview (only when client assigned)
            if shiftType != .off && selectedClient != nil {
                Section("Work Day") {
                    HStack {
                        Image(systemName: "briefcase.fill")
                            .foregroundColor(.purple)
                        Text("WorkDay will be \(existingShiftEntry?.workDay != nil ? "updated" : "created")")
                    }

                    HStack {
                        Text("Day Rate")
                        Spacer()
                        Text(formattedCurrency(selectedClient?.dayRate ?? 0))
                    }

                    if totalMileage > 0, let client = selectedClient {
                        HStack {
                            Text("Mileage Rate")
                            Spacer()
                            Text("\(formattedCurrency(client.mileageRate))/km")
                        }
                    }
                }
            }

            // Delete button for existing entries
            if existingShiftEntry != nil {
                Section {
                    Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Shift Entry")
                        }
                    }
                }
            }
        }
        .navigationTitle("Edit Shift")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveShift()
                }
            }
        }
        .confirmationDialog(
            "Delete Shift Entry?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteShift()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if existingShiftEntry?.workDay?.isInvoiced == true {
                Text("This shift has an associated WorkDay that has been invoiced. Deleting will also remove the WorkDay.")
            } else {
                Text("This will delete the shift entry and any associated WorkDay.")
            }
        }
        .onAppear {
            if !hasLoadedData {
                loadExistingData()
                hasLoadedData = true
            }
        }
    }
    #endif

    // MARK: - Computed Properties

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: date)
    }

    private var totalMileage: Double {
        mileageToLocation + mileageFromLocation + mileageInField + mileageCommute
    }

    // MARK: - Data Loading

    private func loadExistingData() {
        let dayStart = calendar.startOfDay(for: date)

        // Fetch existing shift entry for this date
        let descriptor = FetchDescriptor<ShiftEntry>(
            predicate: #Predicate<ShiftEntry> { entry in
                entry.date >= dayStart
            }
        )

        if let entries = try? modelContext.fetch(descriptor),
           let entry = entries.first(where: { calendar.isDate($0.date, inSameDayAs: dayStart) }) {
            existingShiftEntry = entry
            shiftType = entry.shiftType
            selectedClient = entry.client
            selectedWell = entry.well
            selectedPad = entry.well?.pad  // Set pad from existing well
            notes = entry.notes

            // Load mileage from associated WorkDay if exists
            if let workDay = entry.workDay {
                mileageToLocation = workDay.mileageToLocation
                mileageFromLocation = workDay.mileageFromLocation
                mileageInField = workDay.mileageInField
                mileageCommute = workDay.mileageCommute
            }
        } else {
            // No existing entry, use expected shift type from rotation
            shiftType = ShiftRotationSettings.shared.expectedShiftType(for: date)
        }
    }

    // MARK: - Save

    private func saveShift() {
        let dayStart = calendar.startOfDay(for: date)

        // Get or create ShiftEntry
        let shiftEntry: ShiftEntry
        if let existing = existingShiftEntry {
            shiftEntry = existing
        } else {
            shiftEntry = ShiftEntry(date: dayStart, shiftType: shiftType)
            modelContext.insert(shiftEntry)
        }

        // Update shift entry
        shiftEntry.shiftType = shiftType
        shiftEntry.client = selectedClient
        shiftEntry.well = selectedWell
        shiftEntry.notes = notes
        shiftEntry.updatedAt = Date.now

        // Handle WorkDay creation/update/deletion
        if shiftType != .off && selectedClient != nil {
            // Need a WorkDay
            let workDay: WorkDay
            if let existing = shiftEntry.workDay {
                workDay = existing
            } else {
                workDay = WorkDay(startDate: dayStart, endDate: dayStart)
                modelContext.insert(workDay)
                shiftEntry.workDay = workDay
            }

            // Update WorkDay
            workDay.startDate = dayStart
            workDay.endDate = dayStart
            workDay.client = selectedClient
            workDay.well = selectedWell
            workDay.mileageToLocation = mileageToLocation
            workDay.mileageFromLocation = mileageFromLocation
            workDay.mileageInField = mileageInField
            workDay.mileageCommute = mileageCommute
            workDay.notes = notes

        } else if let existingWorkDay = shiftEntry.workDay {
            // Shift changed to off or no client - remove WorkDay if not invoiced
            if !existingWorkDay.isInvoiced {
                modelContext.delete(existingWorkDay)
                shiftEntry.workDay = nil
            }
        }

        do {
            try modelContext.save()

            // Reschedule notifications
            Task {
                await ShiftNotificationService.shared.scheduleNextReminder(context: modelContext)
            }

            dismiss()
        } catch {
            print("Failed to save shift: \(error)")
        }
    }

    // MARK: - Delete

    private func deleteShift() {
        guard let entry = existingShiftEntry else { return }

        // Delete associated WorkDay first (cascade should handle it, but be explicit)
        if let workDay = entry.workDay {
            modelContext.delete(workDay)
        }

        modelContext.delete(entry)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to delete shift: \(error)")
        }
    }

    // MARK: - Helpers

    private func formattedCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
}
