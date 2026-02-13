//
//  ReamEngine.swift
//  Josh Well Control for Mac
//
//  Combines tripping and circulating for ream/wash operations.
//  Thin wrapper around existing trip engines. Runs the trip simulation, then
//  augments each step with APL (from pump rate) and surge (for ream-in).
//
//  Physics:
//    Ream Out: BHP = HP_static + SABP + APL - Swab  (opposing flows)
//    Ream In:  BHP = HP_static + SABP + APL + Surge  (same direction flows)
//

import Foundation

// MARK: - Result Step Types

struct ReamOutStep: Identifiable {
    let id = UUID()
    let bitMD_m: Double
    let bitTVD_m: Double

    // Static pressures (from trip-out engine)
    let SABP_kPa: Double
    let SABP_kPa_Raw: Double
    let ESDatTD_kgpm3: Double
    let ESDatBit_kgpm3: Double

    // Dynamic pressures
    let swab_kPa: Double               // Swab pressure magnitude (reduces BHP)
    let apl_kPa: Double                // APL from pumping (increases BHP)
    let pumpRate_m3perMin: Double

    // Combined: SABP_Dynamic = max(0, SABP_static + swab - APL)
    let SABP_Dynamic_kPa: Double

    // ECD including all dynamic effects
    let ECD_kgpm3: Double

    // Volume tracking (from trip-out engine)
    let floatState: String
    let stepBackfill_m3: Double
    let cumulativeBackfill_m3: Double
    let expectedFillIfClosed_m3: Double
    let expectedFillIfOpen_m3: Double

    // Layer snapshots
    let layersPocket: [NumericalTripModel.LayerRow]
    let layersAnnulus: [NumericalTripModel.LayerRow]
    let layersString: [NumericalTripModel.LayerRow]
    let totalsPocket: NumericalTripModel.Totals
    let totalsAnnulus: NumericalTripModel.Totals
    let totalsString: NumericalTripModel.Totals
}

struct ReamInStep: Identifiable {
    let id = UUID()
    let stepIndex: Int
    let bitMD_m: Double
    let bitTVD_m: Double

    // Static pressures (from trip-in engine)
    let ESDAtControl_kgpm3: Double
    let ESDAtBit_kgpm3: Double
    let requiredChokePressure_kPa: Double

    // Dynamic pressures
    let surge_kPa: Double              // Surge pressure magnitude (increases BHP)
    let apl_kPa: Double                // APL from pumping (increases BHP)
    let pumpRate_m3perMin: Double

    // Combined: dynamicChoke = max(0, requiredChoke - APL - surge)
    let dynamicChoke_kPa: Double

    // ECD including all dynamic effects
    let ECD_kgpm3: Double

    // Volume tracking (from trip-in engine)
    let stepFillVolume_m3: Double
    let cumulativeFillVolume_m3: Double
    let expectedFillClosed_m3: Double
    let expectedFillOpen_m3: Double
    let stepDisplacementReturns_m3: Double
    let cumulativeDisplacementReturns_m3: Double
    let isBelowTarget: Bool
    let floatState: String

    // Layer snapshots
    let layersPocket: [TripLayerSnapshot]
}

// MARK: - APL from LayerRow (used by Ream Out)

/// Calculate annular pressure loss from LayerRow array (trip-out engine format).
/// Walks layers above the bit, computing APL per segment using layer rheology.
func calculateAPLFromLayerRows(
    layers: [NumericalTripModel.LayerRow],
    bitMD_m: Double,
    pumpRate_m3perMin: Double,
    annulusSections: [AnnulusSection],
    drillStringSections: [DrillStringSection]
) -> Double {
    guard pumpRate_m3perMin > 0.001 else { return 0 }

    let apl = APLCalculationService.shared
    var totalAPL = 0.0

    for layer in layers {
        guard layer.bottomMD <= bitMD_m, layer.topMD < layer.bottomMD else { continue }
        let effectiveBottom = min(layer.bottomMD, bitMD_m)
        let length = effectiveBottom - layer.topMD
        guard length > 0 else { continue }

        let midMD = (layer.topMD + effectiveBottom) / 2.0

        // Find hole ID at layer midpoint from annulus sections
        var holeID = 0.3  // fallback
        for s in annulusSections {
            if midMD >= s.topDepth_m && midMD <= s.bottomDepth_m {
                holeID = s.innerDiameter_m
                break
            }
        }

        // Find pipe OD at layer midpoint from drill string sections
        var pipeOD = 0.127  // fallback
        for s in drillStringSections {
            if midMD >= s.topDepth_m && midMD <= s.bottomDepth_m {
                pipeOD = s.outerDiameter_m
                break
            }
        }

        if layer.pv_cP > 0 && layer.yp_Pa > 0 {
            totalAPL += apl.aplBingham(
                length_m: length,
                flowRate_m3_per_min: pumpRate_m3perMin,
                holeDiameter_m: holeID,
                pipeDiameter_m: pipeOD,
                plasticViscosity_cP: layer.pv_cP,
                yieldPoint_Pa: layer.yp_Pa
            )
        } else {
            totalAPL += apl.aplSimplified(
                density_kgm3: layer.rho_kgpm3,
                length_m: length,
                flowRate_m3_per_min: pumpRate_m3perMin,
                holeDiameter_m: holeID,
                pipeDiameter_m: pipeOD
            )
        }
    }

    return totalAPL
}

