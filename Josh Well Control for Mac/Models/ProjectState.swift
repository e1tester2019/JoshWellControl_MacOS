//
//  ProjectState.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//

import Foundation
import SwiftData
import SwiftUI

@Model
final class ProjectState {
    var id: UUID = UUID()

    // NEW — versioning & well linkage
    var name: String = "Baseline"
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var basedOnProjectID: UUID? = nil
    var isDashboardLocked: Bool = false

    @Relationship var well: Well?

    // Collections - all optional for CloudKit compatibility
    @Relationship(deleteRule: .nullify, inverse: \SurveyStation.project) var surveys: [SurveyStation]?
    @Relationship(deleteRule: .nullify, inverse: \DrillStringSection.project) var drillString: [DrillStringSection]?
    @Relationship(deleteRule: .nullify, inverse: \AnnulusSection.project) var annulus: [AnnulusSection]?
    @Relationship(deleteRule: .nullify, inverse: \MudStep.project) var mudSteps: [MudStep]?
    @Relationship(deleteRule: .nullify, inverse: \FinalFluidLayer.project) var finalLayers: [FinalFluidLayer]?
    @Relationship(deleteRule: .nullify, inverse: \MudProperties.project) var muds: [MudProperties]?
    @Relationship(deleteRule: .nullify, inverse: \PumpProgramStage.project) var programStages: [PumpProgramStage]?
    @Relationship(deleteRule: .nullify, inverse: \SwabRun.project) var swabRuns: [SwabRun]?
    @Relationship(deleteRule: .nullify, inverse: \TripRun.project) var tripRuns: [TripRun]?
    @Relationship(deleteRule: .nullify, inverse: \CementJob.project) var cementJobs: [CementJob]?
    @Relationship(deleteRule: .nullify, inverse: \TripSimulation.project) var tripSimulations: [TripSimulation]?
    @Relationship(deleteRule: .nullify, inverse: \TripInSimulation.project) var tripInSimulations: [TripInSimulation]?
    @Relationship(deleteRule: .nullify, inverse: \MPDSheet.project) var mpdSheets: [MPDSheet]?
    @Relationship(deleteRule: .nullify, inverse: \WellTask.project) var tasks: [WellTask]?
    @Relationship(deleteRule: .nullify, inverse: \HandoverNote.project) var notes: [HandoverNote]?

    // Singletons - Internal storage MUST be @Relationship to match inverse declarations
    @Relationship(deleteRule: .nullify) var _window: PressureWindow?
    @Relationship(deleteRule: .nullify) var _slug: SlugPlan?
    @Relationship(deleteRule: .nullify) var _backfill: BackfillPlan?
    @Relationship(deleteRule: .nullify) var _settings: TripSettings?
    @Relationship(deleteRule: .nullify) var _swab: SwabInput?
    @Relationship(deleteRule: .nullify) var _directionalLimits: DirectionalLimits?

    // Public non-optional accessors for backward compatibility
    @Transient var window: PressureWindow {
        get {
            if let w = _window { return w }
            let w = PressureWindow()
            _window = w
            return w
        }
        set { _window = newValue }
    }

    @Transient var slug: SlugPlan {
        get {
            if let s = _slug { return s }
            let s = SlugPlan()
            _slug = s
            return s
        }
        set { _slug = newValue }
    }

    @Transient var backfill: BackfillPlan {
        get {
            if let b = _backfill { return b }
            let b = BackfillPlan()
            _backfill = b
            return b
        }
        set { _backfill = newValue }
    }

    @Transient var settings: TripSettings {
        get {
            if let s = _settings { return s }
            let s = TripSettings()
            _settings = s
            return s
        }
        set { _settings = newValue }
    }

    @Transient var swab: SwabInput {
        get {
            if let s = _swab { return s }
            let s = SwabInput()
            _swab = s
            return s
        }
        set { _swab = newValue }
    }

    @Transient var directionalLimits: DirectionalLimits {
        get {
            if let d = _directionalLimits { return d }
            let d = DirectionalLimits()
            _directionalLimits = d
            return d
        }
        set { _directionalLimits = newValue }
    }

