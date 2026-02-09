//
//  SuperSimHTMLGenerator.swift
//  Josh Well Control for Mac
//
//  Interactive HTML report generator for Super Simulation.
//  Produces a self-contained HTML file with embedded CSS/JS:
//  - Tabbed navigation: Summary + per-operation detail tabs
//  - Per-step wellbore visualization with playback
//  - HiDPI timeline charts (ESD + Back Pressure)
//  - Operation-type-specific step tables matching standalone reports
//

import Foundation

// MARK: - Report Data

struct SuperSimReportData {
    let wellName: String
    let projectName: String
    let generatedDate: Date
    let controlTVD_m: Double

    struct OperationData {
        let index: Int
        let type: OperationType
        let label: String
        let startMD_m: Double
        let endMD_m: Double
        let controlMD_m: Double
        let targetESD_kgpm3: Double
        let tripOutSteps: [TripOutStep]?
        let tripInSteps: [TripInStep]?
        let circulationSteps: [CirculationStep]?
        let stringVolume_m3: Double?
        let annulusVolume_m3: Double?

        var stepCount: Int {
            (tripOutSteps?.count ?? 0) + (tripInSteps?.count ?? 0) + (circulationSteps?.count ?? 0)
        }
    }

    struct TripOutStep {
        let bitMD_m: Double
        let bitTVD_m: Double
        let SABP_kPa: Double
        let SABP_Dynamic_kPa: Double
        let ESDatTD_kgpm3: Double
        let expectedFillIfClosed_m3: Double
        let expectedFillIfOpen_m3: Double
        let stepBackfill_m3: Double
        let cumulativeSurfaceTankDelta_m3: Double
        let floatState: String
        let layersAnnulus: [LayerData]
        let layersString: [LayerData]
        let layersPocket: [LayerData]
    }

    struct TripInStep {
        let bitMD_m: Double
        let bitTVD_m: Double
        let ESDAtControl_kgpm3: Double
        let requiredChokePressure_kPa: Double
        let annulusPressureAtBit_kPa: Double
        let stringPressureAtBit_kPa: Double
        let differentialPressureAtBottom_kPa: Double
        let cumulativeFillVolume_m3: Double
        let cumulativeDisplacementReturns_m3: Double
        let floatState: String
        let layersAnnulus: [LayerData]
        let layersString: [LayerData]
        let layersPocket: [LayerData]
    }

    struct CirculationStep {
        let volumePumped_m3: Double
        let ESDAtControl_kgpm3: Double
        let requiredSABP_kPa: Double
        let deltaSABP_kPa: Double
        let description: String
        let layersAnnulus: [LayerData]
        let layersString: [LayerData]
        let layersPocket: [LayerData]
        let bitMD_m: Double
        let pumpRate_m3perMin: Double
        let apl_kPa: Double
    }

    struct LayerData {
        let topMD: Double
        let bottomMD: Double
        let topTVD: Double
        let bottomTVD: Double
        let rho_kgpm3: Double
        let colorR: Double?
        let colorG: Double?
        let colorB: Double?
        let colorA: Double?
    }

    struct TimelineStep {
        let globalIndex: Int
        let operationIndex: Int
        let operationType: OperationType
        let operationLabel: String
        let bitMD_m: Double
        let bitTVD_m: Double
        let ESD_kgpm3: Double
        let staticSABP_kPa: Double
        let dynamicSABP_kPa: Double
        let layersAnnulus: [LayerData]
        let layersString: [LayerData]
        let layersPocket: [LayerData]
    }

    let operations: [OperationData]
    let timelineSteps: [TimelineStep]
}

// MARK: - Generator

class SuperSimHTMLGenerator {
    static let shared = SuperSimHTMLGenerator()
    private init() {}

    func generateHTML(for data: SuperSimReportData) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy, HH:mm"
        let dateStr = dateFormatter.string(from: data.generatedDate)

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Super Simulation Report - \(esc(data.wellName))</title>
            <style>\(generateCSS())</style>
        </head>
        <body>
            <header>
                <div class="header-content">
                    <h1>Super Simulation Report</h1>
                    <span class="well-name">\(esc(data.wellName))</span>
                </div>
            </header>

            <!-- Tab Bar -->
            <nav class="tab-bar">
                <button class="tab active" onclick="showTab('summary')">Summary</button>
                \(data.operations.map { op in
                    "<button class=\"tab\" onclick=\"showTab('op\(op.index)')\">\(op.index + 1). \(op.type.rawValue)</button>"
                }.joined(separator: "\n                "))
            </nav>

            <main>
                <!-- SUMMARY TAB -->
                <div id="tab-summary" class="tab-content active">
                    \(generateSummaryTab(data, dateStr: dateStr))
                </div>

                <!-- OPERATION TABS -->
                \(data.operations.map { generateOperationTab($0, data: data) }.joined(separator: "\n"))
            </main>

            <footer>
                <p>Generated by Josh Well Control &bull; \(dateStr)</p>
            </footer>

            <script>
                \(generateJavaScript(data))
            </script>
        </body>
        </html>
        """
    }

    // MARK: - Summary Tab

    private func generateSummaryTab(_ data: SuperSimReportData, dateStr: String) -> String {
        let totalSteps = data.timelineSteps.count
        return """
        <!-- Well Information -->
        <section class="card">
            <h2>Well Information</h2>
            <div class="info-grid">
                <div class="info-item"><span class="label">Well:</span> <span>\(esc(data.wellName))</span></div>
                <div class="info-item"><span class="label">Project:</span> <span>\(esc(data.projectName))</span></div>
                <div class="info-item"><span class="label">Date:</span> <span>\(dateStr)</span></div>
                <div class="info-item"><span class="label">Operations:</span> <span>\(data.operations.count)</span></div>
                <div class="info-item"><span class="label">Total Steps:</span> <span>\(totalSteps)</span></div>
            </div>
        </section>

        <!-- Operations Timeline -->
        <section class="card">
            <h2>Operations Timeline</h2>
            \(generateOpsTimeline(data.operations))
        </section>

