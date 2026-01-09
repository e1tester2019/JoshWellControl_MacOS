//
//  MaterialTransferPDFGenerator.swift
//  Josh Well Control
//
//  Cross-platform PDF generation for Material Transfer reports
//

import Foundation
import SwiftUI
import CoreGraphics
import CoreText

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Service for generating Material Transfer PDF reports in a cross-platform way
class MaterialTransferPDFGenerator {
    static let shared = MaterialTransferPDFGenerator()

    #if os(macOS)
    private typealias MTFont = NSFont
    private typealias MTColor = NSColor
    #elseif os(iOS)
    private typealias MTFont = UIFont
    private typealias MTColor = UIColor
    #endif

    private init() {}

    // Brand color matching the app theme
    private let brandColor = MTColor(red: 82/255, green: 165/255, blue: 191/255, alpha: 1.0)
    private let darkBrandColor = MTColor(red: 61/255, green: 143/255, blue: 168/255, alpha: 1.0)

    func generatePDF(for transfer: MaterialTransfer, well: Well, pageSize: CGSize = CGSize(width: 612, height: 792)) -> Data? {
        let pdfInfo = [
            kCGPDFContextCreator: "Josh Well Control" as CFString
        ] as CFDictionary

        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)

        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, pdfInfo) else {
            return nil
        }

        let margin: CGFloat = 40
        let contentWidth = pageSize.width - 2 * margin
        let pageBottom: CGFloat = 60
        var y: CGFloat = pageSize.height
        var currentPage = 1

        // Helper functions
        func fillRect(_ rect: CGRect, color: MTColor) {
            ctx.setFillColor(color.cgColor)
            ctx.fill(rect)
        }

        func drawText(_ text: String, at point: CGPoint, attributes: [NSAttributedString.Key: Any]) {
            let attrString = NSAttributedString(string: text, attributes: attributes)
            let line = CTLineCreateWithAttributedString(attrString)
            ctx.textPosition = CGPoint(x: point.x, y: point.y)
            CTLineDraw(line, ctx)
        }

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

            ctx.textPosition = CGPoint(x: x, y: rect.minY)
            CTLineDraw(line, ctx)
        }

        func strokeLine(from: CGPoint, to: CGPoint, color: MTColor, width: CGFloat, dashed: Bool = false) {
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(width)
            if dashed {
                ctx.setLineDash(phase: 0, lengths: [3, 3])
            } else {
                ctx.setLineDash(phase: 0, lengths: [])
            }
            ctx.move(to: from)
            ctx.addLine(to: to)
            ctx.strokePath()
        }

        func startPage() {
            ctx.beginPDFPage(nil)
        }

        func endPage() {
            let pageNumAttrs: [NSAttributedString.Key: Any] = [
                .font: MTFont.systemFont(ofSize: 10),
                .foregroundColor: MTColor.gray
            ]
            drawText("\(currentPage)", in: CGRect(x: 0, y: 20, width: pageSize.width, height: 20), attributes: pageNumAttrs, alignment: .center)
            ctx.endPDFPage()
        }

        func checkPageBreak(neededHeight: CGFloat) -> Bool {
            if y - neededHeight < pageBottom {
                endPage()
                currentPage += 1
                startPage()
                y = pageSize.height - 40
                return true
            }
            return false
        }

        // Fonts
        let headerFont = MTFont.systemFont(ofSize: 16, weight: .bold)
        let titleFont = MTFont.systemFont(ofSize: 24, weight: .light)
        let subtitleFont = MTFont.systemFont(ofSize: 14, weight: .medium)
        let labelFont = MTFont.systemFont(ofSize: 10, weight: .semibold)
        let valueFont = MTFont.systemFont(ofSize: 10, weight: .regular)
        let smallFont = MTFont.systemFont(ofSize: 9, weight: .regular)
        let tableHeaderFont = MTFont.systemFont(ofSize: 9, weight: .semibold)

        let businessInfo = BusinessInfo.shared

        // Number formatters
        let currencyFormatter = NumberFormatter()
        currencyFormatter.numberStyle = .currency
        currencyFormatter.currencySymbol = "$"

        let weightFormatter = NumberFormatter()
        weightFormatter.numberStyle = .decimal
        weightFormatter.maximumFractionDigits = 1

        // Group items by receiver address (preserving order of first appearance)
        let items = transfer.items ?? []
        var addressOrder: [String] = []
        var itemsByAddress: [String: [MaterialTransferItem]] = [:]

        for item in items {
            let addr = (item.receiverAddress?.isEmpty == false) ? item.receiverAddress! : "(No Receiver Address)"
            if itemsByAddress[addr] == nil {
                addressOrder.append(addr)
                itemsByAddress[addr] = []
            }
            itemsByAddress[addr]?.append(item)
        }

        let sortedDestinations = addressOrder  // Use insertion order, not alphabetical

        // Start first page
        startPage()

        // Header bar with brand color
        fillRect(CGRect(x: 0, y: pageSize.height - 50, width: pageSize.width, height: 50), color: brandColor)

        // Company name in header
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: headerFont,
            .foregroundColor: MTColor.white
        ]
        drawText(businessInfo.companyName, at: CGPoint(x: margin, y: pageSize.height - 34), attributes: headerAttrs)

        // Accent line under header
        fillRect(CGRect(x: 0, y: pageSize.height - 54, width: pageSize.width, height: 4), color: darkBrandColor)

        y = pageSize.height - 75

        // Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: MTColor.darkGray
        ]
        drawText("MATERIAL TRANSFER", at: CGPoint(x: margin, y: y), attributes: titleAttrs)

        y -= 30

        // Transfer number badge
        let transferNumAttrs: [NSAttributedString.Key: Any] = [
            .font: subtitleFont,
            .foregroundColor: brandColor
        ]
        drawText("Transfer #\(transfer.number)", at: CGPoint(x: margin, y: y), attributes: transferNumAttrs)

        // Date on right side
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy"
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: MTColor.darkGray
        ]
        drawText("Date: \(dateFormatter.string(from: transfer.date))", in: CGRect(x: pageSize.width - margin - 150, y: y, width: 150, height: 16), attributes: dateAttrs, alignment: .right)

        y -= 35

        // Info section background
        let infoBoxHeight: CGFloat = 90
        fillRect(CGRect(x: margin, y: y - infoBoxHeight, width: contentWidth, height: infoBoxHeight), color: MTColor(white: 0.97, alpha: 1.0))

        // Well info (left column)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: MTColor.gray
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: MTColor.black
        ]

        var infoY = y - 15
        let leftCol = margin + 12
        let rightCol = pageSize.width / 2 + 20

        // Left column - Well info
        drawText("WELL", at: CGPoint(x: leftCol, y: infoY), attributes: labelAttrs)
        infoY -= 14
        drawText(well.name, at: CGPoint(x: leftCol, y: infoY), attributes: valueAttrs)
        infoY -= 18

        if let uwi = well.uwi, !uwi.isEmpty {
            drawText("UWI", at: CGPoint(x: leftCol, y: infoY), attributes: labelAttrs)
            infoY -= 14
            drawText(uwi, at: CGPoint(x: leftCol, y: infoY), attributes: valueAttrs)
        }

        // Right column - Transfer details
        var rightY = y - 15
        drawText("DIRECTION", at: CGPoint(x: rightCol, y: rightY), attributes: labelAttrs)
        rightY -= 14
        let directionAttrs: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: transfer.isShippingOut ? MTColor.systemOrange : MTColor.systemGreen
        ]
        drawText(transfer.isShippingOut ? "Shipping Out" : "Receiving", at: CGPoint(x: rightCol, y: rightY), attributes: directionAttrs)
        rightY -= 18

        if let transportedBy = transfer.transportedBy, !transportedBy.isEmpty {
            drawText("TRANSPORTED BY", at: CGPoint(x: rightCol, y: rightY), attributes: labelAttrs)
            rightY -= 14
            drawText(transportedBy, at: CGPoint(x: rightCol, y: rightY), attributes: valueAttrs)
        }

        y -= infoBoxHeight + 20

        // Grand totals tracking
        var grandTotalQty: Double = 0
        var grandTotalWeight: Double = 0
        var grandTotalValue: Double = 0

        // Process each address group
        for (destIndex, destination) in sortedDestinations.enumerated() {
            let destItems = itemsByAddress[destination] ?? []

            // Check if we need a new page for destination header
            _ = checkPageBreak(neededHeight: 100)

            // Destination header
            let destHeaderAttrs: [NSAttributedString.Key: Any] = [
                .font: MTFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: brandColor
            ]

            if sortedDestinations.count > 1 {
                // Multiple destinations - show destination header
                fillRect(CGRect(x: margin, y: y - 22, width: contentWidth, height: 26), color: brandColor.withAlphaComponent(0.1))
                drawText("TO: \(destination)", at: CGPoint(x: margin + 10, y: y - 15), attributes: destHeaderAttrs)
                y -= 30
            }

            // Table header
            fillRect(CGRect(x: margin, y: y - 22, width: contentWidth, height: 26), color: brandColor)

            let tableHeaderAttrsWhite: [NSAttributedString.Key: Any] = [
                .font: tableHeaderFont,
                .foregroundColor: MTColor.white
            ]

            // Column definitions: (title, width, alignment)
            let columns: [(String, CGFloat, NSTextAlignment)] = [
                ("QTY", 40, .center),
                ("DESCRIPTION", contentWidth * 0.30, .left),
                ("SERIAL #", 70, .left),
                ("COND", 45, .center),
                ("WEIGHT", 55, .right),
                ("UNIT $", 60, .right),
                ("TOTAL", 65, .right)
            ]

            var xOffset = margin + 5
            for (title, width, alignment) in columns {
                drawText(title, in: CGRect(x: xOffset, y: y - 16, width: width - 6, height: 16), attributes: tableHeaderAttrsWhite, alignment: alignment)
                xOffset += width
            }

            y -= 28

            // Table rows
            let rowHeight: CGFloat = 32
            let descAttrs: [NSAttributedString.Key: Any] = [
                .font: valueFont,
                .foregroundColor: MTColor.black
            ]

            var destTotalQty: Double = 0
            var destTotalWeight: Double = 0
            var destTotalValue: Double = 0

            for (index, item) in destItems.enumerated() {
                // Check page break
                if checkPageBreak(neededHeight: rowHeight + 20) {
                    // Redraw table header on new page
                    fillRect(CGRect(x: margin, y: y - 22, width: contentWidth, height: 26), color: brandColor)
                    xOffset = margin + 5
                    for (title, width, alignment) in columns {
                        drawText(title, in: CGRect(x: xOffset, y: y - 16, width: width - 6, height: 16), attributes: tableHeaderAttrsWhite, alignment: alignment)
                        xOffset += width
                    }
                    y -= 28
                }

                // Alternating row background
                let bgColor = index % 2 == 0 ? MTColor(white: 0.98, alpha: 1.0) : MTColor.white
                fillRect(CGRect(x: margin, y: y - rowHeight, width: contentWidth, height: rowHeight), color: bgColor)

                xOffset = margin + 5

                // Quantity
                let qty = item.quantity
                destTotalQty += qty
                drawText("\(Int(qty))", in: CGRect(x: xOffset, y: y - 14, width: columns[0].1 - 6, height: 16), attributes: descAttrs, alignment: .center)
                xOffset += columns[0].1

                // Description
                drawText(item.descriptionText, at: CGPoint(x: xOffset, y: y - 14), attributes: descAttrs)
                xOffset += columns[1].1

                // Serial Number
                if let serial = item.serialNumber, !serial.isEmpty {
                    drawText(serial, at: CGPoint(x: xOffset, y: y - 14), attributes: descAttrs)
                }
                xOffset += columns[2].1

                // Condition
                if let condition = item.conditionCode, !condition.isEmpty {
                    let conditionColor: MTColor
                    switch condition.uppercased() {
                    case "NEW", "N": conditionColor = .systemGreen
                    case "GOOD", "G": conditionColor = .systemBlue
                    case "FAIR", "F": conditionColor = .systemOrange
                    case "POOR", "P", "SCRAP", "S": conditionColor = .systemRed
                    default: conditionColor = .darkGray
                    }
                    let condAttrs: [NSAttributedString.Key: Any] = [
                        .font: smallFont,
                        .foregroundColor: conditionColor
                    ]
                    drawText(condition, in: CGRect(x: xOffset, y: y - 14, width: columns[3].1 - 6, height: 16), attributes: condAttrs, alignment: .center)
                }
                xOffset += columns[3].1

                // Weight
                let weight = item.estimatedWeight ?? 0
                destTotalWeight += weight
                if weight > 0 {
                    let weightStr = weightFormatter.string(from: NSNumber(value: weight)) ?? "0"
                    drawText("\(weightStr) lb", in: CGRect(x: xOffset, y: y - 14, width: columns[4].1 - 6, height: 16), attributes: descAttrs, alignment: .right)
                }
                xOffset += columns[4].1

                // Unit Price
                let unitPrice = item.unitPrice ?? 0
                if unitPrice > 0 {
                    let unitStr = currencyFormatter.string(from: NSNumber(value: unitPrice)) ?? "$0.00"
                    drawText(unitStr, in: CGRect(x: xOffset, y: y - 14, width: columns[5].1 - 6, height: 16), attributes: descAttrs, alignment: .right)
                }
                xOffset += columns[5].1

                // Total
                let itemTotal = unitPrice * qty
                destTotalValue += itemTotal
                if itemTotal > 0 {
                    let totalStr = currencyFormatter.string(from: NSNumber(value: itemTotal)) ?? "$0.00"
                    drawText(totalStr, in: CGRect(x: xOffset, y: y - 14, width: columns[6].1 - 6, height: 16), attributes: descAttrs, alignment: .right)
                }

                // Row separator
                strokeLine(from: CGPoint(x: margin, y: y - rowHeight),
                          to: CGPoint(x: pageSize.width - margin, y: y - rowHeight),
                          color: MTColor(white: 0.85, alpha: 1.0), width: 0.5)

                y -= rowHeight
            }

            // Destination subtotals
            grandTotalQty += destTotalQty
            grandTotalWeight += destTotalWeight
            grandTotalValue += destTotalValue

            // Subtotal row
            y -= 5
            fillRect(CGRect(x: margin, y: y - 24, width: contentWidth, height: 28), color: MTColor(white: 0.93, alpha: 1.0))

            let subtotalLabelAttrs: [NSAttributedString.Key: Any] = [
                .font: MTFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: MTColor.darkGray
            ]

            let subtotalLabel = sortedDestinations.count > 1 ? "Subtotal - \(destination):" : "Total:"
            drawText(subtotalLabel, at: CGPoint(x: margin + 10, y: y - 16), attributes: subtotalLabelAttrs)

            // Subtotal values
            xOffset = margin + 5
            xOffset += columns[0].1 + columns[1].1 + columns[2].1 + columns[3].1

            // Weight subtotal
            if destTotalWeight > 0 {
                let weightStr = weightFormatter.string(from: NSNumber(value: destTotalWeight)) ?? "0"
                drawText("\(weightStr) lb", in: CGRect(x: xOffset, y: y - 16, width: columns[4].1 - 6, height: 16), attributes: subtotalLabelAttrs, alignment: .right)
            }
            xOffset += columns[4].1

            // Qty subtotal (in unit price column)
            drawText("\(Int(destTotalQty)) items", in: CGRect(x: xOffset, y: y - 16, width: columns[5].1 - 6, height: 16), attributes: subtotalLabelAttrs, alignment: .right)
            xOffset += columns[5].1

            // Value subtotal
            if destTotalValue > 0 {
                let valueStr = currencyFormatter.string(from: NSNumber(value: destTotalValue)) ?? "$0.00"
                drawText(valueStr, in: CGRect(x: xOffset, y: y - 16, width: columns[6].1 - 6, height: 16), attributes: subtotalLabelAttrs, alignment: .right)
            }

            y -= 35

            // Add spacing between destination groups
            if destIndex < sortedDestinations.count - 1 {
                y -= 10
            }
        }

        // Grand totals (only if multiple destinations)
        if sortedDestinations.count > 1 {
            _ = checkPageBreak(neededHeight: 50)

            fillRect(CGRect(x: margin, y: y - 30, width: contentWidth, height: 34), color: brandColor.withAlphaComponent(0.15))

            let grandTotalAttrs: [NSAttributedString.Key: Any] = [
                .font: MTFont.systemFont(ofSize: 12, weight: .bold),
                .foregroundColor: MTColor.black
            ]

            drawText("GRAND TOTAL:", at: CGPoint(x: margin + 10, y: y - 20), attributes: grandTotalAttrs)

            var gtX = pageSize.width - margin - 200

            // Weight
            if grandTotalWeight > 0 {
                let weightStr = weightFormatter.string(from: NSNumber(value: grandTotalWeight)) ?? "0"
                drawText("\(weightStr) lb", at: CGPoint(x: gtX, y: y - 20), attributes: grandTotalAttrs)
            }
            gtX += 70

            // Items
            drawText("\(Int(grandTotalQty)) items", at: CGPoint(x: gtX, y: y - 20), attributes: grandTotalAttrs)
            gtX += 60

            // Value
            if grandTotalValue > 0 {
                let valueStr = currencyFormatter.string(from: NSNumber(value: grandTotalValue)) ?? "$0.00"
                drawText(valueStr, in: CGRect(x: gtX, y: y - 20, width: 70, height: 18), attributes: grandTotalAttrs, alignment: .right)
            }

            y -= 50
        }

        // Signatures section
        if y > 150 {
            strokeLine(from: CGPoint(x: margin, y: y), to: CGPoint(x: pageSize.width - margin, y: y), color: MTColor(white: 0.8, alpha: 1.0), width: 0.5)
            y -= 25

            let sigLabelAttrs: [NSAttributedString.Key: Any] = [
                .font: smallFont,
                .foregroundColor: MTColor.gray
            ]

            // Shipped by
            drawText("Shipped By:", at: CGPoint(x: margin, y: y), attributes: sigLabelAttrs)
            strokeLine(from: CGPoint(x: margin + 60, y: y - 3), to: CGPoint(x: margin + 200, y: y - 3), color: MTColor.gray, width: 0.5)

            // Received by
            drawText("Received By:", at: CGPoint(x: pageSize.width / 2, y: y), attributes: sigLabelAttrs)
            strokeLine(from: CGPoint(x: pageSize.width / 2 + 65, y: y - 3), to: CGPoint(x: pageSize.width - margin, y: y - 3), color: MTColor.gray, width: 0.5)

            y -= 30

            // Date lines
            drawText("Date:", at: CGPoint(x: margin, y: y), attributes: sigLabelAttrs)
            strokeLine(from: CGPoint(x: margin + 35, y: y - 3), to: CGPoint(x: margin + 120, y: y - 3), color: MTColor.gray, width: 0.5)

            drawText("Date:", at: CGPoint(x: pageSize.width / 2, y: y), attributes: sigLabelAttrs)
            strokeLine(from: CGPoint(x: pageSize.width / 2 + 35, y: y - 3), to: CGPoint(x: pageSize.width / 2 + 120, y: y - 3), color: MTColor.gray, width: 0.5)
        }

        endPage()
        ctx.closePDF()

        return data as Data
    }
}
