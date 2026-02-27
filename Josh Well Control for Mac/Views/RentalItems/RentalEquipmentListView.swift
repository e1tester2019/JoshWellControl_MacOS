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
    @State private var filterActiveOnly = false
    @State private var importText = ""
    @State private var selectedEquipmentIDs: Set<UUID> = []
    @State private var activeSheet: SheetType? = nil

    private enum SheetType: Identifiable {
        case addEquipment
        case categoryManager
        case issueLog(RentalEquipment)
        case editEquipment(RentalEquipment)
        case onLocationReport
        case importSheet
        case bulkEdit
        case sendToLocation

        var id: String {
            switch self {
            case .addEquipment: return "addEquipment"
            case .categoryManager: return "categoryManager"
            case .issueLog(let eq): return "issueLog-\(eq.id)"
            case .editEquipment(let eq): return "editEquipment-\(eq.id)"
            case .onLocationReport: return "onLocationReport"
            case .importSheet: return "importSheet"
            case .bulkEdit: return "bulkEdit"
            case .sendToLocation: return "sendToLocation"
            }
        }
    }

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

    /// Selected equipment for bulk operations
    private var selectedEquipmentObjects: [RentalEquipment] {
        allEquipment.filter { selectedEquipmentIDs.contains($0.id) }
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
                    activeSheet = .issueLog(equipment)
                })
                .id(equipment.id) // Force view recreation when selection changes
                .frame(minWidth: 350)
            } else {
                emptyDetailView
            }
        }
        .navigationTitle("Equipment Registry")
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addEquipment:
                EquipmentEditorSheet(equipment: nil, categories: categories, vendors: vendors) { equipment in
                    modelContext.insert(equipment)
                    try? modelContext.save()
                    selectedEquipment = equipment
                }
            case .categoryManager:
                RentalCategoryManagerView()
            case .issueLog(let equipment):
                IssueLogSheet(equipment: equipment)
            case .editEquipment(let equipment):
                EquipmentEditorSheet(equipment: equipment, categories: categories, vendors: vendors) { _ in
                    try? modelContext.save()
                }
            case .onLocationReport:
                #if os(macOS)
                EquipmentOnLocationReportPreview(equipment: onLocationEquipment)
                #else
                EmptyView()
                #endif
            case .importSheet:
                #if os(macOS)
                EquipmentImportSheet(
                    csvText: $importText,
                    categories: categories,
                    vendors: vendors,
                    existingEquipment: allEquipment
                ) {
                    activeSheet = nil
                    importText = ""
                }
                #else
                EmptyView()
                #endif
            case .bulkEdit:
                #if os(macOS)
                BulkEquipmentEditSheet(
                    equipment: selectedEquipmentObjects,
                    categories: categories,
                    vendors: vendors
                ) {
                    activeSheet = nil
                    selectedEquipmentIDs.removeAll()
                }
                #else
                EmptyView()
                #endif
            case .sendToLocation:
                #if os(macOS)
                SendToLocationSheet(
                    equipment: selectedEquipmentObjects
                ) {
                    activeSheet = nil
                    selectedEquipmentIDs.removeAll()
                }
                #else
                EmptyView()
                #endif
            }
        }
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Equipment Registry")
                    .font(.title3)
                    .bold()

                // Selection indicator
                if !selectedEquipmentIDs.isEmpty {
                    Text("\(selectedEquipmentIDs.count) selected")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(4)

                    Button("Clear") {
                        selectedEquipmentIDs.removeAll()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                // Bulk actions (when items selected)
                if !selectedEquipmentIDs.isEmpty {
                    Button("Bulk Edit", systemImage: "pencil") {
                        activeSheet = .bulkEdit
                    }
                    Button("Send to Location", systemImage: "arrow.right.circle") {
                        activeSheet = .sendToLocation
                    }

                    Divider()
                        .frame(height: 20)
                }

                // Import/Export Menu
                Menu {
                    Button("Import from File...", systemImage: "doc.badge.arrow.up") {
                        if let text = EquipmentImportService.shared.importFromFile() {
                            importText = text
                            activeSheet = .importSheet
                        }
                    }
                    Button("Paste from Clipboard", systemImage: "doc.on.clipboard") {
                        if let text = EquipmentImportService.shared.getClipboardText() {
                            importText = text
                            activeSheet = .importSheet
                        }
                    }
                    Divider()
                    Button("Download Template...", systemImage: "arrow.down.doc") {
                        EquipmentImportService.shared.saveTemplate()
                    }
                    Button("Export All Equipment...", systemImage: "arrow.up.doc") {
                        EquipmentImportService.shared.exportToFile(allEquipment)
                    }
                } label: {
                    Label("Import/Export", systemImage: "square.and.arrow.up.on.square")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button("On Location Report", systemImage: "doc.text") {
                    activeSheet = .onLocationReport
                }
                .disabled(onLocationEquipment.isEmpty)
                Button("Categories", systemImage: "folder") {
                    activeSheet = .categoryManager
                }
                Button("Add Equipment", systemImage: "plus") {
                    activeSheet = .addEquipment
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
                .controlSize(.small)

                Toggle("Active Only", isOn: $filterActiveOnly)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
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
        HStack(spacing: 8) {
            // Selection checkbox
            Button {
                if selectedEquipmentIDs.contains(equipment.id) {
                    selectedEquipmentIDs.remove(equipment.id)
                } else {
                    selectedEquipmentIDs.insert(equipment.id)
                }
            } label: {
                Image(systemName: selectedEquipmentIDs.contains(equipment.id) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selectedEquipmentIDs.contains(equipment.id) ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            EquipmentRow(equipment: equipment)
        }
        .tag(equipment)
        .contextMenu {
            Button("Edit", systemImage: "pencil") {
                activeSheet = .editEquipment(equipment)
            }
            Button("Log Issue", systemImage: "exclamationmark.triangle") {
                selectedEquipment = equipment
                activeSheet = .issueLog(equipment)
            }
            Divider()
            if !selectedEquipmentIDs.contains(equipment.id) {
                Button("Select", systemImage: "checkmark.square") {
                    selectedEquipmentIDs.insert(equipment.id)
                }
            } else {
                Button("Deselect", systemImage: "square") {
                    selectedEquipmentIDs.remove(equipment.id)
                }
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

struct EquipmentEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Well.name) private var wells: [Well]
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
    @State private var selectedWell: Well?

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

                    if locationStatus == .onLocation {
                        Picker("Location", selection: $selectedWell) {
                            Text("Select a well...").tag(nil as Well?)
                            ForEach(wells) { well in
                                Text(well.name).tag(well as Well?)
                            }
                        }
                    } else {
                        TextField("Location", text: $locationName)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Image(systemName: locationStatus.icon)
                            .foregroundStyle(locationStatus.color)
                        Text(locationStatus.rawValue)
                            .foregroundStyle(.secondary)
                        if locationStatus == .onLocation, let well = selectedWell {
                            Text("• \(well.name)")
                                .foregroundStyle(.tertiary)
                        } else if !locationName.isEmpty {
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
                    eq.currentLocationName = locationStatus == .onLocation ? (selectedWell?.name ?? "") : locationName
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
                // Try to match existing location name to a well
                if eq.locationStatus == .onLocation {
                    selectedWell = wells.first { $0.name == eq.currentLocationName }
                }
            }
        }
    }
}

// MARK: - Issue Log Sheet

struct IssueLogSheet: View {
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
// MARK: - Bulk Equipment Edit Sheet

struct BulkEquipmentEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let equipment: [RentalEquipment]
    let categories: [RentalCategory]
    let vendors: [Vendor]
    let onComplete: () -> Void

    @State private var assignVendor = false
    @State private var selectedVendor: Vendor?
    @State private var assignCategory = false
    @State private var selectedCategory: RentalCategory?
    @State private var setActiveStatus = false
    @State private var activeStatus = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Bulk Edit \(equipment.count) Items")
                    .font(.headline)
                Spacer()
                Button("Cancel") { onComplete() }
            }
            .padding()

            Divider()

            Form {
                Section("Assign Vendor") {
                    Toggle("Set vendor for all items", isOn: $assignVendor)

                    if assignVendor {
                        Picker("Vendor", selection: $selectedVendor) {
                            Text("None").tag(nil as Vendor?)
                            ForEach(vendors) { vendor in
                                Text(vendor.companyName).tag(vendor as Vendor?)
                            }
                        }
                    }
                }

                Section("Assign Category") {
                    Toggle("Set category for all items", isOn: $assignCategory)

                    if assignCategory {
                        Picker("Category", selection: $selectedCategory) {
                            Text("None").tag(nil as RentalCategory?)
                            ForEach(categories) { cat in
                                Label(cat.name, systemImage: cat.icon).tag(cat as RentalCategory?)
                            }
                        }
                    }
                }

                Section("Status") {
                    Toggle("Set active status for all items", isOn: $setActiveStatus)

                    if setActiveStatus {
                        Picker("Status", selection: $activeStatus) {
                            Text("Active").tag(true)
                            Text("Inactive").tag(false)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section("Preview") {
                    Text("\(equipment.count) items will be updated")
                        .foregroundStyle(.secondary)

                    ForEach(equipment.prefix(5)) { eq in
                        HStack {
                            Text(eq.displayName)
                                .font(.caption)
                            Spacer()
                            if assignVendor {
                                Text(selectedVendor?.companyName ?? "No vendor")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    if equipment.count > 5 {
                        Text("+ \(equipment.count - 5) more...")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Apply Changes") {
                    applyChanges()
                }
                .disabled(!assignVendor && !assignCategory && !setActiveStatus)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 450, height: 550)
    }

    private func applyChanges() {
        for eq in equipment {
            if assignVendor {
                eq.vendor = selectedVendor
            }
            if assignCategory {
                eq.category = selectedCategory
            }
            if setActiveStatus {
                eq.isActive = activeStatus
            }
            eq.touch()
        }
        try? modelContext.save()
        onComplete()
    }
}

// MARK: - Send to Location Sheet

struct SendToLocationSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Well.name) private var wells: [Well]
    @Query(sort: \Pad.name) private var pads: [Pad]

    let equipment: [RentalEquipment]
    let onComplete: () -> Void

    @State private var destinationType: DestinationType = .well
    @State private var selectedWell: Well?
    @State private var selectedPad: Pad?
    @State private var locationStatus: EquipmentLocation = .onLocation

    enum DestinationType: String, CaseIterable {
        case well = "Well"
        case pad = "Pad"
        case vendor = "Back to Vendor"
    }

    private var destinationName: String {
        switch destinationType {
        case .well: return selectedWell?.name ?? ""
        case .pad: return selectedPad?.name ?? ""
        case .vendor: return "Vendor"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Send \(equipment.count) Items to Location")
                    .font(.headline)
                Spacer()
                Button("Cancel") { onComplete() }
            }
            .padding()

            Divider()

            Form {
                Section("Destination") {
                    Picker("Send to", selection: $destinationType) {
                        ForEach(DestinationType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch destinationType {
                    case .well:
                        Picker("Well", selection: $selectedWell) {
                            Text("Select a well...").tag(nil as Well?)
                            ForEach(wells) { well in
                                Text(well.name).tag(well as Well?)
                            }
                        }
                    case .pad:
                        Picker("Pad", selection: $selectedPad) {
                            Text("Select a pad...").tag(nil as Pad?)
                            ForEach(pads) { pad in
                                Text(pad.name).tag(pad as Pad?)
                            }
                        }
                    case .vendor:
                        Text("Equipment will be marked as 'With Vendor'")
                            .foregroundStyle(.secondary)
                    }
                }

                if destinationType != .vendor {
                    Section("Status at Location") {
                        Picker("Status", selection: $locationStatus) {
                            Label("In Use", systemImage: EquipmentLocation.inUse.icon)
                                .tag(EquipmentLocation.inUse)
                            Label("On Location (Standby)", systemImage: EquipmentLocation.onLocation.icon)
                                .tag(EquipmentLocation.onLocation)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section("Equipment to Send") {
                    ForEach(equipment) { eq in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(eq.displayName)
                                    .font(.caption)
                                if let vendor = eq.vendor {
                                    Text(vendor.companyName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: eq.locationStatus.icon)
                                .foregroundStyle(eq.locationStatus.color)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Send to Location") {
                    sendToLocation()
                }
                .disabled(destinationType == .well && selectedWell == nil ||
                         destinationType == .pad && selectedPad == nil)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 550)
    }

    private func sendToLocation() {
        for eq in equipment {
            switch destinationType {
            case .well:
                if let well = selectedWell {
                    eq.locationStatus = locationStatus
                    eq.currentLocationName = well.name
                }
            case .pad:
                if let pad = selectedPad {
                    eq.locationStatus = locationStatus
                    eq.currentLocationName = pad.name
                }
            case .vendor:
                eq.backhaul()
            }
            eq.touch()
        }
        try? modelContext.save()
        onComplete()
    }
}

// MARK: - Equipment Import Sheet

struct EquipmentImportSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Binding var csvText: String
    let categories: [RentalCategory]
    let vendors: [Vendor]
    let existingEquipment: [RentalEquipment]
    let onComplete: () -> Void

    @State private var parsedItems: [EquipmentImportService.ParsedEquipment] = []
    @State private var skipDuplicates = true
    @State private var importResult: EquipmentImportService.ImportResult?
    @State private var showingResult = false

    private var validCount: Int {
        parsedItems.filter { $0.isValid }.count
    }

    private var errorCount: Int {
        parsedItems.filter { !$0.isValid }.count
    }

    private var warningCount: Int {
        parsedItems.filter { $0.isValid && $0.hasWarnings }.count
    }

    private var duplicateCount: Int {
        let existingSerials = Set(existingEquipment.map { $0.serialNumber.lowercased() })
        return parsedItems.filter { existingSerials.contains($0.serialNumber.lowercased()) }.count
    }

    private var unmatchedVendors: [String] {
        Array(Set(parsedItems.filter { $0.vendorNotFound }.map { $0.vendorName })).sorted()
    }

    private var unmatchedCategories: [String] {
        Array(Set(parsedItems.filter { $0.categoryNotFound }.map { $0.categoryName })).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Import Equipment")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    onComplete()
                }
            }
            .padding()

            Divider()

            HSplitView {
                // Left: CSV Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("CSV Data")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $csvText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 200)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )

                    HStack {
                        Button("Parse") {
                            parseCSV()
                        }
                        .disabled(csvText.isEmpty)

                        Button("Paste from Clipboard", systemImage: "doc.on.clipboard") {
                            if let text = EquipmentImportService.shared.getClipboardText() {
                                csvText = text
                                parseCSV()
                            }
                        }

                        Spacer()

                        Button("Clear") {
                            csvText = ""
                            parsedItems = []
                        }
                    }

                }
                .padding()
                .frame(minWidth: 350)

                // Right: Preview
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Preview")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !parsedItems.isEmpty {
                            Text("\(validCount) valid")
                                .foregroundStyle(.green)
                            if warningCount > 0 {
                                Text("• \(warningCount) warnings")
                                    .foregroundStyle(.yellow)
                            }
                            if errorCount > 0 {
                                Text("• \(errorCount) errors")
                                    .foregroundStyle(.red)
                            }
                            if duplicateCount > 0 {
                                Text("• \(duplicateCount) duplicates")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    // Unmatched vendors/categories warning
                    if !unmatchedVendors.isEmpty || !unmatchedCategories.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            if !unmatchedVendors.isEmpty {
                                HStack(alignment: .top) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.yellow)
                                    VStack(alignment: .leading) {
                                        Text("Vendors not found:")
                                            .fontWeight(.medium)
                                        Text(unmatchedVendors.joined(separator: ", "))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .font(.caption)
                            }
                            if !unmatchedCategories.isEmpty {
                                HStack(alignment: .top) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.yellow)
                                    VStack(alignment: .leading) {
                                        Text("Categories not found:")
                                            .fontWeight(.medium)
                                        Text(unmatchedCategories.joined(separator: ", "))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .font(.caption)
                            }
                            Text("Items will import without vendor/category. Use bulk edit after import to assign.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(8)
                        .background(Color.yellow.opacity(0.1))
                        .cornerRadius(8)
                    }

                    if parsedItems.isEmpty {
                        VStack {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("Paste CSV data and click Parse")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(parsedItems) { item in
                                ImportPreviewRow(item: item)
                            }
                        }
                        .listStyle(.inset)
                    }
                }
                .padding()
                .frame(minWidth: 400)
            }

            Divider()

            // Footer
            HStack {
                Toggle("Skip duplicates (same serial number)", isOn: $skipDuplicates)
                    .toggleStyle(.checkbox)

                Spacer()

                if let result = importResult {
                    HStack(spacing: 12) {
                        if result.imported > 0 {
                            Label("\(result.imported) imported", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        if result.skipped > 0 {
                            Label("\(result.skipped) skipped", systemImage: "minus.circle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                }

                Button("Import \(validCount) Items") {
                    performImport()
                }
                .disabled(validCount == 0)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 900, height: 600)
        .onAppear {
            // Parse on appear if we have text
            if !csvText.isEmpty {
                parseCSV()
            }
        }
        .alert("Import Complete", isPresented: $showingResult) {
            Button("Done") {
                onComplete()
            }
        } message: {
            if let result = importResult {
                Text("Imported \(result.imported) items. \(result.skipped) skipped.")
            }
        }
    }

    private func parseCSV() {
        parsedItems = EquipmentImportService.shared.parseCSV(csvText, categories: categories, vendors: vendors)
    }

    private func performImport() {
        let validItems = parsedItems.filter { $0.isValid }
        importResult = EquipmentImportService.shared.importEquipment(
            validItems,
            into: modelContext,
            categories: categories,
            vendors: vendors,
            existingEquipment: existingEquipment,
            skipDuplicates: skipDuplicates
        )
        showingResult = true
    }
}

private struct ImportPreviewRow: View {
    let item: EquipmentImportService.ParsedEquipment

    private var statusIcon: String {
        if !item.isValid { return "exclamationmark.triangle.fill" }
        if item.hasWarnings { return "exclamationmark.circle.fill" }
        return "checkmark.circle.fill"
    }

    private var statusColor: Color {
        if !item.isValid { return .red }
        if item.hasWarnings { return .yellow }
        return .green
    }

    var body: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.name)
                        .fontWeight(.medium)
                    if !item.serialNumber.isEmpty {
                        Text("SN: \(item.serialNumber)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    if !item.categoryName.isEmpty {
                        HStack(spacing: 2) {
                            Text(item.categoryName)
                            if item.categoryNotFound {
                                Image(systemName: "questionmark.circle")
                                    .foregroundStyle(.yellow)
                            }
                        }
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(item.categoryNotFound ? Color.yellow.opacity(0.1) : Color.blue.opacity(0.1))
                        .cornerRadius(4)
                    }
                    if !item.vendorName.isEmpty {
                        HStack(spacing: 2) {
                            Text(item.vendorName)
                            if item.vendorNotFound {
                                Image(systemName: "questionmark.circle")
                                    .foregroundStyle(.yellow)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(item.vendorNotFound ? .yellow : .secondary)
                    }
                }

                if let error = item.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            if !item.model.isEmpty {
                Text(item.model)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .opacity(item.isValid ? 1 : 0.7)
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
