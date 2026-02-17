//
//  NumericalTripModelService.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-07.
//

import Foundation


final class NumericalTripModel: @unchecked Sendable {
    static let g = HydraulicsDefaults.gravity_mps2
    static let eps = HydraulicsDefaults.epsilon
    static let rhoAir = HydraulicsDefaults.rhoAir_kgm3

    enum Side { case string, annulus }

    struct ColorRGBA: Equatable, Codable, Sendable {
        var r: Double
        var g: Double
        var b: Double
        var a: Double
        static let clear = ColorRGBA(r: 0, g: 0, b: 0, a: 0)
    }

    struct Layer: Sendable {
        var rho: Double
        var topMD: Double
        var bottomMD: Double
        var color: ColorRGBA? = nil
        var pv_cP: Double = 0
        var yp_Pa: Double = 0

        /// Extract fluid properties as a FluidIdentity
        var fluid: FluidIdentity {
            FluidIdentity(density_kgm3: rho, color: color, pv_cP: pv_cP, yp_Pa: yp_Pa)
        }
    }

    /// Sendable snapshot of fluid layer data for crossing concurrency boundaries
    struct FinalLayerSnapshot: Sendable {
        let topMD_m: Double
        let bottomMD_m: Double
        let density_kgm3: Double
        let colorR: Double
        let colorG: Double
        let colorB: Double
        let colorA: Double
        // Mud rheology for swab calculation
        let mudDial600: Double?
        let mudDial300: Double?
        let mudK_annulus: Double?
        let mudN_annulus: Double?
        let mudK_powerLaw: Double?
        let mudN_powerLaw: Double?

        init(from layer: FinalFluidLayer) {
            self.topMD_m = layer.topMD_m
            self.bottomMD_m = layer.bottomMD_m
            self.density_kgm3 = layer.density_kgm3
            self.colorR = layer.colorR
            self.colorG = layer.colorG
            self.colorB = layer.colorB
            self.colorA = layer.colorA
            self.mudDial600 = layer.mud?.dial600
            self.mudDial300 = layer.mud?.dial300
            self.mudK_annulus = layer.mud?.K_annulus
            self.mudN_annulus = layer.mud?.n_annulus
            self.mudK_powerLaw = layer.mud?.k_powerLaw_Pa_s_n
            self.mudN_powerLaw = layer.mud?.n_powerLaw
        }
    }

    /// All project data needed for simulation, in sendable form
    struct ProjectSnapshot: Sendable {
        let annulusLayers: [FinalLayerSnapshot]
        let stringLayers: [FinalLayerSnapshot]

        init(from project: ProjectState) {
            self.annulusLayers = project.finalAnnulusLayersSorted.map { FinalLayerSnapshot(from: $0) }
            self.stringLayers = project.finalStringLayersSorted.map { FinalLayerSnapshot(from: $0) }
        }
    }

    // MARK: - StackOps (Swift port)
    enum StackOps {
        /// Split a layer at an MD boundary if it falls strictly inside a layer span.
        static func splitAt(_ stack: NumericalTripModel.Stack, _ md: Double) {
            guard !stack.layers.isEmpty else { return }
            let eps = NumericalTripModel.eps
            for i in 0..<stack.layers.count {
                let L = stack.layers[i]
                if md > L.topMD + eps && md < L.bottomMD - eps {
                    let right = NumericalTripModel.Layer(rho: L.rho, topMD: md, bottomMD: L.bottomMD, color: L.color, pv_cP: L.pv_cP, yp_Pa: L.yp_Pa)
                    stack.layers[i].bottomMD = md
                    stack.layers.insert(right, at: i + 1)
                    return
                }
            }
        }

        /// Paint (set density) for all sublayers fully contained within [fromMD, toMD].
        static func paintInterval(_ stack: NumericalTripModel.Stack, _ fromMD: Double, _ toMD: Double, _ rho: Double) {
            paintInterval(stack, fromMD, toMD, rho, color: nil, pv_cP: 0, yp_Pa: 0)
        }

        /// Color-aware variant; when `color` is provided, painted sublayers also carry a composition color.
        static func paintInterval(_ stack: NumericalTripModel.Stack, _ fromMD: Double, _ toMD: Double, _ rho: Double, color: NumericalTripModel.ColorRGBA?, pv_cP: Double = 0, yp_Pa: Double = 0) {
            let a = fromMD, b = toMD
            if b <= a { return }
            splitAt(stack, a)
            splitAt(stack, b)
            for i in 0..<stack.layers.count {
                if stack.layers[i].topMD >= a && stack.layers[i].bottomMD <= b {
                    stack.layers[i].rho = rho
                    stack.layers[i].color = color
                    stack.layers[i].pv_cP = pv_cP
                    stack.layers[i].yp_Pa = yp_Pa
                }
            }
            stack.ensureInvariants(bitMD: stack.layers.last?.bottomMD ?? b)
        }
    }

    final class Stack {
        let side: Side
        let geom: GeometryService
        let tvdOfMd: (Double) -> Double
        var layers: [Layer] = [] // ordered top -> bottom

        init(side: Side, geom: GeometryService, tvdOfMd: @escaping (Double)->Double) {
            self.side = side
            self.geom = geom
            self.tvdOfMd = tvdOfMd
        }

        func seedUniform(rho: Double, topMD: Double, bottomMD: Double) {
            layers = [Layer(rho: rho, topMD: min(topMD, bottomMD), bottomMD: max(topMD, bottomMD), color: nil)]
        }

        func adjustBit(to newBitMD: Double) {
            guard !layers.isEmpty else { return }
            let totalLen = layers.reduce(0.0) { $0 + ($1.bottomMD - $1.topMD) }
            let newTop = max(0.0, newBitMD - totalLen)
            var cursor = newTop
            for i in layers.indices {
                let len = layers[i].bottomMD - layers[i].topMD
                layers[i].topMD = cursor
                cursor += len
                layers[i].bottomMD = cursor
            }
        }

        func translateAllLayers(by deltaMD: Double, bitMD: Double) {
            guard !layers.isEmpty, abs(deltaMD) > 1e-12 else { return }
            for i in layers.indices {
                layers[i].topMD += deltaMD
                layers[i].bottomMD += deltaMD
            }
            ensureInvariants(bitMD: bitMD)
        }

        func addBackfillFromSurface(rho: Double, volume_m3: Double, bitMD: Double, color: ColorRGBA? = nil, pv_cP: Double = 0, yp_Pa: Double = 0) {
            guard volume_m3 > 1e-12 else { return }
            let len = geom.lengthForAnnulusVolume_m(0.0, volume_m3)
            guard len > 1e-12 else { return }

            // Check if we can merge with existing top layer (same density and color)
            let canMerge = !layers.isEmpty
                && abs(layers[0].topMD) < 1e-9
                && abs(layers[0].rho - rho) < 1e-6
                && layers[0].color == color

            if !canMerge {
                layers.insert(Layer(rho: rho, topMD: 0, bottomMD: 0, color: color, pv_cP: pv_cP, yp_Pa: yp_Pa), at: 0)
            }
            layers[0].bottomMD += len
            for i in 1..<layers.count {
                layers[i].topMD += len
                layers[i].bottomMD += len
            }
            ensureInvariants(bitMD: bitMD)
        }

        func pressureAtBit_kPa(sabp_kPa: Double, bitMD: Double) -> Double {
            var P = (side == .annulus) ? sabp_kPa : 0.0
            for L in layers {
                let a = max(0.0, min(L.topMD, bitMD))
                let b = max(0.0, min(L.bottomMD, bitMD))
                guard b > a else { continue }
                let dH = max(0.0, tvdOfMd(b) - tvdOfMd(a))
                P += L.rho * NumericalTripModel.g * dH / 1000.0
            }
            return P
        }

        func ensureInvariants(bitMD: Double) {
            guard !layers.isEmpty else { return }
            for i in layers.indices {
                layers[i].topMD = max(0.0, min(layers[i].topMD, bitMD))
                layers[i].bottomMD = max(0.0, min(layers[i].bottomMD, bitMD))
            }
            layers.removeAll { ($0.bottomMD - $0.topMD) <= 1e-12 }
            layers.sort { $0.topMD < $1.topMD }

            // Snap contiguity only when we still have elements
            guard !layers.isEmpty else { return }
            if abs(layers[0].topMD) > 1e-9 { layers[0].topMD = 0 }
            if layers.count >= 2 {
                for i in 1..<layers.count { layers[i].topMD = layers[i-1].bottomMD }
            }

            // Merge identical-ρ neighbors
            var i = 1
            while i < layers.count {
                if abs(layers[i].rho - layers[i-1].rho) < 1e-6 && abs(layers[i].topMD - layers[i-1].bottomMD) < 1e-9 {
                    layers[i-1].bottomMD = layers[i].bottomMD
                    layers.remove(at: i)
                } else {
                    i += 1
                }
            }
        }

