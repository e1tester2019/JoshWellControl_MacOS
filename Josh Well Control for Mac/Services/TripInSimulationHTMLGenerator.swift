//
//  TripInSimulationHTMLGenerator.swift
//  Josh Well Control for Mac
//
//  Interactive HTML report generator for Trip-In Simulation
//

import Foundation

/// Report data for Trip-In simulation
struct TripInSimulationReportData {
    let wellName: String
    let projectName: String
    let generatedDate: Date

    // Simulation parameters
    let startMD: Double
    let endMD: Double
    let controlMD: Double
    let stepSize: Double
    let targetESD: Double

    // String configuration
    let stringName: String
    let pipeOD_m: Double
    let pipeID_m: Double

    // Floated casing
    let isFloatedCasing: Bool
    let floatSubMD: Double
    let crackFloat: Double

    // Fluids
    let fillMudName: String
    let fillMudDensity: Double
    let baseMudDensity: Double

    // Fill mud color (optional - defaults to density-based color if not provided)
    let fillMudColorR: Double?
    let fillMudColorG: Double?
    let fillMudColorB: Double?

    // Source
    let sourceName: String

    // Geometry data
    let annulusSections: [PDFSectionData]

    // Results
    let steps: [TripInSimulationViewModel.TripInStep]

    // Computed metrics
    var minESD: Double { steps.map { $0.ESDAtControl_kgpm3 }.min() ?? 0 }
    var maxESD: Double { steps.map { $0.ESDAtControl_kgpm3 }.max() ?? 0 }
    var maxChokePressure: Double { steps.map { $0.requiredChokePressure_kPa }.max() ?? 0 }
    var maxDifferentialPressure: Double { steps.map { $0.differentialPressureAtBottom_kPa }.max() ?? 0 }
    var totalFillVolume: Double { steps.last?.cumulativeFillVolume_m3 ?? 0 }
    var totalDisplacementReturns: Double { steps.last?.cumulativeDisplacementReturns_m3 ?? 0 }
    var depthBelowTarget: Double? { steps.first(where: { $0.isBelowTarget })?.bitMD_m }
}

/// Cross-platform HTML generator for trip-in simulation reports
class TripInSimulationHTMLGenerator {
    static let shared = TripInSimulationHTMLGenerator()

    private init() {}

    func generateHTML(for data: TripInSimulationReportData) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy, HH:mm"
        let dateStr = dateFormatter.string(from: data.generatedDate)

        // Convert steps to JSON for JavaScript
        let stepsJSON = stepsToJSON(data.steps)

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Trip-In Simulation Report - \(escapeHTML(data.wellName))</title>
            <style>
                \(generateCSS())
            </style>
        </head>
        <body>
            <header>
                <div class="header-content">
                    <h1>Trip-In Simulation Report</h1>
                    <span class="well-name">\(escapeHTML(data.wellName))</span>
                </div>
            </header>

            <main>
                <!-- Well Information -->
                <section class="card">
                    <h2>Well Information</h2>
                    <div class="info-grid">
                        <div class="info-item">
                            <span class="label">Well:</span>
                            <span class="value">\(escapeHTML(data.wellName))</span>
                        </div>
                        <div class="info-item">
                            <span class="label">Project:</span>
                            <span class="value">\(escapeHTML(data.projectName))</span>
                        </div>
                        <div class="info-item">
                            <span class="label">Date:</span>
                            <span class="value">\(dateStr)</span>
                        </div>
                        <div class="info-item">
                            <span class="label">Trip:</span>
                            <span class="value">RIH (Run In Hole)</span>
                        </div>
                        <div class="info-item">
                            <span class="label">Source:</span>
                            <span class="value">\(escapeHTML(data.sourceName))</span>
                        </div>
                    </div>
                </section>

                <!-- Simulation Parameters -->
                <section class="card">
                    <h2>Simulation Parameters</h2>
                    <div class="params-grid">
                        <div class="param-item">
                            <span class="label">Start MD:</span>
                            <span class="value">\(String(format: "%.0f m", data.startMD))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">End MD (TD):</span>
                            <span class="value">\(String(format: "%.0f m", data.endMD))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Control MD:</span>
                            <span class="value">\(String(format: "%.0f m", data.controlMD))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Step Size:</span>
                            <span class="value">\(String(format: "%.0f m", data.stepSize))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Target ESD:</span>
                            <span class="value">\(String(format: "%.0f kg/m³", data.targetESD))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Fill Mud:</span>
                            <span class="value">\(escapeHTML(data.fillMudName)) (\(String(format: "%.0f kg/m³", data.fillMudDensity)))</span>
                        </div>
                    </div>
                    <h3>String Configuration</h3>
                    <div class="params-grid">
                        <div class="param-item">
                            <span class="label">String:</span>
                            <span class="value">\(escapeHTML(data.stringName))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Pipe OD:</span>
                            <span class="value">\(String(format: "%.1f mm", data.pipeOD_m * 1000))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Pipe ID:</span>
                            <span class="value">\(String(format: "%.1f mm", data.pipeID_m * 1000))</span>
                        </div>
                        \(data.isFloatedCasing ? """
                        <div class="param-item">
                            <span class="label">Float Sub MD:</span>
                            <span class="value">\(String(format: "%.0f m", data.floatSubMD))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Crack Float:</span>
                            <span class="value">\(String(format: "%.0f kPa", data.crackFloat))</span>
                        </div>
                        """ : "")
                    </div>
                </section>

