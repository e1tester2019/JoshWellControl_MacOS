//
//  AnnulusSection.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//


import Foundation
import SwiftData

@Model
final class AnnulusSection {
    // Identity
    var id: UUID = UUID()
    var name: String = ""

    // Placement (measured depth in m)
    var topDepth_m: Double = 0.0
    var length_m: Double = 0.0
    var inclination_deg: Double = 0         // optional: lets you align with survey/T&D

    // Geometry (concentric circular annulus)
    // Outer boundary is the wellbore/casing ID; inner boundary is the string OD in that section.
    var innerDiameter_m: Double = 0.0       // casing/wellbore ID
    var outerDiameter_m: Double = 0.0       // string OD in this section

    // Wall roughness (m) – typical casing/wellbore equivalent sand roughness
    var wallRoughness_m: Double = 4.6e-5

    // Fluid (per-section; used for ECD/ΔP)
    enum RheologyModel: Int, Codable {
        case newtonian = 0
        case bingham
        case powerLaw
        case herschelBulkley
    }
    var rheologyModelRaw: Int = RheologyModel.bingham.rawValue

    // Common fluid properties
    var density_kg_per_m3: Double = 1100

    // Newtonian: dynamicVisc_Pa_s
    var dynamicViscosity_Pa_s: Double = 0.01

    // Bingham: PV (Pa·s), YP (Pa)
    var pv_Pa_s: Double = 0.02
    var yp_Pa: Double = 5.0

    // Power-law: n (–), k (Pa·s^n)
    var n_powerLaw: Double = 0.6
    var k_powerLaw_Pa_s_n: Double = 0.5

    // Herschel–Bulkley: τ0 (Pa), n (–), k (Pa·s^n)
    var hb_tau0_Pa: Double = 3.0
    var hb_n: Double = 0.6
    var hb_k_Pa_s_n: Double = 0.5

    // Optional cuttings concentration (vol fraction 0–1)
    var cuttingsVolFrac: Double = 0.0

    // Relationship
    @Relationship(deleteRule: .nullify)
    var project: ProjectState?

    // MARK: - Transient derived values (not stored)

    @Transient var bottomDepth_m: Double { topDepth_m + length_m }

    /// Cross-sectional flow area for concentric circular annulus: A = π/4 (ID² − OD²)
    @Transient var flowArea_m2: Double {
        let ID = innerDiameter_m
        let OD = outerDiameter_m
        guard ID > OD else { return 0 }
        return .pi * 0.25 * (ID*ID - OD*OD)
    }

    /// Wetted perimeter P = π (ID + OD)
    @Transient var wettedPerimeter_m: Double {
        .pi * (innerDiameter_m + outerDiameter_m)
    }

    /// Hydraulic radius Rh = A / P
    @Transient var hydraulicRadius_m: Double {
        let P = wettedPerimeter_m
        return P > 0 ? (flowArea_m2 / P) : 0
    }

    /// Common “equivalent diameter” De = ID − OD (used in many annular correlations)
    @Transient var equivalentDiameter_m: Double {
        max(innerDiameter_m - outerDiameter_m, 0)
    }

    /// Section volume (m³) = area × length
    @Transient var volume_m3: Double {
        flowArea_m2 * length_m
    }

    // Convenience
    @Transient var rheologyModel: RheologyModel {
        get { RheologyModel(rawValue: rheologyModelRaw) ?? .bingham }
        set { rheologyModelRaw = newValue.rawValue }
    }

    // MARK: - Init with basic validation
    init(
        name: String,
        topDepth_m: Double,
        length_m: Double,
        innerDiameter_m: Double,
        outerDiameter_m: Double,
        inclination_deg: Double = 0,
        wallRoughness_m: Double = 4.6e-5,
        rheologyModel: RheologyModel = .bingham,
        density_kg_per_m3: Double = 1100,
        dynamicViscosity_Pa_s: Double = 0.01,
        pv_Pa_s: Double = 0.02,
        yp_Pa: Double = 5.0,
        n_powerLaw: Double = 0.6,
        k_powerLaw_Pa_s_n: Double = 0.5,
        hb_tau0_Pa: Double = 3.0,
        hb_n: Double = 0.6,
        hb_k_Pa_s_n: Double = 0.5,
        cuttingsVolFrac: Double = 0.0,
        project: ProjectState? = nil
    ) {
        precondition(innerDiameter_m > outerDiameter_m, "Annulus ID must be greater than string OD.")
        precondition(length_m >= 0, "Annulus length must be non-negative.")
        precondition(cuttingsVolFrac >= 0 && cuttingsVolFrac <= 1, "Cuttings vol frac must be 0–1.")

        self.name = name
        self.topDepth_m = topDepth_m
        self.length_m = length_m
        self.inclination_deg = inclination_deg
        self.innerDiameter_m = innerDiameter_m
        self.outerDiameter_m = outerDiameter_m
        self.wallRoughness_m = wallRoughness_m
        self.rheologyModelRaw = rheologyModel.rawValue
        self.density_kg_per_m3 = density_kg_per_m3
        self.dynamicViscosity_Pa_s = dynamicViscosity_Pa_s
        self.pv_Pa_s = pv_Pa_s
        self.yp_Pa = yp_Pa
        self.n_powerLaw = n_powerLaw
        self.k_powerLaw_Pa_s_n = k_powerLaw_Pa_s_n
        self.hb_tau0_Pa = hb_tau0_Pa
        self.hb_n = hb_n
        self.hb_k_Pa_s_n = hb_k_Pa_s_n
        self.cuttingsVolFrac = cuttingsVolFrac
        self.project = project
    }
}

extension AnnulusSection: AnnulusSectionLike {
    var topTVD_m: Double { topDepth_m }            // if vertical; else map MD→TVD
    var bottomTVD_m: Double { bottomDepth_m }      // provide TVD via your surveys
    var roughness_m: Double { wallRoughness_m }
}

extension AnnulusSection {
    /// Computes the effective annular volume for this section,
    /// subtracting any overlapping drill string ODs.
    func effectiveAnnularVolume(with drillStrings: [DrillStringSection]) -> Double {
        // Collect boundaries from this section and all overlapping drill strings
        var boundaries: [Double] = [topDepth_m, bottomDepth_m]
        for d in drillStrings where d.bottomDepth_m > topDepth_m && d.topDepth_m < bottomDepth_m {
            boundaries.append(max(d.topDepth_m, topDepth_m))
            boundaries.append(min(d.bottomDepth_m, bottomDepth_m))
        }
        let unique = Array(Set(boundaries)).sorted()
        guard unique.count > 1 else { return 0 }

        var totalVolume = 0.0
        for i in 0..<(unique.count - 1) {
            let t = unique[i]
            let b = unique[i + 1]
            guard b > t else { continue }
            let id = innerDiameter_m
            // Find OD of drill string covering this slice, if any
            let od = drillStrings.first(where: { $0.topDepth_m <= t && $0.bottomDepth_m >= b })?.outerDiameter_m ?? 0
            let area = max(0, .pi * (id * id - od * od) / 4.0)
            totalVolume += area * (b - t)
        }
        return totalVolume
    }
}