        // STRING only
        func addAirFromSurface(volume_m3: Double, bitMD: Double) {
            precondition(side == .string, "Air fill is for STRING only")
            guard volume_m3 > 1e-12 else { return }
            let addLen = geom.lengthForStringVolume_m(0.0, volume_m3)
            guard addLen > 1e-12 else { return }
            if layers.isEmpty || abs(layers[0].topMD) > 1e-9 || abs(layers[0].rho - NumericalTripModel.rhoAir) > 1e-6 {
                layers.insert(Layer(rho: NumericalTripModel.rhoAir, topMD: 0, bottomMD: 0, color: nil), at: 0)
            }
            layers[0].bottomMD += addLen
            for i in 1..<layers.count {
                layers[i].topMD += addLen
                layers[i].bottomMD += addLen
            }
            ensureInvariants(bitMD: bitMD)
        }

        // ANNULUS only
        @discardableResult
        func injectParcelAtBit_PushUphole(rho: Double, volume_m3: Double, bitMD: Double) -> Double {
            precondition(side == .annulus, "Parcel inject applies to ANNULUS only")
            guard volume_m3 > 1e-12 else { return 0 }
            let len = geom.lengthForAnnulusVolume_m(0.0, volume_m3)
            guard len > 1e-12 else { return 0 }
            for i in layers.indices { // shift uphole (toward surface)
                layers[i].topMD = max(0.0, layers[i].topMD - len)
                layers[i].bottomMD = max(0.0, layers[i].bottomMD - len)
            }
            let newTop = max(0.0, bitMD - len)
            let newBot = bitMD
            if let last = layers.last, abs(last.bottomMD - newTop) < 1e-9, abs(last.rho - rho) < 1e-6 {
                var l = last
                l.bottomMD = newBot
                layers[layers.count-1] = l
            } else {
                layers.append(Layer(rho: rho, topMD: newTop, bottomMD: newBot, color: nil))
            }
            ensureInvariants(bitMD: bitMD)
            let lenClamped = min(len, bitMD)
            let pitGain = geom.volumeInAnnulus_m3(0.0, lenClamped)
            return min(volume_m3, pitGain)
        }
    }

    struct LayerRow: Identifiable {
        let id = UUID()
        var side: String
        var topMD: Double
        var bottomMD: Double
        var topTVD: Double
        var bottomTVD: Double
        var rho_kgpm3: Double
        var deltaHydroStatic_kPa: Double
        var volume_m3: Double
        var color: ColorRGBA? = nil
        var pv_cP: Double = 0
        var yp_Pa: Double = 0

        /// Extract fluid properties as a FluidIdentity
        var fluid: FluidIdentity {
            FluidIdentity(density_kgm3: rho_kgpm3, color: color, pv_cP: pv_cP, yp_Pa: yp_Pa)
        }
    }

    struct Totals {
        var count: Int
        var tvd_m: Double
        var deltaP_kPa: Double
    }

    struct TripStep: Identifiable {
        let id = UUID()
        var bitMD_m: Double
        var bitTVD_m: Double
        var SABP_kPa: Double
        var SABP_kPa_Raw: Double
        var ESDatTD_kgpm3: Double
        var ESDatBit_kgpm3: Double
        var backfillRemaining_m3: Double
        var swabDropToBit_kPa: Double
        var SABP_Dynamic_kPa: Double

        // Volume tracking
        var floatState: String = "CLOSED"           // "OPEN" or "CLOSED"
        var stepBackfill_m3: Double = 0             // Volume pumped from surface this step (tank decreases)
        var cumulativeBackfill_m3: Double = 0       // Total volume pumped from surface so far
        var expectedFillIfClosed_m3: Double = 0     // Expected fill if float closed (pipe OD)
        var expectedFillIfOpen_m3: Double = 0       // Expected fill if float open (steel only)
        var slugContribution_m3: Double = 0         // Volume from string that filled annulus (not from surface)
        var cumulativeSlugContribution_m3: Double = 0  // Cumulative slug contribution
        var pitGain_m3: Double = 0                  // Volume overflowed at surface this step (tank increases)
        var cumulativePitGain_m3: Double = 0        // Total pit gain so far
        var surfaceTankDelta_m3: Double = 0         // Net tank change this step (pitGain - backfill, + = gain)
        var cumulativeSurfaceTankDelta_m3: Double = 0  // Cumulative net tank change

        // Snapshots for UI/debug
        var layersPocket: [LayerRow]
        var layersAnnulus: [LayerRow]
        var layersString: [LayerRow]
        var totalsPocket: Totals
        var totalsAnnulus: Totals
        var totalsString: Totals
    }

    struct TripInput: @unchecked Sendable {
        var tvdOfMd: @Sendable (Double)->Double
        var shoeTVD_m: Double
        var startBitMD_m: Double
        var endMD_m: Double
        var crackFloat_kPa: Double
        var step_m: Double = 10.0
        var baseMudDensity_kgpm3: Double
        var backfillDensity_kgpm3: Double
        var backfillColor: ColorRGBA? = nil
        var baseMudColor: ColorRGBA? = nil
        var backfillPV_cP: Double = 0
        var backfillYP_Pa: Double = 0
        var baseMudPV_cP: Double = 0
        var baseMudYP_Pa: Double = 0
        var fixedBackfillVolume_m3: Double = 0
        var switchToBaseAfterFixed: Bool = true
        var targetESDAtTD_kgpm3: Double
        var initialSABP_kPa: Double = 0
        var holdSABPOpen: Bool = false
        // Swab parameters
        var tripSpeed_m_per_s: Double = 0.5        // Hoist speed (m/s), default 0.5 m/s = 30 m/min
        var eccentricityFactor: Double = 1.0       // Pipe eccentricity factor (1.0 = concentric)
        var swabSafetyFactor = HydraulicsDefaults.swabSafetyFactor
        // Fallback rheology if layers don't have mud references
        var fallbackTheta600: Double? = nil
        var fallbackTheta300: Double? = nil
        // Observed pit gain calibration
        // When set, uses this value instead of calculating equalization from pressure
        var observedInitialPitGain_m3: Double? = nil
        // Super Simulation: custom initial layer state
        // When set, seeds stacks from these layers instead of ProjectSnapshot.
        // This enables chaining operations (e.g., trip out after circulation).
        var initialAnnulusLayers: [TripLayerSnapshot]? = nil
        var initialStringLayers: [TripLayerSnapshot]? = nil
        var initialPocketLayers: [TripLayerSnapshot]? = nil
    }

    /// Progress reporting for long-running simulations
    struct TripProgress {
        enum Phase {
            case initializing
            case initialEqualization
            case tripping
            case stepEqualization
            case complete
        }

        var phase: Phase
        var currentMD_m: Double
        var startMD_m: Double
        var endMD_m: Double
        var floatState: String  // "OPEN" or "CLOSED"
        var equalizationIterations: Int
        var message: String

        /// Progress as a value from 0.0 to 1.0
        var progress: Double {
            guard startMD_m > endMD_m else { return 1.0 }
            let totalDistance = startMD_m - endMD_m
            let traveled = startMD_m - currentMD_m
            return min(1.0, max(0.0, traveled / totalDistance))
        }

        /// Progress as a percentage string
        var progressPercent: String {
            String(format: "%.1f%%", progress * 100)
        }
    }

    /// Callback type for progress updates
    typealias ProgressCallback = (TripProgress) -> Void

    // MARK: - Public run

