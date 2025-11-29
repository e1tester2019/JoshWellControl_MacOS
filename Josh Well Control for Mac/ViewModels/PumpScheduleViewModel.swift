//
//  PumpScheduleViewModel.swift
//  Josh Well Control
//
//  ViewModel for pump schedule simulation
//

import Foundation
import SwiftUI
import Observation

@Observable
class PumpScheduleViewModel {
    enum Side { case annulus, string }

    struct Stage {
        let name: String
        let color: Color
        let totalVolume_m3: Double
        let side: Side
        let mud: MudProperties?
    }

    var stages: [Stage] = []
    var stageIndex: Int = 0
    var progress: Double = 0
    var stageDisplayIndex: Int { min(max(stageIndex, 0), max(stages.count - 1, 0)) }

    // Hydraulics inputs
    var pumpRate_m3permin: Double = 0.50
    var mpdEnabled: Bool = false
    var targetEMD_kgm3: Double = 1300
    var controlMD_m: Double = 0

    enum ControlDepthMode: Int, Codable { case bit = 0, custom }
    var controlDepthModeRaw: Int = ControlDepthMode.bit.rawValue
    var controlDepthMode: ControlDepthMode {
        get { ControlDepthMode(rawValue: controlDepthModeRaw) ?? .bit }
        set { controlDepthModeRaw = newValue.rawValue }
    }

    // Source mode: build from final layers (existing) or from a custom program of volume-based stages
    enum SourceMode: Int, Codable { case finalLayers = 0, program = 1 }
    var sourceModeRaw: Int = SourceMode.finalLayers.rawValue
    var sourceMode: SourceMode {
        get { SourceMode(rawValue: sourceModeRaw) ?? .finalLayers }
        set { sourceModeRaw = newValue.rawValue }
    }

    // Program stages (volume-based) to pump down the string
    struct ProgramStage: Identifiable {
        let id: UUID
        var name: String
        var mudID: UUID?
        var color: Color
        var volume_m3: Double
        var pumpRate_m3permin: Double?
    }
    var program: [ProgramStage] = []

    func loadProgram(from project: ProjectState) {
        program = project.programStages
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { s in
                ProgramStage(
                    id: s.id,
                    name: s.name,
                    mudID: s.mud?.id,
                    color: s.color,
                    volume_m3: s.volume_m3,
                    pumpRate_m3permin: s.pumpRate_m3permin
                )
            }
    }

    func saveProgram(to project: ProjectState) {
        // Build a lookup of existing models by id
        var byID: [UUID: PumpProgramStage] = [:]
        for s in project.programStages { byID[s.id] = s }

        // Track the next order index
        let maxOrder = project.programStages.map { $0.orderIndex }.max() ?? -1
        var nextOrder = maxOrder + 1

        // Delete removed
        let desiredIDs = Set(program.map { $0.id })
        project.programStages.removeAll { !desiredIDs.contains($0.id) }

        // Update existing and add new, maintaining orderIndex
        for stage in program {
            if let existing = byID[stage.id] {
                existing.name = stage.name
                existing.volume_m3 = stage.volume_m3
                existing.pumpRate_m3permin = stage.pumpRate_m3permin
                existing.color = stage.color
                existing.mud = stage.mudID.flatMap { id in project.muds.first(where: { $0.id == id }) }
                // keep existing.orderIndex as-is
            } else {
                let mud = stage.mudID.flatMap { id in project.muds.first(where: { $0.id == id }) }
                let s = PumpProgramStage(name: stage.name,
                                         volume_m3: stage.volume_m3,
                                         pumpRate_m3permin: stage.pumpRate_m3permin,
                                         color: stage.color,
                                         project: project,
                                         mud: mud)
                s.id = stage.id
                s.orderIndex = nextOrder
                nextOrder += 1
                project.programStages.append(s)
            }
        }
    }

    func currentStage(project: ProjectState) -> Stage? {
        stages.isEmpty ? nil : stages[stageDisplayIndex]
    }

    func currentStageMud(project: ProjectState) -> MudProperties? {
        print("\(currentStage(project: project)?.mud?.density_kgm3 ?? 0)");
        return currentStage(project: project)?.mud
    }

    func buildStages(project: ProjectState) {
        switch sourceMode {
        case .finalLayers:
            buildStagesFromFinalLayers(project: project)
        case .program:
            buildStagesFromProgram(project: project)
        }
        saveProgram(to: project)
    }

