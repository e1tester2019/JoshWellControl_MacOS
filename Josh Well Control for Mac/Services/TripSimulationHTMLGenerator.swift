//
//  TripSimulationHTMLGenerator.swift
//  Josh Well Control for Mac
//
//  Interactive HTML report generator for Trip Simulation
//

import Foundation

/// Cross-platform HTML generator for trip simulation reports
class TripSimulationHTMLGenerator {
    static let shared = TripSimulationHTMLGenerator()

    private init() {}

    func generateHTML(for data: TripSimulationReportData) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy, HH:mm"
        let dateStr = dateFormatter.string(from: data.generatedDate)

        let direction = data.startMD > data.endMD ? "POOH (Pull Out Of Hole)" : "RIH (Run In Hole)"

        // Convert steps to JSON for JavaScript
        let stepsJSON = stepsToJSON(data.steps)

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Trip Simulation Report - \(escapeHTML(data.wellName))</title>
            <style>
                \(generateCSS())
            </style>
        </head>
        <body>
            <header>
                <div class="header-content">
                    <h1>Trip Simulation Report</h1>
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
                            <span class="value">\(direction)</span>
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
                            <span class="label">End MD:</span>
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
                            <span class="label">Base Mud:</span>
                            <span class="value">\(String(format: "%.0f kg/m³", data.baseMudDensity))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Backfill:</span>
                            <span class="value">\(String(format: "%.0f kg/m³", data.backfillDensity))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Target ESD:</span>
                            <span class="value">\(String(format: "%.0f kg/m³", data.targetESD))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Crack Float:</span>
                            <span class="value">\(String(format: "%.0f kPa", data.crackFloat))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Initial SABP:</span>
                            <span class="value">\(String(format: "%.0f kPa", data.initialSABP))</span>
                        </div>
                        <div class="param-item">
                            <span class="label">Trip Speed:</span>
                            <span class="value">\(String(format: "%.1f m/min", data.tripSpeed))</span>
                        </div>
                    </div>
                </section>

                <!-- Safety Summary -->
                <section class="card">
                    <h2>Safety Summary</h2>
                    <div class="metrics-grid">
                        <div class="metric-box">
                            <div class="metric-title">ESD Range</div>
                            <div class="metric-value">\(String(format: "%.0f - %.0f", data.minESD, data.maxESD))</div>
                            <div class="metric-unit">kg/m³</div>
                        </div>
                        <div class="metric-box">
                            <div class="metric-title">Max Static SABP</div>
                            <div class="metric-value">\(String(format: "%.0f", data.maxStaticSABP))</div>
                            <div class="metric-unit">kPa</div>
                        </div>
                        <div class="metric-box \(data.maxDynamicSABP > 50 ? "warning" : "")">
                            <div class="metric-title">Max Dynamic SABP</div>
                            <div class="metric-value">\(String(format: "%.0f", data.maxDynamicSABP))</div>
                            <div class="metric-unit">kPa</div>
                        </div>
                        <div class="metric-box">
                            <div class="metric-title">Total Backfill</div>
                            <div class="metric-value">\(String(format: "%.1f", data.totalBackfill))</div>
                            <div class="metric-unit">m³</div>
                        </div>
                    </div>
                    <div class="metrics-grid secondary">
                        <div class="metric-box small">
                            <div class="metric-title">Initial Pit Gain</div>
                            <div class="metric-value">\(String(format: "%.2f m³", data.totalPitGain))</div>
                        </div>
                        <div class="metric-box small \(data.netTankChange < 0 ? "danger" : "")">
                            <div class="metric-title">Net Tank Change</div>
                            <div class="metric-value">\(String(format: "%+.1f m³", data.netTankChange))</div>
                        </div>
                        <div class="metric-box small">
                            <div class="metric-title">Number of Steps</div>
                            <div class="metric-value">\(data.steps.count)</div>
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
                        <div class="well-columns-container">
                            <div class="well-column">
                                <div class="column-header">Annulus</div>
                                <canvas id="annulus-left" width="80" height="400"></canvas>
                            </div>
                            <div class="well-column string-column">
                                <div class="column-header">String</div>
                                <canvas id="string-canvas" width="80" height="400"></canvas>
                            </div>
                            <div class="well-column">
                                <div class="column-header">Annulus</div>
                                <canvas id="annulus-right" width="80" height="400"></canvas>
                            </div>
                        </div>
                        <canvas id="pocket-overlay" class="pocket-overlay"></canvas>
                    </div>
                    <div class="step-info" id="step-info">
                        <div class="info-row"><span>Bit MD:</span> <span id="info-md">--</span></div>
                        <div class="info-row"><span>ESD @ TD:</span> <span id="info-esd">--</span></div>
                        <div class="info-row"><span>Static SABP:</span> <span id="info-sabp">--</span></div>
                        <div class="info-row"><span>Float State:</span> <span id="info-float">--</span></div>
                        <div class="info-row"><span>Step Backfill:</span> <span id="info-backfill">--</span></div>
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
                        <div class="chart-container" id="container-sabp">
                            <canvas id="chart-sabp" width="280" height="180"></canvas>
                            <div class="chart-tooltip" id="tooltip-sabp"></div>
                        </div>
                        <div class="chart-container" id="container-tank">
                            <canvas id="chart-tank" width="280" height="180"></canvas>
                            <div class="chart-tooltip" id="tooltip-tank"></div>
                        </div>
                        <div class="chart-container" id="container-backfill">
                            <canvas id="chart-backfill" width="280" height="180"></canvas>
                            <div class="chart-tooltip" id="tooltip-backfill"></div>
                        </div>
                    </div>
                </section>

                <!-- Final Spotted Fluids -->
                \(generateFinalSpottedFluidsSection(data))

                <!-- Fluids Used -->
                <section class="card">
                    <h2>Fluids Used</h2>
                    \(generateFluidsTable(data))
                </section>

                <!-- Geometry Tables -->
                <section class="card">
                    <h2>Well Geometry</h2>
                    <h3>Drill String</h3>
                    \(generateDrillStringTable(data.drillStringSections, totalCapacity: data.totalStringCapacity, totalDisplacement: data.totalStringDisplacement))

                    <h3>Annulus</h3>
                    \(generateAnnulusTable(data.annulusSections, totalCapacity: data.totalAnnulusCapacity))
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
                                    <th onclick="sortTable(2)">Static SABP ⇅</th>
                                    <th onclick="sortTable(3)">Dynamic SABP ⇅</th>
                                    <th onclick="sortTable(4)">ESD (kg/m³) ⇅</th>
                                    <th onclick="sortTable(5)">DP Wet (m³) ⇅</th>
                                    <th onclick="sortTable(6)">DP Dry (m³) ⇅</th>
                                    <th onclick="sortTable(7)">Actual (m³) ⇅</th>
                                    <th onclick="sortTable(8)">Tank Δ (m³) ⇅</th>
                                    <th onclick="sortTable(9)">Float ⇅</th>
                                </tr>
                            </thead>
                            <tbody>
                                \(generateTableRows(data.steps))
                            </tbody>
                        </table>
                    </div>
                    <div class="table-legend">
                        Units: MD/TVD (m), SABP (kPa), ESD (kg/m³), Fill volumes (m³), Tank Δ (m³ cumulative)
                    </div>
                </section>
            </main>

