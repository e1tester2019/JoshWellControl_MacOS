//
//  FrozenSimulationInputs.swift
//  Josh Well Control for Mac
//
//  Lightweight Codable snapshots for freezing simulation inputs.
//  These capture the essential well state at simulation time so results remain valid.
//

import Foundation
import CryptoKit

// MARK: - Frozen Drill String

/// Minimal drill string data needed for simulation calculations
struct FrozenDrillString: Codable, Equatable {
    let name: String
    let topDepth_m: Double
    let length_m: Double
    let outerDiameter_m: Double
    let innerDiameter_m: Double

    var bottomDepth_m: Double { topDepth_m + length_m }

    init(from section: DrillStringSection) {
        self.name = section.name
        self.topDepth_m = section.topDepth_m
        self.length_m = section.length_m
        self.outerDiameter_m = section.outerDiameter_m
        self.innerDiameter_m = section.innerDiameter_m
    }

    init(name: String, topDepth_m: Double, length_m: Double, outerDiameter_m: Double, innerDiameter_m: Double) {
        self.name = name
        self.topDepth_m = topDepth_m
        self.length_m = length_m
        self.outerDiameter_m = outerDiameter_m
        self.innerDiameter_m = innerDiameter_m
    }
}

// MARK: - Frozen Annulus

/// Minimal annulus data needed for simulation calculations
struct FrozenAnnulus: Codable, Equatable {
    let name: String
    let topDepth_m: Double
    let length_m: Double
    let innerDiameter_m: Double  // wellbore/casing ID
    let outerDiameter_m: Double  // string OD in this section

    var bottomDepth_m: Double { topDepth_m + length_m }

    /// Flow area for this annulus section (m²)
    var flowArea_m2: Double {
        let id = innerDiameter_m
        let od = outerDiameter_m
        guard id > od else { return 0 }
        return .pi * 0.25 * (id * id - od * od)
    }

    /// Section volume (m³)
    var volume_m3: Double {
        flowArea_m2 * length_m
    }

    init(from section: AnnulusSection) {
        self.name = section.name
        self.topDepth_m = section.topDepth_m
        self.length_m = section.length_m
        self.innerDiameter_m = section.innerDiameter_m
        self.outerDiameter_m = section.outerDiameter_m
    }

    init(name: String, topDepth_m: Double, length_m: Double, innerDiameter_m: Double, outerDiameter_m: Double) {
        self.name = name
        self.topDepth_m = topDepth_m
        self.length_m = length_m
        self.innerDiameter_m = innerDiameter_m
        self.outerDiameter_m = outerDiameter_m
    }
}

// MARK: - Frozen Mud

/// Minimal mud data needed for simulation (density + rheology for swab calcs)
struct FrozenMud: Codable, Equatable {
    let name: String
    let density_kgm3: Double
    let dial600: Double?
    let dial300: Double?
    let colorR: Double
    let colorG: Double
    let colorB: Double
    let colorA: Double

    init(from mud: MudProperties) {
        self.name = mud.name
        self.density_kgm3 = mud.density_kgm3
        self.dial600 = mud.dial600
        self.dial300 = mud.dial300
        self.colorR = mud.colorR
        self.colorG = mud.colorG
        self.colorB = mud.colorB
        self.colorA = mud.colorA
    }

    init(name: String, density_kgm3: Double, dial600: Double? = nil, dial300: Double? = nil,
         colorR: Double = 0.8, colorG: Double = 0.8, colorB: Double = 0.0, colorA: Double = 1.0) {
        self.name = name
        self.density_kgm3 = density_kgm3
        self.dial600 = dial600
        self.dial300 = dial300
        self.colorR = colorR
        self.colorG = colorG
        self.colorB = colorB
        self.colorA = colorA
    }

    /// Extract fluid properties as a FluidIdentity
    var fluid: FluidIdentity {
        FluidIdentity(
            density_kgm3: density_kgm3,
            colorR: colorR, colorG: colorG, colorB: colorB, colorA: colorA,
            dial600: dial600 ?? 0, dial300: dial300 ?? 0,
            mudName: name
        )
    }

