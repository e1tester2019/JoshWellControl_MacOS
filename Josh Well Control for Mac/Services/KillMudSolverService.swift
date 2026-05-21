//
//  KillMudSolverService.swift
//  Josh Well Control for Mac
//
//  Kill mud density & volume calculator.
//  Pipe kill density: (killPressure + crackFloat) / (g × TVD) + targetESD
//    where killPressure = (targetESD - baseMW) × TVD × g
//  Pipe volume fills string to heel.
//  Annulus kill density computed analytically:
//    totalKillPressure = (targetESD - baseMW) × controlTVD × g
//    slugContribution = (pipeDensity - baseMW) × slugHeight × g
//    remaining = totalKillPressure - slugContribution
//    annDensity = baseMW + remaining / (backfillTVD × g)
//  Each candidate is then validated with a full NumericalTripModel run.
//

import Foundation

struct KillMudSolverService {

    // MARK: - Input / Output

    struct SolverInput: Sendable {
        var annulusSections: [AnnulusSection]
        var drillStringSections: [DrillStringSection]
        var surveys: [SurveyStation]
        var projectSnapshot: NumericalTripModel.ProjectSnapshot

        var startMD_m: Double          // Bit at start (deepest)
        var endMD_m: Double            // Bit at end (shallowest, often 0)
        var controlMD_m: Double        // Control / shoe MD
        var targetESD_kgpm3: Double
        var crackFloat_kPa: Double
        var tripSpeed_m_per_s: Double
        var eccentricityFactor: Double
        var step_m: Double

        var baseMudDensity_kgpm3: Double
        var baseMudPV_cP: Double
        var baseMudYP_Pa: Double

        var porePressureESD_kgpm3: Double
        var fracGradientESD_kgpm3: Double

        // Density sweep range for annulus kill validation
        var sweepStartDensity_kgpm3: Double = 1500
        var sweepEndDensity_kgpm3: Double = 1700
        var sweepStep_kgpm3: Double = 10
    }

    struct SolverResult: Identifiable, Sendable {
        let id = UUID()
        var label: String              // e.g. "100% Fill", "75% Fill"
        var fillFraction: Double       // 1.0, 0.75, 0.50, 0.25
        var pipeKillDensity_kgpm3: Double
        var pipeKillVolume_m3: Double
        var annulusKillDensity_kgpm3: Double
        var annulusKillVolume_m3: Double
        var killTVD_m: Double          // TVD height of backfill
        var sustainedKillDepth_m: Double
        var maxESDAtControl_kgpm3: Double
        var maxSABP_kPa: Double
        var feasible: Bool
        var relived: Bool
    }

    /// Zone step for the zone-by-zone hydrostatic table
    struct ZoneStep: Sendable {
        var name: String               // e.g. "Surface Csg (air)", "Intermediate Csg"
        var topMD_m: Double
        var bottomMD_m: Double
        var topTVD_m: Double
        var bottomTVD_m: Double
        var deltaTVD_m: Double
        var pipeVol_m3: Double         // Pipe interior volume in this zone
        var boreVol_m3: Double         // Total bore volume in this zone
        var pipeContentDensity: Double // 1 (air) above slug top, pipeDensity below
        var mixedDensity_kgpm3: Double // Volume-weighted density
        var pressure_kPa: Double       // mixedDensity × g × deltaTVD
        var cumPressure_kPa: Double    // Running total
    }

    /// Intermediate geometry calculations exposed for display
    struct SolverGeometry: Sendable {
        var pipeDensity_kgpm3: Double
        var pipeVolume_m3: Double          // Total pipe interior volume (surface to heel)
        var heelMD_m: Double
        var bitTVD_m: Double
        var controlTVD_m: Double
        var steelDisplacement_m3: Double
        var slugDrop_m3: Double            // Volume of pipe kill mud that U-tubes into annulus
        var maxBackfillHeight_m: Double    // Height of steel displacement (MD)
        var boreVolToControl_m3: Double    // Total bore volume surface to control
        var avgDensityAtControl_kgpm3: Double // Mass-balanced density at control
        var totalKillPressure_kPa: Double
        var remainingPressure_kPa: Double  // What the backfill must provide
        var slugTopMD_m: Double            // MD where pipe kill mud starts (below air gap)
        var kopMD_m: Double                // Kickoff point MD
        var casingCapacity_m3_per_m: Double = 0 // Full bore area of casing (m³/m)
        var ohCapacity_m3_per_m: Double = 0    // Full bore area of open hole (m³/m)
        var avgCapacity_m3_per_m: Double = 0   // Length-weighted avg full bore capacity (cased + OH)

