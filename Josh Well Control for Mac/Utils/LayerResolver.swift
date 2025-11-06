//
//  LayerResolver.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-06.
//

import Foundation

/// Domain for which side of the bit is evaluated.
///  - swabAboveBit: integrate [surface .. bit]
///  - surgeBelowBit: integrate [bit .. lowerLimit]
enum LayerDomain { case swabAboveBit, surgeBelowBit }

/// Utility that slices the project's persisted FinalFluidLayer set into the
/// interval used by the swab/surge engine and converts them into DTOs.
struct LayerResolver {
    /// Select which placements to include when building the annular fluid column.
    /// Typically `.annulus` and `.both`. Include `.string` only for open-ended string modelling.
    struct Options: OptionSet {
        let rawValue: Int
        static let includeAnnulus = Options(rawValue: 1 << 0)
        static let includeString  = Options(rawValue: 1 << 1)
        static let includeBoth    = Options(rawValue: 1 << 2)

        static let annulusOnly: Options = [.includeAnnulus, .includeBoth]
        static let all: Options = [.includeAnnulus, .includeString, .includeBoth]
    }

    /// Returns deep→shallow ordered DTO layers clipped to the domain range.
    static func slice(
        _ layers: [FinalFluidLayer],
        for project: ProjectState,
        domain: LayerDomain,
        bitMD: Double,
        lowerLimitMD: Double,
        include options: Options = .annulusOnly,
        mergeAdjacentSameDensity: Bool = true
    ) -> [SwabCalculator.LayerDTO] {
        // Determine range [lo, hi] for the domain
        let (lo, hi): (Double, Double) = {
            switch domain {
            case .swabAboveBit:  return (0.0, max(bitMD, 0.0))
            case .surgeBelowBit: return (min(bitMD, lowerLimitMD), max(bitMD, lowerLimitMD))
            }
        }()

        // Filter layers by project and placement
        let relevant = layers.filter { L in
            guard L.project === project else { return false }
            switch L.placement {
            case .annulus: return options.contains(.includeAnnulus)
            case .string:  return options.contains(.includeString)
            case .both:    return options.contains(.includeBoth)
            }
        }

        // Clip each layer to [lo, hi]
        var out: [SwabCalculator.LayerDTO] = []
        out.reserveCapacity(relevant.count)
        for L in relevant {
            let t = min(L.topMD_m, L.bottomMD_m)
            let b = max(L.topMD_m, L.bottomMD_m)
            let segTop = max(lo, t)
            let segBot = min(hi, b)
            if segBot > segTop + 1e-9 {
                out.append(.init(rho_kgpm3: L.density_kgm3, topMD_m: segTop, bottomMD_m: segBot))
            }
        }

        // Sort deep→shallow for the engine
        out.sort { max($0.topMD_m, $0.bottomMD_m) > max($1.topMD_m, $1.bottomMD_m) }

        // Optionally merge adjacent segments with identical density to reduce work
        if mergeAdjacentSameDensity, !out.isEmpty {
            var merged: [SwabCalculator.LayerDTO] = []
            merged.reserveCapacity(out.count)
            var cur = out[0]
            for i in 1..<out.count {
                let nxt = out[i]
                let curTop = min(cur.topMD_m, cur.bottomMD_m)
                let curBot = max(cur.topMD_m, cur.bottomMD_m)
                let nxtTop = min(nxt.topMD_m, nxt.bottomMD_m)
                let nxtBot = max(nxt.topMD_m, nxt.bottomMD_m)
                if abs(cur.rho_kgpm3 - nxt.rho_kgpm3) < 1e-9 && abs(nxtTop - curBot) < 1e-9 {
                    // extend current
                    cur = .init(rho_kgpm3: cur.rho_kgpm3, topMD_m: curTop, bottomMD_m: nxtBot)
                } else {
                    merged.append(cur)
                    cur = nxt
                }
            }
            merged.append(cur)
            out = merged
        }

        return out
    }
}