    /// Run trip simulation with pre-extracted project snapshot (concurrency-safe version)
    /// Callers should create the ProjectSnapshot on the main actor before calling this method.
    /// Marked nonisolated so it can run on a background thread for UI responsiveness.
    nonisolated func run(_ input: TripInput, geom: GeometryService, projectSnapshot: ProjectSnapshot, onProgress: ProgressCallback? = nil) -> [TripStep] {
        var sabp_kPa = input.initialSABP_kPa
        var bitMD = input.startBitMD_m
        let step = max(0.1, input.step_m)
        let tvdOfMd = input.tvdOfMd
        let tdTVD = tvdOfMd(input.startBitMD_m)
        let targetP_TD_kPa = input.targetESDAtTD_kgpm3 * NumericalTripModel.g * tdTVD / 1000.0

        // Stacks
        let stringStack = Stack(side: .string, geom: geom, tvdOfMd: tvdOfMd)
        let annulusStack = Stack(side: .annulus, geom: geom, tvdOfMd: tvdOfMd)

        // Seed annulus stack: from custom initial layers (Super Sim) or ProjectSnapshot
        if let customAnnulus = input.initialAnnulusLayers, !customAnnulus.isEmpty {
            // Direct layer assignment — avoids seed+paint boundary gaps
            annulusStack.layers = customAnnulus.map { l in
                let color: ColorRGBA? = (l.colorR != nil)
                    ? ColorRGBA(r: l.colorR ?? 0, g: l.colorG ?? 0, b: l.colorB ?? 0, a: l.colorA ?? 1)
                    : nil
                return Layer(rho: l.rho_kgpm3, topMD: l.topMD, bottomMD: l.bottomMD, color: color, pv_cP: l.pv_cP ?? 0, yp_Pa: l.yp_Pa ?? 0)
            }
            annulusStack.ensureInvariants(bitMD: bitMD)
        } else {
            annulusStack.seedUniform(rho: input.baseMudDensity_kgpm3, topMD: 0, bottomMD: bitMD)
            let ann = projectSnapshot.annulusLayers
            for l in ann {
                let layerColor = ColorRGBA(r: l.colorR, g: l.colorG, b: l.colorB, a: l.colorA)
                let pvCp = (l.mudDial600 != nil && l.mudDial300 != nil) ? (l.mudDial600! - l.mudDial300!) : 0.0
                let ypPa = (l.mudDial300 != nil) ? max(0, (l.mudDial300! - pvCp) * HydraulicsDefaults.fann35_dialToPa) : 0.0
                StackOps.paintInterval(annulusStack, l.topMD_m, l.bottomMD_m, l.density_kgm3, color: layerColor, pv_cP: pvCp, yp_Pa: ypPa)
            }
        }

        // Seed string stack: from custom initial layers (Super Sim) or ProjectSnapshot
        if let customString = input.initialStringLayers, !customString.isEmpty {
            // Direct layer assignment — avoids seed+paint boundary gaps
            stringStack.layers = customString.map { l in
                let color: ColorRGBA? = (l.colorR != nil)
                    ? ColorRGBA(r: l.colorR ?? 0, g: l.colorG ?? 0, b: l.colorB ?? 0, a: l.colorA ?? 1)
                    : nil
                return Layer(rho: l.rho_kgpm3, topMD: l.topMD, bottomMD: l.bottomMD, color: color, pv_cP: l.pv_cP ?? 0, yp_Pa: l.yp_Pa ?? 0)
            }
            stringStack.ensureInvariants(bitMD: bitMD)
        } else {
            stringStack.seedUniform(rho: input.baseMudDensity_kgpm3, topMD: 0, bottomMD: bitMD)
            let str = projectSnapshot.stringLayers
            for l in str {
                let layerColor = ColorRGBA(r: l.colorR, g: l.colorG, b: l.colorB, a: l.colorA)
                let pvCp = (l.mudDial600 != nil && l.mudDial300 != nil) ? (l.mudDial600! - l.mudDial300!) : 0.0
                let ypPa = (l.mudDial300 != nil) ? max(0, (l.mudDial300! - pvCp) * HydraulicsDefaults.fann35_dialToPa) : 0.0
                StackOps.paintInterval(stringStack, l.topMD_m, l.bottomMD_m, l.density_kgm3, color: layerColor, pv_cP: pvCp, yp_Pa: ypPa)
            }
        }

        // --- Slug Pulse / U-Tube Equalization Phase ---
        // Before the trip starts, check if the float would be open (string heavier than annulus).
        // If so, the heavy slug drains from the string, pushes annulus fluid up, and air fills the string.
        //
        // Two modes:
        // 1. Calculated: Iteratively drain until pressures equalize (pressure-based)
        // 2. Observed: Use user-provided pit gain to determine exactly how much slug drained (field calibration)

        // Report initial state
        onProgress?(TripProgress(
            phase: .initializing,
            currentMD_m: bitMD,
            startMD_m: input.startBitMD_m,
            endMD_m: input.endMD_m,
            floatState: "CHECKING",
            equalizationIterations: 0,
            message: "Initializing simulation..."
        ))

        let pulseStep_m3 = 0.01  // Small volume parcels for equalization (10 L)
        let maxPulseIterations = 10000  // Safety limit
        var pulseIteration = 0
        var totalDrainedVolume_m3 = 0.0  // Track total volume drained for observed mode

        // Helper function to drain a single parcel from string to annulus
        func drainParcel(volume: Double) -> Bool {
            guard volume > 1e-12, !stringStack.layers.isEmpty else { return false }

            let bottomLayer = stringStack.layers[stringStack.layers.count - 1]
            let bottomLen = bottomLayer.bottomMD - bottomLayer.topMD
            let bottomVol = geom.volumeInString_m3(bottomLayer.topMD, bottomLayer.bottomMD)

            let drainVol = min(volume, bottomVol)
            guard drainVol > 1e-12 else { return false }

            let drainLen = (bottomVol > 1e-12) ? (drainVol / bottomVol) * bottomLen : 0
            guard drainLen > 1e-12 else { return false }

            // Remove from bottom of string
            let drainRho = bottomLayer.rho
            let drainColor = bottomLayer.color
            let drainPV = bottomLayer.pv_cP
            let drainYP = bottomLayer.yp_Pa
            stringStack.layers[stringStack.layers.count - 1].bottomMD -= drainLen
            if stringStack.layers[stringStack.layers.count - 1].bottomMD - stringStack.layers[stringStack.layers.count - 1].topMD < 1e-9 {
                stringStack.layers.removeLast()
            }

            // Add air at top of string
            let airLen = geom.lengthForStringVolume_m(0, drainVol)
            if airLen > 1e-9 {
                if stringStack.layers.isEmpty || abs(stringStack.layers[0].rho - NumericalTripModel.rhoAir) > 1e-6 {
                    stringStack.layers.insert(Layer(rho: NumericalTripModel.rhoAir, topMD: 0, bottomMD: 0, color: nil), at: 0)
                }
                for i in 1..<stringStack.layers.count {
                    stringStack.layers[i].topMD += airLen
                    stringStack.layers[i].bottomMD += airLen
                }
                stringStack.layers[0].bottomMD += airLen
            }
            stringStack.ensureInvariants(bitMD: bitMD)

            // Inject at bottom of annulus, push everything up
            let annulusArea = geom.annulusArea_m2(bitMD)
            let annulusInjectLen = (annulusArea > 1e-12) ? drainVol / annulusArea : 0

            for i in annulusStack.layers.indices {
                annulusStack.layers[i].topMD = max(0, annulusStack.layers[i].topMD - annulusInjectLen)
                annulusStack.layers[i].bottomMD = max(0, annulusStack.layers[i].bottomMD - annulusInjectLen)
            }

            let newTop = max(0, bitMD - annulusInjectLen)
            if let lastAnn = annulusStack.layers.last, abs(lastAnn.rho - drainRho) < 1e-6 {
                annulusStack.layers[annulusStack.layers.count - 1].bottomMD = bitMD
            } else {
                annulusStack.layers.append(Layer(rho: drainRho, topMD: newTop, bottomMD: bitMD, color: drainColor, pv_cP: drainPV, yp_Pa: drainYP))
            }
            annulusStack.ensureInvariants(bitMD: bitMD)

            totalDrainedVolume_m3 += drainVol
            return true
        }

        if let observedPitGain = input.observedInitialPitGain_m3, observedPitGain > 0 {
            // --- OBSERVED MODE: Drain exactly the observed pit gain volume ---
            onProgress?(TripProgress(
                phase: .initialEqualization,
                currentMD_m: bitMD,
                startMD_m: input.startBitMD_m,
                endMD_m: input.endMD_m,
                floatState: "CALIBRATING",
                equalizationIterations: 0,
                message: "Calibrating to observed pit gain: \(String(format: "%.1f", observedPitGain * 1000))L"
            ))

            var remainingToDrain = observedPitGain
            while remainingToDrain > 1e-12 && pulseIteration < maxPulseIterations {
                pulseIteration += 1
                let drainAmount = min(pulseStep_m3, remainingToDrain)
                if !drainParcel(volume: drainAmount) { break }
                remainingToDrain -= drainAmount

                if pulseIteration % 100 == 0 {
                    onProgress?(TripProgress(
                        phase: .initialEqualization,
                        currentMD_m: bitMD,
                        startMD_m: input.startBitMD_m,
                        endMD_m: input.endMD_m,
                        floatState: "CALIBRATING",
                        equalizationIterations: pulseIteration,
                        message: "Calibrating - drained \(String(format: "%.1f", totalDrainedVolume_m3 * 1000))L of \(String(format: "%.1f", observedPitGain * 1000))L"
                    ))
                }
            }
        } else {
            // --- CALCULATED MODE: Drain until pressures equalize ---
            while pulseIteration < maxPulseIterations {
                pulseIteration += 1

                if pulseIteration % 100 == 0 {
                    onProgress?(TripProgress(
                        phase: .initialEqualization,
                        currentMD_m: bitMD,
                        startMD_m: input.startBitMD_m,
                        endMD_m: input.endMD_m,
                        floatState: "OPEN",
                        equalizationIterations: pulseIteration,
                        message: "Initial slug pulse - draining \(String(format: "%.1f", totalDrainedVolume_m3 * 1000))L"
                    ))
                }

                // Calculate pressures at bit
                let Pstr = stringStack.pressureAtBit_kPa(sabp_kPa: 0, bitMD: bitMD)
                let Pann = annulusStack.pressureAtBit_kPa(sabp_kPa: sabp_kPa, bitMD: bitMD)

                // Float closes when string pressure <= annulus pressure
                if Pstr <= Pann + input.crackFloat_kPa {
                    break
                }

                if !drainParcel(volume: pulseStep_m3) { break }
            }
        }

        // --- Pre-step initial snapshot (state AFTER slug pulse equalization) ---
        // Seed pocket (open hole below bit) from previous operation's state
        var pocket: [Layer] = []
        if let customPocket = input.initialPocketLayers {
            for l in customPocket where l.bottomMD > bitMD + 1e-9 {
                let top = max(l.topMD, bitMD)
                let color: ColorRGBA? = (l.colorR != nil) ? ColorRGBA(r: l.colorR ?? 0, g: l.colorG ?? 0, b: l.colorB ?? 0, a: l.colorA ?? 1) : nil
                pocket.append(Layer(rho: l.rho_kgpm3, topMD: top, bottomMD: l.bottomMD, color: color, pv_cP: l.pv_cP ?? 0, yp_Pa: l.yp_Pa ?? 0))
            }
        }
        let initPocketRows = snapshotPocket(pocket, bitMD: bitMD)
        let initAnnRows = snapshotStack(annulusStack, bitMD: bitMD)
        let initStrRows = snapshotStack(stringStack, bitMD: bitMD)
        let initTotPocket = sum(initPocketRows)
        let initTotAnn = sum(initAnnRows)
        let initTotStr = sum(initStrRows)
        let initSabpRaw = max(0.0, targetP_TD_kPa - initTotPocket.deltaP_kPa - initTotAnn.deltaP_kPa)
        // Respect HoldSABPOpen for the initial state as well
        if input.holdSABPOpen {
            sabp_kPa = 0.0
        } else {
            sabp_kPa = max(0.0, initSabpRaw)
        }
        let initBitTVD = tvdOfMd(bitMD)
        let initESD_TD = (initTotPocket.deltaP_kPa + initTotAnn.deltaP_kPa + sabp_kPa) / 0.00981 / tdTVD
        let initESD_Bit = max(0.0, (initTotAnn.deltaP_kPa + sabp_kPa) / 0.00981 / max(initBitTVD, 1e-9))
        // Volume tracking - cumulative values
        var cumulativeBackfill_m3: Double = 0.0
        var cumulativeSlugContribution_m3: Double = 0.0
        var cumulativePitGain_m3: Double = 0.0
        var cumulativeSurfaceTankDelta_m3: Double = 0.0

        // Track slug contribution from initial equalization phase
        // When slug drains from string, it pushes annulus fluid up and out at surface (pit gain)
        // Use actual drained volume (more accurate than pulseIteration * pulseStep_m3)
        let initialSlugContribution_m3: Double = totalDrainedVolume_m3
        let initialPitGain_m3: Double = initialSlugContribution_m3  // Overflow at surface = slug drained
        cumulativePitGain_m3 = initialPitGain_m3
        cumulativeSlugContribution_m3 = initialSlugContribution_m3
        cumulativeSurfaceTankDelta_m3 = initialPitGain_m3  // Tank increases during initial equalization

        var results: [TripStep] = [
            TripStep(
                bitMD_m: bitMD,
                bitTVD_m: initBitTVD,
                SABP_kPa: sabp_kPa,
                SABP_kPa_Raw: initSabpRaw,
                ESDatTD_kgpm3: initESD_TD,
                ESDatBit_kgpm3: initESD_Bit,
                backfillRemaining_m3: max(0.0, input.fixedBackfillVolume_m3),
                swabDropToBit_kPa: 0.0,
                SABP_Dynamic_kPa: sabp_kPa,
                floatState: pulseIteration > 0 ? "OPEN (Initial Slug)" : "CLOSED",  // Initial state
                stepBackfill_m3: 0,
                cumulativeBackfill_m3: 0,
                expectedFillIfClosed_m3: 0,
                expectedFillIfOpen_m3: 0,
                slugContribution_m3: initialSlugContribution_m3,
                cumulativeSlugContribution_m3: initialSlugContribution_m3,
                pitGain_m3: initialPitGain_m3,
                cumulativePitGain_m3: cumulativePitGain_m3,
                surfaceTankDelta_m3: initialPitGain_m3,  // Initial: tank increases from overflow
                cumulativeSurfaceTankDelta_m3: cumulativeSurfaceTankDelta_m3,
                layersPocket: initPocketRows,
                layersAnnulus: initAnnRows,
                layersString: initStrRows,
                totalsPocket: initTotPocket,
                totalsAnnulus: initTotAnn,
                totalsString: initTotStr
            )
        ]

        var backfillRemaining = input.fixedBackfillVolume_m3

        // Helper closures
        func snapshotPocket(_ pocket: [Layer], bitMD: Double) -> [LayerRow] {
            var rows: [LayerRow] = []
            for L in pocket where L.bottomMD > bitMD + 1e-9 {
                let a = max(L.topMD, bitMD)
                let b = L.bottomMD
                guard b - a > 1e-9 else { continue }
                let tvdTop = tvdOfMd(a), tvdBot = tvdOfMd(b)
                let dTVD = max(0.0, tvdBot - tvdTop)
                let dP = L.rho * NumericalTripModel.g * dTVD / 1000.0
                var row = LayerRow(side: "Pocket", topMD: a, bottomMD: b, topTVD: tvdTop, bottomTVD: tvdBot, rho_kgpm3: L.rho, deltaHydroStatic_kPa: dP, volume_m3: 0, color: L.color)
                row.pv_cP = L.pv_cP
                row.yp_Pa = L.yp_Pa
                rows.append(row)
            }
            return rows
        }
        func snapshotStack(_ s: Stack, bitMD: Double) -> [LayerRow] {
            var rows: [LayerRow] = []
            let sideLabel = (s.side == .annulus) ? "Annulus" : "String"
            for L in s.layers {
                let a = max(0.0, L.topMD)
                let b = min(bitMD, L.bottomMD)
                guard b - a > 1e-9 else { continue }
                let tvdTop = tvdOfMd(a), tvdBot = tvdOfMd(b)
                let dTVD = max(0.0, tvdBot - tvdTop)
                let dP = L.rho * NumericalTripModel.g * dTVD / 1000.0
                let vol = (sideLabel == "Annulus") ? geom.volumeInAnnulus_m3(a, b) : geom.volumeInString_m3(a, b)
                var row = LayerRow(side: sideLabel, topMD: a, bottomMD: b, topTVD: tvdTop, bottomTVD: tvdBot, rho_kgpm3: L.rho, deltaHydroStatic_kPa: dP, volume_m3: vol, color: L.color)
                row.pv_cP = L.pv_cP
                row.yp_Pa = L.yp_Pa
                rows.append(row)
            }
            return rows
        }
        func sum(_ rows: [LayerRow]) -> Totals {
            var tvd = 0.0, dP = 0.0
            for r in rows { tvd += max(0, r.bottomTVD - r.topTVD); dP += r.deltaHydroStatic_kPa }
            return Totals(count: rows.count, tvd_m: tvd, deltaP_kPa: dP)
        }
        func addPocketBelowBit(rho: Double, len: Double, bitMD: Double, color: ColorRGBA? = nil, pv_cP: Double = 0, yp_Pa: Double = 0) {
            guard len > 1e-9 else { return }
            let top = bitMD
            let bot = bitMD + len
            // Check if we can merge with the last pocket layer (same density and color)
            if let last = pocket.last, abs(last.rho - rho) < 1e-6, abs(last.bottomMD - top) < 1e-9 {
                // When merging, blend colors and PV/YP by length
                let lastLen = last.bottomMD - last.topMD
                let newLen = len
                let totalLen = lastLen + newLen
                var mergedColor: ColorRGBA? = nil
                if let lastColor = last.color, let newColor = color, totalLen > 1e-9 {
                    mergedColor = ColorRGBA(
                        r: (lastColor.r * lastLen + newColor.r * newLen) / totalLen,
                        g: (lastColor.g * lastLen + newColor.g * newLen) / totalLen,
                        b: (lastColor.b * lastLen + newColor.b * newLen) / totalLen,
                        a: (lastColor.a * lastLen + newColor.a * newLen) / totalLen
                    )
                } else {
                    mergedColor = last.color ?? color
                }
                let mergedPV = totalLen > 1e-9 ? (last.pv_cP * lastLen + pv_cP * newLen) / totalLen : pv_cP
                let mergedYP = totalLen > 1e-9 ? (last.yp_Pa * lastLen + yp_Pa * newLen) / totalLen : yp_Pa
                pocket[pocket.count-1] = Layer(rho: rho, topMD: last.topMD, bottomMD: bot, color: mergedColor, pv_cP: mergedPV, yp_Pa: mergedYP)
            } else {
                pocket.append(Layer(rho: rho, topMD: top, bottomMD: bot, color: color, pv_cP: pv_cP, yp_Pa: yp_Pa))
            }
        }

        // Main Trip Loop - Adaptive Stepping
        // Use coarse steps (5m) when float is solidly closed
        // Fall back to fine steps (1m) near float transitions or when float is open
        let fineStep: Double = 1.0           // 1m for precision near transitions
        let coarseStep: Double = 5.0         // 5m when float is solidly closed
        let marginForCoarse_kPa: Double = 50.0  // Pressure margin needed for coarse stepping

        var lastRecordedMD = bitMD  // Track when we last recorded a result
        var lastProgressReportMD = bitMD  // Track when we last reported progress
        let progressReportInterval: Double = 100.0  // Report progress every 100m (was 10m)

        // Step-level volume tracking (accumulated across internal steps until recorded)
        var stepBackfill_m3: Double = 0.0
        var stepSlugContribution_m3: Double = 0.0
        var stepPitGain_m3: Double = 0.0
        var stepExpectedIfClosed_m3: Double = 0.0
        var stepExpectedIfOpen_m3: Double = 0.0
        var stepFloatState: String = "CLOSED"
        var stepInternalCount: Int = 0      // Total internal steps in this output step
        var stepOpenCount: Int = 0          // Number of internal steps where float was OPEN
        var stepSwabAccum_kPa: Double = 0   // Accumulated swab pressure for averaging

        // Float valve tolerance: allows float to open when string pressure exceeds
        // annulus pressure by more than this threshold. Accounts for numerical
        // precision and real-world conditions where small differentials crack the float.
        let floatTolerance_kPa = HydraulicsDefaults.floatTolerance_kPa

        while bitMD > input.endMD_m + 1e-9 {
            // Check float state and pressure margin to determine step size
            var Pann_bit = annulusStack.pressureAtBit_kPa(sabp_kPa: sabp_kPa, bitMD: bitMD)
            var Pstr_bit = stringStack.pressureAtBit_kPa(sabp_kPa: 0, bitMD: bitMD)
            var floatClosed = (Pstr_bit <= Pann_bit + floatTolerance_kPa)
            let pressureMargin = Pann_bit + floatTolerance_kPa - Pstr_bit

            // Adaptive step size: use coarse steps when float is solidly closed
            let adaptiveStep: Double
            if floatClosed && pressureMargin > marginForCoarse_kPa {
                // Float solidly closed - safe to use coarse steps
                adaptiveStep = coarseStep
            } else {
                // Float open or near transition - use fine steps
                adaptiveStep = fineStep
            }

            // Calculate next position
            let nextMD = max(input.endMD_m, bitMD - adaptiveStep)
            let dL = bitMD - nextMD
            let oldBitMD = bitMD

            // Calculate expected fill volumes for this step
            // DP Wet = Pipe OD volume (capacity + displacement)
            // DP Dry = Steel displacement only (metal ring area)
            let expectedIfClosed = geom.volumeOfStringOD_m3(oldBitMD - dL, oldBitMD)  // DP Wet
            let expectedIfOpen = geom.steelDisplacement_m2(oldBitMD) * dL  // DP Dry
            stepExpectedIfClosed_m3 += expectedIfClosed
            stepExpectedIfOpen_m3 += expectedIfOpen

            // Report progress periodically (less frequently now)
            if lastProgressReportMD - bitMD >= progressReportInterval {
                lastProgressReportMD = bitMD
                onProgress?(TripProgress(
                    phase: .tripping,
                    currentMD_m: bitMD,
                    startMD_m: input.startBitMD_m,
                    endMD_m: input.endMD_m,
                    floatState: floatClosed ? "CLOSED" : "OPEN",
                    equalizationIterations: 0,
                    message: "Tripping at \(String(format: "%.0f", bitMD))m MD"
                ))
            }

            // If float is OPEN, run U-tube equalization before continuing the trip step
            // This drains string fluid into annulus until pressures equalize
            if !floatClosed {
                var eqIterations = 0
                let maxEqIterations = 1000  // Safety limit per step
                var eqSlugDrained_m3 = 0.0  // Track slug volume drained during this step's equalization

                while eqIterations < maxEqIterations {
                    eqIterations += 1

                    // Report progress every 200 iterations during equalization (was 50)
                    if eqIterations % 200 == 0 {
                        onProgress?(TripProgress(
                            phase: .stepEqualization,
                            currentMD_m: bitMD,
                            startMD_m: input.startBitMD_m,
                            endMD_m: input.endMD_m,
                            floatState: "OPEN",
                            equalizationIterations: eqIterations,
                            message: "Equalizing at \(String(format: "%.0f", bitMD))m"
                        ))
                    }

                    // Recalculate pressures
                    let Pstr_eq = stringStack.pressureAtBit_kPa(sabp_kPa: 0, bitMD: oldBitMD)
                    let Pann_eq = annulusStack.pressureAtBit_kPa(sabp_kPa: sabp_kPa, bitMD: oldBitMD)

                    // Float closes when string pressure <= annulus pressure
                    if Pstr_eq <= Pann_eq + input.crackFloat_kPa {
                        floatClosed = true
                        break
                    }

                    // Drain a small parcel from string bottom
                    guard !stringStack.layers.isEmpty else { break }

                    let bottomLayer = stringStack.layers[stringStack.layers.count - 1]
                    let bottomLen = bottomLayer.bottomMD - bottomLayer.topMD
                    let bottomVol = geom.volumeInString_m3(bottomLayer.topMD, bottomLayer.bottomMD)

                    let drainVol = min(pulseStep_m3, bottomVol)
                    guard drainVol > 1e-12 else { break }

                    // Track slug contribution
                    eqSlugDrained_m3 += drainVol

                    let drainLen = (bottomVol > 1e-12) ? (drainVol / bottomVol) * bottomLen : 0
                    guard drainLen > 1e-12 else { break }

                    // Remove from string bottom
                    let drainRho = bottomLayer.rho
                    let drainColor = bottomLayer.color
                    let drainPV = bottomLayer.pv_cP
                    let drainYP = bottomLayer.yp_Pa
                    stringStack.layers[stringStack.layers.count - 1].bottomMD -= drainLen
                    if stringStack.layers[stringStack.layers.count - 1].bottomMD - stringStack.layers[stringStack.layers.count - 1].topMD < 1e-9 {
                        stringStack.layers.removeLast()
                    }

                    // Add air at top of string
                    let airLen = geom.lengthForStringVolume_m(0, drainVol)
                    if airLen > 1e-9 {
                        if stringStack.layers.isEmpty || abs(stringStack.layers[0].rho - NumericalTripModel.rhoAir) > 1e-6 {
                            stringStack.layers.insert(Layer(rho: NumericalTripModel.rhoAir, topMD: 0, bottomMD: 0, color: nil), at: 0)
                        }
                        for i in 1..<stringStack.layers.count {
                            stringStack.layers[i].topMD += airLen
                            stringStack.layers[i].bottomMD += airLen
                        }
                        stringStack.layers[0].bottomMD += airLen
                    }
                    stringStack.ensureInvariants(bitMD: oldBitMD)

                    // Push annulus fluid up, inject drained string fluid at bottom
                    // Use annulus area at oldBitMD since we're injecting at the bottom
                    let annulusAreaMid = geom.annulusArea_m2(oldBitMD)
                    let annulusInjectLen = (annulusAreaMid > 1e-12) ? drainVol / annulusAreaMid : 0
                    for i in annulusStack.layers.indices {
                        annulusStack.layers[i].topMD = max(0, annulusStack.layers[i].topMD - annulusInjectLen)
                        annulusStack.layers[i].bottomMD = max(0, annulusStack.layers[i].bottomMD - annulusInjectLen)
                    }

                    let newTop = max(0, oldBitMD - annulusInjectLen)
                    if let lastAnn = annulusStack.layers.last, abs(lastAnn.rho - drainRho) < 1e-6 {
                        annulusStack.layers[annulusStack.layers.count - 1].bottomMD = oldBitMD
                    } else {
                        annulusStack.layers.append(Layer(rho: drainRho, topMD: newTop, bottomMD: oldBitMD, color: drainColor, pv_cP: drainPV, yp_Pa: drainYP))
                    }
                    annulusStack.ensureInvariants(bitMD: oldBitMD)
                }

                // Recalculate float state after equalization
                Pann_bit = annulusStack.pressureAtBit_kPa(sabp_kPa: sabp_kPa, bitMD: oldBitMD)
                Pstr_bit = stringStack.pressureAtBit_kPa(sabp_kPa: 0, bitMD: oldBitMD)
                floatClosed = (Pstr_bit <= Pann_bit + floatTolerance_kPa)

                // Add slug contribution from this step's equalization
                // Slug drains from string → pushes annulus up → overflow at surface (pit gain)
                stepSlugContribution_m3 += eqSlugDrained_m3
                stepPitGain_m3 += eqSlugDrained_m3  // Overflow at surface = slug drained
            }

            // Carve @ bottom for this step
            var lenA = 0.0, volA = 0.0, massA = 0.0

            func takeBottomByLen(_ stack: Stack, isAnnulus: Bool, lenReq: Double) -> (len: Double, mass: Double, vol: Double, blendedColor: ColorRGBA?, blendedPV_cP: Double, blendedYP_Pa: Double) {
                var remaining = lenReq
                var totLen = 0.0, totVol = 0.0, totMass = 0.0
                // For color blending: track volume-weighted color components
                var colorR = 0.0, colorG = 0.0, colorB = 0.0, colorA = 0.0
                var colorVol = 0.0
                // For PV/YP blending: volume-weighted
                var pvAccum = 0.0, ypAccum = 0.0, rheoVol = 0.0

                while remaining > 1e-9, !stack.layers.isEmpty {
                    var last = stack.layers.removeLast()
                    let span = last.bottomMD - last.topMD
                    if span <= 1e-12 { continue }
                    let take = min(span, remaining)
                    let segTop = last.bottomMD - take
                    let segBot = last.bottomMD
                    let segVol = isAnnulus ? stack.geom.volumeInAnnulus_m3(segTop, segBot) : stack.geom.volumeInString_m3(segTop, segBot)
                    let segMass = last.rho * segVol
                    totLen += take; totVol += segVol; totMass += segMass

                    // Accumulate volume-weighted color
                    if let c = last.color {
                        colorR += c.r * segVol
                        colorG += c.g * segVol
                        colorB += c.b * segVol
                        colorA += c.a * segVol
                        colorVol += segVol
                    }

                    // Accumulate volume-weighted PV/YP
                    if segVol > 1e-12 {
                        pvAccum += last.pv_cP * segVol
                        ypAccum += last.yp_Pa * segVol
                        rheoVol += segVol
                    }

                    last.bottomMD -= take
                    if last.bottomMD - last.topMD > 1e-12 { stack.layers.append(last) }
                    remaining -= take
                }

                // Calculate blended color
                let blendedColor: ColorRGBA? = colorVol > 1e-12 ? ColorRGBA(
                    r: colorR / colorVol,
                    g: colorG / colorVol,
                    b: colorB / colorVol,
                    a: colorA / colorVol
                ) : nil

                let blendedPV = rheoVol > 1e-12 ? pvAccum / rheoVol : 0.0
                let blendedYP = rheoVol > 1e-12 ? ypAccum / rheoVol : 0.0

                return (totLen, totMass, totVol, blendedColor, blendedPV, blendedYP)
            }

            var colorA: ColorRGBA? = nil
            var colorS: ColorRGBA? = nil
            var lenS = 0.0, volS = 0.0, massS = 0.0
            var mPocket = 0.0, vPocket = 0.0, lenPocket = 0.0
            var pvA = 0.0, ypA = 0.0, pvS = 0.0, ypS = 0.0

            if !floatClosed {
                // Float OPEN: String mud drains out the bottom (stays stationary relative to hole)
                // Pocket receives: string capacity + annulus capacity + steel displacement
                // Both stacks donate fluid that goes into the pocket below the bit

                // Carve from both string AND annulus
                let s = takeBottomByLen(stringStack, isAnnulus: false, lenReq: dL)
                lenS = s.len; volS = s.vol; massS = s.mass; colorS = s.blendedColor
                pvS = s.blendedPV_cP; ypS = s.blendedYP_Pa

                let a = takeBottomByLen(annulusStack, isAnnulus: true, lenReq: dL)
                lenA = a.len; volA = a.vol; massA = a.mass; colorA = a.blendedColor
                pvA = a.blendedPV_cP; ypA = a.blendedYP_Pa

                // Steel displacement goes to annulus side (added to pocket)
                let vSteel = geom.steelDisplacement_m2(oldBitMD) * dL
                let rhoA = (volA > 1e-12) ? massA/volA : input.baseMudDensity_kgpm3
                massA += rhoA * vSteel
                volA += vSteel

                // Pocket receives both string and annulus contributions
                mPocket = massA + massS
                vPocket = volA + volS
                lenPocket = min(lenA, lenS)

            } else {
                // Float CLOSED: String mud rises with the pipe (no draining)
                // Pocket receives: annulus only + pipe OD volume (all from annulus)

                // Only carve from annulus
                let a = takeBottomByLen(annulusStack, isAnnulus: true, lenReq: dL)
                lenA = a.len; volA = a.vol; massA = a.mass; colorA = a.blendedColor
                pvA = a.blendedPV_cP; ypA = a.blendedYP_Pa

                // Full pipe OD volume (not just steel) - the void left by the pipe
                let vOD = geom.volumeOfStringOD_m3(oldBitMD - dL, oldBitMD)
                let rhoA = (volA > 1e-12) ? massA/volA : input.baseMudDensity_kgpm3
                massA += rhoA * vOD
                volA += vOD

                mPocket = massA
                vPocket = volA
                lenPocket = lenA

                // String fluid moves with pipe - translate upward
                stringStack.translateAllLayers(by: -dL, bitMD: bitMD)
            }

            let rhoMix = (vPocket > 1e-12) ? (mPocket / vPocket) : input.baseMudDensity_kgpm3

            // Blend PV/YP for mixed pocket (volume-weighted)
            let mixedPV: Double
            let mixedYP: Double
            if !floatClosed, vPocket > 1e-12 {
                mixedPV = (pvA * volA + pvS * volS) / vPocket
                mixedYP = (ypA * volA + ypS * volS) / vPocket
            } else {
                mixedPV = pvA
                mixedYP = ypA
            }

            // Blend colors for mixed pocket (float OPEN mixes string + annulus colors)
            let mixedColor: ColorRGBA? = {
                var totalR = 0.0, totalG = 0.0, totalB = 0.0, totalA = 0.0
                var totalVol = 0.0

                if let cA = colorA, volA > 1e-12 {
                    totalR += cA.r * volA; totalG += cA.g * volA
                    totalB += cA.b * volA; totalA += cA.a * volA
                    totalVol += volA
                }
                if !floatClosed, let cS = colorS, volS > 1e-12 {
                    totalR += cS.r * volS; totalG += cS.g * volS
                    totalB += cS.b * volS; totalA += cS.a * volS
                    totalVol += volS
                }
                guard totalVol > 1e-12 else { return nil }
                return ColorRGBA(r: totalR/totalVol, g: totalG/totalVol,
                                 b: totalB/totalVol, a: totalA/totalVol)
            }()

            // Re-anchor stacks to new bit
            bitMD = nextMD

            if floatClosed {
                // String already translated above, just ensure annulus invariants
                annulusStack.ensureInvariants(bitMD: bitMD)
            } else {
                // Both stacks adjust to new bit position
                annulusStack.adjustBit(to: bitMD)
                stringStack.adjustBit(to: bitMD)
                annulusStack.ensureInvariants(bitMD: bitMD)
                stringStack.ensureInvariants(bitMD: bitMD)
            }

            // Append pocket at new bit with blended color
            addPocketBelowBit(rho: rhoMix, len: lenPocket, bitMD: bitMD, color: mixedColor, pv_cP: mixedPV, yp_Pa: mixedYP)

            // Surface backfill required
            // Float CLOSED (DP Wet): backfill = pipe OD volume (capacity + displacement)
            // Float OPEN (DP Dry): backfill = steel displacement only
            let needBefore: Double
            if floatClosed {
                needBefore = geom.volumeOfStringOD_m3(oldBitMD - dL, oldBitMD)  // DP Wet
            } else {
                needBefore = geom.steelDisplacement_m2(oldBitMD) * dL  // DP Dry
            }
            var need = needBefore
            if need > 1e-12 {
                // Determine which density to use for backfill:
                // - If fixedBackfillVolume was set and we still have some, use backfillDensity
                // - If fixedBackfillVolume was set but depleted and switchToBaseAfterFixed, use baseMudDensity
                // - If no fixedBackfillVolume was set (0), always use backfillDensity (user's selected mud)
                let hasFixedVolume = input.fixedBackfillVolume_m3 > 1e-12

                if hasFixedVolume {
                    // Original behavior: pump fixed volume of backfill, then switch to base
                    var useKill = min(need, backfillRemaining)
                    if !input.switchToBaseAfterFixed { useKill = need }
                    if useKill > 1e-12 {
                        annulusStack.addBackfillFromSurface(rho: input.backfillDensity_kgpm3, volume_m3: useKill, bitMD: bitMD, color: input.backfillColor, pv_cP: input.backfillPV_cP, yp_Pa: input.backfillYP_Pa)
                        backfillRemaining -= useKill
                        need -= useKill
                    }
                    if need > 1e-12, input.switchToBaseAfterFixed {
                        annulusStack.addBackfillFromSurface(rho: input.baseMudDensity_kgpm3, volume_m3: need, bitMD: bitMD, color: input.baseMudColor, pv_cP: input.baseMudPV_cP, yp_Pa: input.baseMudYP_Pa)
                        need = 0.0
                    }
                } else {
                    // No fixed volume specified: use backfillDensity for ALL backfill
                    // This is the common case where user selects a backfill mud in the UI
                    annulusStack.addBackfillFromSurface(rho: input.backfillDensity_kgpm3, volume_m3: need, bitMD: bitMD, color: input.backfillColor, pv_cP: input.backfillPV_cP, yp_Pa: input.backfillYP_Pa)
                    need = 0.0
                }
                annulusStack.ensureInvariants(bitMD: bitMD)
            }

            // Track actual backfill used for this 1m step
            let actualBackfill = needBefore - need
            stepBackfill_m3 += actualBackfill

            // Track float state for this step - count OPEN vs CLOSED internal steps
            stepInternalCount += 1
            if !floatClosed {
                stepOpenCount += 1
            }

            // Calculate swab at this 1m internal step using current float state
            // Accumulate for averaging over the recording interval
            let internalSwab_kPa = calculateSwabFromSnapshot(
                annulusLayers: projectSnapshot.annulusLayers,
                bitMD: bitMD,
                tripSpeed_m_per_s: input.tripSpeed_m_per_s,
                eccentricityFactor: input.eccentricityFactor,
                geom: geom,
                tvdOfMd: tvdOfMd,
                fallbackTheta600: input.fallbackTheta600,
                fallbackTheta300: input.fallbackTheta300,
                floatIsOpen: !floatClosed  // Use actual float state at this position
            )
            stepSwabAccum_kPa += internalSwab_kPa

            // Recompute pressures after fill
            Pann_bit = annulusStack.pressureAtBit_kPa(sabp_kPa: sabp_kPa, bitMD: bitMD)
            Pstr_bit = stringStack.pressureAtBit_kPa(sabp_kPa: 0, bitMD: bitMD)
            floatClosed = (Pstr_bit <= Pann_bit + floatTolerance_kPa)

            // Only record results at step_m intervals (or at the final position)
            let distanceSinceLastRecord = lastRecordedMD - bitMD
            let shouldRecord = distanceSinceLastRecord >= step - 0.01 || bitMD <= input.endMD_m + 0.01

            if shouldRecord {
                lastRecordedMD = bitMD

                // Snapshots & totals
                let pocketRows = snapshotPocket(pocket, bitMD: bitMD)
                let annRows = snapshotStack(annulusStack, bitMD: bitMD)
                let strRows = snapshotStack(stringStack, bitMD: bitMD)
                let totPocket = sum(pocketRows)
                let totAnn = sum(annRows)
                let totString = sum(strRows)

                // SABP target (hold closed-loop TD pressure if not HoldSABPOpen)
                // Average swab from all 1m internal steps (uses actual float state at each position)
                let swab_kPa = stepInternalCount > 0 ? stepSwabAccum_kPa / Double(stepInternalCount) : 0.0

                let sabpRaw = max(0.0, targetP_TD_kPa - totPocket.deltaP_kPa - totAnn.deltaP_kPa)
                if input.holdSABPOpen {
                    sabp_kPa = 0.0
                } else {
                    sabp_kPa = max(0.0, sabpRaw)
                }
                // Dynamic SABP includes swab compensation
                let sabpDyn = max(0.0, sabp_kPa + swab_kPa)

                let bitTVD = tvdOfMd(bitMD)
                let esdTD = (totPocket.deltaP_kPa + totAnn.deltaP_kPa + sabp_kPa) / 0.00981 / tdTVD
                let esdBit = max(0.0, (totAnn.deltaP_kPa + sabp_kPa) / 0.00981 / max(bitTVD, 1e-9))

                // Update cumulative volume tracking
                cumulativeBackfill_m3 += stepBackfill_m3
                cumulativeSlugContribution_m3 += stepSlugContribution_m3
                cumulativePitGain_m3 += stepPitGain_m3

                // Calculate surface tank delta (positive = tank gained, negative = tank used)
                // Pit gain increases tank, backfill decreases tank
                let stepTankDelta = stepPitGain_m3 - stepBackfill_m3
                cumulativeSurfaceTankDelta_m3 += stepTankDelta

                // Format float state with percentage (e.g., "OPEN 72%" or "CLOSED 100%")
                let openPercent = stepInternalCount > 0 ? Int(round(Double(stepOpenCount) / Double(stepInternalCount) * 100)) : 0
                if openPercent == 100 {
                    stepFloatState = "OPEN 100%"
                } else if openPercent == 0 {
                    stepFloatState = "CLOSED 100%"
                } else {
                    stepFloatState = "OPEN \(openPercent)%"
                }

                results.append(TripStep(bitMD_m: bitMD,
                                        bitTVD_m: bitTVD,
                                        SABP_kPa: sabp_kPa,
                                        SABP_kPa_Raw: sabpRaw,
                                        ESDatTD_kgpm3: esdTD,
                                        ESDatBit_kgpm3: esdBit,
                                        backfillRemaining_m3: max(0.0, backfillRemaining),
                                        swabDropToBit_kPa: swab_kPa,
                                        SABP_Dynamic_kPa: sabpDyn,
                                        floatState: stepFloatState,
                                        stepBackfill_m3: stepBackfill_m3,
                                        cumulativeBackfill_m3: cumulativeBackfill_m3,
                                        expectedFillIfClosed_m3: stepExpectedIfClosed_m3,
                                        expectedFillIfOpen_m3: stepExpectedIfOpen_m3,
                                        slugContribution_m3: stepSlugContribution_m3,
                                        cumulativeSlugContribution_m3: cumulativeSlugContribution_m3,
                                        pitGain_m3: stepPitGain_m3,
                                        cumulativePitGain_m3: cumulativePitGain_m3,
                                        surfaceTankDelta_m3: stepTankDelta,
                                        cumulativeSurfaceTankDelta_m3: cumulativeSurfaceTankDelta_m3,
                                        layersPocket: pocketRows,
                                        layersAnnulus: annRows,
                                        layersString: strRows,
                                        totalsPocket: totPocket,
                                        totalsAnnulus: totAnn,
                                        totalsString: totString))

                // Reset step-level accumulators for next recording interval
                stepBackfill_m3 = 0.0
                stepSlugContribution_m3 = 0.0
                stepPitGain_m3 = 0.0
                stepExpectedIfClosed_m3 = 0.0
                stepExpectedIfOpen_m3 = 0.0
                stepFloatState = "CLOSED"
                stepInternalCount = 0
                stepOpenCount = 0
                stepSwabAccum_kPa = 0
            }
        }

        // Report completion
        onProgress?(TripProgress(
            phase: .complete,
            currentMD_m: bitMD,
            startMD_m: input.startBitMD_m,
            endMD_m: input.endMD_m,
            floatState: "N/A",
            equalizationIterations: 0,
            message: "Simulation complete - \(results.count) steps recorded"
        ))

        return results
    }

