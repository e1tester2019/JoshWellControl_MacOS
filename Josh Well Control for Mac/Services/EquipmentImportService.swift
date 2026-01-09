//
//  EquipmentImportService.swift
//  Josh Well Control for Mac
//
//  Handles import/export of equipment registry data via CSV.
//

import Foundation
import SwiftData
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

class EquipmentImportService {
    static let shared = EquipmentImportService()
    private init() {}

    // MARK: - CSV Column Definitions

    enum CSVColumn: String, CaseIterable {
        case name = "Name"
        case serialNumber = "Serial Number"
        case model = "Model"
        case description = "Description"
        case category = "Category"
        case vendor = "Vendor"
        case notes = "Notes"
        case active = "Active"

        static var headers: String {
            allCases.map { $0.rawValue }.joined(separator: ",")
        }
    }

    // MARK: - Import Result

    struct ImportResult {
        let imported: Int
        let skipped: Int
        let errors: [String]
    }

    struct ParsedEquipment: Identifiable {
        let id = UUID()
        var name: String
        var serialNumber: String
        var model: String
        var description: String
        var categoryName: String
        var vendorName: String
        var notes: String
        var isActive: Bool
        var error: String?
        var vendorNotFound: Bool = false
        var categoryNotFound: Bool = false

        var isValid: Bool {
            !name.isEmpty && !serialNumber.isEmpty && error == nil
        }

        var hasWarnings: Bool {
            vendorNotFound || categoryNotFound
        }
    }

    // MARK: - Template Generation

