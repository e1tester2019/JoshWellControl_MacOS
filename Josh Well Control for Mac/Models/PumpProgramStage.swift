import Foundation
import SwiftData
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@Model
final class PumpProgramStage {
    @Attribute(.unique) var id: UUID = UUID()

    var name: String = ""
    var volume_m3: Double = 0.0
    var pumpRate_m3permin: Double?

    // Stable ordering (creation order)
    var orderIndex: Int = 0

    // Persist color as RGBA scalars for portability
    var colorR: Double = 0.5
    var colorG: Double = 0.5
    var colorB: Double = 0.5
    var colorA: Double = 1.0

    // Optional link to a mud in this project
    @Relationship var mud: MudProperties?

    // Back-reference to owning project
    @Relationship(inverse: \ProjectState.programStages) var project: ProjectState?

    init(name: String,
         volume_m3: Double,
         pumpRate_m3permin: Double? = nil,
         color: Color,
         project: ProjectState? = nil,
         mud: MudProperties? = nil) {
        self.name = name
        self.volume_m3 = volume_m3
        self.pumpRate_m3permin = pumpRate_m3permin
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(UIKit)
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        #elseif canImport(AppKit)
        let ns = NSColor(color)
        let inSRGB = ns.usingColorSpace(.sRGB) ?? ns.usingColorSpace(.deviceRGB)
        inSRGB?.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        self.colorR = Double(r)
        self.colorG = Double(g)
        self.colorB = Double(b)
        self.colorA = Double(a)
        self.project = project
        self.mud = mud

        if let project {
            let next = (project.programStages.map { $0.orderIndex }.max() ?? -1) + 1
            self.orderIndex = next
        } else {
            self.orderIndex = 0
        }
    }
}

extension PumpProgramStage {
    var color: Color {
        get { Color(red: colorR, green: colorG, blue: colorB, opacity: colorA) }
        set {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            #if canImport(UIKit)
            UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
            #elseif canImport(AppKit)
            let ns = NSColor(newValue)
            let inSRGB = ns.usingColorSpace(.sRGB) ?? ns.usingColorSpace(.deviceRGB)
            inSRGB?.getRed(&r, green: &g, blue: &b, alpha: &a)
            #endif
            colorR = Double(r)
            colorG = Double(g)
            colorB = Double(b)
            colorA = Double(a)
        }
    }
}
