//
//  TripSimulationViewModel.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-03.
//

import Foundation


extension TripSimulationView {
  @Observable
  class ViewModel {
    // Inputs
    var startBitMD_m: Double = 5983.28
    var endMD_m: Double = 0
    var shoeMD_m: Double = 2910
    var step_m: Double = 100
    var baseMudDensity_kgpm3: Double = 1260
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
      let baseActive = project.activeMud?.density_kgm3 ?? baseMudDensity_kgpm3
      baseMudDensity_kgpm3 = baseActive
      backfillDensity_kgpm3 = baseActive
      backfillMudID = project.activeMud?.id
      targetESDAtTD_kgpm3 = baseActive

      #if DEBUG
      let layerCount = (project.finalLayers ?? []).count
      print("[TripSim] Bootstrap: found \(layerCount) final layers, startBitMD=\(startBitMD_m)")
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

      let geom = ProjectGeometryService(
        project: project,
        currentStringBottomMD: startBitMD_m,
        tvdMapper: { md in project.tvd(of: md) }
      )

      // Get fallback rheology from active mud
      let activeMud = project.activeMud
      let fallbackTheta600 = activeMud?.dial600
      let fallbackTheta300 = activeMud?.dial300

      let input = NumericalTripModel.TripInput(
        tvdOfMd: { md in project.tvd(of: md) },
        shoeTVD_m: project.tvd(of: shoeMD_m),
        startBitMD_m: startBitMD_m,
        endMD_m: endMD_m,
        crackFloat_kPa: crackFloat_kPa,
        step_m: step_m,
        baseMudDensity_kgpm3: (activeMud?.density_kgm3 ?? baseMudDensity_kgpm3),
        backfillDensity_kgpm3: (
            (backfillMudID.flatMap { id in (project.muds ?? []).first(where: { $0.id == id })?.density_kgm3 })
            ?? activeMud?.density_kgm3
            ?? backfillDensity_kgpm3
        ),
        targetESDAtTD_kgpm3: targetESDAtTD_kgpm3,
        initialSABP_kPa: initialSABP_kPa,
        holdSABPOpen: holdSABPOpen,
        tripSpeed_m_per_s: abs(project.settings.tripSpeed_m_per_s),  // Use absolute value for speed
        eccentricityFactor: eccentricityFactor,
        fallbackTheta600: fallbackTheta600,
        fallbackTheta300: fallbackTheta300,
        observedInitialPitGain_m3: useObservedPitGain ? observedInitialPitGain_m3 : nil
      )

      // Run simulation on background thread with progress updates
      Task.detached { [weak self] in
        let model = NumericalTripModel()
        let results = model.run(input, geom: geom, project: project) { progress in
          Task { @MainActor in
            self?.progressValue = progress.progress
            self?.progressMessage = progress.message
            self?.progressPhase = progress.phase
          }
        }

        await MainActor.run {
          self?.steps = results
          self?.selectedIndex = results.isEmpty ? nil : 0
          self?.stepSlider = 0
          self?.isRunning = false
          self?.progressMessage = "Complete"

          // Store the calculated pit gain from the initial step (for display/comparison)
          if let firstStep = results.first {
            self?.calculatedInitialPitGain_m3 = firstStep.cumulativePitGain_m3
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
  }
}

#if (os(iOS))
extension TripSimulationViewIOS {
  @Observable
  class ViewModel {
    // Inputs
    var startBitMD_m: Double = 5983.28
    var endMD_m: Double = 0
    var shoeMD_m: Double = 2910
    var step_m: Double = 100
    var baseMudDensity_kgpm3: Double = 1260
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

      let geom = ProjectGeometryService(
        project: project,
        currentStringBottomMD: startBitMD_m,
        tvdMapper: { md in project.tvd(of: md) }
      )

      // Get fallback rheology from active mud
      let activeMud = project.activeMud
      let fallbackTheta600 = activeMud?.dial600
      let fallbackTheta300 = activeMud?.dial300

      let input = NumericalTripModel.TripInput(
        tvdOfMd: { md in project.tvd(of: md) },
        shoeTVD_m: project.tvd(of: shoeMD_m),
        startBitMD_m: startBitMD_m,
        endMD_m: endMD_m,
        crackFloat_kPa: crackFloat_kPa,
        step_m: step_m,
        baseMudDensity_kgpm3: (activeMud?.density_kgm3 ?? baseMudDensity_kgpm3),
        backfillDensity_kgpm3: (
            (backfillMudID.flatMap { id in (project.muds ?? []).first(where: { $0.id == id })?.density_kgm3 })
            ?? activeMud?.density_kgm3
            ?? backfillDensity_kgpm3
        ),
        targetESDAtTD_kgpm3: targetESDAtTD_kgpm3,
        initialSABP_kPa: initialSABP_kPa,
        holdSABPOpen: holdSABPOpen,
        tripSpeed_m_per_s: abs(project.settings.tripSpeed_m_per_s),
        eccentricityFactor: eccentricityFactor,
        fallbackTheta600: fallbackTheta600,
        fallbackTheta300: fallbackTheta300,
        observedInitialPitGain_m3: useObservedPitGain ? observedInitialPitGain_m3 : nil
      )

      // Run simulation on background thread with progress updates
      Task.detached { [weak self] in
        let model = NumericalTripModel()
        let results = model.run(input, geom: geom, project: project) { progress in
          Task { @MainActor in
            self?.progressValue = progress.progress
            self?.progressMessage = progress.message
            self?.progressPhase = progress.phase
          }
        }

        await MainActor.run {
          self?.steps = results
          self?.selectedIndex = results.isEmpty ? nil : 0
          self?.stepSlider = 0
          self?.isRunning = false
          self?.progressMessage = "Complete"

          // Store the calculated pit gain from the initial step
          if let firstStep = results.first {
            self?.calculatedInitialPitGain_m3 = firstStep.cumulativePitGain_m3
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
  }
}
#endif
