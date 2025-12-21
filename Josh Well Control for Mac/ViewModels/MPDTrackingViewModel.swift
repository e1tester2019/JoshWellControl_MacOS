//
//  MPDTrackingViewModel.swift
//  Josh Well Control for Mac
//
//  ViewModel for MPD (Managed Pressure Drilling) tracking
//  Manages readings and chart data for ECD/ESD monitoring
//

import Foundation
import SwiftUI
import Observation
import SwiftData

@Observable
class MPDTrackingViewModel {

    // MARK: - State

    private(set) var context: ModelContext?
    var boundProject: ProjectState?
    var boundSheet: MPDSheet?

    // MARK: - Input Fields (for new reading)

    var inputFlowRate_m3_per_min: Double = 0.8
    var inputDensityOut_kgm3: Double = 1080.0
    var inputChokeFriction_kPa: Double = 0.0
    var inputIsCirculating: Bool = true
    var inputShutInPressure_kPa: Double = 0.0
    var inputNotes: String = ""

    // MARK: - Sheet Configuration

    var sheetName: String = "MPD Sheet"
    var heelMD_m: Double = 0.0
    var bitMD_m: Double = 0.0
    var toeMD_m: Double = 0.0
    var porePressure_kgm3: Double = 1000.0
    var fracGradient_kgm3: Double = 1800.0
    var defaultCirculatingChoke_kPa: Double = 0.0
    var defaultShutInChoke_kPa: Double = 0.0

    // MARK: - Computed Preview (before adding reading)

    /// Preview APL to heel
    var previewAPLToHeel_kPa: Double {
        guard let project = boundProject, inputIsCirculating else { return 0 }
        return APLCalculationService.shared.aplToDepth(
            toDepth_m: heelMD_m,
            density_kgm3: inputDensityOut_kgm3,
            flowRate_m3_per_min: inputFlowRate_m3_per_min,
            annulusSections: project.annulus ?? [],
            drillStringSections: project.drillString ?? [],
            chokeFriction_kPa: inputChokeFriction_kPa
        )
    }

    /// Preview APL to bit
    var previewAPLToBit_kPa: Double {
        guard let project = boundProject, inputIsCirculating else { return 0 }
        return APLCalculationService.shared.aplToDepth(
            toDepth_m: bitMD_m,
            density_kgm3: inputDensityOut_kgm3,
            flowRate_m3_per_min: inputFlowRate_m3_per_min,
            annulusSections: project.annulus ?? [],
            drillStringSections: project.drillString ?? [],
            chokeFriction_kPa: inputChokeFriction_kPa
        )
    }

    /// Preview APL to toe (extrapolated)
    var previewAPLToToe_kPa: Double {
        guard let project = boundProject, inputIsCirculating else { return 0 }
        return APLCalculationService.shared.aplToDepth(
            toDepth_m: toeMD_m,
            density_kgm3: inputDensityOut_kgm3,
            flowRate_m3_per_min: inputFlowRate_m3_per_min,
            annulusSections: project.annulus ?? [],
            drillStringSections: project.drillString ?? [],
            chokeFriction_kPa: inputChokeFriction_kPa
        )
    }

    /// Preview ECD at heel
    var previewECDAtHeel_kgm3: Double {
        guard inputIsCirculating else { return inputDensityOut_kgm3 }
        let tvd = boundProject?.tvd(of: heelMD_m) ?? heelMD_m
        return APLCalculationService.shared.ecd(
            staticDensity_kgm3: inputDensityOut_kgm3,
            apl_kPa: previewAPLToHeel_kPa,
            tvd_m: tvd
        )
    }

    /// Preview ECD at bit
    var previewECDAtBit_kgm3: Double {
        guard inputIsCirculating else { return inputDensityOut_kgm3 }
        let tvd = boundProject?.tvd(of: bitMD_m) ?? bitMD_m
        return APLCalculationService.shared.ecd(
            staticDensity_kgm3: inputDensityOut_kgm3,
            apl_kPa: previewAPLToBit_kPa,
            tvd_m: tvd
        )
    }

