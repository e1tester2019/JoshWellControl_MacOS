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
        // Surge pressure fields
        let surgePressure_kPa: Double
        let surgeECD_kgm3: Double
        let dynamicESDAtControl_kgpm3: Double
        // Torque & drag fields (nil if T&D not configured)
        let pickupHookLoad_kN: Double?
        let slackOffHookLoad_kN: Double?
        let rotatingHookLoad_kN: Double?
        let freeHangingWeight_kN: Double?
        let surfaceTorque_kNm: Double?
        let bucklingOnsetMD: Double?
        let stretch_m: Double?
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
        // Surge pressure inputs (0 speed = no surge)
        var tripSpeed_m_per_s: Double = 0
        var eccentricityFactor: Double = 1.0
        var floatIsOpen: Bool = false
        var fallbackTheta600: Double? = nil
        var fallbackTheta300: Double? = nil
        var geom: GeometryService? = nil
        // Torque & drag inputs (nil = skip T&D)
        var tdSurveys: [TorqueDragEngine.SurveyPoint]? = nil
        var tdStringSegments: [TorqueDragEngine.StringSegment]? = nil
        var tdHoleSections: [TorqueDragEngine.HoleSection]? = nil
        var tdFriction: TorqueDragEngine.FrictionFactors? = nil
        var tdBlockWeight_kN: Double = 0
        var tdAplEccentricity: Double = 1.0
        var tdPressureAreaBuoyancy: Bool = true
        var tdRPM: Double = 0
        var tdTripSpeedCased_m_per_s: Double = 0
        var tdTripSpeedOpenHole_m_per_s: Double = 0
        var tdRotationEfficiencyUp: Double = 1.0
        var tdRotationEfficiencyDown: Double = 1.0
        var tdSheaveLineFriction: Double = 0
        var holdSABPOpen: Bool = false
        // Continuation support: start cumulative counters from existing values
        var initialCumulativeFill_m3: Double = 0
        var initialCumulativeDisplacement_m3: Double = 0
    }

    // MARK: - Per-step surge from live layers

    /// Compute surge pressure at current bit depth using the actual displaced pocket layers.
    private static func computeSurge(
        displacedPockets: [TripLayerSnapshot],
        bitMD: Double,
        tripSpeed_m_per_s: Double,
        eccentricityFactor: Double,
        floatIsOpen: Bool,
        fallbackTheta600: Double?,
        fallbackTheta300: Double?,
        geom: GeometryService,
        tvdSampler: TvdSampler
    ) -> Double {
        guard tripSpeed_m_per_s > 0 else { return 0 }

        // Filter layers above the bit
        let layersAboveBit = displacedPockets.filter { $0.topMD < bitMD }
        guard !layersAboveBit.isEmpty else { return 0 }

        var layerDTOs: [SwabCalculator.LayerDTO] = []
        for layer in layersAboveBit {
            let topMD = layer.topMD
            let bottomMD = min(layer.bottomMD, bitMD)
            guard bottomMD > topMD else { continue }

            // Prefer dial readings directly, then reverse-engineer from pv/yp, then fallback
            var theta600: Double? = nil
            var theta300: Double? = nil

            if let d600 = layer.dial600, let d300 = layer.dial300, d600 > 0, d300 > 0 {
                theta600 = d600
                theta300 = d300
            } else if let pv = layer.pv_cP, let yp = layer.yp_Pa, pv > 0 || yp > 0 {
                let t300 = pv + yp / HydraulicsDefaults.fann35_dialToPa
                let t600 = 2.0 * pv + yp / HydraulicsDefaults.fann35_dialToPa
                if t300 > 0 && t600 > 0 {
                    theta300 = t300
                    theta600 = t600
                }
            }

            // Fall back to global fallback if no per-layer rheology
            if theta600 == nil || theta300 == nil {
                theta600 = fallbackTheta600
                theta300 = fallbackTheta300
            }

            layerDTOs.append(SwabCalculator.LayerDTO(
                rho_kgpm3: layer.rho_kgpm3,
                topMD_m: topMD,
                bottomMD_m: bottomMD,
                theta600: theta600,
                theta300: theta300
            ))
        }

        guard !layerDTOs.isEmpty else { return 0 }

        let hasRheology = layerDTOs.contains { ($0.theta600 != nil && $0.theta300 != nil) }
            || (fallbackTheta600 != nil && fallbackTheta300 != nil)
        guard hasRheology else { return 0 }

        let trajSampler = _ClosureTrajectorySampler { tvdSampler.tvd(of: $0) }
        let calculator = SwabCalculator()
        do {
            let result = try calculator.estimateFromLayersPowerLaw(
                layers: layerDTOs,
                theta600: fallbackTheta600,
                theta300: fallbackTheta300,
                hoistSpeed_mpermin: tripSpeed_m_per_s * 60.0,
                eccentricityFactor: eccentricityFactor,
                step_m: 10.0,
                geom: geom,
                traj: trajSampler,
                sabpSafety: 1.0,
                floatIsOpen: floatIsOpen
            )
            return result.totalSwab_kPa
        } catch {
            #if DEBUG
            print("[TripInSurge] Calculation error: \(error.localizedDescription)")
            #endif
            return 0
        }
    }

    /// TrajectorySampler wrapper for closure-based TVD lookup
    private struct _ClosureTrajectorySampler: TrajectorySampler {
        let tvdOfMd: (Double) -> Double
        func TVDofMD(_ md: Double) -> Double { tvdOfMd(md) }
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

        var cumulativeFill: Double = input.initialCumulativeFill_m3
        var cumulativeDisplacement: Double = input.initialCumulativeDisplacement_m3
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
            if input.holdSABPOpen || !isBelowTarget {
                requiredChoke = 0
            } else {
                requiredChoke = max(0, (input.targetESD_kgpm3 - ESDAtControl) * 0.00981 * controlTVD)
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

            // Surge pressure from live layer rheology
            let surgeGeom: GeometryService? = input.geom
            let surgePressure: Double
            if let geom = surgeGeom, input.tripSpeed_m_per_s > 0 {
                surgePressure = computeSurge(
                    displacedPockets: displacedPockets,
                    bitMD: bitMD,
                    tripSpeed_m_per_s: input.tripSpeed_m_per_s,
                    eccentricityFactor: input.eccentricityFactor,
                    floatIsOpen: input.floatIsOpen,
                    fallbackTheta600: input.fallbackTheta600,
                    fallbackTheta300: input.fallbackTheta300,
                    geom: geom,
                    tvdSampler: input.tvdSampler
                )
            } else {
                surgePressure = 0
            }
            let surgeECD = controlTVD > 0 ? surgePressure / (0.00981 * controlTVD) : 0
            let dynamicESD = ESDAtControl + surgeECD

            // Torque & drag (if configured)
            var tdPickup: Double? = nil
            var tdSlackOff: Double? = nil
            var tdRotating: Double? = nil
            var tdFreeHanging: Double? = nil
            var tdTorque: Double? = nil
            var tdBucklingMD: Double? = nil
            var tdStretch: Double? = nil

            if let surveys = input.tdSurveys,
               let strSegs = input.tdStringSegments,
               let holeSegs = input.tdHoleSections,
               let friction = input.tdFriction {
                // Build string fluid layers for PA buoyancy
                var strFluidLayers: [TripLayerSnapshot] = []
                if input.isFloatedCasing && bitMD > input.floatSubMD_m {
                    // Partially filled: mud from 0 to fill level, air above
                    let pipeCapPerM = Double.pi / 4.0 * input.pipeID_m * input.pipeID_m
                    let fillMD = min(cumulativeFill / pipeCapPerM, bitMD)
                    if fillMD > 1e-3 {
                        let tvdTop = input.tvdSampler.tvd(of: 0)
                        let tvdBot = input.tvdSampler.tvd(of: fillMD)
                        strFluidLayers.append(TripLayerSnapshot(
                            side: "String", topMD: 0, bottomMD: fillMD,
                            topTVD: tvdTop, bottomTVD: tvdBot,
                            rho_kgpm3: input.activeMudDensity_kgpm3,
                            deltaHydroStatic_kPa: input.activeMudDensity_kgpm3 * 0.00981 * (tvdBot - tvdTop),
                            volume_m3: 0
                        ))
                    }
                    // Air above fill level (density ≈ 0)
                    if fillMD < bitMD - 1e-3 {
                        let tvdAirTop = input.tvdSampler.tvd(of: fillMD)
                        let tvdAirBot = input.tvdSampler.tvd(of: bitMD)
                        strFluidLayers.append(TripLayerSnapshot(
                            side: "String", topMD: fillMD, bottomMD: bitMD,
                            topTVD: tvdAirTop, bottomTVD: tvdAirBot,
                            rho_kgpm3: 1.225,  // air
                            deltaHydroStatic_kPa: 1.225 * 0.00981 * (tvdAirBot - tvdAirTop),
                            volume_m3: 0
                        ))
                    }
                } else {
                    // Full string: uniform active mud density
                    let tvdTop = input.tvdSampler.tvd(of: 0)
                    let tvdBot = input.tvdSampler.tvd(of: bitMD)
                    strFluidLayers.append(TripLayerSnapshot(
                        side: "String", topMD: 0, bottomMD: bitMD,
                        topTVD: tvdTop, bottomTVD: tvdBot,
                        rho_kgpm3: input.activeMudDensity_kgpm3,
                        deltaHydroStatic_kPa: input.activeMudDensity_kgpm3 * 0.00981 * (tvdBot - tvdTop),
                        volume_m3: 0
                    ))
                }

                let multi = TorqueDragEngine.computeAllCases(
                    surveys: surveys,
                    stringSegments: strSegs,
                    holeSections: holeSegs,
                    fluidLayers: displacedPockets,
                    bitMD: bitMD,
                    friction: friction,
                    blockWeight_kN: input.tdBlockWeight_kN,
                    tvdSampler: input.tvdSampler,
                    SABP_kPa: requiredChoke,
                    floatIsOpen: input.floatIsOpen,
                    surgePressure_kPa: surgePressure,
                    aplEccentricityFactor: input.tdAplEccentricity,
                    pressureAreaBuoyancy: input.tdPressureAreaBuoyancy,
                    stringFluidLayers: strFluidLayers,
                    rpm: input.tdRPM,
                    tripSpeedCased_m_per_s: input.tdTripSpeedCased_m_per_s,
                    tripSpeedOpenHole_m_per_s: input.tdTripSpeedOpenHole_m_per_s,
                    rotationEfficiencyUp: input.tdRotationEfficiencyUp,
                    rotationEfficiencyDown: input.tdRotationEfficiencyDown,
                    sheaveLineFriction: input.tdSheaveLineFriction
                )
                tdPickup = multi.pickupHookLoad_kN
                tdSlackOff = multi.slackOffHookLoad_kN
                tdRotating = multi.rotatingHookLoad_kN
                tdFreeHanging = multi.freeHangingWeight_kN
                tdTorque = multi.surfaceTorque_kNm
                tdBucklingMD = multi.bucklingOnsetMD
                tdStretch = multi.slackOffStretch_m
            }

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
                layersPocket: displacedPockets,
                surgePressure_kPa: surgePressure,
                surgeECD_kgm3: surgeECD,
                dynamicESDAtControl_kgpm3: dynamicESD,
                pickupHookLoad_kN: tdPickup,
                slackOffHookLoad_kN: tdSlackOff,
                rotatingHookLoad_kN: tdRotating,
                freeHangingWeight_kN: tdFreeHanging,
                surfaceTorque_kNm: tdTorque,
                bucklingOnsetMD: tdBucklingMD,
                stretch_m: tdStretch
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
                isInAnnulus: layer.isInAnnulus,
                pv_cP: layer.pv_cP,
                yp_Pa: layer.yp_Pa,
                dial600: layer.dial600,
                dial300: layer.dial300
            ))
        }

        return resultLayers
    }
}
