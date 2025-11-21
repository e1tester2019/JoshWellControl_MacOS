import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct MaterialTransferEditorView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var well: Well
    @Bindable var transfer: MaterialTransfer

    @State private var selection: MaterialTransferItem? = nil
    @State private var showingExportPanel = false
    @State private var exportError: String? = nil
    @State private var expandedItems: Set<UUID> = []
    @State private var detailsHeights: [UUID: CGFloat] = [:]
    @State private var addressHeights: [UUID: CGFloat] = [:]

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
        .alert("Export Error", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "Unknown error")
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button { addItem() } label: { Label("Add Item", systemImage: "plus") }
                Button("Save") { try? modelContext.save() }
                Button { previewPDF() } label: { Label("Preview PDF", systemImage: "doc.text.magnifyingglass") }
                Button { exportPDF() } label: { Label("Export PDF", systemImage: "square.and.arrow.up") }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
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
                    Text("AFE #:").frame(width: 90, alignment: .trailing).foregroundStyle(.secondary)
                    TextField("AFE #", text: Binding(get: { transfer.afeNumber ?? "" }, set: { transfer.afeNumber = $0 }))
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
                    Text("Destination:").frame(width: 130, alignment: .trailing).foregroundStyle(.secondary)
                    TextField("To Loc/AFE/Vendor", text: Binding(get: { transfer.destinationName ?? "" }, set: { transfer.destinationName = $0 }))
                        .textFieldStyle(.roundedBorder)
                    Text("Transported By:").frame(width: 90, alignment: .trailing).foregroundStyle(.secondary)
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
            }
            .padding(8)
        }
    }

    // MARK: - Items
    private var itemsList: some View {
        GroupBox("Outgoing Transfers") {
            VStack(alignment: .leading, spacing: 8) {
                if transfer.items.isEmpty {
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
                    ForEach(transfer.items) { item in
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
                                // Per-card actions
                                Button { duplicate(item) } label: { Image(systemName: "doc.on.doc") }
                                    .buttonStyle(.borderless)
                                    .help("Duplicate")
                                Button(role: .destructive) { delete(item) } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless)
                                    .help("Delete")
                                // Disclosure toggle
                                Button {
                                    if expandedItems.contains(item.id) { expandedItems.remove(item.id) } else { expandedItems.insert(item.id) }
                                } label: {
                                    Label(expandedItems.contains(item.id) ? "Hide" : "More", systemImage: expandedItems.contains(item.id) ? "chevron.up" : "chevron.down")
                                }
                                .buttonStyle(.borderless)
                            }

                            // Expanded section with additional fields
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
                                                TextField("A-New / B-Used", text: Binding(get: { item.conditionCode ?? "" }, set: { item.conditionCode = $0 }))
                                                    .textFieldStyle(.roundedBorder)
                                            }
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
                                                Text("Transported By").font(.caption).foregroundStyle(.secondary)
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
                    .onDelete { idx in
                        let items = idx.map { transfer.items[$0] }
                        items.forEach { delete($0) }
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 240)
            }
            .padding(8)
        }
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

    // MARK: - Actions
    private func addItem() {
        let item = MaterialTransferItem(quantity: 1, descriptionText: "")
        item.transfer = transfer
        transfer.items.append(item)
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
        transfer.items.append(item)
        modelContext.insert(item)
        try? modelContext.save()
        selection = item
    }

    private func delete(_ item: MaterialTransferItem) {
        if let i = transfer.items.firstIndex(where: { $0.id == item.id }) { transfer.items.remove(at: i) }
        modelContext.delete(item)
        try? modelContext.save()
        if selection?.id == item.id { selection = nil }
    }

    private func previewPDF() {
        // Ensure latest edits are persisted before previewing
        try? modelContext.save()

        // Use a fresh instance of the report view so it reflects current state
        let host = WindowHost(title: "Preview – Material Transfer #\(transfer.number)") {
            MaterialTransferReportView(well: well, transfer: transfer)
                .id(UUID()) // force fresh render in case the host caches content
        }
        host.show()
    }

    private func exportPDF() {
        let page = CGSize(width: 612, height: 792)
        // Persist any pending edits so the report reflects the latest values
        try? modelContext.save()

        #if os(macOS)
        let reportView = MaterialTransferReportView(well: well, transfer: transfer)
            .id(UUID()) // force fresh render for export

        if let data = pdfDataForView(reportView, pageSize: page) {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = "MaterialTransfer_\(transfer.number).pdf"
            panel.canCreateDirectories = true
            if panel.runModal() == .OK, let url = panel.url {
                do {
                    try data.write(to: url)
                } catch {
                    exportError = error.localizedDescription
                }
            }
        } else {
            exportError = "Failed to generate PDF"
        }
        #endif
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
    t.country = "Canada"; t.province = "Alberta"; t.surfaceLocation = "14-21-055-22W5"; t.afeNumber = "25D2566"
    t.destinationName = "SCS Fishing"; t.transportedBy = "roughneck"
    t.accountCode = "3320-3210 - Drilling-Equipment- Downhole Rental"
    t.well = w
    w.transfers.append(t)
    ctx.insert(t)
    let i1 = MaterialTransferItem(quantity: 1, descriptionText: "1 guardian tripped 13 pin serial # VG1045")
    i1.accountCode = t.accountCode; i1.conditionCode = "B - Used"; i1.unitPrice = 0; i1.vendorOrTo = "SCS Fishing"; i1.transportedBy = "roughneck"; i1.transfer = t
    t.items.append(i1)
    ctx.insert(i1)
    return MaterialTransferEditorView(well: w, transfer: t)
        .modelContainer(container)
        .frame(width: 1000, height: 640)
}
