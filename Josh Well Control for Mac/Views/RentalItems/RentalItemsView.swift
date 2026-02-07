import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct RentalItemsView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var well: Well

    @Query(sort: \RentalCategory.sortOrder) private var categories: [RentalCategory]
    @Query(sort: \RentalEquipment.name) private var allEquipment: [RentalEquipment]
    @Query private var allWells: [Well]

    @State private var selection: RentalItem? = nil
    @State private var editingRental: RentalItem? = nil
    @State private var selectedCategory: RentalCategory? = nil
    @State private var showOnlyActive = false
    @State private var showTransferSheet = false
    @State private var showEquipmentPicker = false
    @State private var showAddFromRegistry = false
    @State private var showOnLocationReport = false
    @State private var showBulkTransferSheet = false
    @State private var viewMode: RentalViewMode = .list

    enum RentalViewMode: String, CaseIterable {
        case list = "List"
        case cards = "Cards"

        var icon: String {
            switch self {
            case .list: return "list.bullet"
            case .cards: return "rectangle.grid.1x2"
            }
        }
    }

    init(well: Well) { self._well = Bindable(wrappedValue: well) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Rentals for \(well.name)").font(.title3).bold()
                Spacer()

                // View mode picker
                Picker("View", selection: $viewMode) {
                    ForEach(RentalViewMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

                // Category filter
                Picker("Category", selection: $selectedCategory) {
                    Text("All Categories").tag(nil as RentalCategory?)
                    ForEach(categories) { cat in
                        Label(cat.name, systemImage: cat.icon).tag(cat as RentalCategory?)
                    }
                }
                .frame(width: 160)

                Toggle("Active Only", isOn: $showOnlyActive)
                    #if os(macOS)
                    .toggleStyle(.checkbox)
                    #endif

                Menu {
                    Button("New Rental", systemImage: "plus") { addRental() }
                    Button("Add from Registry", systemImage: "shippingbox") { showAddFromRegistry = true }
                    Divider()
                    Button("Transfer Selected", systemImage: "arrow.right.circle") { showTransferSheet = true }
                        .disabled(selection == nil)
                    Button("Bulk Transfer Active/Standby", systemImage: "arrow.right.circle.fill") { showBulkTransferSheet = true }
                        .disabled(activeAndStandbyRentals.isEmpty)
                    Divider()
                    Button("On Location Report", systemImage: "doc.text") { showOnLocationReport = true }
                        .disabled(onLocationRentals.isEmpty)
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
            }

            // List or Card view
            if viewMode == .list {
                rentalListView
            } else {
                rentalCardView
            }

            // Footer
            HStack {
                Button("Edit Details", systemImage: "square.and.pencil") {
                    if let s = selection { openEditor(s) }
                }
                .disabled(selection == nil)

                Button("Link Equipment", systemImage: "link") {
                    showEquipmentPicker = true
                }
                .disabled(selection == nil)

                Spacer()

                // Summary
                let totalDays = filteredRentals.reduce(0) { $0 + $1.totalDays }
                let totalCost = filteredRentals.reduce(0) { $0 + $1.totalCost }
                Text("\(filteredRentals.count) items • \(totalDays) days • $\(String(format: "%.2f", totalCost))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .navigationTitle("Rentals")
        .sheet(item: $editingRental) { rental in
            RentalDetailEditor(rental: rental, allEquipment: allEquipment)
                .id(rental.id) // Force view recreation when editing different rental
                .environment(\.locale, Locale(identifier: "en_GB"))
                #if os(macOS)
                .frame(minWidth: 720, minHeight: 600)
                #endif
        }
        .sheet(isPresented: $showTransferSheet) {
            if let rental = selection {
                TransferRentalSheet(rental: rental, currentWell: well, allWells: allWells.filter { $0.id != well.id })
            }
        }
        .sheet(isPresented: $showEquipmentPicker) {
            EquipmentPickerSheet(rental: selection, allEquipment: allEquipment.filter { $0.isActive })
        }
        .sheet(isPresented: $showAddFromRegistry) {
            AddFromRegistrySheet(well: well, allEquipment: allEquipment.filter { $0.isActive })
        }
        #if os(macOS)
        .sheet(isPresented: $showOnLocationReport) {
            RentalsOnLocationReportPreview(well: well, rentals: onLocationRentals)
        }
        #endif
        .sheet(isPresented: $showBulkTransferSheet) {
            BulkTransferRentalSheet(
                rentals: activeAndStandbyRentals,
                currentWell: well,
                allWells: allWells.filter { $0.id != well.id }
            )
        }
    }

    private var filteredRentals: [RentalItem] {
        var rentals = well.rentals ?? []

        // Category filter
        if let category = selectedCategory {
            rentals = rentals.filter { $0.category?.id == category.id }
        }

        // Active filter
        if showOnlyActive {
            rentals = rentals.filter { $0.used && !$0.invoiced }
        }

        // Sort by date, then name
        return rentals.sorted { a, b in
            let asd = a.startDate ?? .distantPast
            let bsd = b.startDate ?? .distantPast
            if asd != bsd { return asd > bsd }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// Rentals currently on location (for report)
    private var onLocationRentals: [RentalItem] {
        (well.rentals ?? []).filter { $0.onLocation && !$0.invoiced }
            .sorted { a, b in
                let asd = a.startDate ?? .distantPast
                let bsd = b.startDate ?? .distantPast
                if asd != bsd { return asd < bsd }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }

    /// Rentals that are active (used & on location) or standby (on location but not used yet)
    private var activeAndStandbyRentals: [RentalItem] {
        (well.rentals ?? []).filter { $0.onLocation && !$0.invoiced }
            .sorted { a, b in
                // Sort active first, then standby
                if a.used != b.used { return a.used }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }

    // MARK: - Grouped Rentals for List View

    private struct CategoryGroup: Identifiable {
        var id: String { category?.id.uuidString ?? "uncategorized" }
        let category: RentalCategory?
        var active: [RentalItem]      // Used/running, on location, not invoiced
        var standby: [RentalItem]     // On location but not used yet
        var shipped: [RentalItem]     // Shipped out (not on location), not invoiced
        var invoiced: [RentalItem]    // Completed/invoiced

        var totalCount: Int { active.count + standby.count + shipped.count + invoiced.count }
    }

    private var groupedRentals: [CategoryGroup] {
        var categoryBuckets: [UUID?: [RentalItem]] = [:]
        for rental in filteredRentals {
            let catId = rental.category?.id
            categoryBuckets[catId, default: []].append(rental)
        }

        var groups: [CategoryGroup] = []

        // Sort categories by name
        let categoryIds = Set(categoryBuckets.keys)
        let sortedCats: [RentalCategory] = categoryIds.compactMap { catId -> RentalCategory? in
            guard let catId = catId else { return nil }
            return categories.first { $0.id == catId }
        }.sorted { $0.name < $1.name }

        for cat in sortedCats {
            let rentals = categoryBuckets[cat.id] ?? []
            let active = rentals.filter { $0.used && $0.onLocation && !$0.invoiced }.sorted { $0.name < $1.name }
            let standby = rentals.filter { !$0.used && $0.onLocation && !$0.invoiced }.sorted { $0.name < $1.name }
            let shipped = rentals.filter { !$0.onLocation && !$0.invoiced }.sorted { $0.name < $1.name }
            let invoiced = rentals.filter { $0.invoiced }.sorted { $0.name < $1.name }
            groups.append(CategoryGroup(category: cat, active: active, standby: standby, shipped: shipped, invoiced: invoiced))
        }

        // Uncategorized
        if let uncategorized = categoryBuckets[nil], !uncategorized.isEmpty {
            let active = uncategorized.filter { $0.used && $0.onLocation && !$0.invoiced }.sorted { $0.name < $1.name }
            let standby = uncategorized.filter { !$0.used && $0.onLocation && !$0.invoiced }.sorted { $0.name < $1.name }
            let shipped = uncategorized.filter { !$0.onLocation && !$0.invoiced }.sorted { $0.name < $1.name }
            let invoiced = uncategorized.filter { $0.invoiced }.sorted { $0.name < $1.name }
            groups.append(CategoryGroup(category: nil, active: active, standby: standby, shipped: shipped, invoiced: invoiced))
        }

        return groups
    }

    // MARK: - List View

    private var rentalListView: some View {
        List(selection: $selection) {
            ForEach(groupedRentals) { group in
                Section {
                    // Active rentals
                    if !group.active.isEmpty {
                        DisclosureGroup {
                            ForEach(group.active) { rental in
                                RentalListRow(rental: rental)
                                    .tag(rental)
                                    .contextMenu { rentalContextMenu(for: rental) }
                            }
                        } label: {
                            Label("\(group.active.count) Active", systemImage: "play.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }

                    // Standby rentals
                    if !group.standby.isEmpty {
                        DisclosureGroup {
                            ForEach(group.standby) { rental in
                                RentalListRow(rental: rental)
                                    .tag(rental)
                                    .contextMenu { rentalContextMenu(for: rental) }
                            }
                        } label: {
                            Label("\(group.standby.count) Standby", systemImage: "pause.circle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                    }

                    // Shipped rentals (off location, awaiting invoice)
                    if !group.shipped.isEmpty {
                        DisclosureGroup {
                            ForEach(group.shipped) { rental in
                                RentalListRow(rental: rental)
                                    .tag(rental)
                                    .contextMenu { rentalContextMenu(for: rental) }
                            }
                        } label: {
                            Label("\(group.shipped.count) Shipped", systemImage: "shippingbox.fill")
                                .foregroundStyle(.blue)
                                .font(.caption)
                        }
                    }

                    // Invoiced rentals
                    if !group.invoiced.isEmpty {
                        DisclosureGroup {
                            ForEach(group.invoiced) { rental in
                                RentalListRow(rental: rental)
                                    .tag(rental)
                                    .contextMenu { rentalContextMenu(for: rental) }
                            }
                        } label: {
                            Label("\(group.invoiced.count) Invoiced", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                } header: {
                    HStack {
                        if let category = group.category {
                            Label(category.name, systemImage: category.icon)
                        } else {
                            Label("Uncategorized", systemImage: "questionmark.folder")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        // Status summary
                        HStack(spacing: 8) {
                            if group.active.count > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "play.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("\(group.active.count)")
                                }
                            }
                            if group.standby.count > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "pause.circle.fill")
                                        .foregroundStyle(.orange)
                                    Text("\(group.standby.count)")
                                }
                            }
                            if group.shipped.count > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "shippingbox.fill")
                                        .foregroundStyle(.blue)
                                    Text("\(group.shipped.count)")
                                }
                            }
                            if group.invoiced.count > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                    Text("\(group.invoiced.count)")
                                }
                            }
                        }
                        .font(.caption2)
                    }
                }
            }
        }
        .listStyle(.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Card View

    private var rentalCardView: some View {
        List(selection: $selection) {
            ForEach(filteredRentals) { r in
                RentalCard(rental: r, selected: selection?.id == r.id, allEquipment: allEquipment) { selection = r }
                    .listRowSeparator(.hidden)
                    .contentShape(Rectangle())
                    .contextMenu { rentalContextMenu(for: r) }
            }
            .onDelete { idx in
                let items = idx.map { filteredRentals[$0] }
                items.forEach(delete)
            }
        }
        .listStyle(.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func rentalContextMenu(for r: RentalItem) -> some View {
        Button("Edit Details", systemImage: "square.and.pencil") { openEditor(r) }
        if r.equipment == nil {
            Button("Link to Equipment", systemImage: "link") {
                selection = r
                showEquipmentPicker = true
            }
        } else {
            Button("Unlink Equipment", systemImage: "link.badge.minus") {
                r.equipment = nil
                try? modelContext.save()
            }
        }
        Divider()
        statusMenu(for: r)
        Divider()
        Button("Transfer to Well", systemImage: "arrow.right.circle") {
            selection = r
            showTransferSheet = true
        }
        Button("Copy Summary", systemImage: "doc.on.doc") { copySummary(r) }
        Button("Copy Well + Rental", systemImage: "doc.on.clipboard") { copyWellPlusRental(r) }
        Divider()
        Button(role: .destructive) { delete(r) } label: { Label("Delete", systemImage: "trash") }
    }

    @ViewBuilder
    private func statusMenu(for rental: RentalItem) -> some View {
        Menu("Status") {
            ForEach(RentalItemStatus.allCases, id: \.self) { status in
                Button {
                    rental.status = status
                    try? modelContext.save()
                } label: {
                    Label(status.rawValue, systemImage: status.icon)
                }
            }
        }
    }

    private func addRental() {
        let r = RentalItem(name: "New Rental", detail: "", serialNumber: "", used: false, startDate: Date(), endDate: Date(), usageDates: [], onLocation: true, invoiced: false, costPerDay: 0, well: well)
        if well.rentals == nil { well.rentals = [] }
        well.rentals?.append(r)
        modelContext.insert(r)
        try? modelContext.save()
        selection = r
        openEditor(r)
    }

    private func delete(_ r: RentalItem) {
        if selection?.id == r.id { selection = nil }
        if editingRental?.id == r.id { editingRental = nil }
        if let i = (well.rentals ?? []).firstIndex(where: { $0.id == r.id }) {
            well.rentals?.remove(at: i)
        }
        modelContext.delete(r)
        try? modelContext.save()
    }

    private func openEditor(_ r: RentalItem) {
        // Ensure clean state transition for sheet
        if editingRental != nil {
            editingRental = nil
            // Small delay to allow sheet to dismiss before presenting new one
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                editingRental = r
            }
        } else {
            editingRental = r
        }
    }

    private func copySummary(_ r: RentalItem) {
        let summary = buildRentalSummary(r)
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        #else
        UIPasteboard.general.string = summary
        #endif
    }

    private func copyWellPlusRental(_ r: RentalItem) {
        let wellHeader = "Well Name: \(well.name)\nUWI: \(well.uwi ?? "")\nAFE: \(well.afeNumber ?? "")\nRequisitioner: \(well.requisitioner ?? "")"
        let rentalSummary = buildRentalSummary(r)
        let combined = wellHeader + "\n\n" + rentalSummary
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(combined, forType: .string)
        #else
        UIPasteboard.general.string = combined
        #endif
    }

    private func buildRentalSummary(_ r: RentalItem) -> String {
        let cal = Calendar.current
        let dates: [Date]
        if !r.usageDates.isEmpty {
            dates = r.usageDates.map { cal.startOfDay(for: $0) }.sorted()
        } else if let s = r.startDate, let e = r.endDate {
            var out: [Date] = []
            var day = cal.startOfDay(for: min(s, e))
            let end = cal.startOfDay(for: max(s, e))
            while day <= end { out.append(day); day = cal.date(byAdding: .day, value: 1, to: day) ?? day }
            dates = out
        } else {
            dates = []
        }
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .none
        var parts: [String] = []
        if !dates.isEmpty {
            var start = dates[0]; var prev = dates[0]
            func push() {
                if start == prev { parts.append(df.string(from: start)) }
                else { parts.append("\(df.string(from: start))–\(df.string(from: prev))") }
            }
            for d in dates.dropFirst() {
                if let next = cal.date(byAdding: .day, value: 1, to: prev), cal.isDate(d, inSameDayAs: next) { prev = d } else { push(); start = d; prev = d }
            }
            push()
        }
        let total = !dates.isEmpty ? dates.count : r.totalDays
        var lines: [String] = []
        lines.append("Tool: \(r.displayName)")
        if let d = r.detail, !d.isEmpty { lines.append("Desc: \(d)") }
        if let sn = r.serialNumber, !sn.isEmpty { lines.append("SN: \(sn)") }
        if let vendor = r.vendor { lines.append("Vendor: \(vendor.companyName)") }
        if !parts.isEmpty { lines.append("Days: \(parts.joined(separator: "; ")) (total: \(total))") } else { lines.append("Days: (total: \(total))") }
        if r.status != .notRun { lines.append("Status: \(r.status.rawValue)") }
        return lines.joined(separator: "\n")
    }
}

// MARK: - List Row
private struct RentalListRow: View {
    let rental: RentalItem

    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            Image(systemName: rental.category?.icon ?? "shippingbox")
                .font(.title2)
                .foregroundStyle(rental.invoiced ? Color.secondary : Color.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(rental.displayName)
                        .fontWeight(.medium)
                    if !rental.issueNotes.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                    if !rental.onLocation && !rental.invoiced {
                        Text("SHIPPED")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.2))
                            .foregroundStyle(.blue)
                            .cornerRadius(4)
                    } else if rental.used && rental.onLocation && !rental.invoiced {
                        Text("ACTIVE")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.2))
                            .foregroundStyle(.green)
                            .cornerRadius(4)
                    }
                    if rental.wasTransferred {
                        Image(systemName: "arrow.right.circle")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
                HStack(spacing: 8) {
                    if let sn = rental.serialNumber, !sn.isEmpty {
                        Text("SN: \(sn)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let vendor = rental.vendor {
                        Text(vendor.companyName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let equipment = rental.equipment {
                        HStack(spacing: 2) {
                            Image(systemName: "link")
                            Text(equipment.serialNumber)
                        }
                        .font(.caption)
                        .foregroundStyle(.blue)
                    }
                }
            }

            Spacer()

            // Status
            HStack(spacing: 4) {
                Image(systemName: rental.status.icon)
                    .foregroundStyle(rental.status.color)
                Text(rental.status.rawValue)
            }
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(rental.status.color.opacity(0.15))
            .cornerRadius(4)

            // Date range
            VStack(alignment: .trailing, spacing: 2) {
                if let start = rental.startDate {
                    Text(start, style: .date)
                        .font(.caption)
                }
                if rental.used {
                    Text("\(rental.totalDays) days")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, alignment: .trailing)

            // Cost
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "$%.2f", rental.totalCost))
                    .font(.caption)
                    .monospacedDigit()
                    .bold()
                if rental.costPerDay > 0 {
                    Text("$\(Int(rental.costPerDay))/day")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .opacity(rental.invoiced ? 0.6 : 1)
    }
}

// MARK: - Card Row
private struct RentalCard: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var rental: RentalItem
    var selected: Bool
    var allEquipment: [RentalEquipment]
    var onSelect: () -> Void

    private var cardFill: Color { selected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08) }
    private var cardStroke: Color { selected ? Color.accentColor : Color.secondary.opacity(0.25) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // First row: Name, Description, Serial, Status
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                // Category icon
                if let category = rental.category {
                    Image(systemName: category.icon)
                        .foregroundStyle(.blue)
                        .frame(width: 20)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Name").font(.caption).foregroundStyle(.secondary)
                    if rental.equipment != nil {
                        // Show name from linked equipment (read-only)
                        Text(rental.displayName)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(minWidth: 200, alignment: .leading)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                    } else {
                        TextField("Name", text: $rental.name)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 200)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Description").font(.caption).foregroundStyle(.secondary)
                    TextField("Description", text: Binding(get: { rental.detail ?? "" }, set: { rental.detail = $0 }))
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Serial #").font(.caption).foregroundStyle(.secondary)
                    if let equipment = rental.equipment {
                        // Show serial from linked equipment (read-only)
                        Text(equipment.serialNumber.isEmpty ? "—" : equipment.serialNumber)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(width: 160, alignment: .leading)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                    } else {
                        // Legacy: allow editing if no equipment linked
                        TextField("Serial #", text: Binding(get: { rental.serialNumber ?? "" }, set: { rental.serialNumber = $0 }))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                    }
                }

                // Status indicator
                VStack(alignment: .leading, spacing: 2) {
                    Text("Status").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: rental.status.icon)
                            .foregroundStyle(rental.status.color)
                        Text(rental.status.rawValue)
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(rental.status.color.opacity(0.15))
                    .cornerRadius(6)
                }

                Spacer(minLength: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text("$/Day").font(.caption).foregroundStyle(.secondary)
                    TextField("0", value: $rental.costPerDay, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                Button { copySummary() } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .help("Copy rental summary")
            }

            // Second row: Run, Dates, Days, Flags, Costs
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Run").font(.caption).foregroundStyle(.secondary)
                    Toggle("", isOn: $rental.used).labelsHidden()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start").font(.caption).foregroundStyle(.secondary)
                    DatePicker("", selection: Binding(get: { rental.startDate ?? Date() }, set: { rental.startDate = $0 }), displayedComponents: .date)
                        .labelsHidden()
                        .onChange(of: rental.startDate) { _, _ in syncUsageDatesFromRange() }
                        .frame(width: 160)
                        .disabled(!rental.used)
                        .opacity(rental.used ? 1 : 0.5)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("End").font(.caption).foregroundStyle(.secondary)
                    DatePicker("", selection: Binding(get: { rental.endDate ?? Date() }, set: { rental.endDate = $0 }), displayedComponents: .date)
                        .labelsHidden()
                        .onChange(of: rental.endDate) { _, _ in syncUsageDatesFromRange() }
                        .frame(width: 160)
                        .disabled(!rental.used)
                        .opacity(rental.used ? 1 : 0.5)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Days").font(.caption).foregroundStyle(.secondary)
                    Text("\(rental.totalDays)")
                        .monospacedDigit()
                        .foregroundStyle(rental.used ? .primary : .secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("On Loc").font(.caption).foregroundStyle(.secondary)
                    Toggle("", isOn: $rental.onLocation)
                        .labelsHidden()
                        .onChange(of: rental.onLocation) { _, newValue in
                            syncEquipmentLocation(onLocation: newValue)
                        }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Invoiced").font(.caption).foregroundStyle(.secondary)
                    Toggle("", isOn: $rental.invoiced).labelsHidden()
                }

                Spacer(minLength: 12)

                // Transfer indicator
                if rental.wasTransferred {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("From").font(.caption).foregroundStyle(.secondary)
                        Text(rental.transferredFromWellName ?? "Unknown")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                // Equipment link indicator
                if let equipment = rental.equipment {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Equipment").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.caption)
                            Text(equipment.serialNumber)
                                .font(.caption)
                        }
                        .foregroundStyle(.blue)
                    }
                }

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Additional").font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "$%.2f", rental.additionalCostsTotal)).monospacedDigit()
                }
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Total").font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "$%.2f", rental.totalCost)).bold().monospacedDigit()
                }
            }

            // Issue notes (if any)
            if !rental.issueNotes.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(rental.issueNotes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(cardFill))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(cardStroke, lineWidth: selected ? 1.5 : 1))
        .onTapGesture { onSelect() }
        .onDisappear { try? modelContext.save() }
    }

    private func syncUsageDatesFromRange() {
        guard let s = rental.startDate, let e = rental.endDate else { return }
        let cal = Calendar.current
        var day = cal.startOfDay(for: min(s, e))
        let end = cal.startOfDay(for: max(s, e))
        var days: [Date] = []
        while day <= end {
            days.append(day)
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        rental.usageDates = days
        try? modelContext.save()
    }

    private func syncEquipmentLocation(onLocation: Bool) {
        guard let equipment = rental.equipment else { return }
        if onLocation {
            // Coming back on location - set to onLocation or inUse based on whether rental is active
            equipment.locationStatus = rental.used ? .inUse : .onLocation
        } else {
            // Shipped out - set to withVendor
            equipment.locationStatus = .withVendor
        }
        equipment.touch()
        try? modelContext.save()
    }

    private func copySummary() {
        let summary = rentalSummaryString(for: rental)
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        #else
        UIPasteboard.general.string = summary
        #endif
    }

    private func rentalSummaryString(for r: RentalItem) -> String {
        let dates = normalizedDates(for: r)
        let ranges = condensedRangesString(from: dates)
        let total = dates.count > 0 ? dates.count : r.totalDays
        var lines: [String] = []
        lines.append("Tool: \(r.displayName)")
        if let d = r.detail, !d.isEmpty { lines.append("Desc: \(d)") }
        if let sn = r.serialNumber, !sn.isEmpty { lines.append("SN: \(sn)") }
        if !ranges.isEmpty { lines.append("Days: \(ranges) (total: \(total))") } else { lines.append("Days: (total: \(total))") }
        return lines.joined(separator: "\n")
    }

    private func normalizedDates(for r: RentalItem) -> [Date] {
        let cal = Calendar.current
        if !r.usageDates.isEmpty {
            return r.usageDates.map { cal.startOfDay(for: $0) }.sorted()
        }
        guard let s = r.startDate, let e = r.endDate else { return [] }
        var out: [Date] = []
        var day = cal.startOfDay(for: min(s, e))
        let end = cal.startOfDay(for: max(s, e))
        while day <= end {
            out.append(day)
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out
    }

    private func condensedRangesString(from dates: [Date]) -> String {
        guard !dates.isEmpty else { return "" }
        let cal = Calendar.current
        let dfShort = DateFormatter(); dfShort.dateStyle = .medium; dfShort.timeStyle = .none
        var parts: [String] = []
        var start = dates[0]
        var prev = dates[0]
        func pushCurrent() {
            if start == prev {
                parts.append(dfShort.string(from: start))
            } else {
                parts.append("\(dfShort.string(from: start))–\(dfShort.string(from: prev))")
            }
        }
        for d in dates.dropFirst() {
            if let next = cal.date(byAdding: .day, value: 1, to: prev), cal.isDate(d, inSameDayAs: next) {
                prev = d
            } else {
                pushCurrent()
                start = d
                prev = d
            }
        }
        pushCurrent()
        return parts.joined(separator: "; ")
    }
}

// MARK: - Transfer Sheet
private struct TransferRentalSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let rental: RentalItem
    let currentWell: Well
    let allWells: [Well]

    @State private var selectedWell: Well?
    @State private var keepOnCurrentWell = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Transfer Equipment") {
                    Text("Transfer **\(rental.displayName)** to another well.")
                        .font(.callout)

                    Picker("Destination Well", selection: $selectedWell) {
                        Text("Select a well...").tag(nil as Well?)
                        ForEach(allWells) { well in
                            Text(well.name).tag(well as Well?)
                        }
                    }

                    Toggle("Keep on current well (mark as invoiced)", isOn: $keepOnCurrentWell)
                        .help("If enabled, the current rental will be marked as invoiced. Otherwise, it will be removed.")
                }

                if let equipment = rental.equipment, equipment.isCurrentlyInUse, equipment.currentWell?.id != currentWell.id {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Warning: This equipment is currently marked as in use on \(equipment.currentWell?.name ?? "another well").")
                                .font(.caption)
                        }
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Transfer Rental")
            #if os(macOS)
            .frame(width: 450, height: 350)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Transfer") { performTransfer() }
                        .disabled(selectedWell == nil)
                }
            }
        }
    }

    private func performTransfer() {
        guard let destinationWell = selectedWell else { return }

        // Check for conflicts
        if let equipment = rental.equipment {
            if let error = equipment.canTransfer(to: destinationWell) {
                errorMessage = error
                return
            }
        }

        // Create new rental on destination well
        let newRental = rental.createTransferCopy(to: destinationWell)
        if destinationWell.rentals == nil { destinationWell.rentals = [] }
        destinationWell.rentals?.append(newRental)
        modelContext.insert(newRental)

        // Handle current rental
        if keepOnCurrentWell {
            rental.invoiced = true
            rental.used = true
        } else {
            // Remove from current well
            if let i = (currentWell.rentals ?? []).firstIndex(where: { $0.id == rental.id }) {
                currentWell.rentals?.remove(at: i)
            }
            modelContext.delete(rental)
        }

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Bulk Transfer Sheet
private struct BulkTransferRentalSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let rentals: [RentalItem]
    let currentWell: Well
    let allWells: [Well]

    @State private var selectedRentals: Set<UUID> = []
    @State private var selectedWell: Well?
    @State private var keepOnCurrentWell = true
    @State private var errorMessage: String?
    @State private var isTransferring = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header info
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bulk Transfer from \(currentWell.name)")
                            .font(.headline)
                        Text("\(selectedRentals.count) of \(rentals.count) items selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Select All") {
                        selectedRentals = Set(rentals.map { $0.id })
                    }
                    .buttonStyle(.bordered)
                    Button("Select None") {
                        selectedRentals.removeAll()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()

                Divider()

                // Rental list with checkboxes
                List {
                    Section("Active") {
                        ForEach(rentals.filter { $0.used }) { rental in
                            BulkTransferRow(rental: rental, isSelected: selectedRentals.contains(rental.id)) {
                                toggleSelection(rental)
                            }
                        }
                    }

                    Section("Standby") {
                        ForEach(rentals.filter { !$0.used }) { rental in
                            BulkTransferRow(rental: rental, isSelected: selectedRentals.contains(rental.id)) {
                                toggleSelection(rental)
                            }
                        }
                    }
                }
                .listStyle(.inset)

                Divider()

                // Transfer options
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Destination Well", selection: $selectedWell) {
                        Text("Select a well...").tag(nil as Well?)
                        ForEach(allWells) { well in
                            Text(well.name).tag(well as Well?)
                        }
                    }

                    Toggle("Keep on current well (mark as invoiced)", isOn: $keepOnCurrentWell)
                        .help("If enabled, the current rentals will be marked as invoiced. Otherwise, they will be removed.")

                    if let error = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .foregroundStyle(.red)
                        }
                        .font(.caption)
                    }
                }
                .padding()
            }
            .navigationTitle("Bulk Transfer")
            #if os(macOS)
            .frame(width: 600, height: 550)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Transfer \(selectedRentals.count) Items") {
                        performBulkTransfer()
                    }
                    .disabled(selectedWell == nil || selectedRentals.isEmpty || isTransferring)
                }
            }
            .onAppear {
                // Pre-select all rentals
                selectedRentals = Set(rentals.map { $0.id })
            }
        }
    }

    private func toggleSelection(_ rental: RentalItem) {
        if selectedRentals.contains(rental.id) {
            selectedRentals.remove(rental.id)
        } else {
            selectedRentals.insert(rental.id)
        }
    }

    private func performBulkTransfer() {
        guard let destinationWell = selectedWell else { return }
        isTransferring = true
        errorMessage = nil

        let rentalsToTransfer = rentals.filter { selectedRentals.contains($0.id) }

        // Check for conflicts
        for rental in rentalsToTransfer {
            if let equipment = rental.equipment {
                if let error = equipment.canTransfer(to: destinationWell) {
                    errorMessage = "Cannot transfer \(rental.displayName): \(error)"
                    isTransferring = false
                    return
                }
            }
        }

        // Perform transfers
        for rental in rentalsToTransfer {
            // Create new rental on destination well
            let newRental = rental.createTransferCopy(to: destinationWell)
            if destinationWell.rentals == nil { destinationWell.rentals = [] }
            destinationWell.rentals?.append(newRental)
            modelContext.insert(newRental)

            // Handle current rental
            if keepOnCurrentWell {
                rental.invoiced = true
                rental.used = true
                rental.onLocation = false
            } else {
                // Remove from current well
                if let i = (currentWell.rentals ?? []).firstIndex(where: { $0.id == rental.id }) {
                    currentWell.rentals?.remove(at: i)
                }
                modelContext.delete(rental)
            }
        }

        try? modelContext.save()
        isTransferring = false
        dismiss()
    }
}