    private func buildStagesFromFinalLayers(project: ProjectState) {
        stages.removeAll()
        let bitMD = max(
            project.annulus.map { $0.bottomDepth_m }.max() ?? 0,
            project.drillString.map { $0.bottomDepth_m }.max() ?? 0
        )
        let geom = ProjectGeometryService(project: project, currentStringBottomMD: bitMD)
        let activeMud = project.activeMud
        // Annulus first – order by shallow to deep (top MD ascending)
        let ann = project.finalLayers.filter { $0.placement == .annulus || $0.placement == .both }
            .sorted { min($0.topMD_m, $0.bottomMD_m) < min($1.topMD_m, $1.bottomMD_m) }
        for L in ann {
            let t = min(L.topMD_m, L.bottomMD_m)
            let b = max(L.topMD_m, L.bottomMD_m)
            let vol = geom.volumeInAnnulus_m3(t, b)
            let col = L.mud?.color ?? L.color
            stages.append(Stage(name: L.name, color: col, totalVolume_m3: vol, side: .annulus, mud: L.mud ?? activeMud))
        }
        // Then string – order deepest to shallowest as per spec
        let str = project.finalLayers.filter { $0.placement == .string || $0.placement == .both }
            .sorted { min($0.topMD_m, $0.bottomMD_m) < min($1.topMD_m, $1.bottomMD_m) }
            .reversed()
        for L in str {
            let t = min(L.topMD_m, L.bottomMD_m)
            let b = max(L.topMD_m, L.bottomMD_m)
            let vol = geom.volumeInString_m3(t, b)
            let col = L.mud?.color ?? L.color
            stages.append(Stage(name: L.name, color: col, totalVolume_m3: vol, side: .string, mud: L.mud ?? activeMud))
        }
        stageIndex = 0
        progress = 0
    }

    private func mudFor(id: UUID?, in project: ProjectState) -> MudProperties? {
        guard let id else { return project.activeMud }
        return project.muds.first(where: { $0.id == id }) ?? project.activeMud
    }

    private func buildStagesFromProgram(project: ProjectState) {
        stages.removeAll()
        for s in program {
            let mud = mudFor(id: s.mudID, in: project)
            let col = mud?.color ?? s.color
            stages.append(Stage(name: s.name, color: col, totalVolume_m3: max(0, s.volume_m3), side: .string, mud: mud))
        }
        stageIndex = 0
        progress = 0
    }

    func bootstrap(project: ProjectState) {
        loadProgram(from: project)
        buildStages(project: project)
        controlMD_m = project.pressureDepth_m
    }

    func nextStageOrWrap() {
        if progress >= 0.9999 {
            stageIndex = min(stageIndex + 1, max(stages.count - 1, 0))
            progress = 0
        } else {
            progress = 1
        }
    }

    func prevStageOrWrap() {
        if progress <= 0.0001 {
            stageIndex = max(stageIndex - 1, 0)
            progress = 1
        } else {
            progress = 0
        }
    }

    struct Seg {
        var top: Double
        var bottom: Double
        var color: Color
        var mud: MudProperties?
    }

    /// A volume parcel of a specific mud and color
    private struct VolumeParcel {
        var volume_m3: Double
        var color: Color
        var mud: MudProperties?
    }

    /// A capacity section (either string or annulus) with fixed total volume
    /// and an ordered list of parcels from shallow (index 0) to deep (last).
    private struct VolumeSection {
        let topMD: Double
        let bottomMD: Double
        let capacity_m3: Double
        var parcels: [VolumeParcel]
    }

    private func merge(_ segs: [Seg]) -> [Seg] {
        let tol = 1e-6
        var out: [Seg] = []
        for s in segs {
            if s.bottom - s.top < tol { continue }
            if let last = out.last,
               abs(last.bottom - s.top) < tol,
               last.mud?.id == s.mud?.id {
                out[out.count - 1].bottom = s.bottom
            } else {
                out.append(s)
            }
        }
        return out
    }

    struct StackState {
        var string: [Seg]
        var annulus: [Seg]
    }

    func stacksFor(project: ProjectState, stageIndex: Int, pumpedV: Double) -> StackState {
        let bitMD = max(
            project.annulus.map { $0.bottomDepth_m }.max() ?? 0,
            project.drillString.map { $0.bottomDepth_m }.max() ?? 0
        )
        let geom = ProjectGeometryService(project: project, currentStringBottomMD: bitMD)

        // Initial active mud fills both
        var string: [Seg] = [Seg(top: 0, bottom: bitMD, color: project.activeMud?.color ?? .gray.opacity(0.35), mud: project.activeMud)]
        var annulus: [Seg] = [Seg(top: 0, bottom: bitMD, color: project.activeMud?.color ?? .gray.opacity(0.35), mud: project.activeMud)]

        // Apply all stages before the current one completely
        for i in 0..<stageIndex {
            guard i < stages.count else { break }
            let st = stages[i]
            let vol = max(0, st.totalVolume_m3)
            string = applyStringStage(string: string, volume: vol, color: st.color, mud: st.mud, bitMD: bitMD, geom: geom)
            annulus = applyAnnulusStage(annulus: annulus, string: string, volume: vol, color: st.color, mud: st.mud, bitMD: bitMD, geom: geom)
        }

        // Partially apply the current stage by pumpedV
        if stageIndex < stages.count {
            let st = stages[stageIndex]
            let vol = pumpedV
            string = applyStringStage(string: string, volume: vol, color: st.color, mud: st.mud, bitMD: bitMD, geom: geom)
            annulus = applyAnnulusStage(annulus: annulus, string: string, volume: vol, color: st.color, mud: st.mud, bitMD: bitMD, geom: geom)
        }

        return StackState(string: merge(string), annulus: merge(annulus))
    }

