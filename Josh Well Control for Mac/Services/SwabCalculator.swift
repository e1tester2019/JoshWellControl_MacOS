//
//  SwabCalculator.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-06.
//

import Foundation

/// SwabCalculator
///  - Units: ρ (kg/m³), OD/ID/diameters (m), MD/TVD (m), Va (m/s), ΔP (Pa), ΔP per m (Pa/m), speeds (m/min input).
///  - Rheology: Provide validated Power‑Law correlations via the initializer.
///    Pass your C# equivalents for (K,n) from 600/300 and the laminar ΔP/L to reproduce legacy results exactly.

struct SwabSegmentResult: Identifiable {
    let id = UUID()
    let MD_m: Double
    let TVD_m: Double
    let Dh_m: Double
    let Va_mps: Double
    let dPperM_PaPerM: Double
    let CumSwab_kPa: Double
    let Laminar: Bool
    let Re_g: Double
}

struct SwabEstimate {
    let profile: [SwabSegmentResult]
    let totalSwab_kPa: Double
    let recommendedSABP_kPa: Double
    let nonLaminarFlag: Bool
}

struct SwabCalculator {
    // MARK: - Rheology plugs (inject your validated correlations here)
    typealias PLFrom600_300 = (_ theta600: Double, _ theta300: Double) -> (K: Double, n: Double)
    typealias PLLaminarGradient = (_ rho: Double, _ K: Double, _ n: Double, _ Va: Double, _ Dh: Double) -> (dPperM: Double, laminar: Bool, Re_g: Double)

    private let _plFrom600_300: PLFrom600_300
    private let _plLaminarGradient: PLLaminarGradient

    /// Designated initializer allowing callers to inject validated rheology functions.
    /// Defaults match the current placeholder logic so existing behavior is unchanged.
    init(
        plFrom600_300: @escaping PLFrom600_300 = { theta600, theta300 in
            // n from 600/300
            let n = log(theta600/theta300) / log(600.0/300.0) // = ln(θ600/θ300)/ln 2

            // Convert dial → shear stress (Pa) and rpm → shear rate (1/s)
            // Fann 35: τ(Pa)=0.4788*θ ; γ(1/s)=rpm*1.703 ~ {300→511, 600→1022}
            let tau600 = 0.4788 * theta600     // Pa
            let gamma600 = 1022.0              // 1/s
            // Power-law K in Pa·s^n using one point (600):
            let K = tau600 / pow(gamma600, n)  // Pa·s^n

            return (K, n)
        },
        plLaminarGradient: @escaping PLLaminarGradient = { rho, K, n, Va, Dh in
            // Guard
            let Dh = max(Dh, 1e-6)
            let Va = max(Va, 1e-12)

            // Mooney–Rabinowitsch wall shear rate for power-law, pipe-analogy with Dh
            let gamma_w = ((3.0 * n + 1.0) / (4.0 * n)) * (8.0 * Va / Dh) // 1/s
            let tau_w = K * pow(gamma_w, n)                                // Pa

            // Laminar ΔP/L (Pa/m) using τw
            let dPperM = 4.0 * tau_w / Dh

            // Metzner–Reed generalized Reynolds number
            let Re_g = rho * pow(Va, 2.0 - n) * pow(Dh, n) / (K * pow(8.0, n - 1.0))

            // Laminar flag (you can refine the threshold by n if you’d like)
            let laminar = Re_g < 2100.0
            return (dPperM, laminar, Re_g)
        }
    ) {
        self._plFrom600_300 = plFrom600_300
        self._plLaminarGradient = plLaminarGradient
    }

    struct LayerDTO { // light DTO so we aren’t tied to SwiftData types
        let rho_kgpm3: Double
        let topMD_m: Double
        let bottomMD_m: Double
    }

