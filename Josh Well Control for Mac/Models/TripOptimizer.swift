//
//  TripOptimizer.swift
//  Josh Well Control for Mac
//
//  Calculates optimal kill mud density for tripping out of hole.
//
//  Model:
//  - User picks surface slug density and 2nd slug density
//  - 2nd slug volume = string capacity from surface slug bottom to heel
//  - Slug drop = volume displaced by heavy slugs (U-tube effect)
//  - Kill mud volume = pipe displacement + slug drop
//  - Annulus layers (from surface): kill mud, surface slug, 2nd slug, original mud
//  - Solve for kill mud density to achieve target ESD at control point
//

import Foundation
import SwiftData

struct TripOptimizerInput {
    // Target parameters
    let targetESD_kgm3: Double           // Target ESD at control point

    // Surface slug parameters (user picks)
    let surfaceSlugVolume_m3: Double     // Volume of surface slug (e.g., 2 m³)
    let surfaceSlugDensity_kgm3: Double  // Density of surface slug (e.g., 2100 kg/m³)

    // 2nd slug parameters
    // If nil, we calculate: 2 × targetESD - baseMud + (crackFloat / heelTVD / 0.00981)
    let secondSlugDensity_kgm3: Double?

    // Well state
    let baseMudDensity_kgm3: Double      // Active/base mud density
    let crackFloat_kPa: Double           // Float crack pressure
    let startBitMD_m: Double             // Starting bit depth (TD)
    let controlMD_m: Double              // Control/shoe depth

    // Optional manual heel depth (nil = auto-detect from surveys)
    let manualHeelMD_m: Double?

    // Optional observed slug drop from simulation (nil = use approximation)
    let observedSlugDrop_m3: Double?
}

struct TripOptimizerResult {
    // Calculated densities
    let killMudDensity_kgm3: Double      // Density of kill mud (annulus top layer)

    // Volumes
    let surfaceSlugVolume_m3: Double     // User input
    let activeMudVolume_m3: Double       // Between surface slug and 2nd slug
    let secondSlugVolume_m3: Double      // Calculated (string capacity to heel)
    let slugDropVolume_m3: Double        // Volume dropped due to heavy slugs (used)
    let slugDropCalculated_m3: Double    // Calculated slug drop (for display)
    let killMudVolume_m3: Double         // Pipe displacement + slug drop
    let totalSteelDisplacement_m3: Double

    // Slug drop calculation details
    let effectiveESD_kgm3: Double        // Target ESD + crack float equivalent
    let surfaceSlugMDLength_m: Double    // MD length of surface slug in string
    let surfaceSlugTVDHeight_m: Double   // TVD height of surface slug in string
    let secondSlugMDLength_m: Double     // MD length of 2nd slug in string
    let secondSlugTVDHeight_m: Double    // TVD height of 2nd slug in string
    let surfaceSlugDropHeight_m: Double  // Drop contribution from surface slug
    let secondSlugDropHeight_m: Double   // Drop contribution from 2nd slug

    // Layer heights in annulus (from surface down)
    let killMudHeight_m: Double
    let surfaceSlugHeight_m: Double
    let activeMudHeight_m: Double        // Active mud between surface slug and 2nd slug
    let secondSlugHeight_m: Double
    let originalMudHeight_m: Double      // Height from bottom of 2nd slug to control TVD

    // Annulus capacity used for height calculations
    let annulusCapacity_m3_per_m: Double

    // Depths used
    let heelMD_m: Double
    let heelTVD_m: Double
    let sixtyDegTVD_m: Double            // TVD at 60° - bottom of 2nd slug
    let controlTVD_m: Double
    let surfaceSlugBottomMD_m: Double

    // Input echo (for display)
    let surfaceSlugDensity_kgm3: Double
    let secondSlugDensity_kgm3: Double       // The density used (calculated or manual)
    let secondSlugDensityCalculated_kgm3: Double  // Always show calculated value
    let secondSlugDensityWasCalculated: Bool // True if we used the calculated value
    let baseMudDensity_kgm3: Double

    // Diagnostics
    let warnings: [String]
    let isValid: Bool
}

class TripOptimizer {

