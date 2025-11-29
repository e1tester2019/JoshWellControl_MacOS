//
//  PDFService.swift
//  Josh Well Control
//
//  Platform-agnostic PDF generation service
//

import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Service for handling PDF generation in a platform-agnostic way
class PDFService {
    static let shared = PDFService()

    private init() {}

    /// Generate PDF from a SwiftUI view
    /// - Parameter view: The view to render as PDF
    /// - Parameter size: The size of the PDF page
    /// - Returns: PDF data
    @MainActor
    func generatePDF<Content: View>(from view: Content, size: CGSize) -> Data {
        #if os(macOS)
        return generatePDFMacOS(from: view, size: size)
        #elseif os(iOS)
        return generatePDFIOS(from: view, size: size)
        #else
        return Data()
        #endif
    }

    #if os(macOS)
    @MainActor
    private func generatePDFMacOS<Content: View>(from view: Content, size: CGSize) -> Data {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(origin: .zero, size: size)

        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData) else { return Data() }

        var mediaBox = CGRect(origin: .zero, size: size)
        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        pdfContext.beginPDFPage(nil)

        if let context = NSGraphicsContext(cgContext: pdfContext, flipped: false) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context

            hostingView.layer?.render(in: pdfContext)

            NSGraphicsContext.restoreGraphicsState()
        }

        pdfContext.endPDFPage()
        pdfContext.closePDF()

        return pdfData as Data
    }
    #endif

    #if os(iOS)
    @MainActor
    private func generatePDFIOS<Content: View>(from view: Content, size: CGSize) -> Data {
        let hostingController = UIHostingController(rootView: view)
        hostingController.view.frame = CGRect(origin: .zero, size: size)

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))

        return renderer.pdfData { context in
            context.beginPage()
            hostingController.view.layer.render(in: context.cgContext)
        }
    }
    #endif

    /// Create a PDF context for manual drawing
    /// - Parameters:
    ///   - size: The size of the PDF page
    ///   - drawingHandler: Closure that performs the drawing
    /// - Returns: PDF data
    func createPDF(size: CGSize, drawingHandler: (CGContext) -> Void) -> Data {
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData) else { return Data() }

        var mediaBox = CGRect(origin: .zero, size: size)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        context.beginPDFPage(nil)
        drawingHandler(context)
        context.endPDFPage()
        context.closePDF()

        return pdfData as Data
    }
}
