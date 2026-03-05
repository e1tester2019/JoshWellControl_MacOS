//
//  TorqueDragEngine.swift
//  Josh Well Control for Mac
//
//  Soft-string torque & drag model (Johancsik et al., 1984).
//  Stateless engine: call compute(input:) → TorqueDragResult.
//
//  Marches from bit to surface, accumulating axial force and torque
//  per survey interval. Supports variable buoyancy from multi-layer
//  fluid state, per-section friction factors, and Paslay-Dawson
//  buckling criteria.
//

import Foundation

// MARK: - Input / Output Types

enum TorqueDragEngine {

    /// Operation mode determines sign convention for friction
    enum OperationMode: String, Codable, CaseIterable, Identifiable {
        case tripOut       // pulling out — friction adds to tension
        case tripIn        // running in — friction reduces tension
        case rotatingOB    // rotating off-bottom — no axial friction, torque only
        case rotatingDrill // rotating on-bottom with WOB — torque + axial
        case sliding       // sliding (no rotation) with WOB — axial friction only

        var id: String { rawValue }

        var label: String {
            switch self {
            case .tripOut:       return "Trip Out (Pickup)"
            case .tripIn:        return "Trip In (Slack-off)"
            case .rotatingOB:    return "Rotating Off-Bottom"
            case .rotatingDrill: return "Rotating (Drilling)"
            case .sliding:       return "Sliding"
            }
        }
    }

    /// Lightweight survey station for the engine (no SwiftData dependency)
    struct SurveyPoint: Sendable {
        let md: Double      // m
        let inc: Double     // radians
        let azi: Double     // radians
        let tvd: Double     // m
    }

    /// Lightweight drill string segment for the engine
    struct StringSegment: Sendable {
        let topMD: Double           // m
        let bottomMD: Double        // m
        let outerDiameter_m: Double
        let innerDiameter_m: Double
        let linearWeight_kg_per_m: Double  // weight in air per meter
        let toolJointOD_m: Double?
        let steelDensity_kg_per_m3: Double
    }

    /// Lightweight hole section for the engine
    struct HoleSection: Sendable {
        let topMD: Double
        let bottomMD: Double
        let holeDiameter_m: Double
        let isCased: Bool
    }

    /// Per-section friction factors (cased vs open hole)
    struct FrictionFactors: Sendable {
        let casedUp: Double        // pulling out in cased hole
        let casedDown: Double      // running in cased hole
        let casedRotating: Double  // rotating in cased hole
        let openHoleUp: Double     // pulling out in open hole
        let openHoleDown: Double   // running in open hole
        let openHoleRotating: Double // rotating in open hole

        /// Convenience: same FF for all directions per section type
        init(cased: Double = 0.20, openHole: Double = 0.30) {
            self.casedUp = cased
            self.casedDown = cased
            self.casedRotating = cased
            self.openHoleUp = openHole
            self.openHoleDown = openHole
            self.openHoleRotating = openHole
        }

        /// Full control over each direction
        init(casedUp: Double, casedDown: Double, casedRotating: Double,
             openHoleUp: Double, openHoleDown: Double, openHoleRotating: Double) {
            self.casedUp = casedUp
            self.casedDown = casedDown
            self.casedRotating = casedRotating
            self.openHoleUp = openHoleUp
            self.openHoleDown = openHoleDown
            self.openHoleRotating = openHoleRotating
        }
    }

    struct TorqueDragInput: Sendable {
        let surveys: [SurveyPoint]
        let stringSegments: [StringSegment]
        let holeSections: [HoleSection]
        let fluidLayers: [TripLayerSnapshot]  // current annulus fluid state
        let bitMD: Double                      // current bit depth (MD)
        let mode: OperationMode
        let friction: FrictionFactors
        let WOB_kN: Double                     // weight on bit (kN), 0 for tripping
        let blockWeight_kN: Double             // travelling assembly weight (kN)
        let tvdSampler: TvdSampler
    }