    private func applyStringStage(string: [Seg], volume: Double, color: Color, mud: MudProperties?, bitMD: Double, geom: ProjectGeometryService) -> [Seg] {
        let L = geom.lengthForStringVolume_m(0.0, volume)
        let taken = takeFromBottom(string, length: L, bitMD: bitMD, geom: geom)
        return injectAtSurfaceString(string, length: L, color: color, mud: mud, bitMD: bitMD)
    }

    private func applyAnnulusStage(annulus: [Seg], string: [Seg], volume: Double, color: Color, mud: MudProperties?, bitMD: Double, geom: ProjectGeometryService) -> [Seg] {
        let L = geom.lengthForStringVolume_m(0.0, volume)
        let taken = takeFromBottom(string, length: L, bitMD: bitMD, geom: geom)
        let takenV = taken.parcels.reduce(0.0) { $0 + max(0, $1.volume_m3) }
        let excess = max(0.0, volume - takenV)
        var parcels = taken.parcels
        if excess > 1e-9 {
            parcels.append((volume_m3: excess, color: color, mud: mud))
        }
        return pushUpFromBitAnnulus(annulus, parcels: parcels, bitMD: bitMD, geom: geom)
    }

    private func takeFromBottom(_ segs: [Seg], length: Double, bitMD: Double, geom: ProjectGeometryService) -> (remaining: [Seg], parcels: [(volume_m3: Double, color: Color, mud: MudProperties?)]) {
        guard length > 0 else {
            return (segs, [])
        }

        var remain = segs
        var parcels: [(volume_m3: Double, color: Color, mud: MudProperties?)] = []
        var leftToTake = length

        while leftToTake > 1e-9, !remain.isEmpty {
            var last = remain.removeLast()
            let segLen = last.bottom - last.top
            if segLen <= leftToTake + 1e-9 {
                let vol = geom.volumeInString_m3(last.top, last.bottom)
                parcels.append((volume_m3: vol, color: last.color, mud: last.mud))
                leftToTake -= segLen
            } else {
                let newBot = last.bottom - leftToTake
                let vol = geom.volumeInString_m3(newBot, last.bottom)
                parcels.append((volume_m3: vol, color: last.color, mud: last.mud))
                last.bottom = newBot
                remain.append(last)
                leftToTake = 0
            }
        }

        return (remain, parcels.reversed())
    }

    private func injectAtSurfaceString(_ segs: [Seg], length: Double, color: Color, mud: MudProperties?, bitMD: Double) -> [Seg] {
        guard length > 0 else { return segs }
        var out: [Seg] = []
        var injected = false
        for s in segs {
            if !injected, s.top < length {
                if s.bottom <= length {
                    out.append(Seg(top: s.top, bottom: s.bottom, color: color, mud: mud))
                } else {
                    out.append(Seg(top: s.top, bottom: length, color: color, mud: mud))
                    out.append(Seg(top: length, bottom: s.bottom, color: s.color, mud: s.mud))
                }
                injected = true
            } else {
                out.append(s)
            }
        }
        if !injected {
            out.insert(Seg(top: 0, bottom: min(length, bitMD), color: color, mud: mud), at: 0)
        }
        return out
    }

    private func pushUpFromBitAnnulus(_ segs: [Seg], parcels: [(volume_m3: Double, color: Color, mud: MudProperties?)], bitMD: Double, geom: ProjectGeometryService) -> [Seg] {
        guard !parcels.isEmpty else { return segs }

        var result = segs
        var usedFromBottom: Double = 0

        for p in parcels {
            let L = lengthForAnnulusParcelVolumeFromBottom(
                volume: max(0, p.volume_m3),
                bitMD: bitMD,
                usedFromBottom: usedFromBottom,
                geom: geom
            )

            if L > 0 {
                let topMD = max(0, bitMD - usedFromBottom - L)
                let botMD = max(0, bitMD - usedFromBottom)
                result = overlaySegment(result, top: topMD, bottom: botMD, color: p.color, mud: p.mud)
                usedFromBottom += L
            }
        }

        return result
    }