    // MARK: - Swab Calculation Helper

    /// Calculates swab pressure for the annulus layers above the bit
    /// - Parameters:
    ///   - annulusLayers: The final fluid layers in the annulus (from project)
    ///   - bitMD: Current bit measured depth
    ///   - tripSpeed_m_per_s: Hoist speed in m/s
    ///   - eccentricityFactor: Pipe eccentricity factor (1.0 = concentric)
    ///   - geom: Geometry service for wellbore dimensions
    ///   - tvdOfMd: Function to convert MD to TVD
    ///   - fallbackTheta600: Fallback dial600 if layer has no mud reference
    ///   - fallbackTheta300: Fallback dial300 if layer has no mud reference
    ///   - floatIsOpen: Whether the float valve is open
    /// - Returns: Swab pressure drop in kPa, or 0 if calculation fails
    nonisolated private func calculateSwab(
        annulusLayers: [FinalFluidLayer],
        bitMD: Double,
        tripSpeed_m_per_s: Double,
        eccentricityFactor: Double,
        geom: GeometryService,
        tvdOfMd: @escaping (Double) -> Double,
        fallbackTheta600: Double?,
        fallbackTheta300: Double?,
        floatIsOpen: Bool
    ) -> Double {
        // Only calculate if we have positive trip speed (pulling out)
        guard tripSpeed_m_per_s > 0 else { return 0 }

        // Filter to layers above the bit
        let layersAboveBit = annulusLayers.filter { $0.topMD_m < bitMD }
        guard !layersAboveBit.isEmpty else { return 0 }

        // Build LayerDTO array with rheology from mud references
        var layerDTOs: [SwabCalculator.LayerDTO] = []

        for layer in layersAboveBit {
            let topMD = layer.topMD_m
            let bottomMD = min(layer.bottomMD_m, bitMD) // Clamp to bit depth

            guard bottomMD > topMD else { continue }

            // Get rheology from the linked mud, or use fallback
            var theta600: Double? = fallbackTheta600
            var theta300: Double? = fallbackTheta300
            var K: Double? = nil
            var n: Double? = nil

            if let mud = layer.mud {
                // Prefer annulus-specific K/n if available
                if let K_ann = mud.K_annulus, let n_ann = mud.n_annulus, K_ann > 0, n_ann > 0 {
                    K = K_ann
                    n = n_ann
                }
                // Otherwise use general K/n
                else if let K_gen = mud.k_powerLaw_Pa_s_n, let n_gen = mud.n_powerLaw, K_gen > 0, n_gen > 0 {
                    K = K_gen
                    n = n_gen
                }
                // Otherwise use dial readings
                else if let d600 = mud.dial600, let d300 = mud.dial300, d600 > 0, d300 > 0 {
                    theta600 = d600
                    theta300 = d300
                }
            }

            layerDTOs.append(SwabCalculator.LayerDTO(
                rho_kgpm3: layer.density_kgm3,
                topMD_m: topMD,
                bottomMD_m: bottomMD,
                K_Pa_s_n: K,
                n_powerLaw: n,
                theta600: theta600,
                theta300: theta300
            ))
        }

        guard !layerDTOs.isEmpty else { return 0 }

        // Check if we have any rheology data
        let hasRheology = layerDTOs.contains { dto in
            (dto.K_Pa_s_n != nil && dto.n_powerLaw != nil) ||
            (dto.theta600 != nil && dto.theta300 != nil)
        } || (fallbackTheta600 != nil && fallbackTheta300 != nil)

        guard hasRheology else {
            #if DEBUG
            print("[Swab] No rheology data available for swab calculation")
            #endif
            return 0
        }

        // Create trajectory sampler wrapper for TVD lookup
        let trajSampler = ClosureTrajectorySampler(tvdOfMd: tvdOfMd)

        // Calculate swab
        let calculator = SwabCalculator()
        do {
            let result = try calculator.estimateFromLayersPowerLaw(
                layers: layerDTOs,
                theta600: fallbackTheta600,
                theta300: fallbackTheta300,
                hoistSpeed_mpermin: tripSpeed_m_per_s * 60.0, // Convert m/s to m/min
                eccentricityFactor: eccentricityFactor,
                step_m: 10.0, // Fine step for accuracy
                geom: geom,
                traj: trajSampler,
                sabpSafety: 1.0, // We'll apply safety factor separately
                floatIsOpen: floatIsOpen
            )
            return result.totalSwab_kPa
        } catch {
            #if DEBUG
            print("[Swab] Calculation error: \(error.localizedDescription)")
            #endif
            return 0
        }
    }