// MARK: - APL from TripLayerSnapshot (used by Ream In)

/// Calculate annular pressure loss from TripLayerSnapshot array (trip-in engine format).
func calculateAPLFromTripLayerSnapshots(
    layers: [TripLayerSnapshot],
    bitMD_m: Double,
    pumpRate_m3perMin: Double,
    annulusSections: [AnnulusSection],
    drillStringSections: [DrillStringSection]
) -> Double {
    guard pumpRate_m3perMin > 0.001 else { return 0 }

    let apl = APLCalculationService.shared
    var totalAPL = 0.0

    for layer in layers {
        guard layer.bottomMD <= bitMD_m, layer.topMD < layer.bottomMD else { continue }
        let effectiveBottom = min(layer.bottomMD, bitMD_m)
        let length = effectiveBottom - layer.topMD
        guard length > 0 else { continue }

        let midMD = (layer.topMD + effectiveBottom) / 2.0

        var holeID = 0.3
        for s in annulusSections {
            if midMD >= s.topDepth_m && midMD <= s.bottomDepth_m {
                holeID = s.innerDiameter_m
                break
            }
        }

        var pipeOD = 0.127
        for s in drillStringSections {
            if midMD >= s.topDepth_m && midMD <= s.bottomDepth_m {
                pipeOD = s.outerDiameter_m
                break
            }
        }

        let pvCp = layer.pv_cP ?? 0
        let ypPa = layer.yp_Pa ?? 0

        if pvCp > 0 && ypPa > 0 {
            totalAPL += apl.aplBingham(
                length_m: length,
                flowRate_m3_per_min: pumpRate_m3perMin,
                holeDiameter_m: holeID,
                pipeDiameter_m: pipeOD,
                plasticViscosity_cP: pvCp,
                yieldPoint_Pa: ypPa
            )
        } else {
            totalAPL += apl.aplSimplified(
                density_kgm3: layer.rho_kgpm3,
                length_m: length,
                flowRate_m3_per_min: pumpRate_m3perMin,
                holeDiameter_m: holeID,
                pipeDiameter_m: pipeOD
            )
        }
    }

    return totalAPL
}

// MARK: - Ream Out Engine

