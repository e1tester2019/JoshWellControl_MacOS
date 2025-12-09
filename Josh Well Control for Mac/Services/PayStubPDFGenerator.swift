//
//  PayStubPDFGenerator.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-08.
//

import Foundation
import AppKit

class PayStubPDFGenerator {
    static let shared = PayStubPDFGenerator()

    private init() {}

    private let brandColor = NSColor(red: 82/255, green: 165/255, blue: 191/255, alpha: 1.0)

    func generatePDF(for stub: PayStub, payRun: PayRun, pageSize: CGSize = CGSize(width: 612, height: 792)) -> Data? {
        guard let employee = stub.employee else { return nil }

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
        func fillRect(_ rect: CGRect, color: NSColor) {
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

        func strokeLine(from: CGPoint, to: CGPoint, color: NSColor, width: CGFloat) {
            pdfContext.setStrokeColor(color.cgColor)
            pdfContext.setLineWidth(width)
            pdfContext.setLineDash(phase: 0, lengths: [])
            pdfContext.move(to: from)
            pdfContext.addLine(to: to)
            pdfContext.strokePath()
        }

        // Fonts
        let titleFont = NSFont.systemFont(ofSize: 18, weight: .bold)
        let headerFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let labelFont = NSFont.systemFont(ofSize: 10, weight: .regular)
        let valueFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        let smallFont = NSFont.systemFont(ofSize: 9, weight: .regular)

        let businessInfo = BusinessInfo.shared

        // Start page
        pdfContext.beginPDFPage(nil)

        var y = pageSize.height

        // Header bar
        fillRect(CGRect(x: 0, y: y - 50, width: pageSize.width, height: 50), color: brandColor)

        let whiteAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor.white
        ]
        drawText("PAY STUB", at: CGPoint(x: margin, y: y - 34), attributes: whiteAttrs)

        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor.white
        ]
        drawText("Pay Date: \(payRun.payDateString)", in: CGRect(x: pageSize.width - margin - 200, y: y - 34, width: 200, height: 20), attributes: dateAttrs, alignment: .right)

        y -= 70

