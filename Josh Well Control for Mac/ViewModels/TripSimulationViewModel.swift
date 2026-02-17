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

    // Backfill switching: pump backfill mud until displacement volume, then switch to active mud
    // When enabled, uses backfill mud for the drill string displacement portion,
    // then switches to active mud for the remaining backfill (pit gain portion)
    var switchToActiveAfterDisplacement: Bool = false

    // Computed displacement volume (can be overridden by user)
    var computedDisplacementVolume_m3: Double = 0.0
    var overrideDisplacementVolume_m3: Double = 0.0
    var useOverrideDisplacementVolume: Bool = false

    // The actual displacement volume to use (computed or overridden)
    var effectiveDisplacementVolume_m3: Double {
        useOverrideDisplacementVolume ? overrideDisplacementVolume_m3 : computedDisplacementVolume_m3
    }

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

    // TVD source selection - use directional plan instead of surveys for projection
    var useDirectionalPlanForTVD: Bool = false

    // Results / selection
    var steps: [TripStep] = []
    var selectedIndex: Int? = nil
    var stepSlider: Double = 0

    // Progress tracking
    var isRunning: Bool = false
    var progressValue: Double = 0.0  // 0.0 to 1.0
    var progressMessage: String = ""
    var progressPhase: NumericalTripModel.TripProgress.Phase = .initializing

    // MARK: - Circulation State

    var pumpQueue: [CirculationService.PumpOperation] = []
    var selectedCirculateMudID: UUID?
    var circulateVolume_m3: Double = 5.0
    var pumpOutput_m3perStroke: Double = 0.01
    var circulateOutSchedule: [CirculationService.CirculateOutStep] = []
    var previewPocketLayers: [TripLayerSnapshot] = []
    var previewESDAtControl: Double = 0
    var previewRequiredSABP: Double = 0
    var circulationHistory: [CirculationService.CirculationRecord] = []

    /// Source description when imported from another operation
    var importedStateDescription: String?

    var totalQueueVolume_m3: Double {
      pumpQueue.reduce(0) { $0 + $1.volume_m3 }
    }

    func addToPumpQueue(mud: MudProperties, volume_m3: Double) {
      let operation = CirculationService.PumpOperation(volume_m3: volume_m3, fluid: FluidIdentity(from: mud))
      pumpQueue.append(operation)
    }

    func removeFromPumpQueue(at index: Int) {
      guard index >= 0 && index < pumpQueue.count else { return }
      pumpQueue.remove(at: index)
    }

    func clearPumpQueue() {
      pumpQueue.removeAll()
      previewPocketLayers = []
      circulateOutSchedule = []
      previewESDAtControl = 0
      previewRequiredSABP = 0
    }

    /// Preview circulation at the currently selected step.
    /// Models fluid flowing DOWN the drill string and UP the annulus.
    func previewPumpQueue(project: ProjectState) {
      guard let idx = selectedIndex, steps.indices.contains(idx) else { return }
      guard !pumpQueue.isEmpty else { return }

      let step = steps[idx]

      // Convert LayerRow layers to TripLayerSnapshot
      let pocketSnapshots = step.layersPocket.map { TripLayerSnapshot(from: $0) }
      let stringSnapshots = step.layersString.map { TripLayerSnapshot(from: $0) }

      let tvdSampler = TvdSampler(project: project, preferPlan: useDirectionalPlanForTVD)
      let geom = ProjectGeometryService(
        project: project,
        currentStringBottomMD: step.bitMD_m,
        tvdMapper: { md in tvdSampler.tvd(of: md) }
      )

      let result = CirculationService.previewPumpQueue(
        pocketLayers: pocketSnapshots,
        stringLayers: stringSnapshots,
        bitMD: step.bitMD_m,
        controlMD: shoeMD_m,
        targetESD_kgpm3: targetESDAtTD_kgpm3,
        geom: geom,
        tvdSampler: tvdSampler,
        pumpQueue: pumpQueue,
        pumpOutput_m3perStroke: pumpOutput_m3perStroke,
        activeMudDensity_kgpm3: project.activeMud?.density_kgm3 ?? baseMudDensity_kgpm3
      )

      circulateOutSchedule = result.schedule
      previewPocketLayers = result.resultLayersPocket
      previewESDAtControl = result.ESDAtControl
      previewRequiredSABP = result.requiredSABP
    }

    /// Commit circulation and re-run simulation from current depth
    func commitCirculation(project: ProjectState) {
      guard let idx = selectedIndex, steps.indices.contains(idx) else { return }
      guard !previewPocketLayers.isEmpty else { return }
      guard !pumpQueue.isEmpty else { return }

      let currentStep = steps[idx]
      let tvdSampler = TvdSampler(project: project, preferPlan: useDirectionalPlanForTVD)

      // Calculate ESD before
      let pocketSnapshots = currentStep.layersPocket.map { TripLayerSnapshot(from: $0) }
      let esdBefore = CirculationService.calculateESDFromLayers(
        layers: pocketSnapshots,
        atDepthMD: shoeMD_m,
        tvdSampler: tvdSampler
      )

      // Record the circulation
      let record = CirculationService.CirculationRecord(
        timestamp: Date(),
        atBitMD_m: currentStep.bitMD_m,
        operations: pumpQueue,
        ESDBeforeAtControl_kgpm3: esdBefore,
        ESDAfterAtControl_kgpm3: previewESDAtControl,
        SABPRequired_kPa: previewRequiredSABP
      )
      circulationHistory.append(record)

      // Clear queue and preview
      let savedPreviewLayers = previewPocketLayers
      pumpQueue.removeAll()
      previewPocketLayers = []
      circulateOutSchedule = []

      // Truncate steps at current position - we'll re-run from here
      let savedBitMD = currentStep.bitMD_m
      steps = Array(steps.prefix(idx + 1))

      // Re-run from current depth to end with updated fluid state
      // The simulation will use the project's current final layers, but we need to
      // run from the current bit position
      let savedStartBitMD = startBitMD_m
      startBitMD_m = savedBitMD
      runSimulation(project: project)
      // Note: runSimulation is async - steps will be updated when it completes
      // Restore original start for display purposes
      startBitMD_m = savedStartBitMD
    }

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

      // Load persisted backfill switching settings
      switchToActiveAfterDisplacement = project.settings.switchToActiveAfterDisplacement
      useOverrideDisplacementVolume = project.settings.useOverrideDisplacementVolume
      overrideDisplacementVolume_m3 = project.settings.overrideDisplacementVolume_m3

      #if DEBUG
      let layerCount = (project.finalLayers ?? []).count
      print("[TripSim] Bootstrap: found \(layerCount) final layers, startBitMD=\(startBitMD_m), shoeMD=\(shoeMD_m)")
      #endif
    }

    /// Save backfill switching settings to project
    func saveBackfillSettings(to project: ProjectState) {
      project.settings.switchToActiveAfterDisplacement = switchToActiveAfterDisplacement
      project.settings.useOverrideDisplacementVolume = useOverrideDisplacementVolume
      project.settings.overrideDisplacementVolume_m3 = overrideDisplacementVolume_m3
    }

    /// Computes the steel displacement volume for the trip range and stores it
    func computeDisplacementVolume(project: ProjectState) {
      let tvdSampler = TvdSampler(project: project, preferPlan: useDirectionalPlanForTVD)
      let geom = ProjectGeometryService(
        project: project,
        currentStringBottomMD: startBitMD_m,
        tvdMapper: { md in tvdSampler.tvd(of: md) }
      )
      let odVolume = geom.volumeOfStringOD_m3(endMD_m, startBitMD_m)
      let idVolume = geom.volumeInString_m3(endMD_m, startBitMD_m)
      computedDisplacementVolume_m3 = max(0, odVolume - idVolume)

      // Initialize override to computed value if not yet set
      if overrideDisplacementVolume_m3 < 0.001 {
        overrideDisplacementVolume_m3 = computedDisplacementVolume_m3
      }
    }

    /// Extract PV in cP from a mud, preferring dial readings over stored pv_Pa_s.
    /// Matches the conversion logic used in SuperSimViewModel.
    private static func pvCp(for mud: MudProperties?) -> Double {
      guard let mud else { return 0 }
      if let d600 = mud.dial600, let d300 = mud.dial300 {
        return d600 - d300
      } else if let pv = mud.pv_Pa_s {
        return pv * 1000.0 // Pa·s → cP
      }
      return 0
    }

    /// Extract YP in Pa from a mud, preferring dial readings over stored yp_Pa.
    /// Matches the conversion logic used in SuperSimViewModel.
    private static func ypPa(for mud: MudProperties?) -> Double {
      guard let mud else { return 0 }
      if let d600 = mud.dial600, let d300 = mud.dial300 {
        let pvCp = d600 - d300
        return max(0, (d300 - pvCp) * HydraulicsDefaults.fann35_dialToPa)
      } else if let yp = mud.yp_Pa {
        return yp
      }
      return 0
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

      // Create sendable TVD sampler from surveys + directional plan for projection
      let tvdSampler = TvdSampler(project: project, preferPlan: useDirectionalPlanForTVD)

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

      // Use effective displacement volume (computed or user-overridden) if switching enabled
      let displacementVolume_m3: Double = switchToActiveAfterDisplacement ? effectiveDisplacementVolume_m3 : 0.0
      #if DEBUG
      if switchToActiveAfterDisplacement {
        print("[TripSim] Switch to active after displacement enabled - using \(useOverrideDisplacementVolume ? "override" : "computed") volume: \(String(format: "%.2f", displacementVolume_m3)) m³")
      }
      #endif

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
        backfillPV_cP: Self.pvCp(for: backfillMud ?? activeMud),
        backfillYP_Pa: Self.ypPa(for: backfillMud ?? activeMud),
        baseMudPV_cP: Self.pvCp(for: activeMud),
        baseMudYP_Pa: Self.ypPa(for: activeMud),
        fixedBackfillVolume_m3: displacementVolume_m3,
        switchToBaseAfterFixed: switchToActiveAfterDisplacement,
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

      // Run simulation on a background thread to keep UI responsive
      Task.detached { [weak self] in
        let model = NumericalTripModel()
        let results = model.run(input, geom: geom, projectSnapshot: projectSnapshot) { progress in
          Task { @MainActor [weak self] in
            self?.progressValue = progress.progress
            self?.progressMessage = progress.message
            self?.progressPhase = progress.phase
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

      // Store final pocket layers for quick access during Trip-In import
      // (avoids loading all steps just to get the final pocket state)
      if let lastStep = steps.last {
          simulation.finalPocketLayers = lastStep.layersPocket.map { TripLayerSnapshot(from: $0) }
      }

      // Freeze inputs for data integrity - ensures simulation remains valid if project changes
      simulation.freezeInputs(from: project, backfillMud: backfillMud, activeMud: project.activeMud)

      // Clear step layer data to reduce storage (layers can be recomputed from frozen inputs)
      // Keep only final pocket layers for Trip-In import
      simulation.clearStepLayerData()

      // Link to project (for backwards compatibility) and to well
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

    // MARK: - Wellbore State Export

    /// Export the wellbore state at the currently selected step for handoff to Trip In or Pump Schedule.
    func wellboreStateAtSelectedStep() -> WellboreStateSnapshot? {
      guard let idx = selectedIndex, steps.indices.contains(idx) else { return nil }
      let step = steps[idx]
      return WellboreStateSnapshot(
        bitMD_m: step.bitMD_m,
        bitTVD_m: step.bitTVD_m,
        layersPocket: step.layersPocket.map { TripLayerSnapshot(from: $0) },
        layersAnnulus: step.layersAnnulus.map { TripLayerSnapshot(from: $0) },
        layersString: step.layersString.map { TripLayerSnapshot(from: $0) },
        SABP_kPa: step.SABP_kPa,
        ESDAtControl_kgpm3: step.ESDatTD_kgpm3,
        sourceDescription: "Trip Out at \(Int(step.bitMD_m))m MD",
        timestamp: .now
      )
    }

    /// Import wellbore state from another operation (e.g., Trip In handoff)
    func importFromWellboreState(_ state: WellboreStateSnapshot, project: ProjectState) {
      importedStateDescription = state.sourceDescription
      startBitMD_m = state.bitMD_m
      // Keep existing endMD_m (user's end depth target)
      targetESDAtTD_kgpm3 = state.ESDAtControl_kgpm3
    }

    // MARK: - Ballooning Field Adjustment

    var ballooningActualVolume_m3: Double = 0.0
    var ballooningResult: BallooningAdjustmentCalculator.Result?

    func recalculateBallooning(project: ProjectState) {
      guard let idx = selectedIndex, steps.indices.contains(idx) else {
        ballooningResult = nil
        return
      }
      let step = steps[idx]
      let simulatedVol = step.cumulativeBackfill_m3

      let tvdSampler = TvdSampler(project: project, preferPlan: useDirectionalPlanForTVD)
      let geom = ProjectGeometryService(
        project: project,
        currentStringBottomMD: step.bitMD_m,
        tvdMapper: { md in tvdSampler.tvd(of: md) }
      )

      let backfillMud = backfillMudID.flatMap { id in (project.muds ?? []).first(where: { $0.id == id }) }
      let killDensity = backfillMud?.density_kgm3 ?? backfillDensity_kgpm3
      let baseDensity = project.activeMud?.density_kgm3 ?? baseMudDensity_kgpm3

      ballooningResult = BallooningAdjustmentCalculator.calculate(.init(
        simulatedSABP_kPa: step.SABP_kPa,
        simulatedKillMudVolume_m3: simulatedVol,
        actualKillMudVolume_m3: ballooningActualVolume_m3,
        killMudDensity_kgpm3: killDensity,
        originalMudDensity_kgpm3: baseDensity,
        geom: geom
      ))
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

    // Backfill switching: pump backfill mud until displacement volume, then switch to active mud
    var switchToActiveAfterDisplacement: Bool = false

    // Computed displacement volume (can be overridden by user)
    var computedDisplacementVolume_m3: Double = 0.0
    var overrideDisplacementVolume_m3: Double = 0.0
    var useOverrideDisplacementVolume: Bool = false

    var effectiveDisplacementVolume_m3: Double {
        useOverrideDisplacementVolume ? overrideDisplacementVolume_m3 : computedDisplacementVolume_m3
    }

    // Swab calculation parameters
    var eccentricityFactor: Double = 1.2  // 1.0 = concentric, higher = more eccentric (matches SwabbingViewModel)

    // Observed pit gain calibration
    var useObservedPitGain: Bool = false
    var observedInitialPitGain_m3: Double = 0.0
    var calculatedInitialPitGain_m3: Double = 0.0

    // View options
    var colorByComposition: Bool = false
    var showDetails: Bool = false

    // TVD source selection - use directional plan instead of surveys for projection
    var useDirectionalPlanForTVD: Bool = false

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

      // Load persisted backfill switching settings
      switchToActiveAfterDisplacement = project.settings.switchToActiveAfterDisplacement
      useOverrideDisplacementVolume = project.settings.useOverrideDisplacementVolume
      overrideDisplacementVolume_m3 = project.settings.overrideDisplacementVolume_m3
    }

    func saveBackfillSettings(to project: ProjectState) {
      project.settings.switchToActiveAfterDisplacement = switchToActiveAfterDisplacement
      project.settings.useOverrideDisplacementVolume = useOverrideDisplacementVolume
      project.settings.overrideDisplacementVolume_m3 = overrideDisplacementVolume_m3
    }

    func computeDisplacementVolume(project: ProjectState) {
      let tvdSampler = TvdSampler(project: project, preferPlan: useDirectionalPlanForTVD)
      let geom = ProjectGeometryService(
        project: project,
        currentStringBottomMD: startBitMD_m,
        tvdMapper: { md in tvdSampler.tvd(of: md) }
      )
      let odVolume = geom.volumeOfStringOD_m3(endMD_m, startBitMD_m)
      let idVolume = geom.volumeInString_m3(endMD_m, startBitMD_m)
      computedDisplacementVolume_m3 = max(0, odVolume - idVolume)
      if overrideDisplacementVolume_m3 < 0.001 {
        overrideDisplacementVolume_m3 = computedDisplacementVolume_m3
      }
    }

    private static func pvCp(for mud: MudProperties?) -> Double {
      guard let mud else { return 0 }
      if let d600 = mud.dial600, let d300 = mud.dial300 {
        return d600 - d300
      } else if let pv = mud.pv_Pa_s {
        return pv * 1000.0
      }
      return 0
    }

    private static func ypPa(for mud: MudProperties?) -> Double {
      guard let mud else { return 0 }
      if let d600 = mud.dial600, let d300 = mud.dial300 {
        let pvCp = d600 - d300
        return max(0, (d300 - pvCp) * HydraulicsDefaults.fann35_dialToPa)
      } else if let yp = mud.yp_Pa {
        return yp
      }
      return 0
    }

    func runSimulation(project: ProjectState) {
      // Reset progress state
      isRunning = true
      progressValue = 0.0
      progressMessage = "Initializing..."
      progressPhase = .initializing

      // Create sendable TVD sampler from surveys + directional plan for projection
      let tvdSampler = TvdSampler(project: project, preferPlan: useDirectionalPlanForTVD)

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

      // Use effective displacement volume (computed or user-overridden) if switching enabled
      let displacementVolume_m3: Double = switchToActiveAfterDisplacement ? effectiveDisplacementVolume_m3 : 0.0

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
        backfillPV_cP: Self.pvCp(for: backfillMud2 ?? activeMud),
        backfillYP_Pa: Self.ypPa(for: backfillMud2 ?? activeMud),
        baseMudPV_cP: Self.pvCp(for: activeMud),
        baseMudYP_Pa: Self.ypPa(for: activeMud),
        fixedBackfillVolume_m3: displacementVolume_m3,
        switchToBaseAfterFixed: switchToActiveAfterDisplacement,
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

      // Run simulation on a background thread to keep UI responsive
      Task.detached { [weak self] in
        let model = NumericalTripModel()
        let results = model.run(input, geom: geom, projectSnapshot: projectSnapshot) { progress in
          Task { @MainActor [weak self] in
            self?.progressValue = progress.progress
            self?.progressMessage = progress.message
            self?.progressPhase = progress.phase
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

      // Store final pocket layers for quick access during Trip-In import
      // (avoids loading all steps just to get the final pocket state)
      if let lastStep = steps.last {
          simulation.finalPocketLayers = lastStep.layersPocket.map { TripLayerSnapshot(from: $0) }
      }

      // Freeze inputs for data integrity - ensures simulation remains valid if project changes
      simulation.freezeInputs(from: project, backfillMud: backfillMud, activeMud: project.activeMud)

      // Clear step layer data to reduce storage (layers can be recomputed from frozen inputs)
      // Keep only final pocket layers for Trip-In import
      simulation.clearStepLayerData()

      // Link to project (for backwards compatibility) and to well
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

    // MARK: - Wellbore State Export

    /// Export the wellbore state at the currently selected step for handoff to Trip In or Pump Schedule.
    func wellboreStateAtSelectedStep() -> WellboreStateSnapshot? {
      guard let idx = selectedIndex, steps.indices.contains(idx) else { return nil }
      let step = steps[idx]
      return WellboreStateSnapshot(
        bitMD_m: step.bitMD_m,
        bitTVD_m: step.bitTVD_m,
        layersPocket: step.layersPocket.map { TripLayerSnapshot(from: $0) },
        layersAnnulus: step.layersAnnulus.map { TripLayerSnapshot(from: $0) },
        layersString: step.layersString.map { TripLayerSnapshot(from: $0) },
        SABP_kPa: step.SABP_kPa,
        ESDAtControl_kgpm3: step.ESDatTD_kgpm3,
        sourceDescription: "Trip Out at \(Int(step.bitMD_m))m MD",
        timestamp: .now
      )
    }

    // MARK: - Ballooning Field Adjustment

    var ballooningActualVolume_m3: Double = 0.0
    var ballooningResult: BallooningAdjustmentCalculator.Result?

    func recalculateBallooning(project: ProjectState) {
      guard let idx = selectedIndex, steps.indices.contains(idx) else {
        ballooningResult = nil
        return
      }
      let step = steps[idx]
      let simulatedVol = step.cumulativeBackfill_m3

      let tvdSampler = TvdSampler(project: project, preferPlan: useDirectionalPlanForTVD)
      let geom = ProjectGeometryService(
        project: project,
        currentStringBottomMD: step.bitMD_m,
        tvdMapper: { md in tvdSampler.tvd(of: md) }
      )

      let backfillMud = backfillMudID.flatMap { id in (project.muds ?? []).first(where: { $0.id == id }) }
      let killDensity = backfillMud?.density_kgm3 ?? backfillDensity_kgpm3
      let baseDensity = project.activeMud?.density_kgm3 ?? baseMudDensity_kgpm3

      ballooningResult = BallooningAdjustmentCalculator.calculate(.init(
        simulatedSABP_kPa: step.SABP_kPa,
        simulatedKillMudVolume_m3: simulatedVol,
        actualKillMudVolume_m3: ballooningActualVolume_m3,
        killMudDensity_kgpm3: killDensity,
        originalMudDensity_kgpm3: baseDensity,
        geom: geom
      ))
    }
  }
}
#endif
