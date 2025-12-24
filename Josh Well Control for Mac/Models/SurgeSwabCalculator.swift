//
//  SurgeSwabCalculator.swift
//  Josh Well Control for Mac
//
//  Calculates surge and swab pressures for trip operations.
//  Assumes closed-end displacement (bit/float closed).
//

import Foundation

/// Calculator for surge/swab pressures during tripping operations
struct SurgeSwabCalculator {

    // MARK: - Pipe End Type

    enum PipeEndType: String, CaseIterable {
        case closed = "Closed"  // Float/bit closed - displaces full pipe OD
        case open = "Open"      // Float open - displaces pipe wall only (OD² - ID²)
    }

    // MARK: - Input Parameters

    /// Trip speed in m/min (positive = running in, negative = pulling out)
    let tripSpeed_m_per_min: Double

    /// Starting bit depth (MD in meters)
    let startBitMD_m: Double

    /// Ending bit depth (MD in meters)
    let endBitMD_m: Double

    /// Depth step for calculations (meters)
    let depthStep_m: Double

    /// Annulus sections (geometry)
    let annulusSections: [AnnulusSection]

    /// Drill string sections (geometry)
    let drillStringSections: [DrillStringSection]

    /// Active mud properties (rheology source)
    let mud: MudProperties?

    /// Manual clinging constant override (nil = auto-calculate per section)
    let clingingConstantOverride: Double?

    /// Pipe end type (closed or open)
    let pipeEndType: PipeEndType

    /// Eccentricity factor (1.0 = concentric, >1 = eccentric pipe position)
    /// Eccentric pipe increases annular velocity on narrow side
    let eccentricityFactor: Double

    // MARK: - Output

    /// Result at each depth point
    struct DepthResult: Identifiable {
        let id = UUID()
        let bitMD_m: Double
        let bitTVD_m: Double
        let surgePressure_kPa: Double      // Positive = pressure increase (running in)
        let swabPressure_kPa: Double       // Negative = pressure decrease (pulling out)
        let surgeECD_kgm3: Double          // ECD increase due to surge
        let swabECD_kgm3: Double           // ECD decrease due to swab
        let annularVelocity_m_per_s: Double // Average annular velocity at bit
        let flowRegime: String              // Laminar or Turbulent
        let clingingConstant: Double        // Clinging constant used at this depth
    }

    // MARK: - Clinging Factor Calculation

    /// Calculate Burkhardt clinging constant for a given geometry
    /// - Parameters:
    ///   - pipeOD: Pipe outer diameter (m)
    ///   - holeID: Hole/casing inner diameter (m)
    /// - Returns: Calculated clinging constant Kc
    ///
    /// Burkhardt (1961) clinging constant accounts for mud that clings to the pipe
    /// and moves with it during tripping. The formula is:
    ///   Kc = 0.45 + (Dp/Dhole)² × 0.45
    ///
    /// This is used as (1 + Kc) multiplier on annular velocity, typically
    /// increasing effective velocity by 50-80%.
    static func calculateClingingConstant(
        pipeOD: Double,
        holeID: Double
    ) -> Double {
        guard holeID > pipeOD, pipeOD > 0 else { return 0.45 }

        // Burkhardt clinging constant: Kc = 0.45 + (Dp/Dhole)² × 0.45
        let pipeToHoleRatio = pipeOD / holeID
        return 0.45 + (pipeToHoleRatio * pipeToHoleRatio * 0.45)
    }

    // MARK: - Calculation

    /// Calculate surge/swab pressures for the trip
    func calculate(tvdLookup: (Double) -> Double) -> [DepthResult] {
        var results: [DepthResult] = []

        // Determine direction and iteration
        let isRunningIn = endBitMD_m > startBitMD_m
        let depths: [Double]

        if isRunningIn {
            // Running in: start shallow, go deeper
            depths = stride(from: startBitMD_m, through: endBitMD_m, by: depthStep_m).map { $0 }
        } else {
            // Pulling out: start deep, go shallower
            depths = stride(from: startBitMD_m, through: endBitMD_m, by: -depthStep_m).map { $0 }
        }

        for bitMD in depths {
            let result = calculateAtDepth(bitMD: bitMD, tvdLookup: tvdLookup)
            results.append(result)
        }

        return results
    }