    private func lengthForAnnulusParcelVolumeFromBottom(volume: Double, bitMD: Double, usedFromBottom: Double, geom: ProjectGeometryService) -> Double {
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

    private func overlaySegment(_ segs: [Seg], top: Double, bottom: Double, color: Color, mud: MudProperties?) -> [Seg] {
        var out: [Seg] = []
        for s in segs {
            if s.bottom <= top || s.top >= bottom {
                out.append(s)
            } else {
                if s.top < top {
                    out.append(Seg(top: s.top, bottom: top, color: s.color, mud: s.mud))
                }
                let oTop = max(s.top, top)
                let oBot = min(s.bottom, bottom)
                out.append(Seg(top: oTop, bottom: oBot, color: color, mud: mud))
                if s.bottom > bottom {
                    out.append(Seg(top: bottom, bottom: s.bottom, color: s.color, mud: s.mud))
                }
            }
        }
        return out
    }

#if DEBUG
    func exportDebugLog(project: ProjectState) {
        var lines: [String] = []
        func add(_ s: String) { lines.append(s) }
        add("=== Pump Schedule Debug Log ===")
        add("")
        let bitMD = max(
            project.annulus.map { $0.bottomDepth_m }.max() ?? 0,
            project.drillString.map { $0.bottomDepth_m }.max() ?? 0
        )
        add("Bit MD: \(bitMD) m")
        add("")

        let geom = ProjectGeometryService(project: project, currentStringBottomMD: bitMD)

        for (idx, st) in stages.enumerated() {
            add("Stage \(idx + 1): \(st.name)")
            add("  Side: \(st.side == .annulus ? "Annulus" : "String")")
            add("  Total volume: \(st.totalVolume_m3) m³")
            add("")

            if st.side == .string {
                let pV = max(0, st.totalVolume_m3)
                let Ls = geom.lengthForStringVolume_m(0.0, pV)
                add(String(format: "  For volume %.4f m³ → string length %.4f m", pV, Ls))

                var string: [Seg] = [Seg(top: 0, bottom: bitMD, color: project.activeMud?.color ?? .gray.opacity(0.35), mud: project.activeMud)]
                var annulus: [Seg] = [Seg(top: 0, bottom: bitMD, color: project.activeMud?.color ?? .gray.opacity(0.35), mud: project.activeMud)]
                for i in 0..<max(0, min(stageDisplayIndex, stages.count)) {
                    let pst = stages[i]
                    let pVol = max(0, pst.totalVolume_m3)
                    let Lprev = geom.lengthForStringVolume_m(0.0, pVol)
                    let takenPrev = takeFromBottom(string, length: Lprev, bitMD: bitMD, geom: geom)
                    string = injectAtSurfaceString(string, length: Lprev, color: pst.color, mud: pst.mud, bitMD: bitMD)

                    // Excess volume beyond what the string could provide exits the bit immediately
                    let takenVPrev = takenPrev.parcels.reduce(0.0) { $0 + max(0, $1.volume_m3) }
                    let excessPrev = max(0.0, pVol - takenVPrev)
                    var parcelsPrev = takenPrev.parcels
                    if excessPrev > 1e-9 {
                        parcelsPrev.append((volume_m3: excessPrev, color: pst.color, mud: pst.mud))
                    }
                    annulus = pushUpFromBitAnnulus(annulus, parcels: parcelsPrev, bitMD: bitMD, geom: geom)
                }

                let taken = takeFromBottom(string, length: Ls, bitMD: bitMD, geom: geom)
                add(String(format: "String length for current pumpedV (Ls): %.4f m", Ls))

                // Build parcels for the current stage including any excess volume
                var parcels = taken.parcels
                var sumParcels = parcels.reduce(0.0) { $0 + max(0, $1.volume_m3) }
                let excessV = max(0.0, pV - sumParcels)
                if excessV > 1e-9 {
                    parcels.append((volume_m3: excessV, color: st.color, mud: st.mud))
                    sumParcels += excessV
                }

                for (i, parcel) in parcels.enumerated() {
                    let mudName = parcel.mud?.name ?? "<active/unknown>"
                    add(String(format: "  Parcel[%02d] V=%.4f m³, mud=%@", i, parcel.volume_m3, mudName))
                }
                add(String(format: "  Sum parcel volume (including excess): %.4f m³", sumParcels))

                // Compute per-parcel lengths exactly as pushUpFromBitAnnulus does
                var lengths: [Double] = []
                var usedFromBottom: Double = 0
                for p in parcels {
                    let L = lengthForAnnulusParcelVolumeFromBottom(
                        volume: max(0, p.volume_m3),
                        bitMD: bitMD,
                        usedFromBottom: usedFromBottom,
                        geom: geom
                    )
                    lengths.append(L)
                    usedFromBottom += L
                }
                let totalL = usedFromBottom
                let achievedV = (totalL > 0)
                    ? geom.volumeInAnnulus_m3(max(0, bitMD - totalL), bitMD)
                    : 0.0

                add(String(format: "  Annulus totalL: %.4f m", totalL))
                for (i, L) in lengths.enumerated() {
                    add(String(format: "    length[%02d] = %.4f m", i, L))
                }
                add(String(format: "  Achieved annulus volume for [bit-totalL, bit]: %.4f m³", achievedV))
                add(String(format: "  Target parcel volume (including excess): %.4f m³", sumParcels))
            }

            add("")
        }

        // Write to a temp file
        let text = lines.joined(separator: "\n")
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        let fileURL = tmp.appendingPathComponent("PumpScheduleDebug_\(UUID().uuidString).txt")
        do {
            try text.data(using: .utf8)?.write(to: fileURL)
            print("[PumpSchedule] Debug export written to: \(fileURL.path)")
        } catch {
            print("[PumpSchedule] Failed writing debug export: \(error)")
        }
    }
#endif

    func hydraulicsForCurrent(project: ProjectState) -> HydraulicsReadout {
        // Guard
        let bitMD = max(
            project.annulus.map { $0.bottomDepth_m }.max() ?? 0,
            project.drillString.map { $0.bottomDepth_m }.max() ?? 0
        )
        let controlMD: Double = {
            switch controlDepthMode {
            case .bit: return bitMD
            case .custom: return max(0.0, min(controlMD_m, bitMD))
            }
        }()
        let controlTVD = project.tvd(of: controlMD)
        let g = 9.80665

        // Build current stacks to know which fluids are where
        let stg = currentStage(project: project)
        let totalV = stg?.totalVolume_m3 ?? 0
        let pumpedV = max(0.0, min(progress * max(totalV, 0), totalV))
        let stacks = stacksFor(project: project, stageIndex: stageDisplayIndex, pumpedV: pumpedV)

        // Helper to get annulus area and fluid density at MD
        let geom = ProjectGeometryService(project: project, currentStringBottomMD: bitMD)

        // Segment-exact hydrostatic (TVD) and segment-wise friction (MD)
        var annulusHydrostatic_Pa: Double = 0
        var stringHydrostatic_Pa: Double = 0
        var annulusFriction_Pa: Double = 0
        var stringFriction_Pa: Double = 0


        // Clip each annulus segment to [0, controlMD] and integrate
        for seg in stacks.annulus {
            let topMD = max(0.0, min(seg.top, controlMD))
            let botMD = max(0.0, min(seg.bottom, controlMD))
            if botMD <= topMD { continue }

            // Hydrostatic: integrate rho*g*dTVD between the TVDs of the clipped segment
            let tvdTop = project.tvd(of: topMD)
            let tvdBot = project.tvd(of: botMD)
            let dTVD = max(0.0, tvdBot - tvdTop)
            let rho = seg.mud?.density_kgm3 ?? 1260
            annulusHydrostatic_Pa += rho * g * dTVD

            // Friction: along the flow path (MD)
            let dMD = botMD - topMD
            let Q_m3s = max(pumpRate_m3permin, 0) / 60.0
            if Q_m3s > 0 && dMD > 0 {
                let mdMid = 0.5 * (topMD + botMD)
                let Do = max(geom.pipeOD_m(mdMid), 0.001)
                let Dhole = max(geom.holeOD_m(mdMid), Do + 0.0001)
                let Dh = max(Dhole - Do, 1e-6)
                let Aann = .pi * (Dhole * Dhole - Do * Do) / 4.0
                let Va = Q_m3s / max(Aann, 1e-12)

                // Power-law K/n: prefer annulus-specific lab fit if available,
                // otherwise fall back to 600/300 universal fit.
                var K: Double = 0
                var n: Double = 1
                if let m = seg.mud {
                    if let nAnn = m.n_annulus, let KAnn = m.K_annulus {
                        n = nAnn
                        K = KAnn
                    } else if let t600 = m.dial600, let t300 = m.dial300, t600 > 0, t300 > 0 {
                        n = log(t600/t300) / log(600.0/300.0)
                        let tau600 = 0.4788 * t600
                        let gamma600 = 1022.0
                        K = tau600 / pow(gamma600, n)
                    }
                }
                // Mooney–Rabinowitsch laminar ΔP/L (Pa/m)
                let gamma_w = ((3.0 * n + 1.0) / (4.0 * n)) * (8.0 * Va / Dh)
                let tau_w = K > 0 ? K * pow(gamma_w, n) : 0
                let dPperM = 4.0 * tau_w / Dh
                annulusFriction_Pa += dPperM * dMD
            }
        }

        // Clip each string segment to [0, controlMD] and integrate friction inside the drill string
        for seg in stacks.string {
            let topMD = max(0.0, min(seg.top, controlMD))
            let botMD = max(0.0, min(seg.bottom, controlMD))
            if botMD <= topMD { continue }

            let tvdTop = project.tvd(of: topMD)
            let tvdBot = project.tvd(of: botMD)
            let dTVD = max(0.0, tvdBot - tvdTop)
            let rhoString = seg.mud?.density_kgm3 ?? project.activeMudDensity_kgm3
            stringHydrostatic_Pa += rhoString * g * dTVD

            let dMD = botMD - topMD
            let Q_m3s = max(pumpRate_m3permin, 0) / 60.0
            if Q_m3s > 0 && dMD > 0 {
                let mdMid = 0.5 * (topMD + botMD)

                // Internal flow: use pipe ID and internal flow area
                let Di = max(geom.pipeID_m(mdMid), 0.001)
                let Apipe = .pi * Di * Di / 4.0
                let Vp = Q_m3s / max(Apipe, 1e-12)

                // Power-law K/n: prefer pipe-specific lab fit if available,
                // otherwise fall back to 600/300 universal fit.
                var K: Double = 0
                var n: Double = 1
                if let m = seg.mud {
                    if let nPipe = m.n_pipe, let KPipe = m.K_pipe {
                        n = nPipe
                        K = KPipe
                    } else if let t600 = m.dial600, let t300 = m.dial300, t600 > 0, t300 > 0 {
                        n = log(t600/t300) / log(600.0/300.0)
                        let tau600 = 0.4788 * t600
                        let gamma600 = 1022.0
                        K = tau600 / pow(gamma600, n)
                    }
                }
                // Mooney–Rabinowitsch laminar ΔP/L (Pa/m) for pipe flow
                let gamma_w = ((3.0 * n + 1.0) / (4.0 * n)) * (8.0 * Vp / Di)
                let tau_w = K > 0 ? K * pow(gamma_w, n) : 0
                let dPperM = 4.0 * tau_w / Di
                stringFriction_Pa += dPperM * dMD
            }
        }

        let ann_kPa = annulusFriction_Pa / 1000.0
        let str_kPa = stringFriction_Pa / 1000.0
        let totalFric_kPa = ann_kPa + str_kPa

        // MPD SBP to hit target EMD at control depth.
        // For bottomhole pressure, only annulus friction contributes (string friction is upstream of the bit).
        var sbp_kPa: Double = 0
        if mpdEnabled {
            let targetBHP_Pa = max(0, targetEMD_kgm3) * g * controlTVD
            let currentBHP_Pa = annulusHydrostatic_Pa + annulusFriction_Pa
            sbp_kPa = max(0, (targetBHP_Pa - currentBHP_Pa) / 1000.0)
        }

        let annulusAtControl_Pa = annulusHydrostatic_Pa + annulusFriction_Pa + sbp_kPa * 1000.0
        let stringAtControl_Pa  = stringHydrostatic_Pa + stringFriction_Pa
        let deltaStringMinusAnnulus_kPa = (stringAtControl_Pa - annulusAtControl_Pa) / 1000.0

        let bhp_kPa = (annulusHydrostatic_Pa / 1000) + sbp_kPa

        // Total circulating pressure at surface: all friction + any surface backpressure.
        let tcp_kPa = totalFric_kPa + sbp_kPa

        // ECD at control depth: only hydrostatic + annulus friction + SBP affect downhole pressure.
        let ecd_kgm3 = controlTVD > 0
        ? ((annulusHydrostatic_Pa + annulusFriction_Pa + sbp_kPa * 1000.0) / (g * controlTVD))
        : 0

        return HydraulicsReadout(
            annulusAtControl_Pa: annulusAtControl_Pa,
            stringAtControl_Pa: stringAtControl_Pa,
            annulusFriction_kPa: ann_kPa,
            stringFriction_kPa: str_kPa,
            totalFriction_kPa: totalFric_kPa,
            sbp_kPa: sbp_kPa,
            bhp_kPa: bhp_kPa,
            tcp_kPa: tcp_kPa,
            ecd_kgm3: ecd_kgm3
        )
    }

    func maxDepthMD(project: ProjectState) -> Double {
        max(
            project.annulus.map { $0.bottomDepth_m }.max() ?? 0,
            project.drillString.map { $0.bottomDepth_m }.max() ?? 0
        )
    }

    /// Computes a snapshot of fluids that have been expelled from the wellbore
    /// (i.e., pumped in but no longer present in string+annulus) for the
    /// current stage/progress. This is derived from volume balance rather than
    /// tracking discrete parcels over time.
    func expelledFluidsForCurrent(project: ProjectState) -> [ExpelledFluid] {
        // Determine bit depth and geometry
        let bitMD = max(
            project.annulus.map { $0.bottomDepth_m }.max() ?? 0,
            project.drillString.map { $0.bottomDepth_m }.max() ?? 0
        )
        let geom = ProjectGeometryService(project: project, currentStringBottomMD: bitMD)

        // Build current stacks (same as used for visualization/hydraulics)
        let stg = currentStage(project: project)
        let totalV = stg?.totalVolume_m3 ?? 0
        let pumpedVCurrent = max(0.0, min(progress * max(totalV, 0), totalV))
        let stacks = stacksFor(project: project, stageIndex: stageDisplayIndex, pumpedV: pumpedVCurrent)

        // 1) Volume currently in the well, grouped by mud id (including active base mud)
        var inWellByMud: [UUID?: Double] = [:]

        func addInWellVolume(from seg: Seg, isString: Bool) {
            let top = max(0.0, min(seg.top, bitMD))
            let bot = max(0.0, min(seg.bottom, bitMD))
            guard bot > top else { return }
            let vol: Double = isString
                ? geom.volumeInString_m3(top, bot)
                : geom.volumeInAnnulus_m3(top, bot)
            let key = seg.mud?.id
            inWellByMud[key, default: 0.0] += max(0.0, vol)
        }

        for seg in stacks.string {
            addInWellVolume(from: seg, isString: true)
        }
        for seg in stacks.annulus {
            addInWellVolume(from: seg, isString: false)
        }

        // 2) Initial in-hole volume by mud (currently only active mud fills the well)
        var initialByMud: [UUID?: Double] = [:]
        if let active = project.activeMud {
            let activeKey: UUID? = active.id
            let initStringV = geom.volumeInString_m3(0.0, bitMD)
            let initAnnV = geom.volumeInAnnulus_m3(0.0, bitMD)
            initialByMud[activeKey, default: 0.0] += max(0.0, initStringV + initAnnV)
        }

        // 3) Total pumped volume by mud from all stages up to the current point
        var pumpedByMud: [UUID?: Double] = [:]
        for i in stages.indices {
            let stage = stages[i]
            let mudKey = stage.mud?.id
            let totalStageV = max(0.0, stage.totalVolume_m3)
            let pumpedForStage: Double
            if i < stageDisplayIndex {
                // All previous stages are fully pumped
                pumpedForStage = totalStageV
            } else if i == stageDisplayIndex {
                // Current stage pumped fractionally based on progress
                pumpedForStage = max(0.0, min(progress, 1.0)) * totalStageV
            } else {
                pumpedForStage = 0.0
            }
            if pumpedForStage > 0 {
                pumpedByMud[mudKey, default: 0.0] += pumpedForStage
            }
        }

        // 4) Net expelled per mud = initial + pumped - inWell
        //    Only report positive expelled volumes.
        var result: [ExpelledFluid] = []

        // Build a set of all mud keys that appear in any of the maps
        var allKeys = Set<UUID?>()
        for k in initialByMud.keys { allKeys.insert(k) }
        for k in pumpedByMud.keys { allKeys.insert(k) }
        for k in inWellByMud.keys { allKeys.insert(k) }

        for key in allKeys {
            let initialV = initialByMud[key] ?? 0.0
            let pumpedV  = pumpedByMud[key] ?? 0.0
            let inWellV  = inWellByMud[key] ?? 0.0
            let netExpelled = max(0.0, initialV + pumpedV - inWellV)
            guard netExpelled > 1e-6 else { continue }

            // Resolve mud and color for this key
            let mud: MudProperties? = {
                if let id = key {
                    return project.muds.first(where: { $0.id == id })
                } else {
                    return nil
                }
            }()
            let color: Color = mud?.color ?? .gray.opacity(0.35)

            result.append(ExpelledFluid(mud: mud,
                                         color: color,
                                         volume_m3: netExpelled))
        }

        // Sort by volume descending for display
        result.sort { $0.volume_m3 > $1.volume_m3 }
        return result
    }

    #if DEBUG
    /// Debug snapshot based directly on the visual annulus stack.
    /// Uses the same segments and TVD mapping as the Well Snapshot view
    /// to compute per-layer and total hydrostatic pressure.
    func debugCurrentAnnulus(project: ProjectState) {
        let bitMD = max(
            project.annulus.map { $0.bottomDepth_m }.max() ?? 0,
            project.drillString.map { $0.bottomDepth_m }.max() ?? 0
        )

        let stg = currentStage(project: project)
        let totalV = stg?.totalVolume_m3 ?? 0
        let pumpedV = max(0.0, min(progress * max(totalV, 0), totalV))

        // Same stack as the visual
        let stacks = stacksFor(project: project,
                               stageIndex: stageDisplayIndex,
                               pumpedV: pumpedV)

        print("===== Annulus Stack Debug (Visual-Based HP) =====")
        print("Stage index: \(stageDisplayIndex) name: \(stg?.name ?? "<none>")")
        print(String(format: "Bit MD: %.1f m", bitMD))
        print(String(format: "Pumped volume: %.3f m³ (of %.3f m³)",
                     pumpedV, totalV))
        print("-- Annulus segments (as drawn) --")

        let g = 9.80665
        var totalHydrostatic_Pa: Double = 0

        for (i, seg) in stacks.annulus.enumerated() {
            let mudName = seg.mud?.name ?? "<active / unknown>"
            let rho = seg.mud?.density_kgm3 ?? project.activeMudDensity_kgm3

            // Use the same mapping as the visual: MD -> TVD
            let tvdTop = project.tvd(of: seg.top)
            let tvdBot = project.tvd(of: seg.bottom)
            let dTVD   = max(0.0, tvdBot - tvdTop)

            let dP = rho * g * dTVD
            totalHydrostatic_Pa += dP

            let colorDescription = String(describing: seg.color)

            print(String(
                format: "[%02d] MD %.1f–%.1f m, TVD %.1f–%.1f m, dTVD = %.1f m, mud = %@, ρ = %.0f kg/m³, dP = %.0f kPa, color = %@",
                i,
                seg.top,
                seg.bottom,
                tvdTop,
                tvdBot,
                dTVD,
                mudName,
                rho,
                dP / 1000.0,
                colorDescription
            ))
        }

        print(String(format: "Total hydrostatic from visual stack: %.0f kPa",
                     totalHydrostatic_Pa / 1000.0))
        print("===== End Annulus Stack Debug =====")
    }

    /// Exports a detailed debug log of the current stage behavior across progress steps
    /// to a text file in the temporary directory. Prints the file URL to the console.
    func exportAnnulusDebugLog(project: ProjectState) {
        let bitMD = max(
            project.annulus.map { $0.bottomDepth_m }.max() ?? 0,
            project.drillString.map { $0.bottomDepth_m }.max() ?? 0
        )
        let g = 9.80665

        var lines: [String] = []
        func add(_ s: String) { lines.append(s) }

        add("===== Pump Schedule Debug Export =====")
        add(String(format: "Bit MD: %.3f m", bitMD))
        add("Project active mud density: \(project.activeMudDensity_kgm3) kg/m³")
        add("")

        // Iterate over a set of progress samples for the current stage
        let samples = Array(stride(from: 0.0, through: 1.0, by: 0.05))
        for prog in samples {
            let oldProgress = self.progress
            self.progress = prog
            defer { self.progress = oldProgress }

            let stg = currentStage(project: project)
            let totalV = stg?.totalVolume_m3 ?? 0
            let pumpedV = max(0.0, min(progress * max(totalV, 0), totalV))

            add("===== Progress \(String(format: "%.0f%%", prog * 100)) =====")
            add("Stage: \(stg?.name ?? "<none>")")
            add(String(format: "Pumped volume: %.3f m³ (of %.3f m³)", pumpedV, totalV))

            let stacks = stacksFor(project: project, stageIndex: stageDisplayIndex, pumpedV: pumpedV)
            var totalHP_Pa: Double = 0

            add("Annulus segments:")
            for (i, seg) in stacks.annulus.enumerated() {
                let mudName = seg.mud?.name ?? "<active>"
                let rho = seg.mud?.density_kgm3 ?? project.activeMudDensity_kgm3
                let tvdTop = project.tvd(of: seg.top)
                let tvdBot = project.tvd(of: seg.bottom)
                let dTVD = max(0.0, tvdBot - tvdTop)
                let dP = rho * g * dTVD
                totalHP_Pa += dP

                add(String(format: "  [%02d] MD %.1f–%.1f, TVD %.1f–%.1f (dTVD %.1f m), %@, ρ=%.0f, dP=%.0f kPa",
                           i, seg.top, seg.bottom, tvdTop, tvdBot, dTVD, mudName, rho, dP / 1000.0))
            }
            add(String(format: "Total annulus hydrostatic: %.0f kPa", totalHP_Pa / 1000.0))
            add("")
        }

        // Write to a temp file
        let text = lines.joined(separator: "\n")
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        let fileURL = tmp.appendingPathComponent("PumpScheduleDebug_\(UUID().uuidString).txt")
        do {
            try text.data(using: .utf8)?.write(to: fileURL)
            print("[PumpSchedule] Debug export written to: \(fileURL.path)")
        } catch {
            print("[PumpSchedule] Failed writing debug export: \(error)")
        }
    }
    #endif
}

// MARK: - Supporting Types
struct ExpelledFluid: Identifiable {
    let id = UUID()
    let mud: MudProperties?
    let color: Color
    let volume_m3: Double

    var mudName: String {
        mud?.name ?? "Unknown"
    }
}

// MARK: - Hydraulics Readout
struct HydraulicsReadout {
    let annulusAtControl_Pa: Double
    let stringAtControl_Pa: Double
    let annulusFriction_kPa: Double
    let stringFriction_kPa: Double
    let totalFriction_kPa: Double
    let sbp_kPa: Double
    let bhp_kPa: Double
    let tcp_kPa: Double
    let ecd_kgm3: Double
}