    /// Generate a CSV template with headers and example rows
    func generateTemplate(existingEquipment: [RentalEquipment] = []) -> String {
        var lines: [String] = []

        // Header
        lines.append(CSVColumn.headers)

        // Example rows if no existing data
        if existingEquipment.isEmpty {
            lines.append("\"5\" DD Motor,ABC-12345,PowerDrive X5,\"5\" DD motor with bent housing,Motors,Acme Rentals,Good condition,TRUE")
            lines.append("\"7-3/4\" Stabilizer,XYZ-67890,Stab-750,\"7-3/4\" blade stabilizer,Stabilizers,Acme Rentals,,TRUE")
        } else {
            // Export existing equipment as examples
            for eq in existingEquipment.prefix(20) {
                lines.append(equipmentToCSVRow(eq))
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Convert equipment to CSV row
    private func equipmentToCSVRow(_ eq: RentalEquipment) -> String {
        let fields = [
            escapeCSV(eq.name),
            escapeCSV(eq.serialNumber),
            escapeCSV(eq.model),
            escapeCSV(eq.description_),
            escapeCSV(eq.category?.name ?? ""),
            escapeCSV(eq.vendor?.companyName ?? ""),
            escapeCSV(eq.notes),
            eq.isActive ? "TRUE" : "FALSE"
        ]
        return fields.joined(separator: ",")
    }

    /// Escape a field for CSV (handle commas, quotes, newlines)
    private func escapeCSV(_ value: String) -> String {
        let needsQuoting = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        if needsQuoting {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    // MARK: - Parsing

    /// Parse CSV text into equipment entries for preview
    func parseCSV(_ text: String, categories: [RentalCategory], vendors: [Vendor]) -> [ParsedEquipment] {
        var results: [ParsedEquipment] = []

        let lines = parseCSVLines(text)
        guard lines.count > 1 else { return [] }

        // First line is header - validate it
        let headerLine = lines[0]
        let headerMap = buildHeaderMap(headerLine)

        // Process data rows
        for (index, line) in lines.dropFirst().enumerated() {
            let fields = parseCSVLine(line)
            guard !fields.allSatisfy({ $0.isEmpty }) else { continue } // Skip empty rows

            var parsed = ParsedEquipment(
                name: getField(fields, column: .name, headerMap: headerMap),
                serialNumber: getField(fields, column: .serialNumber, headerMap: headerMap),
                model: getField(fields, column: .model, headerMap: headerMap),
                description: getField(fields, column: .description, headerMap: headerMap),
                categoryName: getField(fields, column: .category, headerMap: headerMap),
                vendorName: getField(fields, column: .vendor, headerMap: headerMap),
                notes: getField(fields, column: .notes, headerMap: headerMap),
                isActive: parseBoolean(getField(fields, column: .active, headerMap: headerMap))
            )

            // Validation - required fields
            if parsed.name.isEmpty {
                parsed.error = "Row \(index + 2): Name is required"
            } else if parsed.serialNumber.isEmpty {
                parsed.error = "Row \(index + 2): Serial Number is required"
            }

            // Check category exists if specified (warning only, not error)
            if !parsed.categoryName.isEmpty {
                let match = categories.first { $0.name.localizedCaseInsensitiveCompare(parsed.categoryName) == .orderedSame }
                if match == nil {
                    parsed.categoryNotFound = true
                }
            }

            // Check vendor exists if specified (warning only, not error)
            if !parsed.vendorName.isEmpty {
                let match = vendors.first { $0.companyName.localizedCaseInsensitiveCompare(parsed.vendorName) == .orderedSame }
                if match == nil {
                    parsed.vendorNotFound = true
                }
            }

            results.append(parsed)
        }

        return results
    }

    /// Build a map from column name to index
    private func buildHeaderMap(_ headerLine: String) -> [CSVColumn: Int] {
        let headers = parseCSVLine(headerLine)
        var map: [CSVColumn: Int] = [:]

        for (index, header) in headers.enumerated() {
            let trimmed = header.trimmingCharacters(in: .whitespaces)
            if let column = CSVColumn.allCases.first(where: { $0.rawValue.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
                map[column] = index
            }
        }

        return map
    }

    /// Get field value by column, using header map
    private func getField(_ fields: [String], column: CSVColumn, headerMap: [CSVColumn: Int]) -> String {
        guard let index = headerMap[column], index < fields.count else { return "" }
        return fields[index].trimmingCharacters(in: .whitespaces)
    }

    /// Parse boolean from string
    private func parseBoolean(_ value: String) -> Bool {
        let lower = value.lowercased().trimmingCharacters(in: .whitespaces)
        return lower == "true" || lower == "yes" || lower == "1" || lower == "y"
    }

    /// Split CSV text into lines (handling quoted newlines)
    private func parseCSVLines(_ text: String) -> [String] {
        // First, try simple split - works for CSVs without quoted newlines
        let simpleLines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }

        // Check if any line has unbalanced quotes (indicating quoted newlines)
        var hasQuotedNewlines = false
        for line in simpleLines {
            let quoteCount = line.filter { $0 == "\"" }.count
            if quoteCount % 2 != 0 {
                hasQuotedNewlines = true
                break
            }
        }

        if !hasQuotedNewlines {
            return simpleLines
        }

        // Complex case - handle quoted newlines manually
        var lines: [String] = []
        var currentLine = ""
        var inQuotes = false

        for char in text {
            if char == "\"" {
                inQuotes.toggle()
                currentLine.append(char)
            } else if char.isNewline && !inQuotes {
                if !currentLine.isEmpty {
                    lines.append(currentLine)
                    currentLine = ""
                }
            } else {
                currentLine.append(char)
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        return lines
    }

    /// Parse a single CSV line into fields
    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var currentField = ""
        var inQuotes = false
        var iterator = line.makeIterator()

        while let char = iterator.next() {
            if char == "\"" {
                if inQuotes {
                    // Check for escaped quote
                    if let next = iterator.next() {
                        if next == "\"" {
                            currentField.append("\"")
                        } else {
                            inQuotes = false
                            if next == "," {
                                fields.append(currentField)
                                currentField = ""
                            } else {
                                currentField.append(next)
                            }
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
            } else if char == "," && !inQuotes {
                fields.append(currentField)
                currentField = ""
            } else {
                currentField.append(char)
            }
        }

        fields.append(currentField)
        return fields
    }

    // MARK: - Import

    /// Import parsed equipment into the database
    func importEquipment(
        _ items: [ParsedEquipment],
        into context: ModelContext,
        categories: [RentalCategory],
        vendors: [Vendor],
        existingEquipment: [RentalEquipment],
        skipDuplicates: Bool = true
    ) -> ImportResult {
        var imported = 0
        var skipped = 0
        var errors: [String] = []

        // Build lookup for existing serial numbers
        let existingSerials = Set(existingEquipment.map { $0.serialNumber.lowercased() })

        for item in items {
            // Skip invalid items
            guard item.isValid else {
                if let error = item.error {
                    errors.append(error)
                }
                skipped += 1
                continue
            }

            // Check for duplicates
            if skipDuplicates && existingSerials.contains(item.serialNumber.lowercased()) {
                skipped += 1
                continue
            }

            // Create equipment
            let equipment = RentalEquipment(
                serialNumber: item.serialNumber,
                name: item.name,
                description: item.description,
                model: item.model
            )
            equipment.notes = item.notes
            equipment.isActive = item.isActive

            // Match category
            if !item.categoryName.isEmpty {
                equipment.category = categories.first {
                    $0.name.localizedCaseInsensitiveCompare(item.categoryName) == .orderedSame
                }
            }

            // Match vendor
            if !item.vendorName.isEmpty {
                equipment.vendor = vendors.first {
                    $0.companyName.localizedCaseInsensitiveCompare(item.vendorName) == .orderedSame
                }
            }

            context.insert(equipment)
            imported += 1
        }

        try? context.save()

        return ImportResult(imported: imported, skipped: skipped, errors: errors)
    }

    // MARK: - Export All

    /// Export all equipment to CSV
    func exportAllEquipment(_ equipment: [RentalEquipment]) -> String {
        var lines: [String] = [CSVColumn.headers]

        for eq in equipment.sorted(by: { $0.name < $1.name }) {
            lines.append(equipmentToCSVRow(eq))
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - File Operations

    #if os(macOS)
    /// Save template to file
    func saveTemplate(existingEquipment: [RentalEquipment] = []) {
        let template = generateTemplate(existingEquipment: existingEquipment)

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "equipment_template.csv"
        savePanel.title = "Save Equipment Template"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? template.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Import from file
    func importFromFile() -> String? {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.commaSeparatedText, .plainText]
        openPanel.allowsMultipleSelection = false
        openPanel.title = "Import Equipment"

        if openPanel.runModal() == .OK, let url = openPanel.url {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        return nil
    }

    /// Get text from clipboard
    func getClipboardText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    /// Export to file
    func exportToFile(_ equipment: [RentalEquipment]) {
        let csv = exportAllEquipment(equipment)

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.nameFieldStringValue = "equipment_export.csv"
        savePanel.title = "Export Equipment"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    #endif
}