    /// Power law fit from Fann readings (same as MudProperties)
    func powerLawFit() -> (n: Double, K: Double)? {
        guard let d600 = dial600, let d300 = dial300, d600 > 0, d300 > 0 else { return nil }
        let tau600 = d600 * HydraulicsDefaults.fann35_dialToPa
        let tau300 = d300 * HydraulicsDefaults.fann35_dialToPa
        let g600 = HydraulicsDefaults.fann35_600rpm_shearRate
        let g300 = HydraulicsDefaults.fann35_300rpm_shearRate
        let n = log(tau600 / tau300) / log(g600 / g300)
        let K = tau600 / pow(g600, n)
        return (n, K)
    }
}

// MARK: - Frozen Survey

/// Minimal survey data (MD/TVD pair for interpolation)
struct FrozenSurvey: Codable, Equatable {
    let md: Double
    let tvd: Double

    init(from station: SurveyStation) {
        self.md = station.md
        self.tvd = station.tvd ?? station.md  // fallback to MD if TVD not computed
    }

    init(md: Double, tvd: Double) {
        self.md = md
        self.tvd = tvd
    }
}

// MARK: - Complete Frozen Inputs

/// Complete frozen state for a trip simulation
struct FrozenSimulationInputs: Codable, Equatable {
    let capturedAt: Date
    let drillString: [FrozenDrillString]
    let annulus: [FrozenAnnulus]
    let backfillMud: FrozenMud?
    let activeMud: FrozenMud?
    let surveys: [FrozenSurvey]

    /// Create frozen inputs from current project state
    @MainActor
    init(from project: ProjectState, backfillMud: MudProperties?, activeMud: MudProperties?) {
        self.capturedAt = Date.now
        self.drillString = (project.drillString ?? [])
            .sorted { $0.topDepth_m < $1.topDepth_m }
            .map { FrozenDrillString(from: $0) }
        self.annulus = (project.annulus ?? [])
            .sorted { $0.topDepth_m < $1.topDepth_m }
            .map { FrozenAnnulus(from: $0) }
        self.backfillMud = backfillMud.map { FrozenMud(from: $0) }
        self.activeMud = activeMud.map { FrozenMud(from: $0) }
        self.surveys = (project.surveys ?? [])
            .sorted { $0.md < $1.md }
            .map { FrozenSurvey(from: $0) }
    }

    /// Manual initializer for testing or reconstruction
    init(capturedAt: Date = .now,
         drillString: [FrozenDrillString] = [],
         annulus: [FrozenAnnulus] = [],
         backfillMud: FrozenMud? = nil,
         activeMud: FrozenMud? = nil,
         surveys: [FrozenSurvey] = []) {
        self.capturedAt = capturedAt
        self.drillString = drillString
        self.annulus = annulus
        self.backfillMud = backfillMud
        self.activeMud = activeMud
        self.surveys = surveys
    }