    var baseAnnulusDensity_kgm3: Double = 1260
    var baseStringDensity_kgm3: Double = 1260
    var pressureDepth_m: Double = 3200
    var activeMudDensity_kgm3: Double = 1260
    var activeMudVolume_m3: Double = 56.5
    var surfaceLineVolume_m3: Double = 1.4

    // Survey calculation settings
    var vsdDirection_deg: Double = 0.0  // Vertical Section Direction (reference azimuth for VS calculation)

    init() {
        // Initialize singletons so they're never nil
        self._window = PressureWindow()
        self._slug = SlugPlan()
        self._backfill = BackfillPlan()
        self._settings = TripSettings()
        self._swab = SwabInput()
        self._directionalLimits = DirectionalLimits()
    }
}
extension ProjectState {
    /// TVD at an arbitrary MD using linear interpolation over `surveys`.
    func tvd(of mdQuery: Double) -> Double {
        guard !(surveys ?? []).isEmpty else { return mdQuery } // fallback
        // Sort once per call (fast enough, or cache if you like)
        let s = (surveys ?? []).sorted { $0.md < $1.md }

        if mdQuery <= s.first!.md { return s.first!.tvd ?? 0 }
        if mdQuery >= s.last!.md  { return s.last!.tvd ?? 0 }

        // Binary search for bracketing indices
        var lo = 0, hi = s.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if s[mid].md <= mdQuery { lo = mid } else { hi = mid }
        }

        let md0 = s[lo].md,  md1 = s[hi].md
        let tv0 = s[lo].tvd, tv1 = s[hi].tvd
        let t = (mdQuery - md0) / max(md1 - md0, 1e-12)
        return (tv0 ?? 0.0) + t * ((tv1 ?? 0.0) - (tv0 ?? 0.0))
    }
}

extension ProjectState {
    var finalAnnulusLayersSorted: [FinalFluidLayer] {
        (finalLayers ?? []).filter { $0.placement == .annulus }.sorted { $0.topMD_m < $1.topMD_m }
    }
    var finalStringLayersSorted: [FinalFluidLayer] {
        (finalLayers ?? []).filter { $0.placement == .string }.sorted { $0.topMD_m < $1.topMD_m }
    }
}

extension ProjectState {
    /// Update the timestamp when you mutate state.
    func touchUpdated() {
        self.updatedAt = .now
    }

    /// Replace the persisted final layers with a new set and save.
    /// Call this from Mud Placement after committing a run.
    func replaceFinalLayers(with newLayers: [FinalFluidLayer], using context: ModelContext) {
        if self.finalLayers == nil { self.finalLayers = [] }
        self.finalLayers?.removeAll()
        self.finalLayers?.append(contentsOf: newLayers)
        self.updatedAt = .now
        try? context.save()
    }

    /// Create a shallow snapshot of this project under the provided well.
    /// Collections (surveys, drillString, annulus, mudSteps, finalLayers) are NOT copied here.
    /// Use `deepClone(into:using:)` if you want a full snapshot.
    func shallowClone(into well: Well, using context: ModelContext) -> ProjectState {
        let p = ProjectState()
        p.name = self.name + " (Copy)"
        p.baseAnnulusDensity_kgm3 = self.baseAnnulusDensity_kgm3
        p.baseStringDensity_kgm3 = self.baseStringDensity_kgm3
        p.pressureDepth_m = self.pressureDepth_m
        p.well = well
        if well.projects == nil { well.projects = [] }
        well.projects?.append(p)
        try? context.save()
        return p
    }

