//
//  PaginatedList.swift
//  Josh Well Control for Mac
//
//  A reusable paginated list component for dashboard sections.
//

import SwiftUI

struct PaginatedList<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let pageSize: Int
    let content: (Item) -> Content

    @State private var currentPage: Int = 0

    init(
        items: [Item],
        pageSize: Int = 5,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.items = items
        self.pageSize = pageSize
        self.content = content
    }

    private var totalPages: Int {
        max(1, Int(ceil(Double(items.count) / Double(pageSize))))
    }

    private var currentPageItems: [Item] {
        let start = currentPage * pageSize
        let end = min(start + pageSize, items.count)
        guard start < items.count else { return [] }
        return Array(items[start..<end])
    }

    private var showingRange: String {
        guard !items.isEmpty else { return "" }
        let start = currentPage * pageSize + 1
        let end = min((currentPage + 1) * pageSize, items.count)
        return "\(start)-\(end) of \(items.count)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(currentPageItems) { item in
                content(item)
            }

            // Pagination controls - only show if more than one page
            if totalPages > 1 {
                HStack {
                    Text(showingRange)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    HStack(spacing: 4) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentPage = max(0, currentPage - 1)
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.caption)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.bordered)
                        .disabled(currentPage == 0)

                        Text("\(currentPage + 1)/\(totalPages)")
                            .font(.caption)
                            .monospacedDigit()
                            .frame(minWidth: 40)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentPage = min(totalPages - 1, currentPage + 1)
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.bordered)
                        .disabled(currentPage >= totalPages - 1)
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

#Preview {
    struct PreviewItem: Identifiable {
        let id = UUID()
        let name: String
    }

    let items = (1...12).map { PreviewItem(name: "Item \($0)") }

    return VStack {
        PaginatedList(items: items, pageSize: 5) { item in
            Text(item.name)
                .padding(.vertical, 4)
        }
    }
    .padding()
    .frame(width: 300)
}
