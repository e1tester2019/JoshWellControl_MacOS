//
//  RentalReportPDFGenerator.swift
//  Josh Well Control
//
//  Cross-platform PDF generation for Rental/Equipment on location reports
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

/// Service for generating Rental PDF reports in a cross-platform way
class RentalReportPDFGenerator {
    static let shared = RentalReportPDFGenerator()

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

    // MARK: - Well Rentals On Location Report

    func generateWellRentalsReport(for well: Well, rentals: [RentalItem], pageSize: CGSize = CGSize(width: 612, height: 792)) -> Data? {
        let ctx = PDFContext(pageSize: pageSize, brandColor: brandColor, darkBrandColor: darkBrandColor)
        guard ctx.begin() else { return nil }

        let businessInfo = BusinessInfo.shared

        // Header
        ctx.drawHeader(companyName: businessInfo.companyName)
        ctx.drawTitle("RENTALS ON LOCATION")
        ctx.drawSubtitle(well.name, date: Date())

        // Info section
        var infoItems: [(String, String, MTColor?)] = [
            ("WELL", well.name, nil)
        ]
        if let uwi = well.uwi, !uwi.isEmpty {
            infoItems.append(("UWI", uwi, nil))
        }
        if let pad = well.pad {
            infoItems.append(("PAD", pad.name, nil))
        }
        infoItems.append(("ITEMS ON LOCATION", "\(rentals.count)", nil))

        let totalDays = rentals.reduce(0) { $0 + $1.totalDays }
        let totalCost = rentals.reduce(0.0) { $0 + $1.totalCost }
        infoItems.append(("TOTAL DAYS", "\(totalDays)", nil))
        infoItems.append(("TOTAL COST", ctx.currency(totalCost), nil))

        ctx.drawInfoBox(items: infoItems)

        // Table
        let columns: [(String, CGFloat, NSTextAlignment)] = [
            ("ITEM", ctx.contentWidth * 0.28, .left),
            ("SERIAL #", 70, .left),
            ("CATEGORY", 70, .left),
            ("START", 60, .center),
            ("DAYS", 40, .right),
            ("$/DAY", 55, .right),
            ("TOTAL", 65, .right)
        ]

        ctx.drawTableHeader(columns: columns)

        for (index, rental) in rentals.enumerated() {
            ctx.checkPageBreakAndRedrawHeader(columns: columns)

            var rowData: [(String, NSTextAlignment)] = []
            rowData.append((rental.displayName, .left))
            rowData.append((rental.serialNumber ?? "—", .left))
            rowData.append((rental.category?.name ?? "—", .left))
            rowData.append((rental.startDate?.formatted(date: .abbreviated, time: .omitted) ?? "—", .center))
            rowData.append(("\(rental.totalDays)", .right))
            rowData.append((ctx.currency(rental.costPerDay), .right))
            rowData.append((ctx.currency(rental.totalCost), .right))

            ctx.drawTableRow(data: rowData, columns: columns, isAlternate: index % 2 == 0)
        }

        // Totals row
        ctx.drawTotalsRow(label: "TOTAL:", values: [
            (ctx.currency(totalCost), 65)
        ], extraInfo: "\(rentals.count) items • \(totalDays) days")

        return ctx.end()
    }

    // MARK: - Pad Rentals On Location Report

