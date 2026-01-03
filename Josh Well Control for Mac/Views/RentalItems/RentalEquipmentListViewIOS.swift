//
//  RentalEquipmentListViewIOS.swift
//  Josh Well Control for Mac
//
//  Equipment registry for iOS - tracks all rental equipment across wells.
//

import SwiftUI
import SwiftData

#if os(iOS)
struct RentalEquipmentListViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RentalEquipment.name) private var allEquipment: [RentalEquipment]
    @Query(sort: \RentalCategory.sortOrder) private var categories: [RentalCategory]
    @Query(filter: #Predicate<Vendor> { $0.serviceTypeRaw == "Rentals" }, sort: \Vendor.companyName)
    private var vendors: [Vendor]

    @State private var searchText = ""
    @State private var selectedCategory: RentalCategory?
    @State private var showingAddSheet = false
    @State private var showingCategoryManager = false
    @State private var filterActiveOnly = false
    @State private var selectedEquipment: RentalEquipment?

    private var filteredEquipment: [RentalEquipment] {
        var result = allEquipment

        if filterActiveOnly {
            result = result.filter { $0.isActive }
        }

        if let category = selectedCategory {
            result = result.filter { $0.category?.id == category.id }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.serialNumber.localizedCaseInsensitiveContains(searchText) ||
                ($0.vendor?.companyName ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    /// Equipment grouped by vendor, then category
    private var groupedEquipment: [(vendor: Vendor?, equipment: [RentalEquipment])] {
        var vendorBuckets: [UUID?: [RentalEquipment]] = [:]
        for equipment in filteredEquipment {
            let vendorId = equipment.vendor?.id
            vendorBuckets[vendorId, default: []].append(equipment)
        }

        var result: [(Vendor?, [RentalEquipment])] = []

        // Get all vendors and sort
        let vendorIds = Set(vendorBuckets.keys)
        let sortedVendors: [Vendor] = vendorIds.compactMap { vendorId -> Vendor? in
            guard let vendorId = vendorId else { return nil }
            return vendors.first { $0.id == vendorId }
        }.sorted { $0.companyName < $1.companyName }

        for vendor in sortedVendors {
            let equipment = vendorBuckets[vendor.id] ?? []
            result.append((vendor, equipment.sorted { $0.name < $1.name }))
        }

        // Add equipment with no vendor at end
        if let noVendor = vendorBuckets[nil], !noVendor.isEmpty {
            result.append((nil, noVendor.sorted { $0.name < $1.name }))
        }

        return result
    }

    var body: some View {
        List {
            // Filter section
            Section {
                Picker("Category", selection: $selectedCategory) {
                    Text("All Categories").tag(nil as RentalCategory?)
                    ForEach(categories) { category in
                        Label(category.name, systemImage: category.icon)
                            .tag(category as RentalCategory?)
                    }
                }

                Toggle("Active Only", isOn: $filterActiveOnly)
            }

            // Equipment list grouped by vendor
            ForEach(groupedEquipment, id: \.vendor?.id) { group in
                Section {
                    ForEach(group.equipment) { equipment in
                        NavigationLink {
                            EquipmentDetailViewIOS(equipment: equipment)
                        } label: {
                            EquipmentRowIOS(equipment: equipment)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteEquipment(equipment)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .disabled(equipment.wellsUsedCount > 0)

                            Button {
                                equipment.isActive.toggle()
                                equipment.touch()
                                try? modelContext.save()
                            } label: {
                                Label(equipment.isActive ? "Deactivate" : "Activate",
                                      systemImage: equipment.isActive ? "xmark.circle" : "checkmark.circle")
                            }
                            .tint(equipment.isActive ? .orange : .green)
                        }
                    }
                } header: {
                    HStack {
                        if let vendor = group.vendor {
                            Label(vendor.companyName, systemImage: "building.2")
                        } else {
                            Label("No Vendor", systemImage: "building.2")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(group.equipment.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search equipment...")
        .navigationTitle("Equipment Registry")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add Equipment", systemImage: "plus") {
                        showingAddSheet = true
                    }
                    Button("Manage Categories", systemImage: "folder") {
                        showingCategoryManager = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            NavigationStack {
                EquipmentEditorViewIOS(equipment: nil, categories: categories, vendors: vendors) { equipment in
                    modelContext.insert(equipment)
                    try? modelContext.save()
                }
            }
        }
        .sheet(isPresented: $showingCategoryManager) {
            NavigationStack {
                RentalCategoryManagerView()
            }
        }
        .overlay {
            if filteredEquipment.isEmpty {
                ContentUnavailableView {
                    Label("No Equipment", systemImage: "shippingbox")
                } description: {
                    if allEquipment.isEmpty {
                        Text("Add equipment to start tracking your rentals.")
                    } else {
                        Text("No equipment matches your filters.")
                    }
                } actions: {
                    if allEquipment.isEmpty {
                        Button("Add Equipment") {
                            showingAddSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private func deleteEquipment(_ equipment: RentalEquipment) {
        modelContext.delete(equipment)
        try? modelContext.save()
    }
}

// MARK: - Equipment Row

private struct EquipmentRowIOS: View {
    let equipment: RentalEquipment

    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            Image(systemName: equipment.category?.icon ?? "shippingbox")
                .font(.title2)
                .foregroundStyle(equipment.isActive ? .blue : .secondary)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(equipment.name)
                        .fontWeight(.medium)
                    if equipment.hasFailures {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                HStack(spacing: 8) {
                    if !equipment.serialNumber.isEmpty {
                        Text("SN: \(equipment.serialNumber)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Location status
                    HStack(spacing: 2) {
                        Image(systemName: equipment.locationStatus.icon)
                            .foregroundStyle(equipment.locationStatus.color)
                        Text(equipment.locationStatus.rawValue)
                    }
                    .font(.caption2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(equipment.totalDaysUsed) days")
                    .font(.caption)
                    .monospacedDigit()
                Text("\(equipment.wellsUsedCount) wells")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .opacity(equipment.isActive ? 1 : 0.6)
    }
}

// MARK: - Equipment Detail View

private struct EquipmentDetailViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var equipment: RentalEquipment
    @Query(sort: \RentalCategory.sortOrder) private var categories: [RentalCategory]
    @Query(filter: #Predicate<Vendor> { $0.serviceTypeRaw == "Rentals" }, sort: \Vendor.companyName)
    private var vendors: [Vendor]

    @State private var showingIssueSheet = false
    @State private var showingEditSheet = false

    var body: some View {
        List {
            // Header section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if let category = equipment.category {
                            Label(category.name, systemImage: category.icon)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: equipment.locationStatus.icon)
                                .foregroundStyle(equipment.locationStatus.color)
                            Text(equipment.locationStatus.rawValue)
                                .font(.caption)
                        }
                    }

                    if !equipment.serialNumber.isEmpty {
                        Text("SN: \(equipment.serialNumber)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if !equipment.model.isEmpty {
                        Text("Model: \(equipment.model)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Stats section
            Section("Statistics") {
                LabeledContent("Total Days Used", value: "\(equipment.totalDaysUsed)")
                LabeledContent("Wells Used", value: "\(equipment.wellsUsedCount)")
                LabeledContent("Open Issues", value: "\(equipment.issues?.filter { !$0.isResolved }.count ?? 0)")

                if let well = equipment.currentWell {
                    LabeledContent("Current Location", value: well.name)
                }
            }

            // Vendor section
            if let vendor = equipment.vendor {
                Section("Vendor") {
                    LabeledContent("Company", value: vendor.companyName)
                    if let contact = vendor.primaryContact {
                        if !contact.primaryPhone.isEmpty {
                            LabeledContent("Phone", value: contact.primaryPhone)
                        }
                    }
                }
            }

            // Notes section
            Section("Notes") {
                TextEditor(text: $equipment.notes)
                    .frame(minHeight: 80)
            }

            // Issues section
            Section {
                if equipment.sortedIssues.isEmpty {
                    Text("No issues logged")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(equipment.sortedIssues) { issue in
                        IssueRowIOS(issue: issue)
                    }
                }
            } header: {
                HStack {
                    Text("Issues")
                    Spacer()
                    Button("Log Issue", systemImage: "plus.circle") {
                        showingIssueSheet = true
                    }
                    .font(.caption)
                }
            }

            // Usage History section
            Section("Usage History") {
                if equipment.sortedRentals.isEmpty {
                    Text("No usage history")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(equipment.sortedRentals.prefix(10)) { rental in
                        UsageHistoryRowIOS(rental: rental)
                    }
                    if equipment.sortedRentals.count > 10 {
                        Text("+ \(equipment.sortedRentals.count - 10) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(equipment.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", systemImage: "pencil") {
                    showingEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showingIssueSheet) {
            NavigationStack {
                IssueLogSheetIOS(equipment: equipment)
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            NavigationStack {
                EquipmentEditorViewIOS(equipment: equipment, categories: categories, vendors: vendors) { _ in
                    try? modelContext.save()
                }
            }
        }
    }
}

private struct IssueRowIOS: View {
    let issue: RentalEquipmentIssue

    var body: some View {
        HStack {
            Image(systemName: issue.issueType.icon)
                .foregroundStyle(issue.issueType.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.summary)
                    .font(.subheadline)
                Text(issue.dateString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if issue.isResolved {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }
}

private struct UsageHistoryRowIOS: View {
    let rental: RentalItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(rental.well?.name ?? "Unknown Well")
                    .font(.subheadline)
                if let start = rental.startDate {
                    Text(start, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(rental.totalDays) days")
                .font(.caption)
                .monospacedDigit()
            Image(systemName: rental.status.icon)
                .foregroundStyle(rental.status.color)
        }
    }
}

// MARK: - Equipment Editor

private struct EquipmentEditorViewIOS: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let equipment: RentalEquipment?
    let categories: [RentalCategory]
    let vendors: [Vendor]
    let onSave: (RentalEquipment) -> Void

    @State private var name = ""
    @State private var serialNumber = ""
    @State private var model = ""
    @State private var description = ""
    @State private var selectedCategory: RentalCategory?
    @State private var selectedVendor: Vendor?
    @State private var locationStatus: EquipmentLocation = .withVendor
    @State private var locationName = ""

    private var isEditing: Bool { equipment != nil }

    var body: some View {
        Form {
            Section("Equipment Info") {
                TextField("Name", text: $name)
                TextField("Serial Number", text: $serialNumber)
                TextField("Model", text: $model)

                Picker("Category", selection: $selectedCategory) {
                    Text("None").tag(nil as RentalCategory?)
                    ForEach(categories) { cat in
                        Label(cat.name, systemImage: cat.icon).tag(cat as RentalCategory?)
                    }
                }

                Picker("Vendor", selection: $selectedVendor) {
                    Text("None").tag(nil as Vendor?)
                    ForEach(vendors) { vendor in
                        Text(vendor.companyName).tag(vendor as Vendor?)
                    }
                }
            }

            Section("Description") {
                TextEditor(text: $description)
                    .frame(minHeight: 80)
            }

            Section("Location Status") {
                Picker("Status", selection: $locationStatus) {
                    ForEach(EquipmentLocation.allCases, id: \.self) { status in
                        Label(status.rawValue, systemImage: status.icon)
                            .tag(status)
                    }
                }

                TextField("Location Name", text: $locationName)

                HStack {
                    Image(systemName: locationStatus.icon)
                        .foregroundStyle(locationStatus.color)
                    Text(locationStatus.rawValue)
                        .foregroundStyle(.secondary)
                    if !locationName.isEmpty {
                        Text("• \(locationName)")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)
            }
        }
        .navigationTitle(isEditing ? "Edit Equipment" : "Add Equipment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveEquipment()
                }
                .disabled(name.isEmpty || serialNumber.isEmpty)
            }
        }
        .onAppear {
            if let eq = equipment {
                name = eq.name
                serialNumber = eq.serialNumber
                model = eq.model
                description = eq.description_
                selectedCategory = eq.category
                selectedVendor = eq.vendor
                locationStatus = eq.locationStatus
                locationName = eq.currentLocationName
            }
        }
    }

    private func saveEquipment() {
        let eq = equipment ?? RentalEquipment()
        eq.name = name
        eq.serialNumber = serialNumber
        eq.model = model
        eq.description_ = description
        eq.category = selectedCategory
        eq.vendor = selectedVendor
        eq.locationStatus = locationStatus
        eq.currentLocationName = locationName
        eq.touch()
        onSave(eq)
        dismiss()
    }
}

// MARK: - Issue Log Sheet

private struct IssueLogSheetIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var equipment: RentalEquipment

    @State private var issueType: RentalIssueType = .other
    @State private var severity: RentalIssueSeverity = .minor
    @State private var description = ""
    @State private var actionTaken = ""
    @State private var reportedBy = ""

    var body: some View {
        Form {
            Section("Issue Details") {
                Picker("Issue Type", selection: $issueType) {
                    ForEach(RentalIssueType.allCases, id: \.self) { type in
                        Label(type.rawValue, systemImage: type.icon).tag(type)
                    }
                }

                Picker("Severity", selection: $severity) {
                    ForEach(RentalIssueSeverity.allCases, id: \.self) { sev in
                        Text(sev.rawValue).tag(sev)
                    }
                }
            }

            Section("Description") {
                TextEditor(text: $description)
                    .frame(minHeight: 80)
            }

            Section("Action Taken") {
                TextEditor(text: $actionTaken)
                    .frame(minHeight: 60)
            }

            Section {
                TextField("Reported By", text: $reportedBy)
            }
        }
        .navigationTitle("Log Issue")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Log Issue") {
                    logIssue()
                }
                .disabled(description.isEmpty)
            }
        }
    }

    private func logIssue() {
        let issue = RentalEquipmentIssue(
            issueType: issueType,
            severity: severity,
            description: description,
            reportedBy: reportedBy
        )
        issue.actionTaken = actionTaken
        issue.wellName = equipment.currentWell?.name ?? ""

        if equipment.issues == nil {
            equipment.issues = []
        }
        equipment.issues?.append(issue)
        modelContext.insert(issue)
        try? modelContext.save()
        dismiss()
    }
}
#endif // os(iOS)

#if os(iOS)
#Preview {
    NavigationStack {
        RentalEquipmentListViewIOS()
    }
    .modelContainer(for: [RentalEquipment.self, RentalCategory.self, Vendor.self], inMemory: true)
}
#endif
