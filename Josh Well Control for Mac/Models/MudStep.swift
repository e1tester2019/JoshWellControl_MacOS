//
//  MudStep.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//

//
//  MudStep.swift
//  Josh Well Control for Mac
//
//  SwiftData model for a mud placement step. Each step defines an interval
//  (Top/Bottom in meters), a fluid density (kg/m³), a display color, and
//  where it should be placed (Annulus/String/Both). Steps are linked to a
//  ProjectState for scoping/persistence.
//

import Foundation
import SwiftData
import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Placement
public enum Placement: String, CaseIterable, Identifiable, Codable {
    case annulus = "Annulus"
    case string  = "String"
    case both    = "Both"
    public var id: String { rawValue }
}

// MARK: - Model
@Model
final class MudStep {
    // Core fields

    public var name: String
    public var top_m: Double
    public var bottom_m: Double
    public var density_kgm3: Double

    // Persisted presentation/state
    public var colorHex: String           // e.g. "#FFAA00"
    public var placementRaw: String       // Placement.rawValue

    // Relationship to project (optional inverse; define on ProjectState if desired)
    @Relationship(deleteRule: .nullify)
    var project: ProjectState?
    
    @Relationship var mud: MudProperties?   // ← optional
    
    // Designated initializer (raw storage)
    init(name: String,
         top_m: Double,
         bottom_m: Double,
         density_kgm3: Double,
         colorHex: String,
         placementRaw: String,
         project: ProjectState?,
         mud: MudProperties? = nil) {
        self.name = name
        self.top_m = top_m
        self.bottom_m = bottom_m
        self.density_kgm3 = density_kgm3
        self.colorHex = colorHex
        self.placementRaw = placementRaw
        self.project = project
        self.mud = mud
    }

    // Convenience initializer (typed Color & Placement)
    convenience init(       name: String,
                            top_m: Double,
                            bottom_m: Double,
                            density_kgm3: Double,
                            color: Color,
                            placement: Placement,
                            project: ProjectState?,
                            mud: MudProperties? = nil) {
        self.init(name: name,
                  top_m: top_m,
                  bottom_m: bottom_m,
                  density_kgm3: density_kgm3,
                  colorHex: color.toHexRGB() ?? "#007AFF",  // default system blue
                  placementRaw: placement.rawValue,
                  project: project,
                  mud: mud)
    }
}

// MARK: - Computed accessors
extension MudStep {
    var placement: Placement {
        get { Placement(rawValue: placementRaw) ?? .annulus }
        set { placementRaw = newValue.rawValue }
    }

    var color: Color {
        get { Color(hex: colorHex) ?? .blue }
        set { colorHex = newValue.toHexRGB() ?? colorHex }
    }
}

// MARK: - Color ↔︎ Hex helpers (macOS)
public extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    func toHexRGB() -> String? {
        #if canImport(AppKit)
        let ns = NSColor(self)
        guard let rgb = ns.usingColorSpace(.sRGB) else { return nil }
        let r = Int((rgb.redComponent   * 255.0).rounded())
        let g = Int((rgb.greenComponent * 255.0).rounded())
        let b = Int((rgb.blueComponent  * 255.0).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
        #else
        return nil
        #endif
    }
}