        // Excel-style derived values
        var pipeCapacity_m3_per_m: Double = 0   // Pipe bore cross-section area
        var drainHeight_m: Double = 0           // Slug drain height (TVD)
        var killDepth_m: Double = 0             // Heel − drain height (pipe length with kill mud)
        var killStringVolume_m3: Double = 0     // Kill mud volume after slug drop
        var killStringHeight_m: Double = 0      // KS vol in csg bore height
        var pipeKillPressure_kPa: Double = 0    // KS height × (KS MW − MW) × g
        var dispHeight_m: Double = 0            // Disp vol in csg bore height

        var zones: [ZoneStep] = []         // Zone-by-zone hydrostatic breakdown
    }

    // MARK: - Solve

    static func solve(input: SolverInput) async -> (geometry: SolverGeometry, results: [SolverResult]) {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = solveSync(input: input)
                continuation.resume(returning: result)
            }
        }
    }

    private static func solveSync(input: SolverInput) -> (geometry: SolverGeometry, results: [SolverResult]) {
        let g = 0.00981  // kPa per kg/m³ per m
        let tvdSampler = TvdSampler(stations: input.surveys)
        let geom = ProjectGeometryService(
            annulus: input.annulusSections,
            string: input.drillStringSections,
            currentStringBottomMD: input.startMD_m,
            mdToTvd: { md in tvdSampler.tvd(of: md) }
        )

        let bitTVD = tvdSampler.tvd(of: input.startMD_m)
        let controlTVD = tvdSampler.tvd(of: input.controlMD_m)

        // --- Pipe kill density ---
        // pipeDensity = targetESD + (targetESD - baseMW) + crackFloat / (TVD × g)
        let pipeDensity: Double
        if bitTVD > 0 {
            let killPressure = (input.targetESD_kgpm3 - input.baseMudDensity_kgpm3) * bitTVD * g
            pipeDensity = (killPressure + input.crackFloat_kPa) / (bitTVD * g) + input.targetESD_kgpm3
        } else {
            pipeDensity = input.targetESD_kgpm3
        }

        // --- Heel MD: first survey where inc ≥ 80° ---
        let heelMD: Double = {
            for s in input.surveys where s.inc >= 80 {
                return s.md
            }
            return input.startMD_m
        }()
        let pipeKillBottomMD = min(heelMD, input.startMD_m)

        // --- Pipe kill volume: string ID volume to heel ---
        let pipeKillVolume = geom.volumeInString_m3(0, pipeKillBottomMD)

        // --- Steel displacement (OD - ID) over trip range ---
        let steelDisplacement = max(0,
            geom.volumeOfStringOD_m3(input.endMD_m, input.startMD_m) -
            geom.volumeInString_m3(input.endMD_m, input.startMD_m))

        // --- Slug drop: pipe kill mud U-tubes into annulus, creating air gap ---
        // When string HP > annulus HP + crack float, the heavy pipe mud drains.
        // The drained height (TVD) determines the volume that needs backfill replacement.
        let slugDrop_m3: Double
        let drainHeight_tvd: Double
        if bitTVD > 0 {
            let stringHP = pipeDensity * g * bitTVD
            let annulusHP = input.baseMudDensity_kgpm3 * g * bitTVD
            if stringHP > annulusHP + input.crackFloat_kPa {
                drainHeight_tvd = max(0, bitTVD - (annulusHP + input.crackFloat_kPa) / (pipeDensity * g))
                slugDrop_m3 = drainHeight_tvd / bitTVD * pipeKillVolume
            } else {
                drainHeight_tvd = 0
                slugDrop_m3 = 0
            }
        } else {
            drainHeight_tvd = 0
            slugDrop_m3 = 0
        }

        // --- Backfill height (MD) for fill fraction calculations ---
        let totalHoleVol = geom.volumeInAnnulus_m3(input.endMD_m, input.startMD_m)
            + geom.volumeOfStringOD_m3(input.endMD_m, input.startMD_m)
        let tripMD = input.startMD_m - input.endMD_m
        let avgHoleArea = tripMD > 0 ? totalHoleVol / tripMD : 0.01
        let maxBackfillHeight = avgHoleArea > 0 ? steelDisplacement / avgHoleArea : 0

        // --- Slug top MD: where pipe kill mud starts (below the air gap) ---
        var slugTopMD: Double = 0
        if slugDrop_m3 > 0 {
            let drainTVD = max(0, bitTVD - (input.baseMudDensity_kgpm3 * g * bitTVD + input.crackFloat_kPa) / (pipeDensity * g))
            var searchMD: Double = 0
            while searchMD < input.startMD_m {
                if tvdSampler.tvd(of: searchMD) >= drainTVD {
                    slugTopMD = searchMD
                    break
                }
                searchMD += 10
            }
        }

        // --- KOP: last survey station before inclination starts building ---
        let kopMD: Double = {
            var lastVertical = pipeKillBottomMD
            for s in input.surveys {
                if s.inc < 2 { lastVertical = s.md }
            }
            return lastVertical
        }()

        // --- Zone-by-zone hydrostatic ---
        // Zones are derived from annulus sections (wellbore geometry).
        // slugTopMD is inserted as an additional split point to separate
        // the air gap (pipe empty, ρ=1) from the kill mud zone.
        let boreVolToControl = geom.volumeInAnnulus_m3(0, input.controlMD_m)
            + geom.volumeOfStringOD_m3(0, input.controlMD_m)

        // Build zone boundaries from annulus sections, sorted by topDepth
        let sortedSections = input.annulusSections.sorted { $0.topDepth_m < $1.topDepth_m }
        struct ZoneBoundary {
            var topMD: Double
            var botMD: Double
            var name: String
        }
        var sectionZones: [ZoneBoundary] = sortedSections.map { sec in
            ZoneBoundary(
                topMD: sec.topDepth_m,
                botMD: sec.topDepth_m + sec.length_m,
                name: sec.name.isEmpty ? (sec.isCased ? "Cased" : "Open Hole") : sec.name
            )
        }
        // Clip to pipeKillBottomMD (heel/TD) — we only care about zones with pipe
        sectionZones = sectionZones.compactMap { z in
            guard z.topMD < pipeKillBottomMD else { return nil }
            var clipped = z
            clipped.botMD = min(clipped.botMD, pipeKillBottomMD)
            return clipped
        }

        // Split at slugTopMD if it falls inside a zone (separates air gap from kill mud)
        if slugTopMD > 10 {
            var split: [ZoneBoundary] = []
            for z in sectionZones {
                if slugTopMD > z.topMD + 10 && slugTopMD < z.botMD - 10 {
                    split.append(ZoneBoundary(topMD: z.topMD, botMD: slugTopMD,
                                              name: z.name + " (air)"))
                    split.append(ZoneBoundary(topMD: slugTopMD, botMD: z.botMD,
                                              name: z.name))
                } else {
                    split.append(z)
                }
            }
            sectionZones = split
        }

        // Mark zones entirely above slugTopMD as air gap
        for i in 0..<sectionZones.count {
            if sectionZones[i].botMD <= slugTopMD + 10 && !sectionZones[i].name.contains("(air)") {
                sectionZones[i].name += " (air)"
            }
        }

        var cumPressure: Double = 0
        var zones: [ZoneStep] = []
        var killColumnPressure: Double = 0

        for sz in sectionZones {
            let mdTop = sz.topMD
            let mdBot = sz.botMD
            let tvdTop = tvdSampler.tvd(of: mdTop)
            let tvdBot = tvdSampler.tvd(of: mdBot)
            let deltaTVD = tvdBot - tvdTop

            // Total bore volume (annulus + string OD = full borehole)
            let boreVol = geom.volumeInAnnulus_m3(mdTop, mdBot)
                + geom.volumeOfStringOD_m3(mdTop, mdBot)

            // Pipe interior volume (always present where pipe exists)
            let pipeVol = geom.volumeInString_m3(mdTop, mdBot)

            // Annulus volume = bore - pipe interior
            let annVol = max(0, boreVol - pipeVol)

            // Pipe content: air (ρ=1) above slugTopMD, kill mud below
            let isAirGap = sz.name.contains("(air)")
            let pipeRho: Double = isAirGap ? 1.0 : pipeDensity

            // Mixed density: (pipeVol × pipeRho + annVol × activeMW) / boreVol
            let segDensity = boreVol > 0
                ? (pipeVol * pipeRho + annVol * input.baseMudDensity_kgpm3) / boreVol
                : input.baseMudDensity_kgpm3

            let segPressure = deltaTVD > 0 ? segDensity * g * deltaTVD : 0
            cumPressure += segPressure

            zones.append(ZoneStep(
                name: sz.name,
                topMD_m: mdTop, bottomMD_m: mdBot,
                topTVD_m: tvdTop, bottomTVD_m: tvdBot, deltaTVD_m: deltaTVD,
                pipeVol_m3: pipeVol, boreVol_m3: boreVol,
                pipeContentDensity: pipeRho,
                mixedDensity_kgpm3: segDensity, pressure_kPa: segPressure,
                cumPressure_kPa: cumPressure
            ))

            // Track pressure at control depth for kill contribution calc
            if abs(mdBot - input.controlMD_m) < 10 {
                killColumnPressure = cumPressure
            }
        }

        if killColumnPressure == 0 {
            killColumnPressure = zones.last(where: { $0.bottomMD_m <= input.controlMD_m + 10 })?.cumPressure_kPa ?? cumPressure
        }

        let baseColumnPressure = input.baseMudDensity_kgpm3 * g * controlTVD
        let totalKillPressure = (input.targetESD_kgpm3 - input.baseMudDensity_kgpm3) * controlTVD * g
        let killContribution = killColumnPressure - baseColumnPressure
        let remainingPressure = max(0, totalKillPressure - killContribution)

        let avgDensityAtControl = controlTVD > 0
            ? killColumnPressure / (g * controlTVD)
            : input.baseMudDensity_kgpm3

        // Casing capacity: full bore area (π/4 × ID²) from deepest cased section
        let casingCapacity: Double = {
            if let casedSec = input.annulusSections.filter({ $0.isCased }).max(by: { $0.topDepth_m + $0.length_m < $1.topDepth_m + $1.length_m }) {
                let id = casedSec.innerDiameter_m
                return .pi / 4.0 * id * id
            }
            return boreVolToControl / max(1, input.controlMD_m)
        }()

        // Open hole capacity: full bore area from deepest open hole section
        let ohCapacity: Double = {
            if let ohSec = input.annulusSections.filter({ !$0.isCased }).max(by: { $0.topDepth_m + $0.length_m < $1.topDepth_m + $1.length_m }) {
                let id = ohSec.innerDiameter_m
                return .pi / 4.0 * id * id
            }
            return casingCapacity
        }()

        // TVD-weighted average capacity (hydrostatic depends on TVD, not MD)
        let avgCapacity: Double = {
            var casedTVD = 0.0
            var ohTVD = 0.0
            for sec in input.annulusSections {
                let tvdTop = tvdSampler.tvd(of: sec.topDepth_m)
                let tvdBot = tvdSampler.tvd(of: sec.topDepth_m + sec.length_m)
                let deltaTVD = max(0, tvdBot - tvdTop)
                if sec.isCased {
                    casedTVD += deltaTVD
                } else {
                    ohTVD += deltaTVD
                }
            }
            let totalTVD = casedTVD + ohTVD
            guard totalTVD > 0 else { return casingCapacity }
            return (casingCapacity * casedTVD + ohCapacity * ohTVD) / totalTVD
        }()

        // --- Excel-style derived values ---
        let pipeCapacity = pipeKillBottomMD > 0 ? pipeKillVolume / pipeKillBottomMD : 0
        let killDepth = max(0, pipeKillBottomMD - slugTopMD)
        let killStringVol = geom.volumeInString_m3(slugTopMD, pipeKillBottomMD)
        let killStringHeight = avgCapacity > 0 ? killStringVol / avgCapacity : 0
        let pipeKillPressure = killStringHeight * (pipeDensity - input.baseMudDensity_kgpm3) * g
        let dispHeight = avgCapacity > 0 ? steelDisplacement / avgCapacity : 0

        let solverGeom = SolverGeometry(
            pipeDensity_kgpm3: pipeDensity,
            pipeVolume_m3: pipeKillVolume,
            heelMD_m: pipeKillBottomMD,
            bitTVD_m: bitTVD,
            controlTVD_m: controlTVD,
            steelDisplacement_m3: steelDisplacement,
            slugDrop_m3: slugDrop_m3,
            maxBackfillHeight_m: maxBackfillHeight,
            boreVolToControl_m3: boreVolToControl,
            avgDensityAtControl_kgpm3: avgDensityAtControl,
            totalKillPressure_kPa: totalKillPressure,
            remainingPressure_kPa: remainingPressure,
            slugTopMD_m: slugTopMD,
            kopMD_m: kopMD,
            casingCapacity_m3_per_m: casingCapacity,
            ohCapacity_m3_per_m: ohCapacity,
            avgCapacity_m3_per_m: avgCapacity,
            pipeCapacity_m3_per_m: pipeCapacity,
            drainHeight_m: drainHeight_tvd,
            killDepth_m: killDepth,
            killStringVolume_m3: killStringVol,
            killStringHeight_m: killStringHeight,
            pipeKillPressure_kPa: pipeKillPressure,
            dispHeight_m: dispHeight,
            zones: zones
        )

        // --- Density sweep: run sim at each annulus density using displacement volume ---
        // Backfill volume is fixed (steel displacement + slug drop).
        // Varying the density changes how much pressure that column provides.
        let sweepStart = input.sweepStartDensity_kgpm3
        let sweepEnd = input.sweepEndDensity_kgpm3
        let sweepStep = max(input.sweepStep_kgpm3, 1)
        let backfillVolume = steelDisplacement + slugDrop_m3
        let backfillHeight = avgCapacity > 0 ? backfillVolume / avgCapacity : 0
        var results: [SolverResult] = []

        var annDensity = sweepStart
        while annDensity <= sweepEnd + 0.5 {
            let validated = validateCandidate(
                pipeDensity: pipeDensity,
                pipeVolume: pipeKillVolume,
                annDensity: annDensity,
                annVolume: backfillVolume,
                input: input,
                tvdSampler: tvdSampler,
                geom: geom,
                controlTVD: controlTVD
            )

            results.append(SolverResult(
                label: String(format: "%.0f", annDensity),
                fillFraction: 0,
                pipeKillDensity_kgpm3: pipeDensity,
                pipeKillVolume_m3: pipeKillVolume,
                annulusKillDensity_kgpm3: annDensity,
                annulusKillVolume_m3: backfillVolume,
                killTVD_m: backfillHeight,
                sustainedKillDepth_m: validated.sustainedKillDepth_m,
                maxESDAtControl_kgpm3: validated.maxESD,
                maxSABP_kPa: validated.maxSABP,
                feasible: validated.feasible,
                relived: validated.relived
            ))

            annDensity += sweepStep
        }

        return (solverGeom, results)
    }

    // MARK: - Validate with NumericalTripModel

    private struct ValidationResult {
        var sustainedKillDepth_m: Double
        var maxESD: Double
        var maxSABP: Double
        var finalSABP: Double      // SABP at end of trip — drives density iteration
        var feasible: Bool
        var relived: Bool
    }

    private static func validateCandidate(
        pipeDensity: Double,
        pipeVolume: Double,
        annDensity: Double,
        annVolume: Double,
        input: SolverInput,
        tvdSampler: TvdSampler,
        geom: ProjectGeometryService,
        controlTVD: Double
    ) -> ValidationResult {
        // Build fluid schedule: infinite → single kill fluid;
        // finite → kill mud first, then switch to active mud for remainder.
        let schedule: [NumericalTripModel.FluidScheduleEntry]
        if annVolume.isInfinite {
            schedule = [
                NumericalTripModel.FluidScheduleEntry(
                    density_kgpm3: annDensity,
                    volume_m3: .infinity,
                    pv_cP: input.baseMudPV_cP,
                    yp_Pa: input.baseMudYP_Pa
                ),
            ]
        } else {
            schedule = [
                NumericalTripModel.FluidScheduleEntry(
                    density_kgpm3: annDensity,
                    volume_m3: annVolume,
                    pv_cP: input.baseMudPV_cP,
                    yp_Pa: input.baseMudYP_Pa
                ),
                NumericalTripModel.FluidScheduleEntry(
                    density_kgpm3: input.baseMudDensity_kgpm3,
                    volume_m3: .infinity,
                    pv_cP: input.baseMudPV_cP,
                    yp_Pa: input.baseMudYP_Pa
                ),
            ]
        }

        var tripInput = NumericalTripModel.TripInput(
            tvdOfMd: { md in tvdSampler.tvd(of: md) },
            shoeTVD_m: controlTVD,
            shoeMD_m: input.controlMD_m,
            startBitMD_m: input.startMD_m,
            endMD_m: input.endMD_m,
            crackFloat_kPa: input.crackFloat_kPa,
            step_m: max(input.step_m, 100),
            baseMudDensity_kgpm3: input.baseMudDensity_kgpm3,
            backfillDensity_kgpm3: annDensity,
            backfillPV_cP: input.baseMudPV_cP,
            backfillYP_Pa: input.baseMudYP_Pa,
            baseMudPV_cP: input.baseMudPV_cP,
            baseMudYP_Pa: input.baseMudYP_Pa,
            targetESDAtTD_kgpm3: input.targetESD_kgpm3,
            tripSpeed_m_per_s: input.tripSpeed_m_per_s,
            eccentricityFactor: input.eccentricityFactor
        )
        tripInput.fluidSchedule = schedule

        let model = NumericalTripModel()
        let steps = model.run(tripInput, geom: geom, projectSnapshot: input.projectSnapshot)

        guard !steps.isEmpty else {
            return ValidationResult(sustainedKillDepth_m: 0, maxESD: 0, maxSABP: 0, finalSABP: 0, feasible: false, relived: false)
        }

        var feasible = true
        var maxESD: Double = 0
        var maxSABP: Double = 0

        for step in steps {
            let totalESD: Double
            if controlTVD > 0 {
                totalESD = step.ESDatControl_kgpm3 + step.SABP_kPa / (0.00981 * controlTVD)
            } else {
                totalESD = step.ESDatControl_kgpm3
            }

            if step.ESDatControl_kgpm3 > input.fracGradientESD_kgpm3 {
                feasible = false
            }
            if totalESD < input.porePressureESD_kgpm3 - 1.0 {
                feasible = false
            }

            maxESD = max(maxESD, step.ESDatControl_kgpm3)
            maxSABP = max(maxSABP, step.SABP_kPa)
        }

        // Sustained kill depth
        var sustainedKillFromStep: Int? = nil
        for i in stride(from: steps.count - 1, through: 0, by: -1) {
            if steps[i].SABP_kPa <= 0.5 {
                sustainedKillFromStep = i
            } else {
                break
            }
        }
        let sustainedKillDepth = sustainedKillFromStep.map { steps[$0].bitMD_m } ?? 0

        // Re-live check
        var relived = false
        var sawZero = false
        for step in steps {
            if step.SABP_kPa <= 0.5 {
                sawZero = true
            } else if sawZero {
                relived = true
                break
            }
        }

        let finalSABP = steps.last?.SABP_kPa ?? 0

        return ValidationResult(
            sustainedKillDepth_m: sustainedKillDepth,
            maxESD: maxESD,
            maxSABP: maxSABP,
            finalSABP: finalSABP,
            feasible: feasible,
            relived: relived
        )
    }
}