    func generatePadRentalsReport(for pad: Pad, rentals: [RentalItem], pageSize: CGSize = CGSize(width: 612, height: 792)) -> Data? {
        let ctx = PDFContext(pageSize: pageSize, brandColor: brandColor, darkBrandColor: darkBrandColor)
        guard ctx.begin() else { return nil }

        let businessInfo = BusinessInfo.shared

        // Header
        ctx.drawHeader(companyName: businessInfo.companyName)
        ctx.drawTitle("PAD RENTALS ON LOCATION")
        ctx.drawSubtitle(pad.name, date: Date())

        // Info section
        var infoItems: [(String, String, MTColor?)] = [
            ("PAD", pad.name, nil)
        ]
        if !pad.surfaceLocation.isEmpty {
            infoItems.append(("SURFACE", pad.surfaceLocation, nil))
        }

        let wellCount = Set(rentals.compactMap { $0.well?.id }).count
        infoItems.append(("WELLS", "\(wellCount)", nil))
        infoItems.append(("ITEMS", "\(rentals.count)", nil))

        let totalDays = rentals.reduce(0) { $0 + $1.totalDays }
        let totalCost = rentals.reduce(0.0) { $0 + $1.totalCost }
        infoItems.append(("TOTAL DAYS", "\(totalDays)", nil))
        infoItems.append(("TOTAL COST", ctx.currency(totalCost), nil))

        ctx.drawInfoBox(items: infoItems)

        // Group by well
        var rentalsByWell: [UUID: (well: Well, items: [RentalItem])] = [:]
        var wellOrder: [UUID] = []

        for rental in rentals {
            guard let well = rental.well else { continue }
            if rentalsByWell[well.id] == nil {
                wellOrder.append(well.id)
                rentalsByWell[well.id] = (well: well, items: [])
            }
            rentalsByWell[well.id]?.items.append(rental)
        }

        let columns: [(String, CGFloat, NSTextAlignment)] = [
            ("ITEM", ctx.contentWidth * 0.28, .left),
            ("SERIAL #", 70, .left),
            ("CATEGORY", 65, .left),
            ("START", 55, .center),
            ("DAYS", 35, .right),
            ("$/DAY", 50, .right),
            ("TOTAL", 60, .right)
        ]

        var grandTotalCost: Double = 0
        var grandTotalDays: Int = 0
        var grandTotalItems: Int = 0

        for (wellIndex, wellId) in wellOrder.enumerated() {
            guard let group = rentalsByWell[wellId] else { continue }

            // Well section header
            ctx.checkPageBreak(neededHeight: 100)
            ctx.drawSectionHeader("WELL: \(group.well.name)")

            ctx.drawTableHeader(columns: columns)

            var wellTotalCost: Double = 0
            var wellTotalDays: Int = 0

            for (index, rental) in group.items.enumerated() {
                ctx.checkPageBreakAndRedrawHeader(columns: columns)

                var rowData: [(String, NSTextAlignment)] = []
                rowData.append((rental.displayName, .left))
                rowData.append((rental.serialNumber ?? "—", .left))
                rowData.append((rental.category?.name ?? "—", .left))
                rowData.append((rental.startDate?.formatted(date: .abbreviated, time: .omitted) ?? "—", .center))
                rowData.append(("\(rental.totalDays)", .right))
                rowData.append((ctx.currency(rental.costPerDay), .right))
                rowData.append((ctx.currency(rental.totalCost), .right))

                ctx.drawTableRow(data: rowData, columns: columns, isAlternate: index % 2 == 0)

                wellTotalCost += rental.totalCost
                wellTotalDays += rental.totalDays
            }

            // Well subtotal
            ctx.drawSubtotalRow(label: "Subtotal - \(group.well.name):", values: [
                (ctx.currency(wellTotalCost), 60)
            ], extraInfo: "\(group.items.count) items • \(wellTotalDays) days")

            grandTotalCost += wellTotalCost
            grandTotalDays += wellTotalDays
            grandTotalItems += group.items.count

            if wellIndex < wellOrder.count - 1 {
                ctx.addSpacing(15)
            }
        }

        // Grand totals
        if wellOrder.count > 1 {
            ctx.drawGrandTotalRow(label: "GRAND TOTAL:", values: [
                (ctx.currency(grandTotalCost), 70)
            ], extraInfo: "\(grandTotalItems) items • \(grandTotalDays) days")
        }

        return ctx.end()
    }

    // MARK: - Equipment On Location Report

