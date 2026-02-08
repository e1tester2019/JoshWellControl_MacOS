//
//  CirculationService.swift
//  Josh Well Control for Mac
//
//  Shared circulation calculation service. Models pumping fluid DOWN the drill
//  string and UP the annulus using a volume-parcel-based dual-stack system.
//  Ported from PumpScheduleViewModel's proven parcel model.
//

import Foundation

/// Standalone circulation calculator that works with TripLayerSnapshot arrays.
/// Models the complete flow path: surface → string → bit → annulus → surface.
class CirculationService {

    // MARK: - Data Types

    struct PumpOperation: Identifiable {
        let id = UUID()
        var mudID: UUID
        var mudName: String
        var mudDensity_kgpm3: Double
        var mudColorR: Double
        var mudColorG: Double
        var mudColorB: Double
        var volume_m3: Double
    }

    struct CirculateOutStep: Identifiable {
        let id = UUID()
        let stepIndex: Int
        let volumePumped_m3: Double
        let volumePumped_bbl: Double
        let strokesAtPumpOutput: Double
        let ESDAtControl_kgpm3: Double
        let requiredSABP_kPa: Double
        let deltaSABP_kPa: Double
        let cumulativeDeltaSABP_kPa: Double
        let description: String
        /// Wellbore state snapshot at this step (annulus + open hole layers)
        var layersPocket: [TripLayerSnapshot] = []
        /// String state snapshot at this step
        var layersString: [TripLayerSnapshot] = []
    }

    struct CirculationRecord: Identifiable {
        let id = UUID()
        let timestamp: Date
        let atBitMD_m: Double
        let operations: [PumpOperation]
        let ESDBeforeAtControl_kgpm3: Double
        let ESDAfterAtControl_kgpm3: Double
        let SABPRequired_kPa: Double
    }

    struct PreviewResult {
        let schedule: [CirculateOutStep]
        let resultLayersPocket: [TripLayerSnapshot]
        let resultLayersString: [TripLayerSnapshot]
        let ESDAtControl: Double
        let requiredSABP: Double
    }

    // MARK: - Volume Parcel

    /// A discrete volume of fluid with density and color. UI-framework-independent.
    struct VolumeParcel {
        var volume_m3: Double
        var colorR: Double
        var colorG: Double
        var colorB: Double
        var colorA: Double
        var rho_kgpm3: Double
        var mudID: UUID?
    }

    // MARK: - ESD Calculation

    /// Calculate ESD from layers at a given MD using a TvdSampler
    static func calculateESDFromLayers(
        layers: [TripLayerSnapshot],
        atDepthMD: Double,
        tvdSampler: TvdSampler
    ) -> Double {
        let depthTVD = tvdSampler.tvd(of: atDepthMD)
        guard depthTVD > 0 else { return 0 }

        var totalPressure_kPa: Double = 0

        for layer in layers {
            let layerTop = layer.topMD
            let layerBottom = min(layer.bottomMD, atDepthMD)

            if layerBottom > layerTop && layerTop < atDepthMD {
                let topTVD = tvdSampler.tvd(of: layerTop)
                let bottomTVD = tvdSampler.tvd(of: layerBottom)
                let tvdInterval = bottomTVD - topTVD

                if tvdInterval > 0 {
                    totalPressure_kPa += layer.rho_kgpm3 * 0.00981 * tvdInterval
                }
            }
        }

        return totalPressure_kPa / (0.00981 * depthTVD)
    }

    // MARK: - Parcel Stack Operations

    private static func totalVolume(_ parcels: [VolumeParcel]) -> Double {
        parcels.reduce(0.0) { $0 + max(0.0, $1.volume_m3) }
    }

