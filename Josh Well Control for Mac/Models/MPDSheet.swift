//
//  MPDSheet.swift
//  Josh Well Control for Mac
//
//  Managed Pressure Drilling tracking sheet
//  Tracks pore pressure, ECD, and ESD at heel, bit, and toe positions
//

import Foundation
import SwiftData

@Model
final class MPDSheet {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    // Project relationship
    @Relationship(deleteRule: .nullify)
    var project: ProjectState?

    // Well positions (MD in meters)
    var heelMD_m: Double = 0.0
    var bitMD_m: Double = 0.0   // Current bit depth (tracked position)
    var toeMD_m: Double = 0.0   // Total depth / toe (for extrapolation)

    // Pore pressure window (for reference lines on chart)
    var porePressure_kgm3: Double = 1000.0  // Pore pressure gradient equivalent
    var fracGradient_kgm3: Double = 1800.0  // Frac gradient equivalent

    // Default choke friction (can be overridden per reading)
    var defaultCirculatingChoke_kPa: Double = 0.0
    var defaultShutInChoke_kPa: Double = 0.0

    // Readings relationship
    @Relationship(deleteRule: .cascade, inverse: \MPDReading.mpdSheet)
    var readings: [MPDReading]?

    // MARK: - Computed Properties

    /// Get TVD at heel from project surveys
    var heelTVD_m: Double {
        project?.tvd(of: heelMD_m) ?? heelMD_m
    }

    /// Get TVD at bit from project surveys
    var bitTVD_m: Double {
        project?.tvd(of: bitMD_m) ?? bitMD_m
    }

    /// Get TVD at toe from project surveys
    var toeTVD_m: Double {
        project?.tvd(of: toeMD_m) ?? toeMD_m
    }

    /// Sorted readings by timestamp (most recent first)
    var sortedReadings: [MPDReading] {
        (readings ?? []).sorted { $0.timestamp > $1.timestamp }
    }

    /// Most recent reading
    var latestReading: MPDReading? {
        sortedReadings.first
    }

    // MARK: - Initialization

    init(
        name: String = "MPD Sheet",
        heelMD_m: Double = 0,
        bitMD_m: Double = 0,
        toeMD_m: Double = 0,
        porePressure_kgm3: Double = 1000,
        fracGradient_kgm3: Double = 1800,
        defaultCirculatingChoke_kPa: Double = 0,
        defaultShutInChoke_kPa: Double = 0,
        project: ProjectState? = nil
    ) {
        self.name = name
        self.heelMD_m = heelMD_m
        self.bitMD_m = bitMD_m
        self.toeMD_m = toeMD_m
        self.porePressure_kgm3 = porePressure_kgm3
        self.fracGradient_kgm3 = fracGradient_kgm3
        self.defaultCirculatingChoke_kPa = defaultCirculatingChoke_kPa
        self.defaultShutInChoke_kPa = defaultShutInChoke_kPa
        self.project = project
    }

    // MARK: - Calculations

    /// Calculate APL to a specific depth using project geometry
    /// Automatically extends drill string and annulus to reach the target depth
    func aplToDepth(
        _ depth_m: Double,
        density_kgm3: Double,
        flowRate_m3_per_min: Double,
        chokeFriction_kPa: Double
    ) -> Double {
        guard let project = project else { return 0 }

        // Extend sections to reach target depth (simulates drilling progress)
        let extendedAnnulus = extendAnnulusToDepth(project.annulus ?? [], targetDepth: depth_m)
        let extendedString = extendDrillStringToDepth(project.drillString ?? [], targetDepth: depth_m)

        return APLCalculationService.shared.aplToDepth(
            toDepth_m: depth_m,
            density_kgm3: density_kgm3,
            flowRate_m3_per_min: flowRate_m3_per_min,
            annulusSections: extendedAnnulus,
            drillStringSections: extendedString,
            chokeFriction_kPa: chokeFriction_kPa
        )
    }

    /// Extend the deepest annulus section to reach target depth
    private func extendAnnulusToDepth(_ sections: [AnnulusSection], targetDepth: Double) -> [AnnulusSection] {
        guard !sections.isEmpty else { return sections }

        var extended = sections
        // Find the deepest section (by bottom depth)
        if let deepestIndex = extended.indices.max(by: { extended[$0].bottomDepth_m < extended[$1].bottomDepth_m }) {
            let deepest = extended[deepestIndex]
            if deepest.bottomDepth_m < targetDepth {
                // Calculate new length to reach target depth
                let newLength = targetDepth - deepest.topDepth_m
                // Create extended copy with same properties but extended length
                let extendedSection = AnnulusSection(
                    name: deepest.name,
                    topDepth_m: deepest.topDepth_m,
                    length_m: newLength,
                    innerDiameter_m: deepest.innerDiameter_m,
                    outerDiameter_m: deepest.outerDiameter_m,
                    isCased: deepest.isCased
                )
                extended[deepestIndex] = extendedSection
            }
        }
        return extended
    }

