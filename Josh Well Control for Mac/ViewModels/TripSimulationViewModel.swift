//
//  TripSimulationViewModel.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-03.
//

import Foundation
import SwiftData


extension TripSimulationView {
  @Observable
  class ViewModel {
    // Inputs
    var startBitMD_m: Double = 0
    var endMD_m: Double = 0
    var shoeMD_m: Double = 0
    var step_m: Double = 100
    var baseMudDensity_kgpm3: Double = 1080
    var backfillDensity_kgpm3: Double = 1200
    var targetESDAtTD_kgpm3: Double = 1320
    var crackFloat_kPa: Double = 2100
    var initialSABP_kPa: Double = 0
    var holdSABPOpen: Bool = false

    // New property for backfill mud selection
    var backfillMudID: UUID? = nil

    // Swab calculation parameters
    var eccentricityFactor: Double = 1.2  // 1.0 = concentric, higher = more eccentric (matches SwabbingViewModel)

    // Observed pit gain calibration
    // When useObservedPitGain is true, the simulation uses observedInitialPitGain_m3
    // instead of calculating equalization from pressure balance
    var useObservedPitGain: Bool = false
    var observedInitialPitGain_m3: Double = 0.0

    // Calculated pit gain from last simulation (for display/comparison)
    var calculatedInitialPitGain_m3: Double = 0.0

    // View options
    var colorByComposition: Bool = false
    var showDetails: Bool = false

    // Results / selection
    var steps: [TripStep] = []
    var selectedIndex: Int? = nil
    var stepSlider: Double = 0

    // Progress tracking
    var isRunning: Bool = false
    var progressValue: Double = 0.0  // 0.0 to 1.0
    var progressMessage: String = ""
    var progressPhase: NumericalTripModel.TripProgress.Phase = .initializing

    func bootstrap(from project: ProjectState) {
      if let maxMD = (project.finalLayers ?? []).map({ $0.bottomMD_m }).max() {
        startBitMD_m = maxMD
        endMD_m = 0
      }
      // Initialize shoe depth from deepest casing section (if any)
      let annulusSections = project.annulus ?? []
      if let deepestCasing = annulusSections.filter({ $0.isCased }).max(by: { $0.bottomDepth_m < $1.bottomDepth_m }) {
        shoeMD_m = deepestCasing.bottomDepth_m
      }
      let baseActive = project.activeMud?.density_kgm3 ?? baseMudDensity_kgpm3
      baseMudDensity_kgpm3 = baseActive
      backfillDensity_kgpm3 = baseActive
      backfillMudID = project.activeMud?.id
      targetESDAtTD_kgpm3 = baseActive

      #if DEBUG
      let layerCount = (project.finalLayers ?? []).count
      print("[TripSim] Bootstrap: found \(layerCount) final layers, startBitMD=\(startBitMD_m), shoeMD=\(shoeMD_m)")
      #endif
    }