    func generateEquipmentReport(equipment: [RentalEquipment], pageSize: CGSize = CGSize(width: 612, height: 792)) -> Data? {
        let ctx = PDFContext(pageSize: pageSize, brandColor: brandColor, darkBrandColor: darkBrandColor)
        guard ctx.begin() else { return nil }

        let businessInfo = BusinessInfo.shared

        // Header
        ctx.drawHeader(companyName: businessInfo.companyName)
        ctx.drawTitle("EQUIPMENT ON LOCATION")
        ctx.drawSubtitle("Equipment Registry Report", date: Date())

        let inUseEquipment = equipment.filter { $0.locationStatus == .inUse }
        let onLocationEquipment = equipment.filter { $0.locationStatus == .onLocation }

        // Info section
        let infoItems: [(String, String, MTColor?)] = [
            ("TOTAL EQUIPMENT", "\(equipment.count)", nil),
            ("IN USE", "\(inUseEquipment.count)", MTColor.systemGreen),
            ("ON LOCATION", "\(onLocationEquipment.count)", MTColor.systemBlue),
            ("REPORT DATE", Date().formatted(date: .abbreviated, time: .omitted), nil)
        ]

        ctx.drawInfoBox(items: infoItems)

        // Group equipment by category, then by vendor
        func groupedEquipment(_ items: [RentalEquipment]) -> [(category: String, vendors: [(vendor: String, items: [RentalEquipment])])] {
            // Group by category
            var byCategory: [String: [RentalEquipment]] = [:]
            var categoryOrder: [String] = []
            for eq in items {
                let catName = eq.category?.name ?? "Uncategorized"
                if byCategory[catName] == nil {
                    categoryOrder.append(catName)
                    byCategory[catName] = []
                }
                byCategory[catName]?.append(eq)
            }

            // For each category, group by vendor
            var result: [(category: String, vendors: [(vendor: String, items: [RentalEquipment])])] = []
            for catName in categoryOrder.sorted() {
                let catItems = byCategory[catName] ?? []
                var byVendor: [String: [RentalEquipment]] = [:]
                var vendorOrder: [String] = []
                for eq in catItems {
                    let vendorName = eq.vendor?.companyName ?? "Unknown Vendor"
                    if byVendor[vendorName] == nil {
                        vendorOrder.append(vendorName)
                        byVendor[vendorName] = []
                    }
                    byVendor[vendorName]?.append(eq)
                }
                let vendors = vendorOrder.sorted().map { (vendor: $0, items: byVendor[$0] ?? []) }
                result.append((category: catName, vendors: vendors))
            }
            return result
        }

        let columns: [(String, CGFloat, NSTextAlignment)] = [
            ("EQUIPMENT", ctx.contentWidth * 0.45, .left),
            ("SERIAL #", 120, .left),
            ("DAYS", 50, .right)
        ]

        // In Use section
        if !inUseEquipment.isEmpty {
            ctx.checkPageBreak(neededHeight: 100)
            ctx.drawSectionHeader("IN USE (\(inUseEquipment.count))")

            let grouped = groupedEquipment(inUseEquipment)
            for catGroup in grouped {
                ctx.checkPageBreak(neededHeight: 80)
                ctx.drawCategoryHeader(catGroup.category)

                for vendorGroup in catGroup.vendors {
                    ctx.checkPageBreak(neededHeight: 60)
                    ctx.drawVendorSubheader(vendorGroup.vendor, itemCount: vendorGroup.items.count)
                    ctx.drawTableHeader(columns: columns)

                    for (index, eq) in vendorGroup.items.enumerated() {
                        ctx.checkPageBreakAndRedrawHeader(columns: columns)

                        var rowData: [(String, NSTextAlignment)] = []
                        rowData.append((eq.name, .left))
                        rowData.append((eq.serialNumber.isEmpty ? "—" : eq.serialNumber, .left))
                        rowData.append(("\(eq.totalDaysUsed)", .right))

                        ctx.drawTableRow(data: rowData, columns: columns, isAlternate: index % 2 == 0)
                    }
                    ctx.addSpacing(10)
                }
            }
            ctx.addSpacing(15)
        }

        // On Location section
        if !onLocationEquipment.isEmpty {
            ctx.checkPageBreak(neededHeight: 100)
            ctx.drawSectionHeader("ON LOCATION (\(onLocationEquipment.count))")

            let grouped = groupedEquipment(onLocationEquipment)
            for catGroup in grouped {
                ctx.checkPageBreak(neededHeight: 80)
                ctx.drawCategoryHeader(catGroup.category)

                for vendorGroup in catGroup.vendors {
                    ctx.checkPageBreak(neededHeight: 60)
                    ctx.drawVendorSubheader(vendorGroup.vendor, itemCount: vendorGroup.items.count)
                    ctx.drawTableHeader(columns: columns)

                    for (index, eq) in vendorGroup.items.enumerated() {
                        ctx.checkPageBreakAndRedrawHeader(columns: columns)

                        var rowData: [(String, NSTextAlignment)] = []
                        rowData.append((eq.name, .left))
                        rowData.append((eq.serialNumber.isEmpty ? "—" : eq.serialNumber, .left))
                        rowData.append(("\(eq.totalDaysUsed)", .right))

                        ctx.drawTableRow(data: rowData, columns: columns, isAlternate: index % 2 == 0)
                    }
                    ctx.addSpacing(10)
                }
            }
        }

        return ctx.end()
    }
}