    /// Full snapshot: duplicates major collections and reattaches to the new project under `well`.
    /// Assumes element initializers with settable properties exist for each model type.
    func deepClone(into well: Well, using context: ModelContext) -> ProjectState {
        let p = shallowClone(into: well, using: context)

        p.activeMudDensity_kgm3 = self.activeMudDensity_kgm3
        p.activeMudVolume_m3 = self.activeMudVolume_m3
        p.surfaceLineVolume_m3 = self.surfaceLineVolume_m3
        p.vsdDirection_deg = self.vsdDirection_deg
        p.basedOnProjectID = self.id
        p.createdAt = .now

        // --- Clone MUDS first and build an old->new map by ID ---
        var mudMap: [UUID: MudProperties] = [:]
        if p.muds == nil { p.muds = [] }
        for m0 in (self.muds ?? []) {
            let m = MudProperties(
                name: m0.name,
                density_kgm3: m0.density_kgm3,
                pv_Pa_s: m0.pv_Pa_s,
                yp_Pa: m0.yp_Pa,
                n_powerLaw: m0.n_powerLaw,
                k_powerLaw_Pa_s_n: m0.k_powerLaw_Pa_s_n,
                tau0_Pa: m0.tau0_Pa,
                rheologyModel: m0.rheologyModel,
                gel10s_Pa: m0.gel10s_Pa,
                gel10m_Pa: m0.gel10m_Pa,
                thermalExpCoeff_perC: m0.thermalExpCoeff_perC,
                compressibility_perkPa: m0.compressibility_perkPa,
                gasCutFraction: m0.gasCutFraction,
                dial600: m0.dial600,
                dial300: m0.dial300,
                color: Color(red: m0.colorR, green: m0.colorG, blue: m0.colorB, opacity: m0.colorA),
                project: p
            )
            m.isActive = m0.isActive
            p.muds?.append(m)
            mudMap[m0.id] = m
        }

        // --- Surveys ---
        if p.surveys == nil { p.surveys = [] }
        for s0 in (self.surveys ?? []) {
            let s = SurveyStation(
                md: s0.md,
                inc: s0.inc,
                azi: s0.azi,
                tvd: s0.tvd,
                vs_m: s0.vs_m,
                ns_m: s0.ns_m,
                ew_m: s0.ew_m,
                dls_deg_per30m: s0.dls_deg_per30m,
                subsea_m: s0.subsea_m,
                buildRate_deg_per30m: s0.buildRate_deg_per30m,
                turnRate_deg_per30m: s0.turnRate_deg_per30m,
                vsd_direction_deg: s0.vsd_direction_deg,
                sourceFileName: s0.sourceFileName
            )
            s.project = p
            p.surveys?.append(s)
        }

        // --- Drill string ---
        if p.drillString == nil { p.drillString = [] }
        for d0 in (self.drillString ?? []) {
            let d = DrillStringSection(
                name: d0.name,
                topDepth_m: d0.topDepth_m,
                length_m: d0.length_m,
                outerDiameter_m: d0.outerDiameter_m,
                innerDiameter_m: d0.innerDiameter_m,
                toolJointOD_m: d0.toolJointOD_m,
                jointLength_m: d0.jointLength_m,
                grade: d0.grade,
                steelDensity_kg_per_m3: d0.steelDensity_kg_per_m3,
                unitWeight_kg_per_m: d0.unitWeight_kg_per_m,
                internalRoughness_m: d0.internalRoughness_m,
                project: p
            )
            p.drillString?.append(d)
        }

        // --- Annulus ---
        if p.annulus == nil { p.annulus = [] }
        for a0 in (self.annulus ?? []) {
            let a = AnnulusSection(
                name: a0.name,
                topDepth_m: a0.topDepth_m,
                length_m: a0.length_m,
                innerDiameter_m: a0.innerDiameter_m,
                outerDiameter_m: a0.outerDiameter_m,
                inclination_deg: a0.inclination_deg,
                wallRoughness_m: a0.wallRoughness_m,
                isCased: a0.isCased,
                rheologyModel: a0.rheologyModel,
                density_kg_per_m3: a0.density_kg_per_m3,
                dynamicViscosity_Pa_s: a0.dynamicViscosity_Pa_s,
                pv_Pa_s: a0.pv_Pa_s,
                yp_Pa: a0.yp_Pa,
                n_powerLaw: a0.n_powerLaw,
                k_powerLaw_Pa_s_n: a0.k_powerLaw_Pa_s_n,
                hb_tau0_Pa: a0.hb_tau0_Pa,
                hb_n: a0.hb_n,
                hb_k_Pa_s_n: a0.hb_k_Pa_s_n,
                cuttingsVolFrac: a0.cuttingsVolFrac,
                project: p
            )
            p.annulus?.append(a)
        }

        // --- Mud steps (attach mud by ID map) ---
        if p.mudSteps == nil { p.mudSteps = [] }
        for m0 in (self.mudSteps ?? []) {
            let linked: MudProperties? = m0.mud.flatMap { old in mudMap[old.id] }
            let s = MudStep(
                name: m0.name,
                top_m: m0.top_m,
                bottom_m: m0.bottom_m,
                density_kgm3: m0.density_kgm3,
                colorHex: m0.colorHex,
                placementRaw: m0.placementRaw,
                project: p,
                mud: linked
            )
            p.mudSteps?.append(s)
        }

        // --- Final layers (attach mud by ID map) ---
        if p.finalLayers == nil { p.finalLayers = [] }
        for f0 in (self.finalLayers ?? []) {
            let linked: MudProperties? = f0.mud.flatMap { old in mudMap[old.id] }
            let f = FinalFluidLayer(
                project: p,
                name: f0.name,
                placement: f0.placement,
                topMD_m: f0.topMD_m,
                bottomMD_m: f0.bottomMD_m,
                density_kgm3: f0.density_kgm3,
                color: f0.color,
                createdAt: f0.createdAt,
                mud: linked
            )
            p.finalLayers?.append(f)
        }

        // --- Cement Jobs (with stages) ---
        if p.cementJobs == nil { p.cementJobs = [] }
        for cj0 in (self.cementJobs ?? []) {
            let cj = CementJob(
                name: cj0.name,
                casingType: cj0.casingType,
                topMD_m: cj0.topMD_m,
                bottomMD_m: cj0.bottomMD_m,
                // Lead cement
                leadExcessPercent: cj0.leadExcessPercent,
                leadTopMD_m: cj0.leadTopMD_m,
                leadBottomMD_m: cj0.leadBottomMD_m,
                leadYieldFactor_m3_per_tonne: cj0.leadYieldFactor_m3_per_tonne,
                leadMixWaterRatio_m3_per_tonne: cj0.leadMixWaterRatio_m3_per_tonne,
                // Tail cement
                tailExcessPercent: cj0.tailExcessPercent,
                tailTopMD_m: cj0.tailTopMD_m,
                tailBottomMD_m: cj0.tailBottomMD_m,
                tailYieldFactor_m3_per_tonne: cj0.tailYieldFactor_m3_per_tonne,
                tailMixWaterRatio_m3_per_tonne: cj0.tailMixWaterRatio_m3_per_tonne,
                // Additional volumes
                washUpVolume_m3: cj0.washUpVolume_m3,
                pumpOutVolume_m3: cj0.pumpOutVolume_m3,
                // Legacy
                excessPercent: cj0.excessPercent,
                yieldFactor_m3_per_tonne: cj0.yieldFactor_m3_per_tonne,
                mixWaterRatio_m3_per_tonne: cj0.mixWaterRatio_m3_per_tonne,
                project: p
            )
            cj.casedVolume_m3 = cj0.casedVolume_m3
            cj.openHoleVolume_m3 = cj0.openHoleVolume_m3
            cj.totalVolumeWithExcess_m3 = cj0.totalVolumeWithExcess_m3
            cj.notes = cj0.notes

            // Clone stages
            if cj.stages == nil { cj.stages = [] }
            for s0 in (cj0.stages ?? []).sorted(by: { $0.orderIndex < $1.orderIndex }) {
                let linked: MudProperties? = s0.mud.flatMap { old in mudMap[old.id] }
                let s = CementJobStage(
                    stageType: s0.stageType,
                    name: s0.name,
                    volume_m3: s0.volume_m3,
                    density_kgm3: s0.density_kgm3,
                    pumpRate_m3permin: s0.pumpRate_m3permin,
                    color: s0.color,
                    mud: linked,
                    cementJob: cj
                )
                s.orderIndex = s0.orderIndex
                s.tonnage_t = s0.tonnage_t
                s.mixWater_L = s0.mixWater_L
                s.operationTypeRaw = s0.operationTypeRaw
                s.pressure_MPa = s0.pressure_MPa
                s.overPressure_MPa = s0.overPressure_MPa
                s.duration_min = s0.duration_min
                s.operationVolume_L = s0.operationVolume_L
                s.operationTime = s0.operationTime
                s.floatsClosed = s0.floatsClosed
                s.notes = s0.notes
                cj.stages?.append(s)
            }

            p.cementJobs?.append(cj)
        }

        // --- Trip Simulations (with steps) ---
        if p.tripSimulations == nil { p.tripSimulations = [] }
        for ts0 in (self.tripSimulations ?? []) {
            let linkedMud: MudProperties? = ts0.backfillMud.flatMap { old in mudMap[old.id] }
            let ts = TripSimulation(
                name: ts0.name,
                startBitMD_m: ts0.startBitMD_m,
                endMD_m: ts0.endMD_m,
                shoeMD_m: ts0.shoeMD_m,
                step_m: ts0.step_m,
                baseMudDensity_kgpm3: ts0.baseMudDensity_kgpm3,
                backfillDensity_kgpm3: ts0.backfillDensity_kgpm3,
                targetESDAtTD_kgpm3: ts0.targetESDAtTD_kgpm3,
                crackFloat_kPa: ts0.crackFloat_kPa,
                initialSABP_kPa: ts0.initialSABP_kPa,
                holdSABPOpen: ts0.holdSABPOpen,
                tripSpeed_m_per_s: ts0.tripSpeed_m_per_s,
                eccentricityFactor: ts0.eccentricityFactor,
                fallbackTheta600: ts0.fallbackTheta600,
                fallbackTheta300: ts0.fallbackTheta300,
                useObservedPitGain: ts0.useObservedPitGain,
                observedInitialPitGain_m3: ts0.observedInitialPitGain_m3,
                project: p,
                backfillMud: linkedMud
            )
            ts.calculatedInitialPitGain_m3 = ts0.calculatedInitialPitGain_m3
            ts.maxSABP_kPa = ts0.maxSABP_kPa
            ts.maxESD_kgpm3 = ts0.maxESD_kgpm3
            ts.minESD_kgpm3 = ts0.minESD_kgpm3
            ts.totalBackfill_m3 = ts0.totalBackfill_m3
            ts.totalPitGain_m3 = ts0.totalPitGain_m3
            ts.finalTankDelta_m3 = ts0.finalTankDelta_m3
            ts.createdAt = ts0.createdAt
            ts.updatedAt = ts0.updatedAt

            // Clone steps
            if ts.steps == nil { ts.steps = [] }
            for step0 in (ts0.steps ?? []).sorted(by: { $0.stepIndex < $1.stepIndex }) {
                let step = TripSimulationStep(
                    stepIndex: step0.stepIndex,
                    bitMD_m: step0.bitMD_m,
                    bitTVD_m: step0.bitTVD_m,
                    SABP_kPa: step0.SABP_kPa,
                    SABP_kPa_Raw: step0.SABP_kPa_Raw,
                    SABP_Dynamic_kPa: step0.SABP_Dynamic_kPa,
                    ESDatTD_kgpm3: step0.ESDatTD_kgpm3,
                    ESDatBit_kgpm3: step0.ESDatBit_kgpm3,
                    swabDropToBit_kPa: step0.swabDropToBit_kPa,
                    floatState: step0.floatState,
                    stepBackfill_m3: step0.stepBackfill_m3,
                    cumulativeBackfill_m3: step0.cumulativeBackfill_m3,
                    expectedFillIfClosed_m3: step0.expectedFillIfClosed_m3,
                    expectedFillIfOpen_m3: step0.expectedFillIfOpen_m3,
                    slugContribution_m3: step0.slugContribution_m3,
                    cumulativeSlugContribution_m3: step0.cumulativeSlugContribution_m3,
                    pitGain_m3: step0.pitGain_m3,
                    cumulativePitGain_m3: step0.cumulativePitGain_m3,
                    surfaceTankDelta_m3: step0.surfaceTankDelta_m3,
                    cumulativeSurfaceTankDelta_m3: step0.cumulativeSurfaceTankDelta_m3,
                    backfillRemaining_m3: step0.backfillRemaining_m3,
                    simulation: ts
                )
                // Copy layer data directly (already JSON encoded)
                step.layersAnnulusData = step0.layersAnnulusData
                step.layersStringData = step0.layersStringData
                step.layersPocketData = step0.layersPocketData
                ts.steps?.append(step)
            }

            p.tripSimulations?.append(ts)
        }

        // --- Singletons (force unwrap safe because init() creates them) ---
        p.window = self.window
        p.slug = self.slug
        p.backfill = self.backfill
        p.settings = self.settings
        p.swab = self.swab

        p.updatedAt = .now
        try? context.save()
        return p
    }
}