    /// Calculates swab pressure using pre-extracted layer snapshots (concurrency-safe version)
    nonisolated private func calculateSwabFromSnapshot(
        annulusLayers: [FinalLayerSnapshot],
        bitMD: Double,
        tripSpeed_m_per_s: Double,
        eccentricityFactor: Double,
        geom: GeometryService,
        tvdOfMd: @escaping (Double) -> Double,
        fallbackTheta600: Double?,
        fallbackTheta300: Double?,
        floatIsOpen: Bool
    ) -> Double {
        // Only calculate if we have positive trip speed (pulling out)
        guard tripSpeed_m_per_s > 0 else { return 0 }

        // Filter to layers above the bit
        let layersAboveBit = annulusLayers.filter { $0.topMD_m < bitMD }
        guard !layersAboveBit.isEmpty else { return 0 }

        // Build LayerDTO array with rheology from snapshot
        var layerDTOs: [SwabCalculator.LayerDTO] = []

        for layer in layersAboveBit {
            let topMD = layer.topMD_m
            let bottomMD = min(layer.bottomMD_m, bitMD) // Clamp to bit depth

            guard bottomMD > topMD else { continue }

            // Get rheology from the snapshot, or use fallback
            var theta600: Double? = fallbackTheta600
            var theta300: Double? = fallbackTheta300
            var K: Double? = nil
            var n: Double? = nil

            // Prefer annulus-specific K/n if available
            if let K_ann = layer.mudK_annulus, let n_ann = layer.mudN_annulus, K_ann > 0, n_ann > 0 {
                K = K_ann
                n = n_ann
            }
            // Otherwise use general K/n
            else if let K_gen = layer.mudK_powerLaw, let n_gen = layer.mudN_powerLaw, K_gen > 0, n_gen > 0 {
                K = K_gen
                n = n_gen
            }
            // Otherwise use dial readings
            else if let d600 = layer.mudDial600, let d300 = layer.mudDial300, d600 > 0, d300 > 0 {
                theta600 = d600
                theta300 = d300
            }

            layerDTOs.append(SwabCalculator.LayerDTO(
                rho_kgpm3: layer.density_kgm3,
                topMD_m: topMD,
                bottomMD_m: bottomMD,
                K_Pa_s_n: K,
                n_powerLaw: n,
                theta600: theta600,
                theta300: theta300
            ))
        }

        guard !layerDTOs.isEmpty else { return 0 }

        // Check if we have any rheology data
        let hasRheology = layerDTOs.contains { dto in
            (dto.K_Pa_s_n != nil && dto.n_powerLaw != nil) ||
            (dto.theta600 != nil && dto.theta300 != nil)
        } || (fallbackTheta600 != nil && fallbackTheta300 != nil)

        guard hasRheology else {
            #if DEBUG
            print("[Swab] No rheology data available for swab calculation")
            #endif
            return 0
        }

        // Create trajectory sampler wrapper for TVD lookup
        let trajSampler = ClosureTrajectorySampler(tvdOfMd: tvdOfMd)

        // Calculate swab
        let calculator = SwabCalculator()
        do {
            let result = try calculator.estimateFromLayersPowerLaw(
                layers: layerDTOs,
                theta600: fallbackTheta600,
                theta300: fallbackTheta300,
                hoistSpeed_mpermin: tripSpeed_m_per_s * 60.0, // Convert m/s to m/min
                eccentricityFactor: eccentricityFactor,
                step_m: 10.0, // Fine step for accuracy
                geom: geom,
                traj: trajSampler,
                sabpSafety: 1.0, // We'll apply safety factor separately
                floatIsOpen: floatIsOpen
            )
            return result.totalSwab_kPa
        } catch {
            #if DEBUG
            print("[Swab] Calculation error: \(error.localizedDescription)")
            #endif
            return 0
        }
    }

    // MARK: - Optional color mappers (use in View layer or when seeding composition colors)
    static func rgbaFromHex(_ hex: String) -> ColorRGBA? {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let val = UInt32(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        if s.count == 6 {
            r = Double((val >> 16) & 0xFF) / 255.0
            g = Double((val >> 8)  & 0xFF) / 255.0
            b = Double(val & 0xFF) / 255.0
            a = 1.0
        } else {
            r = Double((val >> 24) & 0xFF) / 255.0
            g = Double((val >> 16) & 0xFF) / 255.0
            b = Double((val >> 8)  & 0xFF) / 255.0
            a = Double(val & 0xFF) / 255.0
        }
        return ColorRGBA(r: r, g: g, b: b, a: a)
    }
}

// MARK: - TrajectorySampler wrapper for closure-based TVD lookup

private struct ClosureTrajectorySampler: TrajectorySampler {
    let tvdOfMd: (Double) -> Double

    func TVDofMD(_ md: Double) -> Double {
        tvdOfMd(md)
    }
}