// MARK: - PDF Drawing Context Helper

#if os(macOS)
private typealias MTFont = NSFont
private typealias MTColor = NSColor
#elseif os(iOS)
private typealias MTFont = UIFont
private typealias MTColor = UIColor
#endif

private class PDFContext {
    let pageSize: CGSize
    let margin: CGFloat = 40
    let pageBottom: CGFloat = 60
    let brandColor: MTColor
    let darkBrandColor: MTColor

    var contentWidth: CGFloat { pageSize.width - 2 * margin }
    var y: CGFloat = 0
    var currentPage = 1
    var ctx: CGContext?
    var data: NSMutableData?
    var lastColumns: [(String, CGFloat, NSTextAlignment)]?

    // Fonts
    let headerFont: MTFont
    let titleFont: MTFont
    let subtitleFont: MTFont
    let labelFont: MTFont
    let valueFont: MTFont
    let smallFont: MTFont
    let tableHeaderFont: MTFont
    let boldFont: MTFont

    init(pageSize: CGSize, brandColor: MTColor, darkBrandColor: MTColor) {
        self.pageSize = pageSize
        self.brandColor = brandColor
        self.darkBrandColor = darkBrandColor

        headerFont = MTFont.systemFont(ofSize: 16, weight: .bold)
        titleFont = MTFont.systemFont(ofSize: 24, weight: .light)
        subtitleFont = MTFont.systemFont(ofSize: 14, weight: .medium)
        labelFont = MTFont.systemFont(ofSize: 10, weight: .semibold)
        valueFont = MTFont.systemFont(ofSize: 10, weight: .regular)
        smallFont = MTFont.systemFont(ofSize: 9, weight: .regular)
        tableHeaderFont = MTFont.systemFont(ofSize: 9, weight: .semibold)
        boldFont = MTFont.systemFont(ofSize: 10, weight: .bold)
    }

    func begin() -> Bool {
        data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)

        guard let consumer = CGDataConsumer(data: data! as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return false
        }