    func runSimulation(project: ProjectState) {
      #if DEBUG
      let annLayers = project.finalAnnulusLayersSorted
      let strLayers = project.finalStringLayersSorted
      print("[TripSim] Running with \(annLayers.count) annulus layers, \(strLayers.count) string layers")
      for l in annLayers { print("  [Ann] \(l.name): \(l.topMD_m)-\(l.bottomMD_m) m, ρ=\(l.density_kgm3) kg/m³") }
      for l in strLayers { print("  [Str] \(l.name): \(l.topMD_m)-\(l.bottomMD_m) m, ρ=\(l.density_kgm3) kg/m³") }
      #endif

      // Reset progress state
      isRunning = true
      progressValue = 0.0
      progressMessage = "Initializing..."
      progressPhase = .initializing

      // Create sendable TVD sampler from surveys (avoid capturing @MainActor project)
      let tvdSampler = TvdSampler(stations: project.surveys ?? [])

      let geom = ProjectGeometryService(
        project: project,
        currentStringBottomMD: startBitMD_m,
        tvdMapper: { md in tvdSampler.tvd(of: md) }
      )

      // Get fallback rheology from active mud
      let activeMud = project.activeMud
      let fallbackTheta600 = activeMud?.dial600
      let fallbackTheta300 = activeMud?.dial300

      // Get backfill mud and its color
      let backfillMud = backfillMudID.flatMap { id in (project.muds ?? []).first(where: { $0.id == id }) }
      let backfillColor: NumericalTripModel.ColorRGBA? = backfillMud.map {
        NumericalTripModel.ColorRGBA(r: $0.colorR, g: $0.colorG, b: $0.colorB, a: $0.colorA)
      } ?? activeMud.map {
        NumericalTripModel.ColorRGBA(r: $0.colorR, g: $0.colorG, b: $0.colorB, a: $0.colorA)
      }
      let baseMudColor: NumericalTripModel.ColorRGBA? = activeMud.map {
        NumericalTripModel.ColorRGBA(r: $0.colorR, g: $0.colorG, b: $0.colorB, a: $0.colorA)
      }

      // Pre-extract values from project to avoid capturing @MainActor state
      let tripSpeed = abs(project.settings.tripSpeed_m_per_s)
      let shoeTVD = tvdSampler.tvd(of: shoeMD_m)

      let input = NumericalTripModel.TripInput(
        tvdOfMd: { md in tvdSampler.tvd(of: md) },
        shoeTVD_m: shoeTVD,
        startBitMD_m: startBitMD_m,
        endMD_m: endMD_m,
        crackFloat_kPa: crackFloat_kPa,
        step_m: step_m,
        baseMudDensity_kgpm3: (activeMud?.density_kgm3 ?? baseMudDensity_kgpm3),
        backfillDensity_kgpm3: (backfillMud?.density_kgm3 ?? activeMud?.density_kgm3 ?? backfillDensity_kgpm3),
        backfillColor: backfillColor,
        baseMudColor: baseMudColor,
        targetESDAtTD_kgpm3: targetESDAtTD_kgpm3,
        initialSABP_kPa: initialSABP_kPa,
        holdSABPOpen: holdSABPOpen,
        tripSpeed_m_per_s: tripSpeed,
        eccentricityFactor: eccentricityFactor,
        fallbackTheta600: fallbackTheta600,
        fallbackTheta300: fallbackTheta300,
        observedInitialPitGain_m3: useObservedPitGain ? observedInitialPitGain_m3 : nil
      )

      // Extract project data into sendable snapshot BEFORE entering detached task
      let projectSnapshot = NumericalTripModel.ProjectSnapshot(from: project)

      // Run simulation on background thread with progress updates
      Task.detached { [weak self] in
        let model = NumericalTripModel()
        let results = model.run(input, geom: geom, projectSnapshot: projectSnapshot) { progress in
          Task { @MainActor [weak self] in
            guard let self else { return }
            self.progressValue = progress.progress
            self.progressMessage = progress.message
            self.progressPhase = progress.phase
          }
        }

        await MainActor.run { [weak self] in
          guard let self else { return }
          self.steps = results
          self.selectedIndex = results.isEmpty ? nil : 0
          self.stepSlider = 0
          self.isRunning = false
          self.progressMessage = "Complete"

          // Store the calculated pit gain from the initial step (for display/comparison)
          if let firstStep = results.first {
            self.calculatedInitialPitGain_m3 = firstStep.cumulativePitGain_m3
          }
        }
      }
    }

