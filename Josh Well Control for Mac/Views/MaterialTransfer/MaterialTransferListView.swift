import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

struct MaterialTransferListView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var well: Well

    @State private var selection: MaterialTransfer? = nil
    @State private var editingTransfer: MaterialTransfer? = nil
    @State private var previewingTransfer: MaterialTransfer? = nil
    @State private var exportError: String? = nil

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
            MaterialTransferPDFPreviewSheet(well: well, transfer: transfer)
                .frame(minWidth: 700, minHeight: 900)
            #else
            MaterialTransferReportView(well: well, transfer: transfer)
                .environment(\.colorScheme, .light)
                .background(Color.white)
            #endif
        }
        .alert("Export Error", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "Unknown error")
        }
    }

    // MARK: - PDF Export (macOS)

    #if os(macOS)
    private func exportPDF(_ transfer: MaterialTransfer) {
        guard let data = MaterialTransferPDFGenerator.shared.generatePDF(for: transfer, well: well) else {
            exportError = "Failed to generate PDF"
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "MaterialTransfer_\(transfer.number).pdf"
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
                NSWorkspace.shared.open(url)
            } catch {
                exportError = error.localizedDescription
            }
        }
    }
    #endif

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
        // CRITICAL: Clear all state references IMMEDIATELY if they match the object being deleted
        if selection?.id == t.id {
            selection = nil
        }
        if editingTransfer?.id == t.id {
            editingTransfer = nil
        }
        if previewingTransfer?.id == t.id {
            previewingTransfer = nil
        }

        // Remove from array
        if let i = (well.transfers ?? []).firstIndex(where: { $0.id == t.id }) {
            well.transfers?.remove(at: i)
        }

        // Delete from context
        modelContext.delete(t)
        try? modelContext.save()
    }
}

// MARK: - PDF Preview Sheet (macOS)

#if os(macOS)
struct MaterialTransferPDFPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let well: Well
    let transfer: MaterialTransfer

    @State private var pdfData: Data?
    @State private var exportError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Material Transfer #\(transfer.number)")
                    .font(.headline)

                Spacer()

                Button {
                    exportPDF()
                } label: {
                    Label("Export PDF", systemImage: "square.and.arrow.up")
                }

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // PDF Preview
            if let data = pdfData {
                PDFKitView(data: data)
            } else {
                ContentUnavailableView("Generating PDF...", systemImage: "doc.text", description: Text("Please wait"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            generatePDF()
        }
        .alert("Export Error", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "Unknown error")
        }
    }

    private func generatePDF() {
        pdfData = MaterialTransferPDFGenerator.shared.generatePDF(for: transfer, well: well)
    }

    private func exportPDF() {
        guard let data = pdfData else {
            exportError = "No PDF data available"
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "MaterialTransfer_\(transfer.number).pdf"
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
                NSWorkspace.shared.open(url)
            } catch {
                exportError = error.localizedDescription
            }
        }
    }
}

// MARK: - PDFKit View Wrapper

import PDFKit

struct PDFKitView: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = NSColor.windowBackgroundColor
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if let document = PDFDocument(data: data) {
            pdfView.document = document
        }
    }
}
#endif

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
