//
//  MPDReading.swift
//  Josh Well Control for Mac
//
//  Individual reading for MPD tracking
//  Records flow rate, density, and pressure data
//

import Foundation
import SwiftData

@Model
final class MPDReading {
    var id: UUID = UUID()
    var timestamp: Date = Date.now

    // Input values
    var flowRate_m3_per_min: Double = 0.0
    var densityOut_kgm3: Double = 1080.0
    var chokeFriction_kPa: Double = 0.0

    // Bit depth at time of reading (captured, not dynamic)
    var bitMD_m: Double = 0.0

    // Circulating state
    var isCirculating: Bool = true

    // Shut-in pressure (when not circulating)
    var shutInPressure_kPa: Double = 0.0

    // Optional notes
    var notes: String = ""

    // Parent relationship
    @Relationship(deleteRule: .nullify)
    var mpdSheet: MPDSheet?

    // MARK: - Computed Properties (using parent sheet's geometry)

    /// APL to heel (kPa)
    var aplToHeel_kPa: Double {
        guard let sheet = mpdSheet, isCirculating else { return 0 }
        return sheet.aplToDepth(
            sheet.heelMD_m,
            density_kgm3: densityOut_kgm3,
            flowRate_m3_per_min: flowRate_m3_per_min,
            chokeFriction_kPa: chokeFriction_kPa
        )
    }

    /// APL to bit (kPa) - uses reading's captured bit depth
    var aplToBit_kPa: Double {
        guard let sheet = mpdSheet, isCirculating else { return 0 }
        return sheet.aplToDepth(
            bitMD_m,
            density_kgm3: densityOut_kgm3,
            flowRate_m3_per_min: flowRate_m3_per_min,
            chokeFriction_kPa: chokeFriction_kPa
        )
    }

    /// TVD at bit (using reading's captured bit depth)
    var bitTVD_m: Double {
        mpdSheet?.project?.tvd(of: bitMD_m) ?? bitMD_m
    }

    /// APL to toe - extrapolated (kPa)
    var aplToToe_kPa: Double {
        guard let sheet = mpdSheet, isCirculating else { return 0 }
        return sheet.aplToDepth(
            sheet.toeMD_m,
            density_kgm3: densityOut_kgm3,
            flowRate_m3_per_min: flowRate_m3_per_min,
            chokeFriction_kPa: chokeFriction_kPa
        )
    }

    /// ECD at heel (kg/m³) - when circulating
    var ecdAtHeel_kgm3: Double {
        guard let sheet = mpdSheet, isCirculating else { return densityOut_kgm3 }
        return sheet.ecdAtHeel(
            density_kgm3: densityOut_kgm3,
            flowRate_m3_per_min: flowRate_m3_per_min,
            chokeFriction_kPa: chokeFriction_kPa
        )
    }

    /// ECD at bit (kg/m³) - when circulating, uses reading's captured bit depth
    var ecdAtBit_kgm3: Double {
        guard isCirculating else { return densityOut_kgm3 }
        return APLCalculationService.shared.ecd(
            staticDensity_kgm3: densityOut_kgm3,
            apl_kPa: aplToBit_kPa,
            tvd_m: bitTVD_m
        )
    }

    /// ECD at toe (kg/m³) - extrapolated to TD, when circulating
    var ecdAtToe_kgm3: Double {
        guard let sheet = mpdSheet, isCirculating else { return densityOut_kgm3 }
        return sheet.ecdAtToe(
            density_kgm3: densityOut_kgm3,
            flowRate_m3_per_min: flowRate_m3_per_min,
            chokeFriction_kPa: chokeFriction_kPa
        )
    }

    /// ESD at heel (kg/m³) - when shut-in
    var esdAtHeel_kgm3: Double {
        guard let sheet = mpdSheet, !isCirculating else { return densityOut_kgm3 }
        return sheet.esdAtHeel(
            density_kgm3: densityOut_kgm3,
            shutInPressure_kPa: shutInPressure_kPa
        )
    }

    /// ESD at bit (kg/m³) - when shut-in, uses reading's captured bit depth
    var esdAtBit_kgm3: Double {
        guard !isCirculating else { return densityOut_kgm3 }
        return APLCalculationService.shared.esd(
            staticDensity_kgm3: densityOut_kgm3,
            surfacePressure_kPa: shutInPressure_kPa,
            tvd_m: bitTVD_m
        )
    }

    /// ESD at toe (kg/m³) - extrapolated to TD, when shut-in
    var esdAtToe_kgm3: Double {
        guard let sheet = mpdSheet, !isCirculating else { return densityOut_kgm3 }
        return sheet.esdAtToe(
            density_kgm3: densityOut_kgm3,
            shutInPressure_kPa: shutInPressure_kPa
        )
    }

    /// Effective density at heel (ECD if circulating, ESD if shut-in)
    var effectiveDensityAtHeel_kgm3: Double {
        isCirculating ? ecdAtHeel_kgm3 : esdAtHeel_kgm3
    }

    /// Effective density at bit (ECD if circulating, ESD if shut-in)
    var effectiveDensityAtBit_kgm3: Double {
        isCirculating ? ecdAtBit_kgm3 : esdAtBit_kgm3
    }

    /// Effective density at toe - extrapolated (ECD if circulating, ESD if shut-in)
    var effectiveDensityAtToe_kgm3: Double {
        isCirculating ? ecdAtToe_kgm3 : esdAtToe_kgm3
    }

    // MARK: - Initialization

    init(
        flowRate_m3_per_min: Double = 0,
        densityOut_kgm3: Double = 1080,
        chokeFriction_kPa: Double = 0,
        bitMD_m: Double = 0,
        isCirculating: Bool = true,
        shutInPressure_kPa: Double = 0,
        notes: String = "",
        mpdSheet: MPDSheet? = nil
    ) {
        self.flowRate_m3_per_min = flowRate_m3_per_min
        self.densityOut_kgm3 = densityOut_kgm3
        self.chokeFriction_kPa = chokeFriction_kPa
        self.bitMD_m = bitMD_m
        self.isCirculating = isCirculating
        self.shutInPressure_kPa = shutInPressure_kPa
        self.notes = notes
        self.mpdSheet = mpdSheet
    }
}