        <!-- Interactive Wellbore -->
        <section class="card">
            <h2>Interactive Well Snapshot</h2>
            <div class="wellbore-controls">
                <div class="slider-container">
                    <label>Simulation Progress:</label>
                    <input type="range" id="global-slider" min="0" max="\(max(0, totalSteps - 1))" value="0">
                    <span id="global-step-label">Step 0</span>
                </div>
                <div class="playback-controls">
                    <button id="global-play-btn" onclick="globalTogglePlay()">&#9654; Play</button>
                    <button onclick="globalReset()">&#8634; Reset</button>
                    <select id="global-speed"><option value="500">Slow</option><option value="200" selected>Normal</option><option value="50">Fast</option></select>
                </div>
            </div>
            <div class="wellbore-display">
                <div id="global-op-label" class="op-activity-label"></div>
                <canvas id="g-well" width="200" height="500"></canvas>
            </div>
            <div class="step-info" id="global-info">
                <div class="info-row"><span>Operation:</span> <span id="gi-op">--</span></div>
                <div class="info-row"><span>Bit MD:</span> <span id="gi-md">--</span></div>
                <div class="info-row"><span>ESD:</span> <span id="gi-esd">--</span></div>
                <div class="info-row"><span>Static SABP:</span> <span id="gi-sabp-s">--</span></div>
                <div class="info-row"><span>Dynamic SABP:</span> <span id="gi-sabp-d">--</span></div>
            </div>
        </section>

