//
//  CompanyStatementPDFGenerator.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-08.
//

import Foundation

#if os(macOS)
import AppKit
typealias CSColor = NSColor
typealias CSFont = NSFont
#elseif os(iOS)
import UIKit
typealias CSColor = UIColor
typealias CSFont = UIFont
#endif

class CompanyStatementPDFGenerator {
    static let shared = CompanyStatementPDFGenerator()

    private init() {}

    enum StatementType: String, CaseIterable {
        case quarterly = "Quarterly"
        case yearly = "Yearly"
    }

    private let brandColor = CSColor(red: 82/255, green: 165/255, blue: 191/255, alpha: 1.0)

    func generatePDF(
        summaries: [(String, FinancialSummary)],
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
        func fillRect(_ rect: CGRect, color: CSColor) {
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

        func strokeLine(from: CGPoint, to: CGPoint, color: CSColor, width: CGFloat) {
            pdfContext.setStrokeColor(color.cgColor)
            pdfContext.setLineWidth(width)
            pdfContext.setLineDash(phase: 0, lengths: [])
            pdfContext.move(to: from)
            pdfContext.addLine(to: to)
            pdfContext.strokePath()
        }

        // Fonts
        let titleFont = CSFont.systemFont(ofSize: 18, weight: .bold)
        let headerFont = CSFont.systemFont(ofSize: 12, weight: .semibold)
        let labelFont = CSFont.systemFont(ofSize: 10, weight: .regular)
        let valueFont = CSFont.systemFont(ofSize: 10, weight: .medium)
        let smallFont = CSFont.systemFont(ofSize: 9, weight: .regular)
        let sectionFont = CSFont.systemFont(ofSize: 11, weight: .semibold)

        let businessInfo = BusinessInfo.shared
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .currency
        numberFormatter.currencySymbol = "$"

        // Attributes
        let whiteAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: CSColor.white
        ]
        let brandAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: brandColor
        ]
        let grayAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: CSColor.darkGray
        ]
        let blackAttrs: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: CSColor.black
        ]
        let boldAttrs: [NSAttributedString.Key: Any] = [
            .font: CSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: CSColor.black
        ]
        let sectionAttrs: [NSAttributedString.Key: Any] = [
            .font: sectionFont,
            .foregroundColor: brandColor
        ]
        let greenAttrs: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: CSColor(red: 0, green: 0.5, blue: 0, alpha: 1)
        ]
        let redAttrs: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: CSColor(red: 0.8, green: 0, blue: 0, alpha: 1)
        ]

        for (periodName, summary) in summaries {
            pdfContext.beginPDFPage(nil)
            var y = pageSize.height

            // Header bar
            fillRect(CGRect(x: 0, y: y - 50, width: pageSize.width, height: 50), color: brandColor)

            let titleText = statementType == .yearly ? "FINANCIAL STATEMENT" : "QUARTERLY STATEMENT"
            drawText(titleText, at: CGPoint(x: margin, y: y - 34), attributes: whiteAttrs)

            let dateAttrs: [NSAttributedString.Key: Any] = [
                .font: labelFont,
                .foregroundColor: CSColor.white
            ]
            drawText("\(periodName) \(year)", in: CGRect(x: pageSize.width - margin - 150, y: y - 34, width: 150, height: 20), attributes: dateAttrs, alignment: .right)

            y -= 70

            // Company info
            drawText(businessInfo.companyName, at: CGPoint(x: margin, y: y), attributes: brandAttrs)
            y -= 14
            drawText(businessInfo.address, at: CGPoint(x: margin, y: y), attributes: brandAttrs)
            y -= 14
            drawText("\(businessInfo.city), \(businessInfo.province) \(businessInfo.postalCode)", at: CGPoint(x: margin, y: y), attributes: brandAttrs)
            y -= 14
            drawText("GST #: \(businessInfo.gstNumber)", at: CGPoint(x: margin, y: y), attributes: grayAttrs)

            y -= 40

            let col1X = margin + 8
            let col2X = margin + contentWidth * 0.7

            // Helper for rows
            func drawRow(label: String, amount: Double, indent: Bool = false, isBold: Bool = false, isGreen: Bool = false, isRed: Bool = false) {
                let labelX = indent ? col1X + 20 : col1X
                let attrs = indent ? grayAttrs : (isBold ? boldAttrs : blackAttrs)
                let valueAttrs = isGreen ? greenAttrs : (isRed ? redAttrs : (isBold ? boldAttrs : blackAttrs))

                drawText(label, at: CGPoint(x: labelX, y: y), attributes: attrs)
                let amountStr = numberFormatter.string(from: NSNumber(value: amount)) ?? "$0.00"
                drawText(amountStr, in: CGRect(x: col2X, y: y, width: contentWidth * 0.28, height: 14), attributes: valueAttrs, alignment: .right)
                y -= 16
            }

            func drawSectionHeader(_ title: String) {
                y -= 18
                drawText(title, at: CGPoint(x: col1X, y: y), attributes: sectionAttrs)
                y -= 18
            }

            func drawDivider() {
                y -= 6
                strokeLine(from: CGPoint(x: margin, y: y), to: CGPoint(x: pageSize.width - margin, y: y), color: .lightGray, width: 0.5)
                y -= 10
            }

            // REVENUE SECTION
            drawSectionHeader("REVENUE")
            drawRow(label: "Invoiced Revenue", amount: summary.totalRevenue)
            drawRow(label: "Less: Unpaid Invoices", amount: -summary.unpaidRevenue, indent: true)
            drawDivider()
            drawRow(label: "Net Revenue (Collected)", amount: summary.collectedRevenue, isBold: true, isGreen: true)

            // EXPENSES SECTION
            drawSectionHeader("EXPENSES")

            let sortedExpenses = summary.expensesByCategory.sorted { $0.value > $1.value }
            for (category, amount) in sortedExpenses {
                drawRow(label: category.rawValue, amount: amount, indent: true)
            }
            if summary.mileageDeduction > 0 {
                drawRow(label: "Mileage (CRA Rate)", amount: summary.mileageDeduction, indent: true)
            }
            drawDivider()
            drawRow(label: "Total Expenses", amount: summary.totalExpenses, isBold: true, isRed: true)

            // PAYROLL SECTION
            drawSectionHeader("PAYROLL")
            drawRow(label: "Gross Wages", amount: summary.grossPayroll)
            drawRow(label: "Employer CPP Contribution", amount: summary.employerCPP, indent: true)
            drawRow(label: "Employer EI Contribution", amount: summary.employerEI, indent: true)
            drawDivider()
            drawRow(label: "Total Payroll Cost", amount: summary.totalPayrollCost, isBold: true, isRed: true)

            // OPERATING INCOME
            let operatingIncome = summary.collectedRevenue - summary.totalExpenses - summary.totalPayrollCost
            drawSectionHeader("OPERATING RESULTS")
            fillRect(CGRect(x: margin, y: y - 4, width: contentWidth, height: 20), color: CSColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1))
            let opIncomeAttrs: [NSAttributedString.Key: Any] = [
                .font: CSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: operatingIncome >= 0 ? CSColor(red: 0, green: 0.5, blue: 0, alpha: 1) : CSColor.red
            ]
            drawText("Operating Income", at: CGPoint(x: col1X, y: y), attributes: boldAttrs)
            let opStr = numberFormatter.string(from: NSNumber(value: operatingIncome)) ?? "$0.00"
            drawText(opStr, in: CGRect(x: col2X, y: y, width: contentWidth * 0.28, height: 14), attributes: opIncomeAttrs, alignment: .right)
            y -= 24

            // DIVIDENDS SECTION
            drawSectionHeader("DIVIDENDS")
            drawRow(label: "Dividends Declared", amount: summary.dividendsDeclared)
            drawRow(label: "Dividends Paid", amount: summary.dividendsPaid, indent: true)

            // NET POSITION
            let netPosition = operatingIncome - summary.dividendsPaid
            drawSectionHeader("NET POSITION")
            fillRect(CGRect(x: margin, y: y - 4, width: contentWidth, height: 20), color: brandColor.withAlphaComponent(0.1))
            let netAttrs: [NSAttributedString.Key: Any] = [
                .font: CSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: netPosition >= 0 ? CSColor.black : CSColor.red
            ]
            drawText("Retained Earnings (After Dividends)", at: CGPoint(x: col1X, y: y), attributes: boldAttrs)
            let netStr = numberFormatter.string(from: NSNumber(value: netPosition)) ?? "$0.00"
            drawText(netStr, in: CGRect(x: col2X, y: y, width: contentWidth * 0.28, height: 14), attributes: netAttrs, alignment: .right)
            y -= 40

            // TAX INFORMATION
            drawSectionHeader("TAX INFORMATION")
            y -= 4

            fillRect(CGRect(x: margin, y: y - 50, width: contentWidth, height: 55), color: CSColor(red: 1.0, green: 0.98, blue: 0.94, alpha: 1))

            let taxCol1 = margin + 10
            let taxCol2 = margin + contentWidth * 0.35
            let taxCol3 = margin + contentWidth * 0.65

            drawText("GST Collected:", at: CGPoint(x: taxCol1, y: y - 12), attributes: grayAttrs)
            let gstCollStr = numberFormatter.string(from: NSNumber(value: summary.gstCollected)) ?? "$0.00"
            drawText(gstCollStr, at: CGPoint(x: taxCol1 + 80, y: y - 12), attributes: blackAttrs)

            drawText("GST Paid (ITC):", at: CGPoint(x: taxCol2, y: y - 12), attributes: grayAttrs)
            let gstPaidStr = numberFormatter.string(from: NSNumber(value: summary.gstPaid)) ?? "$0.00"
            drawText(gstPaidStr, at: CGPoint(x: taxCol2 + 80, y: y - 12), attributes: blackAttrs)

            let netGST = summary.gstCollected - summary.gstPaid
            let gstOwingAttrs: [NSAttributedString.Key: Any] = [
                .font: CSFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: netGST > 0 ? CSColor.red : CSColor(red: 0, green: 0.5, blue: 0, alpha: 1)
            ]
            drawText("Net GST Owing:", at: CGPoint(x: taxCol3, y: y - 12), attributes: grayAttrs)
            let netGSTStr = numberFormatter.string(from: NSNumber(value: netGST)) ?? "$0.00"
            drawText(netGSTStr, at: CGPoint(x: taxCol3 + 80, y: y - 12), attributes: gstOwingAttrs)

            drawText("Total Mileage:", at: CGPoint(x: taxCol1, y: y - 32), attributes: grayAttrs)
            drawText("\(Int(summary.totalMileage)) km", at: CGPoint(x: taxCol1 + 80, y: y - 32), attributes: blackAttrs)

            drawText("Mileage Deduction:", at: CGPoint(x: taxCol2, y: y - 32), attributes: grayAttrs)
            let mileageStr = numberFormatter.string(from: NSNumber(value: summary.mileageDeduction)) ?? "$0.00"
            drawText(mileageStr, at: CGPoint(x: taxCol2 + 100, y: y - 32), attributes: blackAttrs)

            // Footer
            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font: smallFont,
                .foregroundColor: CSColor.gray
            ]
            drawText("This statement is for internal use only. Please consult your accountant for official financial statements.", in: CGRect(x: 0, y: 30, width: pageSize.width, height: 14), attributes: footerAttrs, alignment: .center)

            pdfContext.endPDFPage()
        }

        pdfContext.closePDF()
        return data as Data
    }
}
