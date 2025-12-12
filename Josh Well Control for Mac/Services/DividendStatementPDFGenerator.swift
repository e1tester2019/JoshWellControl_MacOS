//
//  DividendStatementPDFGenerator.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-08.
//

import Foundation

#if os(macOS)
import AppKit
typealias PDFColor = NSColor
typealias PDFFont = NSFont
#elseif os(iOS)
import UIKit
typealias PDFColor = UIColor
typealias PDFFont = UIFont
#endif

class DividendStatementPDFGenerator {
    static let shared = DividendStatementPDFGenerator()

    private init() {}

    enum StatementType: String, CaseIterable {
        case quarterly = "Quarterly"
        case yearly = "Yearly"
    }

    private let brandColor = PDFColor(red: 82/255, green: 165/255, blue: 191/255, alpha: 1.0)

    func generatePDF(
        shareholders: [Shareholder],
        year: Int,
        statementType: StatementType,
        pageSize: CGSize = CGSize(width: 612, height: 792)
    ) -> Data? {
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

        // Helper functions
        func fillRect(_ rect: CGRect, color: PDFColor) {
            pdfContext.setFillColor(color.cgColor)
            pdfContext.fill(rect)
        }

        func drawText(_ text: String, at point: CGPoint, attributes: [NSAttributedString.Key: Any]) {
            let attrString = NSAttributedString(string: text, attributes: attributes)
            let line = CTLineCreateWithAttributedString(attrString)
            pdfContext.textPosition = CGPoint(x: point.x, y: point.y)
            CTLineDraw(line, pdfContext)
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

            pdfContext.textPosition = CGPoint(x: x, y: rect.minY)
            CTLineDraw(line, pdfContext)
        }

        func strokeLine(from: CGPoint, to: CGPoint, color: PDFColor, width: CGFloat) {
            pdfContext.setStrokeColor(color.cgColor)
            pdfContext.setLineWidth(width)
            pdfContext.setLineDash(phase: 0, lengths: [])
            pdfContext.move(to: from)
            pdfContext.addLine(to: to)
            pdfContext.strokePath()
        }

        // Fonts
        let titleFont = PDFFont.systemFont(ofSize: 18, weight: .bold)
        let headerFont = PDFFont.systemFont(ofSize: 12, weight: .semibold)
        let labelFont = PDFFont.systemFont(ofSize: 10, weight: .regular)
        let valueFont = PDFFont.systemFont(ofSize: 10, weight: .medium)
        let smallFont = PDFFont.systemFont(ofSize: 9, weight: .regular)

        let businessInfo = BusinessInfo.shared
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .currency
        numberFormatter.currencySymbol = "$"

        // Attributes
        let whiteAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: PDFColor.white
        ]
        let brandAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: brandColor
        ]
        let grayAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: PDFColor.darkGray
        ]
        let blackAttrs: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: PDFColor.black
        ]
        let boldAttrs: [NSAttributedString.Key: Any] = [
            .font: PDFFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: PDFColor.black
        ]
        let tableHeaderAttrs: [NSAttributedString.Key: Any] = [
            .font: PDFFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: PDFColor.white
        ]
        let greenAttrs: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: PDFColor(red: 0, green: 0.5, blue: 0, alpha: 1)
        ]

        if statementType == .yearly {
            // Generate yearly statement for each shareholder
            for shareholder in shareholders {
                let summary = DividendReportGenerator.yearlySummary(for: shareholder, year: year)

                pdfContext.beginPDFPage(nil)
                var y = pageSize.height

                // Header bar
                fillRect(CGRect(x: 0, y: y - 50, width: pageSize.width, height: 50), color: brandColor)
                drawText("DIVIDEND STATEMENT", at: CGPoint(x: margin, y: y - 34), attributes: whiteAttrs)

                let dateAttrs: [NSAttributedString.Key: Any] = [
                    .font: labelFont,
                    .foregroundColor: PDFColor.white
                ]
                drawText("Tax Year \(year)", in: CGRect(x: pageSize.width - margin - 150, y: y - 34, width: 150, height: 20), attributes: dateAttrs, alignment: .right)

                y -= 70

                // Company info
                drawText(businessInfo.companyName, at: CGPoint(x: margin, y: y), attributes: brandAttrs)
                y -= 14
                drawText(businessInfo.address, at: CGPoint(x: margin, y: y), attributes: brandAttrs)
                y -= 14
                drawText("\(businessInfo.city), \(businessInfo.province) \(businessInfo.postalCode)", at: CGPoint(x: margin, y: y), attributes: brandAttrs)
                y -= 14
                drawText("GST #: \(businessInfo.gstNumber)", at: CGPoint(x: margin, y: y), attributes: grayAttrs)

                // Shareholder info (right side)
                var rightY = pageSize.height - 70
                let rightX = pageSize.width / 2 + 40

                let shNameAttrs: [NSAttributedString.Key: Any] = [
                    .font: headerFont,
                    .foregroundColor: PDFColor.black
                ]
                drawText(shareholder.fullName, at: CGPoint(x: rightX, y: rightY), attributes: shNameAttrs)
                rightY -= 14

                if !shareholder.address.isEmpty {
                    drawText(shareholder.address, at: CGPoint(x: rightX, y: rightY), attributes: grayAttrs)
                    rightY -= 12
                    drawText("\(shareholder.city), \(shareholder.province.shortName) \(shareholder.postalCode)", at: CGPoint(x: rightX, y: rightY), attributes: grayAttrs)
                    rightY -= 12
                }

                drawText("Ownership: \(String(format: "%.1f", shareholder.ownershipPercent))%", at: CGPoint(x: rightX, y: rightY), attributes: grayAttrs)

                y -= 40

                // Annual Summary section
                fillRect(CGRect(x: margin, y: y - 18, width: contentWidth, height: 22), color: brandColor)
                drawText("ANNUAL DIVIDEND SUMMARY", at: CGPoint(x: margin + 8, y: y - 14), attributes: tableHeaderAttrs)

                y -= 40

                // Summary table header
                let col1X = margin + 8
                let col2X = margin + contentWidth * 0.35
                let col3X = margin + contentWidth * 0.55
                let col4X = margin + contentWidth * 0.75

                drawText("Description", at: CGPoint(x: col1X, y: y), attributes: boldAttrs)
                drawText("Eligible", in: CGRect(x: col2X, y: y, width: 80, height: 14), attributes: boldAttrs, alignment: .right)
                drawText("Non-Eligible", in: CGRect(x: col3X, y: y, width: 80, height: 14), attributes: boldAttrs, alignment: .right)
                drawText("Total", in: CGRect(x: col4X, y: y, width: contentWidth * 0.23, height: 14), attributes: boldAttrs, alignment: .right)

                y -= 6
                strokeLine(from: CGPoint(x: margin, y: y), to: CGPoint(x: pageSize.width - margin, y: y), color: .lightGray, width: 0.5)
                y -= 14

                // Quarterly rows
                for quarter in summary.quarterlyBreakdown {
                    if quarter.totalAmount > 0 {
                        drawText(quarter.quarterString, at: CGPoint(x: col1X, y: y), attributes: grayAttrs)
                        let eligibleStr = numberFormatter.string(from: NSNumber(value: quarter.eligibleAmount)) ?? "$0.00"
                        let nonEligibleStr = numberFormatter.string(from: NSNumber(value: quarter.nonEligibleAmount)) ?? "$0.00"
                        let totalStr = numberFormatter.string(from: NSNumber(value: quarter.totalAmount)) ?? "$0.00"
                        drawText(eligibleStr, in: CGRect(x: col2X, y: y, width: 80, height: 14), attributes: blackAttrs, alignment: .right)
                        drawText(nonEligibleStr, in: CGRect(x: col3X, y: y, width: 80, height: 14), attributes: blackAttrs, alignment: .right)
                        drawText(totalStr, in: CGRect(x: col4X, y: y, width: contentWidth * 0.23, height: 14), attributes: blackAttrs, alignment: .right)
                        y -= 16
                    }
                }

                // Total row
                strokeLine(from: CGPoint(x: margin, y: y + 4), to: CGPoint(x: pageSize.width - margin, y: y + 4), color: .lightGray, width: 0.5)
                y -= 4

                drawText("Total Dividends", at: CGPoint(x: col1X, y: y), attributes: boldAttrs)
                let eligibleTotalStr = numberFormatter.string(from: NSNumber(value: summary.eligibleAmount)) ?? "$0.00"
                let nonEligibleTotalStr = numberFormatter.string(from: NSNumber(value: summary.nonEligibleAmount)) ?? "$0.00"
                let grandTotalStr = numberFormatter.string(from: NSNumber(value: summary.totalAmount)) ?? "$0.00"
                drawText(eligibleTotalStr, in: CGRect(x: col2X, y: y, width: 80, height: 14), attributes: boldAttrs, alignment: .right)
                drawText(nonEligibleTotalStr, in: CGRect(x: col3X, y: y, width: 80, height: 14), attributes: boldAttrs, alignment: .right)
                drawText(grandTotalStr, in: CGRect(x: col4X, y: y, width: contentWidth * 0.23, height: 14), attributes: boldAttrs, alignment: .right)

                y -= 40

                // Tax information section
                fillRect(CGRect(x: margin, y: y - 18, width: contentWidth, height: 22), color: brandColor)
                drawText("TAX INFORMATION (FOR T5 PREPARATION)", at: CGPoint(x: margin + 8, y: y - 14), attributes: tableHeaderAttrs)

                y -= 40

                func drawTaxRow(desc: String, eligible: Double, nonEligible: Double, total: Double, isBold: Bool = false, isGreen: Bool = false) {
                    let attrs = isBold ? boldAttrs : grayAttrs
                    let valueAttrs = isGreen ? greenAttrs : (isBold ? boldAttrs : blackAttrs)
                    drawText(desc, at: CGPoint(x: col1X, y: y), attributes: attrs)
                    let e = numberFormatter.string(from: NSNumber(value: eligible)) ?? "$0.00"
                    let n = numberFormatter.string(from: NSNumber(value: nonEligible)) ?? "$0.00"
                    let t = numberFormatter.string(from: NSNumber(value: total)) ?? "$0.00"
                    drawText(e, in: CGRect(x: col2X, y: y, width: 80, height: 14), attributes: valueAttrs, alignment: .right)
                    drawText(n, in: CGRect(x: col3X, y: y, width: 80, height: 14), attributes: valueAttrs, alignment: .right)
                    drawText(t, in: CGRect(x: col4X, y: y, width: contentWidth * 0.23, height: 14), attributes: valueAttrs, alignment: .right)
                    y -= 16
                }

                drawTaxRow(desc: "Actual Dividends Paid", eligible: summary.eligibleAmount, nonEligible: summary.nonEligibleAmount, total: summary.totalAmount)

                let eligibleGrossUp = summary.grossedUpEligible - summary.eligibleAmount
                let nonEligibleGrossUp = summary.grossedUpNonEligible - summary.nonEligibleAmount
                let totalGrossUp = summary.totalGrossedUp - summary.totalAmount
                drawTaxRow(desc: "Gross-up Amount", eligible: eligibleGrossUp, nonEligible: nonEligibleGrossUp, total: totalGrossUp)

                strokeLine(from: CGPoint(x: margin, y: y + 4), to: CGPoint(x: pageSize.width - margin, y: y + 4), color: .lightGray, width: 0.5)
                y -= 4

                drawTaxRow(desc: "Taxable Amount", eligible: summary.grossedUpEligible, nonEligible: summary.grossedUpNonEligible, total: summary.totalGrossedUp, isBold: true)

                y -= 8
                strokeLine(from: CGPoint(x: margin, y: y + 4), to: CGPoint(x: pageSize.width - margin, y: y + 4), color: .lightGray, width: 0.5)
                y -= 12

                drawTaxRow(desc: "Federal Dividend Tax Credit", eligible: summary.federalTaxCreditEligible, nonEligible: summary.federalTaxCreditNonEligible, total: summary.totalFederalTaxCredit, isGreen: true)

                y -= 30

                // T5 Reference Box
                fillRect(CGRect(x: margin, y: y - 70, width: contentWidth, height: 75), color: PDFColor(red: 1.0, green: 0.95, blue: 0.9, alpha: 1))

                let refHeaderAttrs: [NSAttributedString.Key: Any] = [
                    .font: PDFFont.systemFont(ofSize: 10, weight: .semibold),
                    .foregroundColor: PDFColor.black
                ]
                let refAttrs: [NSAttributedString.Key: Any] = [
                    .font: smallFont,
                    .foregroundColor: PDFColor.darkGray
                ]

                drawText("T5 Slip Box Reference", at: CGPoint(x: margin + 10, y: y - 14), attributes: refHeaderAttrs)

                y -= 30
                drawText("Eligible Dividends:", at: CGPoint(x: margin + 10, y: y), attributes: refAttrs)
                drawText("Box 10 - Actual amount of eligible dividends", at: CGPoint(x: margin + 120, y: y), attributes: refAttrs)
                y -= 12
                drawText("", at: CGPoint(x: margin + 10, y: y), attributes: refAttrs)
                drawText("Box 11 - Taxable amount of eligible dividends", at: CGPoint(x: margin + 120, y: y), attributes: refAttrs)
                y -= 12
                drawText("", at: CGPoint(x: margin + 10, y: y), attributes: refAttrs)
                drawText("Box 12 - Dividend tax credit for eligible dividends", at: CGPoint(x: margin + 120, y: y), attributes: refAttrs)

                y -= 20
                drawText("Other Dividends:", at: CGPoint(x: margin + 10, y: y), attributes: refAttrs)
                drawText("Box 23 - Actual amount of dividends other than eligible", at: CGPoint(x: margin + 120, y: y), attributes: refAttrs)
                y -= 12
                drawText("", at: CGPoint(x: margin + 10, y: y), attributes: refAttrs)
                drawText("Box 24 - Taxable amount of dividends other than eligible", at: CGPoint(x: margin + 120, y: y), attributes: refAttrs)
                y -= 12
                drawText("", at: CGPoint(x: margin + 10, y: y), attributes: refAttrs)
                drawText("Box 25 - Dividend tax credit for dividends other than eligible", at: CGPoint(x: margin + 120, y: y), attributes: refAttrs)

                // Footer
                let footerAttrs: [NSAttributedString.Key: Any] = [
                    .font: smallFont,
                    .foregroundColor: PDFColor.gray
                ]
                drawText("This statement is for informational purposes. Please consult your tax professional.", in: CGRect(x: 0, y: 30, width: pageSize.width, height: 14), attributes: footerAttrs, alignment: .center)

                pdfContext.endPDFPage()
            }
        } else {
            // Quarterly statements
            for quarter in 1...4 {
                // Check if any shareholder has dividends in this quarter
                let hasData = shareholders.contains { shareholder in
                    let summary = DividendReportGenerator.quarterlySummary(for: shareholder, year: year, quarter: quarter)
                    return summary.totalAmount > 0
                }

                guard hasData else { continue }

                pdfContext.beginPDFPage(nil)
                var y = pageSize.height

                // Header bar
                fillRect(CGRect(x: 0, y: y - 50, width: pageSize.width, height: 50), color: brandColor)
                drawText("QUARTERLY DIVIDEND STATEMENT", at: CGPoint(x: margin, y: y - 34), attributes: whiteAttrs)

                let dateAttrs: [NSAttributedString.Key: Any] = [
                    .font: labelFont,
                    .foregroundColor: PDFColor.white
                ]
                drawText("Q\(quarter) \(year)", in: CGRect(x: pageSize.width - margin - 100, y: y - 34, width: 100, height: 20), attributes: dateAttrs, alignment: .right)

                y -= 70

                // Company info
                drawText(businessInfo.companyName, at: CGPoint(x: margin, y: y), attributes: brandAttrs)
                y -= 14
                drawText(businessInfo.address, at: CGPoint(x: margin, y: y), attributes: brandAttrs)
                y -= 14
                drawText("\(businessInfo.city), \(businessInfo.province) \(businessInfo.postalCode)", at: CGPoint(x: margin, y: y), attributes: brandAttrs)

                // Quarter period (right side)
                let quarterSummary = DividendReportGenerator.quarterlySummary(for: shareholders.first!, year: year, quarter: quarter)
                var rightY = pageSize.height - 70
                let rightX = pageSize.width / 2 + 40

                let periodAttrs: [NSAttributedString.Key: Any] = [
                    .font: headerFont,
                    .foregroundColor: PDFColor.black
                ]
                drawText("Quarter \(quarter), \(year)", at: CGPoint(x: rightX, y: rightY), attributes: periodAttrs)
                rightY -= 14

                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "d MMM yyyy"
                let periodStr = "\(dateFormatter.string(from: quarterSummary.periodStart)) - \(dateFormatter.string(from: quarterSummary.periodEnd))"
                drawText(periodStr, at: CGPoint(x: rightX, y: rightY), attributes: grayAttrs)

                y -= 50

                // Dividends table
                fillRect(CGRect(x: margin, y: y - 18, width: contentWidth, height: 22), color: brandColor)
                drawText("SHAREHOLDER", at: CGPoint(x: margin + 8, y: y - 14), attributes: tableHeaderAttrs)
                drawText("ELIGIBLE", in: CGRect(x: margin + contentWidth * 0.4, y: y - 14, width: 80, height: 16), attributes: tableHeaderAttrs, alignment: .right)
                drawText("NON-ELIGIBLE", in: CGRect(x: margin + contentWidth * 0.6, y: y - 14, width: 80, height: 16), attributes: tableHeaderAttrs, alignment: .right)
                drawText("TOTAL", in: CGRect(x: margin + contentWidth * 0.8, y: y - 14, width: contentWidth * 0.18, height: 16), attributes: tableHeaderAttrs, alignment: .right)

                y -= 30

                var quarterTotal: Double = 0
                var quarterEligible: Double = 0
                var quarterNonEligible: Double = 0

                for shareholder in shareholders {
                    let summary = DividendReportGenerator.quarterlySummary(for: shareholder, year: year, quarter: quarter)

                    if summary.totalAmount > 0 {
                        drawText(shareholder.fullName, at: CGPoint(x: margin + 8, y: y), attributes: blackAttrs)
                        drawText("\(String(format: "%.0f", shareholder.ownershipPercent))%", at: CGPoint(x: margin + 180, y: y), attributes: grayAttrs)

                        let eligibleStr = numberFormatter.string(from: NSNumber(value: summary.eligibleAmount)) ?? "$0.00"
                        let nonEligibleStr = numberFormatter.string(from: NSNumber(value: summary.nonEligibleAmount)) ?? "$0.00"
                        let totalStr = numberFormatter.string(from: NSNumber(value: summary.totalAmount)) ?? "$0.00"

                        drawText(eligibleStr, in: CGRect(x: margin + contentWidth * 0.4, y: y, width: 80, height: 14), attributes: blackAttrs, alignment: .right)
                        drawText(nonEligibleStr, in: CGRect(x: margin + contentWidth * 0.6, y: y, width: 80, height: 14), attributes: blackAttrs, alignment: .right)
                        drawText(totalStr, in: CGRect(x: margin + contentWidth * 0.8, y: y, width: contentWidth * 0.18, height: 14), attributes: blackAttrs, alignment: .right)

                        quarterTotal += summary.totalAmount
                        quarterEligible += summary.eligibleAmount
                        quarterNonEligible += summary.nonEligibleAmount

                        y -= 18
                    }
                }

                // Quarter total
                strokeLine(from: CGPoint(x: margin, y: y + 6), to: CGPoint(x: pageSize.width - margin, y: y + 6), color: .lightGray, width: 0.5)
                y -= 4

                drawText("Quarter Total", at: CGPoint(x: margin + 8, y: y), attributes: boldAttrs)
                let qEligibleStr = numberFormatter.string(from: NSNumber(value: quarterEligible)) ?? "$0.00"
                let qNonEligibleStr = numberFormatter.string(from: NSNumber(value: quarterNonEligible)) ?? "$0.00"
                let qTotalStr = numberFormatter.string(from: NSNumber(value: quarterTotal)) ?? "$0.00"
                drawText(qEligibleStr, in: CGRect(x: margin + contentWidth * 0.4, y: y, width: 80, height: 14), attributes: boldAttrs, alignment: .right)
                drawText(qNonEligibleStr, in: CGRect(x: margin + contentWidth * 0.6, y: y, width: 80, height: 14), attributes: boldAttrs, alignment: .right)
                drawText(qTotalStr, in: CGRect(x: margin + contentWidth * 0.8, y: y, width: contentWidth * 0.18, height: 14), attributes: boldAttrs, alignment: .right)

                // Footer
                let footerAttrs: [NSAttributedString.Key: Any] = [
                    .font: smallFont,
                    .foregroundColor: PDFColor.gray
                ]
                drawText("This statement is for informational purposes.", in: CGRect(x: 0, y: 30, width: pageSize.width, height: 14), attributes: footerAttrs, alignment: .center)

                pdfContext.endPDFPage()
            }
        }

        pdfContext.closePDF()
        return data as Data
    }
}
