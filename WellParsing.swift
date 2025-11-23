//
//  WellParsing.swift
//
//  Created by AutoParser on 2025-11-23.
//
//  This file defines a parser for extracting well information such as Well Name, UWI,
//  AFE Number, and Requisitioner from a multiline string input. It also provides an
//  extension to apply parsed info to an existing Well instance.
//

import Foundation
import SwiftData

struct ParsedWellInfo {
    var name: String?
    var uwi: String?
    var afeNumber: String?
    var requisitioner: String?

    init(name: String? = nil, uwi: String? = nil, afeNumber: String? = nil, requisitioner: String? = nil) {
        self.name = name
        self.uwi = uwi
        self.afeNumber = afeNumber
        self.requisitioner = requisitioner
    }
}

enum WellParsing {
    static func parse(from text: String) -> ParsedWellInfo {
        var parsed = ParsedWellInfo()

        // Split by lines, ignoring blank lines
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        for line in lines {
            let lowercased = line.lowercased()
            guard let colonIndex = line.firstIndex(of: ":") else { continue }

            let key = line[..<colonIndex].trimmingCharacters(in: .whitespaces)
            let valueStart = line.index(after: colonIndex)
            let rawValue = line[valueStart...].trimmingCharacters(in: .whitespaces)

            switch key.lowercased() {
            case "well name":
                parsed.name = rawValue
            case "uwi":
                parsed.uwi = rawValue
            case "afe", "afe number":
                parsed.afeNumber = rawValue
            case "requisitioner":
                parsed.requisitioner = rawValue
            default:
                continue
            }
        }

        return parsed
    }
}

extension Well {
    func apply(parsed: ParsedWellInfo) {
        if let v = parsed.name, !v.isEmpty {
            self.name = v
        }
        if let v = parsed.uwi, !v.isEmpty {
            self.uwi = v
        }
        if let v = parsed.afeNumber, !v.isEmpty {
            self.afeNumber = v
        }
        if let v = parsed.requisitioner, !v.isEmpty {
            self.requisitioner = v
        }
    }
}

