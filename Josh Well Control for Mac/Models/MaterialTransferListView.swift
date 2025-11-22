import SwiftUI
import SwiftData

struct MaterialTransferListView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var well: Well

    @State private var selection: MaterialTransfer? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Material Transfers for \(well.name)").font(.title3).bold()
                Spacer()
                Button("New Transfer", systemImage: "plus") { addTransfer() }
            }
            HStack(spacing: 12) {
                Text("M.T.#").font(.caption).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
                Text("Date").font(.caption).foregroundStyle(.secondary).frame(width: 140, alignment: .leading)
                Text("Country").font(.caption).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
                Text("Province").font(.caption).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
                Text("Shipping Company").font(.caption).foregroundStyle(.secondary).frame(minWidth: 160, alignment: .leading)
                Spacer(minLength: 12)
                Text("Total").font(.caption).foregroundStyle(.secondary).frame(width: 120, alignment: .trailing)
            }
            .padding(.horizontal, 4)
            List(selection: $selection) {
                ForEach(well.transfers.sorted(by: { $0.date > $1.date })) { t in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("#\(t.number)")
                            .monospacedDigit()
                            .frame(width: 60, alignment: .leading)
                        DatePicker("", selection: Binding(get: { t.date }, set: { t.date = $0 }), displayedComponents: .date)
                            .labelsHidden()
                            .frame(width: 140, alignment: .leading)
                        TextField("Country", text: Binding(get: { t.country ?? "" }, set: { t.country = $0 }))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                        TextField("Province", text: Binding(get: { t.province ?? "" }, set: { t.province = $0 }))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                        TextField("Shipping Company", text: Binding(get: { t.shippingCompany ?? "" }, set: { t.shippingCompany = $0 }))
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 160)
                        Spacer(minLength: 12)
                        let total = t.items.reduce(0.0) { $0 + (($1.unitPrice ?? 0) * $1.quantity) }
                        Text(String(format: "$%.2f", total))
                            .monospacedDigit()
                            .frame(width: 120, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selection = t }
                    .contextMenu {
                        Button("Open Editor", systemImage: "square.and.pencil") { openEditor(t) }
                        Button("Preview PDF", systemImage: "doc.text.magnifyingglass") { preview(t) }
                        Button(role: .destructive) { delete(t) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
                .onDelete { idx in
                    let arr = well.transfers.sorted(by: { $0.date > $1.date })
                    let items = idx.map { arr[$0] }
                    items.forEach(delete)
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
    }

    private func addTransfer() {
        let next = (well.transfers.map { $0.number }.max() ?? 0) + 1
        let t = MaterialTransfer(number: next)
        t.well = well
        well.transfers.append(t)
        modelContext.insert(t)
        try? modelContext.save()
        selection = t
        openEditor(t)
    }

    private func openEditor(_ t: MaterialTransfer) {
        let host = WindowHost(title: "Material Transfer #\(t.number)") {
            MaterialTransferEditorView(well: well, transfer: t)
                .frame(minWidth: 900, minHeight: 600)
        }
        host.show()
    }

    private func preview(_ t: MaterialTransfer) {
        let host = WindowHost(title: "Preview – Material Transfer #\(t.number)") {
            #if os(macOS)
            MaterialTransferReportPreview(well: well, transfer: t)
                .environment(\.colorScheme, .light)
                .background(Color.white)
            #else
            MaterialTransferReportView(well: well, transfer: t)
                .environment(\.colorScheme, .light)
                .background(Color.white)
            #endif
        }
        host.show()
    }

    private func delete(_ t: MaterialTransfer) {
        if let i = well.transfers.firstIndex(where: { $0.id == t.id }) { well.transfers.remove(at: i) }
        modelContext.delete(t)
        try? modelContext.save()
        if selection?.id == t.id { selection = nil }
    }
}

#Preview("Material Transfer List") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Well.self, MaterialTransfer.self, MaterialTransferItem.self, configurations: config)
    let ctx = container.mainContext
    let w = Well(name: "Sundance 102/04-16-055-22W5", uwi: "102/04-16-055-22W5/00", afeNumber: "25D2566")
    ctx.insert(w)
    for n in 1...2 {
        let t = MaterialTransfer(number: n)
        t.activity = n == 1 ? "Drilling" : "Completions"
        t.country = "Canada"; t.province = "Alberta"; t.shippingCompany = "Roughneck Logistics"; t.transportedBy = "TK-123"
        t.well = w
        w.transfers.append(t)
        ctx.insert(t)
    }
    return NavigationStack { MaterialTransferListView(well: w) }
        .modelContainer(container)
        .frame(width: 800, height: 480)
}