        <!-- Timeline Charts -->
        <section class="card">
            <h2>Timeline Charts</h2>
            <div class="chart-tabs">
                <button class="chart-tab active" onclick="showChart('esd',this)">ESD</button>
                <button class="chart-tab" onclick="showChart('sabp',this)">Back Pressure</button>
            </div>
            <div id="container-esd" class="chart-container"><canvas id="chart-esd"></canvas></div>
            <div id="container-sabp" class="chart-container" style="display:none"><canvas id="chart-sabp"></canvas></div>
            <div id="chart-values" class="chart-value-label"></div>
        </section>
        """
    }

    // MARK: - Operations Timeline Cards

    private func generateOpsTimeline(_ ops: [SuperSimReportData.OperationData]) -> String {
        var html = "<div class=\"ops-timeline\">"
        for op in ops {
            let cls: String
            let icon: String
            switch op.type {
            case .tripOut: cls = "trip-out"; icon = "&#9650;"
            case .tripIn: cls = "trip-in"; icon = "&#9660;"
            case .circulate: cls = "circulate"; icon = "&#8634;"
            }
            html += """
            <div class="op-card \(cls)" onclick="showTab('op\(op.index)')" style="cursor:pointer">
                <div class="op-header">
                    <span class="op-icon">\(icon)</span>
                    <span class="op-number">\(op.index + 1)</span>
                    <span class="op-type">\(op.type.rawValue)</span>
                </div>
                <div class="op-details">
                    <div class="op-detail"><span>Depth:</span> \(f0(op.startMD_m))m &rarr; \(f0(op.endMD_m))m</div>
                    <div class="op-detail"><span>Target ESD:</span> \(f0(op.targetESD_kgpm3)) kg/m&sup3;</div>
                    <div class="op-detail"><span>Control MD:</span> \(f0(op.controlMD_m))m</div>
                    <div class="op-detail"><span>Steps:</span> \(op.stepCount)</div>
            """
            if op.type == .circulate {
                if let sv = op.stringVolume_m3 { html += "<div class=\"op-detail\"><span>String Vol:</span> \(f2(sv)) m&sup3;</div>" }
                if let av = op.annulusVolume_m3 { html += "<div class=\"op-detail\"><span>Annulus Vol:</span> \(f2(av)) m&sup3;</div>" }
                if let sv = op.stringVolume_m3, let av = op.annulusVolume_m3 {
                    html += "<div class=\"op-detail highlight\"><span>Combined:</span> \(f2(sv + av)) m&sup3;</div>"
                }
            }
            html += "</div></div>"
        }
        html += "</div>"
        return html
    }

    // MARK: - Per-Operation Tabs

    private func generateOperationTab(_ op: SuperSimReportData.OperationData, data: SuperSimReportData) -> String {
        let opId = "op\(op.index)"
        var html = "<div id=\"tab-\(opId)\" class=\"tab-content\">"

        // Header
        let typeLabel: String
        switch op.type {
        case .tripOut: typeLabel = "Trip Out"
        case .tripIn: typeLabel = "Trip In"
        case .circulate: typeLabel = "Circulate"
        }
        html += """
        <section class="card">
            <h2>\(op.index + 1). \(typeLabel) &mdash; \(f0(op.startMD_m))m &rarr; \(f0(op.endMD_m))m</h2>
            <div class="info-grid">
                <div class="info-item"><span class="label">Control MD:</span> <span>\(f0(op.controlMD_m))m</span></div>
                <div class="info-item"><span class="label">Target ESD:</span> <span>\(f0(op.targetESD_kgpm3)) kg/m&sup3;</span></div>
                <div class="info-item"><span class="label">Steps:</span> <span>\(op.stepCount)</span></div>
        """
        if let sv = op.stringVolume_m3 { html += "<div class=\"info-item\"><span class=\"label\">String Vol:</span> <span>\(f2(sv)) m&sup3;</span></div>" }
        if let av = op.annulusVolume_m3 { html += "<div class=\"info-item\"><span class=\"label\">Annulus Vol:</span> <span>\(f2(av)) m&sup3;</span></div>" }
        html += "</div></section>"

        // Wellbore + step info
        let stepCount = op.stepCount
        html += """
        <section class="card">
            <h2>Wellbore State</h2>
            <div class="wellbore-controls">
                <div class="slider-container">
                    <button onclick="opStepPrev('\(opId)')">&#9664;</button>
                    <input type="range" id="\(opId)-slider" min="0" max="\(max(0, stepCount - 1))" value="0">
                    <button onclick="opStepNext('\(opId)')">&#9654;</button>
                    <span id="\(opId)-step-label">Step 1 / \(stepCount)</span>
                </div>
                <div class="playback-controls">
                    <button id="\(opId)-play-btn" onclick="opTogglePlay('\(opId)')">&#9654; Play</button>
                    <select id="\(opId)-speed"><option value="500">Slow</option><option value="200" selected>Normal</option><option value="50">Fast</option></select>
                </div>
            </div>
            <div class="wellbore-display">
                <div id="\(opId)-op-label" class="op-activity-label">\(op.type.rawValue)</div>
                <canvas id="\(opId)-well" width="200" height="500"></canvas>
            </div>
            <div class="step-info" id="\(opId)-info"></div>
        </section>
        """

        // Step table
        html += "<section class=\"card\">"
        html += "<h2>Step Data</h2>"
        html += "<div class=\"table-controls\">"
        html += "<input type=\"text\" id=\"\(opId)-search\" placeholder=\"Search...\" onkeyup=\"filterOpTable('\(opId)')\">"
        html += "<button onclick=\"exportOpCSV('\(opId)')\">Export CSV</button>"
        html += "</div>"

        switch op.type {
        case .tripOut:
            html += generateTripOutTable(op.tripOutSteps ?? [], opId: opId)
        case .tripIn:
            html += generateTripInTable(op.tripInSteps ?? [], opId: opId)
        case .circulate:
            html += generateCirculationTable(op.circulationSteps ?? [], opId: opId)
        }

        html += "</section>"
        html += "</div>"
        return html
    }

    // MARK: - Trip Out Table

    private func generateTripOutTable(_ steps: [SuperSimReportData.TripOutStep], opId: String) -> String {
        var html = """
        <div class="table-wrapper"><table id="\(opId)-table" class="op-table">
        <thead><tr>
            <th onclick="sortOpTable('\(opId)',0)">MD (m) &#8693;</th>
            <th onclick="sortOpTable('\(opId)',1)">TVD (m) &#8693;</th>
            <th onclick="sortOpTable('\(opId)',2)">Static SABP &#8693;</th>
            <th onclick="sortOpTable('\(opId)',3)">Dynamic SABP &#8693;</th>
            <th onclick="sortOpTable('\(opId)',4)">ESD (kg/m&sup3;) &#8693;</th>
            <th onclick="sortOpTable('\(opId)',5)">DP Wet (m&sup3;) &#8693;</th>
            <th onclick="sortOpTable('\(opId)',6)">DP Dry (m&sup3;) &#8693;</th>
            <th onclick="sortOpTable('\(opId)',7)">Actual (m&sup3;) &#8693;</th>
            <th onclick="sortOpTable('\(opId)',8)">Tank &Delta; (m&sup3;) &#8693;</th>
            <th onclick="sortOpTable('\(opId)',9)">Float &#8693;</th>
        </tr></thead><tbody>
        """
        for (i, s) in steps.enumerated() {
            html += """
            <tr onclick="opGoToStep('\(opId)',\(i))" class="clickable-row">
                <td>\(f0(s.bitMD_m))</td><td>\(f0(s.bitTVD_m))</td>
                <td>\(f0(s.SABP_kPa))</td><td>\(f0(s.SABP_Dynamic_kPa))</td>
                <td>\(f1(s.ESDatTD_kgpm3))</td>
                <td>\(f2(s.expectedFillIfClosed_m3))</td><td>\(f2(s.expectedFillIfOpen_m3))</td>
                <td>\(f2(s.stepBackfill_m3))</td><td>\(f2(s.cumulativeSurfaceTankDelta_m3))</td>
                <td>\(esc(s.floatState))</td>
            </tr>
            """
        }
        html += "</tbody></table></div>"
        return html
    }

    // MARK: - Trip In Table

    private func generateTripInTable(_ steps: [SuperSimReportData.TripInStep], opId: String) -> String {
        var html = """
        <div class="table-wrapper"><table id="\(opId)-table" class="op-table">
        <thead><tr>
            <th onclick="sortOpTable('\(opId)',0)">MD (m) &#8693;</th>
            <th onclick="sortOpTable('\(opId)',1)">TVD (m) &#8693;</th>
            <th onclick="sortOpTable('\(opId)',2)">ESD (kg/m&sup3;) &#8693;</th>
            <th onclick="sortOpTable('\(opId)',3)">Choke (kPa) &#8693;</th>
            <th onclick="sortOpTable('\(opId)',4)">HP Ann@Bit &#8693;</th>
            <th onclick="sortOpTable('\(opId)',5)">HP Str@Bit &#8693;</th>
            <th onclick="sortOpTable('\(opId)',6)">&Delta;P@Float &#8693;</th>
            <th onclick="sortOpTable('\(opId)',7)">Fill (m&sup3;) &#8693;</th>
            <th onclick="sortOpTable('\(opId)',8)">Disp (m&sup3;) &#8693;</th>
            <th onclick="sortOpTable('\(opId)',9)">Float &#8693;</th>
        </tr></thead><tbody>
        """
        for (i, s) in steps.enumerated() {
            let deltaP = (s.annulusPressureAtBit_kPa + s.requiredChokePressure_kPa) - s.stringPressureAtBit_kPa
            html += """
            <tr onclick="opGoToStep('\(opId)',\(i))" class="clickable-row">
                <td>\(f0(s.bitMD_m))</td><td>\(f0(s.bitTVD_m))</td>
                <td>\(f1(s.ESDAtControl_kgpm3))</td><td>\(f0(s.requiredChokePressure_kPa))</td>
                <td>\(f0(s.annulusPressureAtBit_kPa))</td><td>\(f0(s.stringPressureAtBit_kPa))</td>
                <td>\(f0(deltaP))</td>
                <td>\(f2(s.cumulativeFillVolume_m3))</td><td>\(f2(s.cumulativeDisplacementReturns_m3))</td>
                <td>\(esc(s.floatState))</td>
            </tr>
            """
        }
        html += "</tbody></table></div>"
        return html
    }

    // MARK: - Circulation Table

    private func generateCirculationTable(_ steps: [SuperSimReportData.CirculationStep], opId: String) -> String {
        var html = """
        <div class="table-wrapper"><table id="\(opId)-table" class="op-table">
        <thead><tr>
            <th onclick="sortOpTable('\(opId)',0)">Vol Pumped (m&sup3;) &#8693;</th>
            <th onclick="sortOpTable('\(opId)',1)">ESD (kg/m&sup3;) &#8693;</th>
            <th onclick="sortOpTable('\(opId)',2)">Choke (kPa) &#8693;</th>
            <th onclick="sortOpTable('\(opId)',3)">&Delta;BP (kPa) &#8693;</th>
            <th onclick="sortOpTable('\(opId)',4)">Pump Rate (m&sup3;/min) &#8693;</th>
            <th onclick="sortOpTable('\(opId)',5)">APL (kPa) &#8693;</th>
            <th onclick="sortOpTable('\(opId)',6)">Action</th>
        </tr></thead><tbody>
        """
        for (i, s) in steps.enumerated() {
            let deltaStr: String
            if s.deltaSABP_kPa > 0.5 {
                deltaStr = "+\(f0(s.deltaSABP_kPa))"
            } else if s.deltaSABP_kPa < -0.5 {
                deltaStr = f0(s.deltaSABP_kPa)
            } else {
                deltaStr = "0"
            }
            html += """
            <tr onclick="opGoToStep('\(opId)',\(i))" class="clickable-row">
                <td>\(f2(s.volumePumped_m3))</td>
                <td>\(f1(s.ESDAtControl_kgpm3))</td>
                <td>\(f0(s.requiredSABP_kPa))</td>
                <td class="\(s.deltaSABP_kPa > 0.5 ? "delta-up" : s.deltaSABP_kPa < -0.5 ? "delta-down" : "")">\(deltaStr)</td>
                <td>\(f2(s.pumpRate_m3perMin))</td>
                <td>\(f0(s.apl_kPa))</td>
                <td>\(esc(s.description))</td>
            </tr>
            """
        }
        html += "</tbody></table></div>"
        return html
    }

    // MARK: - JSON Serialization

    private func timelineStepsJSON(_ steps: [SuperSimReportData.TimelineStep]) -> String {
        var json = "["
        for (i, s) in steps.enumerated() {
            if i > 0 { json += "," }
            json += """
            {"gi":\(s.globalIndex),"oi":\(s.operationIndex),"ot":"\(escJSON(s.operationType.rawValue))","ol":"\(escJSON(s.operationLabel))","md":\(s.bitMD_m),"tvd":\(s.bitTVD_m),"esd":\(s.ESD_kgpm3),"ss":\(s.staticSABP_kPa),"sd":\(s.dynamicSABP_kPa),"la":\(layersJSON(s.layersAnnulus)),"ls":\(layersJSON(s.layersString)),"lp":\(layersJSON(s.layersPocket))}
            """
        }
        json += "]"
        return json
    }

    private func opStepsJSON(_ op: SuperSimReportData.OperationData) -> String {
        var json = "["
        switch op.type {
        case .tripOut:
            for (i, s) in (op.tripOutSteps ?? []).enumerated() {
                if i > 0 { json += "," }
                json += """
                {"md":\(s.bitMD_m),"tvd":\(s.bitTVD_m),"esd":\(s.ESDatTD_kgpm3),"ss":\(s.SABP_kPa),"sd":\(s.SABP_Dynamic_kPa),"dpW":\(s.expectedFillIfClosed_m3),"dpD":\(s.expectedFillIfOpen_m3),"bf":\(s.stepBackfill_m3),"td":\(s.cumulativeSurfaceTankDelta_m3),"fs":"\(escJSON(s.floatState))","la":\(layersJSON(s.layersAnnulus)),"ls":\(layersJSON(s.layersString)),"lp":\(layersJSON(s.layersPocket))}
                """
            }
        case .tripIn:
            for (i, s) in (op.tripInSteps ?? []).enumerated() {
                if i > 0 { json += "," }
                let deltaP = (s.annulusPressureAtBit_kPa + s.requiredChokePressure_kPa) - s.stringPressureAtBit_kPa
                json += """
                {"md":\(s.bitMD_m),"tvd":\(s.bitTVD_m),"esd":\(s.ESDAtControl_kgpm3),"choke":\(s.requiredChokePressure_kPa),"hpA":\(s.annulusPressureAtBit_kPa),"hpS":\(s.stringPressureAtBit_kPa),"dp":\(deltaP),"fill":\(s.cumulativeFillVolume_m3),"disp":\(s.cumulativeDisplacementReturns_m3),"fs":"\(escJSON(s.floatState))","la":\(layersJSON(s.layersAnnulus)),"ls":\(layersJSON(s.layersString)),"lp":\(layersJSON(s.layersPocket))}
                """
            }
        case .circulate:
            for (i, s) in (op.circulationSteps ?? []).enumerated() {
                if i > 0 { json += "," }
                json += """
                {"vol":\(s.volumePumped_m3),"md":\(s.bitMD_m),"esd":\(s.ESDAtControl_kgpm3),"bp":\(s.requiredSABP_kPa),"dbp":\(s.deltaSABP_kPa),"pr":\(s.pumpRate_m3perMin),"apl":\(s.apl_kPa),"desc":"\(escJSON(s.description))","la":\(layersJSON(s.layersAnnulus)),"ls":\(layersJSON(s.layersString)),"lp":\(layersJSON(s.layersPocket))}
                """
            }
        }
        json += "]"
        return json
    }

    private func layersJSON(_ layers: [SuperSimReportData.LayerData]) -> String {
        var json = "["
        for (i, l) in layers.enumerated() {
            if i > 0 { json += "," }
            let c = colorStr(l)
            json += "{\"t\":\(l.topMD),\"b\":\(l.bottomMD),\"r\":\(l.rho_kgpm3),\"c\":\"\(c)\"}"
        }
        json += "]"
        return json
    }

    // MARK: - Helpers

    private func colorStr(_ l: SuperSimReportData.LayerData) -> String {
        if let r = l.colorR, let g = l.colorG, let b = l.colorB {
            let a = l.colorA ?? 1.0
            return "rgba(\(Int(r * 255)),\(Int(g * 255)),\(Int(b * 255)),\(a))"
        } else if l.rho_kgpm3 < 10 {
            return "rgba(179,217,255,0.8)"
        } else {
            let t = min(max((l.rho_kgpm3 - 800) / 1200, 0), 1)
            let g = Int((0.3 + 0.6 * t) * 255)
            return "rgb(\(g),\(g),\(g))"
        }
    }

    private func computeMaxDepth(_ data: SuperSimReportData) -> Double {
        var m = 0.0
        for s in data.timelineSteps {
            m = max(m, s.bitMD_m)
            for l in s.layersPocket { m = max(m, l.bottomMD) }
            for l in s.layersAnnulus { m = max(m, l.bottomMD) }
        }
        return m
    }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    private func escJSON(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
    }
    private func f0(_ v: Double) -> String { String(format: "%.0f", v) }
    private func f1(_ v: Double) -> String { String(format: "%.1f", v) }
    private func f2(_ v: Double) -> String { String(format: "%.2f", v) }

    // MARK: - CSS

    private func generateCSS() -> String {
        """
        :root{--brand:#e65100;--brand-light:#ff9e40;--bg:#f5f5f5;--card:#fff;--text:#222;--muted:#666;--border:#e0e0e0;}
        *{box-sizing:border-box;margin:0;padding:0;}
        body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:var(--bg);color:var(--text);line-height:1.5;}
        header{background:var(--brand);color:#fff;padding:20px 24px;}
        .header-content{max-width:1200px;margin:0 auto;display:flex;align-items:baseline;gap:16px;}
        header h1{font-size:1.5em;font-weight:600;} .well-name{font-size:1.1em;opacity:0.85;}
        main{max-width:1200px;margin:0 auto;padding:0 16px 20px;}
        .card{background:var(--card);border-radius:12px;padding:20px;margin-bottom:16px;box-shadow:0 1px 3px rgba(0,0,0,0.1);}
        .card h2{font-size:1.2em;margin-bottom:12px;color:var(--brand);border-bottom:2px solid var(--brand-light);padding-bottom:6px;}
        .info-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:8px;}
        .info-item{display:flex;gap:8px;} .info-item .label{font-weight:600;color:var(--muted);white-space:nowrap;}

