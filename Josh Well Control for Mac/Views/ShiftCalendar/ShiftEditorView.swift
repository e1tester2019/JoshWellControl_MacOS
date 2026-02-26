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
    @Query(sort: \ShiftEntry.date, order: .reverse) private var allShiftEntries: [ShiftEntry]

    @State private var shiftType: ShiftType = .off
    @State private var selectedClient: Client?
    @State private var selectedPad: Pad?
    @State private var selectedWell: Well?
    @State private var isPredicted = false

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
        .frame(width: 420, height: 520)
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

            // Quick Confirm banner (for new entries with auto-filled data)
            if existingShiftEntry == nil && shiftType != .off && selectedClient != nil {
                HStack(spacing: 12) {
                    Image(systemName: shiftType.icon)
                        .foregroundColor(.white)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(shiftType.displayName) Shift")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)

                        HStack(spacing: 4) {
                            if let client = selectedClient {
                                Text(client.companyName)
                            }
                            if let well = selectedWell {
                                Text("—")
                                Text(well.name)
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                    }

                    Spacer()

                    Button("Quick Save") {
                        saveShift()
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: shiftType == .day ? [.blue, .cyan] : [.purple, .indigo],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            }

            // Form content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Predicted label
                    if isPredicted && existingShiftEntry == nil {
                        HStack(spacing: 6) {
                            Image(systemName: "wand.and.stars")
                                .foregroundColor(.orange)
                            Text("Predicted from rotation — Save to confirm")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    // Date Display
                    formRow(label: "Date") {
                        Text(dateString)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Shift Type — three tappable cards
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Shift Type")
                            .font(.headline)

                        HStack(spacing: 8) {
                            ForEach(ShiftType.allCases, id: \.self) { type in
                                shiftTypeCard(type)
                            }
                        }
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

                        // Mileage — collapsed by default
                        DisclosureGroup("Mileage (km)") {
                            VStack(spacing: 8) {
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
                            .padding(.top, 4)
                        }
                        .font(.headline)
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

    private func shiftTypeCard(_ type: ShiftType) -> some View {
        let isActive = shiftType == type
        let color: Color = {
            switch type {
            case .day: return .blue
            case .night: return .purple
            case .off: return .gray
            }
        }()

        return Button(action: { shiftType = type }) {
            VStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.title3)
                Text(type.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isActive ? color.opacity(0.15) : Color(NSColor.controlBackgroundColor))
            .foregroundColor(isActive ? color : .secondary)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? color : Color.secondary.opacity(0.2), lineWidth: isActive ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
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

        // Check if there's an existing shift entry for this date
        if let entry = allShiftEntries.first(where: { calendar.isDate($0.date, inSameDayAs: dayStart) }) {
            existingShiftEntry = entry
            shiftType = entry.shiftType
            selectedClient = entry.client
            selectedWell = entry.well
            selectedPad = entry.well?.pad
            notes = entry.notes
            isPredicted = false

            // Load mileage from associated WorkDay if exists
            if let workDay = entry.workDay {
                mileageToLocation = workDay.mileageToLocation
                mileageFromLocation = workDay.mileageFromLocation
                mileageInField = workDay.mileageInField
                mileageCommute = workDay.mileageCommute
            }
        } else {
            // No existing entry — use rotation prediction and auto-fill from last entry
            shiftType = ShiftRotationSettings.shared.expectedShiftType(for: date)
            isPredicted = true

            // Auto-fill client/pad/well from most recent shift with a client
            if let lastEntry = allShiftEntries.first(where: { $0.client != nil }) {
                selectedClient = lastEntry.client
                selectedPad = lastEntry.well?.pad
                selectedWell = lastEntry.well
            }
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

        // Auto-sync WorkDay via service
        ShiftWorkDayService.ensureWorkDay(
            for: shiftEntry,
            client: selectedClient,
            well: selectedWell,
            mileageToLocation: mileageToLocation,
            mileageFromLocation: mileageFromLocation,
            mileageInField: mileageInField,
            mileageCommute: mileageCommute,
            notes: notes,
            context: modelContext
        )

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
