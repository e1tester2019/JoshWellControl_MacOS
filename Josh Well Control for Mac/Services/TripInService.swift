//
//  TripInService.swift
//  Josh Well Control for Mac
//
//  Stateless trip-in physics engine extracted from TripInSimulationViewModel.
//  Models pipe displacement with geometry-aware layer expansion.
//

import Foundation

enum TripInService {

    // MARK: - Result Types

    struct TripInResult {
        let steps: [TripInStepResult]
    }

    struct TripInStepResult: Identifiable {
        let id = UUID()
        let stepIndex: Int
        let bitMD_m: Double
        let bitTVD_m: Double
        let stepFillVolume_m3: Double
        let cumulativeFillVolume_m3: Double
        let expectedFillClosed_m3: Double
        let expectedFillOpen_m3: Double
        let stepDisplacementReturns_m3: Double
        let cumulativeDisplacementReturns_m3: Double
        let ESDAtControl_kgpm3: Double
        let ESDAtBit_kgpm3: Double
        let requiredChokePressure_kPa: Double
        let isBelowTarget: Bool
        let differentialPressureAtBottom_kPa: Double
        let annulusPressureAtBit_kPa: Double
        let stringPressureAtBit_kPa: Double
        let floatState: String
        let layersPocket: [TripLayerSnapshot]
    }

    struct TripInInput {
        let startBitMD_m: Double
        let endBitMD_m: Double
        let controlMD_m: Double
        let step_m: Double
        let pipeOD_m: Double
        let pipeID_m: Double
        let activeMudDensity_kgpm3: Double
        let baseMudDensity_kgpm3: Double
        let targetESD_kgpm3: Double
        let isFloatedCasing: Bool
        let floatSubMD_m: Double
        let crackFloat_kPa: Double
        let pocketLayers: [TripLayerSnapshot]
        let annulusSections: [AnnulusSection]
        let tvdSampler: TvdSampler
    }

    // MARK: - Run Simulation

