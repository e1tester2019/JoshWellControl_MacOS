//
//  DirectionalDashboardViewModel.swift
//  Josh Well Control for Mac
//
//  State management for the Directional Planning Dashboard.
//

import Foundation
import SwiftUI
import SwiftData

/// A temporary scenario survey for what-if projections (not persisted)
struct ScenarioSurvey: Identifiable {
    let id = UUID()
    var md: Double
    var inc: Double
    var azi: Double
    var tvd: Double
    var ns_m: Double
    var ew_m: Double
    var vs_m: Double
    var dls: Double  // DLS from previous survey to this one

    /// Create a scenario survey projected from a base survey
    static func project(
        from base: SurveyStation,
        distance: Double,
        inc: Double,
        azi: Double,
        vsdDirection: Double
    ) -> ScenarioSurvey {
        // Use minimum curvature to calculate position
        let incRad1 = base.inc * .pi / 180
        let aziRad1 = base.azi * .pi / 180
        let incRad2 = inc * .pi / 180
        let aziRad2 = azi * .pi / 180

        // Dogleg calculation
        let cosDL = cos(incRad1) * cos(incRad2) + sin(incRad1) * sin(incRad2) * cos(aziRad2 - aziRad1)
        let dl = acos(min(1.0, max(-1.0, cosDL)))

        // Ratio factor
        let rf: Double
        if dl < 0.0001 {
            rf = 1.0
        } else {
            rf = 2.0 / dl * tan(dl / 2.0)
        }

        // Position changes
        let deltaTVD = distance / 2.0 * (cos(incRad1) + cos(incRad2)) * rf
        let deltaNS = distance / 2.0 * (sin(incRad1) * cos(aziRad1) + sin(incRad2) * cos(aziRad2)) * rf
        let deltaEW = distance / 2.0 * (sin(incRad1) * sin(aziRad1) + sin(incRad2) * sin(aziRad2)) * rf

        // Handle optional values from SurveyStation
        let baseTVD = base.tvd ?? 0
        let baseNS = base.ns_m ?? 0
        let baseEW = base.ew_m ?? 0

        let newTVD = baseTVD + deltaTVD
        let newNS = baseNS + deltaNS
        let newEW = baseEW + deltaEW

        // Calculate VS
        let vsRad = vsdDirection * .pi / 180
        let newVS = newNS * cos(vsRad) + newEW * sin(vsRad)

        // DLS in deg/30m
        let dlsDeg = dl * 180 / .pi
        let dls30m = distance > 0 ? dlsDeg * 30.0 / distance : 0

        return ScenarioSurvey(
            md: base.md + distance,
            inc: inc,
            azi: azi,
            tvd: newTVD,
            ns_m: newNS,
            ew_m: newEW,
            vs_m: newVS,
            dls: dls30m
        )
    }

    /// Create a scenario survey projected from another scenario survey
    static func projectFromScenario(
        from base: ScenarioSurvey,
        distance: Double,
        inc: Double,
        azi: Double,
        vsdDirection: Double
    ) -> ScenarioSurvey {
        // Use minimum curvature to calculate position
        let incRad1 = base.inc * .pi / 180
        let aziRad1 = base.azi * .pi / 180
        let incRad2 = inc * .pi / 180
        let aziRad2 = azi * .pi / 180

        // Dogleg calculation
        let cosDL = cos(incRad1) * cos(incRad2) + sin(incRad1) * sin(incRad2) * cos(aziRad2 - aziRad1)
        let dl = acos(min(1.0, max(-1.0, cosDL)))

        // Ratio factor
        let rf: Double
        if dl < 0.0001 {
            rf = 1.0
        } else {
            rf = 2.0 / dl * tan(dl / 2.0)
        }

        // Position changes
        let deltaTVD = distance / 2.0 * (cos(incRad1) + cos(incRad2)) * rf
        let deltaNS = distance / 2.0 * (sin(incRad1) * cos(aziRad1) + sin(incRad2) * cos(aziRad2)) * rf
        let deltaEW = distance / 2.0 * (sin(incRad1) * sin(aziRad1) + sin(incRad2) * sin(aziRad2)) * rf

        let newTVD = base.tvd + deltaTVD
        let newNS = base.ns_m + deltaNS
        let newEW = base.ew_m + deltaEW

        // Calculate VS
        let vsRad = vsdDirection * .pi / 180
        let newVS = newNS * cos(vsRad) + newEW * sin(vsRad)

        // DLS in deg/30m
        let dlsDeg = dl * 180 / .pi
        let dls30m = distance > 0 ? dlsDeg * 30.0 / distance : 0

        return ScenarioSurvey(
            md: base.md + distance,
            inc: inc,
            azi: azi,
            tvd: newTVD,
            ns_m: newNS,
            ew_m: newEW,
            vs_m: newVS,
            dls: dls30m
        )
    }
}

