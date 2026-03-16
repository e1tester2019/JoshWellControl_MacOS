//
//  RigDataImportService.swift
//  Josh Well Control for Mac
//
//  CSV parsing and processing pipeline for rig sensor data (hook load, bit depth, block height).
//  Produces per-stand averages and static weight measurements for sim vs rig comparison.
//

import Foundation
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

// MARK: - Raw CSV Row

struct RigCSVRow {
    var bitDepth_m: Double
    var hookLoad_kDaN: Double
    var blockHeight_m: Double
}

// MARK: - Import Configuration

struct RigImportConfig {
    var tripType: String = "in"          // "in" or "out"
    var standLength_m: Double = 28.0
    var blockHeightThreshold_m: Double = 19.9
    var connectionHeight_m: Double = 19.4
    var topDriveWeight_kDaN: Double = 20.0
    var maxMinusFilter_kDaN: Double = 15.0
}

// MARK: - Processing Result

struct RigProcessingResult {
    var stands: [RigStandData]
    var staticWeights: [RigStaticWeight]
    var maxBitDepth_m: Double
    var minBitDepth_m: Double
    var totalRawRows: Int
    var filteredRows: Int
}

// MARK: - Service

class RigDataImportService {
    static let shared = RigDataImportService()
    private init() {}

    // MARK: - File Picker

    #if os(macOS)
    func pickCSVFile() -> (text: String, fileName: String)? {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.commaSeparatedText, .plainText]
        openPanel.allowsMultipleSelection = false
        openPanel.title = "Import Rig Data CSV"