    static func run(_ input: TripInInput) -> TripInResult {
        var depths: [Double] = []
        var currentDepth = input.startBitMD_m
        while currentDepth <= input.endBitMD_m {
            depths.append(currentDepth)
            currentDepth += input.step_m
        }
        if depths.last != input.endBitMD_m {
            depths.append(input.endBitMD_m)
        }

        var cumulativeFill: Double = 0
        var cumulativeDisplacement: Double = 0
        let controlTVD = input.tvdSampler.tvd(of: input.controlMD_m)
        var steps: [TripInStepResult] = []

        for (index, bitMD) in depths.enumerated() {
            let bitTVD = input.tvdSampler.tvd(of: bitMD)
            let prevMD = index > 0 ? depths[index - 1] : input.startBitMD_m
            let intervalLength = abs(bitMD - prevMD)

            let pipeCapacity = Double.pi / 4.0 * input.pipeID_m * input.pipeID_m
            let pipeDisplacement = Double.pi / 4.0 * (input.pipeOD_m * input.pipeOD_m - input.pipeID_m * input.pipeID_m)

            let stepFill: Double
            if input.isFloatedCasing && bitMD > input.floatSubMD_m {
                stepFill = 0
            } else {
                stepFill = pipeCapacity * intervalLength
            }
            cumulativeFill += stepFill

            let stepDisplacement = (Double.pi / 4.0 * input.pipeOD_m * input.pipeOD_m) * intervalLength
            cumulativeDisplacement += stepDisplacement

            let expectedClosed = pipeCapacity * bitMD
            let expectedOpen = pipeDisplacement * bitMD

            let displacedPockets = calculateDisplacedPocketLayers(
                bitMD: bitMD,
                pocketLayers: input.pocketLayers,
                annulusSections: input.annulusSections,
                pipeOD_m: input.pipeOD_m,
                tvdSampler: input.tvdSampler
            )

            let ESDAtControl = CirculationService.calculateESDFromLayers(
                layers: displacedPockets,
                atDepthMD: input.controlMD_m,
                tvdSampler: input.tvdSampler
            )

            let ESDAtBit = CirculationService.calculateESDFromLayers(
                layers: displacedPockets,
                atDepthMD: bitMD,
                tvdSampler: input.tvdSampler
            )

            let isBelowTarget = ESDAtControl < input.targetESD_kgpm3

            let requiredChoke: Double
            if isBelowTarget {
                requiredChoke = max(0, (input.targetESD_kgpm3 - ESDAtControl) * 0.00981 * controlTVD)
            } else {
                requiredChoke = 0
            }

            var floatState = "N/A"
            let annulusHP = ESDAtBit * 0.00981 * bitTVD
            var stringHP: Double = 0

            if input.isFloatedCasing && bitMD >= input.floatSubMD_m {
                let pipeCapacityPerMeter = Double.pi / 4.0 * input.pipeID_m * input.pipeID_m
                let mudHeightInString = cumulativeFill / pipeCapacityPerMeter
                let fillLevelMD = min(mudHeightInString, bitMD)
                let fillLevelTVD = input.tvdSampler.tvd(of: fillLevelMD)
                stringHP = input.activeMudDensity_kgpm3 * 0.00981 * fillLevelTVD

                let floatSubTVD = input.tvdSampler.tvd(of: input.floatSubMD_m)
                let annulusPressureAtFloat = input.baseMudDensity_kgpm3 * 0.00981 * floatSubTVD
                let mudAboveFloat = min(mudHeightInString, input.floatSubMD_m)
                let insidePressureAtFloat = input.activeMudDensity_kgpm3 * 0.00981 * input.tvdSampler.tvd(of: mudAboveFloat)
                let diffAtFloat = annulusPressureAtFloat - insidePressureAtFloat

                if diffAtFloat >= input.crackFloat_kPa {
                    let openPercent = min(100, Int((diffAtFloat / input.crackFloat_kPa - 1.0) * 100 + 50))
                    floatState = "OPEN \(openPercent)%"
                } else {
                    let closedPercent = Int((1.0 - diffAtFloat / input.crackFloat_kPa) * 100)
                    floatState = "CLOSED \(closedPercent)%"
                }
            } else {
                stringHP = input.activeMudDensity_kgpm3 * 0.00981 * bitTVD
                floatState = "Full"
            }

            let differentialPressure = annulusHP - stringHP

            steps.append(TripInStepResult(
                stepIndex: index,
                bitMD_m: bitMD,
                bitTVD_m: bitTVD,
                stepFillVolume_m3: stepFill,
                cumulativeFillVolume_m3: cumulativeFill,
                expectedFillClosed_m3: expectedClosed,
                expectedFillOpen_m3: expectedOpen,
                stepDisplacementReturns_m3: stepDisplacement,
                cumulativeDisplacementReturns_m3: cumulativeDisplacement,
                ESDAtControl_kgpm3: ESDAtControl,
                ESDAtBit_kgpm3: ESDAtBit,
                requiredChokePressure_kPa: requiredChoke,
                isBelowTarget: isBelowTarget,
                differentialPressureAtBottom_kPa: differentialPressure,
                annulusPressureAtBit_kPa: annulusHP,
                stringPressureAtBit_kPa: stringHP,
                floatState: floatState,
                layersPocket: displacedPockets
            ))
        }

        return TripInResult(steps: steps)
    }

    // MARK: - Displaced Pocket Layers