@Observable
class DirectionalDashboardViewModel {
    // MARK: - Dependencies

    @ObservationIgnored var modelContext: ModelContext?
    @ObservationIgnored private(set) var project: ProjectState?
    @ObservationIgnored private(set) var well: Well?

    // MARK: - State

    var selectedPlan: DirectionalPlan?
    var variances: [SurveyVariance] = []
    var summary: DirectionalVarianceService.VarianceSummary?

    // Bit projection
    var surveyToBitDistance: Double = 15.0  // Default 15m from survey to bit
    var bitProjection: BitProjection?
    var useRatesForProjection: Bool = true  // Apply current BR/TR to projection

    // Target landing point (user-configurable)
    var targetTVD: Double?           // Target TVD to land at (nil = use plan)
    var targetInc: Double?           // Target inclination at landing (nil = use plan)
    var distanceToLand: Double?      // Distance to land (nil = auto-calculate)

    // Scenario surveys (temporary, not persisted)
    var scenarioSurveys: [ScenarioSurvey] = []
    var showingScenarioEditor: Bool = false
    var editingScenarioIndex: Int? = nil  // nil = adding new, index = editing existing

    // Hover state - synced across all views
    var hoveredVariance: SurveyVariance?
    var hoveredMD: Double?

    // UI State
    var showingImporter: Bool = false
    var showingLimitsSheet: Bool = false
    var importError: String?

    // MARK: - Initialization

    func attach(project: ProjectState, context: ModelContext) {
        self.modelContext = context
        self.project = project
        self.well = project.well

        // Select first plan if available
        if selectedPlan == nil, let firstPlan = sortedPlans.first {
            selectedPlan = firstPlan
        }

        recalculateVariances()
    }

    // MARK: - Computed Properties

    var sortedPlans: [DirectionalPlan] {
        (well?.directionalPlans ?? []).sorted { $0.importedAt > $1.importedAt }
    }

    var surveys: [SurveyStation] {
        (project?.surveys ?? []).sorted { $0.md < $1.md }
    }

    var limits: DirectionalLimits {
        project?.directionalLimits ?? DirectionalLimits()
    }

    /// Project's VSD direction (used as fallback)
    var vsdDirection: Double {
        project?.vsdDirection_deg ?? 0
    }

    /// Effective VS direction - from plan if available, otherwise from project
    var effectiveVsAzimuth: Double {
        selectedPlan?.vsAzimuth_deg ?? vsdDirection
    }

    // MARK: - Plan Management

    func selectPlan(_ plan: DirectionalPlan?) {
        selectedPlan = plan
        recalculateVariances()
    }

    func deletePlan(_ plan: DirectionalPlan) {
        guard let context = modelContext else { return }

        if selectedPlan?.id == plan.id {
            selectedPlan = nil
        }

        context.delete(plan)
        try? context.save()

        // Select another plan if available
        if selectedPlan == nil, let firstPlan = sortedPlans.first {
            selectedPlan = firstPlan
            recalculateVariances()
        }
    }

    // MARK: - Import