    /// Per-segment result (one per survey interval)
    struct SegmentResult: Sendable {
        let topMD: Double
        let bottomMD: Double
        let midMD: Double
        let midTVD: Double
        let midInc_deg: Double
        let axialForce_kN: Double       // at top of segment (+ = tension, - = compression)
        let normalForce_kN: Double      // contact/side force for this segment
        let torque_kNm: Double          // cumulative torque at top of segment
        let buoyancyFactor: Double
        let frictionCoeff: Double
        let bucklingStatus: BucklingStatus
        let criticalBucklingLoad_kN: Double  // Paslay-Dawson sinusoidal
        let helicalBucklingLoad_kN: Double   // √2 × Paslay-Dawson
    }

    enum BucklingStatus: String, Codable, Sendable {
        case ok = "OK"
        case sinusoidal = "Sinusoidal"
        case helical = "Helical"
    }

    struct TorqueDragResult: Sendable {
        let segments: [SegmentResult]
        let hookLoad_kN: Double          // force at surface (top of string)
        let surfaceTorque_kNm: Double    // torque at surface
        let freeHangingWeight_kN: Double // no-friction hook load for reference
        let maxSideForce_kN: Double
        let maxSideForceMD: Double
        let bucklingOnsetMD: Double?     // shallowest MD where buckling occurs
        let bucklingOnsetType: BucklingStatus?
        let neutralPointFromTop_m: Double?   // MD where axial force crosses zero (from surface)
        let neutralPointFromBottom_m: Double? // distance from bit to neutral point
        let stretch_m: Double                 // elastic elongation of the string (m)
        let stringWeightInAir_kN: Double      // total string weight in air
        let stringBuoyedWeight_kN: Double     // total buoyed weight
    }

    // MARK: - Constants

    private static let g: Double = 9.80665           // m/s²
    private static let E_steel: Double = 207e9       // Pa (Young's modulus)
    private static let defaultSteelDensity: Double = 7850  // kg/m³

    // MARK: - Compute

