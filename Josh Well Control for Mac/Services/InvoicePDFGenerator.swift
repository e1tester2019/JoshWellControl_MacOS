//
//  InvoicePDFGenerator.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-08.
//

import Foundation
import AppKit

class InvoicePDFGenerator {
    static let shared = InvoicePDFGenerator()

    private init() {}

    // Brand color matching the invoice header
    private let brandColor = NSColor(red: 82/255, green: 165/255, blue: 191/255, alpha: 1.0)

    func generatePDF(for invoice: Invoice, pageSize: CGSize = CGSize(width: 612, height: 792)) -> Data? {
        let pdfInfo = [
            kCGPDFContextCreator: "Josh Well Control" as CFString
        ] as CFDictionary

        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)

        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, pdfInfo) else {
            return nil
        }

        let margin: CGFloat = 40
        let contentWidth = pageSize.width - 2 * margin
        let pageBottom: CGFloat = 60 // Leave room for page number
        var currentPage = 1
        var y: CGFloat = pageSize.height // Start from top

        // Helper to draw filled rectangle
        func fillRect(_ rect: CGRect, color: NSColor) {
            pdfContext.setFillColor(color.cgColor)
            pdfContext.fill(rect)
        }

        // Helper to draw text at a position (y is from top)
        func drawText(_ text: String, at point: CGPoint, attributes: [NSAttributedString.Key: Any]) {
            let attrString = NSAttributedString(string: text, attributes: attributes)
            let line = CTLineCreateWithAttributedString(attrString)
            pdfContext.textPosition = CGPoint(x: point.x, y: point.y)
            CTLineDraw(line, pdfContext)
        }

        // Helper to draw text in a rect with alignment
        func drawText(_ text: String, in rect: CGRect, attributes: [NSAttributedString.Key: Any], alignment: NSTextAlignment = .left) {
            let attrString = NSAttributedString(string: text, attributes: attributes)
            let line = CTLineCreateWithAttributedString(attrString)
            let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)

            var x = rect.minX
            if alignment == .center {
                x = rect.minX + (rect.width - CGFloat(lineWidth)) / 2
            } else if alignment == .right {
                x = rect.maxX - CGFloat(lineWidth)
            }

            pdfContext.textPosition = CGPoint(x: x, y: rect.minY)
            CTLineDraw(line, pdfContext)
        }

        func strokeLine(from: CGPoint, to: CGPoint, color: NSColor, width: CGFloat, dashed: Bool = false) {
            pdfContext.setStrokeColor(color.cgColor)
            pdfContext.setLineWidth(width)
            if dashed {
                pdfContext.setLineDash(phase: 0, lengths: [2, 2])
            } else {
                pdfContext.setLineDash(phase: 0, lengths: [])
            }
            pdfContext.move(to: from)
            pdfContext.addLine(to: to)
            pdfContext.strokePath()
        }

        func startPage() {
            pdfContext.beginPDFPage(nil)
        }

        func endPage() {
            // Draw page number
            let pageNumAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.gray
            ]
            drawText("\(currentPage)", in: CGRect(x: 0, y: 20, width: pageSize.width, height: 20), attributes: pageNumAttrs, alignment: .center)
            pdfContext.endPDFPage()
        }

        func checkPageBreak(neededHeight: CGFloat) {
            if y - neededHeight < pageBottom {
                endPage()
                currentPage += 1
                startPage()
                y = pageSize.height - 40 // Top margin on new page
            }
        }

        // Setup fonts and attributes
        let headerFont = NSFont.systemFont(ofSize: 16, weight: .bold)
        let titleFont = NSFont.systemFont(ofSize: 24, weight: .light)
        let labelFont = NSFont.systemFont(ofSize: 10, weight: .regular)
        let valueFont = NSFont.systemFont(ofSize: 10, weight: .regular)
        let smallFont = NSFont.systemFont(ofSize: 9, weight: .regular)
        let boldFont = NSFont.systemFont(ofSize: 10, weight: .semibold)

        let businessInfo = BusinessInfo.shared

        // Start first page
        startPage()

        // Draw header bar with brand color (at top of page)
        fillRect(CGRect(x: 0, y: pageSize.height - 50, width: pageSize.width, height: 50), color: brandColor)

        // Company name in header
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: headerFont,
            .foregroundColor: NSColor.white
        ]
        drawText(businessInfo.companyName, at: CGPoint(x: margin, y: pageSize.height - 34), attributes: headerAttrs)

        // Accent line under header
        fillRect(CGRect(x: 0, y: pageSize.height - 54, width: pageSize.width, height: 4), color: brandColor)

        y = pageSize.height - 70

        let brandAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: brandColor
        ]

        let regularAttrs: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: NSColor.darkGray
        ]

        // Left column - INVOICE title and business info
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor.darkGray
        ]
        drawText("INVOICE", at: CGPoint(x: margin, y: y), attributes: titleAttrs)

        y -= 35

        // Business contact info (brand color)
        drawText(businessInfo.phone, at: CGPoint(x: margin, y: y), attributes: brandAttrs)
        y -= 14
        drawText(businessInfo.email, at: CGPoint(x: margin, y: y), attributes: brandAttrs)
        y -= 20

        // Business address (brand color)
        drawText(businessInfo.address, at: CGPoint(x: margin, y: y), attributes: brandAttrs)
        y -= 14
        drawText("\(businessInfo.city), \(businessInfo.province)", at: CGPoint(x: margin, y: y), attributes: brandAttrs)
        y -= 14
        drawText(businessInfo.postalCode, at: CGPoint(x: margin, y: y), attributes: brandAttrs)

        // Right column - Client info
        var rightY: CGFloat = pageSize.height - 70
        let rightX = pageSize.width / 2 + 20

        if let client = invoice.client {
            drawText("Attention: \(client.contactName)", at: CGPoint(x: rightX, y: rightY), attributes: regularAttrs)
            rightY -= 14
            if !client.contactTitle.isEmpty {
                drawText(client.contactTitle, at: CGPoint(x: rightX, y: rightY), attributes: regularAttrs)
                rightY -= 14
            }
            drawText(client.companyName, at: CGPoint(x: rightX, y: rightY), attributes: regularAttrs)
            rightY -= 14
            if !client.address.isEmpty {
                drawText(client.address, at: CGPoint(x: rightX, y: rightY), attributes: regularAttrs)
                rightY -= 14
            }
            drawText("\(client.city), \(client.province) \(client.postalCode)", at: CGPoint(x: rightX, y: rightY), attributes: regularAttrs)
            rightY -= 14
        }

        // Date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d/MM/yyyy"
        drawText("Date: \(dateFormatter.string(from: invoice.date))", at: CGPoint(x: rightX, y: rightY), attributes: regularAttrs)

        y = min(y, rightY) - 30

        // Invoice details row
        dateFormatter.dateFormat = "d MMM yyyy"
        drawText(dateFormatter.string(from: invoice.date), at: CGPoint(x: margin, y: y), attributes: regularAttrs)

        let serviceX = margin + 100
        drawText(invoice.serviceDescription, at: CGPoint(x: serviceX, y: y), attributes: regularAttrs)

        let invoiceNumX = pageSize.width / 2
        drawText("Invoice Number: \(invoice.invoiceNumber)", at: CGPoint(x: invoiceNumX, y: y), attributes: regularAttrs)

        let termsX = pageSize.width - margin - 80
        drawText("Terms: \(invoice.terms)", at: CGPoint(x: termsX, y: y), attributes: regularAttrs)

        y -= 30

        // Table header
        fillRect(CGRect(x: margin, y: y - 18, width: contentWidth, height: 22), color: brandColor)

        let tableHeaderAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.white
        ]

        let columns: [(String, CGFloat, NSTextAlignment)] = [
            ("Description", contentWidth * 0.5, .left),
            ("Quantity", contentWidth * 0.15, .center),
            ("Unit Price", contentWidth * 0.17, .right),
            ("Cost", contentWidth * 0.18, .right)
        ]

        var xOffset = margin + 8
        for (title, width, alignment) in columns {
            drawText(title, in: CGRect(x: xOffset, y: y - 14, width: width - 16, height: 16), attributes: tableHeaderAttrs, alignment: alignment)
            xOffset += width
        }

        y -= 26

        // Table rows
        let rowHeight: CGFloat = 55
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .currency
        numberFormatter.currencySymbol = "$"
        numberFormatter.maximumFractionDigits = 2

        let sortedItems = (invoice.lineItems ?? []).sorted { $0.sortOrder < $1.sortOrder }

        let descAttrs: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: NSColor.black
        ]

        let detailAttrs: [NSAttributedString.Key: Any] = [
            .font: smallFont,
            .foregroundColor: NSColor.darkGray
        ]

        for item in sortedItems {
            // Check if we need a new page
            checkPageBreak(neededHeight: rowHeight + 20)

            // Row background
            fillRect(CGRect(x: margin, y: y - rowHeight, width: contentWidth, height: rowHeight), color: NSColor(white: 0.98, alpha: 1.0))

            xOffset = margin + 8
            var textY = y - 14

            // Description column
            drawText(item.descriptionText, at: CGPoint(x: xOffset, y: textY), attributes: descAttrs)
            textY -= 11

            // Well name
            if !item.wellName.isEmpty {
                drawText(item.wellName, at: CGPoint(x: xOffset, y: textY), attributes: detailAttrs)
                textY -= 10
            }

            // AFE
            if !item.afeNumber.isEmpty {
                drawText("AFE: \(item.afeNumber)", at: CGPoint(x: xOffset, y: textY), attributes: detailAttrs)
                textY -= 10
            }

            // Rig
            if !item.rigName.isEmpty {
                drawText(item.rigName, at: CGPoint(x: xOffset, y: textY), attributes: detailAttrs)
                textY -= 10
            }

            // Cost code
            if !item.costCode.isEmpty {
                drawText("Code: \(item.costCode)", at: CGPoint(x: xOffset, y: textY), attributes: detailAttrs)
            }

            xOffset += columns[0].1

            // Quantity
            drawText("\(item.quantity)", in: CGRect(x: xOffset, y: y - 14, width: columns[1].1 - 16, height: 16), attributes: descAttrs, alignment: .center)
            xOffset += columns[1].1

            // Unit Price
            let priceStr = numberFormatter.string(from: NSNumber(value: item.unitPrice)) ?? "$0.00"
            drawText(priceStr, in: CGRect(x: xOffset, y: y - 14, width: columns[2].1 - 16, height: 16), attributes: descAttrs, alignment: .right)
            xOffset += columns[2].1

            // Total
            let totalStr = numberFormatter.string(from: NSNumber(value: item.total)) ?? "$0.00"
            drawText(totalStr, in: CGRect(x: xOffset, y: y - 14, width: columns[3].1 - 16, height: 16), attributes: descAttrs, alignment: .right)

            // Draw dotted line separator
            strokeLine(from: CGPoint(x: margin, y: y - rowHeight),
                      to: CGPoint(x: pageSize.width - margin, y: y - rowHeight),
                      color: .lightGray, width: 0.5, dashed: true)

            y -= rowHeight
        }

        y -= 20

        // Check if totals section fits on current page
        checkPageBreak(neededHeight: 100)

        // Totals section
        let totalsX = pageSize.width - margin - 150
        let totalsValueX = pageSize.width - margin - 90

        let totalLabelAttrs: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: NSColor.darkGray
        ]

        let totalValueAttrs: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: NSColor.black
        ]

        // Subtotal
        drawText("Subtotal", at: CGPoint(x: totalsX, y: y), attributes: totalLabelAttrs)
        let subtotalStr = numberFormatter.string(from: NSNumber(value: invoice.subtotal)) ?? "$0.00"
        drawText(subtotalStr, in: CGRect(x: totalsValueX, y: y, width: 80, height: 16), attributes: totalValueAttrs, alignment: .right)

        y -= 18

        // GST
        drawText("GST (\(businessInfo.gstNumber)) 5.00%", at: CGPoint(x: totalsX - 80, y: y), attributes: totalLabelAttrs)
        let gstStr = numberFormatter.string(from: NSNumber(value: invoice.gstAmount)) ?? "$0.00"
        drawText(gstStr, in: CGRect(x: totalsValueX, y: y, width: 80, height: 16), attributes: totalValueAttrs, alignment: .right)

        y -= 22

        // Total
        let grandTotalLabelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        let grandTotalValueAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor.black
        ]

        drawText("Total", at: CGPoint(x: totalsX, y: y), attributes: grandTotalLabelAttrs)
        let grandTotalStr = numberFormatter.string(from: NSNumber(value: invoice.total)) ?? "$0.00"
        drawText(grandTotalStr, in: CGRect(x: totalsValueX, y: y, width: 80, height: 18), attributes: grandTotalValueAttrs, alignment: .right)

        // End final page
        endPage()
        pdfContext.closePDF()

        return data as Data
    }
}