                <!-- Safety Summary -->
                <section class="card">
                    <h2>Safety Summary</h2>
                    <div class="metrics-grid">
                        <div class="metric-box \(data.minESD < data.targetESD ? "warning" : "")">
                            <div class="metric-title">Min ESD @ Control</div>
                            <div class="metric-value">\(String(format: "%.0f", data.minESD))</div>
                            <div class="metric-unit">kg/m³</div>
                        </div>
                        <div class="metric-box">
                            <div class="metric-title">Max ESD @ Control</div>
                            <div class="metric-value">\(String(format: "%.0f", data.maxESD))</div>
                            <div class="metric-unit">kg/m³</div>
                        </div>
                        <div class="metric-box \(data.maxChokePressure > 0 ? "warning" : "")">
                            <div class="metric-title">Max Choke Required</div>
                            <div class="metric-value">\(String(format: "%.0f", data.maxChokePressure))</div>
                            <div class="metric-unit">kPa</div>
                        </div>
                        <div class="metric-box">
                            <div class="metric-title">Max ΔP @ Bit</div>
                            <div class="metric-value">\(String(format: "%.0f", data.maxDifferentialPressure))</div>
                            <div class="metric-unit">kPa</div>
                        </div>
                    </div>
                    <div class="metrics-grid secondary">
                        <div class="metric-box small">
                            <div class="metric-title">Total Fill Volume</div>
                            <div class="metric-value">\(String(format: "%.2f m³", data.totalFillVolume))</div>
                        </div>
                        <div class="metric-box small">
                            <div class="metric-title">Total Displacement</div>
                            <div class="metric-value">\(String(format: "%.2f m³", data.totalDisplacementReturns))</div>
                        </div>
                        <div class="metric-box small \(data.depthBelowTarget != nil ? "danger" : "")">
                            <div class="metric-title">Below Target From</div>
                            <div class="metric-value">\(data.depthBelowTarget != nil ? String(format: "%.0f m", data.depthBelowTarget!) : "N/A")</div>
                        </div>
                    </div>
                </section>

                <!-- Interactive Wellbore Visualization -->
                <section class="card">
                    <h2>Interactive Well Snapshot</h2>
                    <div class="wellbore-controls">
                        <div class="slider-container">
                            <label for="depth-slider">Trip Progress:</label>
                            <input type="range" id="depth-slider" min="0" max="\(data.steps.count - 1)" value="0">
                            <span id="current-depth">--</span>
                        </div>
                        <div class="playback-controls">
                            <button id="play-btn" onclick="togglePlayback()">▶ Play</button>
                            <button onclick="resetPlayback()">⟲ Reset</button>
                            <select id="speed-select">
                                <option value="500">Slow</option>
                                <option value="200" selected>Normal</option>
                                <option value="50">Fast</option>
                            </select>
                        </div>
                    </div>
                    <div class="wellbore-display">
                        <canvas id="pocket-canvas" width="280" height="400"></canvas>
                    </div>
                    <div class="step-info" id="step-info">
                        <div class="info-row"><span>Bit MD:</span> <span id="info-md">--</span></div>
                        <div class="info-row"><span>Bit TVD:</span> <span id="info-tvd">--</span></div>
                        <div class="info-row"><span>ESD @ Control:</span> <span id="info-esd">--</span></div>
                        <div class="info-row"><span>Choke:</span> <span id="info-choke">--</span></div>
                        <div class="info-row"><span>HP Ann @ Bit:</span> <span id="info-hp-ann">--</span></div>
                        <div class="info-row"><span>Ann+Choke:</span> <span id="info-hp-ann-choke">--</span></div>
                        <div class="info-row"><span>HP Str @ Bit:</span> <span id="info-hp-str">--</span></div>
                        <div class="info-row"><span>ΔP @ Float:</span> <span id="info-delta-p">--</span></div>
                        <div class="info-row"><span>Float State:</span> <span id="info-float">--</span></div>
                    </div>
                </section>

