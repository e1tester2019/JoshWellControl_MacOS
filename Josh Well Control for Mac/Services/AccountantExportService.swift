//
//  AccountantExportService.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-08.
//

import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

class AccountantExportService {
    static let shared = AccountantExportService()

    private init() {}

    /// Sanitize a string for use in filenames - removes/replaces problematic characters
    func sanitizeFilename(_ input: any StringProtocol) -> String {
        String(input)
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "|", with: "-")
    }

    struct ExportData {
        let year: Int
        let quarter: Int? // nil for full year
        let invoices: [Invoice]
        let expenses: [Expense]
        let mileageLogs: [MileageLog]
        let payStubs: [PayStub]
        let dividends: [Dividend]
        let summary: FinancialSummary
    }

    #if os(macOS)
    func exportPackage(data: ExportData, to url: URL) throws {
        let fileManager = FileManager.default

        // Create temp directory
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        // Create subdirectories
        let receiptsDir = tempDir.appendingPathComponent("receipts")
        let invoicesDir = tempDir.appendingPathComponent("invoices")
        let mileageDir = tempDir.appendingPathComponent("mileage")
        try fileManager.createDirectory(at: receiptsDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: invoicesDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: mileageDir, withIntermediateDirectories: true)

        // Generate mileage detail pages and map images
        var mileageLinks: [UUID: String] = [:] // Map log ID to detail page filename
        let semaphore = DispatchSemaphore(value: 0)
        var mapGenerationError: Error?

        Task {
            do {
                for (index, log) in data.mileageLogs.enumerated() {
                    let tripNumber = index + 1
                    let detailFilename = "trip_\(tripNumber).html"
                    mileageLinks[log.id] = detailFilename

                    // Generate map image if GPS data available
                    var mapFilename: String? = nil
                    if log.hasGPSData {
                        do {
                            let mapData = try await MapSnapshotServiceMacOS.shared.generateJPEGData(
                                for: log,
                                options: .large
                            )
                            mapFilename = "trip_\(tripNumber)_map.jpg"
                            let mapFile = mileageDir.appendingPathComponent(mapFilename!)
                            try mapData.write(to: mapFile)
                        } catch {
                            // Continue without map if generation fails
                            print("Map generation failed for trip \(tripNumber): \(error)")
                        }
                    }

                    // Generate detail HTML page
                    let detailHTML = self.generateMileageDetailHTML(log: log, tripNumber: tripNumber, mapFilename: mapFilename)
                    let detailFile = mileageDir.appendingPathComponent(detailFilename)
                    try detailHTML.write(to: detailFile, atomically: true, encoding: .utf8)
                }
            } catch {
                mapGenerationError = error
            }
            semaphore.signal()
        }
        semaphore.wait()

        if let error = mapGenerationError {
            throw error
        }

        // Generate and save HTML report
        let html = generateHTML(data: data, mileageLinks: mileageLinks)
        let htmlFile = tempDir.appendingPathComponent("financial_report.html")
        try html.write(to: htmlFile, atomically: true, encoding: .utf8)

        // Generate CSS file
        let css = generateCSS()
        let cssFile = tempDir.appendingPathComponent("styles.css")
        try css.write(to: cssFile, atomically: true, encoding: .utf8)

        // Export receipts - MUST be sorted by date to match HTML generation
        var receiptIndex = 1
        for expense in data.expenses.sorted(by: { $0.date < $1.date }) {
            if let receiptData = expense.receiptImageData {
                let ext = expense.receiptIsPDF ? "pdf" : "jpg"
                let filename = String(format: "%03d_%@_%@.%@",
                    receiptIndex,
                    expense.displayDate.replacingOccurrences(of: " ", with: "_"),
                    sanitizeFilename(expense.vendor.prefix(20)),
                    ext
                )
                let receiptFile = receiptsDir.appendingPathComponent(filename)
                try receiptData.write(to: receiptFile)
                receiptIndex += 1
            }
        }

        // Export invoice PDFs
        for invoice in data.invoices {
            if let pdfData = InvoicePDFGenerator.shared.generatePDF(for: invoice) {
                let filename = "Invoice_\(invoice.invoiceNumber).pdf"
                let invoiceFile = invoicesDir.appendingPathComponent(filename)
                try pdfData.write(to: invoiceFile)
            }
        }

        // Create ZIP archive using system zip command
        let zipProcess = Process()
        zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipProcess.currentDirectoryURL = tempDir
        zipProcess.arguments = ["-r", url.path, "."]

        try zipProcess.run()
        zipProcess.waitUntilExit()

        if zipProcess.terminationStatus != 0 {
            throw NSError(domain: "AccountantExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create ZIP archive"])
        }
    }
    #endif

    #if os(iOS)
    /// Export financial data package for iOS (uses share sheet)
    @MainActor
    func exportPackage(data: ExportData) async throws {
        let fileManager = FileManager.default
        let periodName = data.quarter != nil ? "Q\(data.quarter!)_\(data.year)" : "\(data.year)"

        // Create temp directory for export
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("AccountantExport_\(periodName)")
        try? fileManager.removeItem(at: tempDir) // Clean up any previous export
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Create subdirectories
        let receiptsDir = tempDir.appendingPathComponent("receipts")
        let invoicesDir = tempDir.appendingPathComponent("invoices")
        let mileageDir = tempDir.appendingPathComponent("mileage")
        try fileManager.createDirectory(at: receiptsDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: invoicesDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: mileageDir, withIntermediateDirectories: true)

        // Generate mileage detail pages and map images
        var mileageLinks: [UUID: String] = [:]

        for (index, log) in data.mileageLogs.enumerated() {
            let tripNumber = index + 1
            let detailFilename = "trip_\(tripNumber).html"
            mileageLinks[log.id] = detailFilename

            // Generate map image if GPS data available
            var mapFilename: String? = nil
            if log.hasGPSData {
                do {
                    let mapImage = try await MapSnapshotService.shared.generateSnapshot(
                        for: log,
                        options: .large
                    )
                    if let mapData = mapImage.jpegData(compressionQuality: 0.8) {
                        mapFilename = "trip_\(tripNumber)_map.jpg"
                        let mapFile = mileageDir.appendingPathComponent(mapFilename!)
                        try mapData.write(to: mapFile)
                    }
                } catch {
                    print("Map generation failed for trip \(tripNumber): \(error)")
                }
            }

            // Generate detail HTML page
            let detailHTML = self.generateMileageDetailHTML(log: log, tripNumber: tripNumber, mapFilename: mapFilename)
            let detailFile = mileageDir.appendingPathComponent(detailFilename)
            try detailHTML.write(to: detailFile, atomically: true, encoding: .utf8)
        }

        // Generate and save HTML report
        let html = generateHTML(data: data, mileageLinks: mileageLinks)
        let htmlFile = tempDir.appendingPathComponent("financial_report.html")
        try html.write(to: htmlFile, atomically: true, encoding: .utf8)

        // Generate CSS file
        let css = generateCSS()
        let cssFile = tempDir.appendingPathComponent("styles.css")
        try css.write(to: cssFile, atomically: true, encoding: .utf8)

        // Export receipts
        var receiptIndex = 1
        for expense in data.expenses.sorted(by: { $0.date < $1.date }) {
            if let receiptData = expense.receiptImageData {
                let ext = expense.receiptIsPDF ? "pdf" : "jpg"
                let filename = String(format: "%03d_%@_%@.%@",
                    receiptIndex,
                    expense.displayDate.replacingOccurrences(of: " ", with: "_"),
                    sanitizeFilename(expense.vendor.prefix(20)),
                    ext
                )
                let receiptFile = receiptsDir.appendingPathComponent(filename)
                try receiptData.write(to: receiptFile)
                receiptIndex += 1
            }
        }

        // Export invoice PDFs
        for invoice in data.invoices {
            if let pdfData = InvoicePDFGenerator.shared.generatePDF(for: invoice) {
                let filename = "Invoice_\(invoice.invoiceNumber).pdf"
                let invoiceFile = invoicesDir.appendingPathComponent(filename)
                try pdfData.write(to: invoiceFile)
            }
        }

        // Collect all files to share
        var itemsToShare: [Any] = [tempDir]

        // Present share sheet
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {

            let activityVC = UIActivityViewController(
                activityItems: itemsToShare,
                applicationActivities: nil
            )

            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }

            rootViewController.present(activityVC, animated: true)
        }
    }
    #endif

    // MARK: - Mileage Detail Page

    func generateMileageDetailHTML(log: MileageLog, tripNumber: Int, mapFilename: String?) -> String {
        let businessInfo = BusinessInfo.shared
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy"

        let currencyFormatter = NumberFormatter()
        currencyFormatter.numberStyle = .currency
        currencyFormatter.currencySymbol = "$"

        func currency(_ value: Double) -> String {
            currencyFormatter.string(from: NSNumber(value: value)) ?? "$0.00"
        }

        let deduction = MileageSummary.calculateDeduction(totalKm: log.effectiveDistance)

        var html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Trip #\(tripNumber) - \(dateFormatter.string(from: log.date))</title>
            <link rel="stylesheet" href="../styles.css">
        </head>
        <body>
            <div class="container">
                <header>
                    <div class="company-info">
                        <h1>\(businessInfo.companyName)</h1>
                        <p>\(businessInfo.address)<br>
                        \(businessInfo.city), \(businessInfo.province) \(businessInfo.postalCode)<br>
                        GST #: \(businessInfo.gstNumber)</p>
                    </div>
                    <div class="report-info">
                        <h2>Trip Details</h2>
                        <p class="period">Trip #\(tripNumber)</p>
                        <p class="generated">\(dateFormatter.string(from: log.date))</p>
                    </div>
                </header>

                <section class="summary">
                    <div style="margin-bottom: 20px;">
                        <a href="../financial_report.html#mileage" style="display: inline-flex; align-items: center; gap: 8px; color: #52a5bf; text-decoration: none; font-weight: 600; font-size: 15px;">← Back to Financial Report</a>
                    </div>

                    <h2>Trip Summary</h2>

                    <div class="summary-grid">
                        <div class="summary-card revenue">
                            <h3>Distance</h3>
                            <table>
                                <tr><td>One-way Distance</td><td class="amount">\(Int(log.distance)) km</td></tr>
        """

        if log.isRoundTrip {
            html += """
                                <tr class="indent"><td>Round Trip</td><td class="amount">× 2</td></tr>
                                <tr class="total"><td>Effective Distance</td><td class="amount positive"><strong>\(Int(log.effectiveDistance)) km</strong></td></tr>
            """
        } else {
            html += """
                                <tr class="total"><td>Total Distance</td><td class="amount positive"><strong>\(Int(log.effectiveDistance)) km</strong></td></tr>
            """
        }

        html += """
                            </table>
                        </div>

                        <div class="summary-card expenses">
                            <h3>CRA Deduction</h3>
                            <table>
                                <tr><td>Distance</td><td class="amount">\(Int(log.effectiveDistance)) km</td></tr>
                                <tr class="indent"><td>Rate</td><td class="amount">@ $\(String(format: "%.2f", MileageLog.firstTierRate))/km</td></tr>
                                <tr class="total"><td>Deduction Value</td><td class="amount positive"><strong>\(currency(deduction))</strong></td></tr>
                            </table>
                        </div>

                        <div class="summary-card payroll">
                            <h3>Route</h3>
                            <table>
                                <tr><td>From</td><td class="amount" style="color: #16a34a;">\(log.startLocation.isEmpty ? "—" : log.startLocation)</td></tr>
                                <tr><td>To</td><td class="amount" style="color: #dc2626;">\(log.endLocation.isEmpty ? "—" : log.endLocation)</td></tr>
        """

        if let duration = log.formattedDuration {
            html += """
                                <tr class="indent"><td>Duration</td><td class="amount">\(duration)</td></tr>
            """
        }

        html += """
                            </table>
                        </div>
        """

        // Purpose/Notes card
        if !log.purpose.isEmpty || !log.notes.isEmpty || log.client != nil || log.well != nil {
            html += """

                        <div class="summary-card dividends">
                            <h3>Details</h3>
                            <table>
            """

            if !log.purpose.isEmpty {
                html += """
                                <tr><td>Purpose</td><td class="amount">\(log.purpose)</td></tr>
                """
            }

            if let client = log.client {
                html += """
                                <tr><td>Client</td><td class="amount">\(client.companyName)</td></tr>
                """
            }

            if let well = log.well {
                html += """
                                <tr><td>Well</td><td class="amount">\(well.name)</td></tr>
                """
            }

            if !log.notes.isEmpty {
                html += """
                                <tr class="indent"><td colspan="2" style="font-style: italic; color: #64748b;">\(log.notes)</td></tr>
                """
            }

            html += """
                            </table>
                        </div>
            """
        }

        html += """
                    </div>
        """

        // Map section
        if let mapFilename = mapFilename {
            html += """

                    <div class="results" style="text-align: center; padding: 30px;">
                        <h3 style="margin-bottom: 20px; color: #52a5bf;">Route Map</h3>
                        <img src="\(mapFilename)" alt="Trip Route Map" style="max-width: 100%; height: auto; border-radius: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.15);">
                    </div>
            """
        }

        // GPS Coordinates section
        if log.hasGPSData {
            html += """

                    <div class="tax-info">
                        <h3>GPS Data</h3>
                        <div class="tax-grid">
                            <div><strong>Start:</strong> \(String(format: "%.6f", log.startLatitude!)), \(String(format: "%.6f", log.startLongitude!))</div>
                            <div><strong>End:</strong> \(String(format: "%.6f", log.endLatitude!)), \(String(format: "%.6f", log.endLongitude!))</div>
            """

            if let points = log.routePoints, !points.isEmpty {
                html += """
                            <div><strong>Route Points:</strong> \(points.count) GPS coordinates recorded</div>
                """
            }

            html += """
                        </div>
                    </div>
            """
        }

        html += """
                </section>

                <footer>
                    <p>Trip details from \(businessInfo.companyName) mileage log</p>
                </footer>
            </div>
        </body>
        </html>
        """

        return html
    }

    private func generateHTML(data: ExportData, mileageLinks: [UUID: String] = [:]) -> String {
        let businessInfo = BusinessInfo.shared
        let periodName = data.quarter != nil ? "Q\(data.quarter!) \(data.year)" : "Annual \(data.year)"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy"

        let currencyFormatter = NumberFormatter()
        currencyFormatter.numberStyle = .currency
        currencyFormatter.currencySymbol = "$"

        func currency(_ value: Double) -> String {
            currencyFormatter.string(from: NSNumber(value: value)) ?? "$0.00"
        }

        var html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Financial Report - \(periodName)</title>
            <link rel="stylesheet" href="styles.css">
        </head>
        <body>
            <div class="container">
                <header>
                    <div class="company-info">
                        <h1>\(businessInfo.companyName)</h1>
                        <p>\(businessInfo.address)<br>
                        \(businessInfo.city), \(businessInfo.province) \(businessInfo.postalCode)<br>
                        GST #: \(businessInfo.gstNumber)</p>
                    </div>
                    <div class="report-info">
                        <h2>Financial Report</h2>
                        <p class="period">\(periodName)</p>
                        <p class="generated">Generated: \(dateFormatter.string(from: Date()))</p>
                    </div>
                </header>

                <section class="summary">
                    <h2>Financial Summary</h2>

                    <div class="summary-grid">
                        <div class="summary-card revenue">
                            <h3>Revenue</h3>
                            <table>
                                <tr><td>Invoiced Revenue</td><td class="amount">\(currency(data.summary.totalRevenue))</td></tr>
                                <tr class="indent"><td>Less: Unpaid Invoices</td><td class="amount negative">\(currency(-data.summary.unpaidRevenue))</td></tr>
                                <tr class="total"><td>Net Revenue (Collected)</td><td class="amount positive">\(currency(data.summary.collectedRevenue))</td></tr>
                            </table>
                        </div>

                        <div class="summary-card expenses">
                            <h3>Expenses</h3>
                            <table>
        """

        // Add expense categories
        let sortedExpenses = data.summary.expensesByCategory.sorted { $0.value > $1.value }
        for (category, amount) in sortedExpenses {
            html += """
                                <tr class="indent"><td>\(category.rawValue)</td><td class="amount">\(currency(amount))</td></tr>
            """
        }

        if data.summary.mileageDeduction > 0 {
            html += """
                                <tr class="indent"><td>Mileage (CRA Rate)</td><td class="amount">\(currency(data.summary.mileageDeduction))</td></tr>
            """
        }

        html += """
                                <tr class="total"><td>Total Expenses</td><td class="amount negative">\(currency(data.summary.totalExpenses))</td></tr>
                            </table>
                        </div>

                        <div class="summary-card payroll">
                            <h3>Payroll</h3>
                            <table>
                                <tr><td>Gross Wages</td><td class="amount">\(currency(data.summary.grossPayroll))</td></tr>
                                <tr class="indent"><td>Employer CPP</td><td class="amount">\(currency(data.summary.employerCPP))</td></tr>
                                <tr class="indent"><td>Employer EI</td><td class="amount">\(currency(data.summary.employerEI))</td></tr>
                                <tr class="total"><td>Total Payroll Cost</td><td class="amount negative">\(currency(data.summary.totalPayrollCost))</td></tr>
                            </table>
                        </div>

                        <div class="summary-card dividends">
                            <h3>Dividends</h3>
                            <table>
                                <tr><td>Dividends Declared</td><td class="amount">\(currency(data.summary.dividendsDeclared))</td></tr>
                                <tr class="indent"><td>Dividends Paid</td><td class="amount">\(currency(data.summary.dividendsPaid))</td></tr>
                            </table>
                        </div>
                    </div>

                    <div class="results">
        """

        let operatingIncome = data.summary.collectedRevenue - data.summary.totalExpenses - data.summary.totalPayrollCost
        let netPosition = operatingIncome - data.summary.dividendsPaid

        html += """
                        <div class="result-row">
                            <span class="label">Operating Income</span>
                            <span class="value \(operatingIncome >= 0 ? "positive" : "negative")">\(currency(operatingIncome))</span>
                        </div>
                        <div class="result-row highlight">
                            <span class="label">Net Position (After Dividends)</span>
                            <span class="value \(netPosition >= 0 ? "positive" : "negative")">\(currency(netPosition))</span>
                        </div>
                    </div>

                    <div class="tax-info">
                        <h3>Tax Information</h3>
                        <div class="tax-grid">
                            <div><strong>GST Collected:</strong> \(currency(data.summary.gstCollected))</div>
                            <div><strong>GST Paid (ITC):</strong> \(currency(data.summary.gstPaid))</div>
                            <div><strong>Net GST Owing:</strong> <span class="\(data.summary.gstCollected - data.summary.gstPaid > 0 ? "negative" : "positive")">\(currency(data.summary.gstCollected - data.summary.gstPaid))</span></div>
                            <div><strong>Total Mileage:</strong> \(Int(data.summary.totalMileage)) km</div>
                        </div>
                    </div>
                </section>
        """

        // Invoices section
        if !data.invoices.isEmpty {
            html += """

                <section class="invoices">
                    <h2>Invoices (\(data.invoices.count))</h2>
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Invoice #</th>
                                <th>Date</th>
                                <th>Client</th>
                                <th>Days</th>
                                <th>Subtotal</th>
                                <th>GST</th>
                                <th>Total</th>
                                <th>Status</th>
                                <th>PDF</th>
                            </tr>
                        </thead>
                        <tbody>
            """

            for invoice in data.invoices.sorted(by: { $0.date < $1.date }) {
                let status = invoice.isPaid ? "Paid" : "Unpaid"
                let statusClass = invoice.isPaid ? "paid" : "unpaid"
                let pdfLink = "<a href=\"invoices/Invoice_\(invoice.invoiceNumber).pdf\" target=\"_blank\">View</a>"
                html += """
                            <tr>
                                <td><strong>\(invoice.invoiceNumber)</strong></td>
                                <td>\(dateFormatter.string(from: invoice.date))</td>
                                <td>\(invoice.client?.companyName ?? "—")</td>
                                <td>\(invoice.totalDays)</td>
                                <td class="amount">\(currency(invoice.subtotal))</td>
                                <td class="amount">\(currency(invoice.gstAmount))</td>
                                <td class="amount">\(currency(invoice.total))</td>
                                <td class="status \(statusClass)">\(status)</td>
                                <td>\(pdfLink)</td>
                            </tr>
                """
            }

            html += """
                        </tbody>
                        <tfoot>
                            <tr>
                                <td colspan="4"><strong>Total</strong></td>
                                <td class="amount"><strong>\(currency(data.invoices.reduce(0) { $0 + $1.subtotal }))</strong></td>
                                <td class="amount"><strong>\(currency(data.invoices.reduce(0) { $0 + $1.gstAmount }))</strong></td>
                                <td class="amount"><strong>\(currency(data.invoices.reduce(0) { $0 + $1.total }))</strong></td>
                                <td colspan="2"></td>
                            </tr>
                        </tfoot>
                    </table>
                </section>
            """
        }

        // Expenses section
        if !data.expenses.isEmpty {
            // Get unique values for filters
            let uniqueVendors = Set(data.expenses.map { $0.vendor }).sorted()
            let uniqueCategories = Set(data.expenses.map { $0.category.rawValue }).sorted()
            let uniqueMonths = Set(data.expenses.map {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM yyyy"
                return formatter.string(from: $0.date)
            }).sorted()

            html += """

                <section class="expenses-detail">
                    <h2>Expenses (<span id="expense-count">\(data.expenses.count)</span>)</h2>

                    <div class="filter-controls">
                        <div class="filter-group">
                            <label for="filter-search">Search</label>
                            <input type="text" id="filter-search" placeholder="Search all fields..." onkeyup="filterExpenses()">
                        </div>
                        <div class="filter-group">
                            <label for="filter-month">Month</label>
                            <select id="filter-month" onchange="filterExpenses()">
                                <option value="">All Months</option>
            """

            for month in uniqueMonths {
                html += """
                                <option value="\(month)">\(month)</option>
                """
            }

            html += """
                            </select>
                        </div>
                        <div class="filter-group">
                            <label for="filter-vendor">Vendor</label>
                            <select id="filter-vendor" onchange="filterExpenses()">
                                <option value="">All Vendors</option>
            """

            for vendor in uniqueVendors {
                html += """
                                <option value="\(vendor)">\(vendor)</option>
                """
            }

            html += """
                            </select>
                        </div>
                        <div class="filter-group">
                            <label for="filter-category">Category</label>
                            <select id="filter-category" onchange="filterExpenses()">
                                <option value="">All Categories</option>
            """

            for category in uniqueCategories {
                html += """
                                <option value="\(category)">\(category)</option>
                """
            }

            html += """
                            </select>
                        </div>
                        <div class="filter-group">
                            <label for="filter-receipt">Receipt</label>
                            <select id="filter-receipt" onchange="filterExpenses()">
                                <option value="">All</option>
                                <option value="yes">Has Receipt</option>
                                <option value="no">No Receipt</option>
                            </select>
                        </div>
                        <button class="clear-filters" onclick="clearFilters()">Clear Filters</button>
                    </div>

                    <div class="filter-totals">
                        <span>Showing: <strong id="filtered-amount">\(currency(data.expenses.reduce(0) { $0 + $1.preTaxAmount }))</strong></span>
                        <span>GST: <strong id="filtered-gst">\(currency(data.expenses.reduce(0) { $0 + $1.gstAmount }))</strong></span>
                    </div>

                    <table class="data-table" id="expenses-table">
                        <thead>
                            <tr>
                                <th>Date</th>
                                <th>Vendor</th>
                                <th>Category</th>
                                <th>Description</th>
                                <th>Amount</th>
                                <th>GST</th>
                                <th>Receipt</th>
                            </tr>
                        </thead>
                        <tbody>
            """

            var receiptIndex = 1
            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "MMM yyyy"

            for expense in data.expenses.sorted(by: { $0.date < $1.date }) {
                var receiptLink = "—"
                let hasReceipt = expense.receiptImageData != nil
                if hasReceipt {
                    let ext = expense.receiptIsPDF ? "pdf" : "jpg"
                    let filename = String(format: "%03d_%@_%@.%@",
                        receiptIndex,
                        expense.displayDate.replacingOccurrences(of: " ", with: "_"),
                        sanitizeFilename(expense.vendor.prefix(20)),
                        ext
                    )
                    receiptLink = "<a href=\"receipts/\(filename)\" target=\"_blank\">View</a>"
                    receiptIndex += 1
                }

                html += """
                            <tr data-month="\(monthFormatter.string(from: expense.date))" data-vendor="\(expense.vendor)" data-category="\(expense.category.rawValue)" data-receipt="\(hasReceipt ? "yes" : "no")" data-amount="\(expense.preTaxAmount)" data-gst="\(expense.gstAmount)">
                                <td>\(dateFormatter.string(from: expense.date))</td>
                                <td>\(expense.vendor)</td>
                                <td>\(expense.category.rawValue)</td>
                                <td>\(expense.expenseDescription)</td>
                                <td class="amount">\(currency(expense.preTaxAmount))</td>
                                <td class="amount">\(currency(expense.gstAmount))</td>
                                <td>\(receiptLink)</td>
                            </tr>
                """
            }

            html += """
                        </tbody>
                        <tfoot>
                            <tr>
                                <td colspan="4"><strong>Total (All)</strong></td>
                                <td class="amount"><strong>\(currency(data.expenses.reduce(0) { $0 + $1.preTaxAmount }))</strong></td>
                                <td class="amount"><strong>\(currency(data.expenses.reduce(0) { $0 + $1.gstAmount }))</strong></td>
                                <td></td>
                            </tr>
                        </tfoot>
                    </table>
                </section>
            """
        }

        // Mileage section
        if !data.mileageLogs.isEmpty {
            let totalKm = data.mileageLogs.reduce(0.0) { $0 + $1.effectiveDistance }

            // Calculate monthly breakdown
            let calendar = Calendar.current
            var monthlyKm: [Int: Double] = [:]
            var destinationKm: [String: Double] = [:]

            for log in data.mileageLogs {
                let month = calendar.component(.month, from: log.date)
                monthlyKm[month, default: 0] += log.effectiveDistance

                // Group by destination
                let destination = log.endLocation.isEmpty ? "Unknown" : log.endLocation
                destinationKm[destination, default: 0] += log.effectiveDistance
            }

            // CRA tiered calculation
            let firstTierKm = min(totalKm, MileageLog.firstTierLimit)
            let secondTierKm = max(0, totalKm - MileageLog.firstTierLimit)
            let firstTierDeduction = firstTierKm * MileageLog.firstTierRate
            let secondTierDeduction = secondTierKm * MileageLog.secondTierRate
            let totalDeduction = firstTierDeduction + secondTierDeduction

            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "MMMM"

            html += """

                <section class="mileage" id="mileage">
                    <h2>Mileage Log (\(data.mileageLogs.count) trips)</h2>

                    <div class="mileage-summary">
                        <div class="mileage-summary-card">
                            <h3>CRA Deduction Calculation</h3>
                            <table class="summary-table">
                                <tr>
                                    <td>Total Distance</td>
                                    <td class="amount"><strong>\(Int(totalKm)) km</strong></td>
                                </tr>
                                <tr class="indent">
                                    <td>First \(Int(MileageLog.firstTierLimit)) km @ $\(String(format: "%.2f", MileageLog.firstTierRate))/km</td>
                                    <td class="amount">\(Int(firstTierKm)) km = \(currency(firstTierDeduction))</td>
                                </tr>
            """

            if secondTierKm > 0 {
                html += """
                                <tr class="indent">
                                    <td>Remaining km @ $\(String(format: "%.2f", MileageLog.secondTierRate))/km</td>
                                    <td class="amount">\(Int(secondTierKm)) km = \(currency(secondTierDeduction))</td>
                                </tr>
                """
            }

            html += """
                                <tr class="total">
                                    <td><strong>Total CRA Deduction</strong></td>
                                    <td class="amount positive"><strong>\(currency(totalDeduction))</strong></td>
                                </tr>
                            </table>
                        </div>

                        <div class="mileage-summary-card">
                            <h3>Monthly Breakdown</h3>
                            <table class="summary-table">
            """

            for month in 1...12 {
                if let km = monthlyKm[month], km > 0 {
                    var components = DateComponents()
                    components.month = month
                    let monthDate = calendar.date(from: components) ?? Date()
                    html += """
                                <tr>
                                    <td>\(monthFormatter.string(from: monthDate))</td>
                                    <td class="amount">\(Int(km)) km</td>
                                </tr>
                    """
                }
            }

            html += """
                            </table>
                        </div>

                        <div class="mileage-summary-card">
                            <h3>By Destination</h3>
                            <table class="summary-table">
            """

            let sortedDestinations = destinationKm.sorted { $0.value > $1.value }.prefix(10)
            for (destination, km) in sortedDestinations {
                html += """
                                <tr>
                                    <td>\(destination)</td>
                                    <td class="amount">\(Int(km)) km</td>
                                </tr>
                """
            }

            // Get unique values for mileage filters
            let uniqueDestinations = Set(data.mileageLogs.map { $0.endLocation.isEmpty ? "Unknown" : $0.endLocation }).sorted()
            let uniquePurposes = Set(data.mileageLogs.compactMap { $0.purpose.isEmpty ? nil : $0.purpose }).sorted()
            let uniqueMileageMonths = Set(data.mileageLogs.map {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM yyyy"
                return formatter.string(from: $0.date)
            }).sorted()

            html += """
                            </table>
                        </div>
                    </div>

                    <h3>Trip Details (<span id="mileage-count">\(data.mileageLogs.count)</span> trips)</h3>

                    <div class="filter-controls">
                        <div class="filter-group">
                            <label for="mileage-search">Search</label>
                            <input type="text" id="mileage-search" placeholder="Search all fields..." onkeyup="filterMileage()">
                        </div>
                        <div class="filter-group">
                            <label for="mileage-month">Month</label>
                            <select id="mileage-month" onchange="filterMileage()">
                                <option value="">All Months</option>
            """

            for month in uniqueMileageMonths {
                html += """
                                <option value="\(month)">\(month)</option>
                """
            }

            html += """
                            </select>
                        </div>
                        <div class="filter-group">
                            <label for="mileage-destination">Destination</label>
                            <select id="mileage-destination" onchange="filterMileage()">
                                <option value="">All Destinations</option>
            """

            for destination in uniqueDestinations {
                html += """
                                <option value="\(destination)">\(destination)</option>
                """
            }

            html += """
                            </select>
                        </div>
            """

            if !uniquePurposes.isEmpty {
                html += """
                        <div class="filter-group">
                            <label for="mileage-purpose">Purpose</label>
                            <select id="mileage-purpose" onchange="filterMileage()">
                                <option value="">All Purposes</option>
                """

                for purpose in uniquePurposes {
                    html += """
                                <option value="\(purpose)">\(purpose)</option>
                    """
                }

                html += """
                            </select>
                        </div>
                """
            }

            html += """
                        <div class="filter-group">
                            <label for="mileage-gps">GPS Data</label>
                            <select id="mileage-gps" onchange="filterMileage()">
                                <option value="">All</option>
                                <option value="yes">Has GPS</option>
                                <option value="no">No GPS</option>
                            </select>
                        </div>
                        <button class="clear-filters" onclick="clearMileageFilters()">Clear Filters</button>
                    </div>

                    <div class="filter-totals">
                        <span>Showing: <strong id="filtered-km">\(Int(totalKm)) km</strong></span>
                        <span>CRA Deduction: <strong id="filtered-deduction">\(currency(totalDeduction))</strong></span>
                    </div>

                    <table class="data-table" id="mileage-table">
                        <thead>
                            <tr>
                                <th>Date</th>
                                <th>From</th>
                                <th>To</th>
                                <th>Purpose</th>
                                <th>Distance</th>
                                <th>Effective</th>
                                <th>Details</th>
                            </tr>
                        </thead>
                        <tbody>
            """

            let mileageMonthFormatter = DateFormatter()
            mileageMonthFormatter.dateFormat = "MMM yyyy"

            for log in data.mileageLogs.sorted(by: { $0.date < $1.date }) {
                let roundTripNote = log.isRoundTrip ? " (RT)" : ""
                let detailLink: String
                if let filename = mileageLinks[log.id] {
                    let hasMap = log.hasGPSData
                    let icon = hasMap ? "🗺️" : "📄"
                    detailLink = "<a href=\"mileage/\(filename)\">\(icon) View</a>"
                } else {
                    detailLink = "—"
                }
                let destination = log.endLocation.isEmpty ? "Unknown" : log.endLocation
                html += """
                            <tr data-month="\(mileageMonthFormatter.string(from: log.date))" data-destination="\(destination)" data-purpose="\(log.purpose)" data-gps="\(log.hasGPSData ? "yes" : "no")" data-km="\(log.effectiveDistance)">
                                <td>\(dateFormatter.string(from: log.date))</td>
                                <td>\(log.startLocation)</td>
                                <td>\(log.endLocation)</td>
                                <td>\(log.purpose)</td>
                                <td class="amount">\(Int(log.distance)) km\(roundTripNote)</td>
                                <td class="amount">\(Int(log.effectiveDistance)) km</td>
                                <td>\(detailLink)</td>
                            </tr>
                """
            }

            html += """
                        </tbody>
                        <tfoot>
                            <tr>
                                <td colspan="5"><strong>Total</strong></td>
                                <td class="amount"><strong>\(Int(totalKm)) km</strong></td>
                                <td></td>
                            </tr>
                        </tfoot>
                    </table>
                </section>
            """
        }

        // Dividends section
        if !data.dividends.isEmpty {
            html += """

                <section class="dividends-detail">
                    <h2>Dividends (\(data.dividends.count))</h2>
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Payment Date</th>
                                <th>Shareholder</th>
                                <th>Type</th>
                                <th>Amount</th>
                                <th>Gross-up</th>
                                <th>Taxable Amount</th>
                                <th>Status</th>
                            </tr>
                        </thead>
                        <tbody>
            """

            for dividend in data.dividends.sorted(by: { $0.paymentDate < $1.paymentDate }) {
                let status = dividend.isPaid ? "Paid" : "Declared"
                let statusClass = dividend.isPaid ? "paid" : "unpaid"
                html += """
                            <tr>
                                <td>\(dateFormatter.string(from: dividend.paymentDate))</td>
                                <td>\(dividend.shareholder?.fullName ?? "—")</td>
                                <td>\(dividend.dividendType.shortName)</td>
                                <td class="amount">\(currency(dividend.amount))</td>
                                <td class="amount">\(currency(dividend.grossedUpAmount - dividend.amount))</td>
                                <td class="amount">\(currency(dividend.grossedUpAmount))</td>
                                <td class="status \(statusClass)">\(status)</td>
                            </tr>
                """
            }

            html += """
                        </tbody>
                        <tfoot>
                            <tr>
                                <td colspan="3"><strong>Total</strong></td>
                                <td class="amount"><strong>\(currency(data.dividends.reduce(0) { $0 + $1.amount }))</strong></td>
                                <td class="amount"><strong>\(currency(data.dividends.reduce(0) { $0 + ($1.grossedUpAmount - $1.amount) }))</strong></td>
                                <td class="amount"><strong>\(currency(data.dividends.reduce(0) { $0 + $1.grossedUpAmount }))</strong></td>
                                <td></td>
                            </tr>
                        </tfoot>
                    </table>
                </section>
            """
        }

        html += """

                <footer>
                    <p>This report was generated for accounting purposes. All receipts are included in the 'receipts' folder.</p>
                    <p>Generated by Josh Well Control on \(dateFormatter.string(from: Date()))</p>
                </footer>
            </div>

            <script>
            function filterExpenses() {
                const search = document.getElementById('filter-search').value.toLowerCase();
                const month = document.getElementById('filter-month').value;
                const vendor = document.getElementById('filter-vendor').value;
                const category = document.getElementById('filter-category').value;
                const receipt = document.getElementById('filter-receipt').value;

                const table = document.getElementById('expenses-table');
                const rows = table.querySelectorAll('tbody tr');

                let visibleCount = 0;
                let totalAmount = 0;
                let totalGst = 0;

                rows.forEach(row => {
                    const rowMonth = row.dataset.month;
                    const rowVendor = row.dataset.vendor;
                    const rowCategory = row.dataset.category;
                    const rowReceipt = row.dataset.receipt;
                    const rowAmount = parseFloat(row.dataset.amount) || 0;
                    const rowGst = parseFloat(row.dataset.gst) || 0;
                    const rowText = row.textContent.toLowerCase();

                    let show = true;

                    if (search && !rowText.includes(search)) show = false;
                    if (month && rowMonth !== month) show = false;
                    if (vendor && rowVendor !== vendor) show = false;
                    if (category && rowCategory !== category) show = false;
                    if (receipt && rowReceipt !== receipt) show = false;

                    if (show) {
                        row.style.display = '';
                        visibleCount++;
                        totalAmount += rowAmount;
                        totalGst += rowGst;
                    } else {
                        row.style.display = 'none';
                    }
                });

                document.getElementById('expense-count').textContent = visibleCount;
                document.getElementById('filtered-amount').textContent = formatCurrency(totalAmount);
                document.getElementById('filtered-gst').textContent = formatCurrency(totalGst);
            }

            function clearFilters() {
                document.getElementById('filter-search').value = '';
                document.getElementById('filter-month').value = '';
                document.getElementById('filter-vendor').value = '';
                document.getElementById('filter-category').value = '';
                document.getElementById('filter-receipt').value = '';
                filterExpenses();
            }

            function formatCurrency(value) {
                return '$' + value.toFixed(2).replace(/\\d(?=(\\d{3})+\\.)/g, '$&,');
            }

            // Mileage filtering
            function filterMileage() {
                const search = document.getElementById('mileage-search').value.toLowerCase();
                const month = document.getElementById('mileage-month').value;
                const destination = document.getElementById('mileage-destination').value;
                const purposeEl = document.getElementById('mileage-purpose');
                const purpose = purposeEl ? purposeEl.value : '';
                const gps = document.getElementById('mileage-gps').value;

                const table = document.getElementById('mileage-table');
                const rows = table.querySelectorAll('tbody tr');

                let visibleCount = 0;
                let totalKm = 0;

                rows.forEach(row => {
                    const rowMonth = row.dataset.month;
                    const rowDestination = row.dataset.destination;
                    const rowPurpose = row.dataset.purpose;
                    const rowGps = row.dataset.gps;
                    const rowKm = parseFloat(row.dataset.km) || 0;
                    const rowText = row.textContent.toLowerCase();

                    let show = true;

                    if (search && !rowText.includes(search)) show = false;
                    if (month && rowMonth !== month) show = false;
                    if (destination && rowDestination !== destination) show = false;
                    if (purpose && rowPurpose !== purpose) show = false;
                    if (gps && rowGps !== gps) show = false;

                    if (show) {
                        row.style.display = '';
                        visibleCount++;
                        totalKm += rowKm;
                    } else {
                        row.style.display = 'none';
                    }
                });

                // Calculate CRA deduction for filtered amount
                const firstTierLimit = 5000;
                const firstTierRate = 0.72;
                const secondTierRate = 0.66;
                const firstTierKm = Math.min(totalKm, firstTierLimit);
                const secondTierKm = Math.max(0, totalKm - firstTierLimit);
                const deduction = (firstTierKm * firstTierRate) + (secondTierKm * secondTierRate);

                document.getElementById('mileage-count').textContent = visibleCount;
                document.getElementById('filtered-km').textContent = Math.round(totalKm) + ' km';
                document.getElementById('filtered-deduction').textContent = formatCurrency(deduction);
            }

            function clearMileageFilters() {
                document.getElementById('mileage-search').value = '';
                document.getElementById('mileage-month').value = '';
                document.getElementById('mileage-destination').value = '';
                const purposeEl = document.getElementById('mileage-purpose');
                if (purposeEl) purposeEl.value = '';
                document.getElementById('mileage-gps').value = '';
                filterMileage();
            }
            </script>
        </body>
        </html>
        """

        return html
    }

    private func generateCSS() -> String {
        return """
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
            line-height: 1.6;
            color: #333;
            background: #f5f5f5;
        }

        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }

        header {
            display: flex;
            justify-content: space-between;
            align-items: flex-start;
            background: linear-gradient(135deg, #52a5bf 0%, #3d8fa8 100%);
            color: white;
            padding: 30px;
            border-radius: 12px;
            margin-bottom: 30px;
        }

        header h1 {
            font-size: 28px;
            margin-bottom: 10px;
        }

        header h2 {
            font-size: 24px;
            font-weight: 500;
        }

        .report-info {
            text-align: right;
        }

        .period {
            font-size: 20px;
            font-weight: 600;
            margin-top: 5px;
        }

        .generated {
            opacity: 0.8;
            font-size: 14px;
        }

        section {
            background: white;
            border-radius: 12px;
            padding: 25px;
            margin-bottom: 25px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.08);
        }

        section h2 {
            color: #52a5bf;
            font-size: 20px;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 2px solid #52a5bf;
        }

        section h3 {
            color: #555;
            font-size: 16px;
            margin-bottom: 12px;
        }

        .summary-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 20px;
            margin-bottom: 25px;
        }

        .summary-card {
            background: #fafafa;
            border-radius: 8px;
            padding: 20px;
            border-left: 4px solid #ccc;
        }

        .summary-card.revenue { border-left-color: #22c55e; }
        .summary-card.expenses { border-left-color: #ef4444; }
        .summary-card.payroll { border-left-color: #3b82f6; }
        .summary-card.dividends { border-left-color: #f97316; }

        .summary-card table {
            width: 100%;
        }

        .summary-card td {
            padding: 6px 0;
        }

        .summary-card .indent td:first-child {
            padding-left: 20px;
            color: #666;
            font-size: 14px;
        }

        .summary-card .total {
            border-top: 1px solid #ddd;
            font-weight: 600;
        }

        .amount {
            text-align: right;
            font-family: 'SF Mono', Monaco, monospace;
        }

        .positive { color: #16a34a; }
        .negative { color: #dc2626; }

        .filter-controls {
            display: flex;
            flex-wrap: wrap;
            gap: 15px;
            align-items: flex-end;
            background: #f8fafc;
            padding: 20px;
            border-radius: 8px;
            margin-bottom: 15px;
            border: 1px solid #e2e8f0;
        }

        .filter-group {
            display: flex;
            flex-direction: column;
            gap: 5px;
        }

        .filter-group label {
            font-size: 12px;
            font-weight: 600;
            color: #64748b;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .filter-group input,
        .filter-group select {
            padding: 8px 12px;
            border: 1px solid #cbd5e1;
            border-radius: 6px;
            font-size: 14px;
            min-width: 150px;
            background: white;
        }

        .filter-group input:focus,
        .filter-group select:focus {
            outline: none;
            border-color: #52a5bf;
            box-shadow: 0 0 0 3px rgba(82, 165, 191, 0.1);
        }

        .clear-filters {
            padding: 8px 16px;
            background: #ef4444;
            color: white;
            border: none;
            border-radius: 6px;
            font-size: 14px;
            cursor: pointer;
            font-weight: 500;
        }

        .clear-filters:hover {
            background: #dc2626;
        }

        .filter-totals {
            display: flex;
            gap: 30px;
            padding: 12px 20px;
            background: #ecfdf5;
            border-radius: 6px;
            margin-bottom: 15px;
            font-size: 14px;
        }

        .filter-totals strong {
            color: #16a34a;
        }

        .results {
            background: #f0f9ff;
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 20px;
        }

        .result-row {
            display: flex;
            justify-content: space-between;
            padding: 12px 0;
            font-size: 16px;
        }

        .result-row.highlight {
            background: #52a5bf;
            color: white;
            margin: 10px -20px -20px;
            padding: 15px 20px;
            border-radius: 0 0 8px 8px;
            font-weight: 600;
            font-size: 18px;
        }

        .result-row.highlight .positive,
        .result-row.highlight .negative {
            color: white;
        }

        .tax-info {
            background: #fffbeb;
            border-radius: 8px;
            padding: 20px;
        }

        .tax-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
        }

        .mileage-summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 20px;
            margin-bottom: 25px;
        }

        .mileage-summary-card {
            background: #f8fafc;
            border-radius: 8px;
            padding: 20px;
            border: 1px solid #e2e8f0;
        }

        .mileage-summary-card h3 {
            color: #52a5bf;
            font-size: 14px;
            font-weight: 600;
            margin-bottom: 15px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .summary-table {
            width: 100%;
        }

        .summary-table td {
            padding: 8px 0;
            border-bottom: 1px solid #f1f5f9;
        }

        .summary-table tr:last-child td {
            border-bottom: none;
        }

        .summary-table .indent td:first-child {
            padding-left: 15px;
            color: #64748b;
            font-size: 13px;
        }

        .summary-table .total td {
            border-top: 2px solid #e2e8f0;
            border-bottom: none;
            padding-top: 12px;
        }

        .data-table {
            width: 100%;
            border-collapse: collapse;
        }

        .data-table th,
        .data-table td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #eee;
        }

        .data-table th {
            background: #f8f9fa;
            font-weight: 600;
            color: #555;
            font-size: 13px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .data-table tbody tr:hover {
            background: #f8f9fa;
        }

        .data-table tfoot {
            background: #f0f0f0;
        }

        .data-table tfoot td {
            border-top: 2px solid #ddd;
        }

        .status {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: 600;
        }

        .status.paid {
            background: #dcfce7;
            color: #166534;
        }

        .status.unpaid {
            background: #fef3c7;
            color: #92400e;
        }

        a {
            color: #52a5bf;
            text-decoration: none;
        }

        a:hover {
            text-decoration: underline;
        }

        footer {
            text-align: center;
            padding: 30px;
            color: #666;
            font-size: 14px;
        }

        @media print {
            body { background: white; }
            .container { max-width: none; }
            section { box-shadow: none; border: 1px solid #ddd; }
            header { background: #52a5bf !important; -webkit-print-color-adjust: exact; }
        }
        """
    }
}