// MARK: - Bulk Transfer Row
private struct BulkTransferRow: View {
    let rental: RentalItem
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? .blue : .secondary)
                .font(.title3)

            // Category icon
            Image(systemName: rental.category?.icon ?? "shippingbox")
                .foregroundStyle(.blue)
                .frame(width: 24)

            // Details
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(rental.displayName)
                        .fontWeight(.medium)
                    if rental.used {
                        Text("ACTIVE")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.2))
                            .foregroundStyle(.green)
                            .cornerRadius(4)
                    } else {
                        Text("STANDBY")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .cornerRadius(4)
                    }
                }
                HStack(spacing: 8) {
                    if let sn = rental.serialNumber, !sn.isEmpty {
                        Text("SN: \(sn)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let vendor = rental.vendor {
                        Text(vendor.companyName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Days & Cost
            VStack(alignment: .trailing, spacing: 2) {
                if rental.used {
                    Text("\(rental.totalDays) days")
                        .font(.caption)
                }
                Text(String(format: "$%.2f", rental.totalCost))
                    .font(.caption)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
    }
}

// MARK: - Equipment Picker Sheet
private struct EquipmentPickerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let rental: RentalItem?
    let allEquipment: [RentalEquipment]

    @State private var searchText = ""
    @State private var selectedEquipment: RentalEquipment?

    private var filteredEquipment: [RentalEquipment] {
        if searchText.isEmpty { return allEquipment }
        return allEquipment.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.serialNumber.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search
                TextField("Search equipment...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding()

                List(selection: $selectedEquipment) {
                    ForEach(filteredEquipment) { eq in
                        HStack {
                            VStack(alignment: .leading) {
                                HStack {
                                    Text(eq.displayName)
                                        .fontWeight(.medium)
                                    if eq.isCurrentlyInUse {
                                        Text("IN USE")
                                            .font(.caption2)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.orange.opacity(0.2))
                                            .foregroundStyle(.orange)
                                            .cornerRadius(4)
                                    }
                                }
                                HStack(spacing: 8) {
                                    if let cat = eq.category {
                                        Label(cat.name, systemImage: cat.icon)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let vendor = eq.vendor {
                                        Text(vendor.companyName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Spacer()
                            Text("\(eq.totalDaysUsed) days")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(eq)
                        .contentShape(Rectangle())
                    }
                }
            }
            .navigationTitle("Link to Equipment")
            #if os(macOS)
            .frame(width: 500, height: 400)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Link") { linkEquipment() }
                        .disabled(selectedEquipment == nil)
                }
            }
        }
    }

    private func linkEquipment() {
        guard let rental = rental, let equipment = selectedEquipment else { return }
        rental.equipment = equipment
        rental.name = equipment.name
        rental.serialNumber = equipment.serialNumber
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Add From Registry Sheet
private struct AddFromRegistrySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let well: Well
    let allEquipment: [RentalEquipment]

    @State private var searchText = ""
    @State private var selectedEquipment: Set<RentalEquipment> = []

    private var filteredEquipment: [RentalEquipment] {
        let available = allEquipment.filter { eq in
            // Don't show equipment already on this well
            !(eq.rentalUsages ?? []).contains { $0.well?.id == well.id && !$0.invoiced }
        }
        if searchText.isEmpty { return available }
        return available.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.serialNumber.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Search equipment...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding()

                List(filteredEquipment, selection: $selectedEquipment) { eq in
                    HStack {
                        VStack(alignment: .leading) {
                            HStack {
                                Text(eq.displayName)
                                    .fontWeight(.medium)
                                if eq.isCurrentlyInUse {
                                    Text("IN USE: \(eq.currentWell?.name ?? "?")")
                                        .font(.caption2)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.orange.opacity(0.2))
                                        .foregroundStyle(.orange)
                                        .cornerRadius(4)
                                }
                            }
                            HStack(spacing: 8) {
                                if let cat = eq.category {
                                    Label(cat.name, systemImage: cat.icon)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let vendor = eq.vendor {
                                    Text(vendor.companyName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                    }
                    .tag(eq)
                }
            }
            .navigationTitle("Add from Registry")
            #if os(macOS)
            .frame(width: 500, height: 450)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selectedEquipment.count) Items") { addSelected() }
                        .disabled(selectedEquipment.isEmpty)
                }
            }
        }
    }

    private func addSelected() {
        for equipment in selectedEquipment {
            let rental = RentalItem(
                name: equipment.name,
                detail: equipment.description_,
                serialNumber: equipment.serialNumber,
                used: false,
                status: .notRun,
                startDate: Date(),
                endDate: Date(),
                usageDates: [],
                onLocation: true,
                invoiced: false,
                costPerDay: 0,
                well: well,
                equipment: equipment
            )
            if well.rentals == nil { well.rentals = [] }
            well.rentals?.append(rental)
            modelContext.insert(rental)
        }
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Detail Editor
struct RentalDetailEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var rental: RentalItem
    var allEquipment: [RentalEquipment]

    @State private var newCostDesc: String = ""
    @State private var newCostAmount: String = ""
    @State private var showEquipmentPicker = false

    private var detailBinding: Binding<String> { Binding(get: { rental.detail ?? "" }, set: { rental.detail = $0 }) }
    private var serialBinding: Binding<String> { Binding(get: { rental.serialNumber ?? "" }, set: { rental.serialNumber = $0 }) }
    private var startDateBinding: Binding<Date> { Binding(get: { rental.startDate ?? Date() }, set: { rental.startDate = $0 }) }
    private var endDateBinding: Binding<Date> { Binding(get: { rental.endDate ?? Date() }, set: { rental.endDate = $0 }) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Details") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Text("Name").frame(width: 120, alignment: .trailing).foregroundStyle(.secondary)
                            TextField("Name", text: $rental.name).textFieldStyle(.roundedBorder)
                        }
                        HStack(spacing: 12) {
                            Text("Description").frame(width: 120, alignment: .trailing).foregroundStyle(.secondary)
                            TextField("Description", text: detailBinding).textFieldStyle(.roundedBorder)
                        }
                        HStack(spacing: 12) {
                            Text("Serial #").frame(width: 120, alignment: .trailing).foregroundStyle(.secondary)
                            TextField("Serial Number", text: serialBinding).textFieldStyle(.roundedBorder)
                        }
                        HStack(spacing: 12) {
                            Text("Equipment").frame(width: 120, alignment: .trailing).foregroundStyle(.secondary)
                            if let equipment = rental.equipment {
                                HStack {
                                    Image(systemName: "link")
                                        .foregroundStyle(.blue)
                                    Text(equipment.displayName)
                                    Spacer()
                                    Button("Unlink", systemImage: "link.badge.minus") {
                                        rental.equipment = nil
                                        try? modelContext.save()
                                    }
                                    .buttonStyle(.borderless)
                                }
                            } else {
                                Button("Link to Equipment", systemImage: "link") {
                                    showEquipmentPicker = true
                                }
                            }
                        }
                        HStack(spacing: 12) {
                            Text("Status").frame(width: 120, alignment: .trailing).foregroundStyle(.secondary)
                            Picker("", selection: $rental.statusRaw) {
                                ForEach(RentalItemStatus.allCases, id: \.self) { status in
                                    Label(status.rawValue, systemImage: status.icon).tag(status.rawValue)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }
                        HStack(spacing: 12) {
                            Text("Run/Used").frame(width: 120, alignment: .trailing).foregroundStyle(.secondary)
                            Toggle("", isOn: $rental.used).labelsHidden()
                            if !rental.used {
                                Text("(0 days - not run)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 12) {
                            Text("Start Date").frame(width: 120, alignment: .trailing).foregroundStyle(.secondary)
                            DatePicker("", selection: startDateBinding, displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .onChange(of: rental.startDate) { _, _ in syncUsageDatesFromRange() }
                                .disabled(!rental.used)
                                .opacity(rental.used ? 1 : 0.5)
                        }
                        HStack(spacing: 12) {
                            Text("End Date").frame(width: 120, alignment: .trailing).foregroundStyle(.secondary)
                            DatePicker("", selection: endDateBinding, displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .onChange(of: rental.endDate) { _, _ in syncUsageDatesFromRange() }
                                .disabled(!rental.used)
                                .opacity(rental.used ? 1 : 0.5)
                        }
                        HStack(spacing: 12) {
                            Text("On Location").frame(width: 120, alignment: .trailing).foregroundStyle(.secondary)
                            Toggle("", isOn: $rental.onLocation)
                                .labelsHidden()
                                .onChange(of: rental.onLocation) { _, newValue in
                                    syncEquipmentLocation(onLocation: newValue)
                                }
                        }
                        HStack(spacing: 12) {
                            Text("Invoiced").frame(width: 120, alignment: .trailing).foregroundStyle(.secondary)
                            Toggle("", isOn: $rental.invoiced).labelsHidden()
                        }
                    }
                }

                // Issue notes
                GroupBox("Issue Notes") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Record any issues with this rental during this period.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $rental.issueNotes)
                            .frame(minHeight: 60)
                    }
                }

                GroupBox("Usage Days") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Tap days on the calendar to toggle them.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(rental.totalDays) days selected")
                                .font(.caption)
                                .bold()
                        }

                        UsageCalendarView(selectedDates: $rental.usageDates)

                        HStack(spacing: 8) {
                            Button { addToday() } label: { Label("Add Today", systemImage: "calendar.badge.plus") }
                            Button { clearUsage() } label: { Label("Clear All", systemImage: "trash") }
                            Spacer()
                            Button { selectWeekdays() } label: { Label("Select Weekdays", systemImage: "calendar") }
                        }
                        .controlSize(.small)
                    }
                }

                GroupBox("Costs") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Text("Cost per day ($)").frame(width: 140, alignment: .trailing).foregroundStyle(.secondary)
                            TextField("0", value: $rental.costPerDay, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                        }
                        Divider()
                        Text("Additional Costs").font(.caption).foregroundStyle(.secondary)
                        AdditionalCostsList(
                            rental: rental,
                            newCostDesc: $newCostDesc,
                            newCostAmount: $newCostAmount,
                            onDelete: { cost in
                                if let i = rental.additionalCosts?.firstIndex(where: { $0 === cost }) {
                                    rental.additionalCosts?.remove(at: i)
                                }
                                modelContext.delete(cost)
                                try? modelContext.save()
                            },
                            onAdd: { addAdditionalCost() }
                        )
                        HStack {
                            Spacer()
                            Text("Addl: $\(String(format: "%.2f", rental.additionalCostsTotal))   Total: $\(String(format: "%.2f", rental.totalCost))")
                                .font(.callout)
                                .bold()
                        }
                    }
                }

                // Transfer history
                if rental.wasTransferred {
                    GroupBox("Transfer History") {
                        HStack {
                            Image(systemName: "arrow.right.circle")
                                .foregroundStyle(.orange)
                            Text("Transferred from \(rental.transferredFromWellName ?? "Unknown")")
                            if let date = rental.transferredAt {
                                Spacer()
                                Text(date, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .onDisappear { try? modelContext.save() }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button { copyWellPlusRental() } label: {
                    Label("Copy Well + Rental", systemImage: "doc.on.clipboard")
                }
            }
        }
        .sheet(isPresented: $showEquipmentPicker) {
            EquipmentPickerSheetForEditor(rental: rental, allEquipment: allEquipment)
        }
    }

    private func addToday() { rental.toggleUsage(on: Date()); try? modelContext.save() }
    private func clearUsage() { rental.usageDates = []; try? modelContext.save() }
    private func selectWeekdays() {
        // Select all weekdays in the current date range (or current month if no range)
        let cal = Calendar.current
        let startDate = rental.startDate ?? cal.startOfDay(for: Date())
        let endDate = rental.endDate ?? cal.date(byAdding: .month, value: 1, to: startDate) ?? startDate

        var days: [Date] = []
        var day = cal.startOfDay(for: min(startDate, endDate))
        let end = cal.startOfDay(for: max(startDate, endDate))

        while day <= end {
            let weekday = cal.component(.weekday, from: day)
            // Weekdays are 2-6 (Mon-Fri), 1 is Sunday, 7 is Saturday
            if weekday >= 2 && weekday <= 6 {
                days.append(day)
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        rental.usageDates = days
        try? modelContext.save()
    }
    private func addAdditionalCost() {
        let amount = Double(newCostAmount.replacingOccurrences(of: ",", with: "")) ?? 0
        guard !newCostDesc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || amount != 0 else { return }
        let c = RentalAdditionalCost(descriptionText: newCostDesc, amount: amount, date: Date())
        if rental.additionalCosts == nil { rental.additionalCosts = [] }
        rental.additionalCosts?.append(c)
        modelContext.insert(c)
        newCostDesc = ""; newCostAmount = ""
        try? modelContext.save()
    }
    private func syncUsageDatesFromRange() {
        guard let s = rental.startDate, let e = rental.endDate else { return }
        let cal = Calendar.current
        var day = cal.startOfDay(for: min(s, e))
        let end = cal.startOfDay(for: max(s, e))
        var days: [Date] = []
        while day <= end {
            days.append(day)
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        rental.usageDates = days
        try? modelContext.save()
    }

    private func syncEquipmentLocation(onLocation: Bool) {
        guard let equipment = rental.equipment else { return }
        if onLocation {
            // Coming back on location - set to onLocation or inUse based on whether rental is active
            equipment.locationStatus = rental.used ? .inUse : .onLocation
        } else {
            // Shipped out - set to withVendor
            equipment.locationStatus = .withVendor
        }
        equipment.touch()
        try? modelContext.save()
    }

    private func copyWellPlusRental() {
        let wellName = rental.well?.name ?? ""
        let uwi = rental.well?.uwi ?? ""
        let afe = rental.well?.afeNumber ?? ""
        let req = rental.well?.requisitioner ?? ""
        let wellHeader = "Well Name: \(wellName)\nUWI: \(uwi)\nAFE: \(afe)\nRequisitioner: \(req)"

        let cal = Calendar.current
        let dates: [Date]
        if !rental.usageDates.isEmpty {
            dates = rental.usageDates.map { cal.startOfDay(for: $0) }.sorted()
        } else if let s = rental.startDate, let e = rental.endDate {
            var out: [Date] = []
            var day = cal.startOfDay(for: min(s, e))
            let end = cal.startOfDay(for: max(s, e))
            while day <= end { out.append(day); day = cal.date(byAdding: .day, value: 1, to: day) ?? day }
            dates = out
        } else {
            dates = []
        }
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .none
        var parts: [String] = []
        if !dates.isEmpty {
            var start = dates[0]; var prev = dates[0]
            func push() {
                if start == prev { parts.append(df.string(from: start)) }
                else { parts.append("\(df.string(from: start))–\(df.string(from: prev))") }
            }
            for d in dates.dropFirst() {
                if let next = cal.date(byAdding: .day, value: 1, to: prev), cal.isDate(d, inSameDayAs: next) { prev = d } else { push(); start = d; prev = d }
            }
            push()
        }
        let total = !dates.isEmpty ? dates.count : rental.totalDays
        var rentalLines: [String] = []
        rentalLines.append("Tool: \(rental.displayName)")
        if let d = rental.detail, !d.isEmpty { rentalLines.append("Desc: \(d)") }
        if let sn = rental.serialNumber, !sn.isEmpty { rentalLines.append("SN: \(sn)") }
        if !parts.isEmpty { rentalLines.append("Days: \(parts.joined(separator: "; ")) (total: \(total))") } else { rentalLines.append("Days: (total: \(total))") }
        let combined = wellHeader + "\n\n" + rentalLines.joined(separator: "\n")
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(combined, forType: .string)
        #else
        UIPasteboard.general.string = combined
        #endif
    }

    private struct AdditionalCostsList: View {
        @Bindable var rental: RentalItem
        @Binding var newCostDesc: String
        @Binding var newCostAmount: String
        var onDelete: (RentalAdditionalCost) -> Void
        var onAdd: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rental.additionalCosts ?? []) { c in
                    HStack(spacing: 8) {
                        TextField("Description", text: Binding(get: { c.descriptionText }, set: { c.descriptionText = $0 }))
                            .textFieldStyle(.roundedBorder)
                        TextField("Amount", value: Binding(get: { c.amount }, set: { c.amount = $0 }), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                        Button(role: .destructive) { onDelete(c) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
                HStack(spacing: 8) {
                    TextField("Description", text: $newCostDesc)
                        .textFieldStyle(.roundedBorder)
                    TextField("Amount", text: $newCostAmount)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                        .onSubmit { onAdd() }
                    Button("Add Cost") { onAdd() }
                }
            }
        }
    }

    private struct UsageChipsView: View {
        let dates: [Date]
        let onRemove: (Date) -> Void
        private func dateString(_ d: Date) -> String { let df = DateFormatter(); df.dateStyle = .medium; return df.string(from: d) }
        var body: some View {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(dates, id: \.self) { d in
                    HStack(spacing: 4) {
                        Text(dateString(d)).font(.caption)
                        Button(role: .destructive) { onRemove(d) } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.12)))
                }
            }
        }
    }
}

// MARK: - Usage Calendar View
private struct UsageCalendarView: View {
    @Binding var selectedDates: [Date]
    @State private var displayedMonth: Date = Date()

    private let calendar = Calendar.current
    private let weekdaySymbols = Calendar.current.veryShortWeekdaySymbols

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayedMonth)
    }

    private var daysInMonth: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else {
            return []
        }

        var days: [Date?] = []
        let firstDayOfMonth = monthInterval.start
        let lastDayOfMonth = calendar.date(byAdding: .day, value: -1, to: monthInterval.end)!

        // Add nil for days before the first of the month
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        for _ in 1..<firstWeekday {
            days.append(nil)
        }

        // Add all days in the month
        var day = firstDayOfMonth
        while day <= lastDayOfMonth {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return days
    }

    private func isSelected(_ date: Date) -> Bool {
        let startOfDay = calendar.startOfDay(for: date)
        return selectedDates.contains { calendar.isDate($0, inSameDayAs: startOfDay) }
    }

    private func toggleDate(_ date: Date) {
        let startOfDay = calendar.startOfDay(for: date)
        if let index = selectedDates.firstIndex(where: { calendar.isDate($0, inSameDayAs: startOfDay) }) {
            selectedDates.remove(at: index)
        } else {
            selectedDates.append(startOfDay)
        }
    }

    private func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    private func isWeekend(_ date: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    var body: some View {
        VStack(spacing: 8) {
            // Month navigation
            HStack {
                Button {
                    if let prev = calendar.date(byAdding: .month, value: -1, to: displayedMonth) {
                        displayedMonth = prev
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)

                Spacer()
                Text(monthYearString)
                    .font(.headline)
                Spacer()

                Button {
                    if let next = calendar.date(byAdding: .month, value: 1, to: displayedMonth) {
                        displayedMonth = next
                    }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
            }

            // Weekday headers
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Calendar grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, date in
                    if let date = date {
                        Button {
                            toggleDate(date)
                        } label: {
                            Text("\(calendar.component(.day, from: date))")
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                                .frame(height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(isSelected(date) ? Color.blue : Color.clear)
                                )
                                .foregroundStyle(
                                    isSelected(date) ? .white :
                                    isToday(date) ? .blue :
                                    isWeekend(date) ? .secondary : .primary
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(isToday(date) ? Color.blue : Color.clear, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("")
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                    }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
        .onAppear {
            // Start displaying the month of the first selected date, or current month
            if let firstDate = selectedDates.sorted().first {
                displayedMonth = firstDate
            }
        }
    }
}

// Equipment Picker for Editor
private struct EquipmentPickerSheetForEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var rental: RentalItem
    let allEquipment: [RentalEquipment]

    @State private var searchText = ""
    @State private var selectedEquipment: RentalEquipment?

    private var filteredEquipment: [RentalEquipment] {
        let active = allEquipment.filter { $0.isActive }
        if searchText.isEmpty { return active }
        return active.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.serialNumber.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Search equipment...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding()

                List(selection: $selectedEquipment) {
                    ForEach(filteredEquipment) { eq in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(eq.displayName).fontWeight(.medium)
                                if let cat = eq.category {
                                    Label(cat.name, systemImage: cat.icon)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .tag(eq)
                    }
                }
            }
            .navigationTitle("Link to Equipment")
            #if os(macOS)
            .frame(width: 450, height: 350)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Link") {
                        if let equipment = selectedEquipment {
                            rental.equipment = equipment
                            rental.name = equipment.name
                            rental.serialNumber = equipment.serialNumber
                            try? modelContext.save()
                        }
                        dismiss()
                    }
                    .disabled(selectedEquipment == nil)
                }
            }
        }
    }
}

#if DEBUG
struct RentalItemsView_Previews: PreviewProvider {
    static var previews: some View {
        let container = try! ModelContainer(
            for: Well.self, RentalItem.self, RentalAdditionalCost.self, RentalCategory.self, RentalEquipment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext
        let well = Well(name: "Test Well")
        ctx.insert(well)
        let r1 = RentalItem(name: "MWD Tool", detail: "Telemetry", startDate: Date().addingTimeInterval(-86400*3), endDate: Date(), usageDates: [Date().addingTimeInterval(-86400*2), Date().addingTimeInterval(-86400)], onLocation: true, invoiced: false, costPerDay: 1200, well: well)
        let c1 = RentalAdditionalCost(descriptionText: "Delivery", amount: 250)
        if well.rentals == nil { well.rentals = [] }
        well.rentals?.append(r1)
        if r1.additionalCosts == nil { r1.additionalCosts = [] }
        r1.additionalCosts?.append(c1)
        ctx.insert(r1); ctx.insert(c1)
        try? ctx.save()

        return NavigationStack { RentalItemsView(well: well) }
            .modelContainer(container)
            .frame(width: 1100, height: 640)
    }
}
#endif
