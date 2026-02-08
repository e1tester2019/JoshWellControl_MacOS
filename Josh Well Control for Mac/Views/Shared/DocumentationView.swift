//
//  DocumentationView.swift
//  Josh Well Control for Mac
//
//  In-app documentation viewer for User Guide and Technical Papers.
//

import SwiftUI

// MARK: - Documentation Types

enum DocumentationType: String, CaseIterable, Identifiable {
    case userGuide = "User Guide"
    case spePaper = "SPE Technical Paper"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .userGuide: return "book.fill"
        case .spePaper: return "doc.text.fill"
        }
    }

    var filename: String {
        switch self {
        case .userGuide: return "UserGuide"
        case .spePaper: return "NumericalTripModel_SPE_Technical_Paper"
        }
    }

    var subtitle: String {
        switch self {
        case .userGuide: return "How to use Josh Well Control"
        case .spePaper: return "Numerical Trip Model Documentation"
        }
    }
}

// MARK: - Main Documentation View

struct DocumentationView: View {
    @State private var selectedDoc: DocumentationType = .userGuide
    @State private var searchText = ""
    @State private var markdownContent: String = ""

    var body: some View {
        HSplitView {
            // Sidebar
            VStack(alignment: .leading, spacing: 0) {
                Text("Documentation")
                    .font(.headline)
                    .padding()

                Divider()

                List(DocumentationType.allCases, selection: $selectedDoc) { doc in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(doc.rawValue)
                                .font(.body)
                            Text(doc.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: doc.icon)
                            .foregroundStyle(.blue)
                    }
                    .tag(doc)
                    .padding(.vertical, 4)
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)

            // Content
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search documentation...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(.bar)

                Divider()

                // Markdown content
                ScrollView {
                    MarkdownContentView(
                        markdown: filteredContent,
                        searchText: searchText
                    )
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            loadMarkdown(for: selectedDoc)
        }
        .onChange(of: selectedDoc) { _, newDoc in
            loadMarkdown(for: newDoc)
        }
    }

    private var filteredContent: String {
        guard !searchText.isEmpty else { return markdownContent }

        // Simple filtering - show sections containing search text
        let lines = markdownContent.components(separatedBy: "\n")
        var result: [String] = []
        var currentSection: [String] = []
        var sectionMatches = false

        for line in lines {
            if line.hasPrefix("## ") || line.hasPrefix("# ") {
                // New section - save previous if it matched
                if sectionMatches && !currentSection.isEmpty {
                    result.append(contentsOf: currentSection)
                    result.append("")
                }
                currentSection = [line]
                sectionMatches = line.localizedCaseInsensitiveContains(searchText)
            } else {
                currentSection.append(line)
                if line.localizedCaseInsensitiveContains(searchText) {
                    sectionMatches = true
                }
            }
        }

        // Don't forget the last section
        if sectionMatches && !currentSection.isEmpty {
            result.append(contentsOf: currentSection)
        }

        return result.isEmpty ? "No results found for \"\(searchText)\"" : result.joined(separator: "\n")
    }

    private func loadMarkdown(for doc: DocumentationType) {
        // Try to load from Documentation folder in the project
        // First check if we can find it via Bundle
        if let url = Bundle.main.url(forResource: doc.filename, withExtension: "md"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            markdownContent = content
            return
        }

        // Fallback: embedded content
        markdownContent = getEmbeddedContent(for: doc)
    }

    private func getEmbeddedContent(for doc: DocumentationType) -> String {
        switch doc {
        case .userGuide:
            return Self.userGuideContent
        case .spePaper:
            return Self.speContent
        }
    }
}

// MARK: - Markdown Rendering View

struct MarkdownContentView: View {
    let markdown: String
    let searchText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(parseMarkdown().enumerated()), id: \.offset) { _, element in
                renderElement(element)
            }
        }
    }

    private func parseMarkdown() -> [MarkdownElement] {
        var elements: [MarkdownElement] = []
        let lines = markdown.components(separatedBy: "\n")
        var currentParagraph: [String] = []
        var inCodeBlock = false
        var codeBlockContent: [String] = []
        var inTable = false
        var tableRows: [[String]] = []

        for line in lines {
            // Code blocks
            if line.hasPrefix("```") {
                if inCodeBlock {
                    elements.append(.codeBlock(codeBlockContent.joined(separator: "\n")))
                    codeBlockContent = []
                    inCodeBlock = false
                } else {
                    flushParagraph(&currentParagraph, &elements)
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                codeBlockContent.append(line)
                continue
            }

            // Tables
            if line.contains("|") && !line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !inTable {
                    flushParagraph(&currentParagraph, &elements)
                    inTable = true
                }
                // Skip separator lines
                if !line.contains("---") {
                    let cells = line.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }
                    if !cells.isEmpty {
                        tableRows.append(cells)
                    }
                }
                continue
            } else if inTable {
                elements.append(.table(tableRows))
                tableRows = []
                inTable = false
            }

            // Headers
            if line.hasPrefix("# ") {
                flushParagraph(&currentParagraph, &elements)
                elements.append(.h1(String(line.dropFirst(2))))
            } else if line.hasPrefix("## ") {
                flushParagraph(&currentParagraph, &elements)
                elements.append(.h2(String(line.dropFirst(3))))
            } else if line.hasPrefix("### ") {
                flushParagraph(&currentParagraph, &elements)
                elements.append(.h3(String(line.dropFirst(4))))
            } else if line.hasPrefix("#### ") {
                flushParagraph(&currentParagraph, &elements)
                elements.append(.h4(String(line.dropFirst(5))))
            }
            // Horizontal rule
            else if line.hasPrefix("---") {
                flushParagraph(&currentParagraph, &elements)
                elements.append(.divider)
            }
            // List items
            else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph(&currentParagraph, &elements)
                elements.append(.listItem(String(line.dropFirst(2)), level: 0))
            }
            else if line.hasPrefix("  - ") || line.hasPrefix("  * ") {
                flushParagraph(&currentParagraph, &elements)
                elements.append(.listItem(String(line.dropFirst(4)), level: 1))
            }
            // Numbered list (e.g., "1. Item")
            else if let range = line.range(of: #"^(\d+)\.\s+"#, options: .regularExpression) {
                flushParagraph(&currentParagraph, &elements)
                let numPart = line[range].trimmingCharacters(in: CharacterSet(charactersIn: ". "))
                let textPart = String(line[range.upperBound...])
                elements.append(.numberedItem(numPart, textPart))
            }
            // Empty line
            else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushParagraph(&currentParagraph, &elements)
            }
            // Regular text
            else {
                currentParagraph.append(line)
            }
        }

        flushParagraph(&currentParagraph, &elements)
        if inTable && !tableRows.isEmpty {
            elements.append(.table(tableRows))
        }

        return elements
    }

    private func flushParagraph(_ paragraph: inout [String], _ elements: inout [MarkdownElement]) {
        if !paragraph.isEmpty {
            elements.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph = []
        }
    }

    @ViewBuilder
    private func renderElement(_ element: MarkdownElement) -> some View {
        switch element {
        case .h1(let text):
            Text(text)
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top, 8)
        case .h2(let text):
            Text(text)
                .font(.title)
                .fontWeight(.semibold)
                .padding(.top, 12)
        case .h3(let text):
            Text(text)
                .font(.title2)
                .fontWeight(.medium)
                .padding(.top, 8)
        case .h4(let text):
            Text(text)
                .font(.title3)
                .fontWeight(.medium)
                .padding(.top, 4)
        case .paragraph(let text):
            renderRichText(text)
                .fixedSize(horizontal: false, vertical: true)
        case .listItem(let text, let level):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .foregroundStyle(.secondary)
                renderRichText(text)
            }
            .padding(.leading, CGFloat(level) * 20)
        case .numberedItem(let num, let text):
            HStack(alignment: .top, spacing: 8) {
                Text("\(num).")
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .trailing)
                renderRichText(text)
            }
        case .codeBlock(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        case .divider:
            Divider()
                .padding(.vertical, 8)
        case .table(let rows):
            renderTable(rows)
        }
    }

    private func renderRichText(_ text: String) -> Text {
        var result = Text("")
        var remaining = text

        // Process bold, italic, code, and keyboard shortcuts
        while !remaining.isEmpty {
            // Bold **text**
            if let boldRange = remaining.range(of: "\\*\\*(.+?)\\*\\*", options: .regularExpression) {
                let before = String(remaining[..<boldRange.lowerBound])
                let match = String(remaining[boldRange])
                let inner = String(match.dropFirst(2).dropLast(2))

                result = result + Text(before) + Text(inner).bold()
                remaining = String(remaining[boldRange.upperBound...])
            }
            // Code `text`
            else if let codeRange = remaining.range(of: "`(.+?)`", options: .regularExpression) {
                let before = String(remaining[..<codeRange.lowerBound])
                let match = String(remaining[codeRange])
                let inner = String(match.dropFirst(1).dropLast(1))

                result = result + Text(before) + Text(inner)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.blue)
                remaining = String(remaining[codeRange.upperBound...])
            }
            else {
                result = result + Text(remaining)
                break
            }
        }

        // Highlight search matches
        if !searchText.isEmpty {
            // This is simplified - full implementation would need AttributedString
        }

        return result
    }

    @ViewBuilder
    private func renderTable(_ rows: [[String]]) -> some View {
        if rows.isEmpty { EmptyView() }
        else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                            Text(cell)
                                .font(rowIndex == 0 ? .headline : .body)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(rowIndex == 0 ? Color.accentColor.opacity(0.1) : Color.clear)
                            if colIndex < row.count - 1 {
                                Divider()
                            }
                        }
                    }
                    if rowIndex < rows.count - 1 {
                        Divider()
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
        }
    }
}

