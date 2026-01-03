//
//  EquipmentOnLocationReportView.swift
//  Josh Well Control for Mac
//
//  PDF report preview for equipment on location
//

import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
import PDFKit
#endif

#if os(macOS)
struct EquipmentOnLocationReportPreview: View {
    let equipment: [RentalEquipment]
    @Environment(\.dismiss) private var dismiss
    @State private var exportError: String? = nil
    @State private var pdfData: Data? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Preview – Equipment On Location")
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
                EquipmentPDFPreviewView(data: data)
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
        pdfData = RentalReportPDFGenerator.shared.generateEquipmentReport(equipment: equipment)
    }

    private func export() {
        guard let data = pdfData else {
            exportError = "No PDF data to export"
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "EquipmentOnLocation_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).pdf"
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
private struct EquipmentPDFPreviewView: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.backgroundColor = .windowBackgroundColor
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if let document = PDFDocument(data: data) {
            pdfView.document = document
        }
    }
}
#endif

#Preview {
    Text("Use EquipmentOnLocationReportPreview")
}