    func esdAtControlText(project: ProjectState) -> String {
      let annMax = (project.annulus ?? []).map { $0.bottomDepth_m }.max() ?? 0
      let dsMax = (project.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0
      let candidates = [annMax, dsMax].filter { $0 > 0 }
      let limit = candidates.min()
      let controlMDRaw = max(0.0, shoeMD_m)
      let controlMD = min(controlMDRaw, limit ?? controlMDRaw)
      let controlTVD = project.tvd(of: controlMD)

      guard let idx = selectedIndex, steps.indices.contains(idx) else { return "" }
      let s = steps[idx]
      var pressure_kPa: Double = s.SABP_kPa

      if controlTVD <= s.bitTVD_m + 1e-9 {
        var remaining = controlTVD
        for r in s.layersAnnulus where r.bottomTVD > r.topTVD {
          let seg = min(remaining, max(0.0, min(r.bottomTVD, controlTVD) - r.topTVD))
          if seg > 1e-9 {
            let frac = seg / max(1e-9, r.bottomTVD - r.topTVD)
            pressure_kPa += r.deltaHydroStatic_kPa * frac
            remaining -= seg
            if remaining <= 1e-9 { break }
          }
        }
      } else {
        var remainingA = s.bitTVD_m
        for r in s.layersAnnulus where r.bottomTVD > r.topTVD {
          let seg = min(remainingA, max(0.0, min(r.bottomTVD, s.bitTVD_m) - r.topTVD))
          if seg > 1e-9 {
            let frac = seg / max(1e-9, r.bottomTVD - r.topTVD)
            pressure_kPa += r.deltaHydroStatic_kPa * frac
            remainingA -= seg
            if remainingA <= 1e-9 { break }
          }
        }
        var remainingP = controlTVD - s.bitTVD_m
        for r in s.layersPocket where r.bottomTVD > r.topTVD {
          let top = max(r.topTVD, s.bitTVD_m)
          let bot = min(r.bottomTVD, controlTVD)
          let seg = max(0.0, bot - top)
          if seg > 1e-9 {
            let frac = seg / max(1e-9, r.bottomTVD - r.topTVD)
            pressure_kPa += r.deltaHydroStatic_kPa * frac
            remainingP -= seg
            if remainingP <= 1e-9 { break }
          }
        }
      }

      let esdAtControl = pressure_kPa / 0.00981 / max(1e-9, controlTVD)
      return String(format: "ESD@control: %.1f kg/m³", esdAtControl)
    }

    // MARK: - Persistence

    /// Save the current simulation results to SwiftData
    func saveSimulation(name: String, project: ProjectState, context: ModelContext) -> TripSimulation? {
      guard !steps.isEmpty else { return nil }

      // Look up the backfill mud if selected
      let backfillMud: MudProperties? = backfillMudID.flatMap { id in
        (project.muds ?? []).first(where: { $0.id == id })
      }

      let simulation = TripSimulation(
        name: name,
        startBitMD_m: startBitMD_m,
        endMD_m: endMD_m,
        shoeMD_m: shoeMD_m,
        step_m: step_m,
        baseMudDensity_kgpm3: baseMudDensity_kgpm3,
        backfillDensity_kgpm3: backfillDensity_kgpm3,
        targetESDAtTD_kgpm3: targetESDAtTD_kgpm3,
        crackFloat_kPa: crackFloat_kPa,
        initialSABP_kPa: initialSABP_kPa,
        holdSABPOpen: holdSABPOpen,
        tripSpeed_m_per_s: project.settings.tripSpeed_m_per_s,
        eccentricityFactor: eccentricityFactor,
        fallbackTheta600: project.activeMud?.dial600,
        fallbackTheta300: project.activeMud?.dial300,
        useObservedPitGain: useObservedPitGain,
        observedInitialPitGain_m3: observedInitialPitGain_m3,
        project: project,
        backfillMud: backfillMud
      )

      simulation.calculatedInitialPitGain_m3 = calculatedInitialPitGain_m3

      // Insert into context
      context.insert(simulation)

      // Convert runtime steps to persisted steps
      for (index, step) in steps.enumerated() {
        let persistedStep = TripSimulationStep(from: step, index: index)
        simulation.addStep(persistedStep)
      }

      // Update summary results
      simulation.updateSummaryResults()

      // Link to project
      if project.tripSimulations == nil { project.tripSimulations = [] }
      project.tripSimulations?.append(simulation)
      project.touchUpdated()

      try? context.save()
      return simulation
    }

    /// Load a saved simulation into the ViewModel for display
    func loadSimulation(_ simulation: TripSimulation, project: ProjectState) {
      // Load inputs
      startBitMD_m = simulation.startBitMD_m
      endMD_m = simulation.endMD_m
      shoeMD_m = simulation.shoeMD_m
      step_m = simulation.step_m
      baseMudDensity_kgpm3 = simulation.baseMudDensity_kgpm3
      backfillDensity_kgpm3 = simulation.backfillDensity_kgpm3
      targetESDAtTD_kgpm3 = simulation.targetESDAtTD_kgpm3
      crackFloat_kPa = simulation.crackFloat_kPa
      initialSABP_kPa = simulation.initialSABP_kPa
      holdSABPOpen = simulation.holdSABPOpen
      eccentricityFactor = simulation.eccentricityFactor
      useObservedPitGain = simulation.useObservedPitGain
      observedInitialPitGain_m3 = simulation.observedInitialPitGain_m3
      calculatedInitialPitGain_m3 = simulation.calculatedInitialPitGain_m3
      backfillMudID = simulation.backfillMud?.id

      // Convert persisted steps back to runtime TripStep objects
      let sortedSteps = simulation.sortedSteps
      steps = sortedSteps.map { persistedStep in
        // Convert layer snapshots back to LayerRows
        let pocket = persistedStep.layersPocket.map { $0.toLayerRow() }
        let annulus = persistedStep.layersAnnulus.map { $0.toLayerRow() }
        let string = persistedStep.layersString.map { $0.toLayerRow() }

        // Compute totals from layers
        let totalsPocket = NumericalTripModel.Totals(
          count: pocket.count,
          tvd_m: pocket.reduce(0) { $0 + max(0, $1.bottomTVD - $1.topTVD) },
          deltaP_kPa: pocket.reduce(0) { $0 + $1.deltaHydroStatic_kPa }
        )
        let totalsAnnulus = NumericalTripModel.Totals(
          count: annulus.count,
          tvd_m: annulus.reduce(0) { $0 + max(0, $1.bottomTVD - $1.topTVD) },
          deltaP_kPa: annulus.reduce(0) { $0 + $1.deltaHydroStatic_kPa }
        )
        let totalsString = NumericalTripModel.Totals(
          count: string.count,
          tvd_m: string.reduce(0) { $0 + max(0, $1.bottomTVD - $1.topTVD) },
          deltaP_kPa: string.reduce(0) { $0 + $1.deltaHydroStatic_kPa }
        )

        return TripStep(
          bitMD_m: persistedStep.bitMD_m,
          bitTVD_m: persistedStep.bitTVD_m,
          SABP_kPa: persistedStep.SABP_kPa,
          SABP_kPa_Raw: persistedStep.SABP_kPa_Raw,
          ESDatTD_kgpm3: persistedStep.ESDatTD_kgpm3,
          ESDatBit_kgpm3: persistedStep.ESDatBit_kgpm3,
          backfillRemaining_m3: persistedStep.backfillRemaining_m3,
          swabDropToBit_kPa: persistedStep.swabDropToBit_kPa,
          SABP_Dynamic_kPa: persistedStep.SABP_Dynamic_kPa,
          floatState: persistedStep.floatState,
          stepBackfill_m3: persistedStep.stepBackfill_m3,
          cumulativeBackfill_m3: persistedStep.cumulativeBackfill_m3,
          expectedFillIfClosed_m3: persistedStep.expectedFillIfClosed_m3,
          expectedFillIfOpen_m3: persistedStep.expectedFillIfOpen_m3,
          slugContribution_m3: persistedStep.slugContribution_m3,
          cumulativeSlugContribution_m3: persistedStep.cumulativeSlugContribution_m3,
          pitGain_m3: persistedStep.pitGain_m3,
          cumulativePitGain_m3: persistedStep.cumulativePitGain_m3,
          surfaceTankDelta_m3: persistedStep.surfaceTankDelta_m3,
          cumulativeSurfaceTankDelta_m3: persistedStep.cumulativeSurfaceTankDelta_m3,
          layersPocket: pocket,
          layersAnnulus: annulus,
          layersString: string,
          totalsPocket: totalsPocket,
          totalsAnnulus: totalsAnnulus,
          totalsString: totalsString
        )
      }

      // Reset selection
      selectedIndex = steps.isEmpty ? nil : 0
      stepSlider = 0
    }

    /// Delete a saved simulation
    func deleteSimulation(_ simulation: TripSimulation, context: ModelContext) {
      context.delete(simulation)
      try? context.save()
    }
  }
}

#if (os(iOS))
extension TripSimulationViewIOS {
  @Observable
  class ViewModel {
    // Inputs
    var startBitMD_m: Double = 0
    var endMD_m: Double = 0
    var shoeMD_m: Double = 0
    var step_m: Double = 100
    var baseMudDensity_kgpm3: Double = 1080
    var backfillDensity_kgpm3: Double = 1200
    var targetESDAtTD_kgpm3: Double = 1320
    var crackFloat_kPa: Double = 2100
    var initialSABP_kPa: Double = 0
    var holdSABPOpen: Bool = false