    static func compute(_ input: TorqueDragInput) -> TorqueDragResult {
        // Sort surveys by MD ascending, filter to within bit depth
        let allSurveys = input.surveys
            .sorted { $0.md < $1.md }
        let surveys = allSurveys.filter { $0.md <= input.bitMD + 0.1 }

        guard surveys.count >= 2 else {
            return emptyResult(blockWeight: input.blockWeight_kN)
        }

        // Build intervals from deepest to shallowest (bit → surface)
        // Each interval is between consecutive survey stations
        var intervals: [(deep: SurveyPoint, shallow: SurveyPoint)] = []
        for i in stride(from: surveys.count - 1, through: 1, by: -1) {
            intervals.append((deep: surveys[i], shallow: surveys[i - 1]))
        }

        // If bit is deeper than deepest survey, extrapolate using last survey's inc/azi
        if let lastSurvey = surveys.last, input.bitMD > lastSurvey.md + 0.1 {
            let bitPoint = SurveyPoint(
                md: input.bitMD,
                inc: lastSurvey.inc,
                azi: lastSurvey.azi,
                tvd: input.tvdSampler.tvd(of: input.bitMD)
            )
            intervals.insert((deep: bitPoint, shallow: lastSurvey), at: 0)
        }

        // Initial axial force at bit
        var axialForce_N: Double
        var torque_Nm: Double = 0

        switch input.mode {
        case .tripOut, .tripIn, .rotatingOB:
            axialForce_N = 0  // no load at bit
        case .rotatingDrill, .sliding:
            axialForce_N = -input.WOB_kN * 1000  // compression from WOB (negative = compression)
        }

        // Also compute free-hanging (no friction) for reference
        var freeHangingForce_N: Double = axialForce_N

        var segmentResults: [SegmentResult] = []
        var maxSideForce: Double = 0
        var maxSideForceMD: Double = 0
        var bucklingOnsetMD: Double? = nil
        var bucklingOnsetType: BucklingStatus? = nil

        for interval in intervals {
            let deepSurvey = interval.deep
            let shallowSurvey = interval.shallow

            let deltaL = deepSurvey.md - shallowSurvey.md
            guard deltaL > 0.001 else { continue }

            let midMD = (deepSurvey.md + shallowSurvey.md) / 2.0
            let midTVD = input.tvdSampler.tvd(of: midMD)

            // Inclination and azimuth
            let inc1 = deepSurvey.inc    // bottom of segment (radians)
            let inc2 = shallowSurvey.inc // top of segment (radians)
            let azi1 = deepSurvey.azi
            let azi2 = shallowSurvey.azi
            let incAvg = (inc1 + inc2) / 2.0
            let deltaInc = inc2 - inc1
            let deltaAzi = azi2 - azi1

            // Look up drill string geometry at midpoint
            let pipeGeom = stringGeometry(at: midMD, segments: input.stringSegments)
            let linearWeight = pipeGeom.linearWeight_kg_per_m
            let pipeOD = pipeGeom.outerDiameter_m
            let pipeID = pipeGeom.innerDiameter_m
            let contactOD = pipeGeom.toolJointOD_m ?? pipeOD
            let steelDensity = pipeGeom.steelDensity_kg_per_m3

            // Variable buoyancy from fluid layers
            let fluidDensity = fluidDensityAtMD(midMD, layers: input.fluidLayers, tvdSampler: input.tvdSampler)
            let buoyancyFactor = max(0, 1.0 - fluidDensity / steelDensity)

            // Buoyed weight of segment
            let weightInAir_N = linearWeight * g * deltaL
            let buoyedWeight_N = weightInAir_N * buoyancyFactor

            // Friction coefficient (direction-dependent)
            let mu = frictionAt(midMD, holeSections: input.holeSections,
                                friction: input.friction, mode: input.mode)

            // Normal (side) force — Johancsik soft-string model
            let axialComponent = axialForce_N * deltaInc + buoyedWeight_N * sin(incAvg)
            let lateralComponent = axialForce_N * sin(incAvg) * deltaAzi
            let normalForce_N = sqrt(axialComponent * axialComponent + lateralComponent * lateralComponent)

            // Axial force increment
            let gravityComponent = buoyedWeight_N * cos(incAvg)
            let frictionForce_N: Double

            switch input.mode {
            case .tripOut:
                frictionForce_N = mu * normalForce_N  // friction opposes upward motion → adds tension
                axialForce_N += gravityComponent + frictionForce_N
            case .tripIn, .sliding:
                frictionForce_N = mu * normalForce_N  // friction opposes downward motion → reduces tension
                axialForce_N += gravityComponent - frictionForce_N
            case .rotatingOB, .rotatingDrill:
                frictionForce_N = 0  // no axial friction when rotating (all goes to torque)
                axialForce_N += gravityComponent
                // Torque increment
                torque_Nm += mu * normalForce_N * (contactOD / 2.0)
            }

            // Free-hanging weight (no friction, for reference)
            freeHangingForce_N += buoyedWeight_N * cos(incAvg)

            // Hole geometry for buckling check
            let holeID = holeDiameterAt(midMD, holeSections: input.holeSections)
            let radialClearance = max((holeID - contactOD) / 2.0, 0.001)

            // Moment of inertia
            let I = momentOfInertia(od: pipeOD, id: pipeID)

            // Buoyed weight per unit length
            let wBuoyed_per_m = linearWeight * g * buoyancyFactor

            // Paslay-Dawson critical buckling load (sinusoidal onset)
            let sinInc = abs(sin(incAvg))
            let criticalBucklingLoad_N: Double
            if sinInc > 0.001 && wBuoyed_per_m > 0 && I > 0 {
                criticalBucklingLoad_N = 2.0 * sqrt(E_steel * I * wBuoyed_per_m * sinInc / radialClearance)
            } else {
                criticalBucklingLoad_N = Double.greatestFiniteMagnitude
            }
            let helicalBucklingLoad_N = sqrt(2.0) * criticalBucklingLoad_N

            // Buckling check (compression = negative axial force)
            let compression_N = -axialForce_N  // positive when pipe is in compression
            let bucklingStatus: BucklingStatus
            if compression_N >= helicalBucklingLoad_N {
                bucklingStatus = .helical
            } else if compression_N >= criticalBucklingLoad_N {
                bucklingStatus = .sinusoidal
            } else {
                bucklingStatus = .ok
            }

            if bucklingStatus != .ok && bucklingOnsetMD == nil {
                bucklingOnsetMD = midMD
                bucklingOnsetType = bucklingStatus
            }

            let normalForce_kN = normalForce_N / 1000.0
            if normalForce_kN > maxSideForce {
                maxSideForce = normalForce_kN
                maxSideForceMD = midMD
            }

            segmentResults.append(SegmentResult(
                topMD: shallowSurvey.md,
                bottomMD: deepSurvey.md,
                midMD: midMD,
                midTVD: midTVD,
                midInc_deg: incAvg * 180.0 / .pi,
                axialForce_kN: axialForce_N / 1000.0,
                normalForce_kN: normalForce_kN,
                torque_kNm: torque_Nm / 1000.0,
                buoyancyFactor: buoyancyFactor,
                frictionCoeff: mu,
                bucklingStatus: bucklingStatus,
                criticalBucklingLoad_kN: criticalBucklingLoad_N == Double.greatestFiniteMagnitude
                    ? 0 : criticalBucklingLoad_N / 1000.0,
                helicalBucklingLoad_kN: helicalBucklingLoad_N == Double.greatestFiniteMagnitude
                    ? 0 : helicalBucklingLoad_N / 1000.0
            ))
        }

        // Hook load = axial force at surface + block weight
        let hookLoad_kN = axialForce_N / 1000.0 + input.blockWeight_kN
        let freeHanging_kN = freeHangingForce_N / 1000.0 + input.blockWeight_kN

        // Neutral point: find where axial force crosses zero
        // segmentResults are in bit→surface order at this point
        var neutralPointFromTop: Double? = nil
        var neutralPointFromBottom: Double? = nil
        for i in 0..<segmentResults.count - 1 {
            let f0 = segmentResults[i].axialForce_kN
            let f1 = segmentResults[i + 1].axialForce_kN
            if (f0 < 0 && f1 >= 0) || (f0 >= 0 && f1 < 0) {
                // Linear interpolation to find zero crossing
                let md0 = segmentResults[i].midMD
                let md1 = segmentResults[i + 1].midMD
                let t = abs(f0) / (abs(f0) + abs(f1))
                let npMD = md0 + t * (md1 - md0)
                neutralPointFromTop = npMD
                neutralPointFromBottom = input.bitMD - npMD
                break
            }
        }

        // Stretch: elastic elongation ΔL = Σ(F_avg × ΔL / (E × A))
        var totalStretch_m: Double = 0
        var totalWeightInAir_N: Double = 0
        var totalBuoyedWeight_N: Double = 0
        for seg in segmentResults {
            let deltaL = seg.bottomMD - seg.topMD
            let pipeGeom = stringGeometry(at: seg.midMD, segments: input.stringSegments)
            let pipeArea = Double.pi / 4.0 * (pipeGeom.outerDiameter_m * pipeGeom.outerDiameter_m
                - pipeGeom.innerDiameter_m * pipeGeom.innerDiameter_m)
            if pipeArea > 1e-9 {
                let force_N = seg.axialForce_kN * 1000.0
                totalStretch_m += max(0, force_N) * deltaL / (E_steel * pipeArea)
            }
            totalWeightInAir_N += pipeGeom.linearWeight_kg_per_m * g * deltaL
            totalBuoyedWeight_N += pipeGeom.linearWeight_kg_per_m * g * deltaL * seg.buoyancyFactor
        }

        return TorqueDragResult(
            segments: segmentResults.reversed(),  // return surface → bit order
            hookLoad_kN: hookLoad_kN,
            surfaceTorque_kNm: torque_Nm / 1000.0,
            freeHangingWeight_kN: freeHanging_kN,
            maxSideForce_kN: maxSideForce,
            maxSideForceMD: maxSideForceMD,
            bucklingOnsetMD: bucklingOnsetMD,
            bucklingOnsetType: bucklingOnsetType,
            neutralPointFromTop_m: neutralPointFromTop,
            neutralPointFromBottom_m: neutralPointFromBottom,
            stretch_m: totalStretch_m,
            stringWeightInAir_kN: totalWeightInAir_N / 1000.0,
            stringBuoyedWeight_kN: totalBuoyedWeight_N / 1000.0
        )
    }