extension ProjectState {
    var activeMud: MudProperties? { (muds ?? []).first(where: { $0.isActive }) ?? (muds ?? []).first }
}

extension ProjectState {
    var activeMudColor: Color { activeMud?.color ?? Color.gray.opacity(0.35) }
}

// MARK: - Export to Dictionary and JSON

extension ProjectState {
    /// A dictionary representation of the entire ProjectState suitable for JSON serialization.
    /// This includes:
    /// - Scalar properties (name, id, densities, volumes, timestamps)
    /// - Arrays of child objects (surveys, drillString, annulus, mudSteps, finalLayers, muds) as arrays of dictionaries
    /// - Singletons (window, slug, backfill, settings, swab) represented as dictionaries of their scalar fields
    var exportDictionary: [String: Any] {
        var dict: [String: Any] = [:]

        // Scalars
        dict["id"] = id.uuidString
        dict["name"] = name
        dict["createdAt"] = ISO8601DateFormatter().string(from: createdAt)
        dict["updatedAt"] = ISO8601DateFormatter().string(from: updatedAt)
        dict["basedOnProjectID"] = basedOnProjectID?.uuidString ?? NSNull()

        dict["baseAnnulusDensity_kgm3"] = baseAnnulusDensity_kgm3
        dict["baseStringDensity_kgm3"] = baseStringDensity_kgm3
        dict["pressureDepth_m"] = pressureDepth_m
        dict["activeMudDensity_kgm3"] = activeMudDensity_kgm3
        dict["activeMudVolume_m3"] = activeMudVolume_m3
        dict["surfaceLineVolume_m3"] = surfaceLineVolume_m3

        // Collections serialized as dictionaries
        dict["surveys"] = (surveys ?? []).map { $0.exportDictionary }
        dict["drillString"] = (drillString ?? []).map { $0.exportDictionary }
        dict["annulus"] = (annulus ?? []).map { $0.exportDictionary }
        dict["mudSteps"] = (mudSteps ?? []).map { $0.exportDictionary }
        dict["finalLayers"] = (finalLayers ?? []).map { $0.exportDictionary }
        dict["muds"] = (muds ?? []).map { $0.exportDictionary }

        // Singletons serialized as dictionaries
        //dict["window"] = window.exportDictionary
        //dict["slug"] = slug.exportDictionary
        //dict["backfill"] = backfill.exportDictionary
        //dict["settings"] = settings.exportDictionary
        //dict["swab"] = swab.exportDictionary

        return dict
    }

