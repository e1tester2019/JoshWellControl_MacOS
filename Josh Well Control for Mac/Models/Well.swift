//
//  Well.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-07.
//

import Foundation
import SwiftData
import PDFKit
#if canImport(AppKit)
import AppKit
#endif

@Model
final class Well {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = "New Well"
    var uwi: String? = nil
    var afeNumber: String? = nil
    var requisitioner: String? = nil
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    @Relationship(deleteRule: .cascade) var projects: [ProjectState] = []
    @Relationship(deleteRule: .cascade) var transfers: [MaterialTransfer] = []
    @Relationship(deleteRule: .cascade) var rentals: [RentalItem] = []

    init(name: String = "New Well", uwi: String? = nil, afeNumber: String? = nil, requisitioner: String? = nil) {
        self.name = name
        self.uwi = uwi
        self.afeNumber = afeNumber
        self.requisitioner = requisitioner
    }
}

extension Well {
    func createTransfer(number: Int? = nil, context: ModelContext) -> MaterialTransfer {
        let transferNumber = number ?? ((transfers.map { $0.number }.max() ?? 0) + 1)
        let transfer = MaterialTransfer(number: transferNumber)
        transfer.well = self
        transfers.append(transfer)
        context.insert(transfer)
        return transfer
    }

    func generateTransferPDF(_ transfer: MaterialTransfer, pageSize: CGSize = CGSize(width: 612, height: 792)) -> Data? {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)

        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        ctx.beginPDFPage(nil)

