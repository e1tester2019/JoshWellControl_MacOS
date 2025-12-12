//
//  FinalFluidLayer.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-06.
//


import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

@Model
final class FinalFluidLayer {
    // Relationships
    @Relationship
    var project: ProjectState?
    @Relationship var mud: MudProperties?   // ← optional link back to the mud check

    // Metadata
    var name: String = ""
    var createdAt: Date = Date.now
    var placementRaw: String = Placement.annulus.rawValue  // Store enum as String

    // Interval (MD, meters)
    var topMD_m: Double = 0.0
    var bottomMD_m: Double = 0.0

    // Fluid
    var density_kgm3: Double = 0.0

    // UI color, persisted as RGBA
    var colorR: Double = 0.5
    var colorG: Double = 0.5
    var colorB: Double = 0.5
    var colorA: Double = 1.0

    init(project: ProjectState?,
         name: String,
         placement: Placement,
         topMD_m: Double,
         bottomMD_m: Double,
         density_kgm3: Double,
         color: Color,
         createdAt: Date = .now,
         mud: MudProperties? = nil)         // ← new param
    {
        self.project = project
        self.name = name
        self.placementRaw = placement.rawValue
        self.topMD_m = topMD_m
        self.bottomMD_m = bottomMD_m
        self.density_kgm3 = density_kgm3
        (self.colorR, self.colorG, self.colorB, self.colorA) = color.rgba
        self.createdAt = createdAt
        self.mud = mud                      // ← store it
    }

    var color: Color { Color(red: colorR, green: colorG, blue: colorB, opacity: colorA) }

    // Computed property for Placement enum
    var placement: Placement {
        get { Placement(rawValue: placementRaw) ?? .annulus }
        set { placementRaw = newValue.rawValue }
    }
}

// Small helper to unpack Color → RGBA
fileprivate extension Color {
    var rgba: (Double, Double, Double, Double) {
        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        let ns = NSColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
        #elseif canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
        #else
        return (0.5, 0.5, 0.5, 1.0)
        #endif
    }
}