            <!-- Debug output (hidden by default, shows on error) -->
            <details class="debug-section">
                <summary>Debug Info</summary>
                <pre id="debug-output"></pre>
            </details>

            <footer>
                <p>Generated by Josh Well Control • \(dateStr)</p>
            </footer>

            <script>
                // Simulation data
                const steps = \(stepsJSON);
                // maxDepth includes pocket bottom to match SwiftUI visualization
                const maxBitMD = \(String(format: "%.1f", max(data.startMD, data.steps.map { $0.bitMD_m }.max() ?? 0)));
                const maxPocketMD = \(String(format: "%.1f", data.steps.flatMap { $0.layersPocket }.map { $0.bottomMD }.max() ?? 0));
                const maxDepth = Math.max(maxBitMD, maxPocketMD);
                const maxTVD = \(String(format: "%.1f", data.steps.map { $0.bitTVD_m }.max() ?? 0));

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

        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }

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

        header h1 {
            font-size: 1.5rem;
            font-weight: 600;
        }

        .well-name {
            opacity: 0.9;
            font-size: 0.9rem;
        }

        main {
            max-width: 1200px;
            margin: 0 auto;
            padding: 24px;
        }

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

        .info-item, .param-item {
            display: flex;
            gap: 8px;
        }

        .label {
            color: var(--text-light);
            font-size: 0.85rem;
        }

        .value {
            font-weight: 500;
        }

        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
            gap: 12px;
            margin-bottom: 12px;
        }

        .metrics-grid.secondary {
            grid-template-columns: repeat(3, 1fr);
        }

        .metric-box {
            background: var(--bg-color);
            border-radius: 6px;
            padding: 12px;
            text-align: center;
        }

        .metric-box.small {
            padding: 10px;
        }

        .metric-box.warning .metric-value {
            color: var(--warning-color);
        }

        .metric-box.danger .metric-value {
            color: var(--danger-color);
        }

        .metric-title {
            font-size: 0.75rem;
            color: var(--text-light);
            margin-bottom: 4px;
        }

        .metric-value {
            font-size: 1.3rem;
            font-weight: 700;
            color: var(--safe-color);
        }

        .metric-box.small .metric-value {
            font-size: 1.1rem;
        }

        .metric-unit {
            font-size: 0.7rem;
            color: var(--text-light);
        }

        /* Final Spotted Fluids */
        .fluids-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 24px;
        }

        @media (max-width: 768px) {
            .fluids-grid {
                grid-template-columns: 1fr;
            }
        }

        .fluids-column h3 {
            font-size: 0.8rem;
            color: var(--text-light);
            margin-bottom: 12px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .fluid-layer {
            display: flex;
            align-items: flex-start;
            padding: 10px 0;
            border-bottom: 1px solid var(--border-color);
        }

        .fluid-layer:last-child {
            border-bottom: none;
        }

        .fluid-swatch {
            width: 16px;
            height: 40px;
            border-radius: 3px;
            margin-right: 12px;
            flex-shrink: 0;
            border: 1px solid rgba(0,0,0,0.15);
        }

        .fluid-info {
            flex: 1;
            min-width: 0;
        }

        .fluid-name {
            font-weight: 600;
            font-size: 0.9rem;
            margin-bottom: 2px;
        }

        .fluid-details {
            font-size: 0.75rem;
            color: var(--text-light);
        }

        .fluid-metrics {
            text-align: right;
            flex-shrink: 0;
        }

        .fluid-volume {
            font-weight: 600;
            font-size: 0.95rem;
        }

        .fluid-capacity {
            font-size: 0.7rem;
            color: var(--text-light);
        }

        /* Wellbore Visualization */
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

        .slider-container {
            display: flex;
            align-items: center;
            gap: 12px;
            flex: 1;
        }

        .slider-container input[type="range"] {
            flex: 1;
            min-width: 200px;
        }

        #current-depth {
            font-weight: 600;
            min-width: 80px;
        }

        .playback-controls {
            display: flex;
            gap: 8px;
        }

        .playback-controls button, .playback-controls select {
            padding: 6px 12px;
            border: 1px solid var(--border-color);
            border-radius: 4px;
            background: white;
            cursor: pointer;
            font-size: 0.85rem;
        }

        .playback-controls button:hover {
            background: var(--bg-color);
        }

        .wellbore-display {
            position: relative;
            padding: 20px;
            background: #1a1a1a;
            border-radius: 6px;
        }

        .well-columns-container {
            display: flex;
            justify-content: center;
            gap: 4px;
            position: relative;
        }

        .well-column {
            display: flex;
            flex-direction: column;
            align-items: center;
        }

        .pocket-overlay {
            position: absolute;
            pointer-events: none;
        }

        .column-header {
            color: rgba(255,255,255,0.7);
            font-size: 0.75rem;
            margin-bottom: 8px;
        }

        .well-column canvas {
            border: 1px solid #333;
            /* Background controlled by JavaScript for proper bit depth rendering */
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

        .info-row {
            display: flex;
            justify-content: space-between;
            font-size: 0.85rem;
        }

        .info-row span:first-child {
            color: var(--text-light);
        }

        .info-row span:last-child {
            font-weight: 600;
        }

        /* Charts */
        .charts-grid {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 16px;
        }

        @media (max-width: 768px) {
            .charts-grid {
                grid-template-columns: 1fr;
            }
        }

        .chart-container {
            background: var(--bg-color);
            border-radius: 6px;
            padding: 12px;
            height: 250px;
        }

        .chart-container canvas {
            width: 100% !important;
            height: 100% !important;
        }

        .chart-container {
            position: relative;
        }

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
            box-shadow: 0 2px 8px rgba(0,0,0,0.3);
        }

        .chart-tooltip.visible {
            opacity: 1;
        }

        .chart-tooltip .tooltip-title {
            font-weight: 600;
            margin-bottom: 4px;
            color: #aaa;
        }

        .chart-tooltip .tooltip-row {
            display: flex;
            justify-content: space-between;
            gap: 12px;
        }

        .chart-tooltip .tooltip-value {
            font-weight: 600;
            font-family: monospace;
        }

        .chart-hint {
            font-size: 0.75rem;
            color: var(--text-light);
            margin-bottom: 12px;
            font-style: italic;
        }

        /* Tables */
        .table-controls {
            display: flex;
            gap: 12px;
            margin-bottom: 12px;
        }

        .table-controls input {
            flex: 1;
            padding: 8px 12px;
            border: 1px solid var(--border-color);
            border-radius: 4px;
            font-size: 0.9rem;
        }

        .table-controls button {
            padding: 8px 16px;
            background: var(--brand-color);
            color: white;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            font-size: 0.85rem;
        }

        .table-wrapper {
            overflow-x: auto;
            max-height: 500px;
            overflow-y: auto;
        }

        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 0.8rem;
        }

        thead {
            position: sticky;
            top: 0;
            z-index: 10;
        }

        th {
            background: var(--brand-color);
            color: white;
            padding: 10px 8px;
            text-align: right;
            cursor: pointer;
            white-space: nowrap;
            user-select: none;
        }

        th:hover {
            background: #4795ab;
        }

        td {
            padding: 8px;
            text-align: right;
            border-bottom: 1px solid var(--border-color);
        }

        tr:nth-child(even) {
            background: var(--bg-color);
        }

        tr:hover {
            background: #e3f2fd;
        }

        tr.highlight {
            background: #bbdefb !important;
        }

        .table-legend {
            margin-top: 8px;
            font-size: 0.7rem;
            color: var(--text-light);
        }

        .volume-summary {
            margin-top: 16px;
            padding: 12px;
            background: var(--bg-color);
            border-radius: 6px;
            max-width: 300px;
        }

        .volume-summary h4 {
            font-size: 0.9rem;
            color: var(--brand-color);
            margin-bottom: 8px;
        }

        .summary-row {
            display: flex;
            justify-content: space-between;
            font-size: 0.85rem;
            padding: 4px 0;
        }

        .summary-row.total {
            border-top: 1px solid var(--border-color);
            margin-top: 4px;
            padding-top: 8px;
            font-weight: 600;
        }

        /* Geometry Tables */
        .geometry-table {
            font-size: 0.8rem;
            margin-bottom: 12px;
        }

        .geometry-table th {
            font-size: 0.75rem;
            padding: 8px 6px;
        }

        .geometry-table td {
            padding: 6px;
        }

        .geometry-table td:first-child {
            text-align: left;
        }

        .total-row {
            background: #e0e0e0 !important;
            font-weight: 600;
        }

        footer {
            text-align: center;
            padding: 20px;
            color: var(--text-light);
            font-size: 0.8rem;
        }

        .debug-section {
            margin: 16px;
            padding: 12px;
            background: #2a2a2a;
            border-radius: 6px;
            color: #0f0;
            font-family: monospace;
            font-size: 11px;
        }

        .debug-section summary {
            cursor: pointer;
            color: #888;
        }

        .debug-section pre {
            margin-top: 8px;
            white-space: pre-wrap;
            max-height: 200px;
            overflow-y: auto;
        }

        @media print {
            header {
                position: static;
            }
            .wellbore-controls, .playback-controls, .table-controls {
                display: none;
            }
            .card {
                break-inside: avoid;
            }
        }
        """
    }

    // MARK: - JavaScript Generation

    private func generateJavaScript() -> String {
        return """
        // Debug helper
        function debugLog(msg) {
            console.log(msg);
            const el = document.getElementById('debug-output');
            if (el) el.textContent += msg + '\\n';
        }

        // Initialize on load
        document.addEventListener('DOMContentLoaded', function() {
            debugLog('DOMContentLoaded fired');
            debugLog('steps.length=' + steps.length);
            debugLog('maxDepth=' + maxDepth + ', maxTVD=' + maxTVD);

            if (steps.length > 0) {
                const s = steps[0];
                debugLog('step[0] keys: ' + Object.keys(s).join(', '));
                debugLog('la count: ' + (s.la ? s.la.length : 'undefined'));
                debugLog('ls count: ' + (s.ls ? s.ls.length : 'undefined'));
                debugLog('lp count: ' + (s.lp ? s.lp.length : 'undefined'));
            }

            initSlider();
            // Use requestAnimationFrame to ensure layout is complete before drawing
            requestAnimationFrame(function() {
                debugLog('requestAnimationFrame callback');
                try {
                    initCharts();
                    updateChartMarker(0);  // Show tooltips for initial position
                    debugLog('initCharts completed');
                } catch (e) {
                    debugLog('initCharts error: ' + e.message);
                }
                try {
                    updateWellbore(0);
                    debugLog('updateWellbore completed');
                } catch (e) {
                    debugLog('updateWellbore error: ' + e.message);
                }
                // Retry after a short delay in case layout wasn't ready
                setTimeout(function() {
                    debugLog('Retry after 100ms');
                    try {
                        initCharts();
                        updateChartMarker(0);  // Show tooltips for initial position
                        updateWellbore(0);
                        debugLog('Retry completed');
                    } catch (e) {
                        debugLog('Retry error: ' + e.message);
                    }
                }, 100);
            });
        });

        // Slider functionality
        function initSlider() {
            const slider = document.getElementById('depth-slider');
            slider.addEventListener('input', function() {
                currentStepIndex = parseInt(this.value);
                updateWellbore(currentStepIndex);
                highlightTableRow(currentStepIndex);
            });
        }

        function updateWellbore(index) {
            if (index < 0 || index >= steps.length) return;
            const step = steps[index];

            // Update info display
            document.getElementById('current-depth').textContent = step.md.toFixed(0) + ' m';
            document.getElementById('info-md').textContent = step.md.toFixed(0) + ' m';
            document.getElementById('info-esd').textContent = step.esd.toFixed(0) + ' kg/m³';
            document.getElementById('info-sabp').textContent = step.ss.toFixed(0) + ' kPa';
            document.getElementById('info-float').textContent = step.fs;
            document.getElementById('info-backfill').textContent = step.sbf.toFixed(3) + ' m³';

            // Draw wellbore canvases
            drawWellboreColumn('annulus-left', step.la, step.md, 'annulus');
            drawWellboreColumn('string-canvas', step.ls, step.md, 'string');
            drawWellboreColumn('annulus-right', step.la, step.md, 'annulus');

            // Draw pocket overlay
            drawPocketOverlay(step.lp, step.md);

            // Draw depth scale markers (TVD on left, MD on right)
            drawDepthScale('annulus-left', step.tvd, 'tvd');
            drawDepthScale('annulus-right', step.md, 'md');

            // Update chart marker if charts exist
            updateChartMarker(index);
        }

        function drawDepthScale(canvasId, currentDepth, type) {
            const canvas = document.getElementById(canvasId);
            if (!canvas) return;
            const ctx = canvas.getContext('2d');
            if (!ctx) return;
            const h = canvas.height;
            const w = canvas.width;
            if (w <= 0 || h <= 0) return;
            const tickCount = 5;
            const maxVal = type === 'tvd' ? maxTVD : maxDepth;
            if (maxVal <= 0) return;
            const label = type === 'tvd' ? 'TVD' : 'MD';

            ctx.font = '9px -apple-system, sans-serif';
            ctx.fillStyle = 'rgba(255, 255, 255, 0.8)';
            ctx.strokeStyle = 'rgba(255, 255, 255, 0.5)';
            ctx.lineWidth = 1;

            // Draw tick marks and labels
            for (let i = 0; i <= tickCount; i++) {
                const depth = (i / tickCount) * maxVal;
                const y = (i / tickCount) * h;

                // Tick line
                ctx.beginPath();
                if (type === 'tvd') {
                    // Left side: tick on right edge of canvas
                    ctx.moveTo(w - 8, y);
                    ctx.lineTo(w, y);
                    ctx.stroke();
                    // Label on left side
                    ctx.textAlign = 'left';
                    ctx.fillText(depth.toFixed(0), 2, y + 3);
                } else {
                    // Right side: tick on left edge of canvas
                    ctx.moveTo(0, y);
                    ctx.lineTo(8, y);
                    ctx.stroke();
                    // Label on right side
                    ctx.textAlign = 'right';
                    ctx.fillText(depth.toFixed(0), w - 2, y + 3);
                }
            }

            // Draw header label at top
            ctx.font = '8px -apple-system, sans-serif';
            ctx.fillStyle = 'rgba(255, 255, 255, 0.6)';
            if (type === 'tvd') {
                ctx.textAlign = 'left';
                ctx.fillText(label, 2, 10);
            } else {
                ctx.textAlign = 'right';
                ctx.fillText(label, w - 2, 10);
            }
        }

        function drawWellboreColumn(canvasId, layers, bitMD, type) {
            const canvas = document.getElementById(canvasId);
            if (!canvas) { debugLog('Canvas not found: ' + canvasId); return; }
            const ctx = canvas.getContext('2d');
            if (!ctx) { debugLog('No 2d context for: ' + canvasId); return; }
            const h = canvas.height;
            const w = canvas.width;
            if (w <= 0 || h <= 0) { debugLog('Invalid canvas size: ' + w + 'x' + h); return; }
            if (maxDepth <= 0) { debugLog('Invalid maxDepth: ' + maxDepth); return; }
            debugLog('Drawing ' + canvasId + ': ' + (layers ? layers.length : 0) + ' layers, bitMD=' + bitMD);

            const bitY = (bitMD / maxDepth) * h;

            // Clear entire canvas first
            ctx.clearRect(0, 0, w, h);

            // Fill background only ABOVE bit (pocket overlay covers below)
            ctx.fillStyle = '#2a2a2a';
            ctx.fillRect(0, 0, w, bitY);

            // Draw layers (only above bit)
            layers.forEach(layer => {
                if (layer.b > bitMD) return;
                const y1 = (layer.t / maxDepth) * h;
                const y2 = Math.min((layer.b / maxDepth) * h, bitY);
                const layerH = Math.max(1, y2 - y1);

                ctx.fillStyle = layer.c || densityToColor(layer.r);
                ctx.fillRect(0, y1, w, layerH);
            });

            // Draw bit line (full width handled by main canvas)
            ctx.fillStyle = '#e05040';
            ctx.fillRect(0, bitY - 1, w, 2);
        }

        function drawPocketOverlay(layers, bitMD) {
            const overlay = document.getElementById('pocket-overlay');
            const wellboreDisplay = document.querySelector('.wellbore-display');
            const leftCanvas = document.getElementById('annulus-left');
            const rightCanvas = document.getElementById('annulus-right');
            if (!overlay || !wellboreDisplay || !leftCanvas || !rightCanvas) return;

            // Get positions relative to the wellbore-display (which has position:relative)
            const displayRect = wellboreDisplay.getBoundingClientRect();
            const leftRect = leftCanvas.getBoundingClientRect();
            const rightRect = rightCanvas.getBoundingClientRect();

            // Position overlay to span exactly from annulus-left to annulus-right
            const overlayLeft = leftRect.left - displayRect.left;
            const overlayTop = leftRect.top - displayRect.top;
            const overlayWidth = rightRect.right - leftRect.left;

            overlay.style.left = overlayLeft + 'px';
            overlay.style.top = overlayTop + 'px';
            overlay.width = overlayWidth;
            overlay.height = leftCanvas.height;
            overlay.style.width = overlayWidth + 'px';
            overlay.style.height = leftCanvas.height + 'px';

            const ctx = overlay.getContext('2d');
            if (!ctx) return;
            const h = overlay.height;
            const w = overlay.width;
            if (w <= 0 || h <= 0 || maxDepth <= 0) return;

            // Clear overlay
            ctx.clearRect(0, 0, w, h);

            // Calculate bit position
            const bitY = (bitMD / maxDepth) * h;

            // Fill pocket area (below bit) with dark background
            ctx.fillStyle = '#2a2a2a';
            ctx.fillRect(0, bitY, w, h - bitY);

            // Draw pocket layers full width (below bit)
            layers.forEach(layer => {
                const y1 = (layer.t / maxDepth) * h;
                const y2 = (layer.b / maxDepth) * h;
                const layerH = Math.max(1, y2 - y1);

                ctx.fillStyle = layer.c || densityToColor(layer.r);
                ctx.fillRect(0, y1, w, layerH);
            });

            // Draw bit line across full width
            ctx.fillStyle = '#e05040';
            ctx.fillRect(0, bitY - 1, w, 2);
        }

        function densityToColor(rho) {
            // Air (rho ~1.2) gets a distinct light blue color
            if (rho < 10) {
                return 'rgba(180, 215, 255, 0.8)';
            }
            // Map density to grayscale (lighter = lighter mud)
            const t = Math.min(Math.max((rho - 800) / 1200, 0), 1);
            const v = Math.round(80 + 150 * (1 - t));
            return `rgb(${v}, ${v}, ${v})`;
        }

        // Playback controls
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
                    if (currentStepIndex >= steps.length) {
                        currentStepIndex = 0;
                    }
                    document.getElementById('depth-slider').value = currentStepIndex;
                    updateWellbore(currentStepIndex);
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
            highlightTableRow(0);
        }

        // Charts
        let charts = {};

        function initCharts() {
            const depths = steps.map(s => s.md);
            const esds = steps.map(s => s.esd);
            const sabpStatic = steps.map(s => s.ss);
            const sabpDynamic = steps.map(s => s.sd);
            const tankDeltas = steps.map(s => s.td);
            const backfills = steps.map(s => s.cbf);

            charts.esd = createChart('chart-esd', 'ESD vs Depth', depths, [
                { data: esds, label: 'ESD (kg/m³)', color: '#2196f3' }
            ]);

            charts.sabp = createChart('chart-sabp', 'SABP vs Depth', depths, [
                { data: sabpStatic, label: 'Static', color: '#4caf50' },
                { data: sabpDynamic, label: 'Dynamic', color: '#ff9800' }
            ]);

            charts.tank = createChart('chart-tank', 'Tank Volume Change', depths, [
                { data: tankDeltas, label: 'Tank Δ (m³)', color: '#9c27b0' }
            ]);

            charts.backfill = createChart('chart-backfill', 'Cumulative Backfill', depths, [
                { data: backfills, label: 'Backfill (m³)', color: '#009688' }
            ]);
        }

        function createChart(canvasId, title, xData, datasets) {
            const canvas = document.getElementById(canvasId);
            if (!canvas) { debugLog('Chart canvas not found: ' + canvasId); return null; }
            const ctx = canvas.getContext('2d');
            if (!ctx) { debugLog('No 2d context for chart: ' + canvasId); return null; }

            // Get tooltip element
            const tooltipId = 'tooltip-' + canvasId.replace('chart-', '');
            const tooltip = document.getElementById(tooltipId);

            // Use explicit canvas dimensions (set in HTML) or fallback
            // Only resize if the canvas has default/small dimensions
            const rect = canvas.parentElement ? canvas.parentElement.getBoundingClientRect() : { width: 0, height: 0 };
            debugLog('Chart ' + canvasId + ' parent rect: ' + rect.width + 'x' + rect.height);
            if (rect.width > 50 && rect.height > 50) {
                canvas.width = rect.width - 24;
                canvas.height = rect.height - 24;
            }
            // Ensure minimum dimensions
            if (canvas.width < 100) canvas.width = 280;
            if (canvas.height < 100) canvas.height = 180;
            debugLog('Chart ' + canvasId + ' final size: ' + canvas.width + 'x' + canvas.height + ', dataPoints=' + xData.length);

            const w = canvas.width;
            const h = canvas.height;
            const margin = { top: 30, right: 20, bottom: 30, left: 50 };
            const plotW = w - margin.left - margin.right;
            const plotH = h - margin.top - margin.bottom;

            const xMin = Math.min(...xData);
            const xMax = Math.max(...xData);
            let yMin = Infinity, yMax = -Infinity;
            datasets.forEach(ds => {
                yMin = Math.min(yMin, ...ds.data);
                yMax = Math.max(yMax, ...ds.data);
            });
            const yPad = (yMax - yMin) * 0.1 || 1;
            yMin -= yPad;
            yMax += yPad;

            // Convert pixel X to data index
            function pxToIndex(px) {
                const relX = (px - margin.left) / plotW;
                const depth = xMax - relX * (xMax - xMin);
                // Find closest data point
                let closestIdx = 0;
                let closestDist = Infinity;
                xData.forEach((x, i) => {
                    const dist = Math.abs(x - depth);
                    if (dist < closestDist) {
                        closestDist = dist;
                        closestIdx = i;
                    }
                });
                return closestIdx;
            }

            function draw(highlightIndex = -1) {
                ctx.clearRect(0, 0, w, h);

                // Background
                ctx.fillStyle = '#f5f5f5';
                ctx.fillRect(0, 0, w, h);

                // Title
                ctx.fillStyle = '#666';
                ctx.font = '12px -apple-system, sans-serif';
                ctx.textAlign = 'center';
                ctx.fillText(title, w / 2, 18);

                // Grid
                ctx.strokeStyle = '#ddd';
                ctx.lineWidth = 0.5;
                for (let i = 0; i <= 4; i++) {
                    const y = margin.top + (plotH * i / 4);
                    ctx.beginPath();
                    ctx.moveTo(margin.left, y);
                    ctx.lineTo(w - margin.right, y);
                    ctx.stroke();
                }

                // Axes
                ctx.strokeStyle = '#999';
                ctx.lineWidth = 1;
                ctx.beginPath();
                ctx.moveTo(margin.left, margin.top);
                ctx.lineTo(margin.left, h - margin.bottom);
                ctx.lineTo(w - margin.right, h - margin.bottom);
                ctx.stroke();

                // Y labels
                ctx.fillStyle = '#666';
                ctx.font = '9px -apple-system, sans-serif';
                ctx.textAlign = 'right';
                for (let i = 0; i <= 4; i++) {
                    const val = yMin + (yMax - yMin) * (1 - i / 4);
                    const y = margin.top + (plotH * i / 4);
                    ctx.fillText(val.toFixed(val >= 100 ? 0 : 1), margin.left - 5, y + 3);
                }

                // X labels (inverted for depth)
                ctx.textAlign = 'center';
                for (let i = 0; i <= 4; i++) {
                    const val = xMax - (xMax - xMin) * i / 4;
                    const x = margin.left + (plotW * i / 4);
                    ctx.fillText(val.toFixed(0), x, h - margin.bottom + 15);
                }

                // Data lines
                datasets.forEach(ds => {
                    ctx.strokeStyle = ds.color;
                    ctx.lineWidth = 1.5;
                    ctx.beginPath();
                    xData.forEach((x, i) => {
                        const px = margin.left + ((xMax - x) / (xMax - xMin)) * plotW;
                        const py = margin.top + ((yMax - ds.data[i]) / (yMax - yMin)) * plotH;
                        if (i === 0) ctx.moveTo(px, py);
                        else ctx.lineTo(px, py);
                    });
                    ctx.stroke();
                });

                // Highlight marker
                if (highlightIndex >= 0 && highlightIndex < xData.length) {
                    const x = xData[highlightIndex];
                    const px = margin.left + ((xMax - x) / (xMax - xMin)) * plotW;
                    ctx.strokeStyle = '#f44336';
                    ctx.lineWidth = 1;
                    ctx.setLineDash([4, 4]);
                    ctx.beginPath();
                    ctx.moveTo(px, margin.top);
                    ctx.lineTo(px, h - margin.bottom);
                    ctx.stroke();
                    ctx.setLineDash([]);

                    // Draw data points at highlight
                    datasets.forEach(ds => {
                        const py = margin.top + ((yMax - ds.data[highlightIndex]) / (yMax - yMin)) * plotH;
                        ctx.fillStyle = ds.color;
                        ctx.beginPath();
                        ctx.arc(px, py, 4, 0, Math.PI * 2);
                        ctx.fill();
                    });
                }

                // Legend
                let legendX = margin.left;
                datasets.forEach(ds => {
                    ctx.fillStyle = ds.color;
                    ctx.fillRect(legendX, margin.top - 15, 12, 3);
                    ctx.fillStyle = '#666';
                    ctx.font = '8px -apple-system, sans-serif';
                    ctx.textAlign = 'left';
                    ctx.fillText(ds.label, legendX + 15, margin.top - 12);
                    legendX += ds.label.length * 5 + 30;
                });
            }

            // Update tooltip for given index (called when slider changes)
            function updateTooltip(idx) {
                if (!tooltip || idx < 0 || idx >= xData.length) {
                    if (tooltip) tooltip.classList.remove('visible');
                    return;
                }

                const depth = xData[idx];
                let html = '<div class="tooltip-title">MD: ' + depth.toFixed(0) + ' m</div>';
                datasets.forEach(ds => {
                    const val = ds.data[idx];
                    html += '<div class="tooltip-row"><span>' + ds.label + ':</span><span class="tooltip-value" style="color:' + ds.color + '">' + val.toFixed(val >= 100 ? 0 : 2) + '</span></div>';
                });
                tooltip.innerHTML = html;

                // Position tooltip at top-right of chart
                tooltip.style.right = '8px';
                tooltip.style.top = '8px';
                tooltip.style.left = 'auto';
                tooltip.classList.add('visible');
            }

            draw();
            return { draw, updateTooltip };
        }

        function updateChartMarker(index) {
            Object.values(charts).forEach(chart => {
                if (chart && chart.draw) {
                    chart.draw(index);
                    if (chart.updateTooltip) chart.updateTooltip(index);
                }
            });
        }

        // Table functionality
        function highlightTableRow(index) {
            const rows = document.querySelectorAll('#data-table tbody tr');
            rows.forEach((row, i) => {
                row.classList.toggle('highlight', i === index);
            });
            // Note: Auto-scroll removed to prevent screen jumping
        }

        let sortDirection = {};
        function sortTable(columnIndex) {
            const table = document.getElementById('data-table');
            const tbody = table.querySelector('tbody');
            const rows = Array.from(tbody.querySelectorAll('tr'));

            sortDirection[columnIndex] = !sortDirection[columnIndex];
            const dir = sortDirection[columnIndex] ? 1 : -1;

            rows.sort((a, b) => {
                const aVal = parseFloat(a.cells[columnIndex].textContent) || 0;
                const bVal = parseFloat(b.cells[columnIndex].textContent) || 0;
                return (aVal - bVal) * dir;
            });

            rows.forEach(row => tbody.appendChild(row));
        }

        function filterTable() {
            const filter = document.getElementById('table-search').value.toLowerCase();
            const rows = document.querySelectorAll('#data-table tbody tr');
            rows.forEach(row => {
                const text = row.textContent.toLowerCase();
                row.style.display = text.includes(filter) ? '' : 'none';
            });
        }

        function exportTableCSV() {
            const table = document.getElementById('data-table');
            let csv = [];
            const headers = Array.from(table.querySelectorAll('th')).map(th => th.textContent.replace(' ⇅', ''));
            csv.push(headers.join(','));

            table.querySelectorAll('tbody tr').forEach(row => {
                const cols = Array.from(row.querySelectorAll('td')).map(td => td.textContent);
                csv.push(cols.join(','));
            });

            const blob = new Blob([csv.join('\\n')], { type: 'text/csv' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = 'trip_simulation_data.csv';
            a.click();
            URL.revokeObjectURL(url);
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

    private func f0(_ v: Double) -> String { String(format: "%.0f", v) }
    private func f1(_ v: Double) -> String { String(format: "%.1f", v) }
    private func f2(_ v: Double) -> String { String(format: "%.2f", v) }

    private func stepsToJSON(_ steps: [NumericalTripModel.TripStep]) -> String {
        var json = "["
        for (i, step) in steps.enumerated() {
            if i > 0 { json += "," }
            json += """
            {"md":\(f1(step.bitMD_m)),"tvd":\(f1(step.bitTVD_m)),"esd":\(f1(step.ESDatTD_kgpm3)),"ss":\(f0(step.SABP_kPa)),"sd":\(f0(step.SABP_Dynamic_kPa)),"td":\(f2(step.cumulativeSurfaceTankDelta_m3)),"cbf":\(f2(step.cumulativeBackfill_m3)),"sbf":\(f2(step.stepBackfill_m3)),"fs":"\(step.floatState)","la":\(layersToJSON(step.layersAnnulus)),"ls":\(layersToJSON(step.layersString)),"lp":\(layersToJSON(step.layersPocket))}
            """
        }
        json += "]"
        return json
    }

    private func layersToJSON(_ layers: [NumericalTripModel.LayerRow]) -> String {
        var json = "["
        for (i, layer) in layers.enumerated() {
            if i > 0 { json += "," }
            let colorStr: String
            if let c = layer.color {
                colorStr = "\"rgba(\(Int(c.r * 255)),\(Int(c.g * 255)),\(Int(c.b * 255)),\(String(format: "%.2f", c.a)))\""
            } else {
                colorStr = "null"
            }
            json += "{\"t\":\(f1(layer.topMD)),\"b\":\(f1(layer.bottomMD)),\"r\":\(f1(layer.rho_kgpm3)),\"c\":\(colorStr)}"
        }
        json += "]"
        return json
    }

    private func generateTableRows(_ steps: [NumericalTripModel.TripStep]) -> String {
        var html = ""
        for step in steps {
            html += """
            <tr>
                <td>\(String(format: "%.0f", step.bitMD_m))</td>
                <td>\(String(format: "%.0f", step.bitTVD_m))</td>
                <td>\(String(format: "%.0f", step.SABP_kPa))</td>
                <td>\(String(format: "%.0f", step.SABP_Dynamic_kPa))</td>
                <td>\(String(format: "%.0f", step.ESDatTD_kgpm3))</td>
                <td>\(String(format: "%.3f", step.expectedFillIfClosed_m3))</td>
                <td>\(String(format: "%.3f", step.expectedFillIfOpen_m3))</td>
                <td>\(String(format: "%.3f", step.stepBackfill_m3))</td>
                <td>\(String(format: "%+.2f", step.cumulativeSurfaceTankDelta_m3))</td>
                <td>\(step.floatState)</td>
            </tr>
            """
        }
        return html
    }

    private func generateFinalSpottedFluidsSection(_ data: TripSimulationReportData) -> String {
        // Use final fluid layers from Mud Placement if available
        if !data.finalFluidLayers.isEmpty {
            return generateFinalSpottedFluidsFromMudPlacement(data)
        }

        // Fallback: Get the final step layers from simulation
        guard let finalStep = data.steps.last else {
            return ""
        }

        let stringLayers = finalStep.layersString
        let annulusLayers = finalStep.layersAnnulus

        func layerVolume(layer: NumericalTripModel.LayerRow, sections: [PDFSectionData]) -> (volume: Double, avgCapacity: Double) {
            var vol: Double = 0
            var totalLen: Double = 0
            for section in sections {
                let overlapTop = max(layer.topMD, section.topMD)
                let overlapBot = min(layer.bottomMD, section.bottomMD)
                if overlapBot > overlapTop {
                    let len = overlapBot - overlapTop
                    vol += len * section.capacity_m3_per_m
                    totalLen += len
                }
            }
            let avgCap = totalLen > 0 ? vol / totalLen : 0
            return (vol, avgCap)
        }

        func colorToCSS(_ color: NumericalTripModel.ColorRGBA?) -> String {
            guard let c = color else {
                return "#888888"
            }
            return String(format: "rgba(%.0f, %.0f, %.0f, %.2f)", c.r * 255, c.g * 255, c.b * 255, c.a)
        }

        func mudName(for layer: NumericalTripModel.LayerRow) -> String {
            // Try to match density to known muds
            let rho = layer.rho_kgpm3
            if abs(rho - data.baseMudDensity) < 5 {
                return data.baseMudName
            } else if abs(rho - data.backfillDensity) < 5 {
                return data.backfillMudName
            } else if data.slugMudVolume > 0 && abs(rho - data.slugMudDensity) < 5 {
                return data.slugMudName
            } else if rho < 50 {
                return "Air"
            }
            return String(format: "Mud (%.0f kg/m³)", rho)
        }

        var totalStringVolume: Double = 0
        var totalAnnulusVolume: Double = 0

        var stringHTML = ""
        for layer in stringLayers {
            let (vol, avgCap) = layerVolume(layer: layer, sections: data.drillStringSections)
            totalStringVolume += vol
            let name = mudName(for: layer)
            let colorCSS = colorToCSS(layer.color)
            stringHTML += """
            <div class="fluid-layer">
                <div class="fluid-swatch" style="background-color: \(colorCSS);"></div>
                <div class="fluid-info">
                    <div class="fluid-name">\(escapeHTML(name))</div>
                    <div class="fluid-details">\(String(format: "%.0f", layer.topMD))–\(String(format: "%.0f", layer.bottomMD)) m  •  ρ=\(String(format: "%.0f", layer.rho_kgpm3)) kg/m³</div>
                </div>
                <div class="fluid-metrics">
                    <div class="fluid-volume">\(String(format: "%.5f", vol)) m³</div>
                    <div class="fluid-capacity">\(String(format: "%.5f", avgCap)) m³/m</div>
                </div>
            </div>
            """
        }

        var annulusHTML = ""
        for layer in annulusLayers {
            let (vol, avgCap) = layerVolume(layer: layer, sections: data.annulusSections)
            totalAnnulusVolume += vol
            let name = mudName(for: layer)
            let colorCSS = colorToCSS(layer.color)
            annulusHTML += """
            <div class="fluid-layer">
                <div class="fluid-swatch" style="background-color: \(colorCSS);"></div>
                <div class="fluid-info">
                    <div class="fluid-name">\(escapeHTML(name))</div>
                    <div class="fluid-details">\(String(format: "%.0f", layer.topMD))–\(String(format: "%.0f", layer.bottomMD)) m  •  ρ=\(String(format: "%.0f", layer.rho_kgpm3)) kg/m³</div>
                </div>
                <div class="fluid-metrics">
                    <div class="fluid-volume">\(String(format: "%.5f", vol)) m³</div>
                    <div class="fluid-capacity">\(String(format: "%.5f", avgCap)) m³/m</div>
                </div>
            </div>
            """
        }

        return """
        <section class="card">
            <h2>Final Spotted Fluids</h2>
            <div class="fluids-grid">
                <div class="fluids-column">
                    <h3>String layers</h3>
                    \(stringHTML.isEmpty ? "<p class=\"no-data\">No string layers</p>" : stringHTML)
                    <div class="fluid-layer" style="background: var(--bg-color); border-radius: 4px; padding: 8px 0; margin-top: 8px;">
                        <div class="fluid-info">
                            <div class="fluid-name" style="color: var(--text-light);">Total String Volume</div>
                        </div>
                        <div class="fluid-metrics">
                            <div class="fluid-volume">\(String(format: "%.5f", totalStringVolume)) m³</div>
                        </div>
                    </div>
                </div>
                <div class="fluids-column">
                    <h3>Annulus layers</h3>
                    \(annulusHTML.isEmpty ? "<p class=\"no-data\">No annulus layers</p>" : annulusHTML)
                    <div class="fluid-layer" style="background: var(--bg-color); border-radius: 4px; padding: 8px 0; margin-top: 8px;">
                        <div class="fluid-info">
                            <div class="fluid-name" style="color: var(--text-light);">Total Annulus Volume</div>
                        </div>
                        <div class="fluid-metrics">
                            <div class="fluid-volume">\(String(format: "%.5f", totalAnnulusVolume)) m³</div>
                        </div>
                    </div>
                </div>
            </div>
        </section>
        """
    }

    private func generateFinalSpottedFluidsFromMudPlacement(_ data: TripSimulationReportData) -> String {
        // Separate string and annulus layers
        let stringLayers = data.finalFluidLayers.filter { $0.placement == .string || $0.placement == .both }
            .sorted { $0.topMD < $1.topMD }
        let annulusLayers = data.finalFluidLayers.filter { $0.placement == .annulus || $0.placement == .both }
            .sorted { $0.topMD < $1.topMD }

        func layerVolume(layer: FinalFluidLayerData, sections: [PDFSectionData]) -> (volume: Double, avgCapacity: Double) {
            var vol: Double = 0
            var totalLen: Double = 0
            let layerTop = min(layer.topMD, layer.bottomMD)
            let layerBottom = max(layer.topMD, layer.bottomMD)
            for section in sections {
                let overlapTop = max(layerTop, section.topMD)
                let overlapBot = min(layerBottom, section.bottomMD)
                if overlapBot > overlapTop {
                    let len = overlapBot - overlapTop
                    vol += len * section.capacity_m3_per_m
                    totalLen += len
                }
            }
            let avgCap = totalLen > 0 ? vol / totalLen : 0
            return (vol, avgCap)
        }

        func colorToCSS(_ layer: FinalFluidLayerData) -> String {
            return String(format: "rgba(%.0f, %.0f, %.0f, %.2f)",
                          layer.colorR * 255, layer.colorG * 255, layer.colorB * 255, layer.colorA)
        }

        var totalStringVolume: Double = 0
        var totalAnnulusVolume: Double = 0

        var stringHTML = ""
        for layer in stringLayers {
            let (vol, avgCap) = layerVolume(layer: layer, sections: data.drillStringSections)
            totalStringVolume += vol
            let colorCSS = colorToCSS(layer)
            let topMD = min(layer.topMD, layer.bottomMD)
            let bottomMD = max(layer.topMD, layer.bottomMD)
            stringHTML += """
            <div class="fluid-layer">
                <div class="fluid-swatch" style="background-color: \(colorCSS);"></div>
                <div class="fluid-info">
                    <div class="fluid-name">\(escapeHTML(layer.name))</div>
                    <div class="fluid-details">\(String(format: "%.0f", topMD))–\(String(format: "%.0f", bottomMD)) m  •  ρ=\(String(format: "%.0f", layer.density_kgm3)) kg/m³</div>
                </div>
                <div class="fluid-metrics">
                    <div class="fluid-volume">\(String(format: "%.5f", vol)) m³</div>
                    <div class="fluid-capacity">\(String(format: "%.5f", avgCap)) m³/m</div>
                </div>
            </div>
            """
        }

        var annulusHTML = ""
        for layer in annulusLayers {
            let (vol, avgCap) = layerVolume(layer: layer, sections: data.annulusSections)
            totalAnnulusVolume += vol
            let colorCSS = colorToCSS(layer)
            let topMD = min(layer.topMD, layer.bottomMD)
            let bottomMD = max(layer.topMD, layer.bottomMD)
            annulusHTML += """
            <div class="fluid-layer">
                <div class="fluid-swatch" style="background-color: \(colorCSS);"></div>
                <div class="fluid-info">
                    <div class="fluid-name">\(escapeHTML(layer.name))</div>
                    <div class="fluid-details">\(String(format: "%.0f", topMD))–\(String(format: "%.0f", bottomMD)) m  •  ρ=\(String(format: "%.0f", layer.density_kgm3)) kg/m³</div>
                </div>
                <div class="fluid-metrics">
                    <div class="fluid-volume">\(String(format: "%.5f", vol)) m³</div>
                    <div class="fluid-capacity">\(String(format: "%.5f", avgCap)) m³/m</div>
                </div>
            </div>
            """
        }

        return """
        <section class="card">
            <h2>Final Spotted Fluids</h2>
            <div class="fluids-grid">
                <div class="fluids-column">
                    <h3>String layers</h3>
                    \(stringHTML.isEmpty ? "<p class=\"no-data\">No string layers</p>" : stringHTML)
                    <div class="fluid-layer" style="background: var(--bg-color); border-radius: 4px; padding: 8px 0; margin-top: 8px;">
                        <div class="fluid-info">
                            <div class="fluid-name" style="color: var(--text-light);">Total String Volume</div>
                        </div>
                        <div class="fluid-metrics">
                            <div class="fluid-volume">\(String(format: "%.5f", totalStringVolume)) m³</div>
                        </div>
                    </div>
                </div>
                <div class="fluids-column">
                    <h3>Annulus layers</h3>
                    \(annulusHTML.isEmpty ? "<p class=\"no-data\">No annulus layers</p>" : annulusHTML)
                    <div class="fluid-layer" style="background: var(--bg-color); border-radius: 4px; padding: 8px 0; margin-top: 8px;">
                        <div class="fluid-info">
                            <div class="fluid-name" style="color: var(--text-light);">Total Annulus Volume</div>
                        </div>
                        <div class="fluid-metrics">
                            <div class="fluid-volume">\(String(format: "%.5f", totalAnnulusVolume)) m³</div>
                        </div>
                    </div>
                </div>
            </div>
        </section>
        """
    }

    private func generateFluidsTable(_ data: TripSimulationReportData) -> String {
        var html = """
        <table class="geometry-table fluids-table">
            <thead>
                <tr>
                    <th>Mud</th>
                    <th>Density (kg/m³)</th>
                    <th>Volume (m³)</th>
                    <th>Purpose</th>
                </tr>
            </thead>
            <tbody>
        """

        // Slug mud (if present) - heaviest mud in string at start
        if data.slugMudVolume > 0.01 {
            html += """
            <tr>
                <td>\(escapeHTML(data.slugMudName))</td>
                <td>\(String(format: "%.0f", data.slugMudDensity))</td>
                <td>\(String(format: "%.2f", data.slugMudVolume))</td>
                <td>Slug (in string at start)</td>
            </tr>
            """
        }

        if data.switchToActiveAfterDisplacement {
            // Two muds used for backfill - backfill first, then active
            html += """
            <tr>
                <td>\(escapeHTML(data.backfillMudName))</td>
                <td>\(String(format: "%.0f", data.backfillDensity))</td>
                <td>\(String(format: "%.2f", data.backfillMudVolume))</td>
                <td>Backfill (displacement)</td>
            </tr>
            <tr>
                <td>\(escapeHTML(data.baseMudName))</td>
                <td>\(String(format: "%.0f", data.baseMudDensity))</td>
                <td>\(String(format: "%.2f", data.activeMudBackfillVolume))</td>
                <td>Backfill (after switch)</td>
            </tr>
            <tr class="total-row">
                <td>TOTAL BACKFILL</td>
                <td></td>
                <td>\(String(format: "%.2f", data.totalBackfill))</td>
                <td></td>
            </tr>
            """
        } else {
            // Single backfill mud used
            html += """
            <tr>
                <td>\(escapeHTML(data.backfillMudName))</td>
                <td>\(String(format: "%.0f", data.backfillDensity))</td>
                <td>\(String(format: "%.2f", data.totalBackfill))</td>
                <td>Backfill</td>
            </tr>
            """
        }

        html += """
            </tbody>
        </table>
        """

        if data.switchToActiveAfterDisplacement {
            html += """
            <div class="volume-summary">
                <h4>Backfill Strategy</h4>
                <div class="summary-row">
                    <span>Switch Volume:</span>
                    <span>\(String(format: "%.2f m³", data.displacementSwitchVolume))</span>
                </div>
                <div class="summary-row">
                    <span>Method:</span>
                    <span>Backfill then Active</span>
                </div>
            </div>
            """
        }

        return html
    }

    private func generateDrillStringTable(_ sections: [PDFSectionData], totalCapacity: Double, totalDisplacement: Double) -> String {
        guard !sections.isEmpty else {
            return "<p>No drill string sections defined</p>"
        }

        var html = """
        <table class="geometry-table">
            <thead>
                <tr>
                    <th>Section</th>
                    <th>Top (m)</th>
                    <th>Bot (m)</th>
                    <th>OD (mm)</th>
                    <th>ID (mm)</th>
                    <th>Cap (m³/m)</th>
                    <th>Disp (m³/m)</th>
                    <th>Vol (m³)</th>
                </tr>
            </thead>
            <tbody>
        """

        for section in sections {
            html += """
            <tr>
                <td>\(escapeHTML(section.name))</td>
                <td>\(String(format: "%.0f", section.topMD))</td>
                <td>\(String(format: "%.0f", section.bottomMD))</td>
                <td>\(String(format: "%.1f", section.outerDiameter * 1000))</td>
                <td>\(String(format: "%.1f", section.innerDiameter * 1000))</td>
                <td>\(String(format: "%.4f", section.capacity_m3_per_m))</td>
                <td>\(String(format: "%.4f", section.displacement_m3_per_m))</td>
                <td>\(String(format: "%.2f", section.totalVolume))</td>
            </tr>
            """
        }

        // Calculate total displacement
        let totalDisp = sections.reduce(0.0) { $0 + $1.displacement_m3_per_m * $1.length }

        html += """
            <tr class="total-row">
                <td>TOTAL</td>
                <td colspan="4"></td>
                <td>\(String(format: "%.4f", sections.reduce(0.0) { $0 + $1.capacity_m3_per_m * $1.length } / max(1, sections.reduce(0.0) { $0 + $1.length })))</td>
                <td>\(String(format: "%.4f", totalDisp / max(1, sections.reduce(0.0) { $0 + $1.length })))</td>
                <td>\(String(format: "%.2f", totalCapacity))</td>
            </tr>
            <tr class="total-row">
                <td>DISPLACEMENT</td>
                <td colspan="6"></td>
                <td>\(String(format: "%.2f", totalDisplacement))</td>
            </tr>
            </tbody>
        </table>
        """

        return html
    }

    private func generateAnnulusTable(_ sections: [PDFSectionData], totalCapacity: Double) -> String {
        guard !sections.isEmpty else {
            return "<p>No annulus sections defined</p>"
        }

        var html = """
        <table class="geometry-table">
            <thead>
                <tr>
                    <th>Section</th>
                    <th>Top (m)</th>
                    <th>Bot (m)</th>
                    <th>Hole ID (mm)</th>
                    <th>Pipe OD (mm)</th>
                    <th>Cap (m³/m)</th>
                    <th>Vol (m³)</th>
                </tr>
            </thead>
            <tbody>
        """

        for section in sections {
            html += """
            <tr>
                <td>\(escapeHTML(section.name))</td>
                <td>\(String(format: "%.0f", section.topMD))</td>
                <td>\(String(format: "%.0f", section.bottomMD))</td>
                <td>\(String(format: "%.1f", section.innerDiameter * 1000))</td>
                <td>\(String(format: "%.1f", section.outerDiameter * 1000))</td>
                <td>\(String(format: "%.4f", section.capacity_m3_per_m))</td>
                <td>\(String(format: "%.2f", section.totalVolume))</td>
            </tr>
            """
        }

        html += """
            <tr class="total-row">
                <td>TOTAL</td>
                <td colspan="5"></td>
                <td>\(String(format: "%.2f", totalCapacity))</td>
            </tr>
            </tbody>
        </table>
        """

        return html
    }
}
