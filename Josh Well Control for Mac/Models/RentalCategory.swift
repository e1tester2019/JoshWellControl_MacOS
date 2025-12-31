//
//  RentalCategory.swift
//  Josh Well Control for Mac
//
//  User-defined categories for organizing rental equipment.
//

import Foundation
import SwiftData

@Model
final class RentalCategory {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = "shippingbox"  // SF Symbol name
    var sortOrder: Int = 0
    var isActive: Bool = true
    var createdAt: Date = Date.now

    // Relationships
    @Relationship(deleteRule: .nullify, inverse: \RentalEquipment.category)
    var equipment: [RentalEquipment]?

    init(name: String = "", icon: String = "shippingbox", sortOrder: Int = 0) {
        self.name = name
        self.icon = icon
        self.sortOrder = sortOrder
    }

    /// Number of equipment items in this category
    var equipmentCount: Int {
        equipment?.count ?? 0
    }

    /// Default categories to seed on first launch
    static var defaultCategories: [(name: String, icon: String)] {
        [
            ("MWD/LWD", "antenna.radiowaves.left.and.right"),
            ("Motors", "gear.circle"),
            ("Jars", "arrow.up.arrow.down"),
            ("Shock Tools", "waveform.path.ecg"),
            ("Reamers", "circle.dotted"),
            ("Stabilizers", "circle.grid.cross"),
            ("Float Equipment", "arrow.down.circle"),
            ("Crossovers", "link"),
            ("Other", "ellipsis.circle")
        ]
    }
}
