//
//  FinalFluidLayer.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-06.
//


import SwiftUI
import SwiftData

@Model
final class FinalFluidLayer {
    // Relationships
    @Relationship(inverse: \ProjectState.finalLayers)
    var project: ProjectState?

    // Metadata
    var name: String
    var createdAt: Date
    var placement: Placement  // .annulus, .string, .both (you already have this enum)

    // Interval (MD, meters)
    var topMD_m: Double
    var bottomMD_m: Double

    // Fluid
    var density_kgm3: Double

    // UI color, persisted as RGBA
    var colorR: Double
    var colorG: Double
    var colorB: Double
    var colorA: Double

    init(project: ProjectState?,
         name: String,
         placement: Placement,
         topMD_m: Double,
         bottomMD_m: Double,
         density_kgm3: Double,
         color: Color,
         createdAt: Date = .now)
    {
        self.project = project
        self.name = name
        self.placement = placement
        self.topMD_m = topMD_m
        self.bottomMD_m = bottomMD_m
        self.density_kgm3 = density_kgm3
        (self.colorR, self.colorG, self.colorB, self.colorA) = color.rgba
        self.createdAt = createdAt
    }

    var color: Color { Color(red: colorR, green: colorG, blue: colorB, opacity: colorA) }
}

// Small helper to unpack Color → RGBA
fileprivate extension Color {
    var rgba: (Double, Double, Double, Double) {
        #if canImport(AppKit)
        let ns = NSColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
        #else
        return (0.5, 0.5, 0.5, 1.0)
        #endif
    }
}