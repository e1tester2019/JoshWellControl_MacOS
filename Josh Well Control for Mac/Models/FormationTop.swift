//
//  FormationTop.swift
//  Josh Well Control for Mac
//
//  Geological formation top with dip angle for directional dashboard overlay.
//

import Foundation
import SwiftData

@Model
final class FormationTop {
    var id: UUID = UUID()
    var name: String = ""
    var tvdTop_m: Double = 0       // TVD at VS=0 (wellhead reference)
    var dipAngle_deg: Double = 90   // Dip angle from vertical (90 = horizontal, 0 = vertical)
    var colorHex: String?          // Optional color for the line (nil = auto-assigned)
    var sortOrder: Int = 0

    @Relationship var well: Well?

    init(name: String = "", tvdTop_m: Double = 0, dipAngle_deg: Double = 90, colorHex: String? = nil, sortOrder: Int = 0) {
        self.name = name
        self.tvdTop_m = tvdTop_m
        self.dipAngle_deg = dipAngle_deg
        self.colorHex = colorHex
        self.sortOrder = sortOrder
    }
}