    /// Convenience method to get JSON string representation of the project state.
    /// Returns nil if encoding fails.
    func exportJSON(prettyPrinted: Bool = true) -> String? {
        let dict = exportDictionary
        guard JSONSerialization.isValidJSONObject(dict) else {
            NSLog("Export JSON: invalid object graph. Ensure all values are JSON types.")
            return nil
        }
        let options: JSONSerialization.WritingOptions = prettyPrinted ? [.prettyPrinted, .sortedKeys] : []
        do {
            let data = try JSONSerialization.data(withJSONObject: dict, options: options)
            return String(data: data, encoding: .utf8)
        } catch {
            NSLog("Export JSON: encoding error: \(error)")
            return nil
        }
    }
}

// MARK: - Export Dictionary for related models

extension SurveyStation {
    var exportDictionary: [String: Any] {
        [
            "md": md,
            "inc": inc,
            "azi": azi,
            "tvd": tvd ?? NSNull()
        ]
    }
}

extension DrillStringSection {
    var exportDictionary: [String: Any] {
        [
            "name": name,
            "topDepth_m": topDepth_m,
            "length_m": length_m,
            "outerDiameter_m": outerDiameter_m,
            "innerDiameter_m": innerDiameter_m,
            "toolJointOD_m": toolJointOD_m ?? NSNull(),
            "jointLength_m": jointLength_m,
            "grade": grade ?? NSNull(),
            "steelDensity_kg_per_m3": steelDensity_kg_per_m3,
            "unitWeight_kg_per_m": unitWeight_kg_per_m ?? NSNull(),
            "internalRoughness_m": internalRoughness_m
        ]
    }
}