        ctx = context
        y = pageSize.height
        currentPage = 1
        startPage()
        return true
    }

    func end() -> Data? {
        endPage()
        ctx?.closePDF()
        return data as Data?
    }

    func startPage() {
        ctx?.beginPDFPage(nil)
    }

    func endPage() {
        let pageNumAttrs: [NSAttributedString.Key: Any] = [
            .font: MTFont.systemFont(ofSize: 10),
            .foregroundColor: MTColor.gray
        ]
        drawText("\(currentPage)", in: CGRect(x: 0, y: 20, width: pageSize.width, height: 20), attributes: pageNumAttrs, alignment: .center)
        ctx?.endPDFPage()
    }

    func checkPageBreak(neededHeight: CGFloat) {
        if y - neededHeight < pageBottom {
            endPage()
            currentPage += 1
            startPage()
            y = pageSize.height - 40
        }
    }

    func checkPageBreakAndRedrawHeader(columns: [(String, CGFloat, NSTextAlignment)]) {
        if y - 40 < pageBottom {
            endPage()
            currentPage += 1
            startPage()
            y = pageSize.height - 40
            drawTableHeader(columns: columns)
        }
    }

    func addSpacing(_ amount: CGFloat) {
        y -= amount
    }

    // MARK: - Drawing Helpers

    func fillRect(_ rect: CGRect, color: MTColor) {
        ctx?.setFillColor(color.cgColor)
        ctx?.fill(rect)
    }

    func drawText(_ text: String, at point: CGPoint, attributes: [NSAttributedString.Key: Any]) {
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        ctx?.textPosition = CGPoint(x: point.x, y: point.y)
        CTLineDraw(line, ctx!)
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

        ctx?.textPosition = CGPoint(x: x, y: rect.minY)
        CTLineDraw(line, ctx!)
    }

    func strokeLine(from: CGPoint, to: CGPoint, color: MTColor, width: CGFloat) {
        ctx?.setStrokeColor(color.cgColor)
        ctx?.setLineWidth(width)
        ctx?.setLineDash(phase: 0, lengths: [])
        ctx?.move(to: from)
        ctx?.addLine(to: to)
        ctx?.strokePath()
    }

    func currency(_ v: Double) -> String {
        String(format: "$%.2f", v)
    }

    // MARK: - High-Level Drawing

    func drawHeader(companyName: String) {
        fillRect(CGRect(x: 0, y: pageSize.height - 50, width: pageSize.width, height: 50), color: brandColor)
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: headerFont,
            .foregroundColor: MTColor.white
        ]
        drawText(companyName, at: CGPoint(x: margin, y: pageSize.height - 34), attributes: headerAttrs)
        fillRect(CGRect(x: 0, y: pageSize.height - 54, width: pageSize.width, height: 4), color: darkBrandColor)
        y = pageSize.height - 75
    }

    func drawTitle(_ title: String) {
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: MTColor.darkGray
        ]
        drawText(title, at: CGPoint(x: margin, y: y), attributes: titleAttrs)
        y -= 30
    }

    func drawSubtitle(_ subtitle: String, date: Date) {
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: subtitleFont,
            .foregroundColor: brandColor
        ]
        drawText(subtitle, at: CGPoint(x: margin, y: y), attributes: subtitleAttrs)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy"
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: MTColor.darkGray
        ]
        drawText("Date: \(dateFormatter.string(from: date))", in: CGRect(x: pageSize.width - margin - 150, y: y, width: 150, height: 16), attributes: dateAttrs, alignment: .right)
        y -= 35
    }

    func drawInfoBox(items: [(String, String, MTColor?)]) {
        let infoBoxHeight: CGFloat = 70
        fillRect(CGRect(x: margin, y: y - infoBoxHeight, width: contentWidth, height: infoBoxHeight), color: MTColor(white: 0.97, alpha: 1.0))

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: MTColor.gray
        ]

        var infoY = y - 15
        let colWidth = contentWidth / 3
        var colIndex = 0
        var rowY = infoY

        for (label, value, valueColor) in items {
            let x = margin + 12 + CGFloat(colIndex) * colWidth

            drawText(label, at: CGPoint(x: x, y: rowY), attributes: labelAttrs)

            let valueAttrs: [NSAttributedString.Key: Any] = [
                .font: valueFont,
                .foregroundColor: valueColor ?? MTColor.black
            ]
            drawText(value, at: CGPoint(x: x, y: rowY - 14), attributes: valueAttrs)

            colIndex += 1
            if colIndex >= 3 {
                colIndex = 0
                rowY -= 32
            }
        }

        y -= infoBoxHeight + 20
    }

    func drawSectionHeader(_ title: String) {
        fillRect(CGRect(x: margin, y: y - 22, width: contentWidth, height: 26), color: brandColor.withAlphaComponent(0.1))
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: MTFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: brandColor
        ]
        drawText(title, at: CGPoint(x: margin + 10, y: y - 15), attributes: headerAttrs)
        y -= 30
    }

    func drawCategoryHeader(_ title: String) {
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: MTFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: MTColor.black
        ]
        drawText(title, at: CGPoint(x: margin, y: y - 12), attributes: headerAttrs)
        y -= 20
    }

    func drawVendorSubheader(_ vendor: String, itemCount: Int) {
        let vendorAttrs: [NSAttributedString.Key: Any] = [
            .font: MTFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: MTColor.darkGray
        ]
        drawText("\(vendor) (\(itemCount))", at: CGPoint(x: margin + 10, y: y - 10), attributes: vendorAttrs)
        y -= 18
    }

    func drawTableHeader(columns: [(String, CGFloat, NSTextAlignment)]) {
        lastColumns = columns
        fillRect(CGRect(x: margin, y: y - 22, width: contentWidth, height: 26), color: brandColor)

        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: tableHeaderFont,
            .foregroundColor: MTColor.white
        ]

        var xOffset = margin + 5
        for (title, width, alignment) in columns {
            drawText(title, in: CGRect(x: xOffset, y: y - 16, width: width - 6, height: 16), attributes: headerAttrs, alignment: alignment)
            xOffset += width
        }

        y -= 28
    }

    func drawTableRow(data: [(String, NSTextAlignment)], columns: [(String, CGFloat, NSTextAlignment)], isAlternate: Bool) {
        let rowHeight: CGFloat = 28
        let bgColor = isAlternate ? MTColor(white: 0.98, alpha: 1.0) : MTColor.white
        fillRect(CGRect(x: margin, y: y - rowHeight, width: contentWidth, height: rowHeight), color: bgColor)

        let descAttrs: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: MTColor.black
        ]

        var xOffset = margin + 5
        for (index, (text, alignment)) in data.enumerated() {
            guard index < columns.count else { break }
            let width = columns[index].1
            drawText(text, in: CGRect(x: xOffset, y: y - 12, width: width - 6, height: 16), attributes: descAttrs, alignment: alignment)
            xOffset += width
        }

        strokeLine(from: CGPoint(x: margin, y: y - rowHeight), to: CGPoint(x: pageSize.width - margin, y: y - rowHeight), color: MTColor(white: 0.85, alpha: 1.0), width: 0.5)
        y -= rowHeight
    }

    func drawSubtotalRow(label: String, values: [(String, CGFloat)], extraInfo: String) {
        y -= 5
        fillRect(CGRect(x: margin, y: y - 24, width: contentWidth, height: 28), color: MTColor(white: 0.93, alpha: 1.0))

        let subtotalAttrs: [NSAttributedString.Key: Any] = [
            .font: MTFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: MTColor.darkGray
        ]

        drawText(label, at: CGPoint(x: margin + 10, y: y - 16), attributes: subtotalAttrs)
        drawText(extraInfo, at: CGPoint(x: margin + 200, y: y - 16), attributes: subtotalAttrs)

        var valueX = pageSize.width - margin - 10
        for (value, width) in values.reversed() {
            drawText(value, in: CGRect(x: valueX - width, y: y - 16, width: width, height: 16), attributes: subtotalAttrs, alignment: .right)
            valueX -= width + 10
        }

        y -= 35
    }

    func drawTotalsRow(label: String, values: [(String, CGFloat)], extraInfo: String) {
        y -= 5
        fillRect(CGRect(x: margin, y: y - 24, width: contentWidth, height: 28), color: MTColor(white: 0.93, alpha: 1.0))

        let totalAttrs: [NSAttributedString.Key: Any] = [
            .font: boldFont,
            .foregroundColor: MTColor.black
        ]

        drawText(label, at: CGPoint(x: margin + 10, y: y - 16), attributes: totalAttrs)
        drawText(extraInfo, at: CGPoint(x: margin + 80, y: y - 16), attributes: totalAttrs)

        var valueX = pageSize.width - margin - 10
        for (value, width) in values.reversed() {
            drawText(value, in: CGRect(x: valueX - width, y: y - 16, width: width, height: 16), attributes: totalAttrs, alignment: .right)
            valueX -= width + 10
        }

        y -= 35
    }

    func drawGrandTotalRow(label: String, values: [(String, CGFloat)], extraInfo: String) {
        checkPageBreak(neededHeight: 50)

        fillRect(CGRect(x: margin, y: y - 30, width: contentWidth, height: 34), color: brandColor.withAlphaComponent(0.15))

        let grandTotalAttrs: [NSAttributedString.Key: Any] = [
            .font: MTFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: MTColor.black
        ]

        drawText(label, at: CGPoint(x: margin + 10, y: y - 20), attributes: grandTotalAttrs)
        drawText(extraInfo, at: CGPoint(x: margin + 150, y: y - 20), attributes: grandTotalAttrs)

        var valueX = pageSize.width - margin - 10
        for (value, width) in values.reversed() {
            drawText(value, in: CGRect(x: valueX - width, y: y - 20, width: width, height: 18), attributes: grandTotalAttrs, alignment: .right)
            valueX -= width + 10
        }

        y -= 50
    }
}