// MARK: - Markdown Element Types

private enum MarkdownElement {
    case h1(String)
    case h2(String)
    case h3(String)
    case h4(String)
    case paragraph(String)
    case listItem(String, level: Int)
    case numberedItem(String, String)
    case codeBlock(String)
    case divider
    case table([[String]])
}

// MARK: - Embedded Content (Fallback)

extension DocumentationView {
    static let userGuideContent = """
# Josh Well Control for Mac - User Guide

## Overview

Josh Well Control is a professional oil and gas well control application designed for field engineers and company managers. It combines powerful technical drilling calculations with comprehensive business management tools in a single, unified platform.

The application operates in two primary modes:
- **Field Mode** - Technical drilling operations, simulations, and well management
- **Business Mode** - Financial tracking, invoicing, payroll, and accounting (PIN-protected)

---

## Getting Started

### Navigation

The app uses a two-panel layout:
- **Sidebar** (left) - Navigation menu organized by category
- **Detail View** (right) - Main content area for the selected feature

### Quick Access

- **Command Palette** (`⌘K`) - Fast navigation to any feature, well, or action
- **Keyboard Shortcuts** (`⌘0-9`) - Quick access to frequently used views
- **Well Selector** - Toolbar dropdown to switch between wells
- **Project Selector** - Choose which project within a well to work on

---

## Field Operations

### Well Geometry

#### Drill String
Define your pipe configuration from surface to bit:
1. Navigate to **Drill String** from the sidebar
2. Add sections with start/end depth, ID, and OD
3. Capacity and displacement are calculated automatically

#### Annulus
Define your casing and annular geometry:
1. Navigate to **Annulus** from the sidebar
2. Add annular sections with depth ranges and dimensions
3. Used for volume calculations and hydraulic analysis

#### Surveys
Track wellbore trajectory:
1. Navigate to **Surveys** from the sidebar
2. Enter survey stations (MD, inclination, azimuth)
3. TVD and coordinates are calculated automatically

---

## Simulations

### Trip Simulation (Tripping Pipe Out)
Full wellbore pressure simulation for pulling pipe:

1. Ensure well geometry and mud properties are configured
2. Set pressure window limits
3. Configure trip speed and mud weights
4. Run simulation and view pressure curves
5. Use Trip Optimizer for optimal slug parameters
6. Export PDF or HTML report

### Trip In Simulation (Running Pipe)
Simulate casing or liner running operations with floated/non-floated conditions.

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘K` | Open Command Palette |
| `⌘0-9` | Quick view access |
| `⌘N` | New item (context-aware) |

---

## Tips

1. **Use Command Palette** - Press `⌘K` for the fastest navigation
2. **Favorite Active Wells** - Keep frequently accessed wells at the top
3. **Set Pressure Windows First** - Always define safety limits before running simulations
"""