    /// Use injected closures for rheology calculations.
    func estimateFromLayersPowerLaw(
        layers: [LayerDTO],
        theta600: Double,
        theta300: Double,
        hoistSpeed_mpermin: Double,
        eccentricityFactor: Double,
        step_m: Double,
        geom: GeometryService,
        traj: TrajectorySampler? = nil,
        sabpSafety: Double = 1.15,
        floatIsOpen: Bool = false     // 👈 add this
    ) throws -> SwabEstimate {

        guard !layers.isEmpty else { throw NSError(domain: "Swab", code: 1, userInfo: [NSLocalizedDescriptionKey: "No layers."]) }
        guard theta600 > 0, theta300 > 0 else { throw NSError(domain: "Swab", code: 2, userInfo: [NSLocalizedDescriptionKey: "Need 600/300."]) }
        guard hoistSpeed_mpermin > 0 else { throw NSError(domain: "Swab", code: 3, userInfo: [NSLocalizedDescriptionKey: "Hoist speed must be > 0 (m/min)."]) }
        guard step_m > 0 else { throw NSError(domain: "Swab", code: 4, userInfo: [NSLocalizedDescriptionKey: "Step must be > 0."]) }

        let (K, n) = _plFrom600_300(theta600, theta300)
        let Vpipe_mps = hoistSpeed_mpermin / 60.0

        // deep → shallow ordering
        var ordered = [(rho: Double, deep: Double, shal: Double)]()
        ordered.reserveCapacity(layers.count)
        for L in layers {
            let deep = max(L.topMD_m, L.bottomMD_m)
            let shal = min(L.topMD_m, L.bottomMD_m)
            ordered.append((L.rho_kgpm3, deep, shal))
        }
        ordered.sort { $0.deep > $1.deep }

        var prof: [SwabSegmentResult] = []
        prof.reserveCapacity(Int(ceil((ordered.first?.deep ?? 0) / step_m)))
        var cumSwab_Pa: Double = 0
        var anyNonLaminar = false

        for L in ordered {
            var md = L.deep
            while md > L.shal + 1e-12 {
                let next = max(md - step_m, L.shal)
                let segLen = md - next
                let mdMid = 0.5 * (md + next)

                // geometry (meters)
                let Do = max(geom.pipeOD_m(mdMid), 0.001)
                let Dhole = max(geom.holeOD_m(mdMid), Do + 0.0001)
                let Dh = max(Dhole - Do, 1e-6)

                let ApipeOD = .pi * Do * Do / 4.0
                let Aann = .pi * (Dhole * Dhole - Do * Do) / 4.0

                var dispA = ApipeOD  // closed-end default
                if floatIsOpen {
                    let Di = max(geom.pipeID_m(mdMid), 0.0001)
                    let ApipeID = .pi * Di * Di / 4.0
                    dispA = max(ApipeOD - ApipeID, 0)
                }

                // annular velocity
                let Va = max(Vpipe_mps * (dispA / Aann) * max(eccentricityFactor, 1.0), 1e-12)

                let rPL = _plLaminarGradient(L.rho, K, n, Va, Dh)
                let dP = rPL.dPperM * segLen // Pa
                cumSwab_Pa += dP
                if !rPL.laminar { anyNonLaminar = true }

                prof.append(SwabSegmentResult(
                    MD_m: next,
                    TVD_m: traj?.TVDofMD(mdMid) ?? 0.0,
                    Dh_m: Dh,
                    Va_mps: Va,
                    dPperM_PaPerM: rPL.dPperM,
                    CumSwab_kPa: cumSwab_Pa / 1000.0,
                    Laminar: rPL.laminar,
                    Re_g: rPL.Re_g
                ))

                md = next
            }
        }

        let total_kPa = cumSwab_Pa / 1000.0
        return SwabEstimate(
            profile: prof,
            totalSwab_kPa: total_kPa,
            recommendedSABP_kPa: total_kPa * sabpSafety,
            nonLaminarFlag: anyNonLaminar
        )
    }
}