    // MARK: - Multi-case convenience

    /// Compute all standard cases at once (pickup, slack-off, rotating, free-hanging)
    /// for a given depth and fluid state. Used by trip simulations for chart overlays.
    struct MultiCaseResult: Sendable {
        let pickupHookLoad_kN: Double
        let slackOffHookLoad_kN: Double
        let rotatingHookLoad_kN: Double
        let freeHangingWeight_kN: Double
        let surfaceTorque_kNm: Double
        let bucklingOnsetMD: Double?
        let bucklingOnsetType: BucklingStatus?
        let neutralPointFromTop_m: Double?
        let neutralPointFromBottom_m: Double?
        let pickupStretch_m: Double
        let slackOffStretch_m: Double
        let stringWeightInAir_kN: Double
        let stringBuoyedWeight_kN: Double
        let pickupResult: TorqueDragResult
        let slackOffResult: TorqueDragResult
        let rotatingResult: TorqueDragResult
    }

    static func computeAllCases(
        surveys: [SurveyPoint],
        stringSegments: [StringSegment],
        holeSections: [HoleSection],
        fluidLayers: [TripLayerSnapshot],
        bitMD: Double,
        friction: FrictionFactors,
        blockWeight_kN: Double,
        tvdSampler: TvdSampler
    ) -> MultiCaseResult {
        let pickup = compute(TorqueDragInput(
            surveys: surveys, stringSegments: stringSegments,
            holeSections: holeSections, fluidLayers: fluidLayers,
            bitMD: bitMD, mode: .tripOut, friction: friction,
            WOB_kN: 0, blockWeight_kN: blockWeight_kN, tvdSampler: tvdSampler
        ))

        let slackOff = compute(TorqueDragInput(
            surveys: surveys, stringSegments: stringSegments,
            holeSections: holeSections, fluidLayers: fluidLayers,
            bitMD: bitMD, mode: .tripIn, friction: friction,
            WOB_kN: 0, blockWeight_kN: blockWeight_kN, tvdSampler: tvdSampler
        ))

        let rotating = compute(TorqueDragInput(
            surveys: surveys, stringSegments: stringSegments,
            holeSections: holeSections, fluidLayers: fluidLayers,
            bitMD: bitMD, mode: .rotatingOB, friction: friction,
            WOB_kN: 0, blockWeight_kN: blockWeight_kN, tvdSampler: tvdSampler
        ))

        return MultiCaseResult(
            pickupHookLoad_kN: pickup.hookLoad_kN,
            slackOffHookLoad_kN: slackOff.hookLoad_kN,
            rotatingHookLoad_kN: rotating.hookLoad_kN,
            freeHangingWeight_kN: pickup.freeHangingWeight_kN,
            surfaceTorque_kNm: rotating.surfaceTorque_kNm,
            bucklingOnsetMD: slackOff.bucklingOnsetMD,
            bucklingOnsetType: slackOff.bucklingOnsetType,
            neutralPointFromTop_m: slackOff.neutralPointFromTop_m,
            neutralPointFromBottom_m: slackOff.neutralPointFromBottom_m,
            pickupStretch_m: pickup.stretch_m,
            slackOffStretch_m: slackOff.stretch_m,
            stringWeightInAir_kN: pickup.stringWeightInAir_kN,
            stringBuoyedWeight_kN: pickup.stringBuoyedWeight_kN,
            pickupResult: pickup,
            slackOffResult: slackOff,
            rotatingResult: rotating
        )
    }

