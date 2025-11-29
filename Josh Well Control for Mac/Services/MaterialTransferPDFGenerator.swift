//
//  MaterialTransferPDFGenerator.swift
//  Josh Well Control
//
//  Cross-platform PDF generation for Material Transfer reports
//

import Foundation
import SwiftUI
import CoreGraphics

#if os(macOS)
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#elseif os(iOS)
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#endif

/// Service for generating Material Transfer PDF reports in a cross-platform way
class MaterialTransferPDFGenerator {
    static let shared = MaterialTransferPDFGenerator()

    private init() {}

    func generatePDF(for transfer: MaterialTransfer, well: Well, pageSize: CGSize = CGSize(width: 612, height: 792)) -> Data? {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)

        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        ctx.beginPDFPage(nil)

        // Setup fonts
        let titleFont = PlatformFont.systemFont(ofSize: 18, weight: .semibold)
        let headerFont = PlatformFont.systemFont(ofSize: 14, weight: .medium)
        let regularFont = PlatformFont.systemFont(ofSize: 12)
        let boldFont = PlatformFont.systemFont(ofSize: 12, weight: .bold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: PlatformColor.black
        ]
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: headerFont,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: PlatformColor.black
        ]
        let regularAttrs: [NSAttributedString.Key: Any] = [
            .font: regularFont,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: PlatformColor.black
        ]
        let boldAttrs: [NSAttributedString.Key: Any] = [
            .font: boldFont,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: PlatformColor.black
        ]

        // Flip coordinate system for top-left origin
        ctx.translateBy(x: 0, y: pageSize.height)
        ctx.scaleBy(x: 1, y: -1)

        let margin: CGFloat = 40
        let contentWidth = pageSize.width - 2 * margin
        var y: CGFloat = margin

        // Helper to draw text
        func drawText(_ text: String, at point: CGPoint, attrs: [NSAttributedString.Key: Any], width: CGFloat, height: CGFloat) -> CGFloat {
            var a = attrs
            if a[.foregroundColor] == nil { a[.foregroundColor] = PlatformColor.black }
            let nsText = NSAttributedString(string: text, attributes: a)
            let rect = CGRect(x: point.x, y: point.y, width: width, height: height)
            nsText.draw(in: rect)
            return height
        }

        // Title
        let titleH: CGFloat = 22
        let titlePoint = CGPoint(x: margin, y: y)
        y += drawText("Material Transfer Report", at: titlePoint, attrs: titleAttrs, width: contentWidth, height: titleH) + 12

        // Transfer number
        let transferNumH: CGFloat = 18
        let transferNumPoint = CGPoint(x: margin, y: y)
        y += drawText("Transfer #\(transfer.number)", at: transferNumPoint, attrs: headerAttrs, width: contentWidth, height: transferNumH) + 10

        // Well info section
        var wellInfo: [(String, String)] = []
        if !well.name.isEmpty { wellInfo.append(("Well:", well.name)) }
        if let uwi = well.uwi, !uwi.isEmpty { wellInfo.append(("UWI:", uwi)) }
        if let afe = well.afeNumber, !afe.isEmpty { wellInfo.append(("AFE:", afe)) }
        if let req = well.requisitioner, !req.isEmpty { wellInfo.append(("Requisitioner:", req)) }

        for (label, value) in wellInfo {
            let lineH: CGFloat = 16
            let labelW: CGFloat = 120
            let labelPoint = CGPoint(x: margin, y: y)
            _ = drawText(label, at: labelPoint, attrs: boldAttrs, width: labelW, height: lineH)
            let valuePoint = CGPoint(x: margin + labelW, y: y)
            y += drawText(value, at: valuePoint, attrs: regularAttrs, width: contentWidth - labelW, height: lineH) + 2
        }
        y += 8

        // Transfer info
        let dateStr = transfer.createdAt.formatted(date: .abbreviated, time: .omitted)
        var transferInfo: [(String, String)] = [
            ("Date:", dateStr),
            ("Direction:", transfer.isShippingOut ? "Shipping Out" : "Receiving"),
            ("Receiver Address:", transfer.receiverAddress ?? "N/A")
        ]
        if let shipped = transfer.shippedDate {
            transferInfo.append(("Shipped:", shipped.formatted(date: .abbreviated, time: .omitted)))
        }
        if let tb = transfer.transportedBy, !tb.isEmpty {
            transferInfo.append(("Transported By:", tb))
        }

        for (label, value) in transferInfo {
            let lineH: CGFloat = 16
            let labelW: CGFloat = 140
            let labelPoint = CGPoint(x: margin, y: y)
            _ = drawText(label, at: labelPoint, attrs: boldAttrs, width: labelW, height: lineH)
            let valuePoint = CGPoint(x: margin + labelW, y: y)
            y += drawText(value, at: valuePoint, attrs: regularAttrs, width: contentWidth - labelW, height: lineH) + 2
        }
        y += 12

        // Table header
        let columns: [(String, Int)] = [
            ("Qty", 40),
            ("Description", 160),
            ("Acct", 60),
            ("Cond", 50),
            ("$/Unit", 65),
            ("To Loc/AFE/Vendor", 100),
            ("Tk#", 50),
            ("Total", 65)
        ]

        var xOffset: CGFloat = margin
        let headerHeight: CGFloat = 18

        for (title, width) in columns {
            let rect = CGRect(x: xOffset, y: y, width: CGFloat(width), height: headerHeight)
            let attr = NSMutableParagraphStyle()
            attr.alignment = .center
            let headerAttr: [NSAttributedString.Key: Any] = [
                .font: boldFont,
                .paragraphStyle: attr,
                .foregroundColor: PlatformColor.black
            ]
            NSString(string: title).draw(in: rect, withAttributes: headerAttr)
            xOffset += CGFloat(width)
        }
        y += headerHeight + 6

        // Header line
        ctx.setStrokeColor(PlatformColor.black.cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: margin, y: y))
        ctx.addLine(to: CGPoint(x: pageSize.width - margin, y: y))
        ctx.strokePath()

        // Table rows
        let rowHeight: CGFloat = 20
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .currency
        numberFormatter.currencySymbol = "$"

        let sortedItems = transfer.items.sorted { $0.orderIndex < $1.orderIndex }

        for item in sortedItems {
            y += 4
            xOffset = margin

            // Quantity
            let qtyRect = CGRect(x: xOffset, y: y, width: CGFloat(columns[0].1), height: rowHeight)
            let qtyAttr = NSMutableParagraphStyle()
            qtyAttr.alignment = .center
            let qtyAttrs: [NSAttributedString.Key: Any] = [
                .font: regularFont,
                .paragraphStyle: qtyAttr,
                .foregroundColor: PlatformColor.black
            ]
            NSString(string: "\(item.quantity)").draw(in: qtyRect, withAttributes: qtyAttrs)
            xOffset += CGFloat(columns[0].1)

            // Description
            let descRect = CGRect(x: xOffset + 2, y: y, width: CGFloat(columns[1].1), height: rowHeight)
            NSString(string: item.descriptionText).draw(in: descRect, withAttributes: regularAttrs)
            xOffset += CGFloat(columns[1].1)

            // Account Code
            let accRect = CGRect(x: xOffset, y: y, width: CGFloat(columns[2].1), height: rowHeight)
            let accAttr = NSMutableParagraphStyle()
            accAttr.alignment = .center
            let accAttrs: [NSAttributedString.Key: Any] = [
                .font: regularFont,
                .paragraphStyle: accAttr,
                .foregroundColor: PlatformColor.black
            ]
            NSString(string: item.accountCode ?? "").draw(in: accRect, withAttributes: accAttrs)
            xOffset += CGFloat(columns[2].1)

            // Condition
            let condRect = CGRect(x: xOffset, y: y, width: CGFloat(columns[3].1), height: rowHeight)
            let condAttr = NSMutableParagraphStyle()
            condAttr.alignment = .center
            let condAttrs: [NSAttributedString.Key: Any] = [
                .font: regularFont,
                .paragraphStyle: condAttr,
                .foregroundColor: PlatformColor.black
            ]
            NSString(string: item.conditionCode ?? "").draw(in: condRect, withAttributes: condAttrs)
            xOffset += CGFloat(columns[3].1)

            // $/Unit
            let unitRect = CGRect(x: xOffset, y: y, width: CGFloat(columns[4].1), height: rowHeight)
            let unitAttr = NSMutableParagraphStyle()
            unitAttr.alignment = .right
            let unitAttrs: [NSAttributedString.Key: Any] = [
                .font: regularFont,
                .paragraphStyle: unitAttr,
                .foregroundColor: PlatformColor.black
            ]
            let unit = item.unitPrice ?? 0
            let unitString = numberFormatter.string(from: NSNumber(value: unit)) ?? "$0.00"
            NSString(string: unitString).draw(in: unitRect, withAttributes: unitAttrs)
            xOffset += CGFloat(columns[4].1)

            // To Loc/AFE/Vendor
            let toLocRect = CGRect(x: xOffset + 2, y: y, width: CGFloat(columns[5].1), height: rowHeight)
            NSString(string: item.vendorOrTo ?? "").draw(in: toLocRect, withAttributes: regularAttrs)
            xOffset += CGFloat(columns[5].1)

            // Transported By Tk#
            let tkRect = CGRect(x: xOffset, y: y, width: CGFloat(columns[6].1), height: rowHeight)
            let tkAttr = NSMutableParagraphStyle()
            tkAttr.alignment = .center
            let tkAttrs: [NSAttributedString.Key: Any] = [
                .font: regularFont,
                .paragraphStyle: tkAttr,
                .foregroundColor: PlatformColor.black
            ]
            NSString(string: item.transportedBy ?? transfer.transportedBy ?? "").draw(in: tkRect, withAttributes: tkAttrs)
            xOffset += CGFloat(columns[6].1)

            // Total Value
            let totalRect = CGRect(x: xOffset, y: y, width: CGFloat(columns[7].1), height: rowHeight)
            let totalAttr = NSMutableParagraphStyle()
            totalAttr.alignment = .right
            let totalAttrs: [NSAttributedString.Key: Any] = [
                .font: regularFont,
                .paragraphStyle: totalAttr,
                .foregroundColor: PlatformColor.black
            ]
            let totalValue = unit * Double(item.quantity)
            let totalString = numberFormatter.string(from: NSNumber(value: totalValue)) ?? "$0.00"
            NSString(string: totalString).draw(in: totalRect, withAttributes: totalAttrs)

            y += rowHeight
        }

        // Draw vertical grid lines
        ctx.setStrokeColor(PlatformColor.black.cgColor)
        ctx.setLineWidth(0.5)

        var xGrid: CGFloat = margin
        ctx.move(to: CGPoint(x: xGrid, y: margin))
        ctx.addLine(to: CGPoint(x: xGrid, y: y))
        for (_, width) in columns {
            xGrid += CGFloat(width)
            ctx.move(to: CGPoint(x: xGrid, y: margin))
            ctx.addLine(to: CGPoint(x: xGrid, y: y))
        }
        ctx.strokePath()

        ctx.endPDFPage()
        ctx.closePDF()

        return data as Data
    }
}