extension AnnulusSection {
    var exportDictionary: [String: Any] {
        [
            "name": name,
            "topDepth_m": topDepth_m,
            "length_m": length_m,
            "innerDiameter_m": innerDiameter_m,
            "outerDiameter_m": outerDiameter_m,
            "inclination_deg": inclination_deg,
            "wallRoughness_m": wallRoughness_m,
            "isCased": isCased,
            "rheologyModel": rheologyModel.rawValue,
            "density_kg_per_m3": density_kg_per_m3,
            "dynamicViscosity_Pa_s": dynamicViscosity_Pa_s,
            "pv_Pa_s": pv_Pa_s,
            "yp_Pa": yp_Pa,
            "n_powerLaw": n_powerLaw,
            "k_powerLaw_Pa_s_n": k_powerLaw_Pa_s_n,
            "hb_tau0_Pa": hb_tau0_Pa,
            "hb_n": hb_n,
            "hb_k_Pa_s_n": hb_k_Pa_s_n,
            "cuttingsVolFrac": cuttingsVolFrac
        ]
    }
}

extension MudStep {
    var exportDictionary: [String: Any] {
        [
            "name": name,
            "top_m": top_m,
            "bottom_m": bottom_m,
            "density_kgm3": density_kgm3,
            "colorHex": colorHex,
            "placementRaw": placementRaw,
            "mudID": mud?.id.uuidString ?? NSNull()
        ]
    }
}