        // Setup attributes for drawing text
        let titleFont = NSFont.systemFont(ofSize: 18, weight: .semibold)
        let headerFont = NSFont.systemFont(ofSize: 14, weight: .medium)
        let regularFont = NSFont.systemFont(ofSize: 12)
        let boldFont = NSFont.systemFont(ofSize: 12, weight: .bold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.black
        ]
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: headerFont,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.black
        ]
        let regularAttrs: [NSAttributedString.Key: Any] = [
            .font: regularFont,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.black
        ]
        let boldAttrs: [NSAttributedString.Key: Any] = [
            .font: boldFont,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.black
        ]

        // Drawing origin top-left corner, flip coordinate system
        ctx.translateBy(x: 0, y: pageSize.height)
        ctx.scaleBy(x: 1, y: -1)

        let margin: CGFloat = 40
        let contentWidth = pageSize.width - 2 * margin
        var y: CGFloat = margin

        // Helper function to draw attributed text with explicit black color and return height consumed
        func drawText(_ text: String, at point: CGPoint, attrs: [NSAttributedString.Key: Any], width: CGFloat, height: CGFloat) -> CGFloat {
            var a = attrs
            if a[.foregroundColor] == nil { a[.foregroundColor] = NSColor.black }
            let nsText = NSAttributedString(string: text, attributes: a)
            let rect = CGRect(x: point.x, y: point.y, width: width, height: height)
            nsText.draw(in: rect)
            return height
        }

        // Title
        let titleH: CGFloat = 22
        let titlePoint = CGPoint(x: margin, y: y)
        y += drawText("Material Transfer Report", at: titlePoint, attrs: titleAttrs, width: contentWidth, height: titleH) + 12

        // Well details
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none

        var wellDetailsLines: [String] = []
        wellDetailsLines.append("Well Name: \(name)")
        if let uwi = uwi {
            wellDetailsLines.append("UWI: \(uwi)")
        }
        if let afe = afeNumber {
            wellDetailsLines.append("AFE Number: \(afe)")
        }
        // Attempt to get province/country from projects if any have these properties
        // As ProjectState details are unknown, skip province/country fields
        // If known, could extract here

        for line in wellDetailsLines {
            y += drawText(line, at: CGPoint(x: margin, y: y), attrs: regularAttrs, width: contentWidth, height: 16)
        }

        y += 10

        // Transfer number and date
        y += drawText("Transfer Number: \(transfer.number)", at: CGPoint(x: margin, y: y), attrs: regularAttrs, width: contentWidth, height: 16)
        let transferDateText = "Date: \(df.string(from: transfer.date))"
        y += drawText(transferDateText, at: CGPoint(x: margin, y: y), attrs: regularAttrs, width: contentWidth, height: 16)
        y += 8

        // Table header
        let columns = [
            ("Quantity", 50),
            ("Description", 150),
            ("Account Code", 80),
            ("Condition", 70),
            ("$/Unit", 60),
            ("To Loc/AFE/Vendor", 110),
            ("Transported By Tk#", 90),
            ("Total Value", 70)
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
                .foregroundColor: NSColor.black
            ]
            NSString(string: title).draw(in: rect, withAttributes: headerAttr)
            xOffset += CGFloat(width)
        }
        y += headerHeight + 6

        // Draw header bottom line
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: margin, y: y))
        ctx.addLine(to: CGPoint(x: pageSize.width - margin, y: y))
        ctx.strokePath()

        // Draw rows
        let rowHeight: CGFloat = 20
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .currency
        numberFormatter.currencySymbol = "$"
        numberFormatter.maximumFractionDigits = 2

        for item in transfer.items {
            if y + rowHeight > pageSize.height - margin {
                ctx.endPDFPage()
                ctx.beginPDFPage(nil)
                ctx.translateBy(x: 0, y: pageSize.height)
                ctx.scaleBy(x: 1, y: -1)
                y = margin
            }

            xOffset = margin

            // Quantity (centered)
            let qtyRect = CGRect(x: xOffset, y: y, width: CGFloat(columns[0].1), height: rowHeight)
            let qtyAttr = NSMutableParagraphStyle()
            qtyAttr.alignment = .center
            let qtyAttrs: [NSAttributedString.Key: Any] = [
                .font: regularFont,
                .paragraphStyle: qtyAttr,
                .foregroundColor: NSColor.black
            ]
            NSString(string: "\(item.quantity)").draw(in: qtyRect, withAttributes: qtyAttrs)
            xOffset += CGFloat(columns[0].1)

            // Description (left)
            let descRect = CGRect(x: xOffset + 2, y: y, width: CGFloat(columns[1].1), height: rowHeight)
            NSString(string: item.descriptionText).draw(in: descRect, withAttributes: regularAttrs)
            xOffset += CGFloat(columns[1].1)

            // Account Code (center)
            let accRect = CGRect(x: xOffset, y: y, width: CGFloat(columns[2].1), height: rowHeight)
            let accAttr = NSMutableParagraphStyle()
            accAttr.alignment = .center
            let accAttrs: [NSAttributedString.Key: Any] = [
                .font: regularFont,
                .paragraphStyle: accAttr,
                .foregroundColor: NSColor.black
            ]
            NSString(string: item.accountCode ?? "").draw(in: accRect, withAttributes: accAttrs)
            xOffset += CGFloat(columns[2].1)

            // Condition (center)
            let condRect = CGRect(x: xOffset, y: y, width: CGFloat(columns[3].1), height: rowHeight)
            let condAttr = NSMutableParagraphStyle()
            condAttr.alignment = .center
            let condAttrs: [NSAttributedString.Key: Any] = [
                .font: regularFont,
                .paragraphStyle: condAttr,
                .foregroundColor: NSColor.black
            ]
            NSString(string: item.conditionCode ?? "").draw(in: condRect, withAttributes: condAttrs)
            xOffset += CGFloat(columns[3].1)

            // $/Unit (right aligned)
            let unitRect = CGRect(x: xOffset, y: y, width: CGFloat(columns[4].1), height: rowHeight)
            let unitAttr = NSMutableParagraphStyle()
            unitAttr.alignment = .right
            let unitAttrs: [NSAttributedString.Key: Any] = [
                .font: regularFont,
                .paragraphStyle: unitAttr,
                .foregroundColor: NSColor.black
            ]
            let unit = item.unitPrice ?? 0
            let unitString = numberFormatter.string(from: NSNumber(value: unit)) ?? "$0.00"
            NSString(string: unitString).draw(in: unitRect, withAttributes: unitAttrs)
            xOffset += CGFloat(columns[4].1)

            // To Loc/AFE/Vendor (left)
            let toLocRect = CGRect(x: xOffset + 2, y: y, width: CGFloat(columns[5].1), height: rowHeight)
            NSString(string: item.vendorOrTo ?? "").draw(in: toLocRect, withAttributes: regularAttrs)
            xOffset += CGFloat(columns[5].1)

            // Transported By Tk# (center)
            let tkRect = CGRect(x: xOffset, y: y, width: CGFloat(columns[6].1), height: rowHeight)
            let tkAttr = NSMutableParagraphStyle()
            tkAttr.alignment = .center
            let tkAttrs: [NSAttributedString.Key: Any] = [
                .font: regularFont,
                .paragraphStyle: tkAttr,
                .foregroundColor: NSColor.black
            ]
            NSString(string: item.transportedBy ?? transfer.transportedBy ?? "").draw(in: tkRect, withAttributes: tkAttrs)
            xOffset += CGFloat(columns[6].1)

            // Total Value (right aligned)
            let totalRect = CGRect(x: xOffset, y: y, width: CGFloat(columns[7].1), height: rowHeight)
            let totalAttr = NSMutableParagraphStyle()
            totalAttr.alignment = .right
            let totalAttrs: [NSAttributedString.Key: Any] = [
                .font: regularFont,
                .paragraphStyle: totalAttr,
                .foregroundColor: NSColor.black
            ]
            let totalValue = unit * Double(item.quantity)
            let totalString = numberFormatter.string(from: NSNumber(value: totalValue)) ?? "$0.00"
            NSString(string: totalString).draw(in: totalRect, withAttributes: totalAttrs)

            y += rowHeight
        }

        // Draw vertical grid lines
        ctx.setStrokeColor(NSColor.black.cgColor)
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

        // Draw horizontal grid lines
        ctx.setLineWidth(0.5)
        var yGrid: CGFloat = margin
        while yGrid <= y {
            ctx.move(to: CGPoint(x: margin, y: yGrid))
            ctx.addLine(to: CGPoint(x: pageSize.width - margin, y: yGrid))
            yGrid += rowHeight
        }
        ctx.strokePath()

        ctx.endPDFPage()
        ctx.closePDF()

        return data as Data
    }
}