                <!-- Charts -->
                <section class="card">
                    <h2>Trip Profile Charts</h2>
                    <p class="chart-hint">Use the slider above to see values at each depth</p>
                    <div class="charts-grid">
                        <div class="chart-container" id="container-esd">
                            <canvas id="chart-esd" width="280" height="180"></canvas>
                            <div class="chart-tooltip" id="tooltip-esd"></div>
                        </div>
                        <div class="chart-container" id="container-choke">
                            <canvas id="chart-choke" width="280" height="180"></canvas>
                            <div class="chart-tooltip" id="tooltip-choke"></div>
                        </div>
                        <div class="chart-container" id="container-hp">
                            <canvas id="chart-hp" width="280" height="180"></canvas>
                            <div class="chart-tooltip" id="tooltip-hp"></div>
                        </div>
                        <div class="chart-container" id="container-fill">
                            <canvas id="chart-fill" width="280" height="180"></canvas>
                            <div class="chart-tooltip" id="tooltip-fill"></div>
                        </div>
                    </div>
                </section>

                <!-- Data Table -->
                <section class="card">
                    <h2>Step-by-Step Data</h2>
                    <div class="table-controls">
                        <input type="text" id="table-search" placeholder="Search..." onkeyup="filterTable()">
                        <button onclick="exportTableCSV()">Export CSV</button>
                    </div>
                    <div class="table-wrapper">
                        <table id="data-table">
                            <thead>
                                <tr>
                                    <th onclick="sortTable(0)">MD (m) ⇅</th>
                                    <th onclick="sortTable(1)">TVD (m) ⇅</th>
                                    <th onclick="sortTable(2)">ESD ⇅</th>
                                    <th onclick="sortTable(3)">Choke ⇅</th>
                                    <th onclick="sortTable(4)">HP Ann@Bit ⇅</th>
                                    <th onclick="sortTable(5)">HP Str@Bit ⇅</th>
                                    <th onclick="sortTable(6)">ΔP@Float ⇅</th>
                                    <th onclick="sortTable(7)">Fill (m³) ⇅</th>
                                    <th onclick="sortTable(8)">Disp (m³) ⇅</th>
                                    <th onclick="sortTable(9)">Float ⇅</th>
                                </tr>
                            </thead>
                            <tbody>
                                \(generateTableRows(data.steps))
                            </tbody>
                        </table>
                    </div>
                    <div class="table-legend">
                        Units: MD/TVD (m), ESD (kg/m³), Choke/HP/ΔP (kPa), Fill/Disp (m³ cumulative)
                    </div>
                </section>
            </main>

            <footer>
                <p>Generated by Josh Well Control • \(dateStr)</p>
            </footer>

            <script>
                // Simulation data
                const steps = \(stepsJSON);
                const maxDepth = \(String(format: "%.1f", data.endMD));
                const maxTVD = steps.length > 0 ? steps[steps.length - 1].bitTVD : maxDepth;
                const pipeOD_m = \(String(format: "%.4f", data.pipeOD_m));
                const pipeID_m = \(String(format: "%.4f", data.pipeID_m));
                const wellboreID_m = 0.2159;  // Approximate 8.5" wellbore
                const fillMudDensity = \(String(format: "%.1f", data.fillMudDensity));
                const fillMudColor = \(data.fillMudColorR != nil ? "\"rgba(\(Int((data.fillMudColorR ?? 0.5) * 255)), \(Int((data.fillMudColorG ?? 0.5) * 255)), \(Int((data.fillMudColorB ?? 0.5) * 255)), 0.9)\"" : "null");
                const isFloatedCasing = \(data.isFloatedCasing ? "true" : "false");
                const floatSubMD = \(String(format: "%.1f", data.floatSubMD));

                // Playback state
                let isPlaying = false;
                let playbackInterval = null;
                let currentStepIndex = 0;

                \(generateJavaScript())
            </script>
        </body>
        </html>
        """
    }

    // MARK: - CSS Generation

    private func generateCSS() -> String {
        return """
        :root {
            --brand-color: #52a5bf;
            --safe-color: #4caf50;
            --warning-color: #ff9800;
            --danger-color: #f44336;
            --bg-color: #f5f5f5;
            --card-bg: #ffffff;
            --text-color: #333333;
            --text-light: #666666;
            --border-color: #e0e0e0;
        }