    /// Push a parcel into the top of the string (surface) and compute overflow from the bottom (bit).
    /// `stringParcels` is ordered shallow (index 0) → deep (last).
    /// `expelled` is appended in the order it exits the bit.
    static func pushToTopAndOverflow(
        stringParcels: inout [VolumeParcel],
        add: VolumeParcel,
        capacity_m3: Double,
        expelled: inout [VolumeParcel]
    ) {
        let addV = max(0.0, add.volume_m3)
        guard addV > 1e-12 else { return }

        stringParcels.insert(VolumeParcel(
            volume_m3: addV, colorR: add.colorR, colorG: add.colorG,
            colorB: add.colorB, colorA: add.colorA, rho_kgpm3: add.rho_kgpm3, mudID: add.mudID
        ), at: 0)

        var overflow = totalVolume(stringParcels) - max(0.0, capacity_m3)
        while overflow > 1e-9, let last = stringParcels.last {
            stringParcels.removeLast()
            let v = max(0.0, last.volume_m3)
            if v <= overflow + 1e-9 {
                expelled.append(last)
                overflow -= v
            } else {
                expelled.append(VolumeParcel(
                    volume_m3: overflow, colorR: last.colorR, colorG: last.colorG,
                    colorB: last.colorB, colorA: last.colorA, rho_kgpm3: last.rho_kgpm3, mudID: last.mudID
                ))
                stringParcels.append(VolumeParcel(
                    volume_m3: v - overflow, colorR: last.colorR, colorG: last.colorG,
                    colorB: last.colorB, colorA: last.colorA, rho_kgpm3: last.rho_kgpm3, mudID: last.mudID
                ))
                overflow = 0
            }
        }
    }

    /// Push a parcel into the bottom of the annulus (bit) and compute overflow out the top (surface).
    /// `annulusParcels` is ordered deep (index 0, at bit) → shallow (last, at surface).
    /// `overflowAtSurface` is appended in the order it would leave the surface.
    static func pushToBottomAndOverflowTop(
        annulusParcels: inout [VolumeParcel],
        add: VolumeParcel,
        capacity_m3: Double,
        overflowAtSurface: inout [VolumeParcel]
    ) {
        let addV = max(0.0, add.volume_m3)
        guard addV > 1e-12 else { return }

        annulusParcels.insert(VolumeParcel(
            volume_m3: addV, colorR: add.colorR, colorG: add.colorG,
            colorB: add.colorB, colorA: add.colorA, rho_kgpm3: add.rho_kgpm3, mudID: add.mudID
        ), at: 0)

        var overflow = totalVolume(annulusParcels) - max(0.0, capacity_m3)
        while overflow > 1e-9, let last = annulusParcels.last {
            annulusParcels.removeLast()
            let v = max(0.0, last.volume_m3)
            if v <= overflow + 1e-9 {
                overflowAtSurface.append(last)
                overflow -= v
            } else {
                overflowAtSurface.append(VolumeParcel(
                    volume_m3: overflow, colorR: last.colorR, colorG: last.colorG,
                    colorB: last.colorB, colorA: last.colorA, rho_kgpm3: last.rho_kgpm3, mudID: last.mudID
                ))
                annulusParcels.append(VolumeParcel(
                    volume_m3: v - overflow, colorR: last.colorR, colorG: last.colorG,
                    colorB: last.colorB, colorA: last.colorA, rho_kgpm3: last.rho_kgpm3, mudID: last.mudID
                ))
                overflow = 0
            }
        }
    }

    // MARK: - Layer ↔ Parcel Conversion

    /// Convert TripLayerSnapshot layers into a VolumeParcel array for the annulus.
    /// Returns parcels ordered deep→shallow (bit at index 0, surface at last).
    static func annulusParcelsFromLayers(
        _ layers: [TripLayerSnapshot],
        bitMD: Double,
        geom: ProjectGeometryService
    ) -> [VolumeParcel] {
        let sorted = layers.filter { $0.bottomMD <= bitMD + 1e-6 }
            .sorted { $0.topMD < $1.topMD }
        // Build parcels deepest first (reverse order)
        var parcels: [VolumeParcel] = []
        for layer in sorted.reversed() {
            let top = max(0, layer.topMD)
            let bot = min(layer.bottomMD, bitMD)
            guard bot > top + 1e-9 else { continue }
            let vol = geom.volumeInAnnulus_m3(top, bot)
            guard vol > 1e-12 else { continue }
            parcels.append(VolumeParcel(
                volume_m3: vol,
                colorR: layer.colorR ?? 0.5, colorG: layer.colorG ?? 0.5,
                colorB: layer.colorB ?? 0.5, colorA: layer.colorA ?? 1.0,
                rho_kgpm3: layer.rho_kgpm3, mudID: nil
            ))
        }
        return parcels
    }