    // MARK: - Sensitivity Analysis

    /// Run T&D for a range of friction factors (like the TADPRO sensitivity charts)
    struct SensitivityResult: Sendable {
        let frictionFactor: Double
        let pickupHookLoad_kN: Double
        let slackOffHookLoad_kN: Double
        let rotatingHookLoad_kN: Double
        let pickupSegments: [SegmentResult]
        let slackOffSegments: [SegmentResult]
    }

    static func sensitivityAnalysis(
        surveys: [SurveyPoint],
        stringSegments: [StringSegment],
        holeSections: [HoleSection],
        fluidLayers: [TripLayerSnapshot],
        bitMD: Double,
        frictionFactors: [Double],
        blockWeight_kN: Double,
        tvdSampler: TvdSampler
    ) -> [SensitivityResult] {
        frictionFactors.map { ff in
            let friction = FrictionFactors(cased: ff, openHole: ff)
            let multi = computeAllCases(
                surveys: surveys, stringSegments: stringSegments,
                holeSections: holeSections, fluidLayers: fluidLayers,
                bitMD: bitMD, friction: friction,
                blockWeight_kN: blockWeight_kN, tvdSampler: tvdSampler
            )
            return SensitivityResult(
                frictionFactor: ff,
                pickupHookLoad_kN: multi.pickupHookLoad_kN,
                slackOffHookLoad_kN: multi.slackOffHookLoad_kN,
                rotatingHookLoad_kN: multi.rotatingHookLoad_kN,
                pickupSegments: multi.pickupResult.segments,
                slackOffSegments: multi.slackOffResult.segments
            )
        }
    }

