//
//  TripSimulationPDFGenerator.swift
//  Josh Well Control for Mac
//
//  PDF generator for Trip Simulation reports with charts
//

import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Simplified section data for PDF report
struct PDFSectionData {
    let name: String
    let topMD: Double
    let bottomMD: Double
    let length: Double
    let innerDiameter: Double  // ID for string (pipe bore), or hole ID for annulus
    let outerDiameter: Double  // OD for string, or pipe OD in annulus
    let capacity_m3_per_m: Double
    let displacement_m3_per_m: Double
    let totalVolume: Double
}

/// Input data for generating a trip simulation PDF report
struct TripSimulationReportData {
    let wellName: String
    let projectName: String
    let generatedDate: Date

    // Simulation parameters
    let startMD: Double
    let endMD: Double
    let controlMD: Double
    let stepSize: Double
    let baseMudDensity: Double
    let backfillDensity: Double
    let targetESD: Double
    let crackFloat: Double
    let initialSABP: Double
    let holdSABPOpen: Bool
    let tripSpeed: Double // m/min
    let useObservedPitGain: Bool
    let observedPitGain: Double?

    // Geometry data
    let drillStringSections: [PDFSectionData]
    let annulusSections: [PDFSectionData]

    // Results
    let steps: [NumericalTripModel.TripStep]

    // Computed safety metrics
    var minESD: Double { steps.map { $0.ESDatTD_kgpm3 }.min() ?? 0 }
    var maxESD: Double { steps.map { $0.ESDatTD_kgpm3 }.max() ?? 0 }
    var maxStaticSABP: Double { steps.map { $0.SABP_kPa }.max() ?? 0 }
    var maxDynamicSABP: Double { steps.map { $0.SABP_Dynamic_kPa }.max() ?? 0 }
    var totalBackfill: Double { steps.last?.cumulativeBackfill_m3 ?? 0 }
    var totalPitGain: Double { steps.last?.cumulativePitGain_m3 ?? 0 }
    var netTankChange: Double { steps.last?.cumulativeSurfaceTankDelta_m3 ?? 0 }

    // Total geometry volumes
    var totalStringCapacity: Double { drillStringSections.reduce(0) { $0 + $1.totalVolume } }
    var totalStringDisplacement: Double {
        drillStringSections.reduce(0) { $0 + $1.displacement_m3_per_m * $1.length }
    }
    var totalAnnulusCapacity: Double { annulusSections.reduce(0) { $0 + $1.totalVolume } }
}

/// Cross-platform PDF generator for trip simulation reports
class TripSimulationPDFGenerator {
    static let shared = TripSimulationPDFGenerator()

    #if os(macOS)
    private typealias PColor = NSColor
    private typealias PFont = NSFont
    #elseif os(iOS)
    private typealias PColor = UIColor
    private typealias PFont = UIFont
    #endif

    private init() {}

    // Brand colors
    private let brandColor = PColor(red: 82/255, green: 165/255, blue: 191/255, alpha: 1.0)
    private let safeColor = PColor(red: 76/255, green: 175/255, blue: 80/255, alpha: 1.0)
    private let warningColor = PColor(red: 255/255, green: 152/255, blue: 0/255, alpha: 1.0)
    private let dangerColor = PColor(red: 244/255, green: 67/255, blue: 54/255, alpha: 1.0)

    // Chart colors
    private let esdColor = PColor(red: 33/255, green: 150/255, blue: 243/255, alpha: 1.0)
    private let staticSABPColor = PColor(red: 76/255, green: 175/255, blue: 80/255, alpha: 1.0)
    private let dynamicSABPColor = PColor(red: 255/255, green: 152/255, blue: 0/255, alpha: 1.0)
    private let tankColor = PColor(red: 156/255, green: 39/255, blue: 176/255, alpha: 1.0)
    private let fillColor = PColor(red: 0/255, green: 150/255, blue: 136/255, alpha: 1.0)

    func generatePDF(for data: TripSimulationReportData, pageSize: CGSize = CGSize(width: 612, height: 792)) -> Data? {
        let pdfInfo = [
            kCGPDFContextCreator: "Josh Well Control" as CFString,
            kCGPDFContextTitle: "Trip Simulation Report - \(data.wellName)" as CFString
        ] as CFDictionary

        let pdfData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, pdfInfo) else {
            return nil
        }

        let margin: CGFloat = 36
        let contentWidth = pageSize.width - 2 * margin
        let pageBottom: CGFloat = 55
        var currentPage = 1
        var y: CGFloat = pageSize.height

        // MARK: - Helper Functions

        func fillRect(_ rect: CGRect, color: PColor) {
            ctx.setFillColor(color.cgColor)
            ctx.fill(rect)
        }

        func fillRoundedRect(_ rect: CGRect, color: PColor, radius: CGFloat) {
            ctx.setFillColor(color.cgColor)
            let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            ctx.addPath(path)
            ctx.fillPath()
        }

        func drawText(_ text: String, at point: CGPoint, attributes: [NSAttributedString.Key: Any]) {
            let attrString = NSAttributedString(string: text, attributes: attributes)
            let line = CTLineCreateWithAttributedString(attrString)
            ctx.textPosition = point
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

        func strokeLine(from: CGPoint, to: CGPoint, color: PColor, width: CGFloat, dashed: Bool = false) {
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(width)
            if dashed {
                ctx.setLineDash(phase: 0, lengths: [4, 4])
            } else {
                ctx.setLineDash(phase: 0, lengths: [])
            }
            ctx.move(to: from)
            ctx.addLine(to: to)
            ctx.strokePath()
        }

        func drawHeader() {
            fillRect(CGRect(x: 0, y: pageSize.height - 40, width: pageSize.width, height: 40), color: brandColor)
            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: PFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: PColor.white
            ]
            drawText("Trip Simulation Report", at: CGPoint(x: margin, y: pageSize.height - 28), attributes: headerAttrs)

            let wellAttrs: [NSAttributedString.Key: Any] = [
                .font: PFont.systemFont(ofSize: 10, weight: .regular),
                .foregroundColor: PColor.white.withAlphaComponent(0.9)
            ]
            drawText(data.wellName, in: CGRect(x: pageSize.width/2, y: pageSize.height - 28, width: pageSize.width/2 - margin, height: 14), attributes: wellAttrs, alignment: .right)
        }

        func startPage() {
            ctx.beginPDFPage(nil)
            drawHeader()
        }

