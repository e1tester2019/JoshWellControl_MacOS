//
//  TvdSampler.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-07.
//


/// Provides TVD interpolation from MD using either survey data or directional plan data.
final class TvdSampler: Sendable {
    private let md: [Double]
    private let tvd: [Double]

    /// Whether this sampler is using directional plan data (vs survey data)
    let isUsingPlan: Bool

    /// Initialize with survey stations (for actual drilled well path)
    init(stations: [SurveyStation]) {
        // sort & dedup by MD, enforce monotonic TVD
        let s = stations.sorted { $0.md < $1.md }
        var mdArr: [Double] = []
        var tvdArr: [Double] = []
        var lastMD = -Double.greatestFiniteMagnitude
        for st in s {
            guard st.md > lastMD else { continue }
            mdArr.append(st.md)
            let tvd = st.tvd ?? st.md
            tvdArr.append(tvd)
            lastMD = st.md
        }
        self.md = mdArr
        self.tvd = tvdArr
        self.isUsingPlan = false
    }

    /// Initialize with directional plan stations (for projected/planned well path)
    init(planStations: [DirectionalPlanStation]) {
        let sorted = planStations.sorted { $0.md < $1.md }
        var mdArr: [Double] = []
        var tvdArr: [Double] = []
        var lastMD = -Double.greatestFiniteMagnitude

        for ps in sorted {
            guard ps.md > lastMD else { continue }
            mdArr.append(ps.md)
            tvdArr.append(ps.tvd)
            lastMD = ps.md
        }

        self.md = mdArr
        self.tvd = tvdArr
        self.isUsingPlan = true
    }

    /// Convenience initializer - uses directional plan if available, otherwise surveys
    /// - Parameters:
    ///   - project: The project state
    ///   - preferPlan: If true, prefer directional plan over surveys when available
    @MainActor
    convenience init(project: ProjectState, preferPlan: Bool = false) {
        let surveys = project.surveys ?? []
        let planStations = project.well?.directionalPlans?.first?.stations ?? []

        if preferPlan && !planStations.isEmpty {
            self.init(planStations: planStations)
        } else if !surveys.isEmpty {
            self.init(stations: surveys)
        } else if !planStations.isEmpty {
            self.init(planStations: planStations)
        } else {
            self.init(stations: [])
        }
    }

    nonisolated func tvd(of queryMD: Double) -> Double {
        guard let firstMD = md.first, let lastMD = md.last else { return queryMD }
        if queryMD <= firstMD { return tvd.first! }
        if queryMD >= lastMD  { return tvd.last!  }
        // binary search then linear interpolation
        var lo = 0, hi = md.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if md[mid] <= queryMD { lo = mid } else { hi = mid }
        }
        let t = (queryMD - md[lo]) / max(md[hi] - md[lo], 1e-12)
        return tvd[lo] + t * (tvd[hi] - tvd[lo])
    }

    /// Get the maximum MD available
    var maxMD: Double {
        md.last ?? 0
    }

    /// Get the maximum TVD available
    var maxTVD: Double {
        tvd.last ?? 0
    }

    /// Initialize directly from MD/TVD arrays (for frozen simulation inputs)
    init(mdArray: [Double], tvdArray: [Double]) {
        precondition(mdArray.count == tvdArray.count, "MD and TVD arrays must have same length")
        // Arrays should already be sorted and deduped by caller
        self.md = mdArray
        self.tvd = tvdArray
        self.isUsingPlan = false
    }

}
