//
//  ReceiptOCRService.swift
//  Josh Well Control for Mac
//
//  Vision framework OCR service for extracting receipt data (iOS only)
//

#if os(iOS)
import Foundation
import Vision
import UIKit

/// Service for extracting receipt data using Vision framework OCR
class ReceiptOCRService {
    static let shared = ReceiptOCRService()

    private init() {}

    // MARK: - OCR Result

    struct OCRResult {
        var vendor: String?
        var date: Date?
        var totalAmount: Double?
        var subtotal: Double?
        var gstAmount: Double?
        var pstAmount: Double?
        var suggestedCategory: ExpenseCategory?
        var confidence: Double
        var rawText: String

        static var empty: OCRResult {
            OCRResult(confidence: 0, rawText: "")
        }
    }

    enum OCRError: LocalizedError {
        case invalidImage
        case recognitionFailed
        case noTextFound

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return "Unable to process image. Please try again."
            case .recognitionFailed:
                return "Text recognition failed."
            case .noTextFound:
                return "No text found in image."
            }
        }
    }

    // MARK: - Main OCR Function

    /// Process a receipt image and extract structured data
    func processReceipt(image: UIImage) async throws -> OCRResult {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        // Perform text recognition
        let rawText = try await performOCR(on: cgImage)

        guard !rawText.isEmpty else {
            throw OCRError.noTextFound
        }

        // Extract structured data
        let result = parseReceiptText(rawText)

        return result
    }

    // MARK: - Vision OCR

    private func performOCR(on image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }

                let text = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")

                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-CA", "en-US", "en-GB"]

            let handler = VNImageRequestHandler(cgImage: image, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.recognitionFailed)
            }
        }
    }

    // MARK: - Text Parsing

    private func parseReceiptText(_ text: String) -> OCRResult {
        var result = OCRResult(confidence: 0.0, rawText: text)

        // Extract total amount
        result.totalAmount = extractTotalAmount(from: text)

        // Extract date
        result.date = extractDate(from: text)

        // Extract vendor (usually first lines)
        result.vendor = extractVendor(from: text)

        // Extract tax breakdown
        let taxes = extractTaxes(from: text)
        result.gstAmount = taxes.gst
        result.pstAmount = taxes.pst
        result.subtotal = taxes.subtotal

        // Suggest category based on vendor
        result.suggestedCategory = suggestCategory(vendor: result.vendor, text: text)

        // Calculate confidence
        result.confidence = calculateConfidence(result)

        return result
    }

    // MARK: - Amount Extraction

    private func extractTotalAmount(from text: String) -> Double? {
        let lines = text.uppercased()

        // Patterns for total amount (prioritized) - more flexible matching
        // Allow optional decimals, various spacing, $ signs
        let totalPatterns: [(pattern: String, priority: Int)] = [
            // Exact "TOTAL" patterns - highest priority
            (#"(?:GRAND\s*)?TOTAL\s*[:=]?\s*\$?\s*(\d+[.,]\d{2})"#, 1),
            (#"(?:GRAND\s*)?TOTAL\s*[:=]?\s*\$?\s*(\d+)\s*$"#, 1),  // No decimals
            (#"AMOUNT\s*(?:DUE|OWING|OWED)\s*[:=]?\s*\$?\s*(\d+[.,]\d{2})"#, 1),
            (#"AMOUNT\s*(?:DUE|OWING|OWED)\s*[:=]?\s*\$?\s*(\d+)\s*$"#, 1),
            (#"SALE\s*TOTAL\s*[:=]?\s*\$?\s*(\d+[.,]\d{2})"#, 1),
            (#"BALANCE\s*(?:DUE|OWING)?\s*[:=]?\s*\$?\s*(\d+[.,]\d{2})"#, 2),
            (#"TTL\s*[:=]?\s*\$?\s*(\d+[.,]\d{2})"#, 3),
            // "TOTAL" on one line, amount on next - check line by line
            (#"\$\s*(\d+[.,]\d{2})"#, 4),  // Generic dollar amount as fallback
        ]

        var bestMatch: (amount: Double, priority: Int)?

        // First, try pattern matching on full text
        for (pattern, priority) in totalPatterns.dropLast() {  // Skip the fallback pattern first
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: lines, options: [], range: NSRange(lines.startIndex..., in: lines)),
               let range = Range(match.range(at: 1), in: lines) {

                var amountStr = String(lines[range])
                    .replacingOccurrences(of: ",", with: ".")
                    .replacingOccurrences(of: " ", with: "")

                // Add .00 if no decimal
                if !amountStr.contains(".") {
                    amountStr += ".00"
                }

                if let amount = Double(amountStr), amount > 0 {
                    if bestMatch == nil || priority < bestMatch!.priority {
                        bestMatch = (amount, priority)
                    }
                }
            }
        }

        // If no match found, try line-by-line analysis
        if bestMatch == nil {
            let textLines = text.uppercased().components(separatedBy: .newlines)

            for (index, line) in textLines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                // Look for "TOTAL" label
                if trimmed.contains("TOTAL") || trimmed.contains("AMOUNT DUE") {
                    // Try to extract amount from same line
                    if let amount = extractAmountFromLine(trimmed) {
                        if bestMatch == nil || amount > (bestMatch?.amount ?? 0) {
                            bestMatch = (amount, 2)
                        }
                    }
                    // Try next line
                    else if index + 1 < textLines.count {
                        if let amount = extractAmountFromLine(textLines[index + 1]) {
                            bestMatch = (amount, 2)
                        }
                    }
                }
            }

            // Last resort: find the largest dollar amount (likely the total)
            if bestMatch == nil {
                var largestAmount: Double = 0
                let dollarPattern = #"\$?\s*(\d+[.,]\d{2})"#
                if let regex = try? NSRegularExpression(pattern: dollarPattern, options: []) {
                    let matches = regex.matches(in: lines, options: [], range: NSRange(lines.startIndex..., in: lines))
                    for match in matches {
                        if let range = Range(match.range(at: 1), in: lines) {
                            let amountStr = String(lines[range]).replacingOccurrences(of: ",", with: ".")
                            if let amount = Double(amountStr), amount > largestAmount {
                                largestAmount = amount
                            }
                        }
                    }
                }
                if largestAmount > 0 {
                    bestMatch = (largestAmount, 5)
                }
            }
        }

        return bestMatch?.amount
    }

    /// Extract a dollar amount from a single line
    private func extractAmountFromLine(_ line: String) -> Double? {
        let patterns = [
            #"\$\s*(\d+[.,]\d{2})"#,
            #"(\d+[.,]\d{2})\s*$"#,
            #"\$\s*(\d+)\s*$"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
               let range = Range(match.range(at: 1), in: line) {
                var amountStr = String(line[range])
                    .replacingOccurrences(of: ",", with: ".")
                    .replacingOccurrences(of: " ", with: "")
                if !amountStr.contains(".") {
                    amountStr += ".00"
                }
                if let amount = Double(amountStr), amount > 0 {
                    return amount
                }
            }
        }
        return nil
    }

    // MARK: - Date Extraction

    private func extractDate(from text: String) -> Date? {
        // First, try unambiguous formats (month names, ISO, etc.)
        if let date = extractUnambiguousDate(from: text) {
            return date
        }

        // Then handle numeric dates with smart parsing
        return extractNumericDate(from: text)
    }

    /// Extract dates with month names (unambiguous)
    private func extractUnambiguousDate(from text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_CA")

        let unambiguousPatterns: [(regex: String, format: String)] = [
            // YYYY-MM-DD (ISO format - unambiguous)
            (#"(\d{4}-\d{2}-\d{2})"#, "yyyy-MM-dd"),
            // DD MMM YYYY (e.g., 15 Dec 2024)
            (#"(\d{1,2}\s+[A-Za-z]{3,9}\s+\d{4})"#, "dd MMM yyyy"),
            // MMM DD, YYYY (e.g., Dec 15, 2024)
            (#"([A-Za-z]{3,9}\s+\d{1,2},?\s+\d{4})"#, "MMM dd, yyyy"),
            // DD-MMM-YYYY (e.g., 15-Dec-2024)
            (#"(\d{1,2}-[A-Za-z]{3,9}-\d{4})"#, "dd-MMM-yyyy"),
            // YYYY/MM/DD
            (#"(\d{4}/\d{2}/\d{2})"#, "yyyy/MM/dd")
        ]

        for (pattern, format) in unambiguousPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {

                let dateStr = String(text[range])
                    .replacingOccurrences(of: ",", with: "")

                formatter.dateFormat = format
                if let date = formatter.date(from: dateStr), isReasonableDate(date) {
                    return date
                }

                // Try with full month name
                formatter.dateFormat = format.replacingOccurrences(of: "MMM", with: "MMMM")
                if let date = formatter.date(from: dateStr), isReasonableDate(date) {
                    return date
                }
            }
        }

        return nil
    }

    /// Extract numeric dates (DD/MM/YYYY or MM/DD/YYYY) with smart parsing
    private func extractNumericDate(from text: String) -> Date? {
        // Match numeric date patterns
        let numericPattern = #"(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})"#

        guard let regex = try? NSRegularExpression(pattern: numericPattern, options: []) else {
            return nil
        }

        let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))

        for match in matches {
            guard match.numberOfRanges >= 4,
                  let range1 = Range(match.range(at: 1), in: text),
                  let range2 = Range(match.range(at: 2), in: text),
                  let range3 = Range(match.range(at: 3), in: text),
                  let num1 = Int(text[range1]),
                  let num2 = Int(text[range2]),
                  var year = Int(text[range3]) else {
                continue
            }

            // Normalize 2-digit year
            if year < 100 {
                year += year < 50 ? 2000 : 1900
            }

            // Skip if year doesn't make sense for a receipt
            let currentYear = Calendar.current.component(.year, from: Date())
            guard year >= currentYear - 2 && year <= currentYear + 1 else {
                continue
            }

            // Determine which is day and which is month
            let possibleDates = determineDayMonth(num1: num1, num2: num2, year: year)

            // Return the most reasonable date
            for date in possibleDates {
                if isReasonableDate(date) {
                    return date
                }
            }
        }

        return nil
    }

    /// Determine day/month from two numbers, preferring DD/MM/YYYY (Canadian format)
    private func determineDayMonth(num1: Int, num2: Int, year: Int) -> [Date] {
        var candidates: [Date] = []

        // If num1 > 12, it MUST be the day (DD/MM/YYYY)
        if num1 > 12 && num1 <= 31 && num2 >= 1 && num2 <= 12 {
            if let date = createDate(day: num1, month: num2, year: year) {
                candidates.append(date)
            }
        }
        // If num2 > 12, it MUST be the day (MM/DD/YYYY)
        else if num2 > 12 && num2 <= 31 && num1 >= 1 && num1 <= 12 {
            if let date = createDate(day: num2, month: num1, year: year) {
                candidates.append(date)
            }
        }
        // Ambiguous case (both could be day or month)
        else if num1 >= 1 && num1 <= 12 && num2 >= 1 && num2 <= 12 {
            // Prefer DD/MM/YYYY (Canadian format) - try this first
            if let date = createDate(day: num1, month: num2, year: year) {
                candidates.append(date)
            }
            // Also try MM/DD/YYYY as fallback
            if let date = createDate(day: num2, month: num1, year: year) {
                candidates.append(date)
            }
        }
        // Edge case: num1 could be day > 12, num2 is month
        else if num1 >= 1 && num1 <= 31 && num2 >= 1 && num2 <= 12 {
            if let date = createDate(day: num1, month: num2, year: year) {
                candidates.append(date)
            }
        }

        return candidates
    }

    /// Create a date from components
    private func createDate(day: Int, month: Int, year: Int) -> Date? {
        var components = DateComponents()
        components.day = day
        components.month = month
        components.year = year

        return Calendar.current.date(from: components)
    }

    /// Check if a date is reasonable for a receipt (not too far in past/future)
    private func isReasonableDate(_ date: Date) -> Bool {
        let now = Date()
        let calendar = Calendar.current

        // Receipt date should be within last 2 years and not more than 1 day in future
        let twoYearsAgo = calendar.date(byAdding: .year, value: -2, to: now) ?? now
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now

        return date >= twoYearsAgo && date <= tomorrow
    }

    // MARK: - Vendor Extraction

    private func extractVendor(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.count >= 3 }

        // Skip lines that look like dates, amounts, or common receipt junk
        let skipPatterns = [
            #"^\d+[/-]"#,           // Dates
            #"^\$"#,                // Amounts
            #"^[0-9\s\-\(\)]+$"#,   // Phone numbers
            #"(?i)^(receipt|invoice|thank|welcome|date|time|terminal|store)"#
        ]

        for line in lines.prefix(5) {
            var shouldSkip = false
            for pattern in skipPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                   regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)) != nil {
                    shouldSkip = true
                    break
                }
            }

            if !shouldSkip && line.count >= 3 {
                // Clean up the vendor name
                let cleaned = line
                    .replacingOccurrences(of: "#", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty {
                    return cleaned
                }
            }
        }

        return nil
    }

    // MARK: - Tax Extraction

    private func extractTaxes(from text: String) -> (gst: Double?, pst: Double?, subtotal: Double?) {
        let lines = text.uppercased()
        var gst: Double?
        var pst: Double?
        var subtotal: Double?

        // GST patterns (5% in Canada) - more flexible
        let gstPatterns = [
            #"GST\s*[@#]?\s*5\.?0?0?%?\s*[:=]?\s*\$?\s*(\d+[.,]\d{2})"#,
            #"GST\s*[:=]?\s*\$?\s*(\d+[.,]\d{2})"#,
            #"GST\s*[:=]?\s*\$?\s*(\d+)"#,  // No decimals
            #"HST\s*[:=]?\s*\$?\s*(\d+[.,]\d{2})"#,
            #"HST\s*[:=]?\s*\$?\s*(\d+)"#,
            #"(?:FED(?:ERAL)?\.?\s*)?TAX\s*[:=]?\s*\$?\s*(\d+[.,]\d{2})"#,
            #"5%\s*(?:TAX|GST)\s*[:=]?\s*\$?\s*(\d+[.,]\d{2})"#,
            #"TAX\s*1?\s*[:=]?\s*\$?\s*(\d+[.,]\d{2})"#
        ]

        for pattern in gstPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: lines, options: [], range: NSRange(lines.startIndex..., in: lines)),
               let range = Range(match.range(at: 1), in: lines) {
                var amountStr = String(lines[range]).replacingOccurrences(of: ",", with: ".")
                if !amountStr.contains(".") { amountStr += ".00" }
                if let amount = Double(amountStr), amount > 0 {
                    gst = amount
                    break
                }
            }
        }

        // PST patterns (BC: 7%)
        let pstPatterns = [
            #"PST\s*[@#]?\s*7\.?0?0?%?\s*[:=]?\s*\$?\s*(\d+[.,]\d{2})"#,
            #"PST\s*[:=]?\s*\$?\s*(\d+[.,]\d{2})"#,
            #"PST\s*[:=]?\s*\$?\s*(\d+)"#,
            #"PROV(?:INCIAL)?\.?\s*TAX\s*[:=]?\s*\$?\s*(\d+[.,]\d{2})"#,
            #"7%\s*(?:TAX|PST)\s*[:=]?\s*\$?\s*(\d+[.,]\d{2})"#,
            #"TAX\s*2\s*[:=]?\s*\$?\s*(\d+[.,]\d{2})"#
        ]

        for pattern in pstPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: lines, options: [], range: NSRange(lines.startIndex..., in: lines)),
               let range = Range(match.range(at: 1), in: lines) {
                var amountStr = String(lines[range]).replacingOccurrences(of: ",", with: ".")
                if !amountStr.contains(".") { amountStr += ".00" }
                if let amount = Double(amountStr), amount > 0 {
                    pst = amount
                    break
                }
            }
        }

        // Subtotal patterns
        let subtotalPatterns = [
            #"SUB\s*[-]?\s*TOTAL\s*[:=]?\s*\$?\s*(\d+[.,]\d{2})"#,
            #"SUBTOTAL\s*[:=]?\s*\$?\s*(\d+[.,]\d{2})"#,
            #"SUBTOTAL\s*[:=]?\s*\$?\s*(\d+)"#,
            #"SUB\s*TTL\s*[:=]?\s*\$?\s*(\d+[.,]\d{2})"#,
            #"BEFORE\s*TAX\s*[:=]?\s*\$?\s*(\d+[.,]\d{2})"#
        ]

        for pattern in subtotalPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: lines, options: [], range: NSRange(lines.startIndex..., in: lines)),
               let range = Range(match.range(at: 1), in: lines) {
                var amountStr = String(lines[range]).replacingOccurrences(of: ",", with: ".")
                if !amountStr.contains(".") { amountStr += ".00" }
                if let amount = Double(amountStr), amount > 0 {
                    subtotal = amount
                    break
                }
            }
        }

        // Line-by-line fallback for taxes
        if gst == nil || pst == nil || subtotal == nil {
            let textLines = text.uppercased().components(separatedBy: .newlines)
            for (index, line) in textLines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                // Check for GST
                if gst == nil && (trimmed.contains("GST") || trimmed.contains("HST")) {
                    if let amount = extractAmountFromLine(trimmed) {
                        gst = amount
                    } else if index + 1 < textLines.count {
                        gst = extractAmountFromLine(textLines[index + 1])
                    }
                }

                // Check for PST
                if pst == nil && trimmed.contains("PST") {
                    if let amount = extractAmountFromLine(trimmed) {
                        pst = amount
                    } else if index + 1 < textLines.count {
                        pst = extractAmountFromLine(textLines[index + 1])
                    }
                }

                // Check for subtotal
                if subtotal == nil && (trimmed.contains("SUBTOTAL") || trimmed.contains("SUB TOTAL") || trimmed.contains("SUB-TOTAL")) {
                    if let amount = extractAmountFromLine(trimmed) {
                        subtotal = amount
                    } else if index + 1 < textLines.count {
                        subtotal = extractAmountFromLine(textLines[index + 1])
                    }
                }
            }
        }

        return (gst, pst, subtotal)
    }

    // MARK: - Category Suggestion

    private func suggestCategory(vendor: String?, text: String) -> ExpenseCategory {
        let vendorLower = vendor?.lowercased() ?? ""
        let textLower = text.lowercased()
        let combined = vendorLower + " " + textLower

        // Fuel stations
        let fuelKeywords = ["shell", "esso", "petro-canada", "petro canada", "petrocan",
                           "chevron", "husky", "co-op gas", "fas gas", "domo", "7-eleven gas",
                           "fuel", "gasoline", "diesel", "litre", "liter", "pump"]
        if fuelKeywords.contains(where: { combined.contains($0) }) {
            return .fuel
        }

        // Hotels/Lodging
        let lodgingKeywords = ["hotel", "inn", "motel", "lodge", "suites", "marriott",
                              "hilton", "holiday inn", "best western", "comfort inn",
                              "super 8", "days inn", "room", "accommodation"]
        if lodgingKeywords.contains(where: { combined.contains($0) }) {
            return .lodging
        }

        // Restaurants/Meals
        let mealKeywords = ["restaurant", "cafe", "coffee", "diner", "grill", "pizza",
                           "burger", "subway", "mcdonald", "tim horton", "starbucks",
                           "a&w", "wendy", "tip", "gratuity", "server"]
        if mealKeywords.contains(where: { combined.contains($0) }) {
            return .meals
        }

        // Tools/Equipment stores
        let toolKeywords = ["canadian tire", "home depot", "home hardware", "princess auto",
                           "rona", "lowes", "tool", "hardware"]
        if toolKeywords.contains(where: { combined.contains($0) }) {
            return .toolsEquipment
        }

        // Office supplies
        let officeKeywords = ["staples", "office depot", "grand & toy", "office"]
        if officeKeywords.contains(where: { combined.contains($0) }) {
            return .officeSupplies
        }

        // Phone/Communications
        let phoneKeywords = ["telus", "rogers", "bell", "shaw", "fido", "koodo",
                            "virgin mobile", "freedom mobile", "phone", "wireless"]
        if phoneKeywords.contains(where: { combined.contains($0) }) {
            return .phone
        }

        // Vehicle maintenance
        let vehicleKeywords = ["oil change", "tire", "midas", "jiffy lube", "mr. lube",
                              "canadian tire auto", "kal tire", "mechanic", "automotive"]
        if vehicleKeywords.contains(where: { combined.contains($0) }) {
            return .vehicleMaintenance
        }

        // Work clothing
        let clothingKeywords = ["mark's", "marks work", "workwear", "coverall", "safety"]
        if clothingKeywords.contains(where: { combined.contains($0) }) {
            return .clothing
        }

        return .other
    }

    // MARK: - Confidence Calculation

    private func calculateConfidence(_ result: OCRResult) -> Double {
        var score = 0.0

        // Weight each extracted field
        if result.totalAmount != nil { score += 0.35 }
        if result.date != nil { score += 0.20 }
        if result.vendor != nil { score += 0.20 }
        if result.gstAmount != nil { score += 0.10 }
        if result.subtotal != nil { score += 0.10 }
        if result.suggestedCategory != .other { score += 0.05 }

        return min(score, 1.0)
    }
}
#endif