    /// Find heel depth - first point where inclination >= 90°
    static func findHeelDepth(
        surveys: [SurveyStation],
        planStations: [DirectionalPlanStation],
        preferPlan: Bool
    ) -> (md: Double, tvd: Double)? {

        if preferPlan && !planStations.isEmpty {
            let sorted = planStations.sorted { $0.md < $1.md }
            if let heel = sorted.first(where: { $0.inc >= 90.0 }) {
                return (heel.md, heel.tvd)
            }
            if let maxInc = sorted.max(by: { $0.inc < $1.inc }), maxInc.inc > 45 {
                return (maxInc.md, maxInc.tvd)
            }
        } else if !surveys.isEmpty {
            let sorted = surveys.sorted { $0.md < $1.md }
            if let heel = sorted.first(where: { $0.inc >= 90.0 }) {
                return (heel.md, heel.tvd ?? heel.md)
            }
            if let maxInc = sorted.max(by: { $0.inc < $1.inc }), maxInc.inc > 45 {
                return (maxInc.md, maxInc.tvd ?? maxInc.md)
            }
        }

        return nil
    }

    /// Find depth at target inclination (e.g., 60°)
    static func findInclinationDepth(
        targetInc: Double,
        surveys: [SurveyStation],
        planStations: [DirectionalPlanStation],
        preferPlan: Bool
    ) -> (md: Double, tvd: Double)? {

        if preferPlan && !planStations.isEmpty {
            let sorted = planStations.sorted { $0.md < $1.md }
            if let point = sorted.first(where: { $0.inc >= targetInc }) {
                return (point.md, point.tvd)
            }
        } else if !surveys.isEmpty {
            let sorted = surveys.sorted { $0.md < $1.md }
            if let point = sorted.first(where: { $0.inc >= targetInc }) {
                return (point.md, point.tvd ?? point.md)
            }
        }

        return nil
    }