        /* Tab Bar */
        .tab-bar{max-width:1200px;margin:0 auto;padding:12px 16px 0;display:flex;flex-wrap:wrap;gap:4px;}
        .tab{padding:8px 16px;border:1px solid var(--border);border-bottom:none;border-radius:8px 8px 0 0;background:var(--card);cursor:pointer;font-size:0.9em;font-weight:500;}
        .tab.active{background:var(--brand);color:#fff;border-color:var(--brand);}
        .tab-content{display:none;} .tab-content.active{display:block;}

        /* Operations Timeline */
        .ops-timeline{display:flex;flex-wrap:wrap;gap:12px;}
        .op-card{border-radius:8px;padding:12px;min-width:180px;flex:1;border-left:4px solid;transition:transform 0.1s;}
        .op-card:hover{transform:translateY(-2px);}
        .op-card.trip-out{border-color:#1976d2;background:#e3f2fd;}
        .op-card.trip-in{border-color:#388e3c;background:#e8f5e9;}
        .op-card.circulate{border-color:#e65100;background:#fff3e0;}
        .op-header{display:flex;align-items:center;gap:8px;margin-bottom:8px;font-weight:600;}
        .op-icon{font-size:1.2em;}
        .op-number{background:rgba(0,0,0,0.1);border-radius:50%;width:24px;height:24px;display:flex;align-items:center;justify-content:center;font-size:0.8em;}
        .op-details{font-size:0.85em;} .op-detail{display:flex;gap:4px;} .op-detail span:first-child{color:var(--muted);}
        .op-detail.highlight{font-weight:600;color:var(--brand);}

        /* Wellbore */
        .wellbore-controls{display:flex;gap:16px;align-items:center;flex-wrap:wrap;margin-bottom:12px;}
        .slider-container{flex:1;display:flex;gap:8px;align-items:center;}
        .slider-container input[type=range]{flex:1;}
        .slider-container button{padding:2px 10px;border-radius:4px;border:1px solid var(--border);background:var(--card);cursor:pointer;}
        .playback-controls{display:flex;gap:8px;}
        .playback-controls button,.playback-controls select{padding:4px 12px;border-radius:6px;border:1px solid var(--border);background:var(--card);cursor:pointer;}
        .wellbore-display{display:flex;flex-direction:column;align-items:center;}
        .wellbore-display canvas{max-width:200px;}
        .op-activity-label{font-size:0.95em;font-weight:600;color:var(--brand);padding:4px 14px;margin-bottom:6px;border-radius:6px;background:rgba(37,99,235,0.08);text-align:center;min-height:1.4em;}
        .step-info{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:4px 16px;margin-top:12px;padding:8px;background:#fafafa;border-radius:8px;font-size:0.85em;}
        .info-row{display:flex;gap:6px;} .info-row span:first-child{color:var(--muted);}

        /* Charts */
        .chart-tabs{display:flex;gap:4px;margin-bottom:12px;}
        .chart-tab{padding:6px 16px;border:1px solid var(--border);border-radius:6px;background:var(--card);cursor:pointer;font-size:0.9em;}
        .chart-tab.active{background:var(--brand);color:#fff;border-color:var(--brand);}
        .chart-container{position:relative;width:100%;height:300px;}
        .chart-container canvas{width:100%;height:100%;}
        .chart-value-label{font-size:0.85em;color:var(--muted);padding:6px 0;display:flex;gap:16px;flex-wrap:wrap;justify-content:center;}
        .chart-value-label span{font-weight:500;color:var(--text);}

        /* Tables */
        .table-controls{display:flex;gap:8px;margin-bottom:8px;}
        .table-controls input{flex:1;padding:6px 10px;border:1px solid var(--border);border-radius:6px;}
        .table-controls button{padding:6px 14px;border-radius:6px;border:1px solid var(--border);background:var(--card);cursor:pointer;}
        .table-wrapper{overflow-x:auto;max-height:500px;overflow-y:auto;}
        table{width:100%;border-collapse:collapse;font-size:0.85em;}
        th,td{padding:6px 10px;text-align:left;border-bottom:1px solid var(--border);}
        th{background:#fafafa;cursor:pointer;user-select:none;font-weight:600;position:sticky;top:0;z-index:1;}
        tr:hover{background:#f0f0f0;}
        .clickable-row{cursor:pointer;} .clickable-row:hover{background:#e3f2fd !important;}
        .clickable-row.selected{background:#bbdefb !important;}
        .delta-up{color:#c62828;font-weight:600;} .delta-down{color:#2e7d32;font-weight:600;}
        .color-swatch{width:20px;height:14px;border-radius:3px;border:1px solid rgba(0,0,0,0.15);display:inline-block;}

        footer{text-align:center;padding:16px;color:var(--muted);font-size:0.8em;}
        @media print{header{-webkit-print-color-adjust:exact;print-color-adjust:exact;}.card{break-inside:avoid;box-shadow:none;border:1px solid var(--border);}.playback-controls,.table-controls,.tab-bar{display:none;}.tab-content{display:block !important;}}
        """
    }

    // MARK: - JavaScript

    private func generateJavaScript(_ data: SuperSimReportData) -> String {
        let maxDepth = computeMaxDepth(data)

        // Build boundaries for summary chart
        var boundaries: [(index: Int, label: String)] = []
        var bIdx = 0
        for op in data.operations {
            boundaries.append((index: bIdx, label: "\(op.index + 1). \(op.type.rawValue)"))
            bIdx += op.stepCount
        }
        let boundariesJSON = "[" + boundaries.map { "{\"i\":\($0.index),\"l\":\"\(escJSON($0.label))\"}" }.joined(separator: ",") + "]"

        // Per-operation step data JSON
        var opDataEntries: [String] = []
        for op in data.operations {
            opDataEntries.append("\"\(op.index)\": { type: \"\(escJSON(op.type.rawValue))\", steps: \(opStepsJSON(op)) }")
        }

        return """
        const gSteps = \(timelineStepsJSON(data.timelineSteps));
        const maxDepth = \(String(format: "%.1f", maxDepth));
        const boundaries = \(boundariesJSON);
        const opData = { \(opDataEntries.joined(separator: ", ")) };
        const controlTVD = \(String(format: "%.2f", data.controlTVD_m));

        // --- Tab Navigation ---
        function showTab(id) {
            document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
            document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
            const el = document.getElementById('tab-' + id);
            if (el) el.classList.add('active');
            // Find matching tab button
            document.querySelectorAll('.tab').forEach(t => {
                if ((id === 'summary' && t.textContent === 'Summary') ||
                    t.getAttribute('onclick')?.includes("'" + id + "'"))
                    t.classList.add('active');
            });
            // Redraw charts if summary
            if (id === 'summary') { setTimeout(() => { initCharts(); globalUpdate(); }, 50); }
            // Init op wellbore
            if (id.startsWith('op')) { setTimeout(() => opUpdate(id), 50); }
        }

        // --- Global Wellbore (Summary) ---
        let gIdx = 0, gPlaying = false, gInterval = null;

        const gSlider = document.getElementById('global-slider');
        if (gSlider) gSlider.addEventListener('input', function() { gIdx = parseInt(this.value); globalUpdate(); });

        function globalUpdate() {
            const s = gSteps[gIdx]; if (!s) return;
            const lbl = document.getElementById('global-step-label');
            if (lbl) lbl.textContent = 'Step ' + s.gi + ' (' + s.ol + ')';
            setText('gi-op', s.ol);
            setText('gi-md', s.md.toFixed(0) + ' m (TVD: ' + s.tvd.toFixed(0) + ' m)');
            setText('gi-esd', s.esd.toFixed(1) + ' kg/m\\u00B3');
            setText('gi-sabp-s', s.ss.toFixed(0) + ' kPa');
            setText('gi-sabp-d', s.sd.toFixed(0) + ' kPa');
            const gLabel = document.getElementById('global-op-label');
            if (gLabel) {
                const activityText = s.ot === 'Trip Out' ? '\\u25B2 Tripping Out' : s.ot === 'Trip In' ? '\\u25BC Tripping In' : '\\u27F3 Circulating';
                gLabel.textContent = activityText + ' \\u2014 ' + s.ol;
            }
            drawWellbore('g-well', s.la, s.ls || [], s.lp || [], s.md);
            drawChartMarker();
        }
        function globalTogglePlay() {
            if (gPlaying) { clearInterval(gInterval); gPlaying = false; setText('global-play-btn', '\\u25B6 Play'); }
            else {
                gPlaying = true; setText('global-play-btn', '\\u23F8 Pause');
                const spd = parseInt(document.getElementById('global-speed')?.value || 200);
                gInterval = setInterval(() => {
                    if (gIdx < gSteps.length - 1) { gIdx++; if (gSlider) gSlider.value = gIdx; globalUpdate(); }
                    else { clearInterval(gInterval); gPlaying = false; setText('global-play-btn', '\\u25B6 Play'); }
                }, spd);
            }
        }
        function globalReset() { if (gPlaying) { clearInterval(gInterval); gPlaying = false; setText('global-play-btn', '\\u25B6 Play'); } gIdx = 0; if (gSlider) gSlider.value = 0; globalUpdate(); }

        // --- Per-Operation Wellbore ---
        const opState = {};
        function getOpState(id) {
            if (!opState[id]) opState[id] = { idx: 0, playing: false, interval: null };
            return opState[id];
        }
        function opUpdate(id) {
            const oi = parseInt(id.replace('op', ''));
            const od = opData[oi]; if (!od) return;
            const st = getOpState(id);
            const s = od.steps[st.idx]; if (!s) return;
            const lbl = document.getElementById(id + '-step-label');
            if (lbl) lbl.textContent = 'Step ' + (st.idx + 1) + ' / ' + od.steps.length;

            // Draw wellbore
            drawWellbore(id + '-well', s.la || [], s.ls || [], s.lp || [], s.md || 0);

            // Step info
            const info = document.getElementById(id + '-info');
            if (info) {
                let html = '';
                if (od.type === 'Trip Out') {
                    html = infoRow('Bit MD', s.md.toFixed(0) + ' m') + infoRow('Bit TVD', s.tvd.toFixed(0) + ' m') +
                           infoRow('ESD', s.esd.toFixed(1) + ' kg/m\\u00B3') +
                           infoRow('Static SABP', s.ss.toFixed(0) + ' kPa') + infoRow('Dynamic SABP', s.sd.toFixed(0) + ' kPa') +
                           infoRow('Float', s.fs) + infoRow('Tank \\u0394', s.td.toFixed(2) + ' m\\u00B3');
                } else if (od.type === 'Trip In') {
                    html = infoRow('Bit MD', s.md.toFixed(0) + ' m') + infoRow('Bit TVD', s.tvd.toFixed(0) + ' m') +
                           infoRow('ESD', s.esd.toFixed(1) + ' kg/m\\u00B3') +
                           infoRow('Choke', s.choke.toFixed(0) + ' kPa') +
                           infoRow('HP Ann@Bit', s.hpA.toFixed(0) + ' kPa') + infoRow('HP Str@Bit', s.hpS.toFixed(0) + ' kPa') +
                           infoRow('\\u0394P@Float', s.dp.toFixed(0) + ' kPa') + infoRow('Float', s.fs);
                } else {
                    html = infoRow('Vol Pumped', s.vol.toFixed(2) + ' m\\u00B3') +
                           infoRow('ESD', s.esd.toFixed(1) + ' kg/m\\u00B3') +
                           infoRow('Choke', s.bp.toFixed(0) + ' kPa') +
                           infoRow('\\u0394BP', s.dbp.toFixed(0) + ' kPa') +
                           infoRow('Pump Rate', s.pr.toFixed(2) + ' m\\u00B3/min') +
                           infoRow('APL', s.apl.toFixed(0) + ' kPa') +
                           infoRow('Action', s.desc);
                }
                info.innerHTML = html;
            }

            // Highlight table row
            document.querySelectorAll('#' + id + '-table .clickable-row').forEach((r, i) => {
                r.classList.toggle('selected', i === st.idx);
            });
        }
        function opGoToStep(id, idx) {
            const st = getOpState(id); st.idx = idx;
            const slider = document.getElementById(id + '-slider');
            if (slider) slider.value = idx;
            opUpdate(id);
        }
        function opStepPrev(id) { const st = getOpState(id); if (st.idx > 0) { st.idx--; document.getElementById(id+'-slider').value = st.idx; opUpdate(id); } }
        function opStepNext(id) {
            const oi = parseInt(id.replace('op','')); const od = opData[oi]; if (!od) return;
            const st = getOpState(id);
            if (st.idx < od.steps.length - 1) { st.idx++; document.getElementById(id+'-slider').value = st.idx; opUpdate(id); }
        }
        function opTogglePlay(id) {
            const st = getOpState(id); const oi = parseInt(id.replace('op','')); const od = opData[oi];
            if (st.playing) { clearInterval(st.interval); st.playing = false; setText(id+'-play-btn','\\u25B6 Play'); }
            else {
                st.playing = true; setText(id+'-play-btn','\\u23F8 Pause');
                const spd = parseInt(document.getElementById(id+'-speed')?.value || 200);
                st.interval = setInterval(() => {
                    if (st.idx < od.steps.length - 1) { st.idx++; document.getElementById(id+'-slider').value = st.idx; opUpdate(id); }
                    else { clearInterval(st.interval); st.playing = false; setText(id+'-play-btn','\\u25B6 Play'); }
                }, spd);
            }
        }

        // Slider listeners for each op
        document.querySelectorAll('[id$="-slider"]').forEach(sl => {
            if (sl.id === 'global-slider') return;
            const id = sl.id.replace('-slider', '');
            sl.addEventListener('input', function() { getOpState(id).idx = parseInt(this.value); opUpdate(id); });
        });

        // --- Wellbore Drawing ---
        function drawWellbore(canvasId, annLayers, strLayers, pocketLayers, bitMD) {
            const c = document.getElementById(canvasId); if (!c) return;
            const ctx = c.getContext('2d');
            ctx.clearRect(0, 0, c.width, c.height);
            const h = c.height, w = c.width;
            const pipeRatio = 0.35;
            const pipeW = w * pipeRatio;
            const pipeX = (w - pipeW) / 2;
            const yBit = (bitMD / maxDepth) * h;

            // 1. Annulus layers (left + right strips, above bit)
            for (const l of annLayers) {
                const y1 = (l.t / maxDepth) * h;
                const y2 = (l.b / maxDepth) * h;
                const ly = Math.floor(y1), lh = Math.max(1, Math.ceil(y2 - y1));
                ctx.fillStyle = l.c || '#999';
                ctx.fillRect(0, ly, pipeX, lh);
                ctx.fillRect(pipeX + pipeW, ly, w - pipeX - pipeW, lh);
            }

            // 2. String layers (center pipe, above bit)
            for (const l of strLayers) {
                const y1 = (l.t / maxDepth) * h;
                const y2 = (Math.min(l.b, bitMD) / maxDepth) * h;
                const ly = Math.floor(y1), lh = Math.max(1, Math.ceil(y2 - y1));
                ctx.fillStyle = l.c || '#999';
                ctx.fillRect(pipeX, ly, pipeW, lh);
            }

            // 3. Pocket layers (full width below bit — open hole)
            for (const l of pocketLayers) {
                const y1 = (l.t / maxDepth) * h;
                const y2 = (l.b / maxDepth) * h;
                const ly = Math.floor(y1), lh = Math.max(1, Math.ceil(y2 - y1));
                ctx.fillStyle = l.c || '#999';
                ctx.fillRect(0, ly, w, lh);
            }

            // 4. Pipe walls (surface to bit)
            if (bitMD > 0) {
                ctx.fillStyle = 'rgba(0,0,0,0.5)';
                ctx.fillRect(pipeX - 1, 0, 2, yBit);
                ctx.fillRect(pipeX + pipeW - 1, 0, 2, yBit);
            }

            // 5. Bit marker
            ctx.fillStyle = '#0066cc';
            ctx.fillRect(pipeX - 4, yBit - 1.5, pipeW + 8, 3);

            // 6. Hole outline
            ctx.strokeStyle = 'rgba(0,0,0,0.5)'; ctx.strokeRect(0, 0, w, h);
        }

        // --- Charts (HiDPI) ---
        function initCanvas(id) {
            const c = document.getElementById(id); if (!c) return null;
            const rect = c.parentElement.getBoundingClientRect();
            const dpr = window.devicePixelRatio || 1;
            c.width = rect.width * dpr;
            c.height = rect.height * dpr;
            const ctx = c.getContext('2d');
            ctx.scale(dpr, dpr);
            return { c, ctx, w: rect.width, h: rect.height };
        }

        function drawLineChart(id, getData, yLabel, colors) {
            const cv = initCanvas(id); if (!cv) return;
            const { ctx, w, h } = cv;
            const pad = { l: 65, r: 20, t: 25, b: 30 };
            const pw = w - pad.l - pad.r, ph = h - pad.t - pad.b;

            const allValues = getData(gSteps);
            if (allValues.length === 0 || allValues[0].length === 0) return;
            const flat = allValues.flat().filter(v => isFinite(v));
            const yMin = Math.min(...flat), yMax = Math.max(...flat);
            const yRange = yMax - yMin || 1;

            // Grid
            ctx.strokeStyle = '#e0e0e0'; ctx.lineWidth = 0.5;
            for (let i = 0; i <= 5; i++) {
                const y = pad.t + ph - (i / 5) * ph;
                ctx.beginPath(); ctx.moveTo(pad.l, y); ctx.lineTo(pad.l + pw, y); ctx.stroke();
                ctx.fillStyle = '#666'; ctx.font = '11px sans-serif'; ctx.textAlign = 'right';
                ctx.fillText((yMin + (i / 5) * yRange).toFixed(0), pad.l - 6, y + 4);
            }
            ctx.fillStyle = '#666'; ctx.font = '11px sans-serif';
            ctx.textAlign = 'center'; ctx.fillText('Step', pad.l + pw / 2, h - 4);
            ctx.textAlign = 'left'; ctx.fillText(yLabel, 4, pad.t + 12);

            // Op boundaries
            ctx.strokeStyle = 'rgba(0,0,0,0.08)'; ctx.lineWidth = 1; ctx.setLineDash([4, 3]);
            for (const b of boundaries) {
                const x = pad.l + (b.i / Math.max(1, gSteps.length - 1)) * pw;
                ctx.beginPath(); ctx.moveTo(x, pad.t); ctx.lineTo(x, pad.t + ph); ctx.stroke();
                ctx.fillStyle = '#999'; ctx.font = '10px sans-serif'; ctx.textAlign = 'left';
                ctx.fillText(b.l, x + 3, pad.t + 12);
            }
            ctx.setLineDash([]);

            // Data lines
            for (let si = 0; si < allValues.length; si++) {
                const vals = allValues[si];
                ctx.strokeStyle = colors[si % colors.length];
                ctx.lineWidth = si === 0 ? 2 : 1.5;
                if (si > 0) ctx.setLineDash([6, 3]);
                ctx.beginPath();
                for (let i = 0; i < gSteps.length; i++) {
                    const x = pad.l + (i / Math.max(1, gSteps.length - 1)) * pw;
                    const y = pad.t + ph - ((vals[i] - yMin) / yRange) * ph;
                    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                }
                ctx.stroke(); ctx.setLineDash([]);
            }
        }

        function drawChartMarker() {
            drawESD(); drawSABP();
            const vis = document.getElementById('container-esd').style.display !== 'none' ? 'chart-esd' : 'chart-sabp';
            const cv = initCanvas(vis); if (!cv) return;
            // Redraw then marker
            if (vis === 'chart-esd') drawESD(); else drawSABP();
            const { ctx, w, h } = cv;
            const pad = { l: 65, r: 20, t: 25, b: 30 };
            const pw = w - pad.l - pad.r;
            const x = pad.l + (gIdx / Math.max(1, gSteps.length - 1)) * pw;
            ctx.strokeStyle = 'rgba(0,102,204,0.7)'; ctx.lineWidth = 2;
            ctx.beginPath(); ctx.moveTo(x, pad.t); ctx.lineTo(x, pad.t + h - pad.t - pad.b); ctx.stroke();
            // Update chart value label
            const s = gSteps[gIdx];
            const valEl = document.getElementById('chart-values');
            if (s && valEl) {
                const totalESD = controlTVD > 0 ? s.esd + s.ss / (0.00981 * controlTVD) : s.esd;
                valEl.innerHTML = s.ol + ' \\u2014 ' +
                    'Step <span>' + s.gi + '</span> \\u2022 ' +
                    'MD <span>' + s.md.toFixed(0) + ' m</span> \\u2022 ' +
                    'ESD <span>' + s.esd.toFixed(1) + ' kg/m\\u00B3</span> \\u2022 ' +
                    'ESD+BP <span>' + totalESD.toFixed(1) + ' kg/m\\u00B3</span> \\u2022 ' +
                    'Static SABP <span>' + s.ss.toFixed(0) + ' kPa</span> \\u2022 ' +
                    'Dynamic SABP <span>' + s.sd.toFixed(0) + ' kPa</span>';
            }
        }

        function drawESD() {
            drawLineChart('chart-esd', s => {
                const hydro = s.map(x => x.esd);
                const total = s.map(x => controlTVD > 0 ? x.esd + x.ss / (0.00981 * controlTVD) : x.esd);
                return [hydro, total];
            }, 'ESD (kg/m\\u00B3)', ['#e65100', '#00bcd4']);
        }
        function drawSABP() {
            drawLineChart('chart-sabp', s => [s.map(x => x.ss), s.map(x => x.sd)], 'SABP (kPa)', ['#d32f2f', '#ef9a9a']);
        }

        function initCharts() { drawESD(); drawSABP(); }
        function showChart(type, btn) {
            document.querySelectorAll('.chart-tab').forEach(t => t.classList.remove('active'));
            if (btn) btn.classList.add('active');
            document.getElementById('container-esd').style.display = type === 'esd' ? '' : 'none';
            document.getElementById('container-sabp').style.display = type === 'sabp' ? '' : 'none';
            drawChartMarker();
        }

        // --- Table Utils ---
        let sortDirs = {};
        function sortOpTable(opId, col) {
            const key = opId + '-' + col;
            sortDirs[key] = !sortDirs[key];
            const tbody = document.querySelector('#' + opId + '-table tbody');
            const rows = Array.from(tbody.querySelectorAll('tr'));
            rows.sort((a, b) => {
                const va = a.cells[col].textContent, vb = b.cells[col].textContent;
                const na = parseFloat(va), nb = parseFloat(vb);
                const cmp = isNaN(na) ? va.localeCompare(vb) : na - nb;
                return sortDirs[key] ? cmp : -cmp;
            });
            rows.forEach(r => tbody.appendChild(r));
        }
        function filterOpTable(opId) {
            const q = document.getElementById(opId + '-search').value.toLowerCase();
            document.querySelectorAll('#' + opId + '-table tbody tr').forEach(r => {
                r.style.display = r.textContent.toLowerCase().includes(q) ? '' : 'none';
            });
        }
        function exportOpCSV(opId) {
            const table = document.getElementById(opId + '-table');
            const rows = Array.from(table.querySelectorAll('tr'));
            const csv = rows.map(r => Array.from(r.querySelectorAll('th, td')).map(c => '"' + c.textContent.replace(/"/g, '""') + '"').join(',')).join('\\n');
            const blob = new Blob([csv], {type: 'text/csv'});
            const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = opId + '_data.csv'; a.click();
        }

        // --- Helpers ---
        function setText(id, text) { const el = document.getElementById(id); if (el) el.textContent = text; }
        function infoRow(label, value) { return '<div class="info-row"><span>' + label + ':</span> <span>' + value + '</span></div>'; }

        // --- Init ---
        initCharts();
        globalUpdate();
        """
    }
}