    // MARK: - Helpers

    /// Build survey points from project survey stations
    static func surveyPoints(from stations: [SurveyStation], tvdSampler: TvdSampler) -> [SurveyPoint] {
        stations.sorted { $0.md < $1.md }.map { s in
            SurveyPoint(
                md: s.md,
                inc: s.inc * .pi / 180.0,
                azi: s.azi * .pi / 180.0,
                tvd: s.tvd ?? tvdSampler.tvd(of: s.md)
            )
        }
    }

    /// Build string segments from project drill string sections
    static func stringSegments(from sections: [DrillStringSection]) -> [StringSegment] {
        sections.map { s in
            let linearWeight = s.unitWeight_kg_per_m
                ?? (s.steelDensity_kg_per_m3 * s.metalArea_m2)
            return StringSegment(
                topMD: s.topDepth_m,
                bottomMD: s.bottomDepth_m,
                outerDiameter_m: s.outerDiameter_m,
                innerDiameter_m: s.innerDiameter_m,
                linearWeight_kg_per_m: linearWeight,
                toolJointOD_m: s.toolJointOD_m,
                steelDensity_kg_per_m3: s.steelDensity_kg_per_m3
            )
        }
    }

    /// Build hole sections from project annulus sections
    static func holeSections(from sections: [AnnulusSection]) -> [HoleSection] {
        sections.map { s in
            HoleSection(
                topMD: s.topDepth_m,
                bottomMD: s.bottomDepth_m,
                holeDiameter_m: s.innerDiameter_m,
                isCased: s.isCased
            )
        }
    }

    // MARK: - Private Helpers

