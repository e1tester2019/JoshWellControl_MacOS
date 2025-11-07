//
//  TvdSampler.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-07.
//


final class TvdSampler {
    private let md: [Double]
    private let tvd: [Double]

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
    }

    func tvd(of queryMD: Double) -> Double {
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
}