    /// Extend drill string by adding pipe at surface
    /// The uppermost section gets longer, all deeper sections shift down (topDepth increases)
    private func extendDrillStringToDepth(_ sections: [DrillStringSection], targetDepth: Double) -> [DrillStringSection] {
        guard !sections.isEmpty else { return sections }

        // Find current max depth
        guard let currentMaxDepth = sections.map({ $0.bottomDepth_m }).max(),
              targetDepth > currentMaxDepth else {
            return sections
        }

        let extensionAmount = targetDepth - currentMaxDepth

        // Sort by topDepth to identify uppermost section
        let sorted = sections.sorted { $0.topDepth_m < $1.topDepth_m }
        guard let uppermost = sorted.first else { return sections }

        var extended: [DrillStringSection] = []

        for section in sections {
            if section.id == uppermost.id {
                // Uppermost section: extend its length
                let extendedSection = DrillStringSection(
                    name: section.name,
                    topDepth_m: section.topDepth_m,
                    length_m: section.length_m + extensionAmount,
                    outerDiameter_m: section.outerDiameter_m,
                    innerDiameter_m: section.innerDiameter_m
                )
                extended.append(extendedSection)
            } else {
                // Deeper sections: shift topDepth down, keep same length
                let shiftedSection = DrillStringSection(
                    name: section.name,
                    topDepth_m: section.topDepth_m + extensionAmount,
                    length_m: section.length_m,
                    outerDiameter_m: section.outerDiameter_m,
                    innerDiameter_m: section.innerDiameter_m
                )
                extended.append(shiftedSection)
            }
        }

        return extended
    }

    /// Calculate ECD at heel
    func ecdAtHeel(
        density_kgm3: Double,
        flowRate_m3_per_min: Double,
        chokeFriction_kPa: Double
    ) -> Double {
        let apl = aplToDepth(heelMD_m, density_kgm3: density_kgm3, flowRate_m3_per_min: flowRate_m3_per_min, chokeFriction_kPa: chokeFriction_kPa)
        return APLCalculationService.shared.ecd(
            staticDensity_kgm3: density_kgm3,
            apl_kPa: apl,
            tvd_m: heelTVD_m
        )
    }

    /// Calculate ECD at bit (current bit depth)
    func ecdAtBit(
        density_kgm3: Double,
        flowRate_m3_per_min: Double,
        chokeFriction_kPa: Double
    ) -> Double {
        let apl = aplToDepth(bitMD_m, density_kgm3: density_kgm3, flowRate_m3_per_min: flowRate_m3_per_min, chokeFriction_kPa: chokeFriction_kPa)
        return APLCalculationService.shared.ecd(
            staticDensity_kgm3: density_kgm3,
            apl_kPa: apl,
            tvd_m: bitTVD_m
        )
    }

    /// Calculate ECD at toe (extrapolated to TD)
    func ecdAtToe(
        density_kgm3: Double,
        flowRate_m3_per_min: Double,
        chokeFriction_kPa: Double
    ) -> Double {
        let apl = aplToDepth(toeMD_m, density_kgm3: density_kgm3, flowRate_m3_per_min: flowRate_m3_per_min, chokeFriction_kPa: chokeFriction_kPa)
        return APLCalculationService.shared.ecd(
            staticDensity_kgm3: density_kgm3,
            apl_kPa: apl,
            tvd_m: toeTVD_m
        )
    }

    /// Calculate ESD at heel (shut-in)
    func esdAtHeel(
        density_kgm3: Double,
        shutInPressure_kPa: Double
    ) -> Double {
        APLCalculationService.shared.esd(
            staticDensity_kgm3: density_kgm3,
            surfacePressure_kPa: shutInPressure_kPa,
            tvd_m: heelTVD_m
        )
    }

    /// Calculate ESD at bit (shut-in, current bit depth)
    func esdAtBit(
        density_kgm3: Double,
        shutInPressure_kPa: Double
    ) -> Double {
        APLCalculationService.shared.esd(
            staticDensity_kgm3: density_kgm3,
            surfacePressure_kPa: shutInPressure_kPa,
            tvd_m: bitTVD_m
        )
    }

    /// Calculate ESD at toe (shut-in, extrapolated to TD)
    func esdAtToe(
        density_kgm3: Double,
        shutInPressure_kPa: Double
    ) -> Double {
        APLCalculationService.shared.esd(
            staticDensity_kgm3: density_kgm3,
            surfacePressure_kPa: shutInPressure_kPa,
            tvd_m: toeTVD_m
        )
    }
}
