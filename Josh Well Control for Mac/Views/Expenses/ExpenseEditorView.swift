//
//  ExpenseEditorView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-08.
//

import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers
import PDFKit

struct ExpenseEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Client.companyName) private var clients: [Client]
    @Query(sort: \Well.name) private var wells: [Well]

    let expense: Expense?

    @State private var date = Date.now
    @State private var amount: Double = 0
    @State private var vendor = ""
    @State private var expenseDescription = ""
    @State private var category: ExpenseCategory = .other
    @State private var province: Province = .alberta
    @State private var paymentMethod: PaymentMethod = .creditCard
    @State private var taxIncludedInAmount = true
    @State private var gstAmount: Double = 0
    @State private var pstAmount: Double = 0
    @State private var isReimbursable = false
    @State private var isReimbursed = false
    @State private var selectedClient: Client?
    @State private var selectedWell: Well?
    @State private var notes = ""

    // Receipt handling
    @State private var receiptImageData: Data?
    @State private var receiptThumbnailData: Data?
    @State private var receiptFileName: String?
    @State private var receiptIsPDF = false
    @State private var receiptDisplayImage: NSImage? // Rendered image for display (for PDFs)
    @State private var showingReceiptPreview = false
    @State private var isDraggingOver = false

    private var preTaxAmount: Double {
        if taxIncludedInAmount {
            return amount / (1 + province.totalTaxRate)
        }
        return amount
    }

    private var calculatedGST: Double {
        preTaxAmount * province.gstRate
    }

    private var calculatedPST: Double {
        preTaxAmount * province.pstRate
    }

    private var totalAmount: Double {
        if taxIncludedInAmount {
            return amount
        }
        return amount + gstAmount + pstAmount
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Info") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "en_GB"))

                    TextField("Vendor/Merchant", text: $vendor)

                    Picker("Category", selection: $category) {
                        ForEach(ExpenseCategory.allCases, id: \.self) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }

                    TextField("Description", text: $expenseDescription)
                }

                Section("Amount & Tax") {
                    Picker("Province", selection: $province) {
                        ForEach(Province.allCases, id: \.self) { prov in
                            Text(prov.rawValue).tag(prov)
                        }
                    }
                    .onChange(of: province) { _, _ in
                        if taxIncludedInAmount {
                            recalculateTaxes()
                        }
                    }

                    Toggle("Amount includes tax", isOn: $taxIncludedInAmount)
                        .onChange(of: taxIncludedInAmount) { _, _ in
                            recalculateTaxes()
                        }

                    HStack {
                        Text(taxIncludedInAmount ? "Total Amount" : "Pre-tax Amount")
                        Spacer()
                        TextField("Amount", value: $amount, format: .currency(code: "CAD"))
                            .frame(width: 120)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: amount) { _, _ in
                                recalculateTaxes()
                            }
                    }

                    HStack {
                        Text("GST (5%)")
                        Spacer()
                        if taxIncludedInAmount {
                            Text(calculatedGST, format: .currency(code: "CAD"))
                                .foregroundStyle(.secondary)
                        } else {
                            TextField("GST", value: $gstAmount, format: .currency(code: "CAD"))
                                .frame(width: 100)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    if province == .bc {
                        HStack {
                            Text("PST (7%)")
                            Spacer()
                            if taxIncludedInAmount {
                                Text(calculatedPST, format: .currency(code: "CAD"))
                                    .foregroundStyle(.secondary)
                            } else {
                                TextField("PST", value: $pstAmount, format: .currency(code: "CAD"))
                                    .frame(width: 100)
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }

                    HStack {
                        Text(taxIncludedInAmount ? "Pre-tax Amount" : "Total")
                            .fontWeight(.medium)
                        Spacer()
                        Text(taxIncludedInAmount ? preTaxAmount : totalAmount, format: .currency(code: "CAD"))
                            .fontWeight(.semibold)
                    }
                }

                Section("Payment") {
                    Picker("Payment Method", selection: $paymentMethod) {
                        ForEach(PaymentMethod.allCases, id: \.self) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                }

                Section("Receipt") {
                    receiptSection
                }

                Section("Reimbursement") {
                    Toggle("Reimbursable expense", isOn: $isReimbursable)

                    if isReimbursable {
                        Toggle("Has been reimbursed", isOn: $isReimbursed)
                    }
                }

                Section("Link to Job (Optional)") {
                    Picker("Client", selection: $selectedClient) {
                        Text("None").tag(nil as Client?)
                        ForEach(clients) { client in
                            Text(client.companyName).tag(client as Client?)
                        }
                    }

                    Picker("Well", selection: $selectedWell) {
                        Text("None").tag(nil as Well?)
                        ForEach(wells) { well in
                            Text(well.name).tag(well as Well?)
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(expense == nil ? "Add Expense" : "Edit Expense")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(amount <= 0)
                }
            }
            .onAppear { loadExpense() }
        }
        .frame(minWidth: 500, minHeight: 650)
    }

    @ViewBuilder
    private var receiptSection: some View {
        if let imageData = receiptImageData, let displayImage = receiptDisplayImage {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    // Thumbnail
                    Image(nsImage: displayImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 150)
                        .cornerRadius(8)
                        .onTapGesture {
                            showingReceiptPreview = true
                        }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 8) {
                        if let fileName = receiptFileName {
                            HStack(spacing: 4) {
                                if receiptIsPDF {
                                    Image(systemName: "doc.fill")
                                        .foregroundStyle(.red)
                                }
                                Text(fileName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button("View Full Size") {
                            showingReceiptPreview = true
                        }
                        .buttonStyle(.bordered)

                        Button("Remove") {
                            receiptImageData = nil
                            receiptThumbnailData = nil
                            receiptFileName = nil
                            receiptIsPDF = false
                            receiptDisplayImage = nil
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(.red)
                    }
                }
            }
            .sheet(isPresented: $showingReceiptPreview) {
                ReceiptPreviewView(imageData: imageData, fileName: receiptFileName, isPDF: receiptIsPDF)
            }
        } else {
            // Drop zone for receipt
            VStack(spacing: 12) {
                Image(systemName: "doc.badge.plus")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)

                Text("Drop receipt here or click to browse")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button("Choose File...") {
                    selectReceiptFile()
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(isDraggingOver ? Color.accentColor.opacity(0.1) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .foregroundStyle(isDraggingOver ? Color.accentColor : Color.secondary.opacity(0.3))
            )
            .onDrop(of: [.image, .pdf, .fileURL], isTargeted: $isDraggingOver) { providers in
                handleDrop(providers: providers)
            }
        }
    }

    private func selectReceiptFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        panel.begin { response in
            if response == .OK, let url = panel.url {
                loadReceiptFromURL(url)
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        loadReceiptFromURL(url)
                    }
                }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                if let data = data, let image = NSImage(data: data) {
                    DispatchQueue.main.async {
                        self.receiptImageData = data
                        self.receiptDisplayImage = image
                        self.receiptThumbnailData = generateThumbnail(from: image)
                        self.receiptFileName = "Dropped Image"
                        self.receiptIsPDF = false
                    }
                }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.pdf.identifier) { data, _ in
                if let data = data, let displayImg = self.renderPDFToImage(data: data) {
                    DispatchQueue.main.async {
                        self.receiptImageData = data
                        self.receiptDisplayImage = displayImg
                        self.receiptThumbnailData = self.generateThumbnail(from: displayImg)
                        self.receiptFileName = "Dropped PDF"
                        self.receiptIsPDF = true
                    }
                }
            }
            return true
        }

        return false
    }

    private func loadReceiptFromURL(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let isPDF = url.pathExtension.lowercased() == "pdf"

            receiptImageData = data
            receiptFileName = url.lastPathComponent
            receiptIsPDF = isPDF

            if isPDF {
                // Render PDF first page as image for display
                if let displayImg = renderPDFToImage(data: data) {
                    receiptDisplayImage = displayImg
                    receiptThumbnailData = generateThumbnail(from: displayImg)
                }
            } else {
                // Regular image
                if let image = NSImage(data: data) {
                    receiptDisplayImage = image
                    receiptThumbnailData = generateThumbnail(from: image)
                }
            }
        } catch {
            print("Failed to load receipt: \(error)")
        }
    }

    private func renderPDFToImage(data: Data, scale: CGFloat = 2.0) -> NSImage? {
        guard let pdfDocument = PDFDocument(data: data),
              let pdfPage = pdfDocument.page(at: 0) else { return nil }

        let pageRect = pdfPage.bounds(for: .mediaBox)
        let scaledSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)

        let image = NSImage(size: scaledSize)
        image.lockFocus()

        if let context = NSGraphicsContext.current?.cgContext {
            // White background
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: scaledSize))

            // Scale and render PDF
            context.scaleBy(x: scale, y: scale)
            pdfPage.draw(with: .mediaBox, to: context)
        }

        image.unlockFocus()
        return image
    }

    private func generateThumbnail(from image: NSImage) -> Data? {
        let maxSize: CGFloat = 200
        let originalSize = image.size
        let scale = min(maxSize / originalSize.width, maxSize / originalSize.height, 1.0)
        let newSize = CGSize(width: originalSize.width * scale, height: originalSize.height * scale)

        let thumbnail = NSImage(size: newSize)
        thumbnail.lockFocus()
        image.draw(in: CGRect(origin: .zero, size: newSize))
        thumbnail.unlockFocus()

        guard let tiffData = thumbnail.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }

        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }

    private func recalculateTaxes() {
        if taxIncludedInAmount {
            gstAmount = calculatedGST
            pstAmount = calculatedPST
        } else {
            gstAmount = preTaxAmount * province.gstRate
            pstAmount = preTaxAmount * province.pstRate
        }
    }

    private func loadExpense() {
        guard let exp = expense else { return }
        date = exp.date
        amount = exp.amount
        vendor = exp.vendor
        expenseDescription = exp.expenseDescription
        category = exp.category
        province = exp.province
        paymentMethod = exp.paymentMethod
        taxIncludedInAmount = exp.taxIncludedInAmount
        gstAmount = exp.gstAmount
        pstAmount = exp.pstAmount
        isReimbursable = exp.isReimbursable
        isReimbursed = exp.isReimbursed
        selectedClient = exp.client
        selectedWell = exp.well
        notes = exp.notes
        receiptImageData = exp.receiptImageData
        receiptThumbnailData = exp.receiptThumbnailData
        receiptFileName = exp.receiptFileName
        receiptIsPDF = exp.receiptIsPDF

        // Regenerate display image from stored data
        if let data = receiptImageData {
            if receiptIsPDF {
                receiptDisplayImage = renderPDFToImage(data: data)
            } else {
                receiptDisplayImage = NSImage(data: data)
            }
        }
    }

    private func save() {
        let exp = expense ?? Expense()
        exp.date = date
        exp.amount = amount
        exp.vendor = vendor
        exp.expenseDescription = expenseDescription
        exp.category = category
        exp.province = province
        exp.paymentMethod = paymentMethod
        exp.taxIncludedInAmount = taxIncludedInAmount
        exp.gstAmount = taxIncludedInAmount ? calculatedGST : gstAmount
        exp.pstAmount = taxIncludedInAmount ? calculatedPST : pstAmount
        exp.isReimbursable = isReimbursable
        exp.isReimbursed = isReimbursable ? isReimbursed : false
        exp.reimbursedDate = isReimbursed ? Date.now : nil
        exp.client = selectedClient
        exp.well = selectedWell
        exp.notes = notes
        exp.receiptImageData = receiptImageData
        exp.receiptThumbnailData = receiptThumbnailData
        exp.receiptFileName = receiptFileName
        exp.receiptIsPDF = receiptIsPDF
        exp.updatedAt = Date.now

        if expense == nil {
            modelContext.insert(exp)
        }
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Receipt Preview

struct ReceiptPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let imageData: Data
    let fileName: String?
    let isPDF: Bool

    var body: some View {
        NavigationStack {
            Group {
                if isPDF {
                    PDFPreviewView(data: imageData)
                } else if let nsImage = NSImage(data: imageData) {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                } else {
                    ContentUnavailableView {
                        Label("Cannot Display", systemImage: "photo")
                    } description: {
                        Text("This file format cannot be previewed")
                    }
                }
            }
            .navigationTitle(fileName ?? "Receipt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save As...") {
                        saveReceipt()
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 700)
    }

    private func saveReceipt() {
        let panel = NSSavePanel()
        if isPDF {
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = fileName ?? "receipt.pdf"
        } else {
            panel.allowedContentTypes = [.jpeg, .png]
            panel.nameFieldStringValue = fileName ?? "receipt.jpg"
        }

        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? imageData.write(to: url)
            }
        }
    }
}

// MARK: - PDF Preview (NSViewRepresentable wrapper for PDFView)

struct PDFPreviewView: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .windowBackgroundColor

        if let document = PDFDocument(data: data) {
            pdfView.document = document
        }

        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if let document = PDFDocument(data: data), pdfView.document?.dataRepresentation() != data {
            pdfView.document = document
        }
    }
}

#Preview {
    ExpenseEditorView(expense: nil)
}
