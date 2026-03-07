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
        case tripOut         // pulling out — friction adds to tension
        case tripIn          // running in — friction reduces tension
        case rotatingOB      // rotating off-bottom — no axial friction, torque only
        case rotatingDrill   // rotating on-bottom with WOB — torque + axial
        case sliding         // sliding (no rotation) with WOB — axial friction only
        case rotatingHoist   // rotating + pulling out — friction split between axial and torque
        case rotatingSlackOff // rotating + running in — friction split between axial and torque

        var id: String { rawValue }

        var label: String {
            switch self {
            case .tripOut:          return "Trip Out (Pickup)"
            case .tripIn:           return "Trip In (Slack-off)"
            case .rotatingOB:       return "Rotating Off-Bottom"
            case .rotatingDrill:    return "Rotating (Drilling)"
            case .sliding:          return "Sliding"
            case .rotatingHoist:    return "Rotating + Hoist"
            case .rotatingSlackOff: return "Rotating + Slack-off"
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
        /// Total flow area at a restriction (bit nozzle TFA, shoe port).
        /// nil = full bore (no restriction), 0 = sealed end.
        let totalFlowArea_m2: Double?
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
        let stringFluidLayers: [TripLayerSnapshot]  // current string (internal) fluid state
        let bitMD: Double                      // current bit depth (MD)
        let mode: OperationMode
        let friction: FrictionFactors
        let WOB_kN: Double                     // weight on bit (kN), 0 for tripping
        let blockWeight_kN: Double             // travelling assembly weight (kN)
        let tvdSampler: TvdSampler
        let SABP_kPa: Double                   // surface annular back pressure (kPa)
        let floatIsOpen: Bool                  // whether float valve is open (affects piston area)
        let flowRate_m3perMin: Double          // circulation rate (0 = no flow, no drag effects)
        let surgePressure_kPa: Double          // surge/swab at shoe (kPa, + = surge, − = swab)
        let aplEccentricityFactor: Double      // multiplier on annular pressure loss (1.0 = concentric)
        let pressureAreaBuoyancy: Bool          // per-element pressure-area correction for circulating buoyancy
        let rpm: Double                         // string rotation speed (rev/min), 0 = no rotation
        let tripSpeed_m_per_s: Double           // axial pipe speed (m/s), 0 = stationary
        let rotationEfficiency: Double          // 0–1 scale on velocity-ratio split (1.0 = full model, 0 = no torque benefit)

        init(surveys: [SurveyPoint], stringSegments: [StringSegment],
             holeSections: [HoleSection], fluidLayers: [TripLayerSnapshot],
             bitMD: Double, mode: OperationMode, friction: FrictionFactors,
             WOB_kN: Double, blockWeight_kN: Double, tvdSampler: TvdSampler,
             SABP_kPa: Double = 0, floatIsOpen: Bool = false,
             flowRate_m3perMin: Double = 0, surgePressure_kPa: Double = 0,
             aplEccentricityFactor: Double = 1.0,
             pressureAreaBuoyancy: Bool = true,
             stringFluidLayers: [TripLayerSnapshot] = [],
             rpm: Double = 0,
             tripSpeed_m_per_s: Double = 0,
             rotationEfficiency: Double = 1.0) {
            self.surveys = surveys
            self.stringSegments = stringSegments
            self.holeSections = holeSections
            self.fluidLayers = fluidLayers
            self.stringFluidLayers = stringFluidLayers
            self.bitMD = bitMD
            self.mode = mode
            self.friction = friction
            self.WOB_kN = WOB_kN
            self.blockWeight_kN = blockWeight_kN
            self.tvdSampler = tvdSampler
            self.SABP_kPa = SABP_kPa
            self.floatIsOpen = floatIsOpen
            self.flowRate_m3perMin = flowRate_m3perMin
            self.surgePressure_kPa = surgePressure_kPa
            self.aplEccentricityFactor = aplEccentricityFactor
            self.pressureAreaBuoyancy = pressureAreaBuoyancy
            self.rpm = rpm
            self.tripSpeed_m_per_s = tripSpeed_m_per_s
            self.rotationEfficiency = rotationEfficiency
        }
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
        let annularPressureLoss_kPa: Double   // total APL from circulation (0 if no flow)
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
        case .tripOut, .tripIn, .rotatingOB, .rotatingHoist, .rotatingSlackOff:
            axialForce_N = 0  // no load at bit
        case .rotatingDrill, .sliding:
            axialForce_N = -input.WOB_kN * 1000  // compression from WOB (negative = compression)
        }

        // SABP piston effect at bit:
        // Annulus back pressure acts on the pipe cross-section at the bit,
        // creating an upward force that reduces hook load (string gets lighter).
        // Float closed: full OD area is the piston (annulus pressure doesn't reach string ID).
        // Float open: only the steel ring area (OD - ID) since pressure equalizes through ID.
        if input.SABP_kPa > 0, let bitPipe = input.stringSegments.first(where: { input.bitMD >= $0.topMD && input.bitMD <= $0.bottomMD }) ?? input.stringSegments.last {
            let sabp_Pa = input.SABP_kPa * 1000.0
            let A_OD = Double.pi / 4.0 * bitPipe.outerDiameter_m * bitPipe.outerDiameter_m
            if input.floatIsOpen {
                let A_ID = Double.pi / 4.0 * bitPipe.innerDiameter_m * bitPipe.innerDiameter_m
                axialForce_N -= sabp_Pa * (A_OD - A_ID)  // steel ring piston
            } else {
                axialForce_N -= sabp_Pa * A_OD  // full OD piston
            }
        }

        // Piston force at shoe from annular pressure (APL from circulation + surge from tripping)
        let circulationAPL_Pa = input.flowRate_m3perMin > 0
            ? computeAnnularPressureLoss(intervals: intervals, input: input) * input.aplEccentricityFactor
            : 0.0
        let surgeAPL_Pa = input.surgePressure_kPa * 1000.0  // + = surge (trip in), − = swab (trip out)
        let totalAPL_Pa = circulationAPL_Pa + surgeAPL_Pa

        if abs(totalAPL_Pa) > 0.1 {
            if let bitPipe = input.stringSegments.first(where: {
                input.bitMD >= $0.topMD && input.bitMD <= $0.bottomMD
            }) ?? input.stringSegments.last {
                let A_OD = Double.pi / 4.0 * bitPipe.outerDiameter_m * bitPipe.outerDiameter_m
                let A_bore = Double.pi / 4.0 * bitPipe.innerDiameter_m * bitPipe.innerDiameter_m
                let A_steel = A_OD - A_bore

                if input.floatIsOpen {
                    // Open/restricted end — use TFA from bottommost pipe
                    let tfa = bitPipe.totalFlowArea_m2 ?? A_bore  // nil = full bore
                    let effectiveTFA = min(max(tfa, 0), A_bore)
                    let A_blocked = A_bore - effectiveTFA

                    let pistonForce_N: Double
                    if input.flowRate_m3perMin > 0 {
                        // CIRCULATION: flow through TFA equalizes internal pressure.
                        // Internal excess = annular excess + nozzle DP.
                        // Piston = APL × A_steel − nozzleDP × A_blocked.
                        var nozzleDP_Pa: Double = 0
                        if effectiveTFA > 1e-8 && A_blocked > 1e-8 {
                            let Q_m3ps = input.flowRate_m3perMin / 60.0
                            let V_nozzle = Q_m3ps / effectiveTFA
                            let rho = fluidDensityAtMD(input.bitMD, layers: input.fluidLayers, tvdSampler: input.tvdSampler)
                            let Cd: Double = 0.95
                            nozzleDP_Pa = rho * V_nozzle * V_nozzle / (2.0 * Cd * Cd)
                        }
                        pistonForce_N = totalAPL_Pa * A_steel - nozzleDP_Pa * A_blocked
                    } else {
                        // TRIPPING: no flow, surge/swab can't equalize through small TFA.
                        // Annular pressure acts on all solid area (A_OD − TFA).
                        let A_piston = A_steel + A_blocked  // = A_OD - effectiveTFA
                        pistonForce_N = totalAPL_Pa * A_piston
                    }
                    axialForce_N -= pistonForce_N
                } else {
                    // Closed end (float shut) — annular pressure acts on full OD
                    axialForce_N -= totalAPL_Pa * A_OD
                }
            }
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

            // Base friction coefficient (direction-dependent)
            var mu = frictionAt(midMD, holeSections: input.holeSections,
                                friction: input.friction, mode: input.mode)

            // Hole geometry (needed for drag and buckling)
            let holeID = holeDiameterAt(midMD, holeSections: input.holeSections)

            // Normal (side) force — Johancsik soft-string model
            let axialComponent = axialForce_N * deltaInc + buoyedWeight_N * sin(incAvg)
            let lateralComponent = axialForce_N * sin(incAvg) * deltaAzi
            let normalForce_N = sqrt(axialComponent * axialComponent + lateralComponent * lateralComponent)

            // Circulation viscous effects: distributed drag and friction reduction
            var annularDrag_N: Double = 0   // upward force from annular flow on pipe OD
            var stringDrag_N: Double = 0    // downward force from string flow on pipe ID

            if input.flowRate_m3perMin > 0 {
                let rheology = fluidRheologyAtMD(midMD, layers: input.fluidLayers)
                let n = rheology.n
                let K = rheology.K_Pa_sn
                let Q_m3ps = input.flowRate_m3perMin / 60.0

                // Annular flow (upward past pipe OD → drags pipe upward)
                let A_ann = Double.pi / 4.0 * (holeID * holeID - pipeOD * pipeOD)
                if A_ann > 1e-8 {
                    let V_ann = Q_m3ps / A_ann
                    let D_h_ann = holeID - pipeOD
                    if D_h_ann > 1e-6 {
                        // Power-law wall shear rate (annular slot approximation)
                        let gamma_ann = 12.0 * V_ann / D_h_ann * (2.0 + 1.0 / n) / 3.0
                        let tau_ann = K * pow(max(gamma_ann, 1e-6), n)
                        annularDrag_N = tau_ann * Double.pi * pipeOD * deltaL * input.aplEccentricityFactor
                    }
                }

                // String internal flow (downward through pipe ID → drags pipe downward)
                // Only applies when float is open (fluid flows through the pipe)
                let A_str = Double.pi / 4.0 * pipeID * pipeID
                if A_str > 1e-8 && input.floatIsOpen {
                    let V_str = Q_m3ps / A_str
                    // Power-law wall shear rate (pipe flow)
                    let gamma_str = 8.0 * V_str / pipeID * (3.0 * n + 1.0) / (4.0 * n)
                    let tau_str = K * pow(max(gamma_str, 1e-6), n)
                    stringDrag_N = tau_str * Double.pi * pipeID * deltaL
                }

                // Stribeck-inspired friction reduction from viscous film
                // dragRatio = annular viscous force / contact force at this interval
                // Higher flow / more viscous mud / less contact → more reduction
                if normalForce_N > 1e-3 {
                    let dragRatio = annularDrag_N / normalForce_N
                    mu *= max(0.7, 1.0 / (1.0 + 15.0 * dragRatio))
                }
            }

            // Trip-induced viscous drag: pipe moving through stationary mud creates
            // Couette-style shear in the annulus. Uses power-law wall shear stress
            // from pipe velocity relative to the annular gap.
            var tripViscousDrag_N: Double = 0
            if input.tripSpeed_m_per_s > 0 && input.flowRate_m3perMin == 0 {
                let rheology = fluidRheologyAtMD(midMD, layers: input.fluidLayers)
                let n = rheology.n
                let K = rheology.K_Pa_sn
                let gap = (holeID - pipeOD) / 2.0
                if gap > 1e-6 {
                    // Couette shear rate: V_pipe / gap (narrow annulus approximation)
                    let gamma_trip = input.tripSpeed_m_per_s / gap
                    let tau_trip = K * pow(max(gamma_trip, 1e-6), n)
                    tripViscousDrag_N = tau_trip * Double.pi * pipeOD * deltaL
                }
            }

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
                // Torque increment (also uses reduced friction)
                torque_Nm += mu * normalForce_N * (contactOD / 2.0)
            case .rotatingHoist, .rotatingSlackOff:
                // Combined rotation + axial motion: friction vector splits between
                // axial and tangential based on velocity ratio.
                // V_tangential = π * contactOD * RPM / 60
                // V_axial = tripSpeed (m/s)
                // α = atan2(V_tangential, V_axial)
                // axial friction = mu * N * cos(α)
                // tangential friction (torque) = mu * N * sin(α)
                let vTan = Double.pi * contactOD * input.rpm / 60.0 * input.rotationEfficiency
                let vAxial = max(input.tripSpeed_m_per_s, 1e-6)
                let alpha = atan2(vTan, vAxial)
                let totalFriction = mu * normalForce_N
                let axialFriction = totalFriction * cos(alpha)
                let tangentialFriction = totalFriction * sin(alpha)
                if input.mode == .rotatingHoist {
                    frictionForce_N = axialFriction
                    axialForce_N += gravityComponent + axialFriction
                } else {
                    frictionForce_N = axialFriction
                    axialForce_N += gravityComponent - axialFriction
                }
                torque_Nm += tangentialFriction * (contactOD / 2.0)
            }

            // Distributed viscous drag (acts regardless of pipe movement direction)
            // Annular upflow → upward on pipe → reduces tension at surface
            // String downflow → downward on pipe → adds tension at surface
            axialForce_N += stringDrag_N - annularDrag_N

            // Trip-induced viscous drag opposes pipe motion:
            // Trip out → drag resists upward motion → adds tension at surface
            // Trip in → drag resists downward motion → reduces tension (adds to axial, since we accumulate bit→surface)
            switch input.mode {
            case .tripOut, .rotatingHoist:
                axialForce_N += tripViscousDrag_N
            case .tripIn, .sliding, .rotatingSlackOff:
                axialForce_N -= tripViscousDrag_N
            case .rotatingOB, .rotatingDrill:
                break  // stationary or no axial movement
            }

            // Free-hanging weight (no friction, but includes viscous drag)
            freeHangingForce_N += buoyedWeight_N * cos(incAvg) + stringDrag_N - annularDrag_N

            // Pressure-area buoyancy correction.
            // Internal fluid pressure acts on A_i (string fluid), external on A_o (annulus fluid).
            // During circulation with different muds, these densities differ and the string
            // weight changes as heavier/lighter fluid displaces the internal volume.
            if input.pressureAreaBuoyancy {
                let deltaTVD = deepSurvey.tvd - shallowSurvey.tvd
                let A_i = Double.pi / 4.0 * pipeID * pipeID
                let A_o = Double.pi / 4.0 * pipeOD * pipeOD
                let annulusDensity = fluidDensity  // already looked up from annulus layers
                let stringDensity: Double
                if input.stringFluidLayers.isEmpty {
                    stringDensity = annulusDensity
                } else {
                    stringDensity = fluidDensityAtMD(midMD, layers: input.stringFluidLayers, tvdSampler: input.tvdSampler)
                }
                let paCorrection = (stringDensity * A_i - annulusDensity * A_o) * g * deltaTVD
                axialForce_N += paCorrection
                freeHangingForce_N += paCorrection
            }
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
            stringBuoyedWeight_kN: totalBuoyedWeight_N / 1000.0,
            annularPressureLoss_kPa: totalAPL_Pa / 1000.0
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
        // Combined rotation + axial cases (nil when rpm/tripSpeed not provided)
        let rotatingHoistHookLoad_kN: Double?
        let rotatingHoistTorque_kNm: Double?
        let rotatingSlackOffHookLoad_kN: Double?
        let rotatingSlackOffTorque_kNm: Double?
    }

    static func computeAllCases(
        surveys: [SurveyPoint],
        stringSegments: [StringSegment],
        holeSections: [HoleSection],
        fluidLayers: [TripLayerSnapshot],
        bitMD: Double,
        friction: FrictionFactors,
        blockWeight_kN: Double,
        tvdSampler: TvdSampler,
        SABP_kPa: Double = 0,
        floatIsOpen: Bool = false,
        flowRate_m3perMin: Double = 0,
        surgePressure_kPa: Double = 0,
        aplEccentricityFactor: Double = 1.0,
        pressureAreaBuoyancy: Bool = true,
        stringFluidLayers: [TripLayerSnapshot] = [],
        rpm: Double = 0,
        tripSpeedCased_m_per_s: Double = 0,
        tripSpeedOpenHole_m_per_s: Double = 0,
        rotationEfficiencyUp: Double = 1.0,
        rotationEfficiencyDown: Double = 1.0,
        sheaveLineFriction: Double = 0
    ) -> MultiCaseResult {
        // Shift string segments so the bottom of the string aligns with the current bit MD.
        // During a trip, the entire string slides as one piece — the BHA stays at the bottom,
        // heavy DP above it, light DP on top. The original section depths are relative to when
        // the string was at its deepest point, so we offset them to match the current bit position.
        let originalBottom = stringSegments.map(\.bottomMD).max() ?? bitMD
        let shift = bitMD - originalBottom
        let shiftedSegments: [StringSegment] = shift == 0 ? stringSegments : stringSegments.map { seg in
            StringSegment(
                topMD: max(0, seg.topMD + shift),
                bottomMD: seg.bottomMD + shift,
                outerDiameter_m: seg.outerDiameter_m,
                innerDiameter_m: seg.innerDiameter_m,
                linearWeight_kg_per_m: seg.linearWeight_kg_per_m,
                toolJointOD_m: seg.toolJointOD_m,
                steelDensity_kg_per_m3: seg.steelDensity_kg_per_m3,
                totalFlowArea_m2: seg.totalFlowArea_m2
            )
        }

        // Resolve trip speed based on whether bit is in cased or open hole
        let bitIsCased = holeSections.first(where: { bitMD >= $0.topMD && bitMD <= $0.bottomMD })?.isCased ?? false
        let tripSpeed = bitIsCased ? tripSpeedCased_m_per_s : tripSpeedOpenHole_m_per_s

        let pickup = compute(TorqueDragInput(
            surveys: surveys, stringSegments: shiftedSegments,
            holeSections: holeSections, fluidLayers: fluidLayers,
            bitMD: bitMD, mode: .tripOut, friction: friction,
            WOB_kN: 0, blockWeight_kN: blockWeight_kN, tvdSampler: tvdSampler,
            SABP_kPa: SABP_kPa, floatIsOpen: floatIsOpen,
            flowRate_m3perMin: flowRate_m3perMin, surgePressure_kPa: surgePressure_kPa,
            aplEccentricityFactor: aplEccentricityFactor,
            pressureAreaBuoyancy: pressureAreaBuoyancy,
            stringFluidLayers: stringFluidLayers,
            tripSpeed_m_per_s: tripSpeed
        ))

        let slackOff = compute(TorqueDragInput(
            surveys: surveys, stringSegments: shiftedSegments,
            holeSections: holeSections, fluidLayers: fluidLayers,
            bitMD: bitMD, mode: .tripIn, friction: friction,
            WOB_kN: 0, blockWeight_kN: blockWeight_kN, tvdSampler: tvdSampler,
            SABP_kPa: SABP_kPa, floatIsOpen: floatIsOpen,
            flowRate_m3perMin: flowRate_m3perMin, surgePressure_kPa: surgePressure_kPa,
            aplEccentricityFactor: aplEccentricityFactor,
            pressureAreaBuoyancy: pressureAreaBuoyancy,
            stringFluidLayers: stringFluidLayers,
            tripSpeed_m_per_s: tripSpeed
        ))

        let rotating = compute(TorqueDragInput(
            surveys: surveys, stringSegments: shiftedSegments,
            holeSections: holeSections, fluidLayers: fluidLayers,
            bitMD: bitMD, mode: .rotatingOB, friction: friction,
            WOB_kN: 0, blockWeight_kN: blockWeight_kN, tvdSampler: tvdSampler,
            SABP_kPa: SABP_kPa, floatIsOpen: floatIsOpen,
            flowRate_m3perMin: flowRate_m3perMin, surgePressure_kPa: surgePressure_kPa,
            aplEccentricityFactor: aplEccentricityFactor,
            pressureAreaBuoyancy: pressureAreaBuoyancy,
            stringFluidLayers: stringFluidLayers
        ))

        // Combined rotation + axial cases (velocity-ratio model):
        // Friction splits between axial and torque based on velocity ratio.
        // rotationEfficiency scales the tangential velocity (0 = no torque benefit, 1 = full model).
        var rotHoistHL: Double? = nil
        var rotHoistTorque: Double? = nil
        var rotSOHL: Double? = nil
        var rotSOTorque: Double? = nil

        if rpm > 0 && tripSpeed > 0 {
            let rotHoist = compute(TorqueDragInput(
                surveys: surveys, stringSegments: shiftedSegments,
                holeSections: holeSections, fluidLayers: fluidLayers,
                bitMD: bitMD, mode: .rotatingHoist, friction: friction,
                WOB_kN: 0, blockWeight_kN: blockWeight_kN, tvdSampler: tvdSampler,
                SABP_kPa: SABP_kPa, floatIsOpen: floatIsOpen,
                flowRate_m3perMin: flowRate_m3perMin, surgePressure_kPa: surgePressure_kPa,
                aplEccentricityFactor: aplEccentricityFactor,
                pressureAreaBuoyancy: pressureAreaBuoyancy,
                stringFluidLayers: stringFluidLayers,
                rpm: rpm, tripSpeed_m_per_s: tripSpeed,
                rotationEfficiency: rotationEfficiencyUp
            ))
            rotHoistHL = rotHoist.hookLoad_kN
            rotHoistTorque = rotHoist.surfaceTorque_kNm
        }

        if rpm > 0 && tripSpeed > 0 {
            let rotSO = compute(TorqueDragInput(
                surveys: surveys, stringSegments: shiftedSegments,
                holeSections: holeSections, fluidLayers: fluidLayers,
                bitMD: bitMD, mode: .rotatingSlackOff, friction: friction,
                WOB_kN: 0, blockWeight_kN: blockWeight_kN, tvdSampler: tvdSampler,
                SABP_kPa: SABP_kPa, floatIsOpen: floatIsOpen,
                flowRate_m3perMin: flowRate_m3perMin, surgePressure_kPa: surgePressure_kPa,
                aplEccentricityFactor: aplEccentricityFactor,
                pressureAreaBuoyancy: pressureAreaBuoyancy,
                stringFluidLayers: stringFluidLayers,
                rpm: rpm, tripSpeed_m_per_s: tripSpeed,
                rotationEfficiency: rotationEfficiencyDown
            ))
            rotSOHL = rotSO.hookLoad_kN
            rotSOTorque = rotSO.surfaceTorque_kNm
        }

        // Sheave/line friction: hoisting increases measured load, lowering decreases it.
        let sf = sheaveLineFriction
        return MultiCaseResult(
            pickupHookLoad_kN: pickup.hookLoad_kN * (1 + sf),
            slackOffHookLoad_kN: slackOff.hookLoad_kN * (1 - sf),
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
            rotatingResult: rotating,
            rotatingHoistHookLoad_kN: rotHoistHL.map { $0 * (1 + sf) },
            rotatingHoistTorque_kNm: rotHoistTorque,
            rotatingSlackOffHookLoad_kN: rotSOHL.map { $0 * (1 - sf) },
            rotatingSlackOffTorque_kNm: rotSOTorque
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
        tvdSampler: TvdSampler,
        SABP_kPa: Double = 0,
        floatIsOpen: Bool = false,
        flowRate_m3perMin: Double = 0,
        surgePressure_kPa: Double = 0,
        aplEccentricityFactor: Double = 1.0,
        pressureAreaBuoyancy: Bool = true,
        stringFluidLayers: [TripLayerSnapshot] = []
    ) -> [SensitivityResult] {
        frictionFactors.map { ff in
            let friction = FrictionFactors(cased: ff, openHole: ff)
            let multi = computeAllCases(
                surveys: surveys, stringSegments: stringSegments,
                holeSections: holeSections, fluidLayers: fluidLayers,
                bitMD: bitMD, friction: friction,
                blockWeight_kN: blockWeight_kN, tvdSampler: tvdSampler,
                SABP_kPa: SABP_kPa, floatIsOpen: floatIsOpen,
                flowRate_m3perMin: flowRate_m3perMin,
                surgePressure_kPa: surgePressure_kPa,
                aplEccentricityFactor: aplEccentricityFactor,
                pressureAreaBuoyancy: pressureAreaBuoyancy,
                stringFluidLayers: stringFluidLayers
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
                steelDensity_kg_per_m3: s.steelDensity_kg_per_m3,
                totalFlowArea_m2: s.totalFlowArea_m2
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
            stringBuoyedWeight_kN: 0,
            annularPressureLoss_kPa: 0
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
        case .rotatingOB, .rotatingDrill, .rotatingHoist, .rotatingSlackOff:
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

    /// Compute total annular pressure loss (APL) from shoe to surface (Pa).
    /// Uses the same Power-law slot approximation as the per-segment drag calculation.
    private static func computeAnnularPressureLoss(
        intervals: [(deep: SurveyPoint, shallow: SurveyPoint)],
        input: TorqueDragInput
    ) -> Double {
        guard input.flowRate_m3perMin > 0 else { return 0 }
        let Q_m3ps = input.flowRate_m3perMin / 60.0
        var totalAPL_Pa: Double = 0

        for interval in intervals {
            let deltaL = interval.deep.md - interval.shallow.md
            guard deltaL > 0.001 else { continue }

            let midMD = (interval.deep.md + interval.shallow.md) / 2.0
            let pipeOD = stringGeometry(at: midMD, segments: input.stringSegments).outerDiameter_m
            let holeID = holeDiameterAt(midMD, holeSections: input.holeSections)
            let D_h = holeID - pipeOD
            guard D_h > 1e-6 else { continue }

            let A_ann = Double.pi / 4.0 * (holeID * holeID - pipeOD * pipeOD)
            guard A_ann > 1e-8 else { continue }

            let V_ann = Q_m3ps / A_ann
            let rheology = fluidRheologyAtMD(midMD, layers: input.fluidLayers)
            let n = rheology.n
            let K = rheology.K_Pa_sn

            // Power-law wall shear stress (annular slot approximation)
            let gamma_ann = 12.0 * V_ann / D_h * (2.0 + 1.0 / n) / 3.0
            let tau_ann = K * pow(max(gamma_ann, 1e-6), n)
            let dP_Pa_per_m = 4.0 * tau_ann / D_h
            totalAPL_Pa += dP_Pa_per_m * deltaL
        }

        return totalAPL_Pa
    }

    /// Look up Power-law rheology (n, K) at a given MD from the current fluid layers.
    /// Returns (flowBehaviorIndex, consistencyIndex_Pa_sn).
    /// Falls back to Newtonian water if no rheology data available.
    private static func fluidRheologyAtMD(
        _ md: Double,
        layers: [TripLayerSnapshot]
    ) -> (n: Double, K_Pa_sn: Double) {
        let layer = layers.first(where: { md >= $0.topMD && md <= $0.bottomMD })
            ?? layers.min(by: {
                let d0 = min(abs(md - $0.topMD), abs(md - $0.bottomMD))
                let d1 = min(abs(md - $1.topMD), abs(md - $1.bottomMD))
                return d0 < d1
            })
        guard let layer else { return (1.0, 0.001) }

        var theta600: Double = 0
        var theta300: Double = 0

        if let d600 = layer.dial600, let d300 = layer.dial300, d600 > 0, d300 > 0 {
            theta600 = d600
            theta300 = d300
        } else if let pv = layer.pv_cP, let yp = layer.yp_Pa, (pv > 0 || yp > 0) {
            let ypFann = yp / 0.51  // Pa → Fann dial units
            theta300 = pv + ypFann
            theta600 = 2.0 * pv + ypFann
        } else {
            return (1.0, 0.001)  // Newtonian fallback
        }

        guard theta300 > 0.1, theta600 > theta300 * 0.5 else { return (1.0, 0.001) }

        let n = 3.322 * log10(theta600 / theta300)
        let K = 0.51 * theta300 / pow(511.0, n)  // Pa·s^n
        return (max(0.1, min(n, 1.5)), max(1e-6, K))
    }
}