    /// Compute a hash of the inputs for staleness detection
    var inputHash: String {
        var hasher = SHA256()

        // Hash drill string geometry
        for ds in drillString {
            withUnsafeBytes(of: ds.topDepth_m) { hasher.update(bufferPointer: $0) }
            withUnsafeBytes(of: ds.length_m) { hasher.update(bufferPointer: $0) }
            withUnsafeBytes(of: ds.outerDiameter_m) { hasher.update(bufferPointer: $0) }
            withUnsafeBytes(of: ds.innerDiameter_m) { hasher.update(bufferPointer: $0) }
        }

        // Hash annulus geometry
        for ann in annulus {
            withUnsafeBytes(of: ann.topDepth_m) { hasher.update(bufferPointer: $0) }
            withUnsafeBytes(of: ann.length_m) { hasher.update(bufferPointer: $0) }
            withUnsafeBytes(of: ann.innerDiameter_m) { hasher.update(bufferPointer: $0) }
            withUnsafeBytes(of: ann.outerDiameter_m) { hasher.update(bufferPointer: $0) }
        }

        // Hash mud properties
        if let mud = backfillMud {
            withUnsafeBytes(of: mud.density_kgm3) { hasher.update(bufferPointer: $0) }
            if let d600 = mud.dial600 { withUnsafeBytes(of: d600) { hasher.update(bufferPointer: $0) } }
            if let d300 = mud.dial300 { withUnsafeBytes(of: d300) { hasher.update(bufferPointer: $0) } }
        }

        // Hash survey data
        for survey in surveys {
            withUnsafeBytes(of: survey.md) { hasher.update(bufferPointer: $0) }
            withUnsafeBytes(of: survey.tvd) { hasher.update(bufferPointer: $0) }
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    /// Create a TvdSampler from frozen surveys
    func makeTvdSampler() -> TvdSampler {
        TvdSampler(frozenSurveys: surveys)
    }

    /// Total annulus volume (m³)
    var totalAnnulusVolume_m3: Double {
        annulus.reduce(0) { $0 + $1.volume_m3 }
    }

    /// Max depth from drill string
    var maxDrillStringDepth_m: Double {
        drillString.map { $0.bottomDepth_m }.max() ?? 0
    }

    /// Max depth from annulus
    var maxAnnulusDepth_m: Double {
        annulus.map { $0.bottomDepth_m }.max() ?? 0
    }
}


// MARK: - Compression Helpers

extension FrozenSimulationInputs {
    /// Encode and compress to Data for storage
    func toCompressedData() -> Data? {
        guard let jsonData = try? JSONEncoder().encode(self) else { return nil }
        return try? (jsonData as NSData).compressed(using: .lzfse) as Data
    }

    /// Decode from compressed Data
    static func fromCompressedData(_ data: Data) -> FrozenSimulationInputs? {
        guard let decompressed = try? (data as NSData).decompressed(using: .lzfse) as Data else { return nil }
        return try? JSONDecoder().decode(FrozenSimulationInputs.self, from: decompressed)
    }
}

// MARK: - Staleness Checking

extension FrozenSimulationInputs {
    /// Compare frozen inputs to current project state
    @MainActor
    func isStale(comparedTo project: ProjectState, backfillMud: MudProperties?, activeMud: MudProperties?) -> Bool {
        let currentInputs = FrozenSimulationInputs(from: project, backfillMud: backfillMud, activeMud: activeMud)
        return self.inputHash != currentInputs.inputHash
    }

    /// Get a description of what changed (for UI display)
    @MainActor
    func changes(comparedTo project: ProjectState, backfillMud: MudProperties?, activeMud: MudProperties?) -> [String] {
        var changes: [String] = []

        let currentDS = (project.drillString ?? []).sorted { $0.topDepth_m < $1.topDepth_m }
        let currentAnn = (project.annulus ?? []).sorted { $0.topDepth_m < $1.topDepth_m }

        // Check drill string
        if currentDS.count != drillString.count {
            changes.append("Drill string sections changed (\(drillString.count) → \(currentDS.count))")
        } else {
            for (i, (frozen, current)) in zip(drillString, currentDS).enumerated() {
                if abs(frozen.outerDiameter_m - current.outerDiameter_m) > 0.0001 ||
                   abs(frozen.innerDiameter_m - current.innerDiameter_m) > 0.0001 {
                    changes.append("Drill string section \(i+1) geometry changed")
                }
                if abs(frozen.topDepth_m - current.topDepth_m) > 0.1 ||
                   abs(frozen.length_m - current.length_m) > 0.1 {
                    changes.append("Drill string section \(i+1) depths changed")
                }
            }
        }

        // Check annulus
        if currentAnn.count != annulus.count {
            changes.append("Annulus sections changed (\(annulus.count) → \(currentAnn.count))")
        } else {
            for (i, (frozen, current)) in zip(annulus, currentAnn).enumerated() {
                if abs(frozen.innerDiameter_m - current.innerDiameter_m) > 0.0001 ||
                   abs(frozen.outerDiameter_m - current.outerDiameter_m) > 0.0001 {
                    changes.append("Annulus section \(i+1) geometry changed")
                }
            }
        }

        // Check mud
        if let frozenMud = self.backfillMud, let currentMud = backfillMud {
            if abs(frozenMud.density_kgm3 - currentMud.density_kgm3) > 1 {
                changes.append("Backfill mud density changed (\(Int(frozenMud.density_kgm3)) → \(Int(currentMud.density_kgm3)) kg/m³)")
            }
        } else if (self.backfillMud == nil) != (backfillMud == nil) {
            changes.append("Backfill mud configuration changed")
        }

        return changes
    }
}