    /// Preview ECD at toe (extrapolated)
    var previewECDAtToe_kgm3: Double {
        guard inputIsCirculating else { return inputDensityOut_kgm3 }
        let tvd = boundProject?.tvd(of: toeMD_m) ?? toeMD_m
        return APLCalculationService.shared.ecd(
            staticDensity_kgm3: inputDensityOut_kgm3,
            apl_kPa: previewAPLToToe_kPa,
            tvd_m: tvd
        )
    }

    /// Preview ESD at heel (when shut-in)
    var previewESDAtHeel_kgm3: Double {
        guard !inputIsCirculating else { return inputDensityOut_kgm3 }
        let tvd = boundProject?.tvd(of: heelMD_m) ?? heelMD_m
        return APLCalculationService.shared.esd(
            staticDensity_kgm3: inputDensityOut_kgm3,
            surfacePressure_kPa: inputShutInPressure_kPa,
            tvd_m: tvd
        )
    }

    /// Preview ESD at bit (when shut-in)
    var previewESDAtBit_kgm3: Double {
        guard !inputIsCirculating else { return inputDensityOut_kgm3 }
        let tvd = boundProject?.tvd(of: bitMD_m) ?? bitMD_m
        return APLCalculationService.shared.esd(
            staticDensity_kgm3: inputDensityOut_kgm3,
            surfacePressure_kPa: inputShutInPressure_kPa,
            tvd_m: tvd
        )
    }

    /// Preview ESD at toe (when shut-in, extrapolated)
    var previewESDAtToe_kgm3: Double {
        guard !inputIsCirculating else { return inputDensityOut_kgm3 }
        let tvd = boundProject?.tvd(of: toeMD_m) ?? toeMD_m
        return APLCalculationService.shared.esd(
            staticDensity_kgm3: inputDensityOut_kgm3,
            surfacePressure_kPa: inputShutInPressure_kPa,
            tvd_m: tvd
        )
    }

    /// Effective density at heel (ECD if circulating, ESD if shut-in)
    var previewEffectiveDensityAtHeel_kgm3: Double {
        inputIsCirculating ? previewECDAtHeel_kgm3 : previewESDAtHeel_kgm3
    }

    /// Effective density at bit (ECD if circulating, ESD if shut-in)
    var previewEffectiveDensityAtBit_kgm3: Double {
        inputIsCirculating ? previewECDAtBit_kgm3 : previewESDAtBit_kgm3
    }

    /// Effective density at toe - extrapolated (ECD if circulating, ESD if shut-in)
    var previewEffectiveDensityAtToe_kgm3: Double {
        inputIsCirculating ? previewECDAtToe_kgm3 : previewESDAtToe_kgm3
    }

    // MARK: - Chart Data

    struct ChartPoint: Identifiable {
        let id = UUID()
        let timestamp: Date
        let densityAtHeel_kgm3: Double
        let densityAtBit_kgm3: Double
        let densityAtToe_kgm3: Double
        let isCirculating: Bool
    }

    var chartData: [ChartPoint] {
        guard let sheet = boundSheet else { return [] }
        return sheet.sortedReadings.reversed().map { reading in
            ChartPoint(
                timestamp: reading.timestamp,
                densityAtHeel_kgm3: reading.effectiveDensityAtHeel_kgm3,
                densityAtBit_kgm3: reading.effectiveDensityAtBit_kgm3,
                densityAtToe_kgm3: reading.effectiveDensityAtToe_kgm3,
                isCirculating: reading.isCirculating
            )
        }
    }

    // MARK: - Readings Table Data

    struct ReadingRow: Identifiable {
        let id: UUID
        let timestamp: Date
        let flowRate_m3_per_min: Double
        let densityOut_kgm3: Double
        let chokeFriction_kPa: Double
        let isCirculating: Bool
        let shutInPressure_kPa: Double
        let ecdAtHeel_kgm3: Double
        let ecdAtBit_kgm3: Double
        let ecdAtToe_kgm3: Double
        let esdAtHeel_kgm3: Double
        let esdAtBit_kgm3: Double
        let esdAtToe_kgm3: Double
        let effectiveDensityAtHeel_kgm3: Double
        let effectiveDensityAtBit_kgm3: Double
        let effectiveDensityAtToe_kgm3: Double
        let notes: String
    }

