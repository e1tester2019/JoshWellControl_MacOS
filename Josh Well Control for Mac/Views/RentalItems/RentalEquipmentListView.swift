//
//  RentalEquipmentListView.swift
//  Josh Well Control for Mac
//
//  Equipment registry - tracks all rental equipment across wells.
//

import SwiftUI
import SwiftData

#if os(macOS)
struct RentalEquipmentListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RentalEquipment.name) private var allEquipment: [RentalEquipment]
    @Query(sort: \RentalCategory.sortOrder) private var categories: [RentalCategory]
    @Query(filter: #Predicate<Vendor> { $0.serviceTypeRaw == "Rentals" }, sort: \Vendor.companyName)
    private var vendors: [Vendor]

    @State private var searchText = ""
    @State private var selectedCategory: RentalCategory?
    @State private var selectedEquipment: RentalEquipment?
    @State private var showingAddSheet = false
    @State private var showingCategoryManager = false
    @State private var showingIssueSheet = false
    @State private var showingEditSheet = false
    @State private var equipmentToEdit: RentalEquipment?
    @State private var filterActiveOnly = false
    @State private var showingOnLocationReport = false

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

    /// Equipment currently in use or on location (for report)
    private var onLocationEquipment: [RentalEquipment] {
        allEquipment.filter { $0.locationStatus == .inUse || $0.locationStatus == .onLocation }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        HSplitView {
            // Equipment list
            VStack(alignment: .leading, spacing: 0) {
                toolbar
                Divider()
                equipmentList
            }
            .frame(minWidth: 400)

            // Detail view
            if let equipment = selectedEquipment {
                EquipmentDetailView(equipment: equipment, onLogIssue: {
                    showingIssueSheet = true
                })
                .id(equipment.id) // Force view recreation when selection changes
                .frame(minWidth: 350)
            } else {
                emptyDetailView
            }
        }
        .navigationTitle("Equipment Registry")
        .sheet(isPresented: $showingAddSheet) {
            EquipmentEditorSheet(equipment: nil, categories: categories, vendors: vendors) { equipment in
                modelContext.insert(equipment)
                try? modelContext.save()
                selectedEquipment = equipment
            }
        }
        .sheet(isPresented: $showingCategoryManager) {
            RentalCategoryManagerView()
        }
        .sheet(isPresented: $showingIssueSheet) {
            if let equipment = selectedEquipment {
                IssueLogSheet(equipment: equipment)
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            if let equipment = equipmentToEdit {
                EquipmentEditorSheet(equipment: equipment, categories: categories, vendors: vendors) { _ in
                    try? modelContext.save()
                }
            }
        }
        #if os(macOS)
        .sheet(isPresented: $showingOnLocationReport) {
            EquipmentOnLocationReportPreview(equipment: onLocationEquipment)
        }
        #endif
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Equipment Registry")
                    .font(.title3)
                    .bold()
                Spacer()
                Button("On Location Report", systemImage: "doc.text") {
                    showingOnLocationReport = true
                }
                .disabled(onLocationEquipment.isEmpty)
                Button("Categories", systemImage: "folder") {
                    showingCategoryManager = true
                }
                Button("Add Equipment", systemImage: "plus") {
                    showingAddSheet = true
                }
            }

            HStack {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)

                // Category filter
                Picker("Category", selection: $selectedCategory) {
                    Text("All Categories").tag(nil as RentalCategory?)
                    ForEach(categories) { category in
                        Label(category.name, systemImage: category.icon)
                            .tag(category as RentalCategory?)
                    }
                }
                .frame(width: 160)

                Toggle("Active Only", isOn: $filterActiveOnly)
                    .toggleStyle(.checkbox)
            }
        }
        .padding()
    }

    /// Equipment grouped by vendor, then category, then location status
    private struct VendorGroup: Identifiable {
        let id: UUID?
        let vendor: Vendor?
        var categoryGroups: [CategoryGroup]

        var totalCount: Int {
            categoryGroups.reduce(0) { $0 + $1.totalCount }
        }
    }

    private struct CategoryGroup: Identifiable {
        var id: String { "\(vendorId?.uuidString ?? "nil")-\(category?.id.uuidString ?? "nil")" }
        let vendorId: UUID?
        let category: RentalCategory?
        var inUse: [RentalEquipment]
        var onLocation: [RentalEquipment]
        var withVendor: [RentalEquipment]

        var totalCount: Int { inUse.count + onLocation.count + withVendor.count }
    }

    private var groupedByVendor: [VendorGroup] {
        // First group by vendor
        var vendorBuckets: [UUID?: [RentalEquipment]] = [:]
        for equipment in filteredEquipment {
            let vendorId = equipment.vendor?.id
            vendorBuckets[vendorId, default: []].append(equipment)
        }

        var result: [VendorGroup] = []

        // Get all vendors and sort
        let vendorIds = Set(vendorBuckets.keys)
        let sortedVendors: [Vendor] = vendorIds.compactMap { vendorId -> Vendor? in
            guard let vendorId = vendorId else { return nil }
            return vendors.first { $0.id == vendorId }
        }.sorted { $0.companyName < $1.companyName }

        // Process each vendor
        for vendor in sortedVendors {
            let equipment = vendorBuckets[vendor.id] ?? []
            let categoryGroups = buildCategoryGroups(from: equipment, vendorId: vendor.id)
            result.append(VendorGroup(id: vendor.id, vendor: vendor, categoryGroups: categoryGroups))
        }

        // Add equipment with no vendor at end
        if let noVendor = vendorBuckets[nil], !noVendor.isEmpty {
            let categoryGroups = buildCategoryGroups(from: noVendor, vendorId: nil)
            result.append(VendorGroup(id: nil, vendor: nil, categoryGroups: categoryGroups))
        }

        return result
    }

    private func buildCategoryGroups(from equipment: [RentalEquipment], vendorId: UUID?) -> [CategoryGroup] {
        var categoryBuckets: [UUID?: [RentalEquipment]] = [:]
        for eq in equipment {
            let catId = eq.category?.id
            categoryBuckets[catId, default: []].append(eq)
        }

        var groups: [CategoryGroup] = []

        // Sort categories
        let categoryIds = Set(categoryBuckets.keys)
        let sortedCats: [RentalCategory] = categoryIds.compactMap { catId -> RentalCategory? in
            guard let catId = catId else { return nil }
            return categories.first { $0.id == catId }
        }.sorted { $0.name < $1.name }

        for cat in sortedCats {
            let eqs = categoryBuckets[cat.id] ?? []
            let inUse = eqs.filter { $0.locationStatus == .inUse }.sorted { $0.name < $1.name }
            let onLoc = eqs.filter { $0.locationStatus == .onLocation }.sorted { $0.name < $1.name }
            let withVen = eqs.filter { $0.locationStatus == .withVendor }.sorted { $0.name < $1.name }
            groups.append(CategoryGroup(vendorId: vendorId, category: cat, inUse: inUse, onLocation: onLoc, withVendor: withVen))
        }

        // Uncategorized
        if let uncategorized = categoryBuckets[nil], !uncategorized.isEmpty {
            let inUse = uncategorized.filter { $0.locationStatus == .inUse }.sorted { $0.name < $1.name }
            let onLoc = uncategorized.filter { $0.locationStatus == .onLocation }.sorted { $0.name < $1.name }
            let withVen = uncategorized.filter { $0.locationStatus == .withVendor }.sorted { $0.name < $1.name }
            groups.append(CategoryGroup(vendorId: vendorId, category: nil, inUse: inUse, onLocation: onLoc, withVendor: withVen))
        }

        return groups
    }

    private var equipmentList: some View {
        List(selection: $selectedEquipment) {
            ForEach(groupedByVendor) { vendorGroup in
                Section {
                    ForEach(vendorGroup.categoryGroups) { catGroup in
                        DisclosureGroup {
                            // In Use
                            if !catGroup.inUse.isEmpty {
                                DisclosureGroup {
                                    ForEach(catGroup.inUse) { equipment in
                                        equipmentRow(for: equipment)
                                    }
                                } label: {
                                    Label("\(catGroup.inUse.count) In Use", systemImage: EquipmentLocation.inUse.icon)
                                        .foregroundStyle(EquipmentLocation.inUse.color)
                                        .font(.caption)
                                }
                            }

                            // On Location (standby)
                            if !catGroup.onLocation.isEmpty {
                                DisclosureGroup {
                                    ForEach(catGroup.onLocation) { equipment in
                                        equipmentRow(for: equipment)
                                    }
                                } label: {
                                    Label("\(catGroup.onLocation.count) On Location", systemImage: EquipmentLocation.onLocation.icon)
                                        .foregroundStyle(EquipmentLocation.onLocation.color)
                                        .font(.caption)
                                }
                            }

                            // With Vendor (Backhauled)
                            if !catGroup.withVendor.isEmpty {
                                DisclosureGroup {
                                    ForEach(catGroup.withVendor) { equipment in
                                        equipmentRow(for: equipment)
                                    }
                                } label: {
                                    Label("\(catGroup.withVendor.count) With Vendor", systemImage: EquipmentLocation.withVendor.icon)
                                        .foregroundStyle(EquipmentLocation.withVendor.color)
                                        .font(.caption)
                                }
                            }
                        } label: {
                            HStack {
                                if let category = catGroup.category {
                                    Label(category.name, systemImage: category.icon)
                                        .font(.subheadline)
                                } else {
                                    Label("Uncategorized", systemImage: "questionmark.folder")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                // Show status summary
                                HStack(spacing: 8) {
                                    if catGroup.inUse.count > 0 {
                                        HStack(spacing: 2) {
                                            Image(systemName: EquipmentLocation.inUse.icon)
                                                .foregroundStyle(EquipmentLocation.inUse.color)
                                            Text("\(catGroup.inUse.count)")
                                        }
                                    }
                                    if catGroup.onLocation.count > 0 {
                                        HStack(spacing: 2) {
                                            Image(systemName: EquipmentLocation.onLocation.icon)
                                                .foregroundStyle(EquipmentLocation.onLocation.color)
                                            Text("\(catGroup.onLocation.count)")
                                        }
                                    }
                                    if catGroup.withVendor.count > 0 {
                                        HStack(spacing: 2) {
                                            Image(systemName: EquipmentLocation.withVendor.icon)
                                                .foregroundStyle(EquipmentLocation.withVendor.color)
                                            Text("\(catGroup.withVendor.count)")
                                        }
                                    }
                                }
                                .font(.caption2)
                            }
                        }
                    }
                } header: {
                    HStack {
                        if let vendor = vendorGroup.vendor {
                            Label(vendor.companyName, systemImage: "building.2")
                        } else {
                            Label("No Vendor", systemImage: "building.2")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(vendorGroup.totalCount)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func equipmentRow(for equipment: RentalEquipment) -> some View {
        EquipmentRow(equipment: equipment)
            .tag(equipment)
            .contextMenu {
                Button("Edit", systemImage: "pencil") {
                    equipmentToEdit = equipment
                    showingEditSheet = true
                }
                Button("Log Issue", systemImage: "exclamationmark.triangle") {
                    selectedEquipment = equipment
                    showingIssueSheet = true
                }
                Divider()
                Button(equipment.isActive ? "Deactivate" : "Activate",
                       systemImage: equipment.isActive ? "xmark.circle" : "checkmark.circle") {
                    equipment.isActive.toggle()
                    equipment.touch()
                    try? modelContext.save()
                }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    deleteEquipment(equipment)
                }
                .disabled(equipment.wellsUsedCount > 0)
            }
    }

    private var emptyDetailView: some View {
        VStack {
            Image(systemName: "shippingbox")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Select equipment to view details")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func deleteEquipment(_ equipment: RentalEquipment) {
        if selectedEquipment?.id == equipment.id {
            selectedEquipment = nil
        }
        modelContext.delete(equipment)
        try? modelContext.save()
    }
}

// MARK: - Equipment Row

private struct EquipmentRow: View {
    let equipment: RentalEquipment

    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            Image(systemName: equipment.category?.icon ?? "shippingbox")
                .font(.title2)
                .foregroundStyle(equipment.isActive ? .blue : .secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(equipment.name)
                        .fontWeight(.medium)
                    if equipment.hasFailures {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    if equipment.isCurrentlyInUse {
                        Text("IN USE")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.2))
                            .foregroundStyle(.green)
                            .cornerRadius(4)
                    }
                }
                HStack(spacing: 8) {
                    if !equipment.serialNumber.isEmpty {
                        Text("SN: \(equipment.serialNumber)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let vendor = equipment.vendor {
                        Text(vendor.companyName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

private struct EquipmentDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var equipment: RentalEquipment
    let onLogIssue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text(equipment.name)
                            .font(.title2)
                            .bold()
                        if !equipment.serialNumber.isEmpty {
                            Text("SN: \(equipment.serialNumber)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let category = equipment.category {
                        Label(category.name, systemImage: category.icon)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                    }
                }

                Divider()

                // Stats
                HStack(spacing: 24) {
                    StatBox(title: "Total Days", value: "\(equipment.totalDaysUsed)")
                    StatBox(title: "Wells Used", value: "\(equipment.wellsUsedCount)")
                    StatBox(title: "Issues", value: "\(equipment.issues?.count ?? 0)")
                    if let well = equipment.currentWell {
                        StatBox(title: "Current Location", value: well.name)
                    }
                }

                // Vendor info
                if let vendor = equipment.vendor {
                    GroupBox("Vendor") {
                        HStack {
                            Text(vendor.companyName)
                            Spacer()
                            if let contact = vendor.primaryContact {
                                Text(contact.primaryPhone)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Notes
                GroupBox("Notes") {
                    TextEditor(text: $equipment.notes)
                        .frame(minHeight: 60)
                }

                // Issues
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Issue Log")
                                .font(.headline)
                            Spacer()
                            Button("Log Issue", systemImage: "plus") {
                                onLogIssue()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if equipment.sortedIssues.isEmpty {
                            Text("No issues logged")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } else {
                            ForEach(equipment.sortedIssues.prefix(5)) { issue in
                                IssueRow(issue: issue)
                            }
                            if equipment.sortedIssues.count > 5 {
                                Text("+ \(equipment.sortedIssues.count - 5) more")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Usage History
                GroupBox("Usage History") {
                    if equipment.sortedRentals.isEmpty {
                        Text("No usage history")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(equipment.sortedRentals.prefix(10)) { rental in
                            UsageHistoryRow(rental: rental)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

private struct StatBox: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .bold()
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 60)
    }
}

private struct IssueRow: View {
    let issue: RentalEquipmentIssue

    var body: some View {
        HStack {
            Image(systemName: issue.issueType.icon)
                .foregroundStyle(issue.issueType.color)
            VStack(alignment: .leading) {
                Text(issue.summary)
                    .font(.caption)
                Text(issue.dateString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if issue.isResolved {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
    }
}

private struct UsageHistoryRow: View {
    let rental: RentalItem

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(rental.well?.name ?? "Unknown Well")
                    .font(.caption)
                if let start = rental.startDate {
                    Text(start, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(rental.totalDays) days")
                .font(.caption)
                .monospacedDigit()
            Image(systemName: rental.status.icon)
                .foregroundStyle(rental.status.color)
                .font(.caption)
        }
    }
}

// MARK: - Equipment Editor Sheet

private struct EquipmentEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(equipment == nil ? "Add Equipment" : "Edit Equipment")
                .font(.headline)

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

                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Location Status") {
                    Picker("Status", selection: $locationStatus) {
                        ForEach(EquipmentLocation.allCases, id: \.self) { status in
                            Label(status.rawValue, systemImage: status.icon)
                                .tag(status)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Location", text: $locationName)
                        .textFieldStyle(.roundedBorder)

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

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
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
                .disabled(name.isEmpty || serialNumber.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400, height: 500)
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
}

// MARK: - Issue Log Sheet

private struct IssueLogSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var equipment: RentalEquipment

    @State private var issueType: RentalIssueType = .other
    @State private var severity: RentalIssueSeverity = .minor
    @State private var description = ""
    @State private var actionTaken = ""
    @State private var reportedBy = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Log Issue for \(equipment.displayName)")
                .font(.headline)

            Form {
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

                TextField("Description", text: $description, axis: .vertical)
                    .lineLimit(3...6)

                TextField("Action Taken", text: $actionTaken, axis: .vertical)
                    .lineLimit(2...4)

                TextField("Reported By", text: $reportedBy)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Log Issue") {
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
                .disabled(description.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 450)
    }
}
#endif // os(macOS)

#if DEBUG && os(macOS)
#Preview {
    RentalEquipmentListView()
        .modelContainer(for: [RentalEquipment.self, RentalCategory.self, Vendor.self], inMemory: true)
        .frame(width: 900, height: 600)
}
#endif