    /// Calculate surge/swab at a specific bit depth
    private func calculateAtDepth(bitMD: Double, tvdLookup: (Double) -> Double) -> DepthResult {
        let bitTVD = tvdLookup(bitMD)
        let tripSpeed_m_per_s = tripSpeed_m_per_min / 60.0

        var totalSurgePressure_kPa = 0.0
        var totalSwabPressure_kPa = 0.0
        var bitAnnularVelocity = 0.0
        var bitFlowRegime = "N/A"
        var bitClingingConstant = clingingConstantOverride ?? 0.45

        // Get mud properties
        let rho = mud?.density_kgm3 ?? 1100
        let pv = mud?.pv_Pa_s ?? 0.02
        let yp = mud?.yp_Pa ?? 5.0

        // Get drill string at bit for displacement calculation
        guard let dsAtBit = drillStringSections.first(where: { $0.topDepth_m <= bitMD && $0.bottomDepth_m >= bitMD }) else {
            return DepthResult(
                bitMD_m: bitMD,
                bitTVD_m: bitTVD,
                surgePressure_kPa: 0,
                swabPressure_kPa: 0,
                surgeECD_kgm3: 0,
                swabECD_kgm3: 0,
                annularVelocity_m_per_s: 0,
                flowRegime: "No DS",
                clingingConstant: bitClingingConstant
            )
        }

        // Displacement area depends on pipe end type
        let pipeOD = dsAtBit.outerDiameter_m
        let pipeID = dsAtBit.innerDiameter_m
        let pipeDisplacementArea: Double
        switch pipeEndType {
        case .closed:
            // Closed-end: displaces full pipe OD
            pipeDisplacementArea = .pi / 4.0 * pipeOD * pipeOD
        case .open:
            // Open-end: displaces only pipe wall (OD² - ID²)
            pipeDisplacementArea = .pi / 4.0 * (pipeOD * pipeOD - pipeID * pipeID)
        }

        // Calculate pressure loss through each annulus section above bit
        for section in annulusSections where section.topDepth_m < bitMD {
            let sectionTop = section.topDepth_m
            let sectionBot = min(section.bottomDepth_m, bitMD)
            let sectionLength = sectionBot - sectionTop

            guard sectionLength > 0 else { continue }

            // Get drill string OD in this section
            let dsInSection = drillStringSections.first(where: {
                $0.topDepth_m <= sectionTop && $0.bottomDepth_m >= sectionBot
            })
            let stringOD = dsInSection?.outerDiameter_m ?? pipeOD

            // Annulus geometry
            let annulusID = section.innerDiameter_m
            let annulusOD = stringOD
            let annulusArea = .pi / 4.0 * (annulusID * annulusID - annulusOD * annulusOD)

            guard annulusArea > 0 else { continue }

            // Equivalent diameter (hydraulic diameter for annulus)
            let De = annulusID - annulusOD

            // Calculate Burkhardt clinging constant for this section (or use override)
            let sectionClingingConstant: Double
            if let override = clingingConstantOverride {
                sectionClingingConstant = override
            } else {
                sectionClingingConstant = Self.calculateClingingConstant(
                    pipeOD: stringOD,
                    holeID: annulusID
                )
            }

            // Annular velocity due to pipe displacement
            // Va = Vpipe × (1 + Kc) × (dispA / Aann) × eccentricityFactor
            // The (1 + Kc) factor accounts for additional mud dragged by the pipe
            // Eccentricity factor accounts for non-concentric pipe position
            let annularVelocity = abs(tripSpeed_m_per_s) * (1.0 + sectionClingingConstant) * (pipeDisplacementArea / annulusArea) * eccentricityFactor

            // Track velocity and clinging at bit depth
            if sectionBot >= bitMD - 1 {
                bitAnnularVelocity = annularVelocity
                bitClingingConstant = sectionClingingConstant
            }

            // Bingham plastic in annulus geometry
            // Wall shear rate: γw = 8V / De (annular approximation)
            let gammaW = max(8.0 * annularVelocity / De, 0.01)

            // Wall shear stress for Bingham: τw = τy + μp × γw
            let tauW = yp + pv * gammaW

            // Pressure gradient for annulus: dP/dL = 2τw / (De/2) = 4τw / De
            // But for wider annuli, use factor of 2 (empirical fit to match field data)
            let dPdL_laminar = 2.0 * tauW / De  // Pa/m

            // Reynolds number for Bingham (using apparent viscosity at wall)
            let mu_apparent = tauW / gammaW  // Apparent viscosity = τw/γw
            let Re_app = rho * annularVelocity * De / mu_apparent

            // Hedstrom number
            let He = rho * yp * De * De / (pv * pv)

            // Critical Reynolds number for Bingham
            let Re_crit = 2100.0 * (1.0 + 0.05 * pow(He, 0.3))

            // Determine flow regime and calculate pressure loss
            let pressureLoss_kPa: Double
            let regime: String

            if Re_app < Re_crit {
                // Laminar flow
                pressureLoss_kPa = dPdL_laminar * sectionLength / 1000.0
                regime = "Laminar"
            } else {
                // Turbulent flow - Darby correlation for Bingham
                let f_turb = 0.079 / pow(Re_app, 0.25)
                let dPdL_turb = f_turb * rho * annularVelocity * annularVelocity / (2.0 * De)

                // Use maximum of laminar and turbulent (smooth transition)
                pressureLoss_kPa = max(dPdL_laminar, dPdL_turb) * sectionLength / 1000.0
                regime = dPdL_turb > dPdL_laminar ? "Turbulent" : "Laminar"
            }

            // Track regime at bit
            if sectionBot >= bitMD - 1 {
                bitFlowRegime = regime
            }

            totalSurgePressure_kPa += pressureLoss_kPa
            totalSwabPressure_kPa += pressureLoss_kPa
        }

        // Convert to ECD change at bit TVD
        // ECD change = ΔP / (0.00981 × TVD)
        let surgeECD = bitTVD > 0 ? totalSurgePressure_kPa / (0.00981 * bitTVD) : 0
        let swabECD = bitTVD > 0 ? totalSwabPressure_kPa / (0.00981 * bitTVD) : 0

        return DepthResult(
            bitMD_m: bitMD,
            bitTVD_m: bitTVD,
            surgePressure_kPa: totalSurgePressure_kPa,
            swabPressure_kPa: -totalSwabPressure_kPa,  // Negative for swab
            surgeECD_kgm3: surgeECD,
            swabECD_kgm3: -swabECD,  // Negative for swab
            annularVelocity_m_per_s: bitAnnularVelocity,
            flowRegime: bitFlowRegime,
            clingingConstant: bitClingingConstant
        )
    }

