//
//  NumericalTripModelService.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-07.
//

import Foundation


@MainActor
final class NumericalTripModel {
    static let g: Double = 9.81
    static let eps: Double = 1e-9
    static let rhoAir: Double = 1.2
    
    enum Side { case string, annulus }
    
    struct ColorRGBA: Equatable, Codable {
        var r: Double
        var g: Double
        var b: Double
        var a: Double
        static let clear = ColorRGBA(r: 0, g: 0, b: 0, a: 0)
    }
    
    struct Layer {
        var rho: Double
        var topMD: Double
        var bottomMD: Double
        var color: ColorRGBA? = nil
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
                    let right = NumericalTripModel.Layer(rho: L.rho, topMD: md, bottomMD: L.bottomMD, color: L.color)
                    stack.layers[i].bottomMD = md
                    stack.layers.insert(right, at: i + 1)
                    return
                }
            }
        }
        
        /// Paint (set density) for all sublayers fully contained within [fromMD, toMD].
        static func paintInterval(_ stack: NumericalTripModel.Stack, _ fromMD: Double, _ toMD: Double, _ rho: Double) {
            paintInterval(stack, fromMD, toMD, rho, color: nil)
        }
        
        /// Color-aware variant; when `color` is provided, painted sublayers also carry a composition color.
        static func paintInterval(_ stack: NumericalTripModel.Stack, _ fromMD: Double, _ toMD: Double, _ rho: Double, color: NumericalTripModel.ColorRGBA?) {
            let a = fromMD, b = toMD
            if b <= a { return }
            splitAt(stack, a)
            splitAt(stack, b)
            for i in 0..<stack.layers.count {
                if stack.layers[i].topMD >= a && stack.layers[i].bottomMD <= b {
                    stack.layers[i].rho = rho
                    stack.layers[i].color = color
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
        
        func addBackfillFromSurface(rho: Double, volume_m3: Double, bitMD: Double) {
            guard volume_m3 > 1e-12 else { return }
            let len = geom.lengthForAnnulusVolume_m(0.0, volume_m3)
            guard len > 1e-12 else { return }
            
            if layers.isEmpty || abs(layers[0].topMD) > 1e-9 || abs(layers[0].rho - rho) > 1e-6 {
                layers.insert(Layer(rho: rho, topMD: 0, bottomMD: 0, color: nil), at: 0)
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
        // Snapshots for UI/debug
        var layersPocket: [LayerRow]
        var layersAnnulus: [LayerRow]
        var layersString: [LayerRow]
        var totalsPocket: Totals
        var totalsAnnulus: Totals
        var totalsString: Totals
    }
    
    struct TripInput {
        var tvdOfMd: (Double)->Double
        var shoeTVD_m: Double
        var startBitMD_m: Double
        var endMD_m: Double
        var crackFloat_kPa: Double
        var step_m: Double = 10.0
        var baseMudDensity_kgpm3: Double
        var backfillDensity_kgpm3: Double
        var fixedBackfillVolume_m3: Double = 0
        var switchToBaseAfterFixed: Bool = true
        var targetESDAtTD_kgpm3: Double
        var initialSABP_kPa: Double = 0
        var holdSABPOpen: Bool = false
        // Swab placeholder
        var swabTheta600: Double? = nil
        var swabTheta300: Double? = nil
    }
    
    // MARK: - Public run
    
    func run(_ input: TripInput, geom: GeometryService, project: ProjectState) -> [TripStep] {
        var sabp_kPa = input.initialSABP_kPa
        var bitMD = input.startBitMD_m
        let step = max(0.1, input.step_m)
        let tvdOfMd = input.tvdOfMd
        let tdTVD = tvdOfMd(input.startBitMD_m)
        let targetP_TD_kPa = input.targetESDAtTD_kgpm3 * NumericalTripModel.g * tdTVD / 1000.0
        // let sampler = TvdSampler(stations: project.surveys) // Unused

        // Stacks
        let stringStack = Stack(side: .string, geom: geom, tvdOfMd: tvdOfMd)
        let annulusStack = Stack(side: .annulus, geom: geom, tvdOfMd: tvdOfMd)
        
        let ann = project.finalAnnulusLayersSorted
        let str = project.finalStringLayersSorted
        
        annulusStack.seedUniform(rho: input.baseMudDensity_kgpm3, topMD: 0, bottomMD: bitMD)
        for l in ann {
            StackOps.paintInterval(annulusStack, l.topMD_m, l.bottomMD_m, l.density_kgm3)
        }

        stringStack.seedUniform(rho: input.baseMudDensity_kgpm3, topMD: 0, bottomMD: bitMD)
        for l in str {
            StackOps.paintInterval(stringStack, l.topMD_m, l.bottomMD_m, l.density_kgm3)
        }

        // --- Pre-step initial snapshot (state BEFORE any movement) ---
        var pocket: [Layer] = []
        let initPocketRows = snapshotPocket(pocket, bitMD: bitMD)
        let initAnnRows = snapshotStack(annulusStack, bitMD: bitMD)
        let initStrRows = snapshotStack(stringStack, bitMD: bitMD)
        let initTotPocket = sum(initPocketRows)
        let initTotAnn = sum(initAnnRows)
        let initTotStr = sum(initStrRows)
        var initSabpRaw = max(0.0, targetP_TD_kPa - initTotPocket.deltaP_kPa - initTotAnn.deltaP_kPa)
        // Respect HoldSABPOpen for the initial state as well
        if input.holdSABPOpen {
            sabp_kPa = 0.0
        } else {
            sabp_kPa = max(0.0, initSabpRaw)
        }
        let initBitTVD = tvdOfMd(bitMD)
        let initESD_TD = (initTotPocket.deltaP_kPa + initTotAnn.deltaP_kPa + sabp_kPa) / 0.00981 / tdTVD
        let initESD_Bit = max(0.0, (initTotAnn.deltaP_kPa + sabp_kPa) / 0.00981 / max(initBitTVD, 1e-9))
        var results: [TripStep] = [
            TripStep(
                bitMD_m: bitMD,
                bitTVD_m: initBitTVD,
                SABP_kPa: sabp_kPa,
                SABP_kPa_Raw: initSabpRaw,
                ESDatTD_kgpm3: initESD_TD,
                ESDatBit_kgpm3: initESD_Bit,
                backfillRemaining_m3: max(0.0, input.fixedBackfillVolume_m3),
                swabDropToBit_kPa: 0.0, // pre-step snapshot
                SABP_Dynamic_kPa: sabp_kPa, // no swab component yet
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
                rows.append(.init(side: "Pocket", topMD: a, bottomMD: b, topTVD: tvdTop, bottomTVD: tvdBot, rho_kgpm3: L.rho, deltaHydroStatic_kPa: dP, volume_m3: 0, color: L.color))
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
                rows.append(.init(side: sideLabel, topMD: a, bottomMD: b, topTVD: tvdTop, bottomTVD: tvdBot, rho_kgpm3: L.rho, deltaHydroStatic_kPa: dP, volume_m3: vol, color: L.color))
            }
            return rows
        }
        func sum(_ rows: [LayerRow]) -> Totals {
            var tvd = 0.0, dP = 0.0
            for r in rows { tvd += max(0, r.bottomTVD - r.topTVD); dP += r.deltaHydroStatic_kPa }
            return Totals(count: rows.count, tvd_m: tvd, deltaP_kPa: dP)
        }
        func addPocketBelowBit(rho: Double, len: Double, bitMD: Double) {
            guard len > 1e-9 else { return }
            let top = bitMD
            let bot = bitMD + len
            if let last = pocket.last, abs(last.rho - rho) < 1e-6, abs(last.bottomMD - top) < 1e-9 {
                var L = last; L.bottomMD = bot; pocket[pocket.count-1] = L
            } else {
                pocket.append(Layer(rho: rho, topMD: top, bottomMD: bot))
            }
        }
        
        // Loop
        // var wasClosedPrev = stringStack.pressureAtBit_kPa(sabp_kPa: 0, bitMD: bitMD) <= annulusStack.pressureAtBit_kPa(sabp_kPa: sabp_kPa, bitMD: bitMD) // Unused

        while bitMD > input.endMD_m + 1e-9 {
            let nextMD = max(input.endMD_m, bitMD - step)
            let dL = bitMD - nextMD
            let oldBitMD = bitMD
            
            // Float state before carving
            var Pann_bit = annulusStack.pressureAtBit_kPa(sabp_kPa: sabp_kPa, bitMD: oldBitMD)
            var Pstr_bit = stringStack.pressureAtBit_kPa(sabp_kPa: 0, bitMD: oldBitMD)
            var floatClosed = (Pstr_bit <= Pann_bit)
            
            // Carve @ bottom for this step
            var lenA = 0.0, volA = 0.0, massA = 0.0
            var lenS = 0.0, volS = 0.0, massS = 0.0
            
            func takeBottomByLen(_ stack: Stack, isAnnulus: Bool, lenReq: Double) -> (len: Double, mass: Double, vol: Double) {
                var remaining = lenReq
                var totLen = 0.0, totVol = 0.0, totMass = 0.0
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
                    last.bottomMD -= take
                    if last.bottomMD - last.topMD > 1e-12 { stack.layers.append(last) }
                    remaining -= take
                }
                return (totLen, totMass, totVol)
            }
            
            if !floatClosed {
                let s = takeBottomByLen(stringStack, isAnnulus: false, lenReq: dL)
                let a = takeBottomByLen(annulusStack, isAnnulus: true, lenReq: dL)
                lenS = s.len; volS = s.vol; massS = s.mass
                lenA = a.len; volA = a.vol; massA = a.mass
                // steel displacement goes to annulus side
                let vSteel = geom.steelArea_m2(oldBitMD) * dL
                let rhoA = (volA > 1e-12) ? massA/volA : input.baseMudDensity_kgpm3
                massA += rhoA * vSteel
                volA += vSteel
            } else {
                let a = takeBottomByLen(annulusStack, isAnnulus: true, lenReq: dL)
                lenA = a.len; volA = a.vol; massA = a.mass
                let vOD = geom.volumeOfStringOD_m3(oldBitMD - dL, oldBitMD)
                let rhoA = (volA > 1e-12) ? massA/volA : input.baseMudDensity_kgpm3
                massA += rhoA * vOD
                volA += vOD
            }
            
            let vPocket = volA + (floatClosed ? 0.0 : volS)
            let mPocket = massA + (floatClosed ? 0.0 : massS)
            let rhoMix = (vPocket > 1e-12) ? (mPocket / vPocket) : input.baseMudDensity_kgpm3
            
            // Re-anchor stacks to new bit
            bitMD = nextMD
            if floatClosed {
                stringStack.translateAllLayers(by: -dL, bitMD: bitMD)
                annulusStack.ensureInvariants(bitMD: bitMD)
            } else {
                annulusStack.adjustBit(to: bitMD)
                stringStack.adjustBit(to: bitMD)
                annulusStack.ensureInvariants(bitMD: bitMD)
            }
            // Append pocket at new bit
            addPocketBelowBit(rho: rhoMix, len: min(lenA, (floatClosed ? lenA : lenS)), bitMD: bitMD)
            
            // Surface backfill required
            let needBefore = floatClosed ? geom.volumeOfStringOD_m3(oldBitMD - dL, oldBitMD) : geom.steelArea_m2(oldBitMD) * dL
            var need = needBefore
            var _usedKill = 0.0 // Placeholder for tracking
            var _usedBase = 0.0 // Placeholder for tracking
            if need > 1e-12 {
                var useKill = min(need, backfillRemaining)
                if !input.switchToBaseAfterFixed { useKill = need }
                if useKill > 1e-12 {
                    annulusStack.addBackfillFromSurface(rho: input.backfillDensity_kgpm3, volume_m3: useKill, bitMD: bitMD)
                    backfillRemaining -= useKill
                    need -= useKill
                    _usedKill = useKill
                }
                if need > 1e-12, input.switchToBaseAfterFixed {
                    annulusStack.addBackfillFromSurface(rho: input.baseMudDensity_kgpm3, volume_m3: need, bitMD: bitMD)
                    _usedBase = need
                    need = 0.0
                }
                annulusStack.ensureInvariants(bitMD: bitMD)
            }
            
            // Recompute pressures after fill
            Pann_bit = annulusStack.pressureAtBit_kPa(sabp_kPa: sabp_kPa, bitMD: bitMD)
            Pstr_bit = stringStack.pressureAtBit_kPa(sabp_kPa: 0, bitMD: bitMD)
            floatClosed = (Pstr_bit <= Pann_bit)
            
            // Snapshots & totals
            let pocketRows = snapshotPocket(pocket, bitMD: bitMD)
            let annRows = snapshotStack(annulusStack, bitMD: bitMD)
            let strRows = snapshotStack(stringStack, bitMD: bitMD)
            let totPocket = sum(pocketRows)
            let totAnn = sum(annRows)
            let totString = sum(strRows)
            
            // SABP target (hold closed-loop TD pressure if not HoldSABPOpen)
            var swab_kPa = 0.0 // placeholder hook for future SwabEstimatorService
            var sabpRaw = max(0.0, targetP_TD_kPa - totPocket.deltaP_kPa - totAnn.deltaP_kPa)
            if input.holdSABPOpen {
                sabp_kPa = 0.0
            } else {
                sabp_kPa = max(0.0, sabpRaw)
            }
            let sabpDyn = max(0.0, sabp_kPa + swab_kPa)
            
            let bitTVD = tvdOfMd(bitMD)
            let esdTD = (totPocket.deltaP_kPa + totAnn.deltaP_kPa + sabp_kPa) / 0.00981 / tdTVD
            let esdBit = max(0.0, (totAnn.deltaP_kPa + sabp_kPa) / 0.00981 / max(bitTVD, 1e-9))
            
            results.append(TripStep(bitMD_m: bitMD,
                                    bitTVD_m: bitTVD,
                                    SABP_kPa: sabp_kPa,
                                    SABP_kPa_Raw: sabpRaw,
                                    ESDatTD_kgpm3: esdTD,
                                    ESDatBit_kgpm3: esdBit,
                                    backfillRemaining_m3: max(0.0, backfillRemaining),
                                    swabDropToBit_kPa: swab_kPa,
                                    SABP_Dynamic_kPa: sabpDyn,
                                    layersPocket: pocketRows,
                                    layersAnnulus: annRows,
                                    layersString: strRows,
                                    totalsPocket: totPocket,
                                    totalsAnnulus: totAnn,
                                    totalsString: totString))
            wasClosedPrev = floatClosed
        }
        
        return results
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
