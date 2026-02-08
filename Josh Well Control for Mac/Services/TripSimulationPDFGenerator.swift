//
//  TripSimulationPDFGenerator.swift
//  Josh Well Control for Mac
//
//  PDF generator for Trip Simulation reports - renders HTML to PDF
//

import Foundation
import SwiftUI
import WebKit

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

/// Final fluid layer data for reports (from Mud Placement)
struct FinalFluidLayerData {
    let name: String
    let placement: Placement  // .annulus, .string, or .both
    let topMD: Double
    let bottomMD: Double
    let density_kgm3: Double
    let colorR: Double
    let colorG: Double
    let colorB: Double
    let colorA: Double
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

    // Mud details for report
    var baseMudName: String = "Active Mud"
    var backfillMudName: String = "Backfill Mud"
    var switchToActiveAfterDisplacement: Bool = false
    var displacementSwitchVolume: Double = 0  // Volume at which to switch from backfill to active

    // Slug mud - heaviest mud in string at start (for weighted spacer/pill)
    var slugMudName: String = ""
    var slugMudDensity: Double = 0
    var slugMudVolume: Double = 0  // Volume in string at start

    // Geometry data
    let drillStringSections: [PDFSectionData]
    let annulusSections: [PDFSectionData]

    // Final fluid layers from Mud Placement (for Final Spotted Fluids section)
    var finalFluidLayers: [FinalFluidLayerData] = []

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

    // Computed backfill volumes by mud type
    var backfillMudVolume: Double {
        if switchToActiveAfterDisplacement {
            return min(totalBackfill, displacementSwitchVolume)
        }
        return totalBackfill
    }
    var activeMudBackfillVolume: Double {
        if switchToActiveAfterDisplacement {
            return max(0, totalBackfill - displacementSwitchVolume)
        }
        return 0
    }
}

/// Cross-platform PDF generator that renders HTML to PDF using WebKit
class TripSimulationPDFGenerator: NSObject, WKNavigationDelegate {
    static let shared = TripSimulationPDFGenerator()

    private override init() {
        super.init()
    }

    // Keep WebView alive during PDF generation
    private var activeWebView: WKWebView?
    private var pdfCompletion: ((Data?) -> Void)?