/// Run ream-out: trip-out engine + APL from pumping per step.
/// SABP_Dynamic = max(0, SABP_static + swab - APL)
func runReamOut(
    tripInput: NumericalTripModel.TripInput,
    geom: GeometryService,
    projectSnapshot: NumericalTripModel.ProjectSnapshot,
    pumpRate_m3perMin: Double,
    annulusSections: [AnnulusSection],
    drillStringSections: [DrillStringSection],
    controlMD_m: Double,
    tvdSampler: TvdSampler
) -> [ReamOutStep] {
    let model = NumericalTripModel()
    let tripSteps = model.run(tripInput, geom: geom, projectSnapshot: projectSnapshot)

    let controlTVD = tvdSampler.tvd(of: controlMD_m)

    return tripSteps.map { step in
        let aplValue = calculateAPLFromLayerRows(
            layers: step.layersAnnulus,
            bitMD_m: step.bitMD_m,
            pumpRate_m3perMin: pumpRate_m3perMin,
            annulusSections: annulusSections,
            drillStringSections: drillStringSections
        )

        let swab = step.swabDropToBit_kPa

        // Ream Out: swab requires more SABP, APL requires less (opposing flows)
        let sabpDynamic = max(0, step.SABP_kPa + swab - aplValue)

        // ECD at control depth
        let ecd = controlTVD > 0
            ? step.ESDatTD_kgpm3 + (sabpDynamic + aplValue) / (0.00981 * controlTVD)
            : step.ESDatTD_kgpm3

        return ReamOutStep(
            bitMD_m: step.bitMD_m,
            bitTVD_m: step.bitTVD_m,
            SABP_kPa: step.SABP_kPa,
            SABP_kPa_Raw: step.SABP_kPa_Raw,
            ESDatTD_kgpm3: step.ESDatTD_kgpm3,
            ESDatBit_kgpm3: step.ESDatBit_kgpm3,
            swab_kPa: swab,
            apl_kPa: aplValue,
            pumpRate_m3perMin: pumpRate_m3perMin,
            SABP_Dynamic_kPa: sabpDynamic,
            ECD_kgpm3: ecd,
            floatState: step.floatState,
            stepBackfill_m3: step.stepBackfill_m3,
            cumulativeBackfill_m3: step.cumulativeBackfill_m3,
            expectedFillIfClosed_m3: step.expectedFillIfClosed_m3,
            expectedFillIfOpen_m3: step.expectedFillIfOpen_m3,
            layersPocket: step.layersPocket,
            layersAnnulus: step.layersAnnulus,
            layersString: step.layersString,
            totalsPocket: step.totalsPocket,
            totalsAnnulus: step.totalsAnnulus,
            totalsString: step.totalsString
        )
    }
}

// MARK: - Ream In Engine

/// Run ream-in: trip-in engine + surge + APL per step.
/// dynamicChoke = max(0, requiredChoke - APL - surge)
func runReamIn(
    tripInInput: TripInService.TripInInput,
    pumpRate_m3perMin: Double,
    annulusSections: [AnnulusSection],
    drillStringSections: [DrillStringSection],
    tvdSampler: TvdSampler,
    controlMD_m: Double
) -> [ReamInStep] {
    let tripInResult = TripInService.run(tripInInput)
    let controlTVD = tvdSampler.tvd(of: controlMD_m)

    return tripInResult.steps.map { step in
        let aplValue = calculateAPLFromTripLayerSnapshots(
            layers: step.layersPocket,
            bitMD_m: step.bitMD_m,
            pumpRate_m3perMin: pumpRate_m3perMin,
            annulusSections: annulusSections,
            drillStringSections: drillStringSections
        )

        // Surge is already computed in step from the surgeProfile
        let surge = step.surgePressure_kPa

        // Ream In: both surge and APL increase BHP → reduce required choke
        let dynamicChoke = max(0, step.requiredChokePressure_kPa - aplValue - surge)

        // ECD at control depth
        let ecd = controlTVD > 0
            ? step.ESDAtControl_kgpm3 + (dynamicChoke + aplValue + surge) / (0.00981 * controlTVD)
            : step.ESDAtControl_kgpm3

        return ReamInStep(
            stepIndex: step.stepIndex,
            bitMD_m: step.bitMD_m,
            bitTVD_m: step.bitTVD_m,
            ESDAtControl_kgpm3: step.ESDAtControl_kgpm3,
            ESDAtBit_kgpm3: step.ESDAtBit_kgpm3,
            requiredChokePressure_kPa: step.requiredChokePressure_kPa,
            surge_kPa: surge,
            apl_kPa: aplValue,
            pumpRate_m3perMin: pumpRate_m3perMin,
            dynamicChoke_kPa: dynamicChoke,
            ECD_kgpm3: ecd,
            stepFillVolume_m3: step.stepFillVolume_m3,
            cumulativeFillVolume_m3: step.cumulativeFillVolume_m3,
            expectedFillClosed_m3: step.expectedFillClosed_m3,
            expectedFillOpen_m3: step.expectedFillOpen_m3,
            stepDisplacementReturns_m3: step.stepDisplacementReturns_m3,
            cumulativeDisplacementReturns_m3: step.cumulativeDisplacementReturns_m3,
            isBelowTarget: step.isBelowTarget,
            floatState: step.floatState,
            layersPocket: step.layersPocket
        )
    }
}