    /// Calculate optimal kill mud density
    @MainActor
    static func calculate(
        input: TripOptimizerInput,
        project: ProjectState,
        tvdSampler: TvdSampler
    ) -> TripOptimizerResult {

        var warnings: [String] = []

        // 1. Determine heel depth (90°) and 60° depth
        let heelMD: Double
        let heelTVD: Double

        if let manual = input.manualHeelMD_m {
            heelMD = manual
            heelTVD = tvdSampler.tvd(of: manual)
        } else if let detected = findHeelDepth(
            surveys: project.surveys ?? [],
            planStations: project.well?.directionalPlans?.first?.stations ?? [],
            preferPlan: tvdSampler.isUsingPlan
        ) {
            heelMD = detected.md
            heelTVD = detected.tvd
        } else {
            heelMD = input.startBitMD_m * 0.7
            heelTVD = tvdSampler.tvd(of: heelMD)
            warnings.append("No heel (90°) found. Using 70% of TD as estimate.")
        }

        // 2nd slug bottom is at the heel (90°)
        // The slug extends upward from the heel

        // 2. Calculate 2nd slug density if not provided
        // Formula: 2 × targetESD - activeMud + (crackFloat / heelTVD / 0.00981)
        let secondSlugDensityCalculated = 2.0 * input.targetESD_kgm3 - input.baseMudDensity_kgm3
            + (input.crackFloat_kPa / heelTVD / 0.00981)

        let secondSlugDensity: Double
        let secondSlugDensityWasCalculated: Bool
        if let manual = input.secondSlugDensity_kgm3 {
            secondSlugDensity = manual
            secondSlugDensityWasCalculated = false
        } else {
            secondSlugDensity = secondSlugDensityCalculated
            secondSlugDensityWasCalculated = true
        }

        // 3. Get key depths
        let controlTVD = tvdSampler.tvd(of: input.controlMD_m)
        let drillString = project.drillString ?? []

        // 3. Calculate slug volumes in drill string
        // Surface slug: from 0 to surfaceSlugBottomMD
        let surfaceSlugBottomMD = calculateDepthForVolume(
            volume: input.surfaceSlugVolume_m3,
            fromMD: 0,
            drillString: drillString
        )

        // 2nd slug: from surface slug bottom to heel (volume in string)
        let secondSlugVolume = calculateStringVolume(
            fromMD: surfaceSlugBottomMD,
            toMD: heelMD,
            drillString: drillString
        )

        // 4. Calculate slug drop
        // Get capacities
        let annulusCapacity = getAnnulusCapacityAtSurface(project: project)  // m² for annulus layers
        let stringCapacity = getStringCapacityAtSurface(project: project)    // m² for slug drop

        // Effective ESD = target ESD + crack float equivalent density
        // Crack float resists draining, so add it to the target
        let crackFloatEquivalentDensity = input.crackFloat_kPa / heelTVD / 0.00981
        let effectiveESD = input.targetESD_kgm3 + crackFloatEquivalentDensity

        // Get MD lengths and TVD heights of each slug in the drill string
        let surfaceSlugMDLength = surfaceSlugBottomMD  // from 0 to surfaceSlugBottomMD
        let secondSlugMDLength = heelMD - surfaceSlugBottomMD

        let surfaceSlugBottomTVD_string = tvdSampler.tvd(of: surfaceSlugBottomMD)
        let surfaceSlugTVDHeight = surfaceSlugBottomTVD_string  // from surface (TVD=0)
        let secondSlugTVDHeight = heelTVD - surfaceSlugBottomTVD_string

        // For each slug: drop_height = (Δρ × TVD_height) / effectiveESD
        // Δρ = slug_density - effectiveESD
        let surfaceSlugDeltaRho = input.surfaceSlugDensity_kgm3 - effectiveESD
        let secondSlugDeltaRho = secondSlugDensity - effectiveESD

        let surfaceSlugDropHeight = (surfaceSlugDeltaRho * surfaceSlugTVDHeight) / effectiveESD
        let secondSlugDropHeight = (secondSlugDeltaRho * secondSlugTVDHeight) / effectiveESD

        // Total drop height and convert to volume using STRING capacity (fluid drains from string)
        let totalSlugDropHeight = max(0, surfaceSlugDropHeight + secondSlugDropHeight)

        let totalSlugDrop: Double
        let calculatedSlugDrop = totalSlugDropHeight * stringCapacity
        if let observed = input.observedSlugDrop_m3 {
            totalSlugDrop = observed
        } else {
            totalSlugDrop = calculatedSlugDrop
        }

        // 5. Calculate steel displacement
        let steelDisplacement = calculateSteelDisplacement(
            fromMD: 0,
            toMD: input.startBitMD_m,
            drillString: drillString
        )

        // 6. Kill mud volume = pipe displacement + slug drop
        let killMudVolume = steelDisplacement + totalSlugDrop

        // 7. Layer positions in annulus by MD, then convert to TVD for pressure calc
        //
        // Layers from surface (by MD):
        // - Kill mud: 0 to killMudBottomMD
        // - Surface slug: killMudBottomMD to surfaceSlugBottomMD
        // - Active mud: surfaceSlugBottomMD to secondSlugTopMD
        // - 2nd slug: secondSlugTopMD to heelMD (bottom at heel)
        // - Original mud: heelMD to controlMD

        // Calculate MD lengths from volumes
        let killMudLength_MD = killMudVolume / max(annulusCapacity, 0.001)
        let surfaceSlugLength_MD = input.surfaceSlugVolume_m3 / max(annulusCapacity, 0.001)
        let secondSlugLength_MD = secondSlugVolume / max(annulusCapacity, 0.001)

        // Calculate MD positions of layer boundaries
        let killMudBottomMD = killMudLength_MD
        let surfaceSlugBottomMD_ann = killMudBottomMD + surfaceSlugLength_MD
        let secondSlugTopMD = heelMD - secondSlugLength_MD  // 2nd slug bottom is at heel
        let activeMudLength_MD = max(0, secondSlugTopMD - surfaceSlugBottomMD_ann)

        // Convert MD positions to TVD using the sampler
        let killMudBottomTVD = tvdSampler.tvd(of: killMudBottomMD)
        let surfaceSlugBottomTVD = tvdSampler.tvd(of: surfaceSlugBottomMD_ann)
        let secondSlugTopTVD = tvdSampler.tvd(of: secondSlugTopMD)
        // heelTVD already calculated above
        // controlTVD already calculated above

        // Calculate TVD heights for pressure calculation
        let killMudHeight = killMudBottomTVD  // From surface (TVD=0) to killMudBottomTVD
        let surfaceSlugHeight = surfaceSlugBottomTVD - killMudBottomTVD
        let activeMudHeight = max(0, secondSlugTopTVD - surfaceSlugBottomTVD)
        let secondSlugHeight = heelTVD - secondSlugTopTVD
        let originalMudHeight = max(0, controlTVD - heelTVD)

        // Volume of active mud in annulus
        let activeMudVolumeAnnulus = activeMudLength_MD * annulusCapacity

        // 8. Solve for kill mud density to achieve target ESD at control point
        //
        // 5 layers from surface: kill mud, surface slug, active mud, 2nd slug, original mud
        // P_control = ρ_kill × h_kill_TVD + ρ_surface × h_surface_TVD + ...
        //
        // Solve for ρ_kill:
        // ρ_kill = (targetESD × controlTVD - other contributions) / h_kill_TVD

        let targetPressure = input.targetESD_kgm3 * controlTVD
        let surfaceSlugContribution = input.surfaceSlugDensity_kgm3 * surfaceSlugHeight
        let activeMudContribution = input.baseMudDensity_kgm3 * activeMudHeight
        let secondSlugContribution = secondSlugDensity * secondSlugHeight
        let originalMudContribution = input.baseMudDensity_kgm3 * originalMudHeight

        var killMudDensity: Double
        if killMudHeight > 0.1 {
            killMudDensity = (targetPressure - surfaceSlugContribution - activeMudContribution - secondSlugContribution - originalMudContribution) / killMudHeight
        } else {
            killMudDensity = input.baseMudDensity_kgm3
            warnings.append("Kill mud height too small. Using base mud density.")
        }

        // 9. Validate and clamp
        if killMudDensity < 1000 {
            warnings.append("Calculated kill mud density (\(String(format: "%.0f", killMudDensity)) kg/m³) is very low. Heavy slugs may be overcompensating.")
            killMudDensity = max(killMudDensity, 800)  // Allow water-like minimum
        }
        if killMudDensity > 2500 {
            warnings.append("Kill mud density clamped to 2500 kg/m³. Check inputs.")
            killMudDensity = 2500
        }

        let isValid = killMudDensity >= 800 && killMudDensity <= 2500

        return TripOptimizerResult(
            killMudDensity_kgm3: killMudDensity,
            surfaceSlugVolume_m3: input.surfaceSlugVolume_m3,
            activeMudVolume_m3: activeMudVolumeAnnulus,
            secondSlugVolume_m3: secondSlugVolume,
            slugDropVolume_m3: totalSlugDrop,
            slugDropCalculated_m3: calculatedSlugDrop,
            killMudVolume_m3: killMudVolume,
            totalSteelDisplacement_m3: steelDisplacement,
            effectiveESD_kgm3: effectiveESD,
            surfaceSlugMDLength_m: surfaceSlugMDLength,
            surfaceSlugTVDHeight_m: surfaceSlugTVDHeight,
            secondSlugMDLength_m: secondSlugMDLength,
            secondSlugTVDHeight_m: secondSlugTVDHeight,
            surfaceSlugDropHeight_m: surfaceSlugDropHeight,
            secondSlugDropHeight_m: secondSlugDropHeight,
            killMudHeight_m: killMudHeight,
            surfaceSlugHeight_m: surfaceSlugHeight,
            activeMudHeight_m: activeMudHeight,
            secondSlugHeight_m: secondSlugHeight,
            originalMudHeight_m: originalMudHeight,
            annulusCapacity_m3_per_m: annulusCapacity,
            heelMD_m: heelMD,
            heelTVD_m: heelTVD,
            sixtyDegTVD_m: heelTVD,  // 2nd slug bottom is at heel
            controlTVD_m: controlTVD,
            surfaceSlugBottomMD_m: surfaceSlugBottomMD,
            surfaceSlugDensity_kgm3: input.surfaceSlugDensity_kgm3,
            secondSlugDensity_kgm3: secondSlugDensity,
            secondSlugDensityCalculated_kgm3: secondSlugDensityCalculated,
            secondSlugDensityWasCalculated: secondSlugDensityWasCalculated,
            baseMudDensity_kgm3: input.baseMudDensity_kgm3,
            warnings: warnings,
            isValid: isValid
        )
    }