    /// Generate PDF by rendering HTML through WebKit
    /// - Parameters:
    ///   - data: The report data
    ///   - completion: Called with the PDF data or nil on failure
    @MainActor
    func generatePDFAsync(for data: TripSimulationReportData, completion: @escaping (Data?) -> Void) {
        // Generate HTML with print-optimized styles
        let htmlContent = generatePrintHTML(for: data)

        // Create an offscreen WebView and keep strong reference
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 612, height: 792))
        webView.navigationDelegate = self
        self.activeWebView = webView
        self.pdfCompletion = completion

        // Load HTML - delegate will handle completion
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }

    // MARK: - WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            // Small delay to ensure rendering is complete
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds

            let config = WKPDFConfiguration()
            // Don't set rect - let it capture the full content

            webView.createPDF(configuration: config) { [weak self] result in
                Task { @MainActor in
                    self?.activeWebView = nil

                    switch result {
                    case .success(let pdfData):
                        print("PDF generated successfully: \(pdfData.count) bytes")
                        self?.pdfCompletion?(pdfData)
                    case .failure(let error):
                        print("PDF generation failed: \(error)")
                        self?.pdfCompletion?(nil)
                    }
                    self?.pdfCompletion = nil
                }
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            print("WebView navigation failed: \(error)")
            self.activeWebView = nil
            self.pdfCompletion?(nil)
            self.pdfCompletion = nil
        }
    }

    /// Generate print-optimized HTML (hides interactive elements)
    private func generatePrintHTML(for data: TripSimulationReportData) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy, HH:mm"
        let dateStr = dateFormatter.string(from: data.generatedDate)

        let direction = data.startMD > data.endMD ? "POOH (Pull Out Of Hole)" : "RIH (Run In Hole)"

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Trip Simulation Report - \(escapeHTML(data.wellName))</title>
            <style>
                \(generatePrintCSS())
            </style>
        </head>
        <body>
            <header>
                <div class="header-content">
                    <h1>Trip Simulation Report</h1>
                    <span class="well-name">\(escapeHTML(data.wellName))</span>
                </div>
            </header>

            <main>
                <!-- Well Information -->
                <section class="card">
                    <h2>Well Information</h2>
                    <div class="info-grid">
                        <div class="info-item">
                            <span class="label">Well:</span>
                            <span class="value">\(escapeHTML(data.wellName))</span>
                        </div>
                        <div class="info-item">
                            <span class="label">Project:</span>
                            <span class="value">\(escapeHTML(data.projectName))</span>
                        </div>
                        <div class="info-item">
                            <span class="label">Date:</span>
                            <span class="value">\(dateStr)</span>
                        </div>
                        <div class="info-item">
                            <span class="label">Trip:</span>
                            <span class="value">\(direction)</span>
                        </div>
                    </div>
                </section>

                <!-- Simulation Parameters -->
                <section class="card">
                    <h2>Simulation Parameters</h2>
                    <div class="params-grid">
                        <div class="param-item">
                            <span class="label">Start MD:</span>
                            <span class="value">\(String(format: "%.0f m", data.startMD))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">End MD:</span>
                            <span class="value">\(String(format: "%.0f m", data.endMD))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Control MD:</span>
                            <span class="value">\(String(format: "%.0f m", data.controlMD))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Step Size:</span>
                            <span class="value">\(String(format: "%.0f m", data.stepSize))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Base Mud:</span>
                            <span class="value">\(String(format: "%.0f kg/m³", data.baseMudDensity))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Backfill:</span>
                            <span class="value">\(String(format: "%.0f kg/m³", data.backfillDensity))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Target ESD:</span>
                            <span class="value">\(String(format: "%.0f kg/m³", data.targetESD))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Crack Float:</span>
                            <span class="value">\(String(format: "%.0f kPa", data.crackFloat))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Initial SABP:</span>
                            <span class="value">\(String(format: "%.0f kPa", data.initialSABP))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Trip Speed:</span>
                            <span class="value">\(String(format: "%.1f m/min", data.tripSpeed))</span>
                        </div>
                    </div>
                </section>

                <!-- Safety Summary -->
                <section class="card">
                    <h2>Safety Summary</h2>
                    <div class="metrics-grid">
                        <div class="metric-box">
                            <div class="metric-title">ESD Range</div>
                            <div class="metric-value">\(String(format: "%.0f - %.0f", data.minESD, data.maxESD))</div>
                            <div class="metric-unit">kg/m³</div>
                        </div>
                        <div class="metric-box">
                            <div class="metric-title">Max Static SABP</div>
                            <div class="metric-value">\(String(format: "%.0f", data.maxStaticSABP))</div>
                            <div class="metric-unit">kPa</div>
                        </div>
                        <div class="metric-box \(data.maxDynamicSABP > 50 ? "warning" : "")">
                            <div class="metric-title">Max Dynamic SABP</div>
                            <div class="metric-value">\(String(format: "%.0f", data.maxDynamicSABP))</div>
                            <div class="metric-unit">kPa</div>
                        </div>
                        <div class="metric-box">
                            <div class="metric-title">Total Backfill</div>
                            <div class="metric-value">\(String(format: "%.1f", data.totalBackfill))</div>
                            <div class="metric-unit">m³</div>
                        </div>
                    </div>
                    <div class="metrics-grid secondary">
                        <div class="metric-box small">
                            <div class="metric-title">Initial Pit Gain</div>
                            <div class="metric-value">\(String(format: "%.2f m³", data.totalPitGain))</div>
                        </div>
                        <div class="metric-box small \(data.netTankChange < 0 ? "danger" : "")">
                            <div class="metric-title">Net Tank Change</div>
                            <div class="metric-value">\(String(format: "%+.1f m³", data.netTankChange))</div>
                        </div>
                        <div class="metric-box small">
                            <div class="metric-title">Number of Steps</div>
                            <div class="metric-value">\(data.steps.count)</div>
                        </div>
                    </div>
                </section>

                <!-- Charts -->
                <section class="card">
                    <h2>Trip Profile Charts</h2>
                    <div class="charts-grid">
                        \(generateSVGChart(title: "ESD vs Depth", xValues: data.steps.map { $0.bitMD_m }, datasets: [(data.steps.map { $0.ESDatTD_kgpm3 }, "#2196f3", "ESD")]))
                        \(generateSVGChart(title: "SABP vs Depth", xValues: data.steps.map { $0.bitMD_m }, datasets: [(data.steps.map { $0.SABP_kPa }, "#4caf50", "Static"), (data.steps.map { $0.SABP_Dynamic_kPa }, "#ff9800", "Dynamic")]))
                        \(generateSVGChart(title: "Tank Change vs Depth", xValues: data.steps.map { $0.bitMD_m }, datasets: [(data.steps.map { $0.cumulativeSurfaceTankDelta_m3 }, "#9c27b0", "Tank Δ")]))
                        \(generateSVGChart(title: "Cumulative Backfill", xValues: data.steps.map { $0.bitMD_m }, datasets: [(data.steps.map { $0.cumulativeBackfill_m3 }, "#009688", "Backfill")]))
                    </div>
                </section>

                <!-- Geometry Tables -->
                <section class="card">
                    <h2>Well Geometry</h2>
                    <h3>Drill String</h3>
                    \(generateDrillStringTable(data.drillStringSections, totalCapacity: data.totalStringCapacity))

                    <h3>Annulus</h3>
                    \(generateAnnulusTable(data.annulusSections, totalCapacity: data.totalAnnulusCapacity))
                </section>

                <!-- Data Table -->
                <section class="card page-break-before">
                    <h2>Step-by-Step Data</h2>
                    <div class="table-wrapper">
                        <table id="data-table">
                            <thead>
                                <tr>
                                    <th>MD</th>
                                    <th>TVD</th>
                                    <th>SABP</th>
                                    <th>ESD</th>
                                    <th>Backfill</th>
                                    <th>Tank Δ</th>
                                    <th>Float</th>
                                </tr>
                            </thead>
                            <tbody>
                                \(generateTableRows(data.steps))
                            </tbody>
                        </table>
                    </div>
                    <div class="table-legend">
                        MD/TVD (m), SABP (kPa), ESD (kg/m³), Backfill/Tank Δ (m³)
                    </div>
                </section>
            </main>

            <footer>
                <p>Generated by Josh Well Control • \(dateStr)</p>
            </footer>
        </body>
        </html>
        """
    }

    // MARK: - Print-optimized CSS

    private func generatePrintCSS() -> String {
        return """
        :root {
            --brand-color: #52a5bf;
            --safe-color: #4caf50;
            --warning-color: #ff9800;
            --danger-color: #f44336;
            --bg-color: #ffffff;
            --card-bg: #ffffff;
            --text-color: #333333;
            --text-light: #666666;
            --border-color: #e0e0e0;
        }

        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: var(--bg-color);
            color: var(--text-color);
            line-height: 1.4;
            font-size: 10pt;
        }

        header {
            background: var(--brand-color);
            color: white;
            padding: 12px 20px;
        }

        .header-content {
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        header h1 {
            font-size: 16pt;
            font-weight: 600;
        }

        .well-name {
            opacity: 0.9;
            font-size: 10pt;
        }

        main {
            padding: 16px;
        }

        .card {
            background: var(--card-bg);
            border: 1px solid var(--border-color);
            border-radius: 6px;
            padding: 14px;
            margin-bottom: 14px;
        }

        .card h2 {
            color: var(--brand-color);
            font-size: 12pt;
            margin-bottom: 10px;
            padding-bottom: 6px;
            border-bottom: 1px solid var(--border-color);
        }

        .card h3 {
            color: var(--text-color);
            font-size: 10pt;
            margin: 12px 0 8px 0;
        }

        .info-grid, .params-grid {
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 8px;
        }

        .info-item, .param-item {
            display: flex;
            gap: 6px;
        }

        .label {
            color: var(--text-light);
            font-size: 9pt;
        }

        .value {
            font-weight: 500;
            font-size: 9pt;
        }

        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 10px;
            margin-bottom: 10px;
        }

        .metrics-grid.secondary {
            grid-template-columns: repeat(3, 1fr);
        }

        .metric-box {
            background: #f5f5f5;
            border-radius: 4px;
            padding: 10px;
            text-align: center;
        }

        .metric-box.small {
            padding: 8px;
        }

        .metric-box.warning .metric-value {
            color: var(--warning-color);
        }

        .metric-box.danger .metric-value {
            color: var(--danger-color);
        }

        .metric-title {
            font-size: 8pt;
            color: var(--text-light);
            margin-bottom: 3px;
        }

        .metric-value {
            font-size: 14pt;
            font-weight: 700;
            color: var(--safe-color);
        }

        .metric-box.small .metric-value {
            font-size: 11pt;
        }

        .metric-unit {
            font-size: 7pt;
            color: var(--text-light);
        }

        /* Charts */
        .charts-grid {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 12px;
        }

        .svg-chart {
            border: 1px solid var(--border-color);
            border-radius: 4px;
            overflow: hidden;
        }

        .chart-placeholder {
            height: 160px;
            display: flex;
            align-items: center;
            justify-content: center;
            background: #f5f5f5;
            color: var(--text-light);
        }

        /* Tables */
        .table-wrapper {
            overflow: visible;
        }

        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 7pt;
        }

        th {
            background: var(--brand-color);
            color: white;
            padding: 6px 4px;
            text-align: right;
            white-space: nowrap;
            font-weight: 600;
        }

        td {
            padding: 4px;
            text-align: right;
            border-bottom: 1px solid var(--border-color);
        }

        tr:nth-child(even) {
            background: #f9f9f9;
        }

        .table-legend {
            margin-top: 6px;
            font-size: 7pt;
            color: var(--text-light);
        }

        /* Geometry Tables */
        .geometry-table {
            font-size: 8pt;
            margin-bottom: 10px;
        }

        .geometry-table th {
            font-size: 7pt;
            padding: 5px 4px;
        }

        .geometry-table td {
            padding: 4px;
        }

        .geometry-table td:first-child {
            text-align: left;
        }

        .total-row {
            background: #e0e0e0 !important;
            font-weight: 600;
        }

        footer {
            text-align: center;
            padding: 12px;
            color: var(--text-light);
            font-size: 8pt;
            border-top: 1px solid var(--border-color);
        }

        /* Print-specific */
        .page-break-before {
            page-break-before: always;
        }

        @media print {
            body {
                -webkit-print-color-adjust: exact;
                print-color-adjust: exact;
            }
            .card {
                break-inside: avoid;
            }
        }
        """
    }

    // MARK: - HTML Helpers

    private func escapeHTML(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func generateTableRows(_ steps: [NumericalTripModel.TripStep]) -> String {
        var html = ""
        for step in steps {
            html += """
            <tr>
                <td>\(String(format: "%.0f", step.bitMD_m))</td>
                <td>\(String(format: "%.0f", step.bitTVD_m))</td>
                <td>\(String(format: "%.0f", step.SABP_kPa))</td>
                <td>\(String(format: "%.0f", step.ESDatTD_kgpm3))</td>
                <td>\(String(format: "%.2f", step.cumulativeBackfill_m3))</td>
                <td>\(String(format: "%+.2f", step.cumulativeSurfaceTankDelta_m3))</td>
                <td>\(step.floatState)</td>
            </tr>
            """
        }
        return html
    }

    // MARK: - SVG Chart Generation

    private func generateSVGChart(title: String, xValues: [Double], datasets: [(values: [Double], color: String, label: String)]) -> String {
        guard xValues.count > 1, !datasets.isEmpty else {
            return "<div class=\"chart-placeholder\">No data</div>"
        }

        let width = 260.0
        let height = 160.0
        let margin = (top: 25.0, right: 10.0, bottom: 25.0, left: 45.0)
        let plotW = width - margin.left - margin.right
        let plotH = height - margin.top - margin.bottom

        let xMin = xValues.min() ?? 0
        let xMax = xValues.max() ?? 1
        let xRange = xMax - xMin > 0 ? xMax - xMin : 1

        // Find y range across all datasets
        let allYValues = datasets.flatMap { $0.values }
        let yMinVal = allYValues.min() ?? 0
        let yMaxVal = allYValues.max() ?? 1
        let yPad = (yMaxVal - yMinVal) * 0.1
        let yMin = yMinVal - yPad
        let yMax = yMaxVal + yPad
        let yRange = yMax - yMin > 0 ? yMax - yMin : 1

        // Generate paths for each dataset
        var paths = ""
        for dataset in datasets {
            var pathD = ""
            for (i, (x, y)) in zip(xValues, dataset.values).enumerated() {
                let px = margin.left + ((xMax - x) / xRange) * plotW
                let py = margin.top + ((yMax - y) / yRange) * plotH
                pathD += i == 0 ? "M \(px) \(py)" : " L \(px) \(py)"
            }
            paths += "<path d=\"\(pathD)\" fill=\"none\" stroke=\"\(dataset.color)\" stroke-width=\"1.5\"/>\n"
        }

        // Y-axis labels
        var yLabels = ""
        for i in 0...4 {
            let val = yMin + (yMax - yMin) * Double(4 - i) / 4.0
            let y = margin.top + plotH * Double(i) / 4.0
            yLabels += "<text x=\"\(margin.left - 5)\" y=\"\(y + 3)\" text-anchor=\"end\" font-size=\"8\" fill=\"#666\">\(String(format: "%.0f", val))</text>"
            yLabels += "<line x1=\"\(margin.left)\" y1=\"\(y)\" x2=\"\(width - margin.right)\" y2=\"\(y)\" stroke=\"#ddd\" stroke-width=\"0.5\"/>"
        }

        // X-axis labels (depth, inverted)
        var xLabels = ""
        for i in 0...4 {
            let val = xMax - (xMax - xMin) * Double(i) / 4.0
            let x = margin.left + plotW * Double(i) / 4.0
            xLabels += "<text x=\"\(x)\" y=\"\(height - 5)\" text-anchor=\"middle\" font-size=\"8\" fill=\"#666\">\(String(format: "%.0f", val))</text>"
        }

        // Legend for multiple datasets
        var legend = ""
        if datasets.count > 1 {
            for (i, dataset) in datasets.enumerated() {
                let lx = margin.left + 5 + Double(i) * 60
                legend += "<rect x=\"\(lx)\" y=\"18\" width=\"10\" height=\"3\" fill=\"\(dataset.color)\"/>"
                legend += "<text x=\"\(lx + 12)\" y=\"21\" font-size=\"7\" fill=\"#666\">\(dataset.label)</text>"
            }
        }

        return """
        <div class="svg-chart">
            <svg width="\(width)" height="\(height)" viewBox="0 0 \(width) \(height)">
                <rect width="\(width)" height="\(height)" fill="#f9f9f9"/>
                <text x="\(width/2)" y="12" text-anchor="middle" font-size="10" font-weight="600" fill="#333">\(title)</text>
                \(legend)
                \(yLabels)
                \(xLabels)
                <line x1="\(margin.left)" y1="\(margin.top)" x2="\(margin.left)" y2="\(height - margin.bottom)" stroke="#999"/>
                <line x1="\(margin.left)" y1="\(height - margin.bottom)" x2="\(width - margin.right)" y2="\(height - margin.bottom)" stroke="#999"/>
                \(paths)
            </svg>
        </div>
        """
    }

    private func generateDrillStringTable(_ sections: [PDFSectionData], totalCapacity: Double) -> String {
        guard !sections.isEmpty else {
            return "<p>No drill string sections defined</p>"
        }

        var html = """
        <table class="geometry-table">
            <thead>
                <tr>
                    <th>Section</th>
                    <th>Top (m)</th>
                    <th>Bot (m)</th>
                    <th>OD (mm)</th>
                    <th>ID (mm)</th>
                    <th>Cap (m³/m)</th>
                    <th>Disp (m³/m)</th>
                    <th>Vol (m³)</th>
                </tr>
            </thead>
            <tbody>
        """

        for section in sections {
            html += """
            <tr>
                <td>\(escapeHTML(section.name))</td>
                <td>\(String(format: "%.0f", section.topMD))</td>
                <td>\(String(format: "%.0f", section.bottomMD))</td>
                <td>\(String(format: "%.1f", section.outerDiameter * 1000))</td>
                <td>\(String(format: "%.1f", section.innerDiameter * 1000))</td>
                <td>\(String(format: "%.4f", section.capacity_m3_per_m))</td>
                <td>\(String(format: "%.4f", section.displacement_m3_per_m))</td>
                <td>\(String(format: "%.2f", section.totalVolume))</td>
            </tr>
            """
        }

        html += """
            <tr class="total-row">
                <td>TOTAL</td>
                <td colspan="6"></td>
                <td>\(String(format: "%.2f", totalCapacity))</td>
            </tr>
            </tbody>
        </table>
        """

        return html
    }

    private func generateAnnulusTable(_ sections: [PDFSectionData], totalCapacity: Double) -> String {
        guard !sections.isEmpty else {
            return "<p>No annulus sections defined</p>"
        }

        var html = """
        <table class="geometry-table">
            <thead>
                <tr>
                    <th>Section</th>
                    <th>Top (m)</th>
                    <th>Bot (m)</th>
                    <th>Hole ID (mm)</th>
                    <th>Pipe OD (mm)</th>
                    <th>Cap (m³/m)</th>
                    <th>Vol (m³)</th>
                </tr>
            </thead>
            <tbody>
        """

        for section in sections {
            html += """
            <tr>
                <td>\(escapeHTML(section.name))</td>
                <td>\(String(format: "%.0f", section.topMD))</td>
                <td>\(String(format: "%.0f", section.bottomMD))</td>
                <td>\(String(format: "%.1f", section.innerDiameter * 1000))</td>
                <td>\(String(format: "%.1f", section.outerDiameter * 1000))</td>
                <td>\(String(format: "%.4f", section.capacity_m3_per_m))</td>
                <td>\(String(format: "%.2f", section.totalVolume))</td>
            </tr>
            """
        }

        html += """
            <tr class="total-row">
                <td>TOTAL</td>
                <td colspan="5"></td>
                <td>\(String(format: "%.2f", totalCapacity))</td>
            </tr>
            </tbody>
        </table>
        """

        return html
    }
}
