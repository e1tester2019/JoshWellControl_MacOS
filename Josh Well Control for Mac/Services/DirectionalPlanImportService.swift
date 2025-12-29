//
//  DirectionalPlanImportService.swift
//  Josh Well Control for Mac
//
//  Service for importing directional plan data from CSV/TSV files.
//

import Foundation

/// Service for importing directional plan data from CSV files
enum DirectionalPlanImportService {

    // MARK: - Import Result

    struct ImportResult {
        let stations: [ParsedStation]
        let name: String
        let sourceFileName: String
        let vsAzimuth_deg: Double?  // Vertical Section Azimuth if parsed from metadata
    }

    struct ParsedStation {
        let md: Double
        let inc: Double
        let azi: Double
        let tvd: Double
        let ns_m: Double
        let ew_m: Double
        let vs_m: Double?
    }

    enum ImportError: LocalizedError {
        case emptyFile
        case noDataRows
        case missingRequiredColumns(missing: [String])
        case invalidData(row: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .emptyFile:
                return "The file is empty."
            case .noDataRows:
                return "No data rows found in the file."
            case .missingRequiredColumns(let missing):
                return "Missing required columns: \(missing.joined(separator: ", "))"
            case .invalidData(let row, let message):
                return "Invalid data in row \(row): \(message)"
            }
        }
    }

    // MARK: - Main Import

    /// Import directional plan data from text content
    /// - Parameters:
    ///   - text: The CSV/TSV text content
    ///   - fileName: Original file name for metadata
    /// - Returns: ImportResult with parsed stations
    static func importPlan(from text: String, fileName: String) throws -> ImportResult {
        // Detect separator (tab or comma)
        let isTabSeparated = text.contains("\t") && text.split(separator: "\t").count > 3

        let rows: [[String: String]]
        if isTabSeparated {
            rows = parseTabSeparated(text: text)
        } else {
            rows = parseCSV(text: text)
        }

        guard !rows.isEmpty else {
            throw ImportError.noDataRows
        }

        // Find column indices
        let columnMap = buildColumnMap(from: rows)

        // Validate required columns
        var missing: [String] = []
        if columnMap.md == nil { missing.append("MD") }
        if columnMap.inc == nil { missing.append("Inc/Inclination") }
        if columnMap.azi == nil { missing.append("Azi/Azimuth") }
        if columnMap.tvd == nil { missing.append("TVD") }
        if columnMap.ns == nil { missing.append("NS/North-South") }
        if columnMap.ew == nil { missing.append("EW/East-West") }

        guard missing.isEmpty else {
            throw ImportError.missingRequiredColumns(missing: missing)
        }

        // Parse rows
        var stations: [ParsedStation] = []
        for row in rows {
            guard let md = parseDouble(row[columnMap.md!]),
                  let inc = parseDouble(row[columnMap.inc!]),
                  let azi = parseDouble(row[columnMap.azi!]),
                  let tvd = parseDouble(row[columnMap.tvd!]),
                  let ns = parseDouble(row[columnMap.ns!]),
                  let ew = parseDouble(row[columnMap.ew!]) else {
                // Skip rows with missing/invalid required values
                continue
            }

            let vs = columnMap.vs.flatMap { parseDouble(row[$0]) }

            let station = ParsedStation(
                md: md,
                inc: inc,
                azi: azi,
                tvd: tvd,
                ns_m: ns,
                ew_m: ew,
                vs_m: vs
            )
            stations.append(station)
        }

        guard !stations.isEmpty else {
            throw ImportError.noDataRows
        }

        // Sort by MD
        let sortedStations = stations.sorted { $0.md < $1.md }

        // Generate name from file
        let baseName = (fileName as NSString).deletingPathExtension
        let name = baseName.isEmpty ? "Imported Plan" : baseName

        // Try to parse VS Azimuth from metadata in the text
        let vsAzimuth = parseVSAzimuth(from: text)

        return ImportResult(
            stations: sortedStations,
            name: name,
            sourceFileName: fileName,
            vsAzimuth_deg: vsAzimuth
        )
    }

    // MARK: - Metadata Parsing

    /// Parse Vertical Section Azimuth from metadata lines
    /// Looks for patterns like "Vertical Section Azimuth: 285.761 °(TRUE North)"
    private static func parseVSAzimuth(from text: String) -> Double? {
        // Common patterns for VS azimuth in directional plan exports
        let patterns = [
            "Vertical Section Azimuth[:\\s]+([\\d.]+)",
            "VS Azimuth[:\\s]+([\\d.]+)",
            "VSD[:\\s]+([\\d.]+)",
            "V\\.S\\. Azimuth[:\\s]+([\\d.]+)"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range) {
                    if match.numberOfRanges >= 2,
                       let valueRange = Range(match.range(at: 1), in: text) {
                        let valueStr = String(text[valueRange])
                        if let value = Double(valueStr) {
                            return value
                        }
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Column Mapping

    private struct ColumnMap {
        var md: String?
        var inc: String?
        var azi: String?
        var tvd: String?
        var ns: String?
        var ew: String?
        var vs: String?
    }

    private static func buildColumnMap(from rows: [[String: String]]) -> ColumnMap {
        guard let firstRow = rows.first else { return ColumnMap() }
        let keys = Array(firstRow.keys)

        var map = ColumnMap()

        // MD column variants (newlines in headers are normalized to spaces)
        map.md = findColumn(keys, variants: [
            "MD", "MD(m)", "MD (m)", "Measured Depth", "Meas Depth", "Depth"
        ])

        // Inclination column variants
        map.inc = findColumn(keys, variants: [
            "Inc", "Incl", "Incl (°)", "Inc(deg)", "Inc (deg)", "INCL", "INCL (°)",
            "Inclination", "Inclination (deg)", "Inclination (°)"
        ])

        // Azimuth column variants
        map.azi = findColumn(keys, variants: [
            "Azi", "Azm", "Azim", "Azim (°)", "Azi(deg)", "Azm(deg)", "Azi (deg)", "Azm (deg)",
            "AZI", "AZI (°)", "Azimuth", "Azimuth (deg)", "Azimuth (°)"
        ])

        // TVD column variants
        map.tvd = findColumn(keys, variants: [
            "TVD", "TVD(m)", "TVD (m)", "True Vertical Depth"
        ])

        // North-South column variants
        map.ns = findColumn(keys, variants: [
            "NS", "NS(m)", "NS (m)", "North-South", "North", "N/S", "+N/-S"
        ])

        // East-West column variants
        map.ew = findColumn(keys, variants: [
            "EW", "EW(m)", "EW (m)", "East-West", "East", "E/W", "+E/-W"
        ])

        // Vertical Section column variants (optional)
        map.vs = findColumn(keys, variants: [
            "VS", "VS(m)", "VS (m)", "Vertical Section"
        ])

        return map
    }

    private static func findColumn(_ keys: [String], variants: [String]) -> String? {
        for key in keys {
            let normalized = normalizeHeader(key)
            for variant in variants {
                let normalizedVariant = normalizeHeader(variant)
                if normalized.caseInsensitiveCompare(normalizedVariant) == .orderedSame {
                    return key
                }
            }
        }
        return nil
    }

    // MARK: - Parsing Helpers

    /// Normalize header by removing BOM, collapsing whitespace/newlines
    private static func normalizeHeader(_ s: String) -> String {
        var result = s.trimmingCharacters(in: .whitespacesAndNewlines)
        result = result.replacingOccurrences(of: "\u{FEFF}", with: "")  // Remove BOM
        result = result.replacingOccurrences(of: "\r\n", with: " ")    // Windows newlines
        result = result.replacingOccurrences(of: "\n", with: " ")      // Unix newlines
        result = result.replacingOccurrences(of: "\r", with: " ")      // Old Mac newlines
        // Collapse multiple spaces into one
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func parseDouble(_ raw: String?) -> Double? {
        guard var s = raw else { return nil }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: ",", with: "")  // Remove thousands separator
        return Double(s)
    }

    // MARK: - CSV Parsing

    private static func parseCSV(text: String) -> [[String: String]] {
        var rows: [[String: String]] = []
        let lines = text.split(whereSeparator: { $0.isNewline }).map(String.init)
        guard let headerLine = lines.first else { return [] }

        let headers = splitCSVLine(headerLine).map { normalizeHeader($0) }

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let cols = splitCSVLine(line)
            var row: [String: String] = [:]
            for (i, h) in headers.enumerated() {
                row[h] = i < cols.count ? cols[i] : ""
            }
            rows.append(row)
        }
        return rows
    }

    private static func splitCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        while let ch = iterator.next() {
            if ch == "\"" { inQuotes.toggle(); continue }
            if ch == "," && !inQuotes {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                continue
            }
            current.append(ch)
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }

    // MARK: - Tab-Separated Parsing

    private static func parseTabSeparated(text: String) -> [[String: String]] {
        // Use quote-aware line splitting to handle embedded newlines in quoted fields
        let lines = splitLinesQuoteAware(text)
        var dataLines = lines

        // Skip comment lines at the beginning
        while let first = dataLines.first,
              first.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
            dataLines.removeFirst()
        }

        guard let headerLine = dataLines.first else { return [] }
        let headerFields = splitTabLineQuoteAware(headerLine)
        let headers = headerFields.map { normalizeHeader($0) }

        var rows: [[String: String]] = []
        for line in dataLines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed == "#EOF" { continue }

            let cols = splitTabLineQuoteAware(line)
            var row: [String: String] = [:]
            for (i, h) in headers.enumerated() {
                row[h] = i < cols.count ? cols[i] : ""
            }
            rows.append(row)
        }
        return rows
    }

    /// Split text into lines, respecting quoted fields that may contain newlines
    private static func splitLinesQuoteAware(_ text: String) -> [String] {
        var lines: [String] = []
        var current = ""
        var inQuotes = false

        for char in text {
            if char == "\"" {
                inQuotes.toggle()
                current.append(char)
            } else if (char == "\n" || char == "\r") && !inQuotes {
                // End of logical line (outside quotes)
                if !current.isEmpty {
                    lines.append(current)
                    current = ""
                }
                // Skip \r\n as single line break
                continue
            } else {
                current.append(char)
            }
        }

        // Don't forget the last line
        if !current.isEmpty {
            lines.append(current)
        }

        return lines
    }

    /// Split a tab-separated line, respecting quoted fields
    private static func splitTabLineQuoteAware(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
                // Don't include the quote character in the result
                continue
            } else if char == "\t" && !inQuotes {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }

        // Add the last field
        result.append(current.trimmingCharacters(in: .whitespaces))

        return result
    }
}