    static let speContent = """
# Numerical Modeling of Wellbore Hydraulics During Tripping Operations

**Technical Documentation — SPE Paper Style**

---

## Abstract

This paper presents a comprehensive numerical simulation framework for modeling wellbore hydraulics during both trip-out (pulling out of hole, POOH) and trip-in (running in hole, RIH) operations. The framework addresses critical challenges in Managed Pressure Drilling (MPD) where precise bottomhole pressure control is essential for wellbore stability.

---

## 1. Introduction

### 1.1 Problem Statement

Tripping operations represent critical phases in drilling operations where wellbore pressure management is paramount. During these operations, the displacement of pipe creates fluid movement that can induce significant pressure transients at the bottom of the wellbore.

The complexity of tripping simulations is compounded by:
- **Heterogeneous fluid columns**: Multiple fluid types with distinct densities and rheological properties
- **Float valve dynamics**: State changes fundamentally altering hydraulic system behavior
- **Swab and surge effects**: Viscous pressure losses affecting bottomhole pressure
- **Variable geometry**: Non-uniform annular geometries from casing programs

### 1.2 Scope

This numerical framework provides:
- Multi-layer fluid tracking in drillstring and annulus compartments
- Float valve state transitions based on pressure equilibrium
- U-tube equilibration with iterative pressure balancing
- Swab/surge pressure calculations using power-law rheology

---

## 2. Physical System Description

### 2.1 Wellbore Compartments

**String Stack**: Fluid column inside the drillstring from surface to bit depth.

**Annulus Stack**: Fluid column in the annular space between drillstring and wellbore.

**Pocket Region**: During trip-out, fluid accumulates below the current bit position.

### 2.2 Float Valve Behavior

The float valve controls fluid communication between the drillstring interior and the annulus:

**Closed Float State:**
- String fluid rises with the pipe
- Annulus must be backfilled with full pipe OD volume

**Open Float State:**
- String fluid drains through the float into the annulus
- Air fills the string from surface

---

## 3. Governing Equations

### 3.1 Hydrostatic Pressure

P = ρgh

Where:
- P = hydrostatic pressure (Pa)
- ρ = fluid density (kg/m³)
- g = gravitational acceleration (9.81 m/s²)
- h = vertical height (m)

### 3.2 Swab Pressure (Power Law Model)

ΔP_swab = (K × v^n × L) / (D_h)

Where K and n are power-law fluid parameters derived from Fann viscometer readings.

---

For the complete technical documentation, see the full SPE paper in the Documentation folder.
"""
}

// MARK: - Preview

#if DEBUG
#Preview {
    DocumentationView()
        .frame(width: 900, height: 600)
}
#endif