        func endPage() {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: PFont.systemFont(ofSize: 8),
                .foregroundColor: PColor.gray
            ]
            drawText("Page \(currentPage)", in: CGRect(x: 0, y: 20, width: pageSize.width, height: 12), attributes: attrs, alignment: .center)

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
            drawText("Generated: \(dateFormatter.string(from: data.generatedDate)) | Josh Well Control",
                    in: CGRect(x: margin, y: 32, width: contentWidth, height: 10),
                    attributes: attrs, alignment: .center)

            ctx.endPDFPage()
        }

        func checkPageBreak(neededHeight: CGFloat) {
            if y - neededHeight < pageBottom {
                endPage()
                currentPage += 1
                startPage()
                y = pageSize.height - 55
            }
        }

        // MARK: - Chart Drawing

        func drawLineChart(
            in rect: CGRect,
            title: String,
            xValues: [Double],
            yDataSets: [(values: [Double], color: PColor, label: String)],
            xLabel: String,
            yLabel: String,
            invertX: Bool = true // For depth charts where we want high depth at bottom
        ) {
            let chartMargin: CGFloat = 45
            let chartRect = CGRect(
                x: rect.minX + chartMargin,
                y: rect.minY + 25,
                width: rect.width - chartMargin - 10,
                height: rect.height - 50
            )

            // Background
            fillRoundedRect(rect, color: PColor(white: 0.98, alpha: 1.0), radius: 4)

            // Title
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: PFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: PColor.darkGray
            ]
            drawText(title, in: CGRect(x: rect.minX, y: rect.maxY - 18, width: rect.width, height: 14), attributes: titleAttrs, alignment: .center)

            // Get ranges
            let xMin = xValues.min() ?? 0
            let xMax = xValues.max() ?? 1
            var yMin = Double.infinity
            var yMax = -Double.infinity
            for dataSet in yDataSets {
                if let min = dataSet.values.min(), min < yMin { yMin = min }
                if let max = dataSet.values.max(), max > yMax { yMax = max }
            }
            // Add some padding to y range
            let yPadding = (yMax - yMin) * 0.1
            yMin -= yPadding
            yMax += yPadding
            if yMin == yMax { yMax = yMin + 1 }

            // Draw axes
            let axisColor = PColor.gray
            strokeLine(from: CGPoint(x: chartRect.minX, y: chartRect.minY),
                      to: CGPoint(x: chartRect.minX, y: chartRect.maxY),
                      color: axisColor, width: 1)
            strokeLine(from: CGPoint(x: chartRect.minX, y: chartRect.minY),
                      to: CGPoint(x: chartRect.maxX, y: chartRect.minY),
                      color: axisColor, width: 1)

            // Draw grid lines and labels
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: PFont.systemFont(ofSize: 7),
                .foregroundColor: PColor.gray
            ]

            // Y-axis labels (5 ticks)
            for i in 0...4 {
                let yVal = yMin + (yMax - yMin) * Double(i) / 4.0
                let yPos = chartRect.minY + chartRect.height * CGFloat(i) / 4.0
                strokeLine(from: CGPoint(x: chartRect.minX - 3, y: yPos),
                          to: CGPoint(x: chartRect.minX, y: yPos),
                          color: axisColor, width: 0.5)
                // Grid line
                strokeLine(from: CGPoint(x: chartRect.minX, y: yPos),
                          to: CGPoint(x: chartRect.maxX, y: yPos),
                          color: PColor.lightGray.withAlphaComponent(0.5), width: 0.5, dashed: true)
                let labelStr = yVal >= 100 ? String(format: "%.0f", yVal) : String(format: "%.1f", yVal)
                drawText(labelStr, in: CGRect(x: rect.minX + 2, y: yPos - 4, width: chartMargin - 8, height: 10), attributes: labelAttrs, alignment: .right)
            }

            // X-axis labels (5 ticks)
            for i in 0...4 {
                let xVal = invertX ? (xMax - (xMax - xMin) * Double(i) / 4.0) : (xMin + (xMax - xMin) * Double(i) / 4.0)
                let xPos = chartRect.minX + chartRect.width * CGFloat(i) / 4.0
                strokeLine(from: CGPoint(x: xPos, y: chartRect.minY),
                          to: CGPoint(x: xPos, y: chartRect.minY - 3),
                          color: axisColor, width: 0.5)
                let labelStr = String(format: "%.0f", xVal)
                drawText(labelStr, in: CGRect(x: xPos - 20, y: chartRect.minY - 14, width: 40, height: 10), attributes: labelAttrs, alignment: .center)
            }

            // Axis labels
            let axisLabelAttrs: [NSAttributedString.Key: Any] = [
                .font: PFont.systemFont(ofSize: 8, weight: .medium),
                .foregroundColor: PColor.darkGray
            ]
            drawText(xLabel, in: CGRect(x: chartRect.minX, y: rect.minY + 2, width: chartRect.width, height: 12), attributes: axisLabelAttrs, alignment: .center)

            // Draw data lines
            for dataSet in yDataSets {
                guard dataSet.values.count == xValues.count, dataSet.values.count > 1 else { continue }

                ctx.setStrokeColor(dataSet.color.cgColor)
                ctx.setLineWidth(1.5)
                ctx.setLineDash(phase: 0, lengths: [])

                var started = false
                for i in 0..<xValues.count {
                    let xNorm = invertX ? (xMax - xValues[i]) / (xMax - xMin) : (xValues[i] - xMin) / (xMax - xMin)
                    let yNorm = (dataSet.values[i] - yMin) / (yMax - yMin)

                    let px = chartRect.minX + chartRect.width * CGFloat(xNorm)
                    let py = chartRect.minY + chartRect.height * CGFloat(yNorm)

                    if !started {
                        ctx.move(to: CGPoint(x: px, y: py))
                        started = true
                    } else {
                        ctx.addLine(to: CGPoint(x: px, y: py))
                    }
                }
                ctx.strokePath()
            }

            // Legend
            var legendX = chartRect.minX
            let legendY = rect.maxY - 32
            for dataSet in yDataSets {
                ctx.setFillColor(dataSet.color.cgColor)
                ctx.fill(CGRect(x: legendX, y: legendY, width: 12, height: 3))
                legendX += 14
                let legendAttrs: [NSAttributedString.Key: Any] = [
                    .font: PFont.systemFont(ofSize: 7),
                    .foregroundColor: PColor.darkGray
                ]
                drawText(dataSet.label, at: CGPoint(x: legendX, y: legendY - 2), attributes: legendAttrs)
                legendX += CGFloat(dataSet.label.count * 5 + 15)
            }
        }

        // MARK: - Fonts

        let headerFont = PFont.systemFont(ofSize: 13, weight: .semibold)
        let labelFont = PFont.systemFont(ofSize: 9, weight: .regular)
        let valueFont = PFont.systemFont(ofSize: 9, weight: .medium)
        let tableHeaderFont = PFont.systemFont(ofSize: 7, weight: .semibold)
        let tableFont = PFont.systemFont(ofSize: 7, weight: .regular)

        let darkGray = PColor.darkGray
        let lightGray = PColor.lightGray

        // ========================================
        // MARK: - Page 1: Summary
        // ========================================

        startPage()
        y = pageSize.height - 55

        let sectionHeaderAttrs: [NSAttributedString.Key: Any] = [
            .font: headerFont,
            .foregroundColor: brandColor
        ]
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: darkGray
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: PColor.black
        ]

        // Well Info Section
        drawText("Well Information", at: CGPoint(x: margin, y: y), attributes: sectionHeaderAttrs)
        y -= 16

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy, HH:mm"

        drawText("Well:", at: CGPoint(x: margin, y: y), attributes: labelAttrs)
        drawText(data.wellName, at: CGPoint(x: margin + 50, y: y), attributes: valueAttrs)
        drawText("Project:", at: CGPoint(x: pageSize.width / 2, y: y), attributes: labelAttrs)
        drawText(data.projectName, at: CGPoint(x: pageSize.width / 2 + 50, y: y), attributes: valueAttrs)
        y -= 12
        drawText("Date:", at: CGPoint(x: margin, y: y), attributes: labelAttrs)
        drawText(dateFormatter.string(from: data.generatedDate), at: CGPoint(x: margin + 50, y: y), attributes: valueAttrs)
        let direction = data.startMD > data.endMD ? "POOH (Pull Out Of Hole)" : "RIH (Run In Hole)"
        drawText("Trip:", at: CGPoint(x: pageSize.width / 2, y: y), attributes: labelAttrs)
        drawText(direction, at: CGPoint(x: pageSize.width / 2 + 50, y: y), attributes: valueAttrs)

        y -= 8
        strokeLine(from: CGPoint(x: margin, y: y), to: CGPoint(x: pageSize.width - margin, y: y), color: lightGray, width: 0.5)
        y -= 14

        // Simulation Parameters - compact 2-column layout
        drawText("Simulation Parameters", at: CGPoint(x: margin, y: y), attributes: sectionHeaderAttrs)
        y -= 14

        let col1 = margin
        let col2 = margin + 100
        let col3 = pageSize.width / 2 + 10
        let col4 = pageSize.width / 2 + 110

        let params: [(String, String, String, String)] = [
            ("Start MD:", String(format: "%.0f m", data.startMD), "End MD:", String(format: "%.0f m", data.endMD)),
            ("Control MD:", String(format: "%.0f m", data.controlMD), "Step Size:", String(format: "%.0f m", data.stepSize)),
            ("Base Mud:", String(format: "%.0f kg/m³", data.baseMudDensity), "Backfill:", String(format: "%.0f kg/m³", data.backfillDensity)),
            ("Target ESD:", String(format: "%.0f kg/m³", data.targetESD), "Crack Float:", String(format: "%.0f kPa", data.crackFloat)),
            ("Initial SABP:", String(format: "%.0f kPa", data.initialSABP), "Trip Speed:", String(format: "%.1f m/min", data.tripSpeed)),
        ]

        for (l1, v1, l2, v2) in params {
            drawText(l1, at: CGPoint(x: col1, y: y), attributes: labelAttrs)
            drawText(v1, at: CGPoint(x: col2, y: y), attributes: valueAttrs)
            drawText(l2, at: CGPoint(x: col3, y: y), attributes: labelAttrs)
            drawText(v2, at: CGPoint(x: col4, y: y), attributes: valueAttrs)
            y -= 11
        }

        y -= 8
        strokeLine(from: CGPoint(x: margin, y: y), to: CGPoint(x: pageSize.width - margin, y: y), color: lightGray, width: 0.5)
        y -= 14

        // Safety Summary - Key metrics boxes
        drawText("Safety Summary", at: CGPoint(x: margin, y: y), attributes: sectionHeaderAttrs)
        y -= 10

        let boxWidth: CGFloat = (contentWidth - 24) / 4
        let boxHeight: CGFloat = 55
        let boxY = y - boxHeight

        let metricTitleAttrs: [NSAttributedString.Key: Any] = [
            .font: PFont.systemFont(ofSize: 8, weight: .medium),
            .foregroundColor: darkGray
        ]
        let metricValueAttrs: [NSAttributedString.Key: Any] = [
            .font: PFont.systemFont(ofSize: 15, weight: .bold),
            .foregroundColor: safeColor
        ]
        let metricUnitAttrs: [NSAttributedString.Key: Any] = [
            .font: PFont.systemFont(ofSize: 7),
            .foregroundColor: darkGray
        ]

        // Box 1: ESD Range
        fillRoundedRect(CGRect(x: margin, y: boxY, width: boxWidth, height: boxHeight), color: PColor(white: 0.96, alpha: 1.0), radius: 4)
        drawText("ESD Range", in: CGRect(x: margin, y: boxY + boxHeight - 14, width: boxWidth, height: 12), attributes: metricTitleAttrs, alignment: .center)
        drawText(String(format: "%.0f - %.0f", data.minESD, data.maxESD), in: CGRect(x: margin, y: boxY + 16, width: boxWidth, height: 18), attributes: metricValueAttrs, alignment: .center)
        drawText("kg/m³", in: CGRect(x: margin, y: boxY + 4, width: boxWidth, height: 10), attributes: metricUnitAttrs, alignment: .center)

        // Box 2: Max Static SABP
        let box2X = margin + boxWidth + 8
        fillRoundedRect(CGRect(x: box2X, y: boxY, width: boxWidth, height: boxHeight), color: PColor(white: 0.96, alpha: 1.0), radius: 4)
        drawText("Max Static SABP", in: CGRect(x: box2X, y: boxY + boxHeight - 14, width: boxWidth, height: 12), attributes: metricTitleAttrs, alignment: .center)
        drawText(String(format: "%.0f", data.maxStaticSABP), in: CGRect(x: box2X, y: boxY + 16, width: boxWidth, height: 18), attributes: metricValueAttrs, alignment: .center)
        drawText("kPa", in: CGRect(x: box2X, y: boxY + 4, width: boxWidth, height: 10), attributes: metricUnitAttrs, alignment: .center)

        // Box 3: Max Dynamic SABP
        let box3X = margin + 2 * (boxWidth + 8)
        fillRoundedRect(CGRect(x: box3X, y: boxY, width: boxWidth, height: boxHeight), color: PColor(white: 0.96, alpha: 1.0), radius: 4)
        let dynamicColor = data.maxDynamicSABP > 50 ? warningColor : safeColor
        let dynamicValueAttrs: [NSAttributedString.Key: Any] = [
            .font: PFont.systemFont(ofSize: 15, weight: .bold),
            .foregroundColor: dynamicColor
        ]
        drawText("Max Dynamic SABP", in: CGRect(x: box3X, y: boxY + boxHeight - 14, width: boxWidth, height: 12), attributes: metricTitleAttrs, alignment: .center)
        drawText(String(format: "%.0f", data.maxDynamicSABP), in: CGRect(x: box3X, y: boxY + 16, width: boxWidth, height: 18), attributes: dynamicValueAttrs, alignment: .center)
        drawText("kPa", in: CGRect(x: box3X, y: boxY + 4, width: boxWidth, height: 10), attributes: metricUnitAttrs, alignment: .center)

        // Box 4: Total Backfill
        let box4X = margin + 3 * (boxWidth + 8)
        fillRoundedRect(CGRect(x: box4X, y: boxY, width: boxWidth, height: boxHeight), color: PColor(white: 0.96, alpha: 1.0), radius: 4)
        drawText("Total Backfill", in: CGRect(x: box4X, y: boxY + boxHeight - 14, width: boxWidth, height: 12), attributes: metricTitleAttrs, alignment: .center)
        drawText(String(format: "%.1f", data.totalBackfill), in: CGRect(x: box4X, y: boxY + 16, width: boxWidth, height: 18), attributes: metricValueAttrs, alignment: .center)
        drawText("m³", in: CGRect(x: box4X, y: boxY + 4, width: boxWidth, height: 10), attributes: metricUnitAttrs, alignment: .center)

        y = boxY - 12

        // Second row of metrics
        let smallBoxWidth: CGFloat = (contentWidth - 16) / 3
        let smallBoxHeight: CGFloat = 42
        let smallBoxY = y - smallBoxHeight

        fillRoundedRect(CGRect(x: margin, y: smallBoxY, width: smallBoxWidth, height: smallBoxHeight), color: PColor(white: 0.96, alpha: 1.0), radius: 4)
        drawText("Initial Pit Gain", in: CGRect(x: margin, y: smallBoxY + smallBoxHeight - 13, width: smallBoxWidth, height: 11), attributes: metricTitleAttrs, alignment: .center)
        let smallValueAttrs: [NSAttributedString.Key: Any] = [
            .font: PFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: safeColor
        ]
        drawText(String(format: "%.2f m³", data.totalPitGain), in: CGRect(x: margin, y: smallBoxY + 6, width: smallBoxWidth, height: 14), attributes: smallValueAttrs, alignment: .center)

        let smallBox2X = margin + smallBoxWidth + 8
        fillRoundedRect(CGRect(x: smallBox2X, y: smallBoxY, width: smallBoxWidth, height: smallBoxHeight), color: PColor(white: 0.96, alpha: 1.0), radius: 4)
        drawText("Net Tank Change", in: CGRect(x: smallBox2X, y: smallBoxY + smallBoxHeight - 13, width: smallBoxWidth, height: 11), attributes: metricTitleAttrs, alignment: .center)
        let tankValColor = data.netTankChange >= 0 ? safeColor : dangerColor
        let tankValAttrs: [NSAttributedString.Key: Any] = [
            .font: PFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: tankValColor
        ]
        drawText(String(format: "%+.1f m³", data.netTankChange), in: CGRect(x: smallBox2X, y: smallBoxY + 6, width: smallBoxWidth, height: 14), attributes: tankValAttrs, alignment: .center)

        let smallBox3X = margin + 2 * (smallBoxWidth + 8)
        fillRoundedRect(CGRect(x: smallBox3X, y: smallBoxY, width: smallBoxWidth, height: smallBoxHeight), color: PColor(white: 0.96, alpha: 1.0), radius: 4)
        drawText("Number of Steps", in: CGRect(x: smallBox3X, y: smallBoxY + smallBoxHeight - 13, width: smallBoxWidth, height: 11), attributes: metricTitleAttrs, alignment: .center)
        drawText("\(data.steps.count)", in: CGRect(x: smallBox3X, y: smallBoxY + 6, width: smallBoxWidth, height: 14), attributes: smallValueAttrs, alignment: .center)

        y = smallBoxY - 8
        strokeLine(from: CGPoint(x: margin, y: y), to: CGPoint(x: pageSize.width - margin, y: y), color: lightGray, width: 0.5)
        y -= 14

        // Recommendations
        drawText("Recommendations", at: CGPoint(x: margin, y: y), attributes: sectionHeaderAttrs)
        y -= 14

        let bulletAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: PColor.black
        ]

        var recommendations: [String] = []
        if data.maxStaticSABP > 0 {
            recommendations.append("Maintain minimum SABP of \(String(format: "%.0f", data.maxStaticSABP)) kPa throughout trip")
        }
        if data.maxDynamicSABP > data.maxStaticSABP + 5 {
            recommendations.append("Account for dynamic swab pressure up to \(String(format: "%.0f", data.maxDynamicSABP)) kPa")
        }
        recommendations.append("Prepare \(String(format: "%.1f", data.totalBackfill)) m³ backfill at \(String(format: "%.0f", data.backfillDensity)) kg/m³")
        if data.totalPitGain > 0.05 {
            recommendations.append("Expect ~\(String(format: "%.2f", data.totalPitGain)) m³ pit gain during initial equalization")
        }
        recommendations.append("Monitor ESD within \(String(format: "%.0f", data.minESD))-\(String(format: "%.0f", data.maxESD)) kg/m³ window")

        for rec in recommendations {
            drawText("• \(rec)", at: CGPoint(x: margin + 8, y: y), attributes: bulletAttrs)
            y -= 12
        }

        endPage()

        // ========================================
        // MARK: - Page 2: Charts
        // ========================================

        currentPage += 1
        startPage()
        y = pageSize.height - 55

        drawText("Trip Profile Charts", at: CGPoint(x: margin, y: y), attributes: sectionHeaderAttrs)
        y -= 10

        let chartHeight: CGFloat = 160
        let chartWidth = (contentWidth - 10) / 2

        // Prepare data arrays
        let depths = data.steps.map { $0.bitMD_m }
        let esds = data.steps.map { $0.ESDatTD_kgpm3 }
        let staticSABPs = data.steps.map { $0.SABP_kPa }
        let dynamicSABPs = data.steps.map { $0.SABP_Dynamic_kPa }
        let tankDeltas = data.steps.map { $0.cumulativeSurfaceTankDelta_m3 }
        let cumBackfills = data.steps.map { $0.cumulativeBackfill_m3 }

        // Chart 1: ESD vs Depth
        let chart1Rect = CGRect(x: margin, y: y - chartHeight, width: chartWidth, height: chartHeight)
        drawLineChart(
            in: chart1Rect,
            title: "ESD vs Depth",
            xValues: depths,
            yDataSets: [(esds, esdColor, "ESD (kg/m³)")],
            xLabel: "Measured Depth (m)",
            yLabel: "ESD"
        )

        // Chart 2: SABP vs Depth
        let chart2Rect = CGRect(x: margin + chartWidth + 10, y: y - chartHeight, width: chartWidth, height: chartHeight)
        drawLineChart(
            in: chart2Rect,
            title: "SABP vs Depth",
            xValues: depths,
            yDataSets: [
                (staticSABPs, staticSABPColor, "Static"),
                (dynamicSABPs, dynamicSABPColor, "Dynamic")
            ],
            xLabel: "Measured Depth (m)",
            yLabel: "SABP"
        )

        y -= chartHeight + 20

        // Chart 3: Tank Change vs Depth
        let chart3Rect = CGRect(x: margin, y: y - chartHeight, width: chartWidth, height: chartHeight)
        drawLineChart(
            in: chart3Rect,
            title: "Tank Volume Change vs Depth",
            xValues: depths,
            yDataSets: [(tankDeltas, tankColor, "Tank Δ (m³)")],
            xLabel: "Measured Depth (m)",
            yLabel: "Volume"
        )

        // Chart 4: Cumulative Backfill vs Depth
        let chart4Rect = CGRect(x: margin + chartWidth + 10, y: y - chartHeight, width: chartWidth, height: chartHeight)
        drawLineChart(
            in: chart4Rect,
            title: "Cumulative Backfill vs Depth",
            xValues: depths,
            yDataSets: [(cumBackfills, fillColor, "Backfill (m³)")],
            xLabel: "Measured Depth (m)",
            yLabel: "Volume"
        )

        y -= chartHeight + 20

        // Chart interpretation notes
        strokeLine(from: CGPoint(x: margin, y: y), to: CGPoint(x: pageSize.width - margin, y: y), color: lightGray, width: 0.5)
        y -= 14
        drawText("Chart Interpretation", at: CGPoint(x: margin, y: y), attributes: sectionHeaderAttrs)
        y -= 14

        let noteAttrs: [NSAttributedString.Key: Any] = [
            .font: PFont.systemFont(ofSize: 8),
            .foregroundColor: darkGray
        ]
        let notes = [
            "• ESD increases as heavy slug drains into pocket below bit during POOH",
            "• Dynamic SABP shows additional pressure from swab effects during pipe movement",
            "• Tank volume decreases as backfill is pumped; positive values indicate pit gain",
            "• Backfill accumulates as trip progresses; compare with theoretical fill requirements"
        ]
        for note in notes {
            drawText(note, at: CGPoint(x: margin + 8, y: y), attributes: noteAttrs)
            y -= 10
        }

        endPage()

        // ========================================
        // MARK: - Page 3: Geometry & Wellbore Schematic
        // ========================================

        currentPage += 1
        startPage()
        y = pageSize.height - 55

        drawText("Well Geometry", at: CGPoint(x: margin, y: y), attributes: sectionHeaderAttrs)
        y -= 18

        // Drill String Table
        drawText("Drill String", at: CGPoint(x: margin, y: y), attributes: [
            .font: PFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: darkGray
        ])
        y -= 14

        if !data.drillStringSections.isEmpty {
            let dsColumns: [(title: String, width: CGFloat)] = [
                ("Section", 80),
                ("Top (m)", 50),
                ("Bot (m)", 50),
                ("OD (mm)", 50),
                ("ID (mm)", 50),
                ("Cap (m³/m)", 60),
                ("Disp (m³/m)", 60),
                ("Vol (m³)", 50)
            ]
            let dsTableWidth = dsColumns.reduce(0) { $0 + $1.width }
            let dsTableX = margin

            // Header
            fillRoundedRect(CGRect(x: dsTableX, y: y - 14, width: dsTableWidth, height: 14), color: brandColor, radius: 2)
            var xPos = dsTableX + 2
            for (title, width) in dsColumns {
                let attrs: [NSAttributedString.Key: Any] = [.font: PFont.systemFont(ofSize: 7, weight: .semibold), .foregroundColor: PColor.white]
                drawText(title, in: CGRect(x: xPos, y: y - 11, width: width - 4, height: 10), attributes: attrs, alignment: .center)
                xPos += width
            }
            y -= 15

            // Rows
            for (i, section) in data.drillStringSections.enumerated() {
                if i % 2 == 1 {
                    fillRect(CGRect(x: dsTableX, y: y - 11, width: dsTableWidth, height: 11), color: PColor(white: 0.97, alpha: 1.0))
                }
                xPos = dsTableX + 2
                let cellAttrs: [NSAttributedString.Key: Any] = [.font: PFont.systemFont(ofSize: 7), .foregroundColor: PColor.black]
                let values: [String] = [
                    section.name,
                    String(format: "%.0f", section.topMD),
                    String(format: "%.0f", section.bottomMD),
                    String(format: "%.1f", section.outerDiameter * 1000),
                    String(format: "%.1f", section.innerDiameter * 1000),
                    String(format: "%.4f", section.capacity_m3_per_m),
                    String(format: "%.4f", section.displacement_m3_per_m),
                    String(format: "%.2f", section.totalVolume)
                ]
                for (j, val) in values.enumerated() {
                    drawText(val, in: CGRect(x: xPos, y: y - 9, width: dsColumns[j].width - 4, height: 8), attributes: cellAttrs, alignment: j == 0 ? .left : .right)
                    xPos += dsColumns[j].width
                }
                y -= 11
            }

            // Totals row
            fillRect(CGRect(x: dsTableX, y: y - 12, width: dsTableWidth, height: 12), color: PColor(white: 0.92, alpha: 1.0))
            let totalAttrs: [NSAttributedString.Key: Any] = [.font: PFont.systemFont(ofSize: 7, weight: .semibold), .foregroundColor: PColor.black]
            drawText("TOTAL", at: CGPoint(x: dsTableX + 4, y: y - 9), attributes: totalAttrs)
            drawText(String(format: "%.2f", data.totalStringCapacity), in: CGRect(x: dsTableX + dsTableWidth - 54, y: y - 9, width: 50, height: 8), attributes: totalAttrs, alignment: .right)
            y -= 18
        } else {
            drawText("No drill string sections defined", at: CGPoint(x: margin + 8, y: y), attributes: noteAttrs)
            y -= 14
        }

        // Annulus Table
        drawText("Annulus", at: CGPoint(x: margin, y: y), attributes: [
            .font: PFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: darkGray
        ])
        y -= 14

        if !data.annulusSections.isEmpty {
            let annColumns: [(title: String, width: CGFloat)] = [
                ("Section", 80),
                ("Top (m)", 50),
                ("Bot (m)", 50),
                ("Hole ID (mm)", 60),
                ("Pipe OD (mm)", 60),
                ("Cap (m³/m)", 60),
                ("Vol (m³)", 50)
            ]
            let annTableWidth = annColumns.reduce(0) { $0 + $1.width }
            let annTableX = margin

            // Header
            fillRoundedRect(CGRect(x: annTableX, y: y - 14, width: annTableWidth, height: 14), color: brandColor, radius: 2)
            var xPos = annTableX + 2
            for (title, width) in annColumns {
                let attrs: [NSAttributedString.Key: Any] = [.font: PFont.systemFont(ofSize: 7, weight: .semibold), .foregroundColor: PColor.white]
                drawText(title, in: CGRect(x: xPos, y: y - 11, width: width - 4, height: 10), attributes: attrs, alignment: .center)
                xPos += width
            }
            y -= 15

            // Rows
            for (i, section) in data.annulusSections.enumerated() {
                if i % 2 == 1 {
                    fillRect(CGRect(x: annTableX, y: y - 11, width: annTableWidth, height: 11), color: PColor(white: 0.97, alpha: 1.0))
                }
                xPos = annTableX + 2
                let cellAttrs: [NSAttributedString.Key: Any] = [.font: PFont.systemFont(ofSize: 7), .foregroundColor: PColor.black]
                let values: [String] = [
                    section.name,
                    String(format: "%.0f", section.topMD),
                    String(format: "%.0f", section.bottomMD),
                    String(format: "%.1f", section.innerDiameter * 1000),
                    String(format: "%.1f", section.outerDiameter * 1000),
                    String(format: "%.4f", section.capacity_m3_per_m),
                    String(format: "%.2f", section.totalVolume)
                ]
                for (j, val) in values.enumerated() {
                    drawText(val, in: CGRect(x: xPos, y: y - 9, width: annColumns[j].width - 4, height: 8), attributes: cellAttrs, alignment: j == 0 ? .left : .right)
                    xPos += annColumns[j].width
                }
                y -= 11
            }

            // Totals row
            fillRect(CGRect(x: annTableX, y: y - 12, width: annTableWidth, height: 12), color: PColor(white: 0.92, alpha: 1.0))
            let totalAttrs: [NSAttributedString.Key: Any] = [.font: PFont.systemFont(ofSize: 7, weight: .semibold), .foregroundColor: PColor.black]
            drawText("TOTAL", at: CGPoint(x: annTableX + 4, y: y - 9), attributes: totalAttrs)
            drawText(String(format: "%.2f", data.totalAnnulusCapacity), in: CGRect(x: annTableX + annTableWidth - 54, y: y - 9, width: 50, height: 8), attributes: totalAttrs, alignment: .right)
            y -= 18
        } else {
            drawText("No annulus sections defined", at: CGPoint(x: margin + 8, y: y), attributes: noteAttrs)
            y -= 14
        }

        // Volume Summary Box - positioned on left
        y -= 10
        let summaryBoxWidth: CGFloat = 200
        let summaryBoxHeight: CGFloat = 70
        let summaryBoxY = y - summaryBoxHeight
        fillRoundedRect(CGRect(x: margin, y: summaryBoxY, width: summaryBoxWidth, height: summaryBoxHeight), color: PColor(white: 0.96, alpha: 1.0), radius: 4)
        drawText("Volume Summary", in: CGRect(x: margin, y: y - 14, width: summaryBoxWidth, height: 12), attributes: [
            .font: PFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: brandColor
        ], alignment: .center)
        let summaryAttrs: [NSAttributedString.Key: Any] = [.font: PFont.systemFont(ofSize: 8), .foregroundColor: darkGray]
        let summaryValAttrs: [NSAttributedString.Key: Any] = [.font: PFont.systemFont(ofSize: 8, weight: .semibold), .foregroundColor: PColor.black]
        drawText("String Capacity:", at: CGPoint(x: margin + 8, y: y - 28), attributes: summaryAttrs)
        drawText(String(format: "%.2f m³", data.totalStringCapacity), at: CGPoint(x: margin + 100, y: y - 28), attributes: summaryValAttrs)
        drawText("String Displacement:", at: CGPoint(x: margin + 8, y: y - 40), attributes: summaryAttrs)
        drawText(String(format: "%.2f m³", data.totalStringDisplacement), at: CGPoint(x: margin + 100, y: y - 40), attributes: summaryValAttrs)
        drawText("Annulus Capacity:", at: CGPoint(x: margin + 8, y: y - 52), attributes: summaryAttrs)
        drawText(String(format: "%.2f m³", data.totalAnnulusCapacity), at: CGPoint(x: margin + 100, y: y - 52), attributes: summaryValAttrs)
        drawText("Total System:", at: CGPoint(x: margin + 8, y: y - 64), attributes: summaryAttrs)
        drawText(String(format: "%.2f m³", data.totalStringCapacity + data.totalAnnulusCapacity), at: CGPoint(x: margin + 100, y: y - 64), attributes: summaryValAttrs)

        y = summaryBoxY - 20

        // ========================================
        // MARK: - Wellbore Schematic (Before & After) - Full Width Below Tables
        // ========================================

        strokeLine(from: CGPoint(x: margin, y: y + 8), to: CGPoint(x: pageSize.width - margin, y: y + 8), color: lightGray, width: 0.5)

        drawText("Well Snapshot - Before & After Trip", at: CGPoint(x: margin, y: y), attributes: sectionHeaderAttrs)
        y -= 16

        // Get first and last steps for before/after visualization
        guard let firstStep = data.steps.first, let lastStep = data.steps.last else {
            drawText("No simulation data available", at: CGPoint(x: margin + 8, y: y), attributes: noteAttrs)
            endPage()
            currentPage += 1
            startPage()
            y = pageSize.height - 55
            drawText("Step-by-Step Data", at: CGPoint(x: margin, y: y), attributes: sectionHeaderAttrs)
            y -= 18
            // Continue with data table...
            let tableHeaderAttrs2: [NSAttributedString.Key: Any] = [
                .font: tableHeaderFont,
                .foregroundColor: PColor.white
            ]
            let tableCellAttrs2: [NSAttributedString.Key: Any] = [
                .font: tableFont,
                .foregroundColor: PColor.black
            ]
            _ = tableHeaderAttrs2
            _ = tableCellAttrs2
            ctx.closePDF()
            return pdfData as Data
        }

        // Calculate max depth from all layers
        let maxPocketMD = lastStep.layersPocket.map { $0.bottomMD }.max() ?? lastStep.bitMD_m
        let maxDepth = max(firstStep.bitMD_m, maxPocketMD, data.startMD)
        guard maxDepth > 0 else {
            endPage()
            currentPage += 1
            startPage()
            y = pageSize.height - 55
            drawText("Step-by-Step Data", at: CGPoint(x: margin, y: y), attributes: sectionHeaderAttrs)
            y -= 18
            ctx.closePDF()
            return pdfData as Data
        }

        // Layout: Two side-by-side well snapshots (Before | After)
        let snapshotHeight: CGFloat = 220
        let snapshotWidth = (contentWidth - 30) / 2
        let beforeRect = CGRect(x: margin, y: y - snapshotHeight, width: snapshotWidth, height: snapshotHeight)
        let afterRect = CGRect(x: margin + snapshotWidth + 30, y: y - snapshotHeight, width: snapshotWidth, height: snapshotHeight)

        // Helper to convert layer color to PColor
        func layerColor(_ layer: NumericalTripModel.LayerRow) -> PColor {
            if let c = layer.color {
                return PColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
            }
            // Fallback: grayscale based on density
            let t = min(max((layer.rho_kgpm3 - 800) / 1200, 0), 1)
            return PColor(white: 0.3 + 0.6 * t, alpha: 1.0)
        }

        // Helper to draw a well snapshot (3-column: Annulus | String | Annulus)
        func drawWellSnapshot(in rect: CGRect, step: NumericalTripModel.TripStep, title: String) {
            // Background
            fillRoundedRect(rect, color: PColor(white: 0.15, alpha: 1.0), radius: 4)

            // Title
            let titleAttrs: [NSAttributedString.Key: Any] = [.font: PFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: PColor.white]
            drawText(title, in: CGRect(x: rect.minX, y: rect.maxY - 14, width: rect.width, height: 12), attributes: titleAttrs, alignment: .center)

            // Column layout
            let headerHeight: CGFloat = 20
            let gap: CGFloat = 2
            let colW = (rect.width - 2 * gap - 8) / 3
            let drawAreaTop = rect.maxY - headerHeight - 4
            let drawAreaBottom = rect.minY + 20
            let drawAreaHeight = drawAreaTop - drawAreaBottom

            let annLeftRect = CGRect(x: rect.minX + 4, y: drawAreaBottom, width: colW, height: drawAreaHeight)
            let strRect = CGRect(x: rect.minX + 4 + colW + gap, y: drawAreaBottom, width: colW, height: drawAreaHeight)
            let annRightRect = CGRect(x: rect.minX + 4 + 2 * (colW + gap), y: drawAreaBottom, width: colW, height: drawAreaHeight)

            // Column headers
            let colHeaderAttrs: [NSAttributedString.Key: Any] = [.font: PFont.systemFont(ofSize: 6), .foregroundColor: PColor.white.withAlphaComponent(0.8)]
            drawText("Annulus", in: CGRect(x: annLeftRect.minX, y: drawAreaTop + 2, width: colW, height: 10), attributes: colHeaderAttrs, alignment: .center)
            drawText("String", in: CGRect(x: strRect.minX, y: drawAreaTop + 2, width: colW, height: 10), attributes: colHeaderAttrs, alignment: .center)
            drawText("Annulus", in: CGRect(x: annRightRect.minX, y: drawAreaTop + 2, width: colW, height: 10), attributes: colHeaderAttrs, alignment: .center)

            // MD to Y conversion (surface at top, deeper = lower Y in PDF coords)
            func mdToY(_ md: Double) -> CGFloat {
                guard maxDepth > 0 else { return drawAreaTop }
                return drawAreaTop - CGFloat(md / maxDepth) * drawAreaHeight
            }

            // Draw column backgrounds (dark gray)
            ctx.setFillColor(PColor(white: 0.25, alpha: 1.0).cgColor)
            ctx.fill(annLeftRect)
            ctx.fill(strRect)
            ctx.fill(annRightRect)

            // Draw annulus layers (left and right columns)
            for layer in step.layersAnnulus where layer.bottomMD <= step.bitMD_m {
                let yTop = mdToY(layer.topMD)
                let yBot = mdToY(layer.bottomMD)
                let h = max(1, yTop - yBot)
                let layerRect = CGRect(x: annLeftRect.minX, y: yBot, width: colW, height: h)
                ctx.setFillColor(layerColor(layer).cgColor)
                ctx.fill(layerRect)
                // Right annulus
                let rightRect = CGRect(x: annRightRect.minX, y: yBot, width: colW, height: h)
                ctx.fill(rightRect)
            }

            // Draw string layers (center column)
            for layer in step.layersString where layer.bottomMD <= step.bitMD_m {
                let yTop = mdToY(layer.topMD)
                let yBot = mdToY(layer.bottomMD)
                let h = max(1, yTop - yBot)
                let layerRect = CGRect(x: strRect.minX, y: yBot, width: colW, height: h)
                ctx.setFillColor(layerColor(layer).cgColor)
                ctx.fill(layerRect)
            }

            // Draw pocket layers (full width below bit)
            for layer in step.layersPocket {
                let yTop = mdToY(layer.topMD)
                let yBot = mdToY(layer.bottomMD)
                let h = max(1, yTop - yBot)
                let pocketRect = CGRect(x: rect.minX + 4, y: yBot, width: rect.width - 8, height: h)
                ctx.setFillColor(layerColor(layer).cgColor)
                ctx.fill(pocketRect)
            }

            // Draw bit marker
            let bitY = mdToY(step.bitMD_m)
            ctx.setFillColor(PColor(red: 0.9, green: 0.3, blue: 0.2, alpha: 0.9).cgColor)
            ctx.fill(CGRect(x: rect.minX + 4, y: bitY - 1, width: rect.width - 8, height: 2))

            // Draw column borders
            ctx.setStrokeColor(PColor.black.cgColor)
            ctx.setLineWidth(0.5)
            ctx.stroke(annLeftRect)
            ctx.stroke(strRect)
            ctx.stroke(annRightRect)

            // Depth ticks
            let tickAttrs: [NSAttributedString.Key: Any] = [.font: PFont.systemFont(ofSize: 5), .foregroundColor: PColor.white.withAlphaComponent(0.7)]
            let tickCount = 5
            for i in 0...tickCount {
                let md = Double(i) / Double(tickCount) * maxDepth
                let yy = mdToY(md)
                // Left tick
                strokeLine(from: CGPoint(x: annLeftRect.minX, y: yy), to: CGPoint(x: annLeftRect.minX + 3, y: yy), color: PColor.white.withAlphaComponent(0.5), width: 0.5)
                // Right tick
                strokeLine(from: CGPoint(x: annRightRect.maxX - 3, y: yy), to: CGPoint(x: annRightRect.maxX, y: yy), color: PColor.white.withAlphaComponent(0.5), width: 0.5)
                // Labels
                if i > 0 {
                    drawText(String(format: "%.0f", md), at: CGPoint(x: annLeftRect.minX + 4, y: yy - 3), attributes: tickAttrs)
                    drawText(String(format: "%.0f", md), in: CGRect(x: annRightRect.maxX - 25, y: yy - 3, width: 22, height: 8), attributes: tickAttrs, alignment: .right)
                }
            }

            // Bit depth label
            let bitLabelAttrs: [NSAttributedString.Key: Any] = [.font: PFont.systemFont(ofSize: 6), .foregroundColor: PColor.white]
            drawText(String(format: "Bit: %.0f m", step.bitMD_m), in: CGRect(x: rect.minX, y: rect.minY + 4, width: rect.width, height: 10), attributes: bitLabelAttrs, alignment: .center)
        }

        // Draw Before snapshot
        drawWellSnapshot(in: beforeRect, step: firstStep, title: "BEFORE (Start)")

        // Draw After snapshot
        drawWellSnapshot(in: afterRect, step: lastStep, title: "AFTER (End)")

        // ESD labels below each snapshot
        let esdLabelAttrs: [NSAttributedString.Key: Any] = [.font: PFont.systemFont(ofSize: 7), .foregroundColor: darkGray]
        drawText(String(format: "ESD@TD: %.0f kg/m³", firstStep.ESDatTD_kgpm3), in: CGRect(x: beforeRect.minX, y: beforeRect.minY - 12, width: beforeRect.width, height: 10), attributes: esdLabelAttrs, alignment: .center)
        drawText(String(format: "ESD@TD: %.0f kg/m³", lastStep.ESDatTD_kgpm3), in: CGRect(x: afterRect.minX, y: afterRect.minY - 12, width: afterRect.width, height: 10), attributes: esdLabelAttrs, alignment: .center)

        endPage()

        // ========================================
        // MARK: - Page 4+: Data Table
        // ========================================

        currentPage += 1
        startPage()
        y = pageSize.height - 55

        drawText("Step-by-Step Data", at: CGPoint(x: margin, y: y), attributes: sectionHeaderAttrs)
        y -= 18

        let tableHeaderAttrs: [NSAttributedString.Key: Any] = [
            .font: tableHeaderFont,
            .foregroundColor: PColor.white
        ]
        let tableCellAttrs: [NSAttributedString.Key: Any] = [
            .font: tableFont,
            .foregroundColor: PColor.black
        ]

        let rowHeight: CGFloat = 12
        let headerHeight: CGFloat = 16

        let columns: [(title: String, width: CGFloat)] = [
            ("MD", 40),
            ("TVD", 40),
            ("Static", 42),
            ("Dynamic", 48),
            ("ESD", 40),
            ("DP Wet", 48),
            ("DP Dry", 48),
            ("Actual", 42),
            ("Tank Δ", 48)
        ]

        let tableWidth = columns.reduce(0) { $0 + $1.width }
        let tableX = margin + (contentWidth - tableWidth) / 2

        func drawTableHeader(at yPos: CGFloat) {
            fillRoundedRect(CGRect(x: tableX, y: yPos - headerHeight, width: tableWidth, height: headerHeight), color: brandColor, radius: 2)
            var xPos = tableX + 2
            for (title, width) in columns {
                drawText(title, in: CGRect(x: xPos, y: yPos - 12, width: width - 4, height: 10), attributes: tableHeaderAttrs, alignment: .center)
                xPos += width
            }
        }

        func drawTableRow(step: NumericalTripModel.TripStep, at yPos: CGFloat, isAlternate: Bool) {
            if isAlternate {
                fillRect(CGRect(x: tableX, y: yPos - rowHeight, width: tableWidth, height: rowHeight), color: PColor(white: 0.97, alpha: 1.0))
            }
            var xPos = tableX + 2
            let values: [String] = [
                String(format: "%.0f", step.bitMD_m),
                String(format: "%.0f", step.bitTVD_m),
                String(format: "%.0f", step.SABP_kPa),
                String(format: "%.0f", step.SABP_Dynamic_kPa),
                String(format: "%.0f", step.ESDatTD_kgpm3),
                String(format: "%.3f", step.expectedFillIfClosed_m3),
                String(format: "%.3f", step.expectedFillIfOpen_m3),
                String(format: "%.3f", step.stepBackfill_m3),
                String(format: "%+.2f", step.cumulativeSurfaceTankDelta_m3)
            ]
            for (i, value) in values.enumerated() {
                drawText(value, in: CGRect(x: xPos, y: yPos - 9, width: columns[i].width - 4, height: 8), attributes: tableCellAttrs, alignment: .right)
                xPos += columns[i].width
            }
        }

        drawTableHeader(at: y)
        y -= headerHeight + 1

        for (index, step) in data.steps.enumerated() {
            checkPageBreak(neededHeight: rowHeight + headerHeight + 15)
            if y > pageSize.height - 70 {
                drawTableHeader(at: y)
                y -= headerHeight + 1
            }
            drawTableRow(step: step, at: y, isAlternate: index % 2 == 1)
            y -= rowHeight
        }

        y -= 10
        let legendAttrs: [NSAttributedString.Key: Any] = [
            .font: PFont.systemFont(ofSize: 6),
            .foregroundColor: darkGray
        ]
        drawText("Units: MD/TVD (m), Static/Dynamic SABP (kPa), ESD (kg/m³), Fill volumes (m³), Tank Δ (m³ cumulative)", at: CGPoint(x: tableX, y: y), attributes: legendAttrs)

        endPage()
        ctx.closePDF()

        return pdfData as Data
    }
}