    // MARK: - Helper Calculations

    /// Calculate MD reached for a given volume from start
    private static func calculateDepthForVolume(
        volume: Double,
        fromMD: Double,
        drillString: [DrillStringSection]
    ) -> Double {
        let sorted = drillString.sorted { $0.topDepth_m < $1.topDepth_m }
        var remainingVolume = volume
        var currentMD = fromMD

        for section in sorted {
            guard section.bottomDepth_m > currentMD else { continue }

            let sectionTop = max(section.topDepth_m, currentMD)
            let sectionBottom = section.bottomDepth_m
            let sectionLength = sectionBottom - sectionTop

            let id = section.innerDiameter_m
            let capacity = Double.pi * (id / 2) * (id / 2)

            let sectionVolume = capacity * sectionLength

            if remainingVolume <= sectionVolume {
                let depthInSection = remainingVolume / max(capacity, 0.0001)
                return sectionTop + depthInSection
            } else {
                remainingVolume -= sectionVolume
                currentMD = sectionBottom
            }
        }

        return currentMD
    }

    /// Calculate string internal volume between two MDs
    private static func calculateStringVolume(
        fromMD: Double,
        toMD: Double,
        drillString: [DrillStringSection]
    ) -> Double {
        let sorted = drillString.sorted { $0.topDepth_m < $1.topDepth_m }
        var totalVolume: Double = 0

        for section in sorted {
            let sectionTop = max(section.topDepth_m, fromMD)
            let sectionBottom = min(section.bottomDepth_m, toMD)

            guard sectionBottom > sectionTop else { continue }

            let length = sectionBottom - sectionTop
            let id = section.innerDiameter_m
            let capacity = Double.pi * (id / 2) * (id / 2)

            totalVolume += capacity * length
        }

        return totalVolume
    }

