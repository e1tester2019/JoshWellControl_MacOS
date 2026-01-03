//
//  RentalsOnLocationReportView.swift
//  Josh Well Control for Mac
//
//  PDF report preview for rentals currently on location
//

import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

#if os(macOS)
struct RentalsOnLocationReportPreview: View {
    let well: Well
    let rentals: [RentalItem]
    @Environment(\.dismiss) private var dismiss
    @State private var exportError: String? = nil
    @State private var pdfData: Data? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Preview – Rentals On Location")
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    export()
                } label: {
                    Label("Export PDF", systemImage: "square.and.arrow.up")
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(8)
            Divider()

            if let data = pdfData {
                WellRentalPDFPreviewView(data: data)
            } else {
                ContentUnavailableView("Generating PDF...", systemImage: "doc.text")
            }
        }
        .frame(minWidth: 700, minHeight: 600)
        .onAppear {
            generatePreview()
        }
        .alert("Export Error", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "Unknown error")
        }
    }

    private func generatePreview() {
        pdfData = RentalReportPDFGenerator.shared.generateWellRentalsReport(for: well, rentals: rentals)
    }

    private func export() {
        guard let data = pdfData else {
            exportError = "No PDF data to export"
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "RentalsOnLocation_\(well.name.replacingOccurrences(of: " ", with: "_")).pdf"
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
            } catch {
                exportError = error.localizedDescription
            }
        }
    }
}

// PDF Preview using PDFKit
private struct WellRentalPDFPreviewView: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFKit.PDFView {
        let pdfView = PDFKit.PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.backgroundColor = .windowBackgroundColor
        return pdfView
    }

    func updateNSView(_ pdfView: PDFKit.PDFView, context: Context) {
        if let document = PDFKit.PDFDocument(data: data) {
            pdfView.document = document
        }
    }
}

import PDFKit
#endif

#Preview {
    Text("Use RentalsOnLocationReportPreview")
}