    /// Calculate displaced pocket layers at current bit depth.
    /// Models pipe displacement with geometry-aware expansion during trip-IN.
    ///
    /// Physics: As pipe enters a layer, that layer EXPANDS (same volume in narrower annulus = taller).
    /// Expansion factor = original wellbore capacity / new annular capacity.
    /// Expanded layers push layers above them upward; top layers overflow at surface.
    static func calculateDisplacedPocketLayers(
        bitMD: Double,
        pocketLayers: [TripLayerSnapshot],
        annulusSections: [AnnulusSection],
        pipeOD_m: Double,
        tvdSampler: TvdSampler
    ) -> [TripLayerSnapshot] {
        guard !pocketLayers.isEmpty else { return [] }

        func wellboreID(at depth: Double) -> Double {
            if let section = annulusSections.first(where: { depth >= $0.topDepth_m && depth <= $0.bottomDepth_m }) {
                return section.innerDiameter_m
            }
            return annulusSections.max(by: { $0.bottomDepth_m < $1.bottomDepth_m })?.innerDiameter_m ?? 0.2159
        }

        func expansionFactor(at depth: Double) -> Double {
            let wellboreID_m = wellboreID(at: depth)
            let originalArea = Double.pi / 4.0 * wellboreID_m * wellboreID_m
            let annularArea = Double.pi / 4.0 * (wellboreID_m * wellboreID_m - pipeOD_m * pipeOD_m)
            guard annularArea > 0.0001 else { return 1.0 }
            return originalArea / annularArea
        }

        let sortedLayers = pocketLayers.sorted { $0.bottomMD > $1.bottomMD }

        struct LayerTransform {
            let layer: TripLayerSnapshot
            let originalHeight: Double
            let newHeight: Double
        }

        var transforms: [LayerTransform] = []

        for layer in sortedLayers {
            let originalHeight = layer.bottomMD - layer.topMD
            guard originalHeight > 0 else { continue }

            let alreadyInAnnulus = layer.isInAnnulus == true

            let newHeight: Double
            if layer.bottomMD <= bitMD {
                if alreadyInAnnulus {
                    newHeight = originalHeight
                } else {
                    let midpoint = (layer.topMD + layer.bottomMD) / 2.0
                    newHeight = originalHeight * expansionFactor(at: midpoint)
                }
            } else if layer.topMD < bitMD {
                let aboveBitHeight = bitMD - layer.topMD
                let belowBitHeight = layer.bottomMD - bitMD
                if alreadyInAnnulus {
                    newHeight = originalHeight
                } else {
                    let factor = expansionFactor(at: (layer.topMD + bitMD) / 2.0)
                    newHeight = (aboveBitHeight * factor) + belowBitHeight
                }
            } else {
                newHeight = originalHeight
            }

            transforms.append(LayerTransform(layer: layer, originalHeight: originalHeight, newHeight: newHeight))
        }

        var resultLayers: [TripLayerSnapshot] = []
        var nextLayerBottom: Double? = nil

        for transform in transforms {
            let layer = transform.layer

            let newBottom: Double
            if let prevTop = nextLayerBottom {
                newBottom = prevTop
            } else {
                newBottom = layer.bottomMD
            }

            let newTop = newBottom - transform.newHeight
            nextLayerBottom = newTop

            if newBottom <= 0 { continue }
            let clampedTop = max(0, newTop)
            if clampedTop >= newBottom { continue }

            let newTopTVD = tvdSampler.tvd(of: clampedTop)
            let newBottomTVD = tvdSampler.tvd(of: newBottom)
            let deltaP = layer.rho_kgpm3 * 0.00981 * (newBottomTVD - newTopTVD)

            resultLayers.append(TripLayerSnapshot(
                side: layer.side,
                topMD: clampedTop,
                bottomMD: newBottom,
                topTVD: newTopTVD,
                bottomTVD: newBottomTVD,
                rho_kgpm3: layer.rho_kgpm3,
                deltaHydroStatic_kPa: deltaP,
                volume_m3: 0,
                colorR: layer.colorR,
                colorG: layer.colorG,
                colorB: layer.colorB,
                colorA: layer.colorA,
                isInAnnulus: layer.isInAnnulus
            ))
        }

        return resultLayers
    }
}