    var readingRows: [ReadingRow] {
        guard let sheet = boundSheet else { return [] }
        return sheet.sortedReadings.map { reading in
            ReadingRow(
                id: reading.id,
                timestamp: reading.timestamp,
                flowRate_m3_per_min: reading.flowRate_m3_per_min,
                densityOut_kgm3: reading.densityOut_kgm3,
                chokeFriction_kPa: reading.chokeFriction_kPa,
                isCirculating: reading.isCirculating,
                shutInPressure_kPa: reading.shutInPressure_kPa,
                ecdAtHeel_kgm3: reading.ecdAtHeel_kgm3,
                ecdAtBit_kgm3: reading.ecdAtBit_kgm3,
                ecdAtToe_kgm3: reading.ecdAtToe_kgm3,
                esdAtHeel_kgm3: reading.esdAtHeel_kgm3,
                esdAtBit_kgm3: reading.esdAtBit_kgm3,
                esdAtToe_kgm3: reading.esdAtToe_kgm3,
                effectiveDensityAtHeel_kgm3: reading.effectiveDensityAtHeel_kgm3,
                effectiveDensityAtBit_kgm3: reading.effectiveDensityAtBit_kgm3,
                effectiveDensityAtToe_kgm3: reading.effectiveDensityAtToe_kgm3,
                notes: reading.notes
            )
        }
    }

    // MARK: - Initialization

    func bootstrap(project: ProjectState, context: ModelContext) {
        self.context = context
        self.boundProject = project

        // Try to find existing MPD sheet for this project
        if let existingSheet = (project.mpdSheets ?? []).first {
            loadSheet(existingSheet)
        } else {
            // Initialize defaults from project
            if let maxMD = (project.finalLayers ?? []).map({ $0.bottomMD_m }).max() {
                toeMD_m = maxMD
                bitMD_m = maxMD  // Start at TD
            }
            // Set heel to ~80% of TD as a reasonable default
            heelMD_m = toeMD_m * 0.8

            // Use active mud density as default
            inputDensityOut_kgm3 = project.activeMud?.density_kgm3 ?? 1080.0
        }
    }

    func loadSheet(_ sheet: MPDSheet) {
        boundSheet = sheet
        sheetName = sheet.name
        heelMD_m = sheet.heelMD_m
        bitMD_m = sheet.bitMD_m
        toeMD_m = sheet.toeMD_m
        porePressure_kgm3 = sheet.porePressure_kgm3
        fracGradient_kgm3 = sheet.fracGradient_kgm3
        defaultCirculatingChoke_kPa = sheet.defaultCirculatingChoke_kPa
        defaultShutInChoke_kPa = sheet.defaultShutInChoke_kPa
        // Set input choke based on current mode
        inputChokeFriction_kPa = sheet.defaultCirculatingChoke_kPa
        inputShutInPressure_kPa = sheet.defaultShutInChoke_kPa
    }

    // MARK: - Actions

    func createSheet() {
        guard let context = context, let project = boundProject else { return }

        let sheet = MPDSheet(
            name: sheetName,
            heelMD_m: heelMD_m,
            bitMD_m: bitMD_m,
            toeMD_m: toeMD_m,
            porePressure_kgm3: porePressure_kgm3,
            fracGradient_kgm3: fracGradient_kgm3,
            defaultCirculatingChoke_kPa: defaultCirculatingChoke_kPa,
            defaultShutInChoke_kPa: defaultShutInChoke_kPa,
            project: project
        )

        context.insert(sheet)
        boundSheet = sheet
    }

    func updateSheetConfiguration() {
        guard let sheet = boundSheet else { return }

        sheet.name = sheetName
        sheet.heelMD_m = heelMD_m
        sheet.bitMD_m = bitMD_m
        sheet.toeMD_m = toeMD_m
        sheet.porePressure_kgm3 = porePressure_kgm3
        sheet.fracGradient_kgm3 = fracGradient_kgm3
        sheet.defaultCirculatingChoke_kPa = defaultCirculatingChoke_kPa
        sheet.defaultShutInChoke_kPa = defaultShutInChoke_kPa
        sheet.updatedAt = Date.now
    }