        // Company info
        let brandAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: brandColor
        ]
        drawText(businessInfo.companyName, at: CGPoint(x: margin, y: y), attributes: brandAttrs)
        y -= 14
        drawText(businessInfo.address, at: CGPoint(x: margin, y: y), attributes: brandAttrs)
        y -= 14
        drawText("\(businessInfo.city), \(businessInfo.province) \(businessInfo.postalCode)", at: CGPoint(x: margin, y: y), attributes: brandAttrs)

        // Employee info (right side)
        let grayAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor.darkGray
        ]
        let rightX = pageSize.width / 2 + 20
        var rightY = pageSize.height - 70

        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: headerFont,
            .foregroundColor: NSColor.black
        ]
        drawText(employee.fullName, at: CGPoint(x: rightX, y: rightY), attributes: headerAttrs)
        rightY -= 14

        if !employee.employeeNumber.isEmpty {
            drawText("Employee #: \(employee.employeeNumber)", at: CGPoint(x: rightX, y: rightY), attributes: grayAttrs)
            rightY -= 12
        }
        drawText(employee.jobTitle, at: CGPoint(x: rightX, y: rightY), attributes: grayAttrs)
        rightY -= 12

        if !employee.address.isEmpty {
            drawText(employee.address, at: CGPoint(x: rightX, y: rightY), attributes: grayAttrs)
            rightY -= 12
            drawText("\(employee.city), \(employee.province.shortName) \(employee.postalCode)", at: CGPoint(x: rightX, y: rightY), attributes: grayAttrs)
        }

        y -= 30

        // Pay period info
        drawText("Pay Period: \(payRun.periodString)", at: CGPoint(x: margin, y: y), attributes: grayAttrs)
        y -= 30

        // Earnings section
        fillRect(CGRect(x: margin, y: y - 18, width: contentWidth, height: 22), color: brandColor)

        let tableHeaderAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        drawText("EARNINGS", at: CGPoint(x: margin + 8, y: y - 14), attributes: tableHeaderAttrs)
        drawText("Hours", in: CGRect(x: margin + contentWidth * 0.5, y: y - 14, width: 60, height: 16), attributes: tableHeaderAttrs, alignment: .right)
        drawText("Rate", in: CGRect(x: margin + contentWidth * 0.65, y: y - 14, width: 60, height: 16), attributes: tableHeaderAttrs, alignment: .right)
        drawText("Amount", in: CGRect(x: margin + contentWidth * 0.8, y: y - 14, width: contentWidth * 0.18, height: 16), attributes: tableHeaderAttrs, alignment: .right)

        y -= 30

        let blackAttrs: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: NSColor.black
        ]

        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .currency
        numberFormatter.currencySymbol = "$"

        // Earnings rows
        func drawEarningsRow(description: String, hours: Double?, rate: Double?, amount: Double) {
            drawText(description, at: CGPoint(x: margin + 8, y: y), attributes: grayAttrs)
            if let h = hours {
                drawText(String(format: "%.2f", h), in: CGRect(x: margin + contentWidth * 0.5, y: y, width: 60, height: 14), attributes: blackAttrs, alignment: .right)
            }
            if let r = rate {
                let rateStr = numberFormatter.string(from: NSNumber(value: r)) ?? "$0.00"
                drawText(rateStr, in: CGRect(x: margin + contentWidth * 0.65, y: y, width: 60, height: 14), attributes: blackAttrs, alignment: .right)
            }
            let amountStr = numberFormatter.string(from: NSNumber(value: amount)) ?? "$0.00"
            drawText(amountStr, in: CGRect(x: margin + contentWidth * 0.8, y: y, width: contentWidth * 0.18, height: 14), attributes: blackAttrs, alignment: .right)
            y -= 16
        }

        if stub.regularHours > 0 {
            drawEarningsRow(description: "Regular", hours: stub.regularHours, rate: stub.regularRate, amount: stub.regularEarnings)
        }
        if stub.overtimeHours > 0 {
            drawEarningsRow(description: "Overtime (1.5x)", hours: stub.overtimeHours, rate: stub.overtimeRate, amount: stub.overtimeEarnings)
        }
        if stub.holidayHours > 0 {
            drawEarningsRow(description: "Holiday", hours: stub.holidayHours, rate: stub.regularRate, amount: stub.holidayPay)
        }
        if stub.sickHours > 0 {
            drawEarningsRow(description: "Sick", hours: stub.sickHours, rate: stub.regularRate, amount: stub.sickPay)
        }
        if stub.vacationPayout > 0 {
            drawEarningsRow(description: "Vacation Payout", hours: nil, rate: nil, amount: stub.vacationPayout)
        }
        if stub.otherEarnings > 0 {
            let desc = stub.otherEarningsDescription.isEmpty ? "Other" : stub.otherEarningsDescription
            drawEarningsRow(description: desc, hours: nil, rate: nil, amount: stub.otherEarnings)
        }

        // Gross total
        strokeLine(from: CGPoint(x: margin, y: y + 4), to: CGPoint(x: pageSize.width - margin, y: y + 4), color: .lightGray, width: 0.5)
        let boldAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        drawText("GROSS PAY", at: CGPoint(x: margin + 8, y: y - 4), attributes: boldAttrs)
        let grossStr = numberFormatter.string(from: NSNumber(value: stub.grossPay)) ?? "$0.00"
        drawText(grossStr, in: CGRect(x: margin + contentWidth * 0.8, y: y - 4, width: contentWidth * 0.18, height: 14), attributes: boldAttrs, alignment: .right)

        y -= 40

        // Deductions section
        fillRect(CGRect(x: margin, y: y - 18, width: contentWidth, height: 22), color: brandColor)
        drawText("DEDUCTIONS", at: CGPoint(x: margin + 8, y: y - 14), attributes: tableHeaderAttrs)
        drawText("Amount", in: CGRect(x: margin + contentWidth * 0.8, y: y - 14, width: contentWidth * 0.18, height: 16), attributes: tableHeaderAttrs, alignment: .right)

        y -= 30

        let redAttrs: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: NSColor(red: 0.8, green: 0, blue: 0, alpha: 1)
        ]

        func drawDeductionRow(description: String, amount: Double) {
            drawText(description, at: CGPoint(x: margin + 8, y: y), attributes: grayAttrs)
            let amountStr = numberFormatter.string(from: NSNumber(value: amount)) ?? "$0.00"
            drawText(amountStr, in: CGRect(x: margin + contentWidth * 0.8, y: y, width: contentWidth * 0.18, height: 14), attributes: redAttrs, alignment: .right)
            y -= 16
        }

        drawDeductionRow(description: "Canada Pension Plan (CPP)", amount: stub.cppDeduction)
        drawDeductionRow(description: "Employment Insurance (EI)", amount: stub.eiDeduction)
        drawDeductionRow(description: "Federal Income Tax", amount: stub.federalTax)
        drawDeductionRow(description: "Provincial Income Tax (\(employee.province.shortName))", amount: stub.provincialTax)
        if stub.otherDeductions > 0 {
            let desc = stub.otherDeductionsDescription.isEmpty ? "Other Deductions" : stub.otherDeductionsDescription
            drawDeductionRow(description: desc, amount: stub.otherDeductions)
        }

        // Total deductions
        strokeLine(from: CGPoint(x: margin, y: y + 4), to: CGPoint(x: pageSize.width - margin, y: y + 4), color: .lightGray, width: 0.5)
        drawText("TOTAL DEDUCTIONS", at: CGPoint(x: margin + 8, y: y - 4), attributes: boldAttrs)
        let deductStr = numberFormatter.string(from: NSNumber(value: stub.totalDeductions)) ?? "$0.00"
        let boldRedAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor(red: 0.8, green: 0, blue: 0, alpha: 1)
        ]
        drawText(deductStr, in: CGRect(x: margin + contentWidth * 0.8, y: y - 4, width: contentWidth * 0.18, height: 14), attributes: boldRedAttrs, alignment: .right)

        y -= 50

        // Net Pay box
        fillRect(CGRect(x: margin, y: y - 40, width: contentWidth, height: 45), color: NSColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1))

        let netPayLabelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        drawText("NET PAY", at: CGPoint(x: margin + 10, y: y - 26), attributes: netPayLabelAttrs)

        let netPayValueAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: NSColor(red: 0, green: 0.6, blue: 0, alpha: 1)
        ]
        let netStr = numberFormatter.string(from: NSNumber(value: stub.netPay)) ?? "$0.00"
        drawText(netStr, in: CGRect(x: margin + contentWidth * 0.6, y: y - 28, width: contentWidth * 0.38, height: 20), attributes: netPayValueAttrs, alignment: .right)

        y -= 70

        // YTD section
        fillRect(CGRect(x: margin, y: y - 18, width: contentWidth, height: 22), color: brandColor)
        drawText("YEAR-TO-DATE (\(employee.ytdYear))", at: CGPoint(x: margin + 8, y: y - 14), attributes: tableHeaderAttrs)
        drawText("Current", in: CGRect(x: margin + contentWidth * 0.5, y: y - 14, width: 70, height: 16), attributes: tableHeaderAttrs, alignment: .right)
        drawText("YTD", in: CGRect(x: margin + contentWidth * 0.7, y: y - 14, width: contentWidth * 0.28, height: 16), attributes: tableHeaderAttrs, alignment: .right)

        y -= 30

        func drawYTDRow(description: String, current: Double, ytd: Double) {
            drawText(description, at: CGPoint(x: margin + 8, y: y), attributes: grayAttrs)
            let currentStr = numberFormatter.string(from: NSNumber(value: current)) ?? "$0.00"
            drawText(currentStr, in: CGRect(x: margin + contentWidth * 0.5, y: y, width: 70, height: 14), attributes: blackAttrs, alignment: .right)
            let ytdStr = numberFormatter.string(from: NSNumber(value: ytd)) ?? "$0.00"
            drawText(ytdStr, in: CGRect(x: margin + contentWidth * 0.7, y: y, width: contentWidth * 0.28, height: 14), attributes: blackAttrs, alignment: .right)
            y -= 16
        }

        drawYTDRow(description: "Gross Pay", current: stub.grossPay, ytd: stub.ytdGrossPay)
        drawYTDRow(description: "CPP", current: stub.cppDeduction, ytd: stub.ytdCPP)
        drawYTDRow(description: "EI", current: stub.eiDeduction, ytd: stub.ytdEI)
        drawYTDRow(description: "Federal Tax", current: stub.federalTax, ytd: stub.ytdFederalTax)
        drawYTDRow(description: "Provincial Tax", current: stub.provincialTax, ytd: stub.ytdProvincialTax)

        y -= 20

        // Vacation accrual
        strokeLine(from: CGPoint(x: margin, y: y + 10), to: CGPoint(x: pageSize.width - margin, y: y + 10), color: .lightGray, width: 0.5)
        let blueAttrs: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: NSColor.blue
        ]
        drawText("Vacation Accrued This Period:", at: CGPoint(x: margin + 8, y: y - 4), attributes: grayAttrs)
        let vacAccrStr = numberFormatter.string(from: NSNumber(value: stub.vacationAccrued)) ?? "$0.00"
        drawText(vacAccrStr, in: CGRect(x: margin + 200, y: y - 4, width: 80, height: 14), attributes: blueAttrs, alignment: .left)

        drawText("Vacation Balance:", at: CGPoint(x: margin + contentWidth * 0.5, y: y - 4), attributes: grayAttrs)
        let vacBalance = stub.ytdVacationAccrued - stub.ytdVacationUsed
        let vacBalStr = numberFormatter.string(from: NSNumber(value: vacBalance)) ?? "$0.00"
        drawText(vacBalStr, in: CGRect(x: margin + contentWidth * 0.75, y: y - 4, width: contentWidth * 0.23, height: 14), attributes: blueAttrs, alignment: .right)

        // Footer
        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: smallFont,
            .foregroundColor: NSColor.gray
        ]
        drawText("This pay stub is for informational purposes. Please retain for your records.", in: CGRect(x: 0, y: 30, width: pageSize.width, height: 14), attributes: footerAttrs, alignment: .center)

        pdfContext.endPDFPage()
        pdfContext.closePDF()

        return data as Data
    }
}
