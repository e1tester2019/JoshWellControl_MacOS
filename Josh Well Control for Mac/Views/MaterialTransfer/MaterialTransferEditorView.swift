import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct MaterialTransferEditorView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var well: Well
    @Bindable var transfer: MaterialTransfer

    @State private var selection: MaterialTransferItem? = nil
    @State private var showingPreview = false
    @State private var expandedItems: Set<UUID> = []
    @State private var detailsHeights: [UUID: CGFloat] = [:]
    @State private var addressHeights: [UUID: CGFloat] = [:]
    @State private var showRestoreConfirm: Bool = false
    @State private var updateAlertMessage: String? = nil
    @State private var showAddFromRentals: Bool = false
    @State private var selectedRentalIDs: Set<UUID> = []
    @State private var showCreateRentals: Bool = false
    @State private var selectedTransferItemIDs: Set<UUID> = []
    @State private var showAffectedList: Bool = false

    init(well: Well, transfer: MaterialTransfer) {
        self._well = Bindable(wrappedValue: well)
        self._transfer = Bindable(wrappedValue: transfer)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            itemsList
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .frame(minWidth: 900, minHeight: 600)
        .navigationTitle("Material Transfer #\(transfer.number)")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button { addItem() } label: { Label("Add Item", systemImage: "plus") }
                Button { showAddFromRentals = true } label: { Label("Add From Rentals…", systemImage: "shippingbox") }
                Button { showCreateRentals = true } label: { Label("Create Rentals From Lines…", systemImage: "") }
                Button { showAffectedList = true } label: { Label("Preview Changes", systemImage: "eye") }
                Button("Save") { try? modelContext.save() }
                Button {
                    // Block preview if any item is missing receiver address
                    let missing = (transfer.items ?? []).contains { ($0.receiverAddress?.isEmpty ?? true) }
                    if missing {
                        updateAlertMessage = "One or more items are missing a Receiver Address. Please fill them in before previewing/exporting."
                    } else {
                        previewPDF()
                    }
                } label: { Label("Preview PDF", systemImage: "doc.text.magnifyingglass") }
            }
        }
        .sheet(isPresented: $showAddFromRentals) {
            AddFromRentalsSheet(
                rentals: well.rentals ?? [],
                selected: Binding(get: { selectedRentalIDs }, set: { selectedRentalIDs = $0 }),
                onCancel: {
                    selectedRentalIDs.removeAll()
                    showAddFromRentals = false
                },
                onAdd: {
                    addItemsFromSelectedRentals()
                    selectedRentalIDs.removeAll()
                    showAddFromRentals = false
                }
            )
        }
        .sheet(isPresented: $showCreateRentals) {
            CreateRentalsFromLinesSheet(
                items: transfer.items ?? [],
                selected: Binding(get: { selectedTransferItemIDs }, set: { selectedTransferItemIDs = $0 }),
                onCancel: {
                    selectedTransferItemIDs.removeAll()
                    showCreateRentals = false
                },
                onCreate: {
                    createRentalsFromSelectedLines()
                    selectedTransferItemIDs.removeAll()
                    showCreateRentals = false
                }
            )
        }
        .alert("Restore rentals to On Location?", isPresented: $showRestoreConfirm) {
            Button("Restore", role: .destructive) { restoreOnLocationFromTransferItems() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will set matching rentals (by serial number) back to On Location.")
        }
        .alert("Updates Applied", isPresented: Binding(get: { updateAlertMessage != nil }, set: { if !$0 { updateAlertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(updateAlertMessage ?? "")
        }
        .sheet(isPresented: $showAffectedList) {
            AffectedRentalsPreviewSheet(
                rentals: affectedMatches(),
                isShippingOut: transfer.isShippingOut,
                onCancel: { showAffectedList = false },
                onApply: {
                    let count = applyAffectedChanges()
                    updateAlertMessage = count > 0
                        ? (transfer.isShippingOut ? "Marked \(count) rental(s) off location." : "Restored \(count) rental(s) to On Location.")
                        : "No matching rentals to update."
                    transfer.isShippedBack = true
                    try? modelContext.save()
                    showAffectedList = false
                }
            )
        }
        .sheet(isPresented: $showingPreview) {
            #if os(macOS)
            MaterialTransferReportPreview(well: well, transfer: transfer)
                .environment(\.colorScheme, .light)
                .background(Color.white)
                .frame(minWidth: 800, minHeight: 1000)
            #else
            MaterialTransferReportView(well: well, transfer: transfer)
                .environment(\.colorScheme, .light)
                .background(Color.white)
            #endif
        }
    }

    // MARK: - Header
    private var header: some View {
        GroupBox("Header") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Operator:").frame(width: 130, alignment: .trailing).foregroundStyle(.secondary)
                    TextField("Operator", text: Binding(get: { transfer.operatorName ?? "" }, set: { transfer.operatorName = $0 }))
                        .textFieldStyle(.roundedBorder)
                    Text("Country:").frame(width: 90, alignment: .trailing).foregroundStyle(.secondary)
                    TextField("Country", text: Binding(get: { transfer.country ?? "" }, set: { transfer.country = $0 }))
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Activity:").frame(width: 130, alignment: .trailing).foregroundStyle(.secondary)
                    TextField("Drilling / Completions", text: Binding(get: { transfer.activity ?? "" }, set: { transfer.activity = $0 }))
                        .textFieldStyle(.roundedBorder)
                    Text("Date:").frame(width: 90, alignment: .trailing).foregroundStyle(.secondary)
                    DatePicker("", selection: Binding(get: { transfer.date }, set: { transfer.date = $0 }), displayedComponents: .date)
                        .labelsHidden()
                }
                GridRow {
                    Text("Province:").frame(width: 130, alignment: .trailing).foregroundStyle(.secondary)
                    TextField("Province", text: Binding(get: { transfer.province ?? "" }, set: { transfer.province = $0 }))
                        .textFieldStyle(.roundedBorder)
                    Text("Shipping Company:").frame(width: 90, alignment: .trailing).foregroundStyle(.secondary)
                    TextField("Shipping Company", text: Binding(get: { transfer.shippingCompany ?? "" }, set: { transfer.shippingCompany = $0 }))
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Destination:").frame(width: 130, alignment: .trailing).foregroundStyle(.secondary)
                    TextField("To Loc/AFE/Vendor", text: Binding(get: { transfer.destinationName ?? "" }, set: { transfer.destinationName = $0 }))
                        .textFieldStyle(.roundedBorder)
                    Text("Truck #:").frame(width: 90, alignment: .trailing).foregroundStyle(.secondary)
                    TextField("Truck / Company", text: Binding(get: { transfer.transportedBy ?? "" }, set: { transfer.transportedBy = $0 }))
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Default Account Code:").frame(width: 130, alignment: .trailing).foregroundStyle(.secondary)
                    TextField("3320-3210 - Drilling-Equipment- Downhole Rental", text: Binding(get: { transfer.accountCode ?? "" }, set: { transfer.accountCode = $0 }))
                        .textFieldStyle(.roundedBorder)
                    Text("Notes:").frame(width: 90, alignment: .trailing).foregroundStyle(.secondary)
                    TextField("Optional notes", text: Binding(get: { transfer.notes ?? "" }, set: { transfer.notes = $0 }))
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Shipping Out:").frame(width: 130, alignment: .trailing).foregroundStyle(.secondary)
                    Toggle("", isOn: Binding(get: { transfer.isShippingOut }, set: { newVal in
                        transfer.isShippingOut = newVal
                        if newVal {
                            // If shipping out, optionally mark rentals off location when creating from lines
                        }
                    }))
                    .labelsHidden()
                    Text("Shipped Back:").frame(width: 90, alignment: .trailing).foregroundStyle(.secondary)
                    Toggle("", isOn: Binding(get: { transfer.isShippedBack }, set: { newVal in
                        transfer.isShippedBack = newVal
                        if newVal {
                            applyShippedBackUpdate()
                        } else {
                            showRestoreConfirm = true
                        }
                    }))
                    .labelsHidden()
                }
            }
            .padding(8)
        }
    }

    // MARK: - Items
    private var itemsList: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if (transfer.items ?? []).isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No items yet.").font(.headline)
                        Text("Click Add Item to create your first line.")
                            .foregroundStyle(.secondary)
                        Button("Add Item", systemImage: "plus") { addItem() }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                }

                List(selection: $selection) {
                    let sortedItems = (transfer.items ?? []).sorted { lhs, rhs in
                        if lhs.quantity != rhs.quantity { return lhs.quantity > rhs.quantity }
                        let lw = lhs.estimatedWeight ?? 0
                        let rw = rhs.estimatedWeight ?? 0
                        if lw != rw { return lw > rw }
                        return lhs.descriptionText.localizedCaseInsensitiveCompare(rhs.descriptionText) == .orderedAscending
                    }
                    
                    // Group by receiver address key while preserving sorted order within groups
                    let groups: [(key: String, items: [MaterialTransferItem])] = {
                        var order: [String] = []
                        var buckets: [String: [MaterialTransferItem]] = [:]
                        for it in sortedItems {
                            let key = (it.receiverAddress?.isEmpty == false) ? it.receiverAddress! : "(No Receiver Address)"
                            if buckets[key] == nil { order.append(key); buckets[key] = [] }
                            buckets[key]?.append(it)
                        }
                        return order.map { ($0, buckets[$0] ?? []) }
                    }()

                    ForEach(groups, id: \.key) { group in
                        Section {
                            GroupBox(label: Text(group.key)) {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(group.items) { item in
                                        VStack(alignment: .leading, spacing: 8) {
                                            // Header row: qty + description + total + actions
                                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("Quantity").font(.caption).foregroundStyle(.secondary)
                                                    TextField("Qty", value: Binding(get: { item.quantity }, set: { item.quantity = $0 }), format: .number)
                                                        .frame(width: 80)
                                                        .textFieldStyle(.roundedBorder)
                                                        .monospacedDigit()
                                                }
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("$/Unit").font(.caption).foregroundStyle(.secondary)
                                                    TextField("0", value: Binding(get: { item.unitPrice ?? 0 }, set: { item.unitPrice = $0 }), format: .number)
                                                        .frame(width: 140)
                                                        .textFieldStyle(.roundedBorder)
                                                        .monospacedDigit()
                                                }
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("Description").font(.caption).foregroundStyle(.secondary)
                                                    TextField("Description", text: Binding(get: { item.descriptionText }, set: { item.descriptionText = $0 }))
                                                        .textFieldStyle(.roundedBorder)
                                                }
                                                Spacer(minLength: 12)
                                                let total = (item.unitPrice ?? 0) * item.quantity
                                                VStack(alignment: .trailing, spacing: 2) {
                                                    Text("Total").font(.caption).foregroundStyle(.secondary)
                                                    Text(String(format: "$%.2f", total))
                                                        .font(.headline)
                                                        .monospacedDigit()
                                                }
                                                Button { duplicate(item) } label: { Image(systemName: "doc.on.doc") }
                                                    .buttonStyle(.borderless)
                                                    .help("Duplicate")
                                                Button(role: .destructive) { delete(item) } label: { Image(systemName: "trash") }
                                                    .buttonStyle(.borderless)
                                                    .help("Delete")
                                                Button {
                                                    if expandedItems.contains(item.id) { expandedItems.remove(item.id) } else { expandedItems.insert(item.id) }
                                                } label: {
                                                    Label(expandedItems.contains(item.id) ? "Hide" : "More", systemImage: expandedItems.contains(item.id) ? "chevron.up" : "chevron.down")
                                                }
                                                .buttonStyle(.borderless)
                                            }

                                            if expandedItems.contains(item.id) {
                                                VStack(alignment: .leading, spacing: 8) {
                                                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                                                        GridRow {
                                                            Text("Details").frame(width: 130, alignment: .trailing).foregroundStyle(.secondary)
                                                            AutoGrowingEditor(text: Binding(get: { item.detailText ?? "" }, set: { item.detailText = $0 }),
                                                                              height: Binding(get: { detailsHeights[item.id] ?? 80 }, set: { detailsHeights[item.id] = $0 }),
                                                                              minHeight: 80)
                                                                .gridCellColumns(2)
                                                        }
                                                        GridRow {
                                                            Text("Receiver Address").frame(width: 130, alignment: .trailing).foregroundStyle(.secondary)
                                                            AutoGrowingEditor(text: Binding(get: { item.receiverAddress ?? "" }, set: { item.receiverAddress = $0 }),
                                                                              height: Binding(get: { addressHeights[item.id] ?? 80 }, set: { addressHeights[item.id] = $0 }),
                                                                              minHeight: 80)
                                                                .gridCellColumns(2)
                                                        }
                                                        GridRow {
                                                            Text("Account Code").frame(width: 130, alignment: .trailing).foregroundStyle(.secondary)
                                                            TextField("3320-3210", text: Binding(get: { item.accountCode ?? (transfer.accountCode ?? "") }, set: { item.accountCode = $0 }))
                                                                .textFieldStyle(.roundedBorder)
                                                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                                                Text("Condition").font(.caption).foregroundStyle(.secondary)
                                                                Picker("Condition", selection: Binding(get: {
                                                                    (item.conditionCode ?? "New").capitalized
                                                                }, set: { newVal in
                                                                    item.conditionCode = newVal
                                                                })) {
                                                                    Text("New").tag("New")
                                                                    Text("Used").tag("Used")
                                                                    Text("Damaged").tag("Damaged")
                                                                }
                                                                .pickerStyle(.segmented)
                                                                .frame(maxWidth: 280)
                                                            }
                                                        }
                                                        GridRow {
                                                            Text("Serial Number").frame(width: 130, alignment: .trailing).foregroundStyle(.secondary)
                                                            TextField("e.g., VG1045", text: Binding(get: { item.serialNumber ?? "" }, set: { item.serialNumber = $0.isEmpty ? nil : $0 }))
                                                                .textFieldStyle(.roundedBorder)
                                                            Spacer(minLength: 0)
                                                        }
                                                        GridRow {
                                                            Text("Receiver Phone").frame(width: 130, alignment: .trailing).foregroundStyle(.secondary)
                                                            TextField("(555) 555-5555", text: Binding(get: { item.receiverPhone ?? "" }, set: { item.receiverPhone = Self.formatPhone($0) }))
                                                                .textFieldStyle(.roundedBorder)
                                                            Spacer(minLength: 0)
                                                            Spacer(minLength: 0)
                                                        }
                                                        GridRow {
                                                            Text("To Loc/AFE/Vendor").frame(width: 130, alignment: .trailing).foregroundStyle(.secondary)
                                                            TextField("Destination", text: Binding(get: { item.vendorOrTo ?? (transfer.destinationName ?? "") }, set: { item.vendorOrTo = $0 }))
                                                                .textFieldStyle(.roundedBorder)
                                                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                                                Text("Truck #").font(.caption).foregroundStyle(.secondary)
                                                                TextField("Truck / Company", text: Binding(get: { item.transportedBy ?? (transfer.transportedBy ?? "") }, set: { item.transportedBy = $0 }))
                                                                    .textFieldStyle(.roundedBorder)
                                                            }
                                                        }
                                                        GridRow {
                                                            Text("Est. Weight (lb)").frame(width: 130, alignment: .trailing).foregroundStyle(.secondary)
                                                            TextField("0", value: Binding(get: { item.estimatedWeight ?? 0 }, set: { item.estimatedWeight = max(0, $0) }), format: .number)
                                                                .textFieldStyle(.roundedBorder)
                                                            Spacer(minLength: 0)
                                                        }
                                                    }
                                                }
                                                .transition(.opacity.combined(with: .move(edge: .top)))
                                            }
                                        }
                                        .padding(10)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                                        .listRowSeparator(.hidden)
                                        .contentShape(Rectangle())
                                        .onTapGesture { selection = item }
                                        .tag(item as MaterialTransferItem?)
                                    }
                                    // Group subtotal footer
                                    Divider()
                                    let gQty = group.items.reduce(0) { $0 + $1.quantity }
                                    let gWeight = group.items.reduce(0.0) { $0 + Double($1.estimatedWeight ?? 0) }
                                    let gValue = group.items.reduce(0.0) { $0 + Double(($1.unitPrice ?? 0) * $1.quantity) }
                                    HStack {
                                        Text("Subtotal qty:").foregroundStyle(.secondary)
                                        Text("\(Int(gQty))").monospacedDigit()
                                        Spacer()
                                        Text("Subtotal weight (lb):").foregroundStyle(.secondary)
                                        Text(String(format: "%.0f", gWeight)).monospacedDigit()
                                        Spacer()
                                        Text("Subtotal value:").foregroundStyle(.secondary)
                                        Text(String(format: "$%.2f", gValue)).monospacedDigit()
                                    }
                                }
                            }
                        }
                    }
                    
                    // Totals footer
                    Section {
                        let totalItems = (transfer.items ?? []).count
                        let totalQty = (transfer.items ?? []).reduce(0) { $0 + $1.quantity }
                        let totalWeight = (transfer.items ?? []).reduce(0.0) { $0 + Double($1.estimatedWeight ?? 0) }
                        HStack {
                            Text("Total items:")
                                .foregroundStyle(.secondary)
                            Text("\(totalItems)")
                                .monospacedDigit()
                            Spacer()
                            Text("Total qty:")
                                .foregroundStyle(.secondary)
                            Text("\(Int(totalQty))")
                                .monospacedDigit()
                            Spacer()
                            Text("Total weight (lb):")
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.0f", totalWeight))
                                .monospacedDigit()
                        }
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 240)
            }
            .padding(8)
        } label: {
            HStack(spacing: 8) {
                Text(transfer.isShippingOut ? "Outgoing Transfers" : "Incoming Transfers")
                let count = affectedRentalCount()
                if count > 0 {
                    Button {
                        showAffectedList = true
                    } label: {
                        Text("\(count)")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            .overlay(Capsule().stroke(Color.accentColor, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(transfer.isShippingOut ? "Rentals that will be marked off location" : "Rentals that can be restored to on location")
                }
            }
        }
    }

    private func affectedRentalCount() -> Int {
        // Count rentals that would be affected by current transfer lines, by serial number only.
        let serials = Set((transfer.items ?? []).compactMap { $0.serialNumber?.lowercased() }.filter { !$0.isEmpty })
        guard !serials.isEmpty else { return 0 }
        let matching = (well.rentals ?? []).filter { r in
            guard let rsn = r.serialNumber?.lowercased(), serials.contains(rsn) else { return false }
            return transfer.isShippingOut ? r.onLocation : !r.onLocation
        }
        return matching.count
    }

    private func affectedMatches() -> [RentalItem] {
        let serials = Set((transfer.items ?? []).compactMap { $0.serialNumber?.lowercased() }.filter { !$0.isEmpty })
        guard !serials.isEmpty else { return [] }
        return (well.rentals ?? []).filter { r in
            guard let rsn = r.serialNumber?.lowercased(), serials.contains(rsn) else { return false }
            return transfer.isShippingOut ? r.onLocation : !r.onLocation
        }
    }

    @discardableResult
    private func applyAffectedChanges() -> Int {
        let matches = affectedMatches()
        var updated = 0
        if transfer.isShippingOut {
            for r in matches where r.onLocation {
                r.onLocation = false
                updated += 1
            }
        } else {
            for r in matches where !r.onLocation {
                r.onLocation = true
                updated += 1
            }
        }
        if updated > 0 { try? modelContext.save() }
        return updated
    }

    // MARK: - Formatting helpers
    private static func formatPhone(_ raw: String) -> String {
        // Keep digits only and format as (XXX) XXX-XXXX if 10 digits
        let digits = raw.filter { $0.isNumber }
        if digits.count == 10 {
            let a = digits.prefix(3)
            let b = digits.dropFirst(3).prefix(3)
            let c = digits.suffix(4)
            return "(\(a)) \(b)-\(c)"
        }
        return raw
    }

    // MARK: - Auto-growing TextEditor helper
    private struct AutoGrowingEditor: View {
        @Binding var text: String
        @Binding var height: CGFloat
        var minHeight: CGFloat = 44
        var body: some View {
            ZStack(alignment: .topLeading) {
                // Measuring text
                Text(text.isEmpty ? " " : text)
                    .font(.body)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(6)
                    .opacity(0)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onChange(of: text) { _, _ in height = max(minHeight, geo.size.height) }
                                .onAppear { height = max(minHeight, geo.size.height) }
                        }
                    )
                TextEditor(text: $text)
                    .frame(height: max(minHeight, height))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
            }
        }
    }

    // MARK: - Rental ↔ Transfer helpers
    private func addItemsFromSelectedRentals() {
        guard !selectedRentalIDs.isEmpty else { return }
        let selected = (well.rentals ?? []).filter { selectedRentalIDs.contains($0.id) }
        for r in selected {
            let item = MaterialTransferItem(quantity: 1, descriptionText: Self.description(from: r))
            item.detailText = r.detail
            item.conditionCode = r.used ? "Used" : "New"
            item.serialNumber = r.serialNumber
            item.accountCode = transfer.accountCode
            item.transfer = transfer
            if transfer.items == nil { transfer.items = [] }
            transfer.items?.append(item)
            modelContext.insert(item)
        }
        try? modelContext.save()
    }

    private func createRentalsFromSelectedLines() {
        guard !selectedTransferItemIDs.isEmpty else { return }
        let chosen = (transfer.items ?? []).filter { selectedTransferItemIDs.contains($0.id) }
        for it in chosen {
            let rental = RentalItem(
                name: it.descriptionText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                detail: it.detailText,
                serialNumber: it.serialNumber ?? Self.serialNumber(fromDescription: it.descriptionText),
                startDate: transfer.date,
                endDate: nil,
                usageDates: [],
                onLocation: true,
                invoiced: false,
                costPerDay: 0,
                well: well
            )
            rental.used = (it.conditionCode?.lowercased() == "used")
            if well.rentals == nil { well.rentals = [] }
            well.rentals?.append(rental)
            modelContext.insert(rental)
        }
        try? modelContext.save()

        if transfer.isShippingOut {
            var updated = 0
            for it in chosen {
                if let sn = it.serialNumber, !sn.isEmpty {
                    for r in (well.rentals ?? []) where (r.serialNumber ?? "").caseInsensitiveCompare(sn) == .orderedSame {
                        if r.onLocation {
                            r.onLocation = false
                            updated += 1
                        }
                    }
                }
            }
            try? modelContext.save()
        }
    }

    private static func description(from rental: RentalItem) -> String {
        return rental.name
    }

    private static func serialNumber(fromDescription desc: String) -> String? {
        // Best-effort parse of "serial # XYZ" pattern
        let lower = desc.lowercased()
        guard let range = lower.range(of: "serial #") else { return nil }
        let after = desc[range.upperBound...].trimmingCharacters(in: .whitespaces)
        if after.isEmpty { return nil }
        // take until next space-separated clause; keep simple
        let token = after.split(separator: " ").first
        return token.map(String.init)
    }

    // MARK: - Sheets
    private struct AddFromRentalsSheet: View {
        var rentals: [RentalItem]
        @Binding var selected: Set<UUID>
        var onCancel: () -> Void
        var onAdd: () -> Void

        var body: some View {
            NavigationStack {
                VStack(alignment: .leading, spacing: 8) {
                    if rentals.isEmpty {
                        Text("No rentals found for this well.")
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        List {
                            ForEach(rentals) { r in
                                Toggle(isOn: Binding(
                                    get: { selected.contains(r.id) },
                                    set: { newVal in
                                        if newVal { selected.insert(r.id) } else { selected.remove(r.id) }
                                    }
                                )) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.name).font(.headline)
                                        if let d = r.detail, !d.isEmpty {
                                            Text(d).font(.caption).foregroundStyle(.secondary)
                                        }
                                        if let sn = r.serialNumber, !sn.isEmpty {
                                            Text("Serial: \(sn)").font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Add From Rentals")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onCancel() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Add") { onAdd() }.disabled(selected.isEmpty) }
                }
            }
            .frame(minWidth: 520, minHeight: 380)
        }
    }

    private struct CreateRentalsFromLinesSheet: View {
        var items: [MaterialTransferItem]
        @Binding var selected: Set<UUID>
        var onCancel: () -> Void
        var onCreate: () -> Void

        var body: some View {
            NavigationStack {
                VStack(alignment: .leading, spacing: 8) {
                    if items.isEmpty {
                        Text("No transfer lines to select.")
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        List {
                            ForEach(items) { it in
                                Toggle(isOn: Binding(
                                    get: { selected.contains(it.id) },
                                    set: { newVal in
                                        if newVal { selected.insert(it.id) } else { selected.remove(it.id) }
                                    }
                                )) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(it.descriptionText).font(.headline)
                                        if let d = it.detailText, !d.isEmpty {
                                            Text(d).font(.caption).foregroundStyle(.secondary)
                                        }
                                        if let sn = (it.serialNumber ?? MaterialTransferEditorView.serialNumber(fromDescription: it.descriptionText)) {
                                            Text("Serial: \(sn)").font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Create Rentals From Lines")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onCancel() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Create") { onCreate() }.disabled(selected.isEmpty) }
                }
            }
            .frame(minWidth: 520, minHeight: 380)
        }
    }

    private struct AffectedRentalsPreviewSheet: View {
        var rentals: [RentalItem]
        var isShippingOut: Bool
        var onCancel: () -> Void
        var onApply: () -> Void

        var body: some View {
            NavigationStack {
                VStack(alignment: .leading, spacing: 8) {
                    let title = isShippingOut ? "Will mark off location:" : "Will restore to on location:"
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    if rentals.isEmpty {
                        Text("No matching rentals found.")
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        List(rentals) { r in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.name).font(.headline)
                                    if let sn = r.serialNumber, !sn.isEmpty {
                                        Text("Serial: \(sn)").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(r.onLocation ? "On Location" : "Off Location")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .navigationTitle("Preview Changes")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onCancel() } }
                    ToolbarItem(placement: .confirmationAction) { Button(isShippingOut ? "Apply" : "Restore") { onApply() }.disabled(rentals.isEmpty) }
                }
            }
            .frame(minWidth: 520, minHeight: 420)
        }
    }

    // MARK: - Apply shipped back toggle update
    private func applyShippedBackUpdate() {
        // Mark rentals off location for items with matching serial numbers
        var updated = 0
        for it in (transfer.items ?? []) {
            if let sn = it.serialNumber, !sn.isEmpty {
                if let r = (well.rentals ?? []).first(where: { ($0.serialNumber ?? "").caseInsensitiveCompare(sn) == .orderedSame }) {
                    if r.onLocation {
                        r.onLocation = false
                        updated += 1
                    }
                }
            }
        }
        if updated > 0 { updateAlertMessage = "Marked \(updated) rental(s) off location." }
        try? modelContext.save()
    }

    private func restoreOnLocationFromTransferItems() {
        var restored = 0
        for it in (transfer.items ?? []) {
            if let sn = it.serialNumber, !sn.isEmpty {
                if let r = (well.rentals ?? []).first(where: { ($0.serialNumber ?? "").caseInsensitiveCompare(sn) == .orderedSame }) {
                    if !r.onLocation {
                        r.onLocation = true
                        restored += 1
                    }
                }
            }
        }
        if restored > 0 { updateAlertMessage = "Restored \(restored) rental(s) to On Location." }
        try? modelContext.save()
    }

    // MARK: - Actions
    private func addItem() {
        let item = MaterialTransferItem(quantity: 1, descriptionText: "")
        item.transfer = transfer
        if transfer.items == nil { transfer.items = [] }
        transfer.items?.append(item)
        modelContext.insert(item)
        try? modelContext.save()
        selection = item
    }

    private func duplicate(_ src: MaterialTransferItem) {
        let item = MaterialTransferItem(quantity: src.quantity, descriptionText: src.descriptionText)
        item.accountCode = src.accountCode
        item.conditionCode = src.conditionCode
        item.unitPrice = src.unitPrice
        item.vendorOrTo = src.vendorOrTo
        item.transportedBy = src.transportedBy
        item.transfer = transfer
        if transfer.items == nil { transfer.items = [] }
        transfer.items?.append(item)
        modelContext.insert(item)
        try? modelContext.save()
        selection = item
    }

    private func delete(_ item: MaterialTransferItem) {
        if let i = (transfer.items ?? []).firstIndex(where: { $0.id == item.id }) { transfer.items?.remove(at: i) }
        modelContext.delete(item)
        try? modelContext.save()
        if selection?.id == item.id { selection = nil }
    }

    private func previewPDF() {
        // Ensure latest edits are persisted before previewing
        try? modelContext.save()
        showingPreview = true
    }
}

#Preview("Material Transfer Editor") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Well.self, MaterialTransfer.self, MaterialTransferItem.self, configurations: config)
    let ctx = container.mainContext
    let w = Well(name: "Tourmaline Hz Sundance 102 04-16-055-22W5", uwi: "102/04-16-055-22W5/00")
    ctx.insert(w)
    let t = MaterialTransfer(number: 2)
    t.operatorName = "Tourmaline Oil Corp."
    t.activity = "Drilling"
    t.country = "Canada"
    t.province = "Alberta"
    t.shippingCompany = "FastShip Inc."
    t.destinationName = "SCS Fishing"
    t.transportedBy = "Truck #42"
    t.accountCode = "3320-3210 - Drilling-Equipment- Downhole Rental"
    t.well = w
    if w.transfers == nil { w.transfers = [] }
    w.transfers?.append(t)
    ctx.insert(t)
    let i1 = MaterialTransferItem(quantity: 1, descriptionText: "1 guardian tripped 13 pin serial # VG1045")
    i1.accountCode = t.accountCode; i1.conditionCode = "B - Used"; i1.unitPrice = 0; i1.vendorOrTo = "SCS Fishing"; i1.transportedBy = "Truck #42"; i1.transfer = t
    if t.items == nil { t.items = [] }
    t.items?.append(i1)
    ctx.insert(i1)
    return MaterialTransferEditorView(well: w, transfer: t)
        .modelContainer(container)
        .frame(width: 1000, height: 640)
}