    func addReading() {
        guard let context = context, let sheet = boundSheet else { return }

        let reading = MPDReading(
            flowRate_m3_per_min: inputFlowRate_m3_per_min,
            densityOut_kgm3: inputDensityOut_kgm3,
            chokeFriction_kPa: inputChokeFriction_kPa,
            bitMD_m: bitMD_m,  // Capture current bit depth with reading
            isCirculating: inputIsCirculating,
            shutInPressure_kPa: inputShutInPressure_kPa,
            notes: inputNotes,
            mpdSheet: sheet
        )

        context.insert(reading)

        // Update sheet timestamp
        sheet.updatedAt = Date.now

        // Reset notes for next entry
        inputNotes = ""
    }

    func deleteReading(_ readingID: UUID) {
        guard let context = context, let sheet = boundSheet else { return }
        guard let readings = sheet.readings,
              let reading = readings.first(where: { $0.id == readingID }) else { return }

        context.delete(reading)
        sheet.updatedAt = Date.now
    }

    func deleteSheet() {
        guard let context = context, let sheet = boundSheet else { return }
        context.delete(sheet)
        boundSheet = nil
    }

    // MARK: - Helpers

    /// TVD at heel
    var heelTVD_m: Double {
        boundProject?.tvd(of: heelMD_m) ?? heelMD_m
    }

    /// TVD at bit
    var bitTVD_m: Double {
        boundProject?.tvd(of: bitMD_m) ?? bitMD_m
    }

    /// TVD at toe
    var toeTVD_m: Double {
        boundProject?.tvd(of: toeMD_m) ?? toeMD_m
    }

    /// Whether we're within the pressure window
    func isWithinWindow(_ density: Double) -> Bool {
        density >= porePressure_kgm3 && density <= fracGradient_kgm3
    }

    /// Color for density value based on pressure window
    func densityColor(_ density: Double) -> Color {
        if density < porePressure_kgm3 {
            return .orange // Below pore pressure - kick risk
        } else if density > fracGradient_kgm3 {
            return .red // Above frac - loss risk
        } else {
            return .green // Within window
        }
    }

    // MARK: - Geometry Extension

    /// Current max depth of drill string
    var drillStringMaxDepth: Double {
        (boundProject?.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0
    }

    /// Current max depth of annulus
    var annulusMaxDepth: Double {
        (boundProject?.annulus ?? []).map { $0.bottomDepth_m }.max() ?? 0
    }

    /// Whether bit depth exceeds defined geometry
    var bitExceedsGeometry: Bool {
        let maxGeometry = max(drillStringMaxDepth, annulusMaxDepth)
        return bitMD_m > maxGeometry && maxGeometry > 0
    }

    /// Amount by which bit exceeds geometry
    var geometryExtensionNeeded: Double {
        let maxGeometry = max(drillStringMaxDepth, annulusMaxDepth)
        return max(0, bitMD_m - maxGeometry)
    }

    /// Extend drill string and annulus to reach current bit depth
    func extendGeometryToBitDepth() {
        guard let project = boundProject, bitExceedsGeometry else { return }

        let targetDepth = bitMD_m

        // Extend drill string - add pipe at surface, shift deeper sections down
        if let drillString = project.drillString, !drillString.isEmpty {
            let currentMax = drillString.map { $0.bottomDepth_m }.max() ?? 0
            if targetDepth > currentMax {
                let extensionAmount = targetDepth - currentMax
                let sorted = drillString.sorted { $0.topDepth_m < $1.topDepth_m }
                if let uppermost = sorted.first {
                    // Extend uppermost section
                    uppermost.length_m += extensionAmount
                    // Shift all other sections down
                    for section in drillString where section.id != uppermost.id {
                        section.topDepth_m += extensionAmount
                    }
                }
            }
        }

        // Extend annulus - extend deepest section
        if let annulus = project.annulus, !annulus.isEmpty {
            let currentMax = annulus.map { $0.bottomDepth_m }.max() ?? 0
            if targetDepth > currentMax {
                if let deepest = annulus.max(by: { $0.bottomDepth_m < $1.bottomDepth_m }) {
                    let newLength = targetDepth - deepest.topDepth_m
                    deepest.length_m = newLength
                }
            }
        }

        try? context?.save()
    }
}