        if openPanel.runModal() == .OK, let url = openPanel.url {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return (text, url.lastPathComponent)
            }
        }
        return nil
    }
    #endif

    // MARK: - CSV Parsing

    /// Parse raw CSV text into rows, with fuzzy column matching.
    func parseCSV(_ text: String) -> [RigCSVRow] {
        let lines = parseCSVLines(text)
        guard lines.count > 1 else { return [] }

        let headerMap = buildHeaderMap(lines[0])
        guard let depthIdx = headerMap["bitDepth"],
              let hlIdx = headerMap["hookLoad"],
              let bhIdx = headerMap["blockHeight"] else {
            return []
        }

        var rows: [RigCSVRow] = []
        for line in lines.dropFirst() {
            let fields = parseCSVLine(line)
            guard fields.count > max(depthIdx, hlIdx, bhIdx) else { continue }

            let depth = Double(fields[depthIdx].trimmingCharacters(in: .whitespaces))
            let hl = Double(fields[hlIdx].trimmingCharacters(in: .whitespaces))
            let bh = Double(fields[bhIdx].trimmingCharacters(in: .whitespaces))

            guard let d = depth, let h = hl, let b = bh else { continue }
            rows.append(RigCSVRow(bitDepth_m: d, hookLoad_kDaN: h, blockHeight_m: b))
        }
        return rows
    }

    // MARK: - Processing Pipeline

    /// Full processing: filter → bin → extract static weights
    func process(rows: [RigCSVRow], config: RigImportConfig) -> RigProcessingResult {
        guard !rows.isEmpty else {
            return RigProcessingResult(stands: [], staticWeights: [], maxBitDepth_m: 0, minBitDepth_m: 0, totalRawRows: 0, filteredRows: 0)
        }

        let allDepths = rows.map(\.bitDepth_m)
        let maxDepth = allDepths.max() ?? 0
        let minDepth = allDepths.min() ?? 0

        // 1. Detect monotonic trip section and filter
        let filtered = filterRows(rows: rows, config: config)

        // 2. Bin into stands
        let stands = binIntoStands(rows: filtered, config: config)

        // 3. Extract static weights (trip-in only)
        var staticWeights: [RigStaticWeight] = []
        if config.tripType == "in" {
            staticWeights = extractStaticWeights(rows: rows, config: config)
        }

        return RigProcessingResult(
            stands: stands,
            staticWeights: staticWeights,
            maxBitDepth_m: maxDepth,
            minBitDepth_m: minDepth,
            totalRawRows: rows.count,
            filteredRows: filtered.count
        )
    }

    // MARK: - Filter Rows

    private func filterRows(rows: [RigCSVRow], config: RigImportConfig) -> [RigCSVRow] {
        // Find the trip section: detect max depth index, then extract monotonic portion
        let tripRows: [RigCSVRow]
        if config.tripType == "in" {
            tripRows = extractMonotonicIncreasing(rows)
        } else {
            tripRows = extractMonotonicDecreasing(rows)
        }

        // Apply filters:
        // 1. BH > threshold (pipe not in slips)
        // 2. HL > TDW (string in hole, not just top drive)
        // 3. BH delta threshold: require meaningful BH movement in correct direction
        //    (avoids rejecting on single noisy sample like strict direction check did)
        let isTripIn = config.tripType == "in"
        let bhMinDelta = 0.05  // minimum BH change to count as "moving" (m)
        var filtered: [RigCSVRow] = []
        for i in 0..<tripRows.count {
            let row = tripRows[i]
            guard row.blockHeight_m > config.blockHeightThreshold_m else { continue }
            guard row.hookLoad_kDaN > config.topDriveWeight_kDaN else { continue }

            // Use 3-sample BH window for direction check (more stable than consecutive pair)
            if i >= 2 {
                let bhDelta = tripRows[i].blockHeight_m - tripRows[i - 2].blockHeight_m
                if isTripIn && bhDelta > -bhMinDelta { continue }   // BH should be decreasing
                if !isTripIn && bhDelta < bhMinDelta { continue }   // BH should be increasing
            } else if i >= 1 {
                let bhDelta = tripRows[i].blockHeight_m - tripRows[i - 1].blockHeight_m
                if isTripIn && bhDelta > -bhMinDelta { continue }
                if !isTripIn && bhDelta < bhMinDelta { continue }
            }
            filtered.append(row)
        }
        return filtered
    }

    private func extractMonotonicIncreasing(_ rows: [RigCSVRow]) -> [RigCSVRow] {
        // Find max depth index
        guard let maxIdx = rows.indices.max(by: { rows[$0].bitDepth_m < rows[$1].bitDepth_m }) else { return rows }
        // Take rows up to and including max depth where depth is generally increasing
        var result: [RigCSVRow] = []
        var lastDepth: Double = -1
        for i in 0...maxIdx {
            if rows[i].bitDepth_m >= lastDepth - 5 { // 5m tolerance for jitter
                result.append(rows[i])
                lastDepth = rows[i].bitDepth_m
            }
        }
        return result
    }

    private func extractMonotonicDecreasing(_ rows: [RigCSVRow]) -> [RigCSVRow] {
        // Find max depth index (start of trip out)
        guard let maxIdx = rows.indices.max(by: { rows[$0].bitDepth_m < rows[$1].bitDepth_m }) else { return rows }
        // Take rows from max depth onward where depth is generally decreasing
        var result: [RigCSVRow] = []
        var lastDepth = Double.infinity
        for i in maxIdx..<rows.count {
            if rows[i].bitDepth_m <= lastDepth + 5 { // 5m tolerance
                result.append(rows[i])
                lastDepth = rows[i].bitDepth_m
            }
        }
        return result
    }

    // MARK: - Bin Into Stands

    private func binIntoStands(rows: [RigCSVRow], config: RigImportConfig) -> [RigStandData] {
        guard !rows.isEmpty else { return [] }

        // Group by stand number: floor(depth / standLength)
        var bins: [Int: [Double]] = [:]
        for row in rows {
            let standNum = Int(floor(row.bitDepth_m / config.standLength_m))
            bins[standNum, default: []].append(row.hookLoad_kDaN)
        }

        var stands: [RigStandData] = []
        for (standNum, hlValues) in bins.sorted(by: { $0.key < $1.key }) {
            guard hlValues.count >= 5 else { continue } // Need enough samples for robust stats

            let sorted = hlValues.sorted()

            // IQR-based outlier rejection (removes both high and low spikes)
            let q1 = percentileValue(sorted, p: 0.25)
            let q3 = percentileValue(sorted, p: 0.75)
            let iqr = q3 - q1
            let lowerFence = q1 - 1.5 * iqr
            let upperFence = q3 + 1.5 * iqr
            let cleaned = sorted.filter { $0 >= lowerFence && $0 <= upperFence }

            // Fall back to full set if IQR filtering is too aggressive
            let workingValues = cleaned.count >= 5 ? cleaned : sorted

            let median = percentileValue(workingValues, p: 0.50)
            let p10 = percentileValue(workingValues, p: 0.10)
            let p90 = percentileValue(workingValues, p: 0.90)
            let midMD = (Double(standNum) + 0.5) * config.standLength_m

            stands.append(RigStandData(
                standMidMD_m: midMD,
                avgHL_kDaN: median,       // median instead of mean
                minHL_kDaN: p10,           // P10 instead of raw min
                maxHL_kDaN: p90,           // P90 instead of raw max
                count: workingValues.count
            ))
        }
        return stands
    }

    /// Linear interpolation percentile on a sorted array
    private func percentileValue(_ sorted: [Double], p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        if sorted.count == 1 { return sorted[0] }
        let idx = p * Double(sorted.count - 1)
        let lo = Int(floor(idx))
        let hi = min(lo + 1, sorted.count - 1)
        let frac = idx - Double(lo)
        return sorted[lo] + frac * (sorted[hi] - sorted[lo])
    }

    // MARK: - Extract Static Weights (Trip In)

    private func extractStaticWeights(rows: [RigCSVRow], config: RigImportConfig) -> [RigStaticWeight] {
        // Detect block height crossing connectionHeight on downward travel
        var weights: [RigStaticWeight] = []
        var prevBH: Double?
        for row in rows {
            if let prev = prevBH {
                // Crossing from above to below connectionHeight
                if prev > config.connectionHeight_m && row.blockHeight_m <= config.connectionHeight_m {
                    // Capture hook load at this crossing point (pipe at slips = static weight)
                    if row.hookLoad_kDaN > config.topDriveWeight_kDaN {
                        weights.append(RigStaticWeight(depth_m: row.bitDepth_m, hookLoad_kDaN: row.hookLoad_kDaN))
                    }
                }
            }
            prevBH = row.blockHeight_m
        }
        return weights
    }

    // MARK: - CSV Helpers (reused from EquipmentImportService patterns)

    private func buildHeaderMap(_ headerLine: String) -> [String: Int] {
        let headers = parseCSVLine(headerLine)
        var map: [String: Int] = [:]

        // Keywords to match (checked via contains for fuzzy matching with units like "(meters)")
        let bitDepthKeywords = ["bit depth", "bpos", "bit position"]
        let hookLoadKeywords = ["hook load", "hkld", "hookload"]
        let blockHeightKeywords = ["block height", "bkht", "block position"]

        for (index, header) in headers.enumerated() {
            let h = header.trimmingCharacters(in: .whitespaces).lowercased()
            if map["bitDepth"] == nil && bitDepthKeywords.contains(where: { h.contains($0) }) {
                map["bitDepth"] = index
            }
            if map["hookLoad"] == nil && hookLoadKeywords.contains(where: { h.contains($0) }) {
                map["hookLoad"] = index
            }
            if map["blockHeight"] == nil && blockHeightKeywords.contains(where: { h.contains($0) }) {
                map["blockHeight"] = index
            }
        }

        // Fallback: bare "depth" only if bit depth not yet matched (avoid matching "block depth" etc.)
        if map["bitDepth"] == nil {
            for (index, header) in headers.enumerated() {
                let h = header.trimmingCharacters(in: .whitespaces).lowercased()
                if h.hasPrefix("depth") { map["bitDepth"] = index; break }
            }
        }

        return map
    }

    private func parseCSVLines(_ text: String) -> [String] {
        let simpleLines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        var hasQuotedNewlines = false
        for line in simpleLines {
            if line.filter({ $0 == "\"" }).count % 2 != 0 {
                hasQuotedNewlines = true
                break
            }
        }
        if !hasQuotedNewlines { return simpleLines }

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
        if !currentLine.isEmpty { lines.append(currentLine) }
        return lines
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var currentField = ""
        var inQuotes = false
        var iterator = line.makeIterator()

        while let char = iterator.next() {
            if char == "\"" {
                if inQuotes {
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
}