    /// Convert TripLayerSnapshot layers into a VolumeParcel array for the string.
    /// Returns parcels ordered shallow→deep (surface at index 0, bit at last).
    static func stringParcelsFromLayers(
        _ layers: [TripLayerSnapshot],
        bitMD: Double,
        geom: ProjectGeometryService
    ) -> [VolumeParcel] {
        let sorted = layers.filter { $0.bottomMD <= bitMD + 1e-6 }
            .sorted { $0.topMD < $1.topMD }
        var parcels: [VolumeParcel] = []
        for layer in sorted {
            let top = max(0, layer.topMD)
            let bot = min(layer.bottomMD, bitMD)
            guard bot > top + 1e-9 else { continue }
            let vol = geom.volumeInString_m3(top, bot)
            guard vol > 1e-12 else { continue }
            parcels.append(VolumeParcel(
                volume_m3: vol,
                colorR: layer.colorR ?? 0.5, colorG: layer.colorG ?? 0.5,
                colorB: layer.colorB ?? 0.5, colorA: layer.colorA ?? 1.0,
                rho_kgpm3: layer.rho_kgpm3, mudID: nil
            ))
        }
        return parcels
    }

    /// Convert a deep→shallow annulus volume parcel stack into TripLayerSnapshot layers from bit upward.
    static func snapshotsFromAnnulusParcels(
        _ parcels: [VolumeParcel],
        bitMD: Double,
        geom: ProjectGeometryService,
        tvdSampler: TvdSampler
    ) -> [TripLayerSnapshot] {
        var snapshots: [TripLayerSnapshot] = []
        var usedFromBottom: Double = 0.0

        for p in parcels {
            let v = max(0.0, p.volume_m3)
            guard v > 1e-12 else { continue }

            let startMD = max(0, bitMD - usedFromBottom)
            let L = lengthForAnnulusParcelVolumeFromBottom(
                volume: v, bitMD: bitMD, usedFromBottom: usedFromBottom, geom: geom
            )
            guard L > 1e-12 else { continue }

            let topMD = max(0.0, bitMD - usedFromBottom - L)
            let botMD = max(0.0, bitMD - usedFromBottom)

            if botMD > topMD + 1e-9 {
                snapshots.append(TripLayerSnapshot(
                    side: "annulus",
                    topMD: topMD,
                    bottomMD: botMD,
                    topTVD: tvdSampler.tvd(of: topMD),
                    bottomTVD: tvdSampler.tvd(of: botMD),
                    rho_kgpm3: p.rho_kgpm3,
                    deltaHydroStatic_kPa: 0,
                    volume_m3: v,
                    colorR: p.colorR,
                    colorG: p.colorG,
                    colorB: p.colorB,
                    colorA: p.colorA,
                    isInAnnulus: true
                ))
                usedFromBottom += L
            }
            if usedFromBottom >= bitMD - 1e-9 { break }
        }

        return snapshots.sorted { $0.topMD < $1.topMD }
    }

    /// Convert a shallow→deep string volume parcel stack into TripLayerSnapshot layers from surface downward.
    static func snapshotsFromStringParcels(
        _ parcels: [VolumeParcel],
        bitMD: Double,
        geom: ProjectGeometryService,
        tvdSampler: TvdSampler
    ) -> [TripLayerSnapshot] {
        var snapshots: [TripLayerSnapshot] = []
        var currentTop: Double = 0.0

        for p in parcels {
            let v = max(0.0, p.volume_m3)
            guard v > 1e-12 else { continue }

            let L = geom.lengthForStringVolume_m(currentTop, v)
            guard L > 1e-12 else { continue }

            let bottom = min(currentTop + L, bitMD)
            if bottom > currentTop + 1e-9 {
                snapshots.append(TripLayerSnapshot(
                    side: "string",
                    topMD: currentTop,
                    bottomMD: bottom,
                    topTVD: tvdSampler.tvd(of: currentTop),
                    bottomTVD: tvdSampler.tvd(of: bottom),
                    rho_kgpm3: p.rho_kgpm3,
                    deltaHydroStatic_kPa: 0,
                    volume_m3: v,
                    colorR: p.colorR,
                    colorG: p.colorG,
                    colorB: p.colorB,
                    colorA: p.colorA
                ))
                currentTop = bottom
            }
            if currentTop >= bitMD - 1e-9 { break }
        }

        return snapshots
    }