    // New property for backfill mud selection
    var backfillMudID: UUID? = nil

    // Swab calculation parameters
    var eccentricityFactor: Double = 1.2  // 1.0 = concentric, higher = more eccentric (matches SwabbingViewModel)

    // Observed pit gain calibration
    var useObservedPitGain: Bool = false
    var observedInitialPitGain_m3: Double = 0.0
    var calculatedInitialPitGain_m3: Double = 0.0

    // View options
    var colorByComposition: Bool = false
    var showDetails: Bool = false

    // Results / selection
    var steps: [TripStep] = []
    var selectedIndex: Int? = nil
    var stepSlider: Double = 0

    // Progress tracking
    var isRunning: Bool = false
    var progressValue: Double = 0.0  // 0.0 to 1.0
    var progressMessage: String = ""
    var progressPhase: NumericalTripModel.TripProgress.Phase = .initializing

    func bootstrap(from project: ProjectState) {
      if let maxMD = (project.finalLayers ?? []).map({ $0.bottomMD_m }).max() {
        startBitMD_m = maxMD
        endMD_m = 0
      }
      // Initialize shoe depth from deepest casing section (if any)
      let annulusSections = project.annulus ?? []
      if let deepestCasing = annulusSections.filter({ $0.isCased }).max(by: { $0.bottomDepth_m < $1.bottomDepth_m }) {
        shoeMD_m = deepestCasing.bottomDepth_m
      }
      let baseActive = project.activeMud?.density_kgm3 ?? baseMudDensity_kgpm3
      baseMudDensity_kgpm3 = baseActive
      backfillDensity_kgpm3 = baseActive
      backfillMudID = project.activeMud?.id
      targetESDAtTD_kgpm3 = baseActive
    }

