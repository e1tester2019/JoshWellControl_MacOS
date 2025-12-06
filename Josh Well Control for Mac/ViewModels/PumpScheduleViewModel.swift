//
//  PumpScheduleViewModel.swift
//  Josh Well Control
//
//  ViewModel for pump schedule simulation
//

import Foundation
import SwiftUI
import Observation
import SwiftData

@Observable
class PumpScheduleViewModel {
    enum Side { case annulus, string }
    private(set) var context: ModelContext?
    private var didBootstrap = false

    struct Stage {
        let name: String
        let color: Color
        let totalVolume_m3: Double
        let side: Side
        let mud: MudProperties?
    }

    var stages: [Stage] = []
    var stageIndex: Int = 0
    var progress: Double = 0 {
        didSet {
            if let p = boundProject {
                updateHydraulics(project: p)
            }
        }
    }
    var stageDisplayIndex: Int { min(max(stageIndex, 0), max(stages.count - 1, 0)) }

    // Hydraulics inputs
    var pumpRate_m3permin: Double = 0.50
    var mpdEnabled: Bool = false
    var targetEMD_kgm3: Double = 1300
    var controlMD_m: Double = 0
    
    // MARK: - Live hydraulics outputs (bind the UI to these)
    var annulusAtControl_kPa: Double = 0
    var stringAtControl_kPa: Double = 0
    var annulusFriction_kPa: Double = 0
    var stringFriction_kPa: Double = 0
    var totalFriction_kPa: Double = 0
    var sbp_kPa: Double = 0
    var bhp_kPa: Double = 0
    var tcp_kPa: Double = 0
    var ecd_kgm3: Double = 0

    // Hold onto the current project so we can refresh automatically on progress changes.
    var boundProject: ProjectState?

    func bind(project: ProjectState) {
        boundProject = project
        updateHydraulics(project: project)
    }

    func updateHydraulics(project: ProjectState) {
        let h = hydraulicsForCurrent(project: project)
        annulusAtControl_kPa = h.annulusAtControl_Pa / 1000.0
        stringAtControl_kPa  = h.stringAtControl_Pa  / 1000.0
        annulusFriction_kPa  = h.annulusFriction_kPa
        stringFriction_kPa   = h.stringFriction_kPa
        totalFriction_kPa    = h.totalFriction_kPa
        sbp_kPa              = h.sbp_kPa
        bhp_kPa              = h.bhp_kPa
        tcp_kPa              = h.tcp_kPa
        ecd_kgm3             = h.ecd_kgm3
    }

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
        program = (project.programStages ?? [])
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
        if project.programStages == nil { project.programStages = [] }
        for s in (project.programStages ?? []) { byID[s.id] = s }

        // Track the next order index
        let maxOrder = (project.programStages ?? []).map { $0.orderIndex }.max() ?? -1
        var nextOrder = maxOrder + 1

        // Delete removed
        let desiredIDs = Set(program.map { $0.id })
        project.programStages?.removeAll { !desiredIDs.contains($0.id) }