    func handleImport(_ result: Result<[URL], Error>) {
        guard let well = well, let context = modelContext else { return }

        switch result {
        case .failure(let error):
            importError = error.localizedDescription

        case .success(let urls):
            guard let url = urls.first else { return }

            // Start accessing security-scoped resource
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let text: String

                // Check if this is an Excel file
                let fileExtension = url.pathExtension.lowercased()
                if fileExtension == "xlsx" || fileExtension == "xls" {
                    #if os(macOS)
                    text = try ExcelToCSVConverter.convert(url: url)
                    #else
                    throw NSError(domain: "Import", code: 0, userInfo: [NSLocalizedDescriptionKey: "Excel import is only supported on macOS."])
                    #endif
                } else {
                    let data = try Data(contentsOf: url)
                    guard let decoded = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
                        throw NSError(domain: "Import", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unable to decode file as UTF-8 or ASCII."])
                    }
                    text = decoded
                }

                let importResult = try DirectionalPlanImportService.importPlan(
                    from: text,
                    fileName: url.lastPathComponent
                )

                // Create the plan
                let plan = DirectionalPlan(
                    name: importResult.name,
                    revision: "1",
                    planDate: Date.now,
                    sourceFileName: importResult.sourceFileName,
                    notes: "",
                    vsAzimuth_deg: importResult.vsAzimuth_deg,
                    well: well
                )

                // Create stations
                var stations: [DirectionalPlanStation] = []
                for parsed in importResult.stations {
                    let station = DirectionalPlanStation(
                        md: parsed.md,
                        inc: parsed.inc,
                        azi: parsed.azi,
                        tvd: parsed.tvd,
                        ns_m: parsed.ns_m,
                        ew_m: parsed.ew_m,
                        vs_m: parsed.vs_m,
                        plan: plan
                    )
                    stations.append(station)
                }
                plan.stations = stations

                // Add to well
                if well.directionalPlans == nil {
                    well.directionalPlans = []
                }
                well.directionalPlans?.append(plan)

                // Insert into context
                context.insert(plan)
                for station in stations {
                    context.insert(station)
                }
                try context.save()

                // Select the new plan
                selectedPlan = plan
                recalculateVariances()

            } catch {
                importError = error.localizedDescription
            }
        }
    }

    // MARK: - Variance Calculation

    func recalculateVariances() {
        guard let plan = selectedPlan else {
            variances = []
            summary = nil
            bitProjection = nil
            return
        }

        variances = DirectionalVarianceService.calculateVariances(
            surveys: surveys,
            plan: plan,
            projectVsdDirection: vsdDirection
        )

        summary = DirectionalVarianceService.summarize(
            variances: variances,
            limits: limits
        )

        // Calculate bit projection from last survey
        recalculateBitProjection()
    }

    func recalculateBitProjection() {
        guard let plan = selectedPlan else {
            bitProjection = nil
            return
        }

        let sortedSurveys = surveys
        guard sortedSurveys.count >= 1 || scenarioSurveys.count >= 1 else {
            bitProjection = nil
            return
        }

        // Use scenario surveys if available, otherwise use actual surveys
        if let lastScenario = scenarioSurveys.last {
            // Project from the last scenario survey using raw data
            let previousMD: Double?
            let previousInc: Double?
            let previousAzi: Double?

            if scenarioSurveys.count >= 2 {
                let prev = scenarioSurveys[scenarioSurveys.count - 2]
                previousMD = prev.md
                previousInc = prev.inc
                previousAzi = prev.azi
            } else if let lastActual = sortedSurveys.last {
                previousMD = lastActual.md
                previousInc = lastActual.inc
                previousAzi = lastActual.azi
            } else {
                previousMD = nil
                previousInc = nil
                previousAzi = nil
            }

            bitProjection = DirectionalVarianceService.projectToBitFromData(
                surveyMD: lastScenario.md,
                surveyInc: lastScenario.inc,
                surveyAzi: lastScenario.azi,
                surveyTVD: lastScenario.tvd,
                surveyNS: lastScenario.ns_m,
                surveyEW: lastScenario.ew_m,
                previousMD: previousMD,
                previousInc: previousInc,
                previousAzi: previousAzi,
                surveyToBitDistance: surveyToBitDistance,
                plan: plan,
                vsdDirection: effectiveVsAzimuth,
                useRates: useRatesForProjection,
                targetTVD: targetTVD
            )
        } else {
            // Use actual surveys
            guard let lastSurvey = sortedSurveys.last else {
                bitProjection = nil
                return
            }
            let previousSurvey = sortedSurveys.count >= 2 ? sortedSurveys[sortedSurveys.count - 2] : nil

            bitProjection = DirectionalVarianceService.projectToBit(
                lastSurvey: lastSurvey,
                previousSurvey: previousSurvey,
                surveyToBitDistance: surveyToBitDistance,
                plan: plan,
                vsdDirection: effectiveVsAzimuth,
                useRates: useRatesForProjection,
                targetTVD: targetTVD
            )
        }
    }

    func updateBitProjectionDistance(_ distance: Double) {
        surveyToBitDistance = distance
        recalculateBitProjection()
    }

    func toggleUseRatesForProjection() {
        useRatesForProjection.toggle()
        recalculateBitProjection()
    }

    // MARK: - Scenario Survey Management

    /// Get the effective last survey point (actual or scenario)
    var effectiveLastSurvey: (md: Double, inc: Double, azi: Double, tvd: Double, ns: Double, ew: Double, vs: Double)? {
        if let lastScenario = scenarioSurveys.last {
            return (lastScenario.md, lastScenario.inc, lastScenario.azi,
                    lastScenario.tvd, lastScenario.ns_m, lastScenario.ew_m, lastScenario.vs_m)
        } else if let lastSurvey = surveys.last {
            return (lastSurvey.md, lastSurvey.inc, lastSurvey.azi,
                    lastSurvey.tvd ?? 0, lastSurvey.ns_m ?? 0, lastSurvey.ew_m ?? 0, lastSurvey.vs_m ?? 0)
        }
        return nil
    }

    /// Get the effective previous survey for rate calculations
    var effectivePreviousSurvey: (md: Double, inc: Double, azi: Double)? {
        if scenarioSurveys.count >= 2 {
            let prev = scenarioSurveys[scenarioSurveys.count - 2]
            return (prev.md, prev.inc, prev.azi)
        } else if scenarioSurveys.count == 1 {
            // Previous is the last actual survey
            if let lastSurvey = surveys.last {
                return (lastSurvey.md, lastSurvey.inc, lastSurvey.azi)
            }
        } else if surveys.count >= 2 {
            let prev = surveys[surveys.count - 2]
            return (prev.md, prev.inc, prev.azi)
        }
        return nil
    }

    /// Add a new scenario survey
    func addScenarioSurvey(distance: Double, inc: Double, azi: Double) {
        let scenario: ScenarioSurvey

        if let lastScenario = scenarioSurveys.last {
            // Project from last scenario
            scenario = ScenarioSurvey.projectFromScenario(
                from: lastScenario,
                distance: distance,
                inc: inc,
                azi: azi,
                vsdDirection: effectiveVsAzimuth
            )
        } else if let lastSurvey = surveys.last {
            // Project from last actual survey
            scenario = ScenarioSurvey.project(
                from: lastSurvey,
                distance: distance,
                inc: inc,
                azi: azi,
                vsdDirection: effectiveVsAzimuth
            )
        } else {
            return  // No base survey available
        }

        scenarioSurveys.append(scenario)
        recalculateBitProjection()
    }

    /// Update an existing scenario survey
    func updateScenarioSurvey(at index: Int, distance: Double, inc: Double, azi: Double) {
        guard index >= 0 && index < scenarioSurveys.count else { return }

        // Rebuild all scenarios from the edited one forward
        var newScenarios: [ScenarioSurvey] = []

        for i in 0..<scenarioSurveys.count {
            if i < index {
                // Keep scenarios before the edited one
                newScenarios.append(scenarioSurveys[i])
            } else {
                let useInc: Double
                let useAzi: Double
                let useDist: Double

                if i == index {
                    useInc = inc
                    useAzi = azi
                    useDist = distance
                } else {
                    // Recalculate with same angles but new base
                    useInc = scenarioSurveys[i].inc
                    useAzi = scenarioSurveys[i].azi
                    // Calculate original distance
                    if i == 0 {
                        useDist = scenarioSurveys[i].md - (surveys.last?.md ?? 0)
                    } else {
                        useDist = scenarioSurveys[i].md - scenarioSurveys[i - 1].md
                    }
                }

                // Project from appropriate base
                if i == 0 {
                    guard let lastActual = surveys.last else { return }
                    let scenario = ScenarioSurvey.project(
                        from: lastActual,
                        distance: useDist,
                        inc: useInc,
                        azi: useAzi,
                        vsdDirection: effectiveVsAzimuth
                    )
                    newScenarios.append(scenario)
                } else {
                    let prevScenario = newScenarios[i - 1]
                    let scenario = ScenarioSurvey.projectFromScenario(
                        from: prevScenario,
                        distance: useDist,
                        inc: useInc,
                        azi: useAzi,
                        vsdDirection: effectiveVsAzimuth
                    )
                    newScenarios.append(scenario)
                }
            }
        }

        scenarioSurveys = newScenarios
        recalculateBitProjection()
    }

    /// Delete a scenario survey and all following scenarios
    func deleteScenarioSurvey(at index: Int) {
        guard index >= 0 && index < scenarioSurveys.count else { return }
        scenarioSurveys.removeSubrange(index...)
        recalculateBitProjection()
    }

    /// Clear all scenario surveys
    func clearScenarioSurveys() {
        scenarioSurveys.removeAll()
        recalculateBitProjection()
    }

    /// Get default values for a new scenario survey
    func getDefaultsForNewScenario() -> (distance: Double, inc: Double, azi: Double) {
        if let last = scenarioSurveys.last {
            return (30.0, last.inc, last.azi)  // Default 30m, hold angle
        } else if let last = surveys.last {
            return (30.0, last.inc, last.azi)  // Default 30m, hold angle
        }
        return (30.0, 0, 0)
    }

    // MARK: - Hover Coordination

    func setHoveredMD(_ md: Double?) {
        hoveredMD = md
        if let md = md {
            hoveredVariance = variances.min(by: { abs($0.surveyMD - md) < abs($1.surveyMD - md) })
        } else {
            hoveredVariance = nil
        }
    }

    func setHoveredVariance(_ variance: SurveyVariance?) {
        hoveredVariance = variance
        hoveredMD = variance?.surveyMD
    }

    // MARK: - Status Helpers

    func overallStatus() -> VarianceStatus {
        guard let sum = summary else { return .ok }
        if sum.alarmCount > 0 { return .alarm }
        if sum.warningCount > 0 { return .warning }
        return .ok
    }
}