extension FinalFluidLayer {
    var exportDictionary: [String: Any] {
        [
            "name": name,
            "placement": placement.rawValue,
            "topMD_m": topMD_m,
            "bottomMD_m": bottomMD_m,
            "density_kgm3": density_kgm3,
            "color": [
                "r": colorR,
                "g": colorG,
                "b": colorB,
                "a": colorA
            ],
            "createdAt": ISO8601DateFormatter().string(from: createdAt),
            "mudID": mud?.id.uuidString ?? NSNull()
        ]
    }
}

extension MudProperties {
    var exportDictionary: [String: Any] {
        [
            "id": id.uuidString,
            "name": name,
            "isActive": isActive,
            "density_kgm3": density_kgm3,
            "color": [
                "r": colorR,
                "g": colorG,
                "b": colorB,
                "a": colorA
            ]
            // Add other relevant scalar properties as needed
        ]
    }
}

//extension PressureWindow {
//    var exportDictionary: [String: Any] {
//        [
//            "minPressure_Pa": minPressure_Pa,
//            "maxPressure_Pa": maxPressure_Pa,
//            "minDepth_m": minDepth_m,
//            "maxDepth_m": maxDepth_m
//            // Add other scalar properties if any
//        ]
//    }
//}

//extension SlugPlan {
//    var exportDictionary: [String: Any] {
//        [
//            "slugLength_m": slugLength_m,
//            "slugFrequency_min": slugFrequency_min
//            // Add other scalar properties if any
//        ]
//    }
//}

//extension BackfillPlan {
//    var exportDictionary: [String: Any] {
//        [
//            "backfillVolume_m3": backfillVolume_m3,
//            "backfillDensity_kgm3": backfillDensity_kgm3
//            // Add other scalar properties if any
//        ]
//    }
//}

//extension TripSettings {
//    var exportDictionary: [String: Any] {
//        [
//            "tripSpeed_m_per_min": tripSpeed_m_per_min,
//            "tripPumpRate_L_per_min": tripPumpRate_L_per_min
//            // Add other scalar properties if any
//        ]
//    }
//}

//extension SwabInput {
//    var exportDictionary: [String: Any] {
//        [
//            "swabSpeed_m_per_min": swabSpeed_m_per_min,
//            "swabPumpRate_L_per_min": swabPumpRate_L_per_min
//            // Add other scalar properties if any
//        ]
//    }
//}