        // Update existing and add new, maintaining orderIndex
        for stage in program {
            if let existing = byID[stage.id] {
                existing.name = stage.name
                existing.volume_m3 = stage.volume_m3
                existing.pumpRate_m3permin = stage.pumpRate_m3permin
                existing.color = stage.color
                existing.mud = stage.mudID.flatMap { id in (project.muds ?? []).first(where: { $0.id == id }) }
                // keep existing.orderIndex as-is
            } else {
                let mud = stage.mudID.flatMap { id in (project.muds ?? []).first(where: { $0.id == id }) }
                let s = PumpProgramStage(name: stage.name,
                                         volume_m3: stage.volume_m3,
                                         pumpRate_m3permin: stage.pumpRate_m3permin,
                                         color: stage.color,
                                         project: project,
                                         mud: mud)
                s.id = stage.id
                s.orderIndex = nextOrder
                nextOrder += 1
                project.programStages?.append(s)
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
            (project.annulus ?? []).map { $0.bottomDepth_m }.max() ?? 0,
            (project.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0
        )
        let geom = ProjectGeometryService(project: project, currentStringBottomMD: bitMD)
        let activeMud = project.activeMud
        // Annulus first – order by shallow to deep (top MD ascending)
        let ann = (project.finalLayers ?? []).filter { $0.placement == .annulus || $0.placement == .both }
            .sorted { min($0.topMD_m, $0.bottomMD_m) < min($1.topMD_m, $1.bottomMD_m) }
        for L in ann {
            let t = min(L.topMD_m, L.bottomMD_m)
            let b = max(L.topMD_m, L.bottomMD_m)
            let vol = geom.volumeInAnnulus_m3(t, b)
            let col = L.mud?.color ?? L.color
            stages.append(Stage(name: L.name, color: col, totalVolume_m3: vol, side: .annulus, mud: L.mud ?? activeMud))
        }
        // Then string – order deepest to shallowest as per spec
        let str = (project.finalLayers ?? []).filter { $0.placement == .string || $0.placement == .both }
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
        return (project.muds ?? []).first(where: { $0.id == id }) ?? project.activeMud
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
        updateHydraulics(project: project)
    }

    func bootstrap(project: ProjectState, context: ModelContext) {
        guard !didBootstrap else { return }
        self.context = context
        self.bind(project: project)
        self.loadProgram(from: project)
        self.buildStages(project: project)
        self.updateHydraulics(project: project)
        didBootstrap = true
    }

    // Keep your existing bootstrap(project:) if still used elsewhere
    func bootstrap(project: ProjectState) {
        self.bind(project: project)
        self.loadProgram(from: project)
        self.buildStages(project: project)
        self.updateHydraulics(project: project)
    }

    func nextStageOrWrap() {
        if progress >= 0.9999 {
            stageIndex = min(stageIndex + 1, max(stages.count - 1, 0))
            progress = 0
        } else {
            progress = 1
        }
        if let p = boundProject { updateHydraulics(project: p) }
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

    private func totalVolume(_ parcels: [VolumeParcel]) -> Double {
        parcels.reduce(0.0) { $0 + max(0.0, $1.volume_m3) }
    }

    /// Push a parcel into the top of the string (surface) and compute overflow from the bottom (bit).
    /// `stringParcels` is ordered shallow (index 0) -> deep (last).
    /// `expelled` is appended in the order it exits the bit.
    private func pushToTopAndOverflow(
        stringParcels: inout [VolumeParcel],
        add: VolumeParcel,
        capacity_m3: Double,
        expelled: inout [VolumeParcel]
    ) {
        let addV = max(0.0, add.volume_m3)
        guard addV > 1e-12 else { return }

        // Add to top (surface)
        stringParcels.insert(VolumeParcel(volume_m3: addV, color: add.color, mud: add.mud), at: 0)

        // Overflow exits at the bottom (bit)
        var overflow = totalVolume(stringParcels) - max(0.0, capacity_m3)
        while overflow > 1e-9, let last = stringParcels.last {
            stringParcels.removeLast()
            let v = max(0.0, last.volume_m3)
            if v <= overflow + 1e-9 {
                expelled.append(last)
                overflow -= v
            } else {
                // Split the bottom parcel: part expelled, remainder stays in the string
                expelled.append(VolumeParcel(volume_m3: overflow, color: last.color, mud: last.mud))
                stringParcels.append(VolumeParcel(volume_m3: v - overflow, color: last.color, mud: last.mud))
                overflow = 0
            }
        }
    }

    /// Push a parcel into the bottom of the annulus (bit) and compute overflow out the top (surface).
    /// `annulusParcels` is ordered deep (index 0, at bit) -> shallow (last, at surface).
    /// `overflowAtSurface` is appended in the order it would leave the surface.
    private func pushToBottomAndOverflowTop(
        annulusParcels: inout [VolumeParcel],
        add: VolumeParcel,
        capacity_m3: Double,
        overflowAtSurface: inout [VolumeParcel]
    ) {
        let addV = max(0.0, add.volume_m3)
        guard addV > 1e-12 else { return }

        // Add to bottom (bit)
        annulusParcels.insert(VolumeParcel(volume_m3: addV, color: add.color, mud: add.mud), at: 0)

        // Overflow leaves at the top (surface)
        var overflow = totalVolume(annulusParcels) - max(0.0, capacity_m3)
        while overflow > 1e-9, let last = annulusParcels.last {
            annulusParcels.removeLast()
            let v = max(0.0, last.volume_m3)
            if v <= overflow + 1e-9 {
                overflowAtSurface.append(last)
                overflow -= v
            } else {
                // Split the top parcel: part overflows, remainder stays in annulus
                overflowAtSurface.append(VolumeParcel(volume_m3: overflow, color: last.color, mud: last.mud))
                annulusParcels.append(VolumeParcel(volume_m3: v - overflow, color: last.color, mud: last.mud))
                overflow = 0
            }
        }
    }

    /// Convert a deep->shallow annulus volume parcel stack into MD segments from bit upward.
    private func segmentsFromAnnulusParcels(
        _ parcels: [VolumeParcel],
        bitMD: Double,
        geom: ProjectGeometryService,
        fallbackMud: MudProperties?
    ) -> [Seg] {
        var segs: [Seg] = []
        var usedFromBottom: Double = 0.0
        for p in parcels {
            let v = max(0.0, p.volume_m3)
            guard v > 1e-12 else { continue }
            let L = lengthForAnnulusParcelVolumeFromBottom(volume: v, bitMD: bitMD, usedFromBottom: usedFromBottom, geom: geom)
            if L <= 1e-12 { continue }
            let topMD = max(0.0, bitMD - usedFromBottom - L)
            let botMD = max(0.0, bitMD - usedFromBottom)
            if botMD > topMD + 1e-9 {
                segs.append(Seg(top: topMD, bottom: botMD, color: p.color, mud: p.mud ?? fallbackMud))
                usedFromBottom += L
            }
            if usedFromBottom >= bitMD - 1e-9 { break }
        }
        // segs currently go bottom-up; return shallow->deep ordering
        return segs.sorted { $0.top < $1.top }
    }

    /// Convert a shallow->deep string volume parcel stack into MD segments from surface downward.
    private func segmentsFromStringParcels(
        _ parcels: [VolumeParcel],
        bitMD: Double,
        geom: ProjectGeometryService,
        fallbackMud: MudProperties?
    ) -> [Seg] {
        var segs: [Seg] = []
        var currentTop: Double = 0.0

        for p in parcels {
            let v = max(0.0, p.volume_m3)
            guard v > 1e-12 else { continue }

            let L = geom.lengthForStringVolume_m(0.0, v)
            guard L > 1e-12 else { continue }

            let bottom = min(currentTop + L, bitMD)
            if bottom > currentTop + 1e-9 {
                segs.append(Seg(top: currentTop, bottom: bottom, color: p.color, mud: p.mud ?? fallbackMud))
                currentTop = bottom
            }

            if currentTop >= bitMD - 1e-9 { break }
        }

        return segs
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
            (project.annulus ?? []).map { $0.bottomDepth_m }.max() ?? 0,
            (project.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0
        )
        let geom = ProjectGeometryService(project: project, currentStringBottomMD: bitMD)

        // Initial active mud fills both
        var string: [Seg] = [Seg(top: 0, bottom: bitMD, color: project.activeMud?.color ?? .gray.opacity(0.35), mud: project.activeMud)]
        var annulus: [Seg] = [Seg(top: 0, bottom: bitMD, color: project.activeMud?.color ?? .gray.opacity(0.35), mud: project.activeMud)]

        // Keep a volume-accurate annulus parcel stack so that fluid exiting the bit becomes
        // the new bottom-most fluid and pushes older fluids upward toward surface.
        let activeColor = project.activeMud?.color ?? .gray.opacity(0.35)
        let activeMud = project.activeMud
        let annulusCapacity_m3 = geom.volumeInAnnulus_m3(0.0, bitMD)
        var annulusParcelsDeepToShallow: [VolumeParcel] = [
            VolumeParcel(volume_m3: max(0.0, annulusCapacity_m3), color: activeColor, mud: activeMud)
        ]
        var overflowAtSurface: [VolumeParcel] = []

        // Process all stages up to current, including partial progress of current stage
        // We need to handle ALL pumped volume cumulatively
        var totalPumpedVolume: Double = 0
        var pumpSequence: [(id: Int, volume: Double, color: Color, mud: MudProperties?)] = []
        
        // Collect all pumped volumes in order
        for i in 0...stageIndex {
            guard i < stages.count else { break }
            let st = stages[i]
            
            if st.side == .string {
                let vol: Double
                if i < stageIndex {
                    // Previous stages: fully pumped
                    vol = max(0, st.totalVolume_m3)
                } else {
                    // Current stage: partially pumped
                    vol = pumpedV
                }
                
                if vol > 0 {
                    pumpSequence.append((id: i, volume: vol, color: st.color, mud: st.mud))
                    totalPumpedVolume += vol
                }
            } else if st.side == .annulus {
                // Annulus-only pumping: inject at surface (top) and displace downward.
                let vol = i < stageIndex ? max(0, st.totalVolume_m3) : pumpedV
                if vol > 0 {
                    // annulusParcelsDeepToShallow: deep->shallow, so surface is the LAST parcel.
                    annulusParcelsDeepToShallow.append(VolumeParcel(volume_m3: vol, color: st.color, mud: st.mud))

                    // Enforce capacity by overflowing out the bottom (bit side) for now.
                    // (We are not tracking what leaves the bit in annulus-injection mode.)
                    var overflow = totalVolume(annulusParcelsDeepToShallow) - annulusCapacity_m3
                    while overflow > 1e-9, !annulusParcelsDeepToShallow.isEmpty {
                        var first = annulusParcelsDeepToShallow.removeFirst()
                        let v = max(0.0, first.volume_m3)
                        if v <= overflow + 1e-9 {
                            overflow -= v
                        } else {
                            first.volume_m3 = v - overflow
                            annulusParcelsDeepToShallow.insert(first, at: 0)
                            overflow = 0
                        }
                    }
                }
            }
        }
        
        // Now simulate the continuous flow through string -> annulus
        if totalPumpedVolume > 0 {
            // String capacity (in volume)
            let stringCapacity_m3 = geom.volumeInString_m3(0.0, bitMD)

            // Model the string as a finite-capacity FIFO volume stack.
            // Parcels are ordered shallow (surface) -> deep (bit).
            var stringParcels: [VolumeParcel] = [
                VolumeParcel(volume_m3: max(0.0, stringCapacity_m3), color: activeColor, mud: activeMud)
            ]
            var expelledAtBit: [VolumeParcel] = []

            // Replay pumped sequence in chronological order. Each pumped parcel enters at surface;
            // any overflow exits at the bit and must be added to the annulus from the bottom up.
            for entry in pumpSequence {
                pushToTopAndOverflow(
                    stringParcels: &stringParcels,
                    add: VolumeParcel(volume_m3: max(0.0, entry.volume), color: entry.color, mud: entry.mud),
                    capacity_m3: stringCapacity_m3,
                    expelled: &expelledAtBit
                )
            }

            // Build string segments from the parcel stack.
            // (Note: this uses the same volume->length mapping you already use elsewhere.)
            string = segmentsFromStringParcels(stringParcels, bitMD: bitMD, geom: geom, fallbackMud: activeMud)

            // Ensure the string is fully filled to bitMD (numerical guard)
            if let last = string.last, last.bottom < bitMD - 1e-6 {
                string.append(Seg(top: last.bottom, bottom: bitMD, color: activeColor, mud: activeMud))
            } else if string.isEmpty {
                string = [Seg(top: 0, bottom: bitMD, color: activeColor, mud: activeMud)]
            }

            // Any expelled parcels exit at the bit. They must become the NEW bottom-most fluid in the annulus,
            // pushing older annulus fluids upward. Model the annulus as a finite-capacity stack with inflow at bottom.
            if !expelledAtBit.isEmpty {
                for p in expelledAtBit {
                    pushToBottomAndOverflowTop(
                        annulusParcels: &annulusParcelsDeepToShallow,
                        add: p,
                        capacity_m3: annulusCapacity_m3,
                        overflowAtSurface: &overflowAtSurface
                    )
                }
            }

            // Rebuild annulus segments from the parcel stack.
            annulus = segmentsFromAnnulusParcels(annulusParcelsDeepToShallow, bitMD: bitMD, geom: geom, fallbackMud: activeMud)
        }

        // If there was only annulus-side pumping (no string pumping), ensure annulus matches its parcel stack.
        if totalPumpedVolume <= 0 {
            annulus = segmentsFromAnnulusParcels(annulusParcelsDeepToShallow, bitMD: bitMD, geom: geom, fallbackMud: activeMud)
        }

        return StackState(string: merge(string), annulus: merge(annulus))
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
    
    private func injectAtSurfaceAnnulus(_ segs: [Seg], length: Double, color: Color, mud: MudProperties?, bitMD: Double) -> [Seg] {
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

    private func pushUpFromBitAnnulus(_ segs: [Seg], parcels: [(id: Int?, volume_m3: Double, color: Color, mud: MudProperties?)], bitMD: Double, geom: ProjectGeometryService) -> [Seg] {
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
            (project.annulus ?? []).map { $0.bottomDepth_m }.max() ?? 0,
            (project.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0
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
                    var parcelsPrev: [(id: Int?, volume_m3: Double, color: Color, mud: MudProperties?)] = takenPrev.parcels.map { (id: nil, volume_m3: $0.volume_m3, color: $0.color, mud: $0.mud) }
                    if excessPrev > 1e-9 {
                        parcelsPrev.append((id: nil, volume_m3: excessPrev, color: pst.color, mud: pst.mud))
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
            (project.annulus ?? []).map { $0.bottomDepth_m }.max() ?? 0,
            (project.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0
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
        let _deltaStringMinusAnnulus_kPa = (stringAtControl_Pa - annulusAtControl_Pa) / 1000.0 // Computed but unused

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
            (project.annulus ?? []).map { $0.bottomDepth_m }.max() ?? 0,
            (project.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0
        )
    }

    /// Computes a snapshot of fluids that have been expelled from the wellbore
    /// (i.e., pumped in but no longer present in string+annulus) for the
    /// current stage/progress. This is derived from volume balance rather than
    /// tracking discrete parcels over time.
    func expelledFluidsForCurrent(project: ProjectState) -> [ExpelledFluid] {
        // Determine bit depth and geometry
        let bitMD = max(
            (project.annulus ?? []).map { $0.bottomDepth_m }.max() ?? 0,
            (project.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0
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
                    return (project.muds ?? []).first(where: { $0.id == id })
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
            (project.annulus ?? []).map { $0.bottomDepth_m }.max() ?? 0,
            (project.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0
        )

        let stg = currentStage(project: project)
        let totalV = stg?.totalVolume_m3 ?? 0
        let pumpedV = max(0.0, min(progress * max(totalV, 0), totalV))

        // Same stack as the visual
        let stacks = stacksFor(project: project,
                               stageIndex: stageDisplayIndex,
                               pumpedV: pumpedV)

        print("===== Annulus Stack Debug (Visual-Based HP) =====")
        print("Stage index: \(stageDisplayIndex) name: \(stg?.name ?? "<none>") side: \(stg?.side == .annulus ? "ANNULUS" : "STRING")")
        print(String(format: "Bit MD: %.1f m", bitMD))
        print(String(format: "Pumped volume: %.3f m³ (of %.3f m³) = %.0f%%",
                     pumpedV, totalV, (totalV > 0 ? pumpedV/totalV : 0) * 100))
        
        print("\n-- String segments --")
        for (i, seg) in stacks.string.enumerated() {
            let mudName = seg.mud?.name ?? "<active / unknown>"
            let tvdTop = project.tvd(of: seg.top)
            let tvdBot = project.tvd(of: seg.bottom)
            print(String(
                format: "[%02d] MD %.1f–%.1f m, TVD %.1f–%.1f m, mud = %@, color = %@",
                i, seg.top, seg.bottom, tvdTop, tvdBot, mudName, String(describing: seg.color)
            ))
        }
        
        print("\n-- Annulus segments (as drawn) --")

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

        print(String(format: "\nTotal hydrostatic from visual stack: %.0f kPa",
                     totalHydrostatic_Pa / 1000.0))
        
        // Show what takeFromBottom would do
        let geom = ProjectGeometryService(project: project, currentStringBottomMD: bitMD)
        let L = geom.lengthForStringVolume_m(0.0, pumpedV)
        print(String(format: "\nString displacement length for %.3f m³: %.1f m", pumpedV, L))
        print(String(format: "This is %.1f%% of bit depth (%.1f m)", (L/bitMD)*100, bitMD))
        
        let taken = takeFromBottom(stacks.string, length: L, bitMD: bitMD, geom: geom)
        print("\nParcels taken from string bottom:")
        for (i, p) in taken.parcels.enumerated() {
            let mudName = p.mud?.name ?? "<unknown>"
            print(String(format: "  [%02d] %.3f m³ of %@", i, p.volume_m3, mudName))
        }
        let takenV = taken.parcels.reduce(0.0) { $0 + max(0, $1.volume_m3) }
        let excess = max(0.0, pumpedV - takenV)
        print(String(format: "Total taken: %.3f m³, Excess: %.3f m³", takenV, excess))
        
        print("===== End Annulus Stack Debug =====\n")
    }

    /// Exports a detailed debug log of the current stage behavior across progress steps
    /// to a text file in the temporary directory. Prints the file URL to the console.
    func exportAnnulusDebugLog(project: ProjectState) {
        let bitMD = max(
            (project.annulus ?? []).map { $0.bottomDepth_m }.max() ?? 0,
            (project.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0
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