    // MARK: - Convenience Initializer

    init(
        tripSpeed_m_per_min: Double,
        startBitMD_m: Double,
        endBitMD_m: Double,
        depthStep_m: Double = 100,
        annulusSections: [AnnulusSection],
        drillStringSections: [DrillStringSection],
        mud: MudProperties? = nil,
        clingingConstantOverride: Double? = nil,
        pipeEndType: PipeEndType = .closed,
        eccentricityFactor: Double = 1.0
    ) {
        self.tripSpeed_m_per_min = tripSpeed_m_per_min
        self.startBitMD_m = startBitMD_m
        self.endBitMD_m = endBitMD_m
        self.depthStep_m = depthStep_m
        self.annulusSections = annulusSections
        self.drillStringSections = drillStringSections
        self.mud = mud
        self.clingingConstantOverride = clingingConstantOverride
        self.pipeEndType = pipeEndType
        self.eccentricityFactor = eccentricityFactor
    }
}

// MARK: - Summary Statistics

extension SurgeSwabCalculator {

    struct Summary {
        let maxSurgePressure_kPa: Double
        let maxSwabPressure_kPa: Double
        let maxSurgeECD_kgm3: Double
        let maxSwabECD_kgm3: Double
        let depthOfMaxSurge_m: Double
        let depthOfMaxSwab_m: Double
        let averageClingingConstant: Double
        let pipeDisplacementArea_m2: Double
        let pipeEndType: PipeEndType
        let pipeOD_m: Double
        let pipeID_m: Double
        let hasMissingPipeID: Bool  // True if pipe ID is 0 (open vs closed will be same)
    }

    static func summarize(_ results: [DepthResult]) -> Summary {
        summarize(results, pipeOD: 0, pipeID: 0, pipeEndType: .closed)
    }

    static func summarize(_ results: [DepthResult], pipeOD: Double, pipeID: Double, pipeEndType: PipeEndType) -> Summary {
        let maxSurge = results.max(by: { $0.surgePressure_kPa < $1.surgePressure_kPa })
        let maxSwab = results.min(by: { $0.swabPressure_kPa < $1.swabPressure_kPa })
        let avgClinging = results.isEmpty ? 0.45 : results.map(\.clingingConstant).reduce(0, +) / Double(results.count)

        // Calculate displacement area based on pipe end type
        let displacementArea: Double
        switch pipeEndType {
        case .closed:
            displacementArea = .pi / 4.0 * pipeOD * pipeOD
        case .open:
            displacementArea = .pi / 4.0 * (pipeOD * pipeOD - pipeID * pipeID)
        }

        return Summary(
            maxSurgePressure_kPa: maxSurge?.surgePressure_kPa ?? 0,
            maxSwabPressure_kPa: abs(maxSwab?.swabPressure_kPa ?? 0),
            maxSurgeECD_kgm3: maxSurge?.surgeECD_kgm3 ?? 0,
            maxSwabECD_kgm3: abs(maxSwab?.swabECD_kgm3 ?? 0),
            depthOfMaxSurge_m: maxSurge?.bitMD_m ?? 0,
            depthOfMaxSwab_m: maxSwab?.bitMD_m ?? 0,
            averageClingingConstant: avgClinging,
            pipeDisplacementArea_m2: displacementArea,
            pipeEndType: pipeEndType,
            pipeOD_m: pipeOD,
            pipeID_m: pipeID,
            hasMissingPipeID: pipeID == 0 || pipeID < 0.001
        )
    }

    /// Create summary with pipe info from calculator
    func summarize(_ results: [DepthResult]) -> Summary {
        // Get pipe dimensions from the deepest drill string section
        let deepestDS = drillStringSections.max(by: { $0.bottomDepth_m < $1.bottomDepth_m })
        let pipeOD = deepestDS?.outerDiameter_m ?? 0
        let pipeID = deepestDS?.innerDiameter_m ?? 0

        return Self.summarize(results, pipeOD: pipeOD, pipeID: pipeID, pipeEndType: pipeEndType)
    }
}