        * { box-sizing: border-box; margin: 0; padding: 0; }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: var(--bg-color);
            color: var(--text-color);
            line-height: 1.5;
        }

        header {
            background: var(--brand-color);
            color: white;
            padding: 16px 24px;
            position: sticky;
            top: 0;
            z-index: 100;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }

        .header-content {
            max-width: 1200px;
            margin: 0 auto;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        header h1 { font-size: 1.5rem; font-weight: 600; }
        .well-name { opacity: 0.9; font-size: 0.9rem; }

        main { max-width: 1200px; margin: 0 auto; padding: 24px; }

        .card {
            background: var(--card-bg);
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 20px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        }

        .card h2 {
            color: var(--brand-color);
            font-size: 1.1rem;
            margin-bottom: 16px;
            padding-bottom: 8px;
            border-bottom: 1px solid var(--border-color);
        }

        .card h3 {
            color: var(--text-color);
            font-size: 0.95rem;
            margin: 16px 0 12px 0;
        }

        .info-grid, .params-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 12px;
        }

        .info-item, .param-item { display: flex; gap: 8px; }
        .label { color: var(--text-light); font-size: 0.85rem; }
        .value { font-weight: 500; }

        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
            gap: 12px;
            margin-bottom: 12px;
        }

        .metrics-grid.secondary { grid-template-columns: repeat(3, 1fr); }

        .metric-box {
            background: var(--bg-color);
            border-radius: 6px;
            padding: 12px;
            text-align: center;
        }

        .metric-box.small { padding: 10px; }
        .metric-box.warning .metric-value { color: var(--warning-color); }
        .metric-box.danger .metric-value { color: var(--danger-color); }

        .metric-title { font-size: 0.75rem; color: var(--text-light); margin-bottom: 4px; }
        .metric-value { font-size: 1.3rem; font-weight: 700; color: var(--safe-color); }
        .metric-box.small .metric-value { font-size: 1.1rem; }
        .metric-unit { font-size: 0.7rem; color: var(--text-light); }

        .wellbore-controls {
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
            gap: 12px;
            margin-bottom: 16px;
            padding: 12px;
            background: var(--bg-color);
            border-radius: 6px;
        }

        .slider-container { display: flex; align-items: center; gap: 12px; flex: 1; }
        .slider-container input[type="range"] { flex: 1; min-width: 200px; }
        #current-depth { font-weight: 600; min-width: 80px; }

        .playback-controls { display: flex; gap: 8px; }
        .playback-controls button, .playback-controls select {
            padding: 6px 12px;
            border: 1px solid var(--border-color);
            border-radius: 4px;
            background: white;
            cursor: pointer;
            font-size: 0.85rem;
        }
        .playback-controls button:hover { background: var(--bg-color); }

        .wellbore-display {
            display: flex;
            justify-content: center;
            padding: 20px;
            background: #1a1a1a;
            border-radius: 6px;
        }

        .step-info {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 8px;
            margin-top: 16px;
            padding: 12px;
            background: var(--bg-color);
            border-radius: 6px;
        }

        .info-row { display: flex; justify-content: space-between; font-size: 0.85rem; }
        .info-row span:first-child { color: var(--text-light); }
        .info-row span:last-child { font-weight: 600; }

        .charts-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 16px; }
        @media (max-width: 768px) { .charts-grid { grid-template-columns: 1fr; } }

        .chart-container {
            background: var(--bg-color);
            border-radius: 6px;
            padding: 12px;
            height: 250px;
            position: relative;
        }
        .chart-container canvas { width: 100% !important; height: 100% !important; }

        .chart-tooltip {
            position: absolute;
            background: rgba(0, 0, 0, 0.85);
            color: white;
            padding: 8px 12px;
            border-radius: 4px;
            font-size: 0.75rem;
            pointer-events: none;
            opacity: 0;
            transition: opacity 0.15s;
            z-index: 100;
            white-space: nowrap;
        }
        .chart-tooltip.visible { opacity: 1; }
        .chart-hint { font-size: 0.75rem; color: var(--text-light); margin-bottom: 12px; font-style: italic; }

        .table-controls { display: flex; gap: 12px; margin-bottom: 12px; }
        .table-controls input { flex: 1; padding: 8px 12px; border: 1px solid var(--border-color); border-radius: 4px; }
        .table-controls button {
            padding: 8px 16px;
            background: var(--brand-color);
            color: white;
            border: none;
            border-radius: 4px;
            cursor: pointer;
        }

        .table-wrapper { overflow-x: auto; max-height: 500px; overflow-y: auto; }
        table { width: 100%; border-collapse: collapse; font-size: 0.8rem; }
        thead { position: sticky; top: 0; z-index: 10; }
        th {
            background: var(--brand-color);
            color: white;
            padding: 10px 8px;
            text-align: right;
            cursor: pointer;
            white-space: nowrap;
        }
        th:hover { background: #4795ab; }
        td { padding: 8px; text-align: right; border-bottom: 1px solid var(--border-color); }
        tr:nth-child(even) { background: var(--bg-color); }
        tr:hover { background: #e3f2fd; }
        tr.highlight { background: #bbdefb !important; }
        .table-legend { margin-top: 8px; font-size: 0.7rem; color: var(--text-light); }

        footer { text-align: center; padding: 20px; color: var(--text-light); font-size: 0.8rem; }

        @media print {
            header { position: static; }
            .wellbore-controls, .playback-controls, .table-controls { display: none; }
            .card { break-inside: avoid; }
        }
        """
    }

    // MARK: - JavaScript Generation

    private func generateJavaScript() -> String {
        return """
        document.addEventListener('DOMContentLoaded', function() {
            initSlider();
            requestAnimationFrame(function() {
                initCharts();
                updateWellbore(0);
                updateChartMarker(0);
            });
        });

        function initSlider() {
            const slider = document.getElementById('depth-slider');
            slider.addEventListener('input', function() {
                currentStepIndex = parseInt(this.value);
                updateWellbore(currentStepIndex);
                updateChartMarker(currentStepIndex);
                highlightTableRow(currentStepIndex);
            });
        }

        function updateWellbore(index) {
            if (index < 0 || index >= steps.length) return;
            const step = steps[index];

            document.getElementById('current-depth').textContent = step.bitMD.toFixed(0) + ' m';
            document.getElementById('info-md').textContent = step.bitMD.toFixed(0) + ' m';
            document.getElementById('info-tvd').textContent = step.bitTVD.toFixed(0) + ' m';
            document.getElementById('info-esd').textContent = step.esd.toFixed(0) + ' kg/m³';
            document.getElementById('info-choke').textContent = step.choke.toFixed(0) + ' kPa';
            document.getElementById('info-hp-ann').textContent = step.hpAnn.toFixed(0) + ' kPa';
            document.getElementById('info-hp-ann-choke').textContent = (step.hpAnn + step.choke).toFixed(0) + ' kPa';
            document.getElementById('info-hp-str').textContent = step.hpStr.toFixed(0) + ' kPa';
            // True ΔP at float = (Ann HP + Choke) - String HP
            const trueDeltaP = (step.hpAnn + step.choke) - step.hpStr;
            document.getElementById('info-delta-p').textContent = trueDeltaP.toFixed(0) + ' kPa';
            document.getElementById('info-float').textContent = step.floatState;

            drawPocketCanvas(step);
        }

        function drawPocketCanvas(step) {
            const canvas = document.getElementById('pocket-canvas');
            if (!canvas) return;
            const ctx = canvas.getContext('2d');
            const w = canvas.width;
            const h = canvas.height;

            ctx.clearRect(0, 0, w, h);
            ctx.fillStyle = '#2a2a2a';
            ctx.fillRect(0, 0, w, h);

            // Layout: TVD on left (40px), wellbore (rest), MD on right (40px)
            const leftMargin = 45;
            const rightMargin = 40;
            const wellboreWidth = w - leftMargin - rightMargin;
            const wellboreX = leftMargin;

            const bitY = (step.bitMD / maxDepth) * h;

            // Consolidate adjacent layers with same color to avoid artifacts
            const consolidatedLayers = [];
            step.layersPocket.forEach(layer => {
                const color = layer.color || densityToColor(layer.rho);
                if (consolidatedLayers.length > 0) {
                    const last = consolidatedLayers[consolidatedLayers.length - 1];
                    // Check if adjacent and same color (within small tolerance for MD gap)
                    if (Math.abs(last.bottomMD - layer.topMD) < 1.0 && last.color === color) {
                        // Merge: extend last layer's bottom
                        last.bottomMD = layer.bottomMD;
                        return;
                    }
                }
                consolidatedLayers.push({
                    topMD: layer.topMD,
                    bottomMD: layer.bottomMD,
                    color: color
                });
            });

            // Draw consolidated pocket layers (annulus fluid)
            consolidatedLayers.forEach(layer => {
                const y1 = (layer.topMD / maxDepth) * h;
                const y2 = (layer.bottomMD / maxDepth) * h;
                const layerH = Math.max(1, y2 - y1);
                ctx.fillStyle = layer.color;
                ctx.fillRect(wellboreX, y1, wellboreWidth, layerH);
            });

            // Draw drill string overlay from surface to bit depth
            // Calculate relative pipe widths (OD for outer, ID for inner fluid)
            const pipeODRatio = pipeOD_m / wellboreID_m;
            const pipeIDRatio = pipeID_m / wellboreID_m;
            const pipeODWidth = wellboreWidth * pipeODRatio;
            const pipeIDWidth = wellboreWidth * pipeIDRatio;
            const pipeX = wellboreX + (wellboreWidth - pipeODWidth) / 2;
            const pipeInnerX = wellboreX + (wellboreWidth - pipeIDWidth) / 2;
            const wallThickness = (pipeODWidth - pipeIDWidth) / 2;

            // Draw pipe wall (dark gray steel)
            ctx.fillStyle = 'rgba(70, 70, 75, 0.95)';
            ctx.fillRect(pipeX, 0, pipeODWidth, bitY);

            // Draw mud inside the string
            // For floated casing: mud from surface to fill level, air below
            // For non-floated: full mud column
            const pipeCapacity = Math.PI / 4 * pipeID_m * pipeID_m;  // m³/m
            const mudHeightM = step.cumFill / pipeCapacity;  // meters of mud
            const fillLevelMD = Math.min(mudHeightM, step.bitMD);
            const fillY = (fillLevelMD / maxDepth) * h;

            // Use fill mud color if available, otherwise use density-based color
            const mudColor = fillMudColor || densityToColor(fillMudDensity);
            ctx.fillStyle = mudColor;
            ctx.fillRect(pipeInnerX, 0, pipeIDWidth, fillY);

            // If floated casing and fill level < bit depth, show air section (light blue)
            if (isFloatedCasing && fillY < bitY) {
                ctx.fillStyle = 'rgba(180, 220, 255, 0.6)';  // Light blue for air
                ctx.fillRect(pipeInnerX, fillY, pipeIDWidth, bitY - fillY);
            }

            // Pipe outline
            ctx.strokeStyle = '#888';
            ctx.lineWidth = 1;
            ctx.strokeRect(pipeX, 0, pipeODWidth, bitY);

            // Draw bit indicator at bottom of pipe
            ctx.fillStyle = '#e05040';
            ctx.fillRect(pipeX - 3, bitY - 3, pipeODWidth + 6, 6);

            // Draw TVD scale on left (use actual TVD from deepest step)
            ctx.font = '9px -apple-system, sans-serif';
            ctx.textAlign = 'right';
            ctx.fillStyle = '#00bcd4';  // Cyan for TVD
            for (let i = 0; i <= 5; i++) {
                const tvd = (i / 5) * maxTVD;
                const y = (i / 5) * h;
                if (i === 0) {
                    ctx.fillText('TVD', leftMargin - 5, y + 12);
                } else {
                    ctx.fillText(tvd.toFixed(0), leftMargin - 5, y + 4);
                }
            }

            // Draw MD scale on right
            ctx.fillStyle = '#ff9800';  // Orange for MD
            ctx.textAlign = 'left';
            for (let i = 0; i <= 5; i++) {
                const depth = (i / 5) * maxDepth;
                const y = (i / 5) * h;
                if (i === 0) {
                    ctx.fillText('MD', wellboreX + wellboreWidth + 5, y + 12);
                } else {
                    ctx.fillText(depth.toFixed(0), wellboreX + wellboreWidth + 5, y + 4);
                }
            }

            // Draw bit depth label
            ctx.fillStyle = '#e05040';
            ctx.font = '10px -apple-system, sans-serif';
            ctx.textAlign = 'left';
            ctx.fillText('Bit: ' + step.bitMD.toFixed(0) + 'm', wellboreX + wellboreWidth + 5, bitY + 4);
        }

        function densityToColor(rho) {
            if (rho < 10) return 'rgba(180, 215, 255, 0.8)';
            const t = Math.min(Math.max((rho - 800) / 1200, 0), 1);
            const v = Math.round(80 + 150 * (1 - t));
            return `rgb(${v}, ${v}, ${v})`;
        }

        function togglePlayback() {
            const btn = document.getElementById('play-btn');
            if (isPlaying) {
                clearInterval(playbackInterval);
                btn.textContent = '▶ Play';
                isPlaying = false;
            } else {
                const speed = parseInt(document.getElementById('speed-select').value);
                playbackInterval = setInterval(() => {
                    currentStepIndex++;
                    if (currentStepIndex >= steps.length) currentStepIndex = 0;
                    document.getElementById('depth-slider').value = currentStepIndex;
                    updateWellbore(currentStepIndex);
                    updateChartMarker(currentStepIndex);
                    highlightTableRow(currentStepIndex);
                }, speed);
                btn.textContent = '⏸ Pause';
                isPlaying = true;
            }
        }

        function resetPlayback() {
            if (isPlaying) togglePlayback();
            currentStepIndex = 0;
            document.getElementById('depth-slider').value = 0;
            updateWellbore(0);
            updateChartMarker(0);
            highlightTableRow(0);
        }

        let charts = {};

        function initCharts() {
            const depths = steps.map(s => s.bitMD);
            charts.esd = createChart('chart-esd', 'ESD @ Control vs Depth', depths, [
                { data: steps.map(s => s.esd), label: 'ESD (kg/m³)', color: '#2196f3' }
            ]);
            charts.choke = createChart('chart-choke', 'Choke Pressure vs Depth', depths, [
                { data: steps.map(s => s.choke), label: 'Choke (kPa)', color: '#ff9800' }
            ]);
            charts.hp = createChart('chart-hp', 'Pressures @ Bit (ΔP at Float)', depths, [
                { data: steps.map(s => s.hpAnn + s.choke), label: 'Ann+Choke', color: '#f44336' },
                { data: steps.map(s => s.hpAnn), label: 'HP Ann', color: '#2196f3' },
                { data: steps.map(s => s.hpStr), label: 'HP Str', color: '#00bcd4' }
            ]);
            charts.fill = createChart('chart-fill', 'Volumes vs Depth', depths, [
                { data: steps.map(s => s.cumFill), label: 'Fill (m³)', color: '#4caf50' },
                { data: steps.map(s => s.cumDisp), label: 'Disp (m³)', color: '#9c27b0' }
            ]);
        }

        function createChart(canvasId, title, xData, datasets) {
            const canvas = document.getElementById(canvasId);
            if (!canvas) return null;
            const ctx = canvas.getContext('2d');
            const tooltipId = 'tooltip-' + canvasId.replace('chart-', '');
            const tooltip = document.getElementById(tooltipId);

            const rect = canvas.parentElement.getBoundingClientRect();
            if (rect.width > 50) canvas.width = rect.width - 24;
            if (rect.height > 50) canvas.height = rect.height - 24;

            const w = canvas.width, h = canvas.height;
            const margin = { top: 30, right: 20, bottom: 30, left: 50 };
            const plotW = w - margin.left - margin.right;
            const plotH = h - margin.top - margin.bottom;

            const xMin = Math.min(...xData), xMax = Math.max(...xData);
            let yMin = Infinity, yMax = -Infinity;
            datasets.forEach(ds => { yMin = Math.min(yMin, ...ds.data); yMax = Math.max(yMax, ...ds.data); });
            const yPad = (yMax - yMin) * 0.1 || 1;
            yMin -= yPad; yMax += yPad;

            function draw(highlightIndex = -1) {
                ctx.clearRect(0, 0, w, h);
                ctx.fillStyle = '#f5f5f5';
                ctx.fillRect(0, 0, w, h);

                ctx.fillStyle = '#666';
                ctx.font = '12px -apple-system, sans-serif';
                ctx.textAlign = 'center';
                ctx.fillText(title, w / 2, 18);

                ctx.strokeStyle = '#ddd'; ctx.lineWidth = 0.5;
                for (let i = 0; i <= 4; i++) {
                    const y = margin.top + (plotH * i / 4);
                    ctx.beginPath(); ctx.moveTo(margin.left, y); ctx.lineTo(w - margin.right, y); ctx.stroke();
                }

                ctx.strokeStyle = '#999'; ctx.lineWidth = 1;
                ctx.beginPath();
                ctx.moveTo(margin.left, margin.top);
                ctx.lineTo(margin.left, h - margin.bottom);
                ctx.lineTo(w - margin.right, h - margin.bottom);
                ctx.stroke();

                ctx.fillStyle = '#666'; ctx.font = '9px -apple-system, sans-serif'; ctx.textAlign = 'right';
                for (let i = 0; i <= 4; i++) {
                    const val = yMin + (yMax - yMin) * (1 - i / 4);
                    ctx.fillText(val.toFixed(val >= 100 ? 0 : 1), margin.left - 5, margin.top + (plotH * i / 4) + 3);
                }

                ctx.textAlign = 'center';
                for (let i = 0; i <= 4; i++) {
                    const val = xMin + (xMax - xMin) * i / 4;
                    ctx.fillText(val.toFixed(0), margin.left + (plotW * i / 4), h - margin.bottom + 15);
                }

                datasets.forEach(ds => {
                    ctx.strokeStyle = ds.color; ctx.lineWidth = 1.5;
                    ctx.beginPath();
                    xData.forEach((x, i) => {
                        const px = margin.left + ((x - xMin) / (xMax - xMin)) * plotW;
                        const py = margin.top + ((yMax - ds.data[i]) / (yMax - yMin)) * plotH;
                        if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
                    });
                    ctx.stroke();
                });

                if (highlightIndex >= 0 && highlightIndex < xData.length) {
                    const x = xData[highlightIndex];
                    const px = margin.left + ((x - xMin) / (xMax - xMin)) * plotW;
                    ctx.strokeStyle = '#f44336'; ctx.lineWidth = 1; ctx.setLineDash([4, 4]);
                    ctx.beginPath(); ctx.moveTo(px, margin.top); ctx.lineTo(px, h - margin.bottom); ctx.stroke();
                    ctx.setLineDash([]);
                    datasets.forEach(ds => {
                        const py = margin.top + ((yMax - ds.data[highlightIndex]) / (yMax - yMin)) * plotH;
                        ctx.fillStyle = ds.color;
                        ctx.beginPath(); ctx.arc(px, py, 4, 0, Math.PI * 2); ctx.fill();
                    });
                }

                let legendX = margin.left;
                datasets.forEach(ds => {
                    ctx.fillStyle = ds.color;
                    ctx.fillRect(legendX, margin.top - 15, 12, 3);
                    ctx.fillStyle = '#666'; ctx.font = '8px -apple-system, sans-serif'; ctx.textAlign = 'left';
                    ctx.fillText(ds.label, legendX + 15, margin.top - 12);
                    legendX += ds.label.length * 5 + 30;
                });
            }

            function updateTooltip(idx) {
                if (!tooltip || idx < 0 || idx >= xData.length) { if (tooltip) tooltip.classList.remove('visible'); return; }
                let html = '<div style="font-weight:600;color:#aaa">MD: ' + xData[idx].toFixed(0) + ' m</div>';
                datasets.forEach(ds => {
                    html += '<div style="display:flex;justify-content:space-between;gap:12px"><span>' + ds.label + ':</span><span style="font-weight:600;color:' + ds.color + '">' + ds.data[idx].toFixed(ds.data[idx] >= 100 ? 0 : 2) + '</span></div>';
                });
                tooltip.innerHTML = html;
                tooltip.style.right = '8px'; tooltip.style.top = '8px'; tooltip.style.left = 'auto';
                tooltip.classList.add('visible');
            }

            draw();
            return { draw, updateTooltip };
        }

        function updateChartMarker(index) {
            Object.values(charts).forEach(chart => {
                if (chart && chart.draw) { chart.draw(index); if (chart.updateTooltip) chart.updateTooltip(index); }
            });
        }

        function highlightTableRow(index) {
            document.querySelectorAll('#data-table tbody tr').forEach((row, i) => row.classList.toggle('highlight', i === index));
        }

        let sortDirection = {};
        function sortTable(columnIndex) {
            const table = document.getElementById('data-table');
            const tbody = table.querySelector('tbody');
            const rows = Array.from(tbody.querySelectorAll('tr'));
            sortDirection[columnIndex] = !sortDirection[columnIndex];
            const dir = sortDirection[columnIndex] ? 1 : -1;
            rows.sort((a, b) => ((parseFloat(a.cells[columnIndex].textContent) || 0) - (parseFloat(b.cells[columnIndex].textContent) || 0)) * dir);
            rows.forEach(row => tbody.appendChild(row));
        }

        function filterTable() {
            const filter = document.getElementById('table-search').value.toLowerCase();
            document.querySelectorAll('#data-table tbody tr').forEach(row => {
                row.style.display = row.textContent.toLowerCase().includes(filter) ? '' : 'none';
            });
        }

        function exportTableCSV() {
            const table = document.getElementById('data-table');
            let csv = [];
            csv.push(Array.from(table.querySelectorAll('th')).map(th => th.textContent.replace(' ⇅', '')).join(','));
            table.querySelectorAll('tbody tr').forEach(row => csv.push(Array.from(row.querySelectorAll('td')).map(td => td.textContent).join(',')));
            const blob = new Blob([csv.join('\\n')], { type: 'text/csv' });
            const a = document.createElement('a');
            a.href = URL.createObjectURL(blob);
            a.download = 'trip_in_simulation_data.csv';
            a.click();
        }
        """
    }

    // MARK: - HTML Helpers

    private func escapeHTML(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func stepsToJSON(_ steps: [TripInSimulationViewModel.TripInStep]) -> String {
        var json = "["
        for (i, step) in steps.enumerated() {
            if i > 0 { json += "," }
            json += """
            {
                "bitMD": \(step.bitMD_m),
                "bitTVD": \(step.bitTVD_m),
                "esd": \(step.ESDAtControl_kgpm3),
                "choke": \(step.requiredChokePressure_kPa),
                "hpAnn": \(step.annulusPressureAtBit_kPa),
                "hpStr": \(step.stringPressureAtBit_kPa),
                "deltaP": \(step.differentialPressureAtBottom_kPa),
                "cumFill": \(step.cumulativeFillVolume_m3),
                "cumDisp": \(step.cumulativeDisplacementReturns_m3),
                "floatState": "\(step.floatState)",
                "layersPocket": \(layersToJSON(step.layersPocket))
            }
            """
        }
        json += "]"
        return json
    }

    private func layersToJSON(_ layers: [TripLayerSnapshot]) -> String {
        var json = "["
        for (i, layer) in layers.enumerated() {
            if i > 0 { json += "," }
            let r = Int((layer.colorR ?? 0.5) * 255)
            let g = Int((layer.colorG ?? 0.5) * 255)
            let b = Int((layer.colorB ?? 0.5) * 255)
            let a = layer.colorA ?? 1.0
            let colorStr = "\"rgba(\(r), \(g), \(b), \(a))\""
            json += """
            {"topMD": \(layer.topMD), "bottomMD": \(layer.bottomMD), "topTVD": \(layer.topTVD), "bottomTVD": \(layer.bottomTVD), "rho": \(layer.rho_kgpm3), "color": \(colorStr)}
            """
        }
        json += "]"
        return json
    }

    private func generateTableRows(_ steps: [TripInSimulationViewModel.TripInStep]) -> String {
        var html = ""
        for step in steps {
            // True ΔP at float = (Ann HP + Choke) - String HP
            let trueDeltaP = (step.annulusPressureAtBit_kPa + step.requiredChokePressure_kPa) - step.stringPressureAtBit_kPa
            html += """
            <tr>
                <td>\(String(format: "%.0f", step.bitMD_m))</td>
                <td>\(String(format: "%.0f", step.bitTVD_m))</td>
                <td>\(String(format: "%.0f", step.ESDAtControl_kgpm3))</td>
                <td>\(String(format: "%.0f", step.requiredChokePressure_kPa))</td>
                <td>\(String(format: "%.0f", step.annulusPressureAtBit_kPa))</td>
                <td>\(String(format: "%.0f", step.stringPressureAtBit_kPa))</td>
                <td>\(String(format: "%.0f", trueDeltaP))</td>
                <td>\(String(format: "%.3f", step.cumulativeFillVolume_m3))</td>
                <td>\(String(format: "%.3f", step.cumulativeDisplacementReturns_m3))</td>
                <td>\(step.floatState)</td>
            </tr>
            """
        }
        return html
    }
}
