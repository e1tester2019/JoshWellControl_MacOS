import SwiftUI
import SwiftData

struct MaterialTransferListView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var well: Well

    @State private var selection: MaterialTransfer? = nil
    @State private var editingTransfer: MaterialTransfer? = nil
    @State private var previewingTransfer: MaterialTransfer? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Material Transfers for \(well.name)").font(.title3).bold()
                Spacer()
                Button("New Transfer", systemImage: "plus") { addTransfer() }
            }
            List(selection: $selection) {
                // Group transfers by outgoing/incoming
                let sorted = (well.transfers ?? []).sorted(by: { $0.date > $1.date })
                let outgoing = sorted.filter { $0.isShippingOut }
                let incoming = sorted.filter { !$0.isShippingOut }

                Section(header: Text("Outgoing").font(.headline)) {
                    ForEach(outgoing) { t in
                        transferRow(t)
                            .onTapGesture { selection = t }
                            .contextMenu {
                                Button("Open Editor", systemImage: "square.and.pencil") { openEditor(t) }
                                Button("Preview PDF", systemImage: "doc.text.magnifyingglass") { preview(t) }
                                Button(role: .destructive) { delete(t) } label: { Label("Delete", systemImage: "trash") }
                            }
                            .listRowSeparator(.hidden)
                    }
                    .onDelete { idx in
                        let items = idx.map { outgoing[$0] }
                        items.forEach(delete)
                    }
                }

                Section(header: Text("Incoming").font(.headline)) {
                    ForEach(incoming) { t in
                        transferRow(t)
                            .onTapGesture { selection = t }
                            .contextMenu {
                                Button("Open Editor", systemImage: "square.and.pencil") { openEditor(t) }
                                Button("Preview PDF", systemImage: "doc.text.magnifyingglass") { preview(t) }
                                Button(role: .destructive) { delete(t) } label: { Label("Delete", systemImage: "trash") }
                            }
                            .listRowSeparator(.hidden)
                    }
                    .onDelete { idx in
                        let items = idx.map { incoming[$0] }
                        items.forEach(delete)
                    }
                }
            }
            .listStyle(.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Button("Open Editor", systemImage: "square.and.pencil") { if let s = selection { openEditor(s) } }.disabled(selection == nil)
                Button("Preview PDF", systemImage: "doc.text.magnifyingglass") { if let s = selection { preview(s) } }.disabled(selection == nil)
                Spacer()
            }
        }
        .padding(12)
        .navigationTitle("Material Transfers")
        .sheet(item: $editingTransfer) { transfer in
            MaterialTransferEditorView(well: well, transfer: transfer)
                .environment(\.locale, Locale(identifier: "en_GB"))
                .frame(minWidth: 900, minHeight: 600)
        }
        .sheet(item: $previewingTransfer) { transfer in
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

    @ViewBuilder
    private func transferRow(_ t: MaterialTransfer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("#\(t.number)")
                    .font(.headline)
                    .monospacedDigit()
                DatePicker("", selection: Binding(get: { t.date }, set: { t.date = $0 }), displayedComponents: .date)
                    .labelsHidden()
                    .frame(width: 160)
                Spacer(minLength: 12)
                Text(String(format: "$%.2f", (t.items ?? []).reduce(0.0) { $0 + (($1.unitPrice ?? 0) * $1.quantity) }))
                    .font(.headline)
                    .monospacedDigit()
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                TextField("Country", text: Binding(get: { t.country ?? "" }, set: { t.country = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                TextField("Province", text: Binding(get: { t.province ?? "" }, set: { t.province = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                TextField("Shipping Company", text: Binding(get: { t.shippingCompany ?? "" }, set: { t.shippingCompany = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 240)
                Spacer()
                Button("Open Editor", systemImage: "square.and.pencil") { openEditor(t) }
                    .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill((selection?.id == t.id) ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke((selection?.id == t.id) ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: (selection?.id == t.id) ? 1.5 : 1)
        )
    }

    private func addTransfer() {
        let next = ((well.transfers ?? []).map { $0.number }.max() ?? 0) + 1
        let t = MaterialTransfer(number: next)
        t.well = well
        if well.transfers == nil { well.transfers = [] }
        well.transfers?.append(t)
        modelContext.insert(t)
        try? modelContext.save()
        selection = t
        openEditor(t)
    }

    private func openEditor(_ t: MaterialTransfer) {
        editingTransfer = t
    }

    private func preview(_ t: MaterialTransfer) {
        previewingTransfer = t
    }

    private func delete(_ t: MaterialTransfer) {
        if let i = (well.transfers ?? []).firstIndex(where: { $0.id == t.id }) {
            well.transfers?.remove(at: i)
        }
        modelContext.delete(t)
        try? modelContext.save()
        if selection?.id == t.id { selection = nil }
    }
}

//#Preview("Material Transfer List") {
//    let config = ModelConfiguration(isStoredInMemoryOnly: true)
//    let container = try! ModelContainer(for: Well.self, MaterialTransfer.self, MaterialTransferItem.self, configurations: config)
//    let ctx = container.mainContext
//    let w = Well(name: "Sundance 102/04-16-055-22W5", uwi: "102/04-16-055-22W5/00", afeNumber: "25D2566")
//    ctx.insert(w)
//    for n in 1...2 {
//        let t = MaterialTransfer(number: n)
//        t.activity = n == 1 ? "Drilling" : "Completions"
//        t.country = "Canada"; t.province = "Alberta"; t.shippingCompany = "Roughneck Logistics"; t.transportedBy = "TK-123"
//        t.well = w
//        if w.transfers == nil { w.transfers = [] }
//        w.transfers?.append(t)
//        ctx.insert(t)
//    }
//    NavigationStack { MaterialTransferListView(well: w) }
//        .modelContainer(container)
//        .frame(width: 800, height: 480)
//}