    func runSimulation(project: ProjectState) {
      // Reset progress state
      isRunning = true
      progressValue = 0.0
      progressMessage = "Initializing..."
      progressPhase = .initializing

      // Create sendable TVD sampler from surveys (avoid capturing @MainActor project)
      let tvdSampler = TvdSampler(stations: project.surveys ?? [])

      let geom = ProjectGeometryService(
        project: project,
        currentStringBottomMD: startBitMD_m,
        tvdMapper: { md in tvdSampler.tvd(of: md) }
      )

      // Get fallback rheology from active mud
      let activeMud = project.activeMud
      let fallbackTheta600 = activeMud?.dial600
      let fallbackTheta300 = activeMud?.dial300

      // Get backfill mud and its color
      let backfillMud2 = backfillMudID.flatMap { id in (project.muds ?? []).first(where: { $0.id == id }) }
      let backfillColor2: NumericalTripModel.ColorRGBA? = backfillMud2.map {
        NumericalTripModel.ColorRGBA(r: $0.colorR, g: $0.colorG, b: $0.colorB, a: $0.colorA)
      } ?? activeMud.map {
        NumericalTripModel.ColorRGBA(r: $0.colorR, g: $0.colorG, b: $0.colorB, a: $0.colorA)
      }
      let baseMudColor2: NumericalTripModel.ColorRGBA? = activeMud.map {
        NumericalTripModel.ColorRGBA(r: $0.colorR, g: $0.colorG, b: $0.colorB, a: $0.colorA)
      }

      // Pre-extract values from project to avoid capturing @MainActor state
      let tripSpeed = abs(project.settings.tripSpeed_m_per_s)
      let shoeTVD = tvdSampler.tvd(of: shoeMD_m)

      let input = NumericalTripModel.TripInput(
        tvdOfMd: { md in tvdSampler.tvd(of: md) },
        shoeTVD_m: shoeTVD,
        startBitMD_m: startBitMD_m,
        endMD_m: endMD_m,
        crackFloat_kPa: crackFloat_kPa,
        step_m: step_m,
        baseMudDensity_kgpm3: (activeMud?.density_kgm3 ?? baseMudDensity_kgpm3),
        backfillDensity_kgpm3: (backfillMud2?.density_kgm3 ?? activeMud?.density_kgm3 ?? backfillDensity_kgpm3),
        backfillColor: backfillColor2,
        baseMudColor: baseMudColor2,
        targetESDAtTD_kgpm3: targetESDAtTD_kgpm3,
        initialSABP_kPa: initialSABP_kPa,
        holdSABPOpen: holdSABPOpen,
        tripSpeed_m_per_s: tripSpeed,
        eccentricityFactor: eccentricityFactor,
        fallbackTheta600: fallbackTheta600,
        fallbackTheta300: fallbackTheta300,
        observedInitialPitGain_m3: useObservedPitGain ? observedInitialPitGain_m3 : nil
      )

      // Extract project data into sendable snapshot BEFORE entering detached task
      let projectSnapshot = NumericalTripModel.ProjectSnapshot(from: project)

      // Run simulation on background thread with progress updates
      Task.detached { [weak self] in
        let model = NumericalTripModel()
        let results = model.run(input, geom: geom, projectSnapshot: projectSnapshot) { progress in
          Task { @MainActor [weak self] in
            guard let self else { return }
            self.progressValue = progress.progress
            self.progressMessage = progress.message
            self.progressPhase = progress.phase
          }
        }

        await MainActor.run { [weak self] in
          guard let self else { return }
          self.steps = results
          self.selectedIndex = results.isEmpty ? nil : 0
          self.stepSlider = 0
          self.isRunning = false
          self.progressMessage = "Complete"

          // Store the calculated pit gain from the initial step
          if let firstStep = results.first {
            self.calculatedInitialPitGain_m3 = firstStep.cumulativePitGain_m3
          }
        }
      }
    }

