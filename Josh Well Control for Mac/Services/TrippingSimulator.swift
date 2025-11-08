//
//  TrippingSimulator.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-06.
//

import Foundation

/// Optional trajectory sampling to convert MD → TVD during simulation.
protocol TrajectorySampler {
    /// Returns TVD (m) for a given MD (m). Implementations may clamp or interpolate as needed.
    func TVDofMD(_ md: Double) -> Double
}

struct TripDirection { enum Kind { case pullOutOfHole, runInHole } }

struct TrippingSimulator {
    let calc = SwabCalculator()

    /// Runs a tripping simulation, returning a series of swab/surge samples at each bit position.
    /// - Parameters:
    ///   - project: The active project whose geometry and layers are used for context.
    ///   - finalLayers: Persisted final fluid layers to slice (annulus/both) each step.
    ///   - annulus: Annulus geometry sections (hole ID by MD).
    ///   - string: Drill string sections (pipe OD by MD).
    ///   - direction: `.pullOutOfHole` (swab above-bit) or `.runInHole` (surge below-bit).
    ///   - startBitMD: Starting bit MD (m).
    ///   - endBitMD: Ending bit MD (m).
    ///   - mdStep: Step size in MD (m) between samples.
    ///   - hoistSpeed_mpermin: Hoist/run speed magnitude (m/min).
    ///   - theta600/theta300: Fann readings used by rheology model in `SwabCalculator`.
    ///   - eccentricityFactor: Multiplier ≥ 1 used to inflate annular velocity for eccentricity.
    ///   - traj: Optional trajectory sampler providing TVD for reporting; pass `nil` to skip.
    ///   - surgeLowerLimitMD: Lower MD bound for surge integration (e.g., shoe or TD).
    func simulate(
        project: ProjectState,
        finalLayers: [FinalFluidLayer],
        annulus: [AnnulusSection],
        string: [DrillStringSection],
        direction: TripDirection.Kind,
        startBitMD: Double,
        endBitMD: Double,
        mdStep: Double,                 // e.g. 5 m
        hoistSpeed_mpermin: Double,     // positive magnitude; sign from direction
        theta600: Double, theta300: Double,
        eccentricityFactor: Double,
        traj: TrajectorySampler?,       // optional
        surgeLowerLimitMD: Double       // for RIH, usually casing shoe or TD
    ) throws -> [TripSample] {

        guard mdStep > 0 else { return [] }

        let geom = ProjectGeometryService(
            annulus: annulus,
            string: string,
            currentStringBottomMD: startBitMD
        )

        let ascending = direction == .runInHole
        let stepSign = ascending ? +1.0 : -1.0
        var bit = startBitMD
        var out: [TripSample] = []

        func onePass(domain: LayerDomain, bitMD: Double) throws -> TripSample {
            // Update string bottom to current bit
            geom.currentStringBottomMD = bitMD

            let dto = LayerResolver.slice(
                finalLayers,
                for: project,
                domain: domain,
                bitMD: bitMD,
                lowerLimitMD: surgeLowerLimitMD
            )

            // Choose which domain to evaluate:
            // Swab when pulling out (above bit), Surge when running in (below bit).
            let estimate = try calc.estimateFromLayersPowerLaw(
                layers: dto,
                theta600: theta600,
                theta300: theta300,
                hoistSpeed_mpermin: hoistSpeed_mpermin,   // magnitude; engine computes Va from this
                eccentricityFactor: eccentricityFactor,
                step_m: mdStep,
                geom: geom,
                traj: traj,
                sabpSafety: 1.15
            )
            return .init(bitMD_m: bitMD, tvd_m: (traj?.TVDofMD(bitMD) ?? bitMD),
                         total_kPa: estimate.totalSwab_kPa,
                         recommendedSABP_kPa: estimate.recommendedSABP_kPa,
                         nonLaminar: estimate.nonLaminarFlag)
        }

        // March bit depth in mdStep increments
        while true {
            let domain: LayerDomain = ascending ? .surgeBelowBit : .swabAboveBit
            let sample = try onePass(domain: domain, bitMD: bit)
            out.append(sample)

            // advance or stop
            let next = bit + stepSign * mdStep
            if ascending {
                if next > endBitMD + 1e-9 { break }
            } else {
                if next < endBitMD - 1e-9 { break }
            }
            bit = next
        }

        return out
    }
}
