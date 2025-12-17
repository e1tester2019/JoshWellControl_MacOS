//
//  InvoiceDetailView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-08.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct InvoiceDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var invoice: Invoice

    @State private var showingExportOptions = false
    @State private var pdfData: Data?
    @State private var showingEditNumber = false
    @State private var editedInvoiceNumber: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    headerSection

                    Divider()

                    // Line Items Table
                    lineItemsSection

                    Divider()

                    // Totals
                    totalsSection

                    // Status
                    statusSection
                }
                .padding()
            }
            .navigationTitle("Invoice #\(invoice.invoiceNumber)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            exportPDF()
                        } label: {
                            Label("Export PDF", systemImage: "arrow.down.doc")
                        }

                        Button {
                            invoice.isPaid.toggle()
                            if invoice.isPaid {
                                invoice.paidDate = Date.now
                            } else {
                                invoice.paidDate = nil
                            }
                            try? modelContext.save()
                        } label: {
                            Label(invoice.isPaid ? "Mark Unpaid" : "Mark Paid", systemImage: invoice.isPaid ? "xmark.circle" : "checkmark.circle")
                        }

                        Divider()

                        Button(role: .destructive) {
                            deleteInvoice()
                        } label: {
                            Label("Delete Invoice", systemImage: "trash")
                        }
                    } label: {
                        Label("Actions", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 700)
        .alert("Edit Invoice Number", isPresented: $showingEditNumber) {
            TextField("Invoice Number", text: $editedInvoiceNumber)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                if let newNumber = Int(editedInvoiceNumber), newNumber > 0 {
                    invoice.invoiceNumber = newNumber
                    invoice.updatedAt = Date.now
                    try? modelContext.save()

                    // Update next invoice number if needed
                    var businessInfo = BusinessInfo.shared
                    if newNumber >= businessInfo.nextInvoiceNumber {
                        businessInfo.nextInvoiceNumber = newNumber + 1
                        BusinessInfo.shared = businessInfo
                    }
                }
            }
        } message: {
            Text("Enter a new invoice number")
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top) {
            // Business info
            VStack(alignment: .leading, spacing: 4) {
                let info = BusinessInfo.shared
                Text(info.companyName)
                    .font(.headline)
                Text(info.phone)
                Text(info.email)
                Text(info.fullAddress)
            }
            .font(.callout)

            Spacer()

            // Invoice info
            VStack(alignment: .trailing, spacing: 4) {
                Text("INVOICE")
                    .font(.title2)
                    .fontWeight(.bold)

                let dateFormatter: DateFormatter = {
                    let f = DateFormatter()
                    f.dateFormat = "d MMM yyyy"
                    return f
                }()

                Button {
                    editedInvoiceNumber = String(invoice.invoiceNumber)
                    showingEditNumber = true
                } label: {
                    HStack(spacing: 4) {
                        Text("Invoice #\(invoice.invoiceNumber)")
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                Text("Date: \(dateFormatter.string(from: invoice.date))")
                Text("Terms: \(invoice.terms)")

                if let client = invoice.client {
                    Divider().frame(width: 200)
                    Text("Attention: \(client.contactName)")
                    Text(client.contactTitle)
                    Text(client.companyName)
                    Text(client.fullAddress)
                }
            }
            .font(.callout)
        }
    }

    private var lineItemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Line Items")
                .font(.headline)

            // Table header
            HStack {
                Text("Description")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Qty")
                    .frame(width: 60, alignment: .trailing)
                Text("Unit Price")
                    .frame(width: 100, alignment: .trailing)
                Text("Total")
                    .frame(width: 100, alignment: .trailing)
            }
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)

            Divider()

            // Line items
            ForEach((invoice.lineItems ?? []).sorted { $0.sortOrder < $1.sortOrder }) { item in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.descriptionText)
                                .fontWeight(.medium)
                            if !item.wellName.isEmpty {
                                Text(item.wellName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 12) {
                                if !item.afeNumber.isEmpty {
                                    Text("AFE: \(item.afeNumber)")
                                }
                                if !item.rigName.isEmpty {
                                    Text(item.rigName)
                                }
                                if !item.costCode.isEmpty {
                                    Text("Code: \(item.costCode)")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text("\(item.quantity)")
                            .frame(width: 60, alignment: .trailing)

                        Text(item.unitPrice, format: .currency(code: "CAD"))
                            .frame(width: 100, alignment: .trailing)

                        Text(item.total, format: .currency(code: "CAD"))
                            .frame(width: 100, alignment: .trailing)
                    }
                }
                .padding(.vertical, 4)

                Divider()
            }
        }
    }

    private var totalsSection: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                Text("Subtotal")
                Text(invoice.subtotal, format: .currency(code: "CAD"))
                    .frame(width: 100, alignment: .trailing)
            }

            HStack {
                Spacer()
                let info = BusinessInfo.shared
                Text("GST (\(info.gstNumber)) 5%")
                Text(invoice.gstAmount, format: .currency(code: "CAD"))
                    .frame(width: 100, alignment: .trailing)
            }

            Divider()
                .frame(width: 300)
                .frame(maxWidth: .infinity, alignment: .trailing)

            HStack {
                Spacer()
                Text("Total")
                    .fontWeight(.bold)
                Text(invoice.total, format: .currency(code: "CAD"))
                    .fontWeight(.bold)
                    .frame(width: 100, alignment: .trailing)
            }
        }
        .font(.callout)
    }

    private var statusSection: some View {
        let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "d MMM yyyy"
            return f
        }()

        return HStack {
            if invoice.isPaid {
                Label("Paid on \(invoice.paidDate.map { dateFormatter.string(from: $0) } ?? "N/A")", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Unpaid", systemImage: "clock")
                    .foregroundStyle(.orange)
            }

            Spacer()

            Button("Export PDF") {
                exportPDF()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top)
    }

    private func exportPDF() {
        guard let data = InvoicePDFGenerator.shared.generatePDF(for: invoice) else {
            return
        }

        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Invoice_\(invoice.invoiceNumber).pdf"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? data.write(to: url)
                NSWorkspace.shared.open(url)
            }
        }
        #elseif os(iOS)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Invoice_\(invoice.invoiceNumber).pdf")
        do {
            try data.write(to: tempURL)
            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                var presenter = rootVC
                while let presented = presenter.presentedViewController {
                    presenter = presented
                }
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = presenter.view
                    popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                presenter.present(activityVC, animated: true)
            }
        } catch {
            print("Failed to write PDF: \(error)")
        }
        #endif
    }

    private func deleteInvoice() {
        let invoiceNumber = invoice.invoiceNumber

        // Clear references from work days
        for item in invoice.lineItems ?? [] {
            for wd in item.workDays ?? [] {
                wd.lineItem = nil
            }
        }

        modelContext.delete(invoice)

        // Rewind invoice number
        var businessInfo = BusinessInfo.shared
        if invoiceNumber >= businessInfo.nextInvoiceNumber - 1 {
            businessInfo.nextInvoiceNumber = invoiceNumber
            BusinessInfo.shared = businessInfo
        }

        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Invoice.self, configurations: config)

    let invoice = Invoice(invoiceNumber: 1004)
    container.mainContext.insert(invoice)

    return InvoiceDetailView(invoice: invoice)
        .modelContainer(container)
}