    func esdAtControlText(project: ProjectState) -> String {
      let annMax = (project.annulus ?? []).map { $0.bottomDepth_m }.max() ?? 0
      let dsMax = (project.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0
      let candidates = [annMax, dsMax].filter { $0 > 0 }
      let limit = candidates.min()
      let controlMDRaw = max(0.0, shoeMD_m)
      let controlMD = min(controlMDRaw, limit ?? controlMDRaw)
      let controlTVD = project.tvd(of: controlMD)

      guard let idx = selectedIndex, steps.indices.contains(idx) else { return "" }
      let s = steps[idx]
      var pressure_kPa: Double = s.SABP_kPa

      if controlTVD <= s.bitTVD_m + 1e-9 {
        var remaining = controlTVD
        for r in s.layersAnnulus where r.bottomTVD > r.topTVD {
          let seg = min(remaining, max(0.0, min(r.bottomTVD, controlTVD) - r.topTVD))
          if seg > 1e-9 {
            let frac = seg / max(1e-9, r.bottomTVD - r.topTVD)
            pressure_kPa += r.deltaHydroStatic_kPa * frac
            remaining -= seg
            if remaining <= 1e-9 { break }
          }
        }
      } else {
        var remainingA = s.bitTVD_m
        for r in s.layersAnnulus where r.bottomTVD > r.topTVD {
          let seg = min(remainingA, max(0.0, min(r.bottomTVD, s.bitTVD_m) - r.topTVD))
          if seg > 1e-9 {
            let frac = seg / max(1e-9, r.bottomTVD - r.topTVD)
            pressure_kPa += r.deltaHydroStatic_kPa * frac
            remainingA -= seg
            if remainingA <= 1e-9 { break }
          }
        }
        var remainingP = controlTVD - s.bitTVD_m
        for r in s.layersPocket where r.bottomTVD > r.topTVD {
          let top = max(r.topTVD, s.bitTVD_m)
          let bot = min(r.bottomTVD, controlTVD)
          let seg = max(0.0, bot - top)
          if seg > 1e-9 {
            let frac = seg / max(1e-9, r.bottomTVD - r.topTVD)
            pressure_kPa += r.deltaHydroStatic_kPa * frac
            remainingP -= seg
            if remainingP <= 1e-9 { break }
          }
        }
      }

      let esdAtControl = pressure_kPa / 0.00981 / max(1e-9, controlTVD)
      return String(format: "ESD@control: %.1f kg/m³", esdAtControl)
    }

    // MARK: - Persistence

    /// Save the current simulation results to SwiftData
    func saveSimulation(name: String, project: ProjectState, context: ModelContext) -> TripSimulation? {
      guard !steps.isEmpty else { return nil }

      // Look up the backfill mud if selected
      let backfillMud: MudProperties? = backfillMudID.flatMap { id in
        (project.muds ?? []).first(where: { $0.id == id })
      }

      let simulation = TripSimulation(
        name: name,
        startBitMD_m: startBitMD_m,
        endMD_m: endMD_m,
        shoeMD_m: shoeMD_m,
        step_m: step_m,
        baseMudDensity_kgpm3: baseMudDensity_kgpm3,
        backfillDensity_kgpm3: backfillDensity_kgpm3,
        targetESDAtTD_kgpm3: targetESDAtTD_kgpm3,
        crackFloat_kPa: crackFloat_kPa,
        initialSABP_kPa: initialSABP_kPa,
        holdSABPOpen: holdSABPOpen,
        tripSpeed_m_per_s: project.settings.tripSpeed_m_per_s,
        eccentricityFactor: eccentricityFactor,
        fallbackTheta600: project.activeMud?.dial600,
        fallbackTheta300: project.activeMud?.dial300,
        useObservedPitGain: useObservedPitGain,
        observedInitialPitGain_m3: observedInitialPitGain_m3,
        project: project,
        backfillMud: backfillMud
      )

      simulation.calculatedInitialPitGain_m3 = calculatedInitialPitGain_m3

      // Insert into context
      context.insert(simulation)

      // Convert runtime steps to persisted steps
      for (index, step) in steps.enumerated() {
        let persistedStep = TripSimulationStep(from: step, index: index)
        simulation.addStep(persistedStep)
      }

      // Update summary results
      simulation.updateSummaryResults()

      // Link to project
      if project.tripSimulations == nil { project.tripSimulations = [] }
      project.tripSimulations?.append(simulation)
      project.touchUpdated()

      try? context.save()
      return simulation
    }

    /// Load a saved simulation into the ViewModel for display
    func loadSimulation(_ simulation: TripSimulation, project: ProjectState) {
      // Load inputs
      startBitMD_m = simulation.startBitMD_m
      endMD_m = simulation.endMD_m
      shoeMD_m = simulation.shoeMD_m
      step_m = simulation.step_m
      baseMudDensity_kgpm3 = simulation.baseMudDensity_kgpm3
      backfillDensity_kgpm3 = simulation.backfillDensity_kgpm3
      targetESDAtTD_kgpm3 = simulation.targetESDAtTD_kgpm3
      crackFloat_kPa = simulation.crackFloat_kPa
      initialSABP_kPa = simulation.initialSABP_kPa
      holdSABPOpen = simulation.holdSABPOpen
      eccentricityFactor = simulation.eccentricityFactor
      useObservedPitGain = simulation.useObservedPitGain
      observedInitialPitGain_m3 = simulation.observedInitialPitGain_m3
      calculatedInitialPitGain_m3 = simulation.calculatedInitialPitGain_m3
      backfillMudID = simulation.backfillMud?.id

      // Convert persisted steps back to runtime TripStep objects
      let sortedSteps = simulation.sortedSteps
      steps = sortedSteps.map { persistedStep in
        // Convert layer snapshots back to LayerRows
        let pocket = persistedStep.layersPocket.map { $0.toLayerRow() }
        let annulus = persistedStep.layersAnnulus.map { $0.toLayerRow() }
        let string = persistedStep.layersString.map { $0.toLayerRow() }

        // Compute totals from layers
        let totalsPocket = NumericalTripModel.Totals(
          count: pocket.count,
          tvd_m: pocket.reduce(0) { $0 + max(0, $1.bottomTVD - $1.topTVD) },
          deltaP_kPa: pocket.reduce(0) { $0 + $1.deltaHydroStatic_kPa }
        )
        let totalsAnnulus = NumericalTripModel.Totals(
          count: annulus.count,
          tvd_m: annulus.reduce(0) { $0 + max(0, $1.bottomTVD - $1.topTVD) },
          deltaP_kPa: annulus.reduce(0) { $0 + $1.deltaHydroStatic_kPa }
        )
        let totalsString = NumericalTripModel.Totals(
          count: string.count,
          tvd_m: string.reduce(0) { $0 + max(0, $1.bottomTVD - $1.topTVD) },
          deltaP_kPa: string.reduce(0) { $0 + $1.deltaHydroStatic_kPa }
        )

        return TripStep(
          bitMD_m: persistedStep.bitMD_m,
          bitTVD_m: persistedStep.bitTVD_m,
          SABP_kPa: persistedStep.SABP_kPa,
          SABP_kPa_Raw: persistedStep.SABP_kPa_Raw,
          ESDatTD_kgpm3: persistedStep.ESDatTD_kgpm3,
          ESDatBit_kgpm3: persistedStep.ESDatBit_kgpm3,
          backfillRemaining_m3: persistedStep.backfillRemaining_m3,
          swabDropToBit_kPa: persistedStep.swabDropToBit_kPa,
          SABP_Dynamic_kPa: persistedStep.SABP_Dynamic_kPa,
          floatState: persistedStep.floatState,
          stepBackfill_m3: persistedStep.stepBackfill_m3,
          cumulativeBackfill_m3: persistedStep.cumulativeBackfill_m3,
          expectedFillIfClosed_m3: persistedStep.expectedFillIfClosed_m3,
          expectedFillIfOpen_m3: persistedStep.expectedFillIfOpen_m3,
          slugContribution_m3: persistedStep.slugContribution_m3,
          cumulativeSlugContribution_m3: persistedStep.cumulativeSlugContribution_m3,
          pitGain_m3: persistedStep.pitGain_m3,
          cumulativePitGain_m3: persistedStep.cumulativePitGain_m3,
          surfaceTankDelta_m3: persistedStep.surfaceTankDelta_m3,
          cumulativeSurfaceTankDelta_m3: persistedStep.cumulativeSurfaceTankDelta_m3,
          layersPocket: pocket,
          layersAnnulus: annulus,
          layersString: string,
          totalsPocket: totalsPocket,
          totalsAnnulus: totalsAnnulus,
          totalsString: totalsString
        )
      }

      // Reset selection
      selectedIndex = steps.isEmpty ? nil : 0
      stepSlider = 0
    }

    /// Delete a saved simulation
    func deleteSimulation(_ simulation: TripSimulation, context: ModelContext) {
      context.delete(simulation)
      try? context.save()
    }
  }
}
#endif