    /// Calculate steel displacement (OD volume - ID volume)
    private static func calculateSteelDisplacement(
        fromMD: Double,
        toMD: Double,
        drillString: [DrillStringSection]
    ) -> Double {
        let sorted = drillString.sorted { $0.topDepth_m < $1.topDepth_m }
        var totalDisplacement: Double = 0

        for section in sorted {
            let sectionTop = max(section.topDepth_m, fromMD)
            let sectionBottom = min(section.bottomDepth_m, toMD)

            guard sectionBottom > sectionTop else { continue }

            let length = sectionBottom - sectionTop
            let od = section.outerDiameter_m
            let id = section.innerDiameter_m

            let odRadius = od / 2
            let idRadius = id / 2
            let odVolume = Double.pi * odRadius * odRadius * length
            let idVolume = Double.pi * idRadius * idRadius * length

            totalDisplacement += (odVolume - idVolume)
        }

        return totalDisplacement
    }

    /// Get annulus capacity at surface (m³/m)
    @MainActor
    private static func getAnnulusCapacityAtSurface(project: ProjectState) -> Double {
        let annulus = project.annulus ?? []
        // Get the first (shallowest) annulus section
        if let firstSection = annulus.min(by: { $0.topDepth_m < $1.topDepth_m }) {
            return firstSection.flowArea_m2  // m³/m = m²
        }
        // Default if no annulus defined (assume 12-1/4" hole with 5" pipe)
        let holeID = 0.311  // 12.25"
        let pipeOD = 0.127  // 5"
        return Double.pi * ((holeID/2)*(holeID/2) - (pipeOD/2)*(pipeOD/2))
    }

    /// Get drill string internal capacity at surface (m³/m) - pipe bore area
    @MainActor
    private static func getStringCapacityAtSurface(project: ProjectState) -> Double {
        let drillString = project.drillString ?? []
        // Get the first (shallowest) drill string section
        if let firstSection = drillString.min(by: { $0.topDepth_m < $1.topDepth_m }) {
            let id = firstSection.innerDiameter_m
            return Double.pi * (id / 2) * (id / 2)  // m²
        }
        // Default if no drill string defined (assume 5" DP with 4.276" ID)
        let pipeID = 0.1086  // 4.276"
        return Double.pi * (pipeID / 2) * (pipeID / 2)
    }
}
