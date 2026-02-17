//
//  MarkdownListView.swift
//  Josh Well Control for Mac
//
//  Renders plain text with markdown-style lists (- bullets, 1. numbered)
//

import SwiftUI

struct MarkdownListView: View {
    let content: String

    private struct ParsedBlock: Identifiable {
        let id = UUID()
        let kind: Kind

        enum Kind {
            case text(String)
            case bullet([String])
            case numbered([String])
        }
    }

    private var blocks: [ParsedBlock] {
        var result: [ParsedBlock] = []
        var currentBullets: [String] = []
        var currentNumbered: [String] = []

        func flushBullets() {
            if !currentBullets.isEmpty {
                result.append(ParsedBlock(kind: .bullet(currentBullets)))
                currentBullets = []
            }
        }

        func flushNumbered() {
            if !currentNumbered.isEmpty {
                result.append(ParsedBlock(kind: .numbered(currentNumbered)))
                currentNumbered = []
            }
        }

        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("- ") {
                flushNumbered()
                currentBullets.append(String(line.dropFirst(2)))
            } else if line.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                flushBullets()
                let text = line.replacingOccurrences(of: #"^\d+\.\s"#, with: "", options: .regularExpression)
                currentNumbered.append(text)
            } else {
                flushBullets()
                flushNumbered()
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    result.append(ParsedBlock(kind: .text(line)))
                }
            }
        }

        flushBullets()
        flushNumbered()

        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(blocks) { block in
                switch block.kind {
                case .text(let text):
                    Text(text)
                case .bullet(let items):
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 6) {
                            Text("\u{2022}")
                            Text(item)
                        }
                        .padding(.leading, 8)
                    }
                case .numbered(let items):
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .top, spacing: 6) {
                            Text("\(index + 1).")
                                .frame(width: 20, alignment: .trailing)
                            Text(item)
                        }
                        .padding(.leading, 8)
                    }
                }
            }
        }
    }
}