    /// Binary search for the annulus length (from bit upward) that holds a given volume.
    private static func lengthForAnnulusParcelVolumeFromBottom(
        volume: Double,
        bitMD: Double,
        usedFromBottom: Double,
        geom: ProjectGeometryService
    ) -> Double {
        guard volume > 1e-12 else { return 0 }
        let startMD = max(0, bitMD - usedFromBottom)
        var lo: Double = 0
        var hi: Double = startMD
        let tol = 1e-6
        var iter = 0
        let maxIter = 50

        while (hi - lo) > tol, iter < maxIter {
            iter += 1
            let mid = 0.5 * (lo + hi)
            let topMD = max(0, startMD - mid)
            let botMD = startMD
            let vol = geom.volumeInAnnulus_m3(topMD, botMD)
            if vol < volume {
                lo = mid
            } else {
                hi = mid
            }
        }
        return 0.5 * (lo + hi)
    }

    // MARK: - Dual-Stack Preview

    /// Calculate the effect of pumping operations on the wellbore state.
    /// Models fluid flowing DOWN the drill string, exiting at the bit, then UP the annulus.
    /// Open hole (below bit) is unchanged.
    static func previewPumpQueue(
        pocketLayers: [TripLayerSnapshot],
        stringLayers: [TripLayerSnapshot],
        bitMD: Double,
        controlMD: Double,
        targetESD_kgpm3: Double,
        geom: ProjectGeometryService,
        tvdSampler: TvdSampler,
        pumpQueue: [PumpOperation],
        pumpOutput_m3perStroke: Double = 0.01,
        activeMudDensity_kgpm3: Double = 1200
    ) -> PreviewResult {
        guard !pumpQueue.isEmpty else {
            return PreviewResult(
                schedule: [], resultLayersPocket: pocketLayers,
                resultLayersString: stringLayers, ESDAtControl: 0, requiredSABP: 0
            )
        }

        let controlTVD = tvdSampler.tvd(of: controlMD)
        guard controlTVD > 0 else {
            return PreviewResult(
                schedule: [], resultLayersPocket: pocketLayers,
                resultLayersString: stringLayers, ESDAtControl: 0, requiredSABP: 0
            )
        }

        let allLayers = pocketLayers.sorted { $0.topMD < $1.topMD }
        guard !allLayers.isEmpty else {
            return PreviewResult(
                schedule: [], resultLayersPocket: pocketLayers,
                resultLayersString: stringLayers, ESDAtControl: 0, requiredSABP: 0
            )
        }

        // Separate pocket layers into annulus (above bit) and open hole (below bit)
        var annulusLayers: [TripLayerSnapshot] = []
        var openHoleLayers: [TripLayerSnapshot] = []

        for layer in allLayers {
            if layer.bottomMD <= bitMD {
                annulusLayers.append(layer)
            } else if layer.topMD >= bitMD {
                openHoleLayers.append(layer)
            } else {
                // Layer spans the bit - split it
                if layer.topMD < bitMD {
                    annulusLayers.append(TripLayerSnapshot(
                        side: layer.side, topMD: layer.topMD, bottomMD: bitMD,
                        topTVD: tvdSampler.tvd(of: layer.topMD),
                        bottomTVD: tvdSampler.tvd(of: bitMD),
                        rho_kgpm3: layer.rho_kgpm3, deltaHydroStatic_kPa: layer.deltaHydroStatic_kPa,
                        volume_m3: 0, colorR: layer.colorR ?? 0.5, colorG: layer.colorG ?? 0.5,
                        colorB: layer.colorB ?? 0.5, colorA: layer.colorA ?? 1.0
                    ))
                }
                openHoleLayers.append(TripLayerSnapshot(
                    side: layer.side, topMD: bitMD, bottomMD: layer.bottomMD,
                    topTVD: tvdSampler.tvd(of: bitMD),
                    bottomTVD: tvdSampler.tvd(of: layer.bottomMD),
                    rho_kgpm3: layer.rho_kgpm3, deltaHydroStatic_kPa: layer.deltaHydroStatic_kPa,
                    volume_m3: 0, colorR: layer.colorR ?? 0.5, colorG: layer.colorG ?? 0.5,
                    colorB: layer.colorB ?? 0.5, colorA: layer.colorA ?? 1.0
                ))
            }
        }

        // Initialize parcel stacks from existing layers
        let stringCapacity = geom.volumeInString_m3(0, bitMD)
        let annulusCapacity = geom.volumeInAnnulus_m3(0, bitMD)

        // String parcels (shallow→deep)
        var stringParcels: [VolumeParcel]
        if !stringLayers.isEmpty {
            stringParcels = stringParcelsFromLayers(stringLayers, bitMD: bitMD, geom: geom)
        } else {
            // No string layers provided - fill with active mud density
            stringParcels = [VolumeParcel(
                volume_m3: max(0, stringCapacity),
                colorR: 0.5, colorG: 0.5, colorB: 0.5, colorA: 0.35,
                rho_kgpm3: activeMudDensity_kgpm3, mudID: nil
            )]
        }
        // Ensure string parcels fill the capacity
        let currentStringVol = totalVolume(stringParcels)
        if currentStringVol < stringCapacity - 1e-9 {
            stringParcels.append(VolumeParcel(
                volume_m3: stringCapacity - currentStringVol,
                colorR: 0.5, colorG: 0.5, colorB: 0.5, colorA: 0.35,
                rho_kgpm3: activeMudDensity_kgpm3, mudID: nil
            ))
        }

        // Annulus parcels (deep→shallow, bit at index 0)
        var annulusParcels: [VolumeParcel]
        if !annulusLayers.isEmpty {
            annulusParcels = annulusParcelsFromLayers(annulusLayers, bitMD: bitMD, geom: geom)
        } else {
            annulusParcels = [VolumeParcel(
                volume_m3: max(0, annulusCapacity),
                colorR: 0.5, colorG: 0.5, colorB: 0.5, colorA: 0.35,
                rho_kgpm3: activeMudDensity_kgpm3, mudID: nil
            )]
        }
        // Ensure annulus parcels fill the capacity
        let currentAnnulusVol = totalVolume(annulusParcels)
        if currentAnnulusVol < annulusCapacity - 1e-9 {
            annulusParcels.append(VolumeParcel(
                volume_m3: annulusCapacity - currentAnnulusVol,
                colorR: 0.5, colorG: 0.5, colorB: 0.5, colorA: 0.35,
                rho_kgpm3: activeMudDensity_kgpm3, mudID: nil
            ))
        }

        var overflowAtSurface: [VolumeParcel] = []

        // Helper: convert current annulus parcels + open hole to pocket layer snapshots for ESD
        func currentPocketLayers() -> [TripLayerSnapshot] {
            let annulusSnapshots = snapshotsFromAnnulusParcels(
                annulusParcels, bitMD: bitMD, geom: geom, tvdSampler: tvdSampler
            )
            return (annulusSnapshots + openHoleLayers).sorted { $0.topMD < $1.topMD }
        }

        // Initial ESD
        let initialESD = calculateESDFromLayers(
            layers: currentPocketLayers(),
            atDepthMD: controlMD,
            tvdSampler: tvdSampler
        )
        let initialSABP = max(0, (targetESD_kgpm3 - initialESD) * 0.00981 * controlTVD)

        var schedule: [CirculateOutStep] = []
        var cumulativeVolume: Double = 0
        var previousSABP = initialSABP
        var stepIndex = 0

        // Helper: snapshot current string parcels as layers
        func currentStringLayers() -> [TripLayerSnapshot] {
            snapshotsFromStringParcels(stringParcels, bitMD: bitMD, geom: geom, tvdSampler: tvdSampler)
        }

        // Add initial state
        schedule.append(CirculateOutStep(
            stepIndex: stepIndex, volumePumped_m3: 0, volumePumped_bbl: 0,
            strokesAtPumpOutput: 0, ESDAtControl_kgpm3: initialESD,
            requiredSABP_kPa: initialSABP, deltaSABP_kPa: 0,
            cumulativeDeltaSABP_kPa: 0,
            description: "Initial state at \(Int(bitMD))m",
            layersPocket: currentPocketLayers(),
            layersString: currentStringLayers()
        ))
        stepIndex += 1

        // Process each pump operation
        for operation in pumpQueue {
            let stepVolume = 0.5  // Resolution for schedule (m³ per step)
            var operationVolumePumped: Double = 0

            while operationVolumePumped < operation.volume_m3 {
                let thisStepVolume = min(stepVolume, operation.volume_m3 - operationVolumePumped)
                operationVolumePumped += thisStepVolume
                cumulativeVolume += thisStepVolume

                // 1. Push pumped fluid into STRING at surface
                var expelledAtBit: [VolumeParcel] = []
                pushToTopAndOverflow(
                    stringParcels: &stringParcels,
                    add: VolumeParcel(
                        volume_m3: thisStepVolume,
                        colorR: operation.mudColorR, colorG: operation.mudColorG,
                        colorB: operation.mudColorB, colorA: 1.0,
                        rho_kgpm3: operation.mudDensity_kgpm3, mudID: operation.mudID
                    ),
                    capacity_m3: stringCapacity,
                    expelled: &expelledAtBit
                )

                // 2. String overflow exits at bit → enters ANNULUS from bottom
                var displacedDescription = ""
                for expelled in expelledAtBit {
                    var stepOverflow: [VolumeParcel] = []
                    pushToBottomAndOverflowTop(
                        annulusParcels: &annulusParcels,
                        add: expelled,
                        capacity_m3: annulusCapacity,
                        overflowAtSurface: &stepOverflow
                    )
                    for overflow in stepOverflow {
                        overflowAtSurface.append(overflow)
                        if displacedDescription.isEmpty {
                            displacedDescription = "Out: \(Int(overflow.rho_kgpm3)) kg/m\u{00B3}"
                        }
                    }
                }

                // 3. Calculate new ESD from updated annulus + open hole
                let newESD = calculateESDFromLayers(
                    layers: currentPocketLayers(),
                    atDepthMD: controlMD,
                    tvdSampler: tvdSampler
                )
                let newSABP = max(0, (targetESD_kgpm3 - newESD) * 0.00981 * controlTVD)
                let deltaSABP = newSABP - previousSABP
                let cumulativeDelta = newSABP - initialSABP

                // Log every step for smooth visual scrubbing
                let isEndOfOperation = abs(operationVolumePumped - operation.volume_m3) < 0.01

                let description: String
                if isEndOfOperation {
                    description = "End: \(operation.mudName) (\(String(format: "%.1f", operation.volume_m3))m\u{00B3})"
                } else if !displacedDescription.isEmpty {
                    description = displacedDescription
                } else {
                    description = "Pumping \(operation.mudName)..."
                }

                schedule.append(CirculateOutStep(
                    stepIndex: stepIndex,
                    volumePumped_m3: cumulativeVolume,
                    volumePumped_bbl: cumulativeVolume * 6.28981,
                    strokesAtPumpOutput: cumulativeVolume / pumpOutput_m3perStroke,
                    ESDAtControl_kgpm3: newESD,
                    requiredSABP_kPa: newSABP,
                    deltaSABP_kPa: deltaSABP,
                    cumulativeDeltaSABP_kPa: cumulativeDelta,
                    description: description,
                    layersPocket: currentPocketLayers(),
                    layersString: currentStringLayers()
                ))

                stepIndex += 1
                previousSABP = newSABP
            }
        }

        // Build final results
        let finalPocketLayers = currentPocketLayers()
        let finalStringLayers = snapshotsFromStringParcels(
            stringParcels, bitMD: bitMD, geom: geom, tvdSampler: tvdSampler
        )
        let finalESD = schedule.last?.ESDAtControl_kgpm3 ?? initialESD
        let finalSABP = schedule.last?.requiredSABP_kPa ?? initialSABP

        return PreviewResult(
            schedule: schedule,
            resultLayersPocket: finalPocketLayers,
            resultLayersString: finalStringLayers,
            ESDAtControl: finalESD,
            requiredSABP: finalSABP
        )
    }
}
