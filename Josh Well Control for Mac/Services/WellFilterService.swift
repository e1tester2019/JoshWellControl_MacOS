//
//  WellFilterService.swift
//  Josh Well Control for Mac
//
//  Provides filtering, searching, and sorting for wells
//

import Foundation
import SwiftUI

/// Categories for filtering wells
enum WellFilterCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case favorites = "Favorites"
    case recent = "Recent"
    case archived = "Archived"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .favorites: return "star.fill"
        case .recent: return "clock"
        case .archived: return "archivebox"
        }
    }
}

/// Service for filtering and sorting wells
@Observable
final class WellFilterService {
    // MARK: - Filter State

    var searchText: String = ""
    var selectedCategory: WellFilterCategory = .all
    var showArchived: Bool = false

    // MARK: - Filtering

    /// Filters and sorts wells based on current filter state
    /// - Parameter wells: Array of all wells
    /// - Returns: Filtered and sorted array of wells
    func filteredWells(from wells: [Well]) -> [Well] {
        var result = wells

        // 1. Filter by category
        switch selectedCategory {
        case .all:
            // Show non-archived wells (unless showArchived is true)
            if !showArchived {
                result = result.filter { !$0.isArchived }
            }
        case .favorites:
            result = result.filter { $0.isFavorite && !$0.isArchived }
        case .recent:
            // Wells accessed in the last 7 days
            let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
            result = result.filter {
                !$0.isArchived && ($0.lastAccessedAt ?? .distantPast) > cutoff
            }
        case .archived:
            result = result.filter { $0.isArchived }
        }

        // 2. Filter by search text
        if !searchText.isEmpty {
            let lowercasedSearch = searchText.lowercased()
            result = result.filter { well in
                well.name.lowercased().contains(lowercasedSearch) ||
                (well.uwi?.lowercased().contains(lowercasedSearch) ?? false) ||
                (well.rigName?.lowercased().contains(lowercasedSearch) ?? false) ||
                (well.afeNumber?.lowercased().contains(lowercasedSearch) ?? false) ||
                (well.requisitioner?.lowercased().contains(lowercasedSearch) ?? false)
            }
        }

        // 3. Sort: favorites first, then by lastAccessedAt (recent first), then by name
        result.sort { a, b in
            // Favorites always first
            if a.isFavorite != b.isFavorite {
                return a.isFavorite
            }
            // Then by last accessed (most recent first)
            let aAccess = a.lastAccessedAt ?? .distantPast
            let bAccess = b.lastAccessedAt ?? .distantPast
            if aAccess != bAccess {
                return aAccess > bAccess
            }
            // Finally by name
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        return result
    }

    /// Returns wells grouped by their pad (if any)
    /// - Parameter wells: Pre-filtered wells
    /// - Returns: Dictionary keyed by pad name (or "No Pad" for wells without a pad)
    func groupedByPad(from wells: [Well]) -> [(padName: String, wells: [Well])] {
        let grouped = Dictionary(grouping: wells) { well in
            well.pad?.name ?? "No Pad"
        }

        return grouped
            .map { (padName: $0.key, wells: $0.value) }
            .sorted { $0.padName < $1.padName }
    }

    // MARK: - Quick Actions

    /// Toggles favorite status for a well
    func toggleFavorite(_ well: Well, context: ModelContext) {
        well.isFavorite.toggle()
        well.updatedAt = .now
        try? context.save()
    }

    /// Archives a well
    func archive(_ well: Well, context: ModelContext) {
        well.isArchived = true
        well.updatedAt = .now
        try? context.save()
    }

    /// Unarchives a well
    func unarchive(_ well: Well, context: ModelContext) {
        well.isArchived = false
        well.updatedAt = .now
        try? context.save()
    }

    /// Resets all filters to default state
    func resetFilters() {
        searchText = ""
        selectedCategory = .all
        showArchived = false
    }
}

// MARK: - SwiftData Import
import SwiftData