    private static func emptyResult(blockWeight: Double) -> TorqueDragResult {
        TorqueDragResult(
            segments: [],
            hookLoad_kN: blockWeight,
            surfaceTorque_kNm: 0,
            freeHangingWeight_kN: blockWeight,
            maxSideForce_kN: 0,
            maxSideForceMD: 0,
            bucklingOnsetMD: nil,
            bucklingOnsetType: nil,
            neutralPointFromTop_m: nil,
            neutralPointFromBottom_m: nil,
            stretch_m: 0,
            stringWeightInAir_kN: 0,
            stringBuoyedWeight_kN: 0
        )
    }

    /// Look up pipe geometry at a given MD
    private static func stringGeometry(
        at md: Double,
        segments: [StringSegment]
    ) -> (outerDiameter_m: Double, innerDiameter_m: Double,
          linearWeight_kg_per_m: Double, toolJointOD_m: Double?,
          steelDensity_kg_per_m3: Double) {
        if let seg = segments.first(where: { md >= $0.topMD && md <= $0.bottomMD }) {
            return (seg.outerDiameter_m, seg.innerDiameter_m,
                    seg.linearWeight_kg_per_m, seg.toolJointOD_m,
                    seg.steelDensity_kg_per_m3)
        }
        // Fallback: use closest segment
        let closest = segments.min(by: {
            let d0 = min(abs(md - $0.topMD), abs(md - $0.bottomMD))
            let d1 = min(abs(md - $1.topMD), abs(md - $1.bottomMD))
            return d0 < d1
        })
        if let c = closest {
            return (c.outerDiameter_m, c.innerDiameter_m,
                    c.linearWeight_kg_per_m, c.toolJointOD_m,
                    c.steelDensity_kg_per_m3)
        }
        return (0.127, 0.1086, 29.8, nil, defaultSteelDensity)  // 5" DP fallback
    }

    /// Look up fluid density at a given MD from the current layer state
    private static func fluidDensityAtMD(
        _ md: Double,
        layers: [TripLayerSnapshot],
        tvdSampler: TvdSampler
    ) -> Double {
        // Find the layer containing this MD
        if let layer = layers.first(where: { md >= $0.topMD && md <= $0.bottomMD }) {
            return layer.rho_kgpm3
        }
        // If between layers, use nearest
        let nearest = layers.min(by: {
            let d0 = min(abs(md - $0.topMD), abs(md - $0.bottomMD))
            let d1 = min(abs(md - $1.topMD), abs(md - $1.bottomMD))
            return d0 < d1
        })
        return nearest?.rho_kgpm3 ?? 1200  // default 1200 kg/m³
    }

    /// Look up friction coefficient at a given MD, direction-dependent
    private static func frictionAt(
        _ md: Double,
        holeSections: [HoleSection],
        friction: FrictionFactors,
        mode: OperationMode
    ) -> Double {
        let isCased = holeSections.first(where: { md >= $0.topMD && md <= $0.bottomMD })?.isCased ?? false
        switch mode {
        case .tripOut:
            return isCased ? friction.casedUp : friction.openHoleUp
        case .tripIn, .sliding:
            return isCased ? friction.casedDown : friction.openHoleDown
        case .rotatingOB, .rotatingDrill:
            return isCased ? friction.casedRotating : friction.openHoleRotating
        }
    }

    /// Look up hole diameter at a given MD
    private static func holeDiameterAt(
        _ md: Double,
        holeSections: [HoleSection]
    ) -> Double {
        if let section = holeSections.first(where: { md >= $0.topMD && md <= $0.bottomMD }) {
            return section.holeDiameter_m
        }
        return 0.2159  // 8.5" default
    }

    /// Pipe moment of inertia I = π/64 × (OD⁴ - ID⁴)
    private static func momentOfInertia(od: Double, id: Double) -> Double {
        .pi / 64.0 * (pow(od, 4) - pow(id, 4))
    }
}
