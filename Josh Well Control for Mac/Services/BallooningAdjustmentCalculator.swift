//
//  BallooningAdjustmentCalculator.swift
//  Josh Well Control for Mac
//
//  Calculates adjusted SABP when actual kill mud volume differs from simulated
//  due to wellbore ballooning.
//

import Foundation

/// Calculates adjusted SABP when ballooning prevents full kill mud placement.
///
/// The deficit volume is modeled as lighter (original) mud sitting at the top
/// of the annulus instead of heavier kill mud. This conservative placement
/// maximizes the TVD effect, producing the highest SABP correction — the safe
/// direction for well control.
enum BallooningAdjustmentCalculator {

    struct Input {
        let simulatedSABP_kPa: Double
        let simulatedKillMudVolume_m3: Double
        let actualKillMudVolume_m3: Double
        let killMudDensity_kgpm3: Double
        let originalMudDensity_kgpm3: Double
        let geom: GeometryService
    }

    struct Result {
        /// SABP to hold given actual volume
        let adjustedSABP_kPa: Double
        /// Additional SABP above plan (≥ 0)
        let deltaSABP_kPa: Double
        /// Simulated minus actual volume
        let volumeDeficit_m3: Double
        /// TVD height of the missing kill mud column
        let deficitTVDHeight_m: Double
        /// Hydrostatic pressure lost from the deficit
        let pressureLoss_kPa: Double
    }

    static func calculate(_ input: Input) -> Result {
        let deficit = max(0, input.simulatedKillMudVolume_m3 - input.actualKillMudVolume_m3)

        guard deficit > 0.001 else {
            return Result(
                adjustedSABP_kPa: input.simulatedSABP_kPa,
                deltaSABP_kPa: 0,
                volumeDeficit_m3: 0,
                deficitTVDHeight_m: 0,
                pressureLoss_kPa: 0
            )
        }

        // Convert deficit volume to MD length from surface using annulus geometry
        let mdLength = input.geom.lengthForAnnulusVolume_m(0, deficit)

        // Walk the MD span in 1m increments, converting to TVD for pressure calc
        let densityDelta = input.killMudDensity_kgpm3 - input.originalMudDensity_kgpm3
        let stepSize = 1.0
        let stepCount = max(1, Int(ceil(mdLength / stepSize)))
        let actualStep = mdLength / Double(stepCount)

        var totalPressureLoss_kPa = 0.0
        var totalTVDHeight = 0.0

        for i in 0..<stepCount {
            let topMD = Double(i) * actualStep
            let botMD = Double(i + 1) * actualStep
            let topTVD = input.geom.tvd(of: topMD)
            let botTVD = input.geom.tvd(of: botMD)
            let dTVD = max(0, botTVD - topTVD)
            totalTVDHeight += dTVD
            totalPressureLoss_kPa += densityDelta * 0.00981 * dTVD
        }

        let adjustedSABP = input.simulatedSABP_kPa + totalPressureLoss_kPa

        return Result(
            adjustedSABP_kPa: adjustedSABP,
            deltaSABP_kPa: totalPressureLoss_kPa,
            volumeDeficit_m3: deficit,
            deficitTVDHeight_m: totalTVDHeight,
            pressureLoss_kPa: totalPressureLoss_kPa
        )
    }
}
